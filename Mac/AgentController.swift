import AppKit
import ApplicationServices
import WhisperCore

@MainActor
final class AgentController: ObservableObject {
    enum Target: String, CaseIterable, Identifiable {
        case codex = "Codex", claude = "Claude"
        var id: String { rawValue }
        var bundleID: String { self == .codex ? "com.openai.codex" : "com.anthropic.claudefordesktop" }
    }
    @Published var target: Target = .codex
    @Published var phase: HostPhase = .ready
    @Published var detail = "将 Codex 的任务窗口放在前台，然后用手表操作。"
    private var recordingWindow: AXUIElement?
    private var recordingPID: pid_t?
    private var stopControl: AXUIElement?
    private var recordingTitle: String?
    private var pendingTranscription = false
    private var recordingConfirmed = false
    private var busy = false
    private var pendingStop: RemoteAction?
    private var lease = RecordingLease()
    private var leaseTask: Task<Void, Never>?
    private let demo: Bool

    init(demo: Bool = false) {
        self.demo = demo
        if demo { detail = "演示模式：不会操作任何其他应用。" }
        leaseTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self else { return }
                if self.lease.expired(at: ProcessInfo.processInfo.systemUptime) {
                    // Never turn a recording on while recovering from disconnect.
                    _ = await self.perform(.cancelDictation)
                    self.detail = "手表连接中断或录音已达 2 分钟，已请求取消听写。"
                }
            }
        }
    }

    var accessibilityGranted: Bool { demo || AXIsProcessTrusted() }
    var isRecording: Bool { recordingWindow != nil || (demo && phase == .listening) }

    func requestAccessibility() {
        // Only a user click calls this. The OS permission remains a user decision.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func perform(_ action: RemoteAction, value: Int16 = 0) async -> HostPhase {
        if busy {
            if action == .finishDictation || action == .cancelDictation { pendingStop = action }
            return phase
        }
        if action == .heartbeat {
            if recordingConfirmed || demo { lease.renew(at: ProcessInfo.processInfo.systemUptime) }
            if !demo { refresh() }
            return phase
        }
        if demo {
            switch action {
            case .beginDictation: phase = .listening; lease.begin(at: ProcessInfo.processInfo.systemUptime)
            case .finishDictation, .cancelDictation: phase = .ready; lease.finish()
            default: break
            }
            return phase
        }
        busy = true
        defer { busy = false }
        if recordingConfirmed { lease.renew(at: ProcessInfo.processInfo.systemUptime) }
        do {
            guard accessibilityGranted else { throw Failure(.permissionRequired, "在系统设置 → 隐私与安全性 → 辅助功能中允许 Watch Whisper。") }
            switch action {
            case .heartbeat: break
            case .beginDictation: try await begin()
            case .finishDictation: try await finish(cancel: false)
            case .cancelDictation: try await finish(cancel: true)
            case .enter: try enter()
            case .scroll: try scroll(value)
            }
        } catch let error as Failure {
            phase = error.phase; detail = error.message
        } catch {
            phase = .failed; detail = error.localizedDescription
        }
        if let stop = pendingStop {
            pendingStop = nil
            do { try await finish(cancel: stop == .cancelDictation) }
            catch { phase = .failed; detail = "连接中断后无法确认停止，请在 Codex 检查录音。" }
        }
        return phase
    }

    private func begin() async throws {
        guard target == .codex else { throw Failure(.unavailable, "Claude 听写尚未适配。请使用 Codex，Claude 目前仅支持滚动和 Enter。") }
        if recordingWindow != nil { refresh(); return }
        let (app, window) = try frontWindow()
        let elements = descendants(window)
        guard buttons(elements, matching: AgentLabels.stop.union(AgentLabels.transcribing).union(AgentLabels.starting)).isEmpty else {
            throw Failure(.unavailable, "目标已有听写或转写，请先在 Mac 完成。")
        }
        let controls = buttons(elements, matching: AgentLabels.dictate)
        guard controls.count == 1 else { throw Failure(.unavailable, "没有找到唯一的 Codex 听写按钮。请显示任务输入框，使用中／英文界面。") }
        recordingWindow = window; recordingPID = app.processIdentifier
        recordingTitle = string(window, kAXTitleAttribute)
        lease.begin(at: ProcessInfo.processInfo.systemUptime)
        do { try press(controls[0]) } catch { clearRecording(); throw error }
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 100_000_000)
            let stops = buttons(descendants(window), matching: AgentLabels.stop)
            if stops.count == 1 {
                stopControl = stops[0]; phase = .listening; recordingConfirmed = true
                detail = "Codex 正在通过 Mac 当前选择的麦克风收音。"
                return
            }
        }
        // Keep the lease alive so a late start is also cancelled by the watchdog.
        throw Failure(.failed, "听写启动未获界面确认。请查看 Codex 的麦克风权限；手表不会自动重试。")
    }

    private func finish(cancel: Bool) async throws {
        guard let window = recordingWindow else { return }
        guard string(window, kAXTitleAttribute) == recordingTitle else {
            lease.finish()
            throw Failure(.failed, "任务窗口已切换，无法确认原录音。请在 Codex 手动停止。")
        }
        let elements = descendants(window)
        var candidates = buttons(elements, matching: cancel ? AgentLabels.cancel : AgentLabels.stop)
        // Stop is safe if cancellation is absent: it inserts text but never presses send.
        if cancel && candidates.isEmpty { candidates = buttons(elements, matching: AgentLabels.stop) }
        if candidates.isEmpty, let stopControl, !cancel { candidates = [stopControl] }
        guard candidates.count == 1 else {
            if buttons(elements, matching: AgentLabels.dictate).count == 1 {
                clearRecording(); phase = .ready; return
            }
            lease.finish()
            throw Failure(.failed, "未找到原录音的停止控件，请在 Codex 停止听写。")
        }
        try press(candidates[0])
        lease.finish(); stopControl = nil
        // Preserve the exact window through the asynchronous transcription period.
        pendingTranscription = true; phase = .transcribing
        detail = cancel ? "已请求取消听写，不会发送消息。" : "已停止收音，等待 Codex 转写；检查文字后在手表点 Enter。"
        try await Task.sleep(nanoseconds: 150_000_000)
        refresh()
    }

    private func refresh() {
        guard accessibilityGranted else { phase = .permissionRequired; return }
        if let window = recordingWindow {
            guard string(window, kAXTitleAttribute) == recordingTitle else {
                phase = .failed; detail = "原任务已切换，请在 Mac 检查听写状态。"; return
            }
            let elements = descendants(window)
            if !buttons(elements, matching: AgentLabels.stop).isEmpty { phase = .listening; return }
            if !buttons(elements, matching: AgentLabels.transcribing.union(AgentLabels.starting)).isEmpty {
                phase = .transcribing; return
            }
            if buttons(elements, matching: AgentLabels.dictate).count == 1 {
                clearRecording(); phase = .ready; detail = "请检查 Codex 输入框里的文字，再点 Enter。"
            } else if pendingTranscription { phase = .transcribing }
            return
        }
        do { _ = try frontWindow(); phase = .ready }
        catch let failure as Failure { phase = failure.phase }
        catch { phase = .failed }
    }

    private func enter() throws {
        guard recordingWindow == nil else { throw Failure(.transcribing, "请先停止听写，等转写完成后再点 Enter。") }
        let (app, window) = try frontWindow()
        let elements = descendants(window)
        guard buttons(elements, matching: AgentLabels.stop.union(AgentLabels.transcribing).union(AgentLabels.starting)).isEmpty else {
            throw Failure(.transcribing, "Codex 还在收音或转写，请稍后发送。")
        }
        let editor = try composer(elements)
        let value = string(editor, kAXValueAttribute).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw Failure(.unavailable, "输入框是空的，不发送 Enter。") }
        guard AXUIElementSetAttributeValue(editor, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else {
            throw Failure(.unavailable, "无法聚焦任务输入框。")
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            throw Failure(.targetInactive, "目标应用不在前台。")
        }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false) else {
            throw Failure(.failed, "无法创建 Enter 事件。")
        }
        down.postToPid(app.processIdentifier); up.postToPid(app.processIdentifier)
        phase = .ready; detail = "已向目标输入框发送 Enter。请以 Codex 实际任务状态为准。"
    }

    private func scroll(_ pixels: Int16) throws {
        let (app, window) = try frontWindow()
        guard let windowRect = rect(window) else { throw Failure(.unavailable, "无法定位任务窗口。") }
        let elements = descendants(window)
        let editor = try composer(elements)
        guard let editorRect = rect(editor) else { throw Failure(.unavailable, "无法定位任务输入框。") }
        // Use the conversation's horizontal position, never the pointer's current position.
        let x = editorRect.midX
        let candidates = elements.filter { string($0, kAXRoleAttribute) == kAXScrollAreaRole }
            .compactMap { element -> CGRect? in
                guard let r = rect(element), r.width > 200, r.height > 100,
                      x >= r.minX, x <= r.maxX, r.maxY <= editorRect.maxY,
                      r.intersects(windowRect) else { return nil }
                return r.intersection(windowRect)
            }
        let area = candidates.max { $0.width * $0.height < $1.width * $1.height }
        let point = CGPoint(x: x, y: area?.midY ?? windowRect.minY + windowRect.height * 0.42)
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                  wheel1: -Int32(pixels), wheel2: 0, wheel3: 0) else {
            throw Failure(.failed, "无法创建滚动事件。")
        }
        event.location = point; event.postToPid(app.processIdentifier)
        detail = pixels >= 0 ? "向下浏览" : "向上浏览"
    }

    private func frontWindow() throws -> (NSRunningApplication, AXUIElement) {
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == target.bundleID else {
            throw Failure(.targetInactive, "请把 \(target.rawValue) 的任务窗口放在前台。不会把按键发给其他应用。")
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw Failure(.unavailable, "没有可用的任务窗口。")
        }
        return (app, unsafeBitCast(value, to: AXUIElement.self))
    }
    private func composer(_ elements: [AXUIElement]) throws -> AXUIElement {
        let editors = elements.filter {
            string($0, kAXRoleAttribute) == kAXTextAreaRole && rect($0).map { $0.width > 150 && $0.height > 15 } == true
        }
        guard editors.count == 1 else {
            throw Failure(.unavailable, "无法唯一识别任务输入框。请关闭搜索框、终端或其他编辑面板后重试。")
        }
        return editors[0]
    }
    private func clearRecording() {
        lease.finish(); recordingWindow = nil; recordingPID = nil; recordingTitle = nil
        stopControl = nil; pendingTranscription = false
        recordingConfirmed = false
    }
    private func descendants(_ root: AXUIElement) -> [AXUIElement] {
        var queue = [root]; var output: [AXUIElement] = []; var index = 0
        while index < queue.count && index < 2500 {
            let element = queue[index]; index += 1; output.append(element)
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
               let children = value as? [AXUIElement] { queue.append(contentsOf: children) }
        }
        return output
    }
    private func string(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return value as? String ?? ""
    }
    private func buttons(_ elements: [AXUIElement], matching labels: Set<String>) -> [AXUIElement] {
        elements.filter { element in
            guard string(element, kAXRoleAttribute) == kAXButtonRole else { return false }
            return [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].contains { labels.contains(string(element, $0)) }
        }
    }
    private func press(_ element: AXUIElement) throws {
        guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
            throw Failure(.failed, "目标控件没有接受操作。")
        }
    }
    private func rect(_ element: AXUIElement) -> CGRect? {
        var p: CFTypeRef?; var s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &s) == .success,
              let p, let s, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
    private struct Failure: Error { let phase: HostPhase; let message: String
        init(_ phase: HostPhase, _ message: String) { self.phase = phase; self.message = message }
    }
}
