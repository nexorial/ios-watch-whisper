import AppKit
import ApplicationServices
import MicodexCore

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
    @Published var lastOperation = ""
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
    private var accessibilityPreparedPID: pid_t?
    var drainBeforePreserving: (() async -> Void)?
    private var stopDeadline: TimeInterval?
    private struct ScrollAnchor {
        let pid: pid_t; let window: AXUIElement; let frame: CGRect; let title: String
        let editor: AXUIElement?; let editorFrame: CGRect?; let point: CGPoint; let created: TimeInterval
    }
    private var scrollAnchor: ScrollAnchor?
    private var scrollMotion = ScrollMotion()
    private var scrollTask: Task<Void, Never>?
    private var scrollEpoch = UUID()
    private var scrollReportedAt: TimeInterval = 0

    init(demo: Bool = false) {
        self.demo = demo
        if demo { detail = "演示模式：不会操作任何其他应用。" }
        leaseTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self else { return }
                if let deadline = self.stopDeadline, ProcessInfo.processInfo.systemUptime >= deadline {
                    self.stopDeadline = nil; self.lease.finish()
                    self.phase = .failed; self.detail = "已停止 Watch 收音；Codex 尚未确认结束，请在 Mac 完成转写。"
                }
                if self.lease.expired(at: ProcessInfo.processInfo.systemUptime) {
                    self.lease.finish()
                    _ = await self.perform(.finishReceivedAudio)
                    self.detail = "手表连接中断或录音已达 2 分钟，已请求保留收到的内容进行转写。"
                }
            }
        }
    }

    var accessibilityGranted: Bool { demo || AXIsProcessTrusted() }
    var isRecording: Bool { recordingWindow != nil || (demo && phase == .listening) }
    var isFinishing: Bool { pendingTranscription }
    var isBusy: Bool { busy }

    func requestAccessibility() {
        // Only a user click calls this. The OS permission remains a user decision.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func perform(_ action: RemoteAction, value: Int16 = 0) async -> HostPhase {
        if busy {
            if [.finishDictation, .cancelDictation, .finishReceivedAudio].contains(action) { pendingStop = action }
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
            case .finishDictation, .cancelDictation, .finishReceivedAudio: phase = .ready; lease.finish()
            default: break
            }
            return phase
        }
        busy = true
        defer { busy = false }
        if action != .scroll { stopScrolling() }
        if recordingConfirmed { lease.renew(at: ProcessInfo.processInfo.systemUptime) }
        do {
            guard accessibilityGranted else { throw Failure(.permissionRequired, "在系统设置 → 隐私与安全性 → 辅助功能中允许 Micodex。") }
            switch action {
            case .heartbeat: break
            case .beginDictation: try await begin()
            case .finishDictation: try await finish(cancel: false)
            case .finishReceivedAudio: await drainBeforePreserving?(); try await finish(cancel: false)
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
            if stop == .finishReceivedAudio { await drainBeforePreserving?() }
            do { try await finish(cancel: stop == .cancelDictation) }
            catch { phase = .failed; detail = "连接中断后无法确认停止，请在 Codex 检查录音。" }
        }
        if action != .scroll {
            lastOperation = "\(action) · \(phase.caption) · \(detail)"
            ConnectionTrace.record("control", "\(action) phase=\(phase) detail=\(detail)")
        }
        return phase
    }

    private func begin() async throws {
        guard target == .codex else { throw Failure(.unavailable, "Claude 听写尚未适配。请使用 Codex，Claude 目前仅支持滚动和 Enter。") }
        guard !pendingTranscription else { throw Failure(.transcribing, "正在确认上一次听写已停止，请稍后再开始。") }
        if recordingWindow != nil { refresh(); return }
        let (app, window) = try await activateTargetWindow()
        let elements = descendants(window)
        guard buttons(elements, matching: ["Retry dictation", "重试听写"]).isEmpty else {
            throw Failure(.failed, "Codex 上一次转写失败，请先在 Mac 重试听写或清除错误，再开始新录音。")
        }
        let editor = try composer(elements, in: window)
        guard AXUIElementSetAttributeValue(editor, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else {
            throw Failure(.unavailable, "无法聚焦 Codex 任务输入框。")
        }
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
                detail = "Watch 麦克风经 BlackHole 送入 Codex 听写。"
                return
            }
        }
        // Keep the lease alive so a late start is also cancelled by the watchdog.
        throw Failure(.failed, "听写启动未获界面确认。请查看 Codex 的麦克风权限；手表不会自动重试。")
    }

    private func finish(cancel: Bool) async throws {
        guard let window = recordingWindow else { return }
        if pendingTranscription && !cancel { refresh(); return }
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
        // Preserve the exact window through the asynchronous transcription period.
        pendingTranscription = true; phase = .transcribing; recordingConfirmed = false
        lease.finish(); stopDeadline = ProcessInfo.processInfo.systemUptime + 5
        detail = cancel ? "正在取消听写，不会发送消息。" : "正在结束 Codex 收音…"
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 100_000_000)
            let current = descendants(window)
            let finishedLabels = AgentLabels.dictate.union(AgentLabels.transcribing).union(["Retry dictation", "重试听写"])
            if buttons(current, matching: AgentLabels.stop.union(AgentLabels.starting)).isEmpty,
               !buttons(current, matching: finishedLabels).isEmpty {
                lease.finish(); stopControl = nil; stopDeadline = nil
                detail = cancel ? "已取消听写，不会发送消息。" : "已停止收音，等待 Codex 转写；检查文字后在手表点 Enter。"
                refresh(); return
            }
        }
        // Keep the existing watchdog for an unconfirmed finish; a failed cancel
        // itself must not loop forever. Never retry by pressing a start button.
        if cancel {
            lease.finish(); stopDeadline = nil
            throw Failure(.failed, "已请求取消，但 Codex 仍显示录音。请在 Codex 手动停止。")
        }
        // Codex drains its microphone asynchronously. Keep the bounded watchdog,
        // but don't report a failed stop merely because its UI takes over 1 s.
        detail = "Watch 收音已停止，等待 Codex 完成尾音处理与转写。"
    }

    private func refresh() {
        guard accessibilityGranted else { phase = .permissionRequired; return }
        if let window = recordingWindow {
            guard string(window, kAXTitleAttribute) == recordingTitle else {
                phase = .failed; detail = "原任务已切换，请在 Mac 检查听写状态。"; return
            }
            let elements = descendants(window)
            if !buttons(elements, matching: ["Retry dictation", "重试听写"]).isEmpty {
                clearRecording(); phase = .failed
                detail = "Codex 显示重试听写，本次未确认生成文字。请在 Mac 重试或清除错误。"
                return
            }
            if !buttons(elements, matching: AgentLabels.stop).isEmpty {
                if phase != .failed { phase = pendingTranscription ? .transcribing : .listening }
                return
            }
            if !buttons(elements, matching: AgentLabels.transcribing).isEmpty {
                if pendingTranscription { lease.finish(); stopControl = nil; stopDeadline = nil }
                phase = .transcribing; return
            }
            if !buttons(elements, matching: AgentLabels.starting).isEmpty {
                phase = .transcribing; return
            }
            if buttons(elements, matching: AgentLabels.dictate).count == 1 {
                clearRecording(); phase = .ready; detail = "请检查 Codex 输入框里的文字，再点 Enter。"
            } else if pendingTranscription { phase = .transcribing }
            return
        }
        if phase == .failed || phase == .unavailable { return }
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
        let editor = try composer(elements, in: window)
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
        let started = ProcessInfo.processInfo.systemUptime
        let (app, window) = try frontWindow()
        guard let frame = rect(window) else { throw Failure(.unavailable, "无法定位任务窗口。") }
        let title = string(window, kAXTitleAttribute)
        let cached = scrollAnchor.map { anchor in
            anchor.pid == app.processIdentifier && CFEqual(anchor.window, window)
                && anchor.frame == frame && anchor.title == title
                && started - anchor.created < (anchor.editor == nil ? 0.25 : 3)
                && (anchor.editor == nil || anchor.editor.flatMap { rect($0) } == anchor.editorFrame)
        } ?? false
        if !cached {
            let elements = descendants(window)
            let editor = try? composer(elements, in: window)
            let editorFrame = editor.flatMap { rect($0) }
            let areas = elements.filter { string($0, kAXRoleAttribute) == kAXScrollAreaRole }.compactMap { element -> CGRect? in
                guard let r = rect(element), r.width > 240, r.height > 120, r.intersects(frame) else { return nil }
                let visible = r.intersection(frame)
                if let editorFrame {
                    guard visible.contains(CGPoint(x: editorFrame.midX, y: visible.midY)), visible.minY < editorFrame.minY - 60 else { return nil }
                }
                return visible
            }
            let area = areas.max { $0.width * $0.height < $1.width * $1.height }
            let point = CGPoint(x: editorFrame?.midX ?? area?.midX ?? frame.midX,
                                y: area.map { min($0.midY, editorFrame.map { $0.minY - 40 } ?? $0.midY) } ?? frame.minY + frame.height * 0.4)
            scrollAnchor = ScrollAnchor(pid: app.processIdentifier, window: window, frame: frame, title: title,
                                        editor: editor, editorFrame: editorFrame, point: point, created: started)
            ConnectionTrace.record("scroll", String(format: "target resolved in %.1f ms", (ProcessInfo.processInfo.systemUptime - started) * 1000))
        }
        scrollMotion.add(Int(pixels))
        if scrollTask == nil {
            let token = UUID(); scrollEpoch = token
            scrollTask = Task { [weak self] in
                guard let self else { return }
                defer { if self.scrollEpoch == token { self.scrollTask = nil } }
                var frames = 0, totalMS = 0.0
                while !Task.isCancelled, self.scrollEpoch == token, self.scrollMotion.pending != 0 {
                    let tick = ProcessInfo.processInfo.systemUptime
                    do { try self.emitScrollFrame(self.scrollMotion.next()); frames += 1 }
                    catch {
                        self.scrollMotion.reset(); self.scrollAnchor = nil
                        self.phase = .targetInactive; self.detail = "滚动目标已变化，已停止滚动。"; break
                    }
                    totalMS += (ProcessInfo.processInfo.systemUptime - tick) * 1000
                    try? await Task.sleep(nanoseconds: 16_666_667)
                }
                if frames > 0, ProcessInfo.processInfo.systemUptime - self.scrollReportedAt >= 1 {
                    self.scrollReportedAt = ProcessInfo.processInfo.systemUptime
                    ConnectionTrace.record("scroll", String(format: "burst frames=%d mean-frame-work=%.2f ms", frames, totalMS / Double(frames)))
                }
            }
        }
        if !isRecording { phase = .ready }
        let message = pixels >= 0 ? "向下浏览 Codex 对话正文" : "向上浏览 Codex 对话正文"
        if detail != message { detail = message }
    }
    func stopScrolling() {
        scrollEpoch = UUID()
        scrollTask?.cancel(); scrollTask = nil; scrollMotion.reset(); scrollAnchor = nil
    }
    private func emitScrollFrame(_ pixels: Int16) throws {
        guard let anchor = scrollAnchor, NSWorkspace.shared.frontmostApplication?.processIdentifier == anchor.pid,
              rect(anchor.window) == anchor.frame,
              anchor.editor == nil || anchor.editor.flatMap({ rect($0) }) == anchor.editorFrame else { throw Failure(.targetInactive, "目标窗口已变化。") }
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(anchor.pid), kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused, CFEqual(focused, anchor.window) else { throw Failure(.targetInactive, "任务窗口已切换。") }
        var hit: AXUIElement?, hitPID: pid_t = 0
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(anchor.point.x), Float(anchor.point.y), &hit) == .success,
              let hit, AXUIElementGetPid(hit, &hitPID) == .success, hitPID == anchor.pid else { throw Failure(.targetInactive, "正文位置已被遮挡。") }
        guard let event = CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState), units: .pixel,
                                  wheelCount: 1, wheel1: -Int32(pixels), wheel2: 0, wheel3: 0) else { throw Failure(.failed, "无法创建滚动事件。") }
        event.location = anchor.point; event.post(tap: .cghidEventTap)
    }

    private func activateTargetWindow() async throws -> (NSRunningApplication, AXUIElement) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).first else {
            throw Failure(.targetInactive, "请先打开 \(target.rawValue) 的任务。")
        }
        app.activate(options: [.activateIgnoringOtherApps])
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 80_000_000)
            if let result = try? frontWindow(), (try? composer(descendants(result.1), in: result.1)) != nil { return result }
        }
        return try frontWindow()
    }

    private func frontWindow() throws -> (NSRunningApplication, AXUIElement) {
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == target.bundleID else {
            throw Failure(.targetInactive, "请把 \(target.rawValue) 的任务窗口放在前台。不会把按键发给其他应用。")
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        if accessibilityPreparedPID != app.processIdentifier {
            // Chromium only creates its complete web accessibility tree when an
            // assistive client requests it. This uses the user's existing AX grant.
            _ = AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            accessibilityPreparedPID = app.processIdentifier
        }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw Failure(.unavailable, "没有可用的任务窗口。")
        }
        return (app, unsafeBitCast(value, to: AXUIElement.self))
    }
    private func composer(_ elements: [AXUIElement], in window: AXUIElement) throws -> AXUIElement {
        guard let windowRect = rect(window) else { throw Failure(.unavailable, "无法定位任务窗口。") }
        let candidates = elements.enumerated().compactMap { index, element -> ComposerSelection.Candidate? in
            let role = string(element, kAXRoleAttribute)
            guard [kAXTextAreaRole, kAXTextFieldRole].contains(role), let frame = rect(element) else { return nil }
            var value: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(element, "AXDOMClassList" as CFString, &value)
            let classes = value as? [String] ?? []
            return .init(index: index, frame: frame, proseMirror: classes.contains("ProseMirror"), multiline: role == kAXTextAreaRole)
        }
        if let index = ComposerSelection.select(candidates, window: windowRect,
                                                 dictateButtons: buttons(elements, matching: AgentLabels.dictate).compactMap { rect($0) }) {
            return elements[index]
        }
        throw Failure(.unavailable, "尚未定位任务输入框。请保持 Codex 任务页面可见；搜索框或多个编辑面板可能造成歧义。")
    }
    private func clearRecording() {
        stopDeadline = nil; drainBeforePreserving = nil
        lease.finish(); recordingWindow = nil; recordingPID = nil; recordingTitle = nil
        stopControl = nil; pendingTranscription = false
        recordingConfirmed = false
    }
    private func descendants(_ root: AXUIElement) -> [AXUIElement] {
        var queue = [root]; var output: [AXUIElement] = []
        // Visit the last children first: the composer comes after the transcript.
        // Do not spend the traversal budget on every character in long messages.
        while let element = queue.popLast(), output.count < 6000 {
            output.append(element)
            if [kAXStaticTextRole, kAXTextAreaRole, kAXButtonRole].contains(string(element, kAXRoleAttribute)) { continue }
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
