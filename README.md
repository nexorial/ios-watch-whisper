# Watch Whisper

用 Apple Watch 的表冠和屏幕按钮遥控 Mac 上的 Codex。原生 SwiftUI，独立 Watch App；无需 iPhone 伴侣 App。当前是首个可构建原型，真实手表 → 蓝牙 → Codex 联调仍待完成。

## 这版能做什么

- Mac 首次批准手表，通过加密 BLE 配对；保存后在手表 App 前台自动重连。
- 表冠上下滚动；按住说话，右滑锁定；短点开始／再点停止。
- 遥控 **Codex 自带听写**。声音来自 **Mac 当前麦克风**，手表不录音。
- 独立 Enter；收音中第一次 Enter 先停止，等 Codex 转写完成再点击发送。
- 断线不重发指令；5 秒心跳超时请求停止，录音最长 2 分钟。

**普通侧边按钮、表冠按压不能任意重映射。** 手表麦克风传音、自动 Enter、Wi-Fi 传输、后台持续遥控和 Mac 唤醒没有实现。Claude 仅有桌面目标的滚动／Enter 适配代码，未验证；Claude 听写明确禁用。

## 项目

| 路径 | 内容 |
| --- | --- |
| `Watch/` | watchOS 9+ 原生界面、BLE central、手势和表冠 |
| `Mac/` | macOS 13+ 菜单栏接收端、BLE peripheral、目标适配器 |
| `Sources/WhisperCore/` | 20 字节认证协议、重放保护、Keychain、手势和录音租约 |
| `Tests/WhisperCoreTests/` | 协议、篡改、重放、手势、表冠和失联保护测试 |
| `docs/RESEARCH.md` | 方案对比、苹果平台限制与 Codex 映射依据 |
| `docs/VALIDATION.md` | 实际验证结果及剩余真机检查 |

`WatchWhisper` target 是苹果要求的 iOS 分发容器，不含 iPhone 界面或应用代码。`WatchWhisperWatch` 是独立手表程序；开发时直接运行这个 scheme。

## 构建

需要 Xcode（当前验证版本 27.0）与 XcodeGen：

```sh
brew install xcodegen
./scripts/build.sh
```

或者打开 `WatchWhisper.xcodeproj`。默认签名团队为本机项目团队；其他开发者需在 Signing & Capabilities 中选择自己的团队，或构建时覆盖 `DEVELOPMENT_TEAM`。`project.yml` 是工程的源配置，修改后运行 `xcodegen generate`。

单独运行逻辑测试：

```sh
swift test --scratch-path /tmp/watch-whisper-tests
```

scratch path 放在 Documents 外，避免同步文件的扩展属性影响 XCTest 签名。

## 安装与试用

1. Mac 构建 `WatchWhisperMac`，或运行 `scripts/install-mac.sh 'Apple Development: Your Name (...)'`。安装到 `~/Applications/Watch Whisper.app`。
2. 打开 Mac App，在系统提示中允许蓝牙；点击「打开设置」，由你在系统设置允许 **Watch Whisper** 的辅助功能权限。Codex 自己还需要麦克风权限。
3. iPhone 与 Apple Watch 解锁并靠近 Mac。Xcode 的 Devices / Device Hub 里必须显示手表可用；如需要，连接 iPhone、信任此电脑，并按系统提示启用 Developer Mode。
4. 在 Xcode 选择 `WatchWhisperWatch` scheme 与真实手表运行。不需要先安装任何 iPhone App。
5. Mac 点「允许新手表 · 60 秒」，手表打开 App 后选择本机；确认系统蓝牙配对及 Mac 上的「允许这块手表」。首次操作完成后会保存配对。
6. 把 Codex 的任务窗口放在 Mac 前台，输入框可见，关闭其他输入面板。先试滚动，再试听写；确认文字后点手表 Enter。

Mac 上关闭面板不会退出接收端，菜单栏可以再次打开。Mac 当前麦克风可以是内置麦克风、AirPods 等系统音频输入；本项目不更改系统音频设备。

### 模拟器

蓝牙验证必须使用真机。手表启动参数 `--demo` 或连接页的「试用界面」可检查本地 UI；界面明确标记演示，不会控制 Mac。Mac 也支持 `--demo`，完全不启动蓝牙、不操作其他应用。

```sh
xcrun simctl install <WATCH_SIMULATOR_ID> '<BUILD_PRODUCTS>/Watch Whisper Watch.app'
xcrun simctl launch <WATCH_SIMULATOR_ID> com.nexorial.watchwhisper.watchkitapp --demo
```

## 故障排查

- 手表不出现：两端打开蓝牙并允许 App 使用；Mac 接收端保持运行，手表保持前台。模拟器不能证明蓝牙发现。
- 已配对但拒绝指令：两端移除配对后重配，检查 Mac Keychain 是否可用。密钥只存本地 Keychain，不提交到 Git。
- 找不到听写：确认 Codex 听写已启用，界面为中文或英文，当前任务输入框可见。不同版本的可访问性名称可能变化。
- Enter 不可用：先停止听写并等待转写，确认输入框非空、Mac 前台是所选 App；不会把 Return 发给其他进程。
- Codex 未确认启动／停止：立即在 Codex 检查录音状态。自动保护是尽力停止，不保证在目标 App 挂起或控件消失时能成功。
- 表冠滚错区域：收起侧边编辑器、终端和浏览器面板，让任务正文与单个输入框可见。真实 Codex 的坐标落点尚待真机确认。

## 协议

每台手表独立随机 256 位密钥，Mac 明确批准后通过要求链路加密的 GATT 特征读取。每次连接换 128 位随机 challenge。命令包含版本、操作码、单调序号、滚动值与 96 位 HMAC-SHA256；总计 20 字节，适配最小 BLE ATT payload。状态回执采用不同方向标记并认证。重复或旧序号拒绝执行，失联队列清空；写入成功不等于 App 执行成功，手表等待状态通知。

协议单元测试通过不代表已经验证真实无线链路、Apple 系统配对对话框、前台 App 的可访问性树或真实语音识别。
