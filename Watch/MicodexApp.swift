import SwiftUI
import WatchKit
import MicodexCore

@main
struct MicodexApp: App {
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
        }.tint(MicodexStyle.accent)
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
            HStack(spacing: 5) {
                Circle().fill(connection.demo ? Color.orange : MicodexStyle.accent).frame(width: 4, height: 4)
                Text("Micodex").font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Button {
                    stop(); showingConnection = true
                } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 12, weight: .medium))
                        .frame(width: 44, height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("连接设置")
            }.foregroundStyle(.secondary).frame(height: 26)
            VStack(spacing: 7) {
                Image(systemName: connection.stopping ? "ellipsis" : (talking ? (gesture.state == .locked ? "lock.fill" : "waveform") : "mic.fill"))
                    .font(.system(size: geometry.size.height < 180 ? 24 : 30, weight: .medium))
                Text(connection.stopping ? "正在转写…" : (talking ? (gesture.state == .locked ? "点击停止" : "松开结束") : "按住说话"))
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
                    Image(systemName: "stop.fill").font(.system(size: 13))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.09), in: Circle())
                }
                .accessibilityLabel("停止听写")
                Button {
                    if talking { stop() } else { connection.send(.enter) }
                } label: {
                    HStack(spacing: 8) {
                        Text("Enter")
                        Image(systemName: "return")
                    }.font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(Color.white.opacity(0.09), in: Capsule())
                }
                .disabled(connection.phase == .transcribing)
                .accessibilityHint(talking ? "先停止听写，再次点击发送" : "发送 Mac 输入框中的文字")
            }.buttonStyle(.plain).foregroundStyle(.primary)
            Text(footer)
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .lineLimit(2).minimumScaleFactor(0.85)
                .multilineTextAlignment(.center).frame(height: needsAttention ? 25 : 14)
        }.frame(width: geometry.size.width, height: geometry.size.height)
        }
        .padding(.horizontal, 3)
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
    private var needsAttention: Bool {
        [.permissionRequired, .targetInactive, .unavailable, .failed].contains(connection.phase)
    }

    private var footer: String {
        if connection.demo { return "演示 · 不连接 Mac" }
        if connection.stopping { return "正在传完尾音，请稍候" }
        if talking { return gesture.state == .locked ? connection.microphoneLevel : "右滑锁定 · 松开结束" }
        return connection.phase == .ready ? scrollHint : connection.phase.caption
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
    @State private var showingMore = false
    @State private var showingScreenHelp = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 7) {
                    Image(systemName: "waveform").foregroundStyle(MicodexStyle.accent)
                    Text("Micodex").font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(connection.connected ? "Mac 已连接" : "连接你的 Mac").font(.headline)
                    Text(connection.status).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let code = connection.pairingCode {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(code).font(.system(size: 28, weight: .medium, design: .monospaced))
                            .tracking(2).foregroundStyle(MicodexStyle.accent)
                        Text("在 Mac 核对六位码并允许配对。").font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
                if connection.connected {
                    Button("返回遥控") { showingConnection = false }.buttonStyle(.borderedProminent)
                }
                if connection.usesWiFi {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("目标 Mac IP").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        TextField("填写 Mac 显示的 IP", text: $wifiHost)
                            .font(.system(size: 13, design: .monospaced)).accessibilityLabel("目标 Mac IP")
                        Button("保存并连接") { connection.updateWiFiHost(wifiHost) }
                            .font(.system(size: 12, weight: .medium))
                        if !connection.macAddress.isEmpty {
                            Text("当前：\(connection.macAddress)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if !connection.connected {
                    ForEach(connection.nearby) { mac in
                        Button { connection.choose(mac) } label: {
                            Label(mac.name, systemImage: "laptopcomputer").font(.caption)
                        }
                    }
                    Text(connection.usesWiFi ? "Mac 打开 Micodex，点「允许 Wi-Fi 手表」。两台设备需在同一局域网。" : "在 Mac 的 Micodex 中开启蓝牙备用，再选择你的电脑。")
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                Button {
                    showingMore.toggle()
                } label: {
                    HStack {
                        Text("更多选项")
                        Spacer()
                        Image(systemName: showingMore ? "chevron.up" : "chevron.down")
                    }.font(.system(size: 12)).frame(minHeight: 36)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                if showingMore {
                    VStack(alignment: .leading, spacing: 10) {
                        if connection.connected {
                            Button("忘记 Mac", role: .destructive) { connection.forget() }
                        } else {
                            Button("重新配对") { connection.forget() }
                            Button("试用界面") { connection.enableDemo(); showingConnection = false }
                            if connection.usesWiFi { Button("使用蓝牙备用") { connection.useBluetooth() } }
                            else if connection.canUseWiFi { Button("使用 Wi-Fi 直连") { connection.useWiFi() } }
                        }
                        Button("屏幕与录音") { showingScreenHelp.toggle() }
                        if showingScreenHelp {
                            Text("右滑锁定后，放下手腕仍可录音。说话后安静约 2 秒自动停止，只转写不发送，最长 2 分钟。常亮可在系统「显示与亮度 → 始终显示」中设置，屏幕仍会调暗。")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }.font(.caption)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
        }.onAppear { wifiHost = WatchWiFiConnection.configuration?.0 ?? "" }
    }
}
