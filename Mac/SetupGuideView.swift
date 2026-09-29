import SwiftUI
import MicodexCore

/// Real setup actions with live local checks. Permissions owned by Codex and the
/// Watch are explained and confirmed through the user's test, never inferred.
struct SetupGuideView: View {
    @ObservedObject var controller: AgentController
    @ObservedObject var wifi: WiFiHost
    @ObservedObject var audio: WatchAudioOutput
    let demo: Bool
    let onClose: (Bool) -> Void

    @State private var step: Step = .audio
    @State private var readiness = SetupReadiness()
    @State private var voiceEnabled = true
    @State private var scrollingConfirmed = false
    @State private var transcriptionConfirmed = false
    @State private var driverFilesPresent = false
    @State private var copiedCode = false
    @State private var copiedCommand = false

    init(controller: AgentController, wifi: WiFiHost, demo: Bool, onClose: @escaping (Bool) -> Void) {
        self.controller = controller; self.wifi = wifi; self.audio = wifi.audio
        self.demo = demo; self.onClose = onClose
    }

    private enum Step: Int, CaseIterable {
        case audio, permissions, pairing, test
        var caption: String {
            switch self {
            case .audio: return L10n.t("Audio")
            case .permissions: return L10n.t("Permissions")
            case .pairing: return L10n.t("Pair Watch")
            case .test: return L10n.t("Try It")
            }
        }
        var title: String {
            switch self {
            case .audio: return L10n.t("Set up your Watch microphone")
            case .permissions: return L10n.t("Allow the right permissions")
            case .pairing: return L10n.t("Connect your Watch to this Mac")
            case .test: return L10n.t("Try it from your wrist")
            }
        }
    }

    private var busy: Bool { controller.isRecording || controller.isFinishing || controller.isBusy }
    private var canFinish: Bool {
        !demo && readiness.canFinish(voiceEnabled: voiceEnabled, scrollingConfirmed: scrollingConfirmed,
                                     transcriptionConfirmed: transcriptionConfirmed)
            && (!voiceEnabled || controller.target == .codex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(L10n.t("Setup Guide"), systemImage: "applewatch")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(L10n.t("Step %@ of %@", String(step.rawValue + 1), "4"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Button { step = item } label: {
                        Text(item.caption).font(.system(size: 12, weight: step == item ? .semibold : .regular))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(step == item ? MicodexStyle.accent.opacity(0.12) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("setup.step.\(item.rawValue)")
                }
            }
            Text(step.title).font(.system(size: 24, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if demo { Text(L10n.t("Demo · Setup actions are disabled")).foregroundStyle(.secondary) }
                    switch step {
                    case .audio: audioStep
                    case .permissions: permissionsStep
                    case .pairing: pairingStep
                    case .test: testStep
                    }
                }
                .font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 12)
            }
            Divider()
            HStack {
                Button(L10n.t("Set Up Later")) { onClose(false) }.buttonStyle(.plain)
                    .foregroundStyle(.secondary).accessibilityIdentifier("setup.later")
                Spacer()
                Button(L10n.t("Check Again")) { refresh() }
                if step != .audio {
                    Button(L10n.t("Back")) { step = Step(rawValue: step.rawValue - 1) ?? .audio }
                }
                if step == .test {
                    Button(L10n.t("Finish Setup")) { if canFinish { onClose(true) } }
                        .buttonStyle(.borderedProminent).disabled(!canFinish)
                        .accessibilityIdentifier("setup.finish")
                } else {
                    Button(L10n.t("Next")) { step = Step(rawValue: step.rawValue + 1) ?? .test }
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("setup.next")
                }
            }.controlSize(.small)
        }
        .padding(24).frame(width: 500, height: 600).tint(MicodexStyle.accent)
        .task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private var audioStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("Homebrew installs BlackHole 2ch with Micodex. It carries Watch audio to Codex; Codex turns your speech into text."))
            Text(L10n.t("Watch microphone → Micodex → BlackHole 2ch → Codex"))
                .font(.system(size: 12, weight: .medium)).foregroundStyle(MicodexStyle.accent)
            Toggle(L10n.t("Set up voice input too"), isOn: $voiceEnabled).toggleStyle(.checkbox)
            if voiceEnabled {
                statusRow(L10n.t("BlackHole audio device"), ready: readiness.driverAvailable, pending: L10n.t("Not detected"))
                if !readiness.driverAvailable {
                    if driverFilesPresent {
                        Text(L10n.t("BlackHole files are installed, but the audio device is not available yet. Restart your Mac, reopen Micodex, then choose Check Again."))
                    } else {
                        Text(L10n.t("If you used the direct ZIP download or installation was interrupted, run this command. The installer may ask for an administrator password and a restart."))
                        Text("brew install --cask blackhole-2ch").font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        HStack {
                            Button(copiedCommand ? L10n.t("Command Copied") : L10n.t("Copy Install Command")) {
                                copy("brew install --cask blackhole-2ch"); copiedCommand = true
                            }
                            Link(L10n.t("BlackHole Installation Help"), destination: URL(string: "https://github.com/ExistentialAudio/BlackHole#installation-instructions")!)
                        }.controlSize(.small)
                    }
                }
                Divider()
                statusRow(L10n.t("Mac dictation input"), ready: readiness.inputSelected, pending: L10n.t("Select BlackHole 2ch"))
                Text(L10n.t("Choose BlackHole as the Mac input used by Codex. This also changes the microphone for other apps using the system default input. Your speakers stay unchanged."))
                    .foregroundStyle(.secondary)
                HStack {
                    Button(L10n.t("Use BlackHole for Dictation")) { audio.useForDictation(); refresh() }
                        .disabled(demo || busy || !readiness.driverAvailable || readiness.inputSelected)
                    Button(L10n.t("Open Sound Settings")) { openSettings("x-apple.systempreferences:com.apple.Sound-Settings.extension") }
                        .disabled(demo)
                }.controlSize(.small)
                if readiness.driverAvailable {
                    Text(audio.status).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            } else {
                Text(L10n.t("You can set up scrolling and Enter first. Reopen Setup Guide whenever you want to add voice input."))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusRow(L10n.t("Micodex on Mac · Accessibility"), ready: readiness.accessibilityAllowed, pending: L10n.t("Allow in System Settings"))
            Text(L10n.t("Allow Micodex in System Settings → Privacy & Security → Accessibility so your Watch can scroll and use Enter in Codex."))
            Button(L10n.t("Open Accessibility Settings")) { controller.requestAccessibility(); refresh() }
                .disabled(demo).controlSize(.small)
            Divider()
            if voiceEnabled {
                Text(L10n.t("Codex on Mac · Microphone")).fontWeight(.semibold)
                Text(L10n.t("Allow Codex in System Settings → Privacy & Security → Microphone. If Codex is not listed, start dictation in Codex once to request access. Micodex does not need the Mac microphone."))
                Text(L10n.t("Codex may appear as ChatGPT in macOS permission lists. Choose the app you use for Codex."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Button(L10n.t("Open Microphone Settings")) {
                    openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
                }.disabled(demo).controlSize(.small)
                Text(L10n.t("Micodex on Watch · Microphone")).fontWeight(.semibold)
                Text(L10n.t("Tap the microphone in the Watch app and allow microphone access. If you previously denied it, open Watch Settings → Privacy & Security → Microphone and enable Micodex."))
                Divider()
            }
            Text(L10n.t("Local Network · Both devices")).fontWeight(.semibold)
            Text(L10n.t("Allow Local Network for Micodex when prompted. On Mac, check System Settings → Privacy & Security → Local Network if a connection is blocked. Keep both devices on a network that allows them to reach each other."))
            Button(L10n.t("Open Privacy Settings")) { openSettings("x-apple.systempreferences:com.apple.preference.security") }
                .disabled(demo).controlSize(.small)
            Text(L10n.t("Location access is optional: it only displays the Wi-Fi name. You can pair using the Mac connection code without enabling location."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text(L10n.t("Permissions on Codex and Watch are confirmed by your test in the last step, not by an automatic check here."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var pairingStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusRow(L10n.t("Mac receiver"), ready: readiness.receiverReady, pending: wifi.status)
            if let issue = wifi.serviceIssue { Text(issue).foregroundStyle(.orange) }
            if !readiness.receiverReady {
                Text(L10n.t("Wi-Fi control requires macOS 15 or later. Connect your Mac to the local network, then check again."))
            }
            Text(L10n.t("Install and open Micodex on Apple Watch. Its first App Store release is still pending; existing testers can use their installed Watch app."))
            Link(L10n.t("Watch Installation Guide"), destination: URL(string: "https://github.com/nexorial/ios-watch-whisper#2-apple-watch--app-store")!)
            Text(L10n.t("1. Copy this Mac’s connection code.\n2. Paste it into the Watch app using the iPhone keyboard, then tap Trust This Mac & Connect.\n3. Allow pairing here and compare the six-digit codes before approving."))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(copiedCode ? L10n.t("Connection Code Copied") : L10n.t("Copy Connection Code")) {
                    if let code = wifi.connectionCode { copy(code); copiedCode = true }
                }.disabled(demo || wifi.connectionCode == nil)
                Button(wifi.pairingOpen ? L10n.t("Waiting for Watch…") : L10n.t("Allow Wi-Fi Watch")) { wifi.allowPairing() }
                    .disabled(demo || busy || !readiness.receiverReady || wifi.pairingOpen)
            }.controlSize(.small)
            if let code = wifi.pendingCode {
                Text(code).font(.system(size: 30, weight: .medium, design: .monospaced)).tracking(3)
                Button(L10n.t("Codes Match — Allow")) { wifi.approve(); refresh() }
                    .buttonStyle(.borderedProminent).disabled(demo || busy)
            }
            statusRow(L10n.t("Watch pairing"), ready: readiness.watchPaired, pending: L10n.t("Waiting for pairing"))
            Text(L10n.t("An existing pairing is remembered. Open the Watch app to reconnect; pairing does not mean the Watch is currently online."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var testStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t("Open a Codex conversation on your Mac. On Watch, turn the Crown and check that the conversation scrolls."))
            Toggle(L10n.t("I tested Crown scrolling in Codex"), isOn: $scrollingConfirmed).toggleStyle(.checkbox)
            if voiceEnabled {
                if controller.target != .codex {
                    Button(L10n.t("Use Codex as the Control Target")) { controller.target = .codex }
                        .disabled(demo || busy)
                }
                Text(L10n.t("Set Codex’s audio input to System Default or BlackHole 2ch. Tap the Watch microphone, wait for the start haptics, speak a short sentence, then tap again to stop. Check the text on Mac before pressing Enter."))
                Toggle(L10n.t("I saw my Watch speech become text in Codex"), isOn: $transcriptionConfirmed).toggleStyle(.checkbox)
                Text(L10n.t("No text? Recheck BlackHole input, Codex microphone access, Watch microphone access, and the connection. A paired Watch or detected driver alone does not verify speech recognition."))
                    .foregroundStyle(.secondary)
            }
            Divider()
            statusRow(L10n.t("Accessibility"), ready: readiness.accessibilityAllowed, pending: L10n.t("Needs attention"))
            statusRow(L10n.t("Mac receiver"), ready: readiness.receiverReady, pending: L10n.t("Needs attention"))
            statusRow(L10n.t("Watch pairing"), ready: readiness.watchPaired, pending: L10n.t("Needs attention"))
            if voiceEnabled { statusRow(L10n.t("Audio input"), ready: readiness.audioReady, pending: L10n.t("Needs attention")) }
            Text(canFinish ? L10n.t("Your setup checks and Watch test are complete.") : L10n.t("Finish the checks above, or choose Set Up Later. You can reopen this guide from the Mac panel."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private func statusRow(_ title: String, ready: Bool, pending: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ready ? MicodexStyle.accent : Color.secondary)
            Text(title).fontWeight(.medium)
            Spacer(minLength: 12)
            Text(ready ? L10n.t("Ready") : pending).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }.font(.system(size: 12)).accessibilityElement(children: .combine)
    }

    private func refresh() {
        guard !demo else { return }
        readiness = SetupReadiness(driverAvailable: audio.installed, inputSelected: audio.selectedForDictation,
                                   accessibilityAllowed: controller.accessibilityGranted,
                                   receiverReady: wifi.serviceReady, watchPaired: wifi.pairedCount > 0)
        driverFilesPresent = FileManager.default.fileExists(atPath: "/Library/Audio/Plug-Ins/HAL/BlackHole2ch.driver")
    }
    private func openSettings(_ value: String) {
        guard !demo, let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
    private func copy(_ value: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
    }
}
