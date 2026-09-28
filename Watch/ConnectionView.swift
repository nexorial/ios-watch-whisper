import SwiftUI
import MicodexCore

struct ConnectionView: View {
    @ObservedObject var connection: WatchLink
    @Binding var showingConnection: Bool
    @StateObject private var network = WiFiNetworkInfo()
    @State private var wifiHost = ""
    @State private var connectionCode = ""
    @State private var showingSetup = false
    @State private var addressError: String?
    @State private var showingMore = false
    @State private var showingScreenHelp = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 7) {
                    Image(systemName: "waveform").foregroundStyle(MicodexStyle.accent)
                    Text(L10n.t("Micodex")).font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(connection.connected ? L10n.t("Mac Connected") : L10n.t("Connect Your Mac")).font(.headline)
                    Text(connection.status).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if connection.usesWiFi || connection.canUseWiFi {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t("Watch Wi-Fi")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        Text(network.name ?? L10n.t("Name unavailable")).font(.system(size: 13, weight: .medium))
                        if network.name == nil {
                            Text(network.explanation).font(.caption2).foregroundStyle(.secondary)
                            if network.needsAuthorization {
                                Button(L10n.t("Show Wi-Fi Name")) { network.requestNameAccess() }.font(.caption)
                            }
                        }
                    }
                }
                if let code = connection.pairingCode {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(code).font(.system(size: 28, weight: .medium, design: .monospaced))
                            .tracking(2).foregroundStyle(MicodexStyle.accent)
                        Text(L10n.t("Check the six-digit code on your Mac and allow pairing.")).font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
                if connection.connected {
                    Button(L10n.t("Back to Remote")) { showingConnection = false }.buttonStyle(.borderedProminent)
                }
                if connection.usesWiFi && (!connection.canUseWiFi || showingSetup) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.t("Mac Connection Code")).font(.headline)
                        Text(L10n.t("On your Mac, click “Copy Connection Code”. Paste it here using the iPhone keyboard, or enter it exactly. Only use a code from your own Mac."))
                            .font(.caption2).foregroundStyle(.secondary)
                        TextField(L10n.t("micodex:IP:fingerprint"), text: $connectionCode)
                            .textInputAutocapitalization(.never).disableAutocorrection(true)
                            .accessibilityLabel(L10n.t("Mac Connection Code"))
                        Button(L10n.t("Trust This Mac & Connect")) {
                            guard let configuration = WiFiConfiguration(connectionCode: connectionCode) else {
                                addressError = L10n.t("Paste the complete connection code from your Mac. It includes the IP and 64-character certificate fingerprint."); return
                            }
                            addressError = nil
                            connection.configureWiFi(configuration)
                            wifiHost = configuration.host
                            showingSetup = false
                            connectionCode = ""
                        }.disabled(connection.recordingRequested || connection.stopping)
                        if let addressError { Text(addressError).font(.caption2).foregroundStyle(.orange) }
                    }
                }
                if connection.usesWiFi && connection.canUseWiFi {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.t("Mac IP Address")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        Text(L10n.t("Enter the “Mac IP” shown in the Mac app, not your watch’s IP."))
                            .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        TextField(L10n.t("e.g. 192.168.1.20"), text: $wifiHost)
                            .font(.system(size: 13, design: .monospaced)).accessibilityLabel(L10n.t("Mac IP Address. Enter the address shown in the Mac app."))
                        Button(L10n.t("Save & Connect")) {
                            guard let address = MacAddress.ipv4(wifiHost) else {
                                addressError = L10n.t("Enter the full Mac IP address, such as 192.168.1.20."); return
                            }
                            addressError = nil; wifiHost = address; connection.updateWiFiHost(address)
                        }
                            .font(.system(size: 12, weight: .medium))
                        if let addressError { Text(addressError).font(.caption2).foregroundStyle(.orange) }
                        if !connection.macAddress.isEmpty {
                            Text(L10n.t("Saved Mac IP: %@", connection.macAddress)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if !connection.connected {
                    ForEach(connection.nearby) { mac in
                        Button { connection.choose(mac) } label: {
                            Label(mac.name, systemImage: "laptopcomputer").font(.caption)
                        }
                    }
                    Text(connection.usesWiFi ? L10n.t("Keep Micodex open on your Mac with “Wi-Fi Ready” showing. For first-time pairing, click “Allow Wi-Fi Watch” on the Mac and check the code. Paired devices do not need to pair again.") : L10n.t("Enable Bluetooth Backup in Micodex on your Mac, then choose your computer."))
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                Button {
                    showingMore.toggle()
                } label: {
                    HStack {
                        Text(L10n.t("More Options"))
                        Spacer()
                        Image(systemName: showingMore ? "chevron.up" : "chevron.down")
                    }.font(.system(size: 12)).frame(minHeight: 36)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                if showingMore {
                    VStack(alignment: .leading, spacing: 10) {
                        if connection.connected {
                            Button(L10n.t("Forget Mac"), role: .destructive) { connection.forget() }
                        } else {
                            Button(L10n.t("Pair Again")) { connection.forget() }
                            Button(L10n.t("Try Demo")) { connection.enableDemo(); showingConnection = false }
                            if connection.usesWiFi { Button(L10n.t("Use Bluetooth Backup")) { connection.useBluetooth() } }
                            else { Button(L10n.t("Use Direct Wi-Fi")) { connection.useWiFi() } }
                        }
                        if connection.usesWiFi && connection.canUseWiFi {
                            Button(L10n.t("Set Up Another Mac")) { showingSetup.toggle() }
                                .disabled(connection.recordingRequested || connection.stopping)
                        }
                        Button(L10n.t("Screen & Recording")) { showingScreenHelp.toggle() }
                        if showingScreenHelp {
                            Text(L10n.t("Swipe right to lock recording and keep recording with your wrist down. It stops after about 2 seconds of silence after speech, or at 2 minutes, and transcribes without sending. Enable Always On in Settings → Display & Brightness; the screen will still dim."))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }.font(.caption)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
        }.onAppear { wifiHost = WatchWiFiConnection.configuration?.0 ?? "" }
        .task {
            while !Task.isCancelled {
                network.refresh()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
}
