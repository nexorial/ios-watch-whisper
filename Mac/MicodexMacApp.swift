import SwiftUI
import MicodexCore

@main
struct MicodexMacApp: App {
    @StateObject private var controller: AgentController
    @StateObject private var host: BluetoothHost
    @StateObject private var wifi: WiFiHost
    private let demo = ProcessInfo.processInfo.arguments.contains("--demo")
    init() {
        let demo = ProcessInfo.processInfo.arguments.contains("--demo")
        let controller = AgentController(demo: demo)
        _controller = StateObject(wrappedValue: controller)
        _host = StateObject(wrappedValue: BluetoothHost(controller: controller, demo: demo, enabled: false))
        _wifi = StateObject(wrappedValue: WiFiHost(controller: controller, demo: demo))
    }
    var body: some Scene {
        WindowGroup(L10n.t("Micodex"), id: "control") {
            HostView(host: host, wifi: wifi, controller: controller, demo: demo)
        }
        .defaultSize(width: 420, height: 550)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        MenuBarExtra(L10n.t("Micodex"), systemImage: controller.isRecording ? "mic.fill" : "waveform") {
            HostMenu(wifi: wifi, controller: controller)
        }
    }
}

private struct HostMenu: View {
    @ObservedObject var wifi: WiFiHost
    @ObservedObject var controller: AgentController
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(L10n.t("Micodex · %@", wifi.status))
        Text(L10n.t("Mac IP: %@", wifi.address.isEmpty ? L10n.t("No local network") : wifi.address))
        Text(controller.phase.caption)
        Divider()
        Button(L10n.t("Open Micodex")) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "control")
        }
        Button(L10n.t("Stop Dictation")) { Task { _ = await controller.perform(.finishDictation) } }
            .disabled(!controller.isRecording)
        Divider()
        Button(L10n.t("Quit Micodex")) {
            Task { _ = await controller.perform(.cancelDictation); NSApplication.shared.terminate(nil) }
        }
    }
}

private struct HostView: View {
    @ObservedObject var host: BluetoothHost
    @ObservedObject var wifi: WiFiHost
    @ObservedObject var controller: AgentController
    let demo: Bool
    @StateObject private var network = WiFiNetworkInfo()
    @State private var showingConnection = false
    @State private var showingAdvanced = false
    @State private var copiedAddress = false

    private var needsAttention: Bool {
        [.permissionRequired, .targetInactive, .unavailable, .failed].contains(controller.phase)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(MicodexStyle.accent)
                Text(L10n.t("Micodex")).font(.system(size: 22, weight: .semibold, design: .rounded))
                Spacer()
                Text(demo ? L10n.t("UI DEMO") : L10n.t("WATCH → MAC"))
                    .font(.system(size: 9, weight: .medium)).tracking(1.3).foregroundStyle(.secondary)
            }
            .padding(.bottom, 25)

            HStack(alignment: .top, spacing: 16) {
                Image(systemName: controller.isRecording ? "waveform" : (needsAttention ? "exclamationmark" : "mic"))
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(needsAttention ? Color.orange : MicodexStyle.accent)
                    .frame(width: 58, height: 64)
                    .background(MicodexStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 7) {
                    Text(controller.phase == .ready ? L10n.t("Raise your wrist. Begin.") : controller.phase.caption)
                        .font(.system(size: 22, weight: .medium))
                    Text(controller.detail)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 20)
            HStack {
                Text(L10n.t("Control target")).foregroundStyle(.secondary)
                Spacer()
                Picker(L10n.t("Control target"), selection: $controller.target) {
                    ForEach(AgentController.Target.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden().frame(width: 114).disabled(controller.isRecording)
            }.font(.system(size: 12)).padding(.bottom, 14)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    connectionSection
                    Divider()
                    AudioRouteView(audio: wifi.audio, demo: demo)
                    Divider()
                    permissionRow
                    Divider()
                    advancedSection
                }
            }
            .padding(.top, 3)

            Divider()
            HStack(spacing: 5) {
                Image(systemName: "digitalcrown.horizontal.arrow.clockwise")
                Text(L10n.t("Crown to scroll"))
                Text(L10n.t("·")).padding(.horizontal, 3)
                Text(L10n.t("Hold to talk"))
                Text(L10n.t("·")).padding(.horizontal, 3)
                Text(L10n.t("Enter to send"))
                Spacer(minLength: 0)
                if controller.isRecording {
                    Button(L10n.t("Stop")) { Task { _ = await controller.perform(.finishDictation) } }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
            .font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 14)
        }
        .padding(.horizontal, 26).padding(.top, 36).padding(.bottom, 20)
        .frame(width: 420, height: 550)
        .tint(MicodexStyle.accent)
        .task {
            while !Task.isCancelled {
                network.refresh()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            controller.objectWillChange.send(); host.audio.refresh(); host.refreshRadio(); wifi.audio.refresh()
            wifi.refreshAddressIfNeeded(); network.refresh()
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "wifi").foregroundStyle(MicodexStyle.accent).frame(width: 20)
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.t("Apple Watch")).fontWeight(.medium)
                    Text(wifi.status).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(showingConnection ? L10n.t("Hide") : L10n.t("Connect")) { showingConnection.toggle() }
                    .buttonStyle(.borderless).font(.system(size: 11))
                    .accessibilityLabel(showingConnection ? L10n.t("Hide connection settings") : L10n.t("Show connection settings"))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.t("Mac Wi-Fi")).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(network.name ?? L10n.t("Name unavailable")).textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                if network.name == nil {
                    Text(network.explanation).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if network.needsAuthorization {
                        Button(L10n.t("Show Wi-Fi Name")) { network.requestNameAccess() }
                            .buttonStyle(.borderless).disabled(demo)
                    }
                }
            }.font(.system(size: 11)).padding(.leading, 31)
            HStack(spacing: 6) {
                Text(L10n.t("Mac IP")).foregroundStyle(.secondary)
                Text(wifi.address.isEmpty ? L10n.t("No local network") : wifi.address)
                    .monospaced().textSelection(.enabled)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(wifi.address, forType: .string)
                    copiedAddress = true
                } label: { Image(systemName: copiedAddress ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.borderless).disabled(wifi.address.isEmpty)
                    .help(copiedAddress ? L10n.t("IP copied") : L10n.t("Copy IP"))
                    .accessibilityLabel(copiedAddress ? L10n.t("IP copied") : L10n.t("Copy IP"))
            }
            .font(.system(size: 11)).padding(.leading, 31)
            .onChange(of: wifi.address) { _ in copiedAddress = false }
            Text(L10n.t("Enter this address in “Mac IP Address” on your watch."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).padding(.leading, 31)
            if let issue = wifi.serviceIssue {
                VStack(alignment: .leading, spacing: 8) {
                    Text(issue).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(L10n.t("Retry Receiver")) { wifi.refreshNetwork() }.disabled(!wifi.canRefreshNetwork)
                        if wifi.duplicateReceiver {
                            Button(L10n.t("Open Running Receiver")) {
                                NSWorkspace.shared.runningApplications.first {
                                    $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                                }?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                            }
                        }
                    }.controlSize(.small)
                }.font(.system(size: 11)).foregroundStyle(.orange).padding(.leading, 31)
            }
            if showingConnection || wifi.pendingCode != nil || (!demo && wifi.pairedCount == 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.t("1. Connect both devices to the same local network, ideally the same Wi-Fi.\n2. On your watch, enter the Mac IP above and tap “Save & Connect”.\n3. For first-time pairing, allow the watch here and check the six-digit code. Paired devices connect automatically."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(wifi.pairingOpen ? L10n.t("Waiting for Watch…") : L10n.t("Allow Wi-Fi Watch")) { wifi.allowPairing() }
                            .buttonStyle(.borderedProminent).disabled(wifi.pairingOpen || demo || !wifi.serviceReady)
                        Button(L10n.t("Reconnect Network")) { wifi.refreshNetwork(); network.refresh() }.disabled(demo || !wifi.canRefreshNetwork)
                        Spacer()
                    }.controlSize(.small)
                    if wifi.pairedCount > 0 {
                        Text(L10n.t("Paired watches: %@", String(wifi.pairedCount))).font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.leading, 31)
            }
            if let code = wifi.pendingCode {
                HStack {
                    Text(code).font(.system(size: 26, weight: .medium, design: .monospaced)).tracking(3)
                    Spacer()
                    Button(L10n.t("Codes Match — Allow")) { wifi.approve() }.buttonStyle(.borderedProminent)
                }.padding(12).background(MicodexStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }.font(.system(size: 12)).padding(.vertical, 16)
    }

    private var permissionRow: some View {
        HStack(spacing: 11) {
            Image(systemName: "hand.raised").foregroundStyle(MicodexStyle.accent).frame(width: 20)
            Text(L10n.t("Accessibility")).fontWeight(.medium)
            Spacer()
            if controller.accessibilityGranted {
                Label(demo ? L10n.t("Demo") : L10n.t("Allowed"), systemImage: "checkmark")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Button(L10n.t("Open Settings")) { controller.requestAccessibility() }
                    .buttonStyle(.borderless).font(.system(size: 11))
            }
        }.font(.system(size: 12)).padding(.vertical, 16)
    }

    private var advancedSection: some View {
        DisclosureGroup(L10n.t("More Settings"), isExpanded: $showingAdvanced) {
            VStack(alignment: .leading, spacing: 14) {
                DisclosureGroup(L10n.t("Bluetooth Backup")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(host.connection)
                        Text(host.radioStatus).foregroundStyle(.secondary)
                        HStack {
                            Button(L10n.t("Enable Bluetooth Backup")) { host.enableBluetooth() }
                            Button(L10n.t("Allow Bluetooth Watch")) { host.allowPairing() }.disabled(host.pairingOpen)
                        }
                        if let pending = host.pendingWatch {
                            Text(L10n.t("Watch request · %@", pending))
                            Button(L10n.t("Allow This Watch")) { host.approve() }
                        }
                    }.padding(.top, 8)
                }.disabled(demo)
                if !controller.lastOperation.isEmpty {
                    DisclosureGroup(L10n.t("Last Action")) {
                        Text(controller.lastOperation).textSelection(.enabled).padding(.top, 8)
                    }
                }
                Text(L10n.t("Swipe right to lock recording. It stops after about 2 seconds of silence after speech, or at 2 minutes. Speech is transcribed without sending."))
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(L10n.t("Remove All Pairings"), role: .destructive) { host.revokeAll(); wifi.revokeAll() }
                    .disabled(demo || (host.pairedCount == 0 && wifi.pairedCount == 0))
                if demo {
                    HStack {
                        Button(L10n.t("Start Demo")) { Task { _ = await controller.perform(.beginDictation) } }
                        Button(L10n.t("Stop Demo")) { Task { _ = await controller.perform(.finishDictation) } }
                    }
                }
            }.font(.system(size: 11)).controlSize(.small).padding(.top, 12)
        }.font(.system(size: 11)).padding(.vertical, 15)
    }
}

private struct AudioRouteView: View {
    @ObservedObject var audio: WatchAudioOutput
    let demo: Bool
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "mic").foregroundStyle(MicodexStyle.accent).frame(width: 20)
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.t("Watch Microphone")).fontWeight(.medium)
                    Text(audio.status).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(expanded ? L10n.t("Hide") : L10n.t("Settings")) { expanded.toggle() }
                    .buttonStyle(.borderless).font(.system(size: 11))
                    .accessibilityLabel(expanded ? L10n.t("Hide audio settings") : L10n.t("Show audio settings"))
            }
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text(audio.captureSummary).foregroundStyle(.secondary)
                    Text(L10n.t("BlackHole 2ch receives audio from your watch. When set as the dictation input, Codex and other apps using the default microphone will use it."))
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(L10n.t("Use for Dictation")) { audio.useForDictation() }.disabled(demo || !audio.installed)
                        Button(L10n.t("Check Devices")) { audio.refresh() }
                    }
                    Button(L10n.t("Open Sound Settings")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                    }.disabled(demo)
                }.font(.system(size: 11)).controlSize(.small).padding(.leading, 31)
            }
        }.font(.system(size: 12)).padding(.vertical, 16)
    }
}
