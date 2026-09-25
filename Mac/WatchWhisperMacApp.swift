import SwiftUI
import WhisperCore

@main
struct WatchWhisperMacApp: App {
    @StateObject private var controller: AgentController
    @StateObject private var host: BluetoothHost
    private let demo = ProcessInfo.processInfo.arguments.contains("--demo")
    init() {
        let demo = ProcessInfo.processInfo.arguments.contains("--demo")
        let controller = AgentController(demo: demo)
        _controller = StateObject(wrappedValue: controller)
        _host = StateObject(wrappedValue: BluetoothHost(controller: controller, demo: demo))
    }
    var body: some Scene {
        WindowGroup("Watch Whisper", id: "control") { HostView(host: host, controller: controller, demo: demo) }
            .defaultSize(width: 470, height: 570)
            .windowResizability(.contentSize)
        MenuBarExtra("Watch Whisper", systemImage: controller.isRecording ? "mic.fill" : "applewatch.radiowaves.left.and.right") {
            HostMenu(host: host, controller: controller)
        }
    }
}

private struct HostMenu: View {
    @ObservedObject var host: BluetoothHost
    @ObservedObject var controller: AgentController
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(host.connection)
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
                Label(host.connection, systemImage: "antenna.radiowaves.left.and.right").font(.headline)
                Text(controller.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
            GroupBox("1 · 允许 Mac 接收操作") {
                HStack {
                    Label(demo ? "演示无需权限" : (controller.accessibilityGranted ? "辅助功能已允许" : "需要辅助功能权限"), systemImage: controller.accessibilityGranted ? "checkmark.circle.fill" : "hand.raised")
                    Spacer()
                    Button("打开设置") { controller.requestAccessibility() }.disabled(demo)
                }.padding(8)
            }
            GroupBox("2 · 与 Apple Watch 配对") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("在手表打开 Watch Whisper，选择这台 Mac。首次需要在两端确认，之后自动重连。")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(host.pairingOpen ? "等待手表…" : "允许新手表 · 60 秒") { host.allowPairing() }.disabled(host.pairingOpen || demo)
                        Spacer()
                        Text("已配对 \(host.pairedCount) 块").foregroundStyle(.secondary)
                    }
                    if let pending = host.pendingWatch {
                        HStack {
                            Text("附近手表请求 · \(pending)")
                            Button("允许这块手表") { host.approve() }.buttonStyle(.borderedProminent)
                        }
                    }
                }.padding(8)
            }
            AudioRouteView(audio: host.audio)
            HStack {
                Picker("控制目标", selection: $controller.target) {
                    ForEach(AgentController.Target.allCases) { Text($0.rawValue).tag($0) }
                }.disabled(controller.isRecording)
                Spacer()
                Button("移除所有配对") { host.revokeAll() }.disabled(host.pairedCount == 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                Label("表冠滚动 · 按住说话 · 右滑锁定 · Enter 发送", systemImage: "hand.draw")
                Text("语音由 Watch 麦克风采集，经 BlackHole 送入 Codex 自带听写。录音最长 2 分钟；连接中断会请求停止。")
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
                controller.objectWillChange.send(); host.audio.refresh()
            }
    }
}

private struct AudioRouteView: View {
    @ObservedObject var audio: WatchAudioOutput
    var body: some View {
        GroupBox("3 · Watch 麦克风") {
            VStack(alignment: .leading, spacing: 6) {
                Text(audio.status).font(.callout)
                Text("安装 BlackHole 2ch 后，在系统声音设置中选择它作为输入，并让 Codex 使用默认输入或 BlackHole 2ch。其他使用默认麦克风的应用也会使用这一输入。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("检查音频设备") { audio.refresh() }
                    Button("打开声音设置") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
    }
}
