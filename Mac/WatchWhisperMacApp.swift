import SwiftUI
import WhisperCore

@main
struct WatchWhisperMacApp: App {
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
        WindowGroup("Watch Whisper", id: "control") { HostView(host: host, wifi: wifi, controller: controller, demo: demo) }
            .defaultSize(width: 470, height: 570)
            .windowResizability(.contentSize)
        MenuBarExtra("Watch Whisper", systemImage: controller.isRecording ? "mic.fill" : "applewatch.radiowaves.left.and.right") {
            HostMenu(host: host, wifi: wifi, controller: controller)
        }
    }
}

private struct HostMenu: View {
    @ObservedObject var host: BluetoothHost
    @ObservedObject var wifi: WiFiHost
    @ObservedObject var controller: AgentController
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(wifi.status)
        Text("Mac IP：\(wifi.address.isEmpty ? "未连接局域网" : wifi.address)")
        Text(controller.phase.caption)
        Divider()
        Button("打开控制面板") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "control")
        }
        Button("停止听写") { Task { _ = await controller.perform(.finishDictation) } }
        Divider()
        Button("退出") { Task { _ = await controller.perform(.cancelDictation); NSApplication.shared.terminate(nil) } }
    }
}

private struct HostView: View {
    @ObservedObject var host: BluetoothHost
    @ObservedObject var wifi: WiFiHost
    @ObservedObject var controller: AgentController
    let demo: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 36, weight: .light)).foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Watch Whisper").font(.title2.bold())
                    Text(demo ? "界面演示 · 不连接设备" : "抬腕，掌控你的 Agent").foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Label(wifi.status, systemImage: "wifi").font(.headline)
                Text(controller.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
            GroupBox("1 · 允许 Mac 接收操作") {
                HStack {
                    Label(demo ? "演示无需权限" : (controller.accessibilityGranted ? "辅助功能已允许" : "需要辅助功能权限"), systemImage: controller.accessibilityGranted ? "checkmark.circle.fill" : "hand.raised")
                    Spacer()
                    Button("打开设置") { controller.requestAccessibility() }.disabled(demo)
                }.padding(8)
            }
            GroupBox("2 · Wi-Fi 连接 Apple Watch") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Mac IP").font(.callout.bold())
                        Text(wifi.address.isEmpty ? "未连接局域网" : wifi.address)
                            .font(.system(.title3, design: .monospaced).bold()).textSelection(.enabled)
                            .accessibilityLabel("Mac IP：\(wifi.address)")
                        Spacer()
                    }
                    HStack {
                        Button("复制 IP") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(wifi.address, forType: .string)
                        }.disabled(wifi.address.isEmpty)
                        Button("刷新网络") { wifi.refreshNetwork() }.disabled(demo || !wifi.canRefreshNetwork)
                    }
                    Text("在手表的「目标 Mac IP」填入上方地址。两台设备连接同一局域网，设备各自的 IP 不需要相同。首次连接再核对六位配对码。")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(wifi.pairingOpen ? "等待手表…" : "允许 Wi-Fi 手表") { wifi.allowPairing() }
                            .disabled(wifi.pairingOpen || demo)
                        Spacer()
                        Text("已配对 \(wifi.pairedCount) 块").foregroundStyle(.secondary)
                    }
                    if let code = wifi.pendingCode {
                        HStack {
                            Text(code).font(.system(.title2, design: .monospaced).bold())
                            Button("核对一致，允许手表") { wifi.approve() }.buttonStyle(.borderedProminent)
                        }
                    }
                }.padding(8)
            }
            AudioRouteView(audio: wifi.audio)
            if !controller.lastOperation.isEmpty {
                DisclosureGroup("最近一次操作") {
                    Text(controller.lastOperation).font(.caption).textSelection(.enabled)
                }
            }
            DisclosureGroup("蓝牙备用") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(host.connection).font(.caption)
                    Text(host.radioStatus).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("开启蓝牙备用") { host.enableBluetooth() }
                        Button("允许蓝牙手表") { host.allowPairing() }.disabled(host.pairingOpen)
                    }
                    if let pending = host.pendingWatch {
                        HStack {
                            Text("手表请求 · \(pending)")
                            Button("允许这块手表") { host.approve() }
                        }
                    }
                }.padding(.top, 8)
            }.disabled(demo)
            HStack {
                Picker("控制目标", selection: $controller.target) {
                    ForEach(AgentController.Target.allCases) { Text($0.rawValue).tag($0) }
                }.disabled(controller.isRecording)
                Spacer()
                Button("移除所有配对") { host.revokeAll(); wifi.revokeAll() }.disabled(host.pairedCount == 0 && wifi.pairedCount == 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                Label("表冠滚动 · 按住说话 · 右滑锁定 · Enter 发送", systemImage: "hand.draw")
                Text("Watch 麦克风 → Codex 自带听写。说话后安静约 2 秒自动停止，只转写不发送；松开或点停止也可结束。录音最长 2 分钟。")
                    .foregroundStyle(.secondary)
            }.font(.caption)
            if demo {
                HStack {
                    Button("演示开始") { Task { _ = await controller.perform(.beginDictation) } }
                    Button("演示停止") { Task { _ = await controller.perform(.finishDictation) } }
                    Text(controller.phase.caption).foregroundStyle(.mint)
                }
            }
        }.padding(28).frame(width: 470).tint(.mint)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                controller.objectWillChange.send(); host.audio.refresh(); host.refreshRadio(); wifi.audio.refresh()
                wifi.refreshAddressIfNeeded()
            }
    }
}

private struct AudioRouteView: View {
    @ObservedObject var audio: WatchAudioOutput
    var body: some View {
        GroupBox("3 · Watch 麦克风") {
            VStack(alignment: .leading, spacing: 6) {
                Text(audio.status).font(.callout)
                Text(audio.captureSummary).font(.caption).foregroundStyle(.secondary)
                Text("安装 BlackHole 2ch 后，在系统声音设置中选择它作为输入，并让 Codex 使用默认输入或 BlackHole 2ch。其他使用默认麦克风的应用也会使用这一输入。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("设为听写输入") { audio.useForDictation() }.disabled(!audio.installed)
                    Button("检查音频设备") { audio.refresh() }
                    Button("打开声音设置") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }
}
