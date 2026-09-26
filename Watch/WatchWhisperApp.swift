import SwiftUI
import WatchKit
import WhisperCore

@main
struct WatchWhisperApp: App {
    @StateObject private var connection = WatchLink()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ContentView(connection: connection)
                .onChange(of: scenePhase) { connection.setActive($0 == .active) }
        }
    }
}

private struct ContentView: View {
    @ObservedObject var connection: WatchLink
    @State private var showingConnection = false
    var body: some View {
        Group {
            if connection.connected && !showingConnection {
                RemoteView(connection: connection, showingConnection: $showingConnection)
            } else {
                ConnectionView(connection: connection, showingConnection: $showingConnection)
            }
        }.tint(.mint)
    }
}

private struct RemoteView: View {
    @ObservedObject var connection: WatchLink
    @Binding var showingConnection: Bool
    @State private var gesture = TalkGesture()
    @State private var fingerDown = false
    @State private var crown = 0.0
    @State private var accumulator = CrownAccumulator()
    @State private var scrollHint = "转动表冠浏览"
    @FocusState private var crownFocused: Bool
    private var talking: Bool { connection.recordingRequested && !connection.stopping }

    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 6) {
            HStack {
                Circle().fill(connection.demo ? .orange : .mint).frame(width: 5, height: 5)
                Text(connection.demo ? "演示" : "WHISPER").font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(1.5)
                Spacer()
                Button {
                    stop(); showingConnection = true
                } label: { Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 12)) }
                    .buttonStyle(.plain).accessibilityLabel("连接设置")
            }.foregroundStyle(.secondary)
            Text(connection.phase.caption)
                .font(.system(size: 13, weight: .medium)).lineLimit(2).minimumScaleFactor(0.75)
                .foregroundStyle(connection.phase == .listening ? .mint : .primary)
                .frame(height: 20)
            VStack(spacing: 5) {
                Image(systemName: talking ? (gesture.state == .locked ? "lock.fill" : "waveform") : "mic.fill")
                    .font(.system(size: 26, weight: .medium))
                Text(connection.stopping ? "收音已停止" : (talking ? (gesture.state == .locked ? "点击停止" : "松开结束 · 右滑锁定") : "按住说话"))
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity).frame(height: max(48, min(76, geometry.size.height - 106)))
            .foregroundStyle(talking ? Color.black : Color.mint)
            .background(talking ? Color.mint : Color.mint.opacity(0.15), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.mint.opacity(0.35)))
            .contentShape(RoundedRectangle(cornerRadius: 24))
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
            .accessibilityLabel(talking ? "停止听写" : "开始听写，使用 Watch 麦克风")
            .accessibilityHint(connection.recordingLocked ? "锁定录音会在熄屏后继续，最长两分钟" : "短按或向右滑锁定录音")
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
                    Image(systemName: "stop.fill").font(.system(size: 12)).frame(maxWidth: .infinity).frame(height: 36)
                        .background(.mint.opacity(0.15), in: Capsule())
                }
                    .frame(width: 42).accessibilityLabel("停止听写")
                Button {
                    if talking { stop() } else { connection.send(.enter) }
                } label: {
                    Label("Enter", systemImage: "return").font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 36).background(.mint.opacity(0.15), in: Capsule())
                }
                    .disabled(connection.phase == .transcribing)
                    .accessibilityHint(talking ? "先停止听写，再次点击发送" : "发送 Mac 输入框中的文字")
            }.buttonStyle(.plain).foregroundStyle(.mint)
            Text(connection.demo ? "演示 · 不连接 Mac" : (connection.stopping ? "正在传完尾音，请稍候" : (talking ? connection.microphoneLevel : scrollHint)))
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
        }.frame(width: geometry.size.width, height: geometry.size.height)
        }
        .padding(.horizontal, 5)
        .focusable().focused($crownFocused)
        .digitalCrownRotation($crown, from: -10000, through: 10000, by: 0.1, sensitivity: .medium, isContinuous: true, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { [crown] value in
            let pixels = accumulator.add(value - crown)
            if pixels != 0 { connection.send(.scroll, value: pixels); scrollHint = pixels > 0 ? "↓ 向下浏览" : "↑ 向上浏览" }
        }
        .onChange(of: connection.phase) { gesture.hostChanged($0) }
        .onAppear {
            crownFocused = true
            if connection.recordingLocked { gesture.restoreLockedRecording() }
        }
        .onDisappear {
            if !connection.recordingLocked { stop() }
            fingerDown = false; gesture.reset()
        }
    }
    private func stop() {
        let action = gesture.stop()
        if action != nil || connection.phase == .listening { connection.send(.finishDictation) }
    }
}

private struct ConnectionView: View {
    @ObservedObject var connection: WatchLink
    @Binding var showingConnection: Bool
    @State private var wifiHost = ""
    @State private var showingScreenHelp = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "applewatch.radiowaves.left.and.right").font(.system(size: 30, weight: .light)).foregroundStyle(.mint)
                Text("连接你的 Mac").font(.headline)
                Text(connection.status).font(.caption).foregroundStyle(.secondary)
                if connection.usesWiFi { Text("Wi-Fi 直连").font(.caption2).foregroundStyle(.mint) }
                if let code = connection.pairingCode {
                    Text(code).font(.system(size: 30, weight: .semibold, design: .monospaced)).foregroundStyle(.mint)
                    Text("核对 Mac 上的六位码，再允许配对。").font(.caption2)
                }
                if connection.usesWiFi {
                    Text("目标 Mac IP").font(.caption.bold())
                    TextField("填写 Mac 显示的 IP", text: $wifiHost).font(.caption).accessibilityLabel("目标 Mac IP")
                    Text("这是电脑的地址，不是手表自身 IP。请与 Mac 接收端显示的地址核对。")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button("保存地址并重连") { connection.updateWiFiHost(wifiHost) }.font(.caption)
                    Text("已保存目标：\(connection.macAddress)").font(.caption2).foregroundStyle(.secondary)
                }
                if connection.connected {
                    Button("返回遥控") { showingConnection = false }
                    Button("忘记 Mac", role: .destructive) { connection.forget() }
                } else {
                    ForEach(connection.nearby) { mac in
                        Button { connection.choose(mac) } label: {
                            Label(mac.name, systemImage: "laptopcomputer").font(.caption)
                        }
                    }
                    Text(connection.usesWiFi ? "Mac 打开 Watch Whisper，点「允许 Wi-Fi 手表」，核对上方配对码。" : "Mac 打开蓝牙备用，允许配对后在这里选择它。")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button("重新配对") { connection.forget() }.font(.caption)
                    Button("试用界面") { connection.enableDemo(); showingConnection = false }.font(.caption)
                    if connection.usesWiFi { Button("使用蓝牙备用") { connection.useBluetooth() }.font(.caption) }
                    else if connection.canUseWiFi { Button("使用 Wi-Fi 直连") { connection.useWiFi() }.font(.caption) }
                }
                Button("屏幕与锁定录音") { showingScreenHelp.toggle() }.font(.caption)
                if showingScreenHelp {
                    Text("锁定录音在放下手腕或熄屏后继续。说话后安静 2 秒会自动停止，只转写不发送，最长 2 分钟。要保持画面可见，请在手表「设置 → 显示与亮度 → 始终显示」中允许本 App；系统仍会调暗屏幕。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
        }.onAppear { wifiHost = WatchWiFiConnection.configuration?.0 ?? "" }
    }
}
