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
    @Published var detailMessage: LocalizedMessage = L10n.message("Bring a Codex task window to the front, then use your Watch.")
    var detail: String { detailMessage.localizedString }
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
    private var titleUpdatedAt: TimeInterval = 0
    private var titleTarget: Target?
    private var cachedThreadTitle: String?
    var drainBeforePreserving: (() async -> Void)?
    private var stopDeadline: TimeInterval?
    private struct ScrollAnchor {
        let pid: pid_t; let window: AXUIElement; let frame: CGRect; let title: String
        let editor: AXUIElement?; let editorFrame: CGRect?; let point: CGPoint; let created: TimeInterval
        let area: AXUIElement?; let areaFrame: CGRect?
    }
    private var scrollAnchor: ScrollAnchor?
    private var scrollMotion = ScrollMotion()
    private var scrollTask: Task<Void, Never>?
    private var scrollEpoch = UUID()
    private var scrollReportedAt: TimeInterval = 0

    init(demo: Bool = false) {
        self.demo = demo
        if demo {
            detailMessage = L10n.message("Demo mode: other apps will not be controlled.")
            lastOperation = detailMessage.localizedString
        }
        leaseTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self else { return }
                if let deadline = self.stopDeadline, ProcessInfo.processInfo.systemUptime >= deadline {
                    self.stopDeadline = nil; self.lease.finish()
                    self.phase = .failed; self.detailMessage = L10n.message("Watch recording has stopped. Codex has not confirmed completion; finish transcription on your Mac.")
                }
                if self.lease.expired(at: ProcessInfo.processInfo.systemUptime) {
                    self.lease.finish()
                    _ = await self.perform(.finishReceivedAudio)
                    self.detailMessage = L10n.message("The Watch disconnected or reached the 2-minute recording limit. Received audio has been kept for transcription.")
                }
            }
        }
    }

    var accessibilityGranted: Bool { demo || AXIsProcessTrusted() }
    var isRecording: Bool { recordingWindow != nil || (demo && phase == .listening) }
    var isFinishing: Bool { pendingTranscription }
    var isBusy: Bool { busy }

    func focusedThreadTitle() -> String? {
        if demo { return L10n.t("Demo thread") }
        // Scroll commands arrive much faster than status heartbeats. Never walk
        // the full accessibility tree for every Crown increment.
        let now = ProcessInfo.processInfo.systemUptime
        if titleTarget == target, now - titleUpdatedAt < 0.8 { return cachedThreadTitle }
        titleTarget = target; titleUpdatedAt = now
        cachedThreadTitle = readFocusedThreadTitle()
        return cachedThreadTitle
    }

    private func readFocusedThreadTitle() -> String? {
        guard accessibilityGranted,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).first else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        prepareAccessibility(root, pid: app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let window = unsafeBitCast(value, to: AXUIElement.self)
        let elements = descendants(window)
        // Only report a task with a usable composer, not Settings or a search window.
        guard (try? composer(elements, in: window)) != nil else { return nil }
        if let title = ThreadTitle.clean(string(window, kAXTitleAttribute), application: target.rawValue) { return title }
        guard let frame = rect(window) else { return nil }
        // Electron can leave the window title at its app name. In that case use
        // an unambiguous heading in the top content header, never sidebar rows
        // or transcript headings. Missing/ambiguous titles deliberately stay nil.
        let headings = elements.filter {
            guard string($0, kAXRoleAttribute) == "AXHeading", let rect = rect($0) else { return false }
            return rect.minX > frame.minX + 140 && rect.minY >= frame.minY && rect.maxY < frame.minY + 110
        }
        let titles = Set(headings.compactMap { heading -> String? in
            let parts = [string(heading, kAXTitleAttribute), string(heading, kAXValueAttribute)]
                + descendants(heading).filter { string($0, kAXRoleAttribute) == kAXStaticTextRole }.map { string($0, kAXValueAttribute) }
            return parts.compactMap { ThreadTitle.clean($0, application: target.rawValue) }.first
        })
        return titles.count == 1 ? titles.first : nil
    }

    private func prepareAccessibility(_ root: AXUIElement, pid: pid_t) {
        guard accessibilityPreparedPID != pid else { return }
        _ = AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        accessibilityPreparedPID = pid
    }

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
            guard accessibilityGranted else { throw Failure(.permissionRequired, L10n.message("Allow Micodex in System Settings → Privacy & Security → Accessibility.")) }
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
            phase = error.phase; detailMessage = error.message
        } catch {
            phase = .failed; detailMessage = L10n.message("Operation failed: %@", error.localizedDescription)
        }
        if let stop = pendingStop {
            pendingStop = nil
            if stop == .finishReceivedAudio { await drainBeforePreserving?() }
            do { try await finish(cancel: stop == .cancelDictation) }
            catch { phase = .failed; detailMessage = L10n.message("Could not confirm recording stopped after disconnection. Check dictation in Codex.") }
        }
        if action != .scroll {
            lastOperation = "\(action) · \(phase.caption) · \(detail)"
            ConnectionTrace.record("control", "\(action) phase=\(phase) detail=\(detail)")
        }
        return phase
    }

    private func begin() async throws {
        guard target == .codex else { throw Failure(.unavailable, L10n.message("Dictation is not yet supported in Claude. Use Codex for dictation; Claude supports scrolling and Enter.")) }
        guard !pendingTranscription else { throw Failure(.transcribing, L10n.message("Confirming the previous dictation has stopped. Wait before starting again.")) }
        if recordingWindow != nil { refresh(); return }
        let (app, window) = try await activateTargetWindow()
        let elements = descendants(window)
        guard buttons(elements, matching: ["Retry dictation", "重试听写"]).isEmpty else {
            throw Failure(.failed, L10n.message("The previous Codex transcription failed. Retry dictation or clear the error on your Mac before recording again."))
        }
        let editor = try composer(elements, in: window)
        guard AXUIElementSetAttributeValue(editor, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else {
            throw Failure(.unavailable, L10n.message("Could not focus the Codex task input."))
        }
        guard buttons(elements, matching: AgentLabels.stop.union(AgentLabels.transcribing).union(AgentLabels.starting)).isEmpty else {
            throw Failure(.unavailable, L10n.message("Dictation or transcription is already running. Finish it on your Mac first."))
        }
        let controls = buttons(elements, matching: AgentLabels.dictate)
        guard controls.count == 1 else { throw Failure(.unavailable, L10n.message("Could not identify the Codex dictation button. Show the task input and use the English or Chinese Codex interface.")) }
        recordingWindow = window; recordingPID = app.processIdentifier
        recordingTitle = string(window, kAXTitleAttribute)
        lease.begin(at: ProcessInfo.processInfo.systemUptime)
        do { try press(controls[0]) } catch { clearRecording(); throw error }
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 100_000_000)
            let stops = buttons(descendants(window), matching: AgentLabels.stop)
            if stops.count == 1 {
                stopControl = stops[0]; phase = .listening; recordingConfirmed = true
                detailMessage = L10n.message("Watch microphone audio is being sent through BlackHole to Codex dictation.")
                return
            }
        }
        // Keep the lease alive so a late start is also cancelled by the watchdog.
        throw Failure(.failed, L10n.message("Could not confirm dictation started. Check Codex microphone permission; the Watch will not retry automatically."))
    }

    private func finish(cancel: Bool) async throws {
        guard let window = recordingWindow else { return }
        if pendingTranscription && !cancel { refresh(); return }
        guard string(window, kAXTitleAttribute) == recordingTitle else {
            lease.finish()
            throw Failure(.failed, L10n.message("The task window changed, so the original recording cannot be verified. Stop dictation manually in Codex."))
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
            throw Failure(.failed, L10n.message("Could not find the stop control for this recording. Stop dictation in Codex."))
        }
        try press(candidates[0])
        // Preserve the exact window through the asynchronous transcription period.
        pendingTranscription = true; phase = .transcribing; recordingConfirmed = false
        lease.finish(); stopDeadline = ProcessInfo.processInfo.systemUptime + 5
        detailMessage = cancel ? L10n.message("Canceling dictation. No message will be sent.") : L10n.message("Stopping Codex recording…")
        for _ in 0..<10 {
            try await Task.sleep(nanoseconds: 100_000_000)
            let current = descendants(window)
            let finishedLabels = AgentLabels.dictate.union(AgentLabels.transcribing).union(["Retry dictation", "重试听写"])
            if buttons(current, matching: AgentLabels.stop.union(AgentLabels.starting)).isEmpty,
               !buttons(current, matching: finishedLabels).isEmpty {
                lease.finish(); stopControl = nil; stopDeadline = nil
                detailMessage = cancel ? L10n.message("Dictation canceled. No message will be sent.") : L10n.message("Recording stopped. Wait for Codex to transcribe, review the text, then tap Enter on your Watch.")
                refresh(); return
            }
        }
        // Keep the existing watchdog for an unconfirmed finish; a failed cancel
        // itself must not loop forever. Never retry by pressing a start button.
        if cancel {
            lease.finish(); stopDeadline = nil
            throw Failure(.failed, L10n.message("Cancellation requested, but Codex still shows recording. Stop it manually in Codex."))
        }
        // Codex drains its microphone asynchronously. Keep the bounded watchdog,
        // but don't report a failed stop merely because its UI takes over 1 s.
        detailMessage = L10n.message("Watch recording stopped. Waiting for Codex to process the remaining audio and transcribe.")
    }

    private func refresh() {
        guard accessibilityGranted else { phase = .permissionRequired; return }
        if let window = recordingWindow {
            guard string(window, kAXTitleAttribute) == recordingTitle else {
                phase = .failed; detailMessage = L10n.message("The original task changed. Check dictation on your Mac."); return
            }
            let elements = descendants(window)
            if !buttons(elements, matching: ["Retry dictation", "重试听写"]).isEmpty {
                clearRecording(); phase = .failed
                detailMessage = L10n.message("Codex shows Retry dictation; no transcription was confirmed. Retry or clear the error on your Mac.")
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
                clearRecording(); phase = .ready; detailMessage = L10n.message("Review the text in Codex, then tap Enter.")
            } else if pendingTranscription { phase = .transcribing }
            return
        }
        if phase == .failed || phase == .unavailable { return }
        do { _ = try frontWindow(); phase = .ready }
        catch let failure as Failure { phase = failure.phase }
        catch { phase = .failed }
    }

    private func enter() throws {
        guard recordingWindow == nil else { throw Failure(.transcribing, L10n.message("Stop dictation and wait for transcription before tapping Enter.")) }
        let (app, window) = try frontWindow()
        let elements = descendants(window)
        guard buttons(elements, matching: AgentLabels.stop.union(AgentLabels.transcribing).union(AgentLabels.starting)).isEmpty else {
            throw Failure(.transcribing, L10n.message("Codex is still recording or transcribing. Wait before sending."))
        }
        let editor = try composer(elements, in: window)
        let value = string(editor, kAXValueAttribute).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw Failure(.unavailable, L10n.message("The input is empty. Enter was not sent.")) }
        guard AXUIElementSetAttributeValue(editor, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else {
            throw Failure(.unavailable, L10n.message("Could not focus the task input."))
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            throw Failure(.targetInactive, L10n.message("The target app is not in the foreground."))
        }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false) else {
            throw Failure(.failed, L10n.message("Could not create the Enter key event."))
        }
        down.postToPid(app.processIdentifier); up.postToPid(app.processIdentifier)
        phase = .ready; detailMessage = L10n.message("Enter was sent to the task input. Check Codex for the task status.")
    }

    private func scroll(_ pixels: Int16) throws {
        let started = ProcessInfo.processInfo.systemUptime
        let (app, window) = try frontWindow()
        guard let frame = rect(window) else { throw Failure(.unavailable, L10n.message("Could not locate the task window.")) }
        let title = string(window, kAXTitleAttribute)
        let cached = scrollAnchor.map { anchor in
            anchor.pid == app.processIdentifier && CFEqual(anchor.window, window)
                && anchor.frame == frame && anchor.title == title
                // Valid live geometry keeps the anchor usable. Scanning thousands
                // of AX nodes every 3 seconds stalled the main actor for 0.5–1.3 s.
                && (anchor.areaFrame != nil || anchor.editorFrame != nil || started - anchor.created < 0.25)
                && (anchor.area == nil || anchor.area.flatMap { rect($0) } == anchor.areaFrame)
                && (anchor.editor == nil || anchor.editor.flatMap { rect($0) } == anchor.editorFrame)
        } ?? false
        if !cached {
            let elements = descendants(window)
            let editor = try? composer(elements, in: window)
            let editorFrame = editor.flatMap { rect($0) }
            let areas = elements.filter { string($0, kAXRoleAttribute) == kAXScrollAreaRole }.compactMap { element -> (element: AXUIElement, frame: CGRect, visible: CGRect)? in
                guard let r = rect(element), r.width > 240, r.height > 120, r.intersects(frame) else { return nil }
                let visible = r.intersection(frame)
                if let editorFrame {
                    guard visible.contains(CGPoint(x: editorFrame.midX, y: visible.midY)), visible.minY < editorFrame.minY - 60 else { return nil }
                }
                return (element, r, visible)
            }
            let selectedArea = areas.max { $0.visible.width * $0.visible.height < $1.visible.width * $1.visible.height }
            let area = selectedArea?.visible
            let point = CGPoint(x: editorFrame?.midX ?? area?.midX ?? frame.midX,
                                y: area.map { min($0.midY, editorFrame.map { $0.minY - 40 } ?? $0.midY) } ?? frame.minY + frame.height * 0.4)
            scrollAnchor = ScrollAnchor(pid: app.processIdentifier, window: window, frame: frame, title: title,
                                        editor: editor, editorFrame: editorFrame, point: point, created: started,
                                        area: selectedArea?.element, areaFrame: selectedArea?.frame)
            ConnectionTrace.record("scroll", String(format: "target resolved in %.1f ms", (ProcessInfo.processInfo.systemUptime - started) * 1000))
        }
        scrollMotion.add(Int(pixels))
        if scrollTask == nil {
            let token = UUID(); scrollEpoch = token
            scrollTask = Task { [weak self] in
                guard let self else { return }
                defer { if self.scrollEpoch == token { self.scrollTask = nil } }
                var frames = 0, distance = 0, totalMS = 0.0
                while !Task.isCancelled, self.scrollEpoch == token, self.scrollMotion.pending != 0 {
                    let tick = ProcessInfo.processInfo.systemUptime
                    do {
                        let pixels = self.scrollMotion.next()
                        try self.emitScrollFrame(pixels); frames += 1; distance += abs(Int(pixels))
                    }
                    catch {
                        self.scrollMotion.reset(); self.scrollAnchor = nil
                        self.phase = .targetInactive; self.detailMessage = L10n.message("The scroll target changed. Scrolling stopped."); break
                    }
                    totalMS += (ProcessInfo.processInfo.systemUptime - tick) * 1000
                    try? await Task.sleep(nanoseconds: 16_666_667)
                }
                if frames > 0, ProcessInfo.processInfo.systemUptime - self.scrollReportedAt >= 1 {
                    self.scrollReportedAt = ProcessInfo.processInfo.systemUptime
                    ConnectionTrace.record("scroll", String(format: "burst pixels=%d frames=%d mean-frame-work=%.2f ms", distance, frames, totalMS / Double(frames)))
                }
            }
        }
        if !isRecording { phase = .ready }
        let message = pixels >= 0 ? L10n.message("Scrolling down the Codex conversation") : L10n.message("Scrolling up the Codex conversation")
        if detail != message.localizedString { detailMessage = message }
    }
    func stopScrolling() {
        scrollEpoch = UUID()
        scrollTask?.cancel(); scrollTask = nil; scrollMotion.reset(); scrollAnchor = nil
    }
    private func emitScrollFrame(_ pixels: Int16) throws {
        guard let anchor = scrollAnchor, NSWorkspace.shared.frontmostApplication?.processIdentifier == anchor.pid,
              rect(anchor.window) == anchor.frame,
              anchor.area == nil || anchor.area.flatMap({ rect($0) }) == anchor.areaFrame,
              anchor.editor == nil || anchor.editor.flatMap({ rect($0) }) == anchor.editorFrame else { throw Failure(.targetInactive, L10n.message("The target window changed.")) }
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(anchor.pid), kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused, CFEqual(focused, anchor.window) else { throw Failure(.targetInactive, L10n.message("The task window changed.")) }
        var hit: AXUIElement?, hitPID: pid_t = 0
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(anchor.point.x), Float(anchor.point.y), &hit) == .success,
              let hit, AXUIElementGetPid(hit, &hitPID) == .success, hitPID == anchor.pid else { throw Failure(.targetInactive, L10n.message("The conversation area is covered.")) }
        guard let event = CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState), units: .pixel,
                                  wheelCount: 1, wheel1: -Int32(pixels), wheel2: 0, wheel3: 0) else { throw Failure(.failed, L10n.message("Could not create the scroll event.")) }
        event.location = anchor.point; event.post(tap: .cghidEventTap)
    }

    private func activateTargetWindow() async throws -> (NSRunningApplication, AXUIElement) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleID).first else {
            throw Failure(.targetInactive, L10n.message("Open a task in %@ first.", target.rawValue))
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
            throw Failure(.targetInactive, L10n.message("Bring the %@ task window to the front. Keystrokes will not be sent to other apps.", target.rawValue))
        }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        prepareAccessibility(root, pid: app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(root, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw Failure(.unavailable, L10n.message("No task window is available."))
        }
        return (app, unsafeBitCast(value, to: AXUIElement.self))
    }
    private func composer(_ elements: [AXUIElement], in window: AXUIElement) throws -> AXUIElement {
        guard let windowRect = rect(window) else { throw Failure(.unavailable, L10n.message("Could not locate the task window.")) }
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
        throw Failure(.unavailable, L10n.message("Could not locate the task input. Keep the Codex task visible; search fields or multiple editors may prevent detection."))
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
            throw Failure(.failed, L10n.message("The target control did not accept the action."))
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
    private struct Failure: Error { let phase: HostPhase; let message: LocalizedMessage
        init(_ phase: HostPhase, _ message: LocalizedMessage) { self.phase = phase; self.message = message }
    }
}
