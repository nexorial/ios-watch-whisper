import SwiftUI
import WatchKit
import MicodexCore

struct RemoteView: View {
    @ObservedObject var connection: WatchLink
    @Binding var showingConnection: Bool
    @State private var gesture = TalkGesture()
    @State private var fingerDown = false
    @State private var crown = 0.0
    @State private var previousCrownOffset = 0.0
    #if DEBUG
    @State private var crownPixels = 0
    @State private var crownDistance = 0.0
    @State private var crownPeakVelocity = 0.0
    private var crownDiagnostics: String {
        String(format: "pixels=%d;units=%.4f;velocity=%.4f", crownPixels, crownDistance, crownPeakVelocity)
    }
    #endif
    @State private var accumulator = CrownAccumulator()
    @State private var scrollHint = L10n.t("Turn Crown to scroll")
    @FocusState private var crownFocused: Bool
    private var talking: Bool { connection.recordingRequested && !connection.stopping }

    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Circle().fill(connection.demo ? Color.orange : MicodexStyle.accent).frame(width: 4, height: 4)
                Text(L10n.t("Micodex")).font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Button {
                    stop(); showingConnection = true
                } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 12, weight: .medium))
                        .frame(width: 44, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(L10n.t("Connection settings"))
            }.foregroundStyle(.secondary).frame(height: 26)
            VStack(spacing: 7) {
                Image(systemName: connection.stopping ? "ellipsis" : (talking ? (gesture.state == .locked ? "lock.fill" : "waveform") : "mic.fill"))
                    .font(.system(size: geometry.size.height < 180 ? 24 : 30, weight: .medium))
                Text(connection.stopping ? L10n.t("Transcribing…") : (talking ? (gesture.state == .locked ? L10n.t("Tap to stop") : L10n.t("Release to stop")) : L10n.t("Hold to talk")))
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(talking ? MicodexStyle.ink : MicodexStyle.accent)
            .background(talking ? MicodexStyle.accent : MicodexStyle.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 28))
            .contentShape(RoundedRectangle(cornerRadius: 28))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard connection.phase != .transcribing else { return }
                    if !fingerDown {
                        fingerDown = true
                        if let action = gesture.touchDown(at: ProcessInfo.processInfo.systemUptime) { connection.send(action) }
                    }
                    if gesture.drag(right: value.translation.width) {
                        connection.setRecordingLocked(true); WKInterfaceDevice.current().play(.click)
                    }
                }
                .onEnded { _ in
                    guard fingerDown else { return }; fingerDown = false
                    if let action = gesture.release(at: ProcessInfo.processInfo.systemUptime) { connection.send(action) }
                    connection.setRecordingLocked(gesture.state == .locked)
                })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(talking ? L10n.t("Stop Dictation") : L10n.t("Start dictation with the Watch microphone"))
            .accessibilityHint(connection.recordingLocked ? L10n.t("Locked recording continues with the screen off, for up to two minutes") : L10n.t("Tap or swipe right to lock recording"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if talking { stop() }
                else {
                    _ = gesture.touchDown(at: 0); _ = gesture.drag(right: 44); connection.send(.beginDictation)
                    connection.setRecordingLocked(true)
                }
            }
            HStack(spacing: 8) {
                Button { stop() } label: {
                    Image(systemName: "stop.fill").font(.system(size: 13))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.09), in: Circle())
                }
                .accessibilityLabel(L10n.t("Stop Dictation"))
                Button {
                    if talking { stop() } else { connection.send(.enter) }
                } label: {
                    HStack(spacing: 8) {
                        Text(L10n.t("Enter"))
                        Image(systemName: "return")
                    }.font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(Color.white.opacity(0.09), in: Capsule())
                }
                .disabled(connection.phase == .transcribing)
                .accessibilityHint(talking ? L10n.t("Stop dictation first, then tap again to send") : L10n.t("Send the text in the Mac input field"))
            }.buttonStyle(.plain).foregroundStyle(.primary)
            Text(footer)
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .lineLimit(2).minimumScaleFactor(0.85)
                .multilineTextAlignment(.center).frame(height: needsAttention ? 25 : 14)
                #if DEBUG
                .accessibilityIdentifier("remote.footer")
                .accessibilityValue(ProcessInfo.processInfo.arguments.contains("--crown-diagnostics") ? crownDiagnostics : "")
                #endif
        }.frame(width: geometry.size.width, height: geometry.size.height)
        }
        .padding(.horizontal, 3)
        .focusable().focused($crownFocused)
        .digitalCrownRotation($crown, from: -10000, through: 10000, sensitivity: .medium, isContinuous: true, isHapticFeedbackEnabled: true) { event in
            let delta = event.offset - previousCrownOffset
            previousCrownOffset = event.offset
            let pixels = accumulator.add(delta, velocity: event.velocity)
            #if DEBUG
            crownPixels += Int(pixels); crownDistance += delta
            crownPeakVelocity = max(crownPeakVelocity, abs(event.velocity))
            #endif
            if pixels != 0 { connection.send(.scroll, value: pixels); scrollHint = pixels > 0 ? L10n.t("↓ Scroll down") : L10n.t("↑ Scroll up") }
        } onIdle: {
            accumulator.reset()
            #if DEBUG
            ConnectionTrace.record("crown", crownDiagnostics)
            #endif
        }
        .onChange(of: connection.phase) { gesture.hostChanged($0) }
        .onAppear {
            crownFocused = true
            if connection.recordingLocked { gesture.restoreLockedRecording() }
        }
        .onDisappear {
            accumulator.reset()
            if !connection.recordingLocked { stop() }
            fingerDown = false; gesture.reset()
        }
    }
    private var needsAttention: Bool {
        [.permissionRequired, .targetInactive, .unavailable, .failed].contains(connection.phase)
    }

    private var footer: String {
        if connection.demo { return L10n.t("Demo · No Mac connection") }
        if connection.stopping { return L10n.t("Finishing audio…") }
        if talking { return gesture.state == .locked ? connection.microphoneLevel : L10n.t("Swipe right to lock") }
        return connection.phase == .ready ? scrollHint : connection.phase.caption
    }

    private func stop() {
        let action = gesture.stop()
        if action != nil || connection.phase == .listening { connection.send(.finishDictation) }
    }
}
