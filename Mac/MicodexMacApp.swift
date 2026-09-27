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
        WindowGroup("Micodex", id: "control") {
            HostView(host: host, wifi: wifi, controller: controller, demo: demo)
        }
        .defaultSize(width: 420, height: 550)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        MenuBarExtra("Micodex", systemImage: controller.isRecording ? "mic.fill" : "waveform") {
            HostMenu(wifi: wifi, controller: controller)
        }
    }
}

private struct HostMenu: View {
    @ObservedObject var wifi: WiFiHost
    @ObservedObject var controller: AgentController
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("Micodex · \(wifi.status)")
        Text("Mac IP：\(wifi.address.isEmpty ? "未连接局域网" : wifi.address)")
        Text(controller.phase.caption)
        Divider()
        Button("打开 Micodex") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "control")
        }
        Button("停止听写") { Task { _ = await controller.perform(.finishDictation) } }
            .disabled(!controller.isRecording)
        Divider()
        Button("退出 Micodex") {
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
                Text("Micodex").font(.system(size: 22, weight: .semibold, design: .rounded))
                Spacer()
                Text(demo ? "界面演示" : "WATCH → MAC")
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
                    Text(controller.phase == .ready ? "抬腕，即可开始。" : controller.phase.caption)
                        .font(.system(size: 22, weight: .medium))
                    Text(controller.detail)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 20)
            HStack {
                Text("控制目标").foregroundStyle(.secondary)
                Spacer()
                Picker("控制目标", selection: $controller.target) {
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
                Text("表冠滚动")
                Text("·").padding(.horizontal, 3)
                Text("按住说话")
                Text("·").padding(.horizontal, 3)
                Text("Enter 发送")
                Spacer(minLength: 0)
                if controller.isRecording {
                    Button("停止") { Task { _ = await controller.perform(.finishDictation) } }
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
                    Text("Apple Watch").fontWeight(.medium)
                    Text(wifi.status).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(showingConnection ? "收起" : "连接") { showingConnection.toggle() }
                    .buttonStyle(.borderless).font(.system(size: 11))
                    .accessibilityLabel(showingConnection ? "收起连接设置" : "展开连接设置")
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Mac 当前 Wi-Fi").foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(network.name ?? "名称未获取").textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                if network.name == nil {
                    Text(network.explanation).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if network.needsAuthorization {
                        Button("显示 Wi-Fi 名称") { network.requestNameAccess() }
                            .buttonStyle(.borderless).disabled(demo)
                    }
                }
            }.font(.system(size: 11)).padding(.leading, 31)
            HStack(spacing: 6) {
                Text("Mac IP").foregroundStyle(.secondary)
                Text(wifi.address.isEmpty ? "未连接局域网" : wifi.address)
                    .monospaced().textSelection(.enabled)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(wifi.address, forType: .string)
                    copiedAddress = true
                } label: { Image(systemName: copiedAddress ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(.borderless).disabled(wifi.address.isEmpty)
                    .help(copiedAddress ? "已复制 IP" : "复制 IP")
                    .accessibilityLabel(copiedAddress ? "已复制 IP" : "复制 IP")
            }
            .font(.system(size: 11)).padding(.leading, 31)
            .onChange(of: wifi.address) { _ in copiedAddress = false }
            Text("请在手表的「Mac IP 地址」输入这里显示的地址。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true).padding(.leading, 31)
            if let issue = wifi.serviceIssue {
                VStack(alignment: .leading, spacing: 8) {
                    Text(issue).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("重试接收服务") { wifi.refreshNetwork() }.disabled(!wifi.canRefreshNetwork)
                        if wifi.duplicateReceiver {
                            Button("打开已运行的接收端") {
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
                    Text("1. 两端连接可互访的局域网（建议同一 Wi-Fi）。\n2. 手表输入上方 Mac IP，点「保存并连接」。\n3. 首次连接时，在这里允许手表并核对六位码；已配对设备会自动连接。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(wifi.pairingOpen ? "等待手表…" : "允许 Wi-Fi 手表") { wifi.allowPairing() }
                            .buttonStyle(.borderedProminent).disabled(wifi.pairingOpen || demo || !wifi.serviceReady)
                        Button("重新连接网络") { wifi.refreshNetwork(); network.refresh() }.disabled(demo || !wifi.canRefreshNetwork)
                        Spacer()
                    }.controlSize(.small)
                    if wifi.pairedCount > 0 {
                        Text("已配对 \(wifi.pairedCount) 块手表").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.leading, 31)
            }
            if let code = wifi.pendingCode {
                HStack {
                    Text(code).font(.system(size: 26, weight: .medium, design: .monospaced)).tracking(3)
                    Spacer()
                    Button("核对一致，允许") { wifi.approve() }.buttonStyle(.borderedProminent)
                }.padding(12).background(MicodexStyle.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }.font(.system(size: 12)).padding(.vertical, 16)
    }

    private var permissionRow: some View {
        HStack(spacing: 11) {
            Image(systemName: "hand.raised").foregroundStyle(MicodexStyle.accent).frame(width: 20)
            Text("辅助功能").fontWeight(.medium)
            Spacer()
            if controller.accessibilityGranted {
                Label(demo ? "演示" : "已允许", systemImage: "checkmark")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Button("打开设置") { controller.requestAccessibility() }
                    .buttonStyle(.borderless).font(.system(size: 11))
            }
        }.font(.system(size: 12)).padding(.vertical, 16)
    }

    private var advancedSection: some View {
        DisclosureGroup("更多设置", isExpanded: $showingAdvanced) {
            VStack(alignment: .leading, spacing: 14) {
                DisclosureGroup("蓝牙备用") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(host.connection)
                        Text(host.radioStatus).foregroundStyle(.secondary)
                        HStack {
                            Button("开启蓝牙备用") { host.enableBluetooth() }
                            Button("允许蓝牙手表") { host.allowPairing() }.disabled(host.pairingOpen)
                        }
                        if let pending = host.pendingWatch {
                            Text("手表请求 · \(pending)")
                            Button("允许这块手表") { host.approve() }
                        }
                    }.padding(.top, 8)
                }.disabled(demo)
                if !controller.lastOperation.isEmpty {
                    DisclosureGroup("最近一次操作") {
                        Text(controller.lastOperation).textSelection(.enabled).padding(.top, 8)
                    }
                }
                Text("右滑可锁定录音；说话后安静约 2 秒自动停止。只转写，不自动发送，最长 2 分钟。")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("移除所有配对", role: .destructive) { host.revokeAll(); wifi.revokeAll() }
                    .disabled(demo || (host.pairedCount == 0 && wifi.pairedCount == 0))
                if demo {
                    HStack {
                        Button("演示开始") { Task { _ = await controller.perform(.beginDictation) } }
                        Button("演示停止") { Task { _ = await controller.perform(.finishDictation) } }
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
                    Text("Watch 麦克风").fontWeight(.medium)
                    Text(audio.status).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(expanded ? "收起" : "设置") { expanded.toggle() }
                    .buttonStyle(.borderless).font(.system(size: 11))
                    .accessibilityLabel(expanded ? "收起音频设置" : "展开音频设置")
            }
            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Text(audio.captureSummary).foregroundStyle(.secondary)
                    Text("使用 BlackHole 2ch 接收手表声音。设为听写输入后，Codex 和其他使用默认麦克风的应用都会使用它。")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("设为听写输入") { audio.useForDictation() }.disabled(demo || !audio.installed)
                        Button("检查设备") { audio.refresh() }
                    }
                    Button("打开声音设置") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                    }.disabled(demo)
                }.font(.system(size: 11)).controlSize(.small).padding(.leading, 31)
            }
        }.font(.system(size: 12)).padding(.vertical, 16)
    }
}
