# Watch Whisper

用 Apple Watch 的表冠和屏幕按钮遥控 Mac 上的 Codex。原生 SwiftUI，独立 Watch App；无需 iPhone 伴侣 App。

当前 0.3 本机开发版采用 **HTTPS Wi-Fi 直连**，蓝牙保留为备用。**真表 Wi-Fi 连接与表冠滚动 Codex 正文已通过实测**，Build 6 已收到明显音量并有口述文字试用反馈。用户仍报告松开后停止不及时；Build 7 修复触摸状态被异步回执清除的问题，并区分停止收音与处理尾音，继续真机验证。进度见 [验证记录](docs/VALIDATION.md) 与 [TestFlight 记录](docs/TESTFLIGHT.md)。

Build 8 已完成锁定录音熄屏保留、断线保留已收音频和滚动缓存／短程平滑，43 项测试及双端构建通过；Mac 接收端已更新。当前等待 Xcode Apple 账号重新验证，**Watch 新版尚未发布或实机验收**。屏幕常亮仍由手表系统设置控制。

## 这版能做什么

- Wi-Fi 首次由 Mac 批准手表，两端核对六位配对码；开发安装时固定这台 Mac 的完整 TLS 证书摘要。保存后在手表 App 前台自动重连。
- 蓝牙备用保留加密配对、缓存失败后重新扫描与旧回调隔离。
- 表冠上下滚动；按住说话，右滑锁定；短点开始／再点停止。
- 使用 **Watch 内置麦克风**，通过 HTTPS 批量发送认证音频帧到 Mac 的 **BlackHole 2ch** 虚拟麦克风，继续使用 **Codex 自带听写**。不会回退到 Mac 麦克风；驱动和输入路由未就绪时明确报错。
- 开始听写会激活 Codex 并寻找、聚焦任务输入框；表冠滚动对话正文，不再以输入框识别成功为前提。
- 独立 Enter；收音中第一次 Enter 先停止，等 Codex 转写完成再点击发送。
- 断线不重发指令；5 秒心跳超时请求停止，录音最长 2 分钟。

**普通侧边按钮、表冠按压不能任意重映射。** 自动 Enter、后台持续遥控和 Mac 唤醒没有实现。Claude 仅有桌面目标的滚动／Enter 适配代码，未验证；Claude 听写明确禁用。

## 项目

| 路径 | 内容 |
| --- | --- |
| `Watch/` | watchOS 9+ 界面、HTTPS 主连接、蓝牙备用、手势和表冠 |
| `Mac/` | macOS 接收端、HTTPS（15+）、蓝牙备用（13+）、目标适配器 |
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
3. iPhone 与 Apple Watch 解锁并靠近 Mac，手表和 Mac 连接同一 Wi-Fi。先把 iPhone 通过 USB 连接 Mac 并信任此电脑。Device Hub 必须显示你的当前手表可用；如果未出现，点工具栏「＋ → Pair Nearby Device…」，选择左侧 iPhone／iPad／Apple Watch 图标组，保持「Waiting to pair」窗口打开。
4. 在手表「设置 → 隐私与安全性」开启 Developer Mode，按提示重启并确认。**首次配对前这个开关可能不存在，需先做上一步。** 随后在手表的 Developer Mode 页面向下滚动到 **Devices／设备**，选择你的 Mac，点 **Pair／配对**，再把 Mac Device Hub 显示的 PIN 输入到手表。单纯打开开关不会完成这次配对。iPhone 也需开启 Developer Mode。
5. 在 Xcode 选择 `WatchWhisperWatch` scheme 与真实手表运行。不需要先安装任何 iPhone App。
6. 通过 `scripts/install-watch.sh <WATCH_UDID>` 安装时会配置本机 Wi-Fi 地址和 TLS 证书摘要。Mac 点「允许 Wi-Fi 手表」，核对两端六位码，再点「核对一致，允许手表」。蓝牙备用需要在两端明确选择开启。
7. 安装并配置 [BlackHole 2ch](docs/WATCH-AUDIO.md)。在手表首次主动录音时允许麦克风。
8. 把 Codex 任务窗口放在 Mac 前台，先试正文滚动。按住说话时会自动定位输入框；等手表显示「Watch 正在收音」后说话。松开后等 Codex 转写，检查文字，再点 Enter。

当前目标设备是用户指定的 **Apple Watch Ultra 4**；Xcode 中旧的 Series 4 记录和 Ultra 4 模拟器都不能代替这块真机。首次配对的顺序见 [Apple Device Hub 官方说明](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub)，手表端选择 Mac 和输入 PIN 的过程见 [Apple WWDC26 演示](https://developer.apple.com/videos/play/wwdc2026/260/)（约 8 分钟起的配对演示）。

Mac 上关闭面板不会退出接收端，菜单栏可以再次打开。接收端只向 BlackHole 输出手表音频，不自动更改系统默认音频设备。为让 Codex 读取手表音频，需要由用户明确选择 BlackHole 作为输入；使用系统默认输入的其他 App 也会受到影响，使用结束后可改回原麦克风。

### 模拟器

蓝牙验证必须使用真机。手表启动参数 `--demo` 或连接页的「试用界面」可检查本地 UI；界面明确标记演示，不会控制 Mac。Mac 也支持 `--demo`，完全不启动蓝牙、不操作其他应用。

```sh
xcrun simctl install <WATCH_SIMULATOR_ID> '<BUILD_PRODUCTS>/Watch Whisper Watch.app'
xcrun simctl launch <WATCH_SIMULATOR_ID> com.nexorial.watchwhisper.watchkitapp --demo
```

## 故障排查

- 手表不出现：两端打开蓝牙并允许 App 使用；Mac 接收端保持运行，手表保持前台。接收端会显示是否正在广播，也可点「重新广播」。模拟器不能证明蓝牙发现。
- 连接失败：0.2.1 会显示系统错误域与错误码，先记录具体错误；无需仅因提示失败反复删除配对。开发版还会保留最近 100 条连接事件，不包含配对密钥、录音或输入内容。
- Xcode 已配对但安装报 tunnel timeout：先确认真表实际连接与 Mac 相同的 Wi-Fi 并已解锁，网络需允许设备互访。此时是开发安装通道失败，不要把配对状态当成安装成功；不要为排查而抹掉手表或解除它与 iPhone 的日常配对。
- 已配对但拒绝指令：两端移除配对后重配，检查 Mac Keychain 是否可用。遥控配对密钥存本地 Keychain；TLS 身份存储见 Wi-Fi 文档，私有身份均不提交到 Git。
- 找不到听写：确认 Codex 听写已启用，界面为中文或英文，当前任务输入框可见。不同版本的可访问性名称可能变化。
- Enter 不可用：先停止听写并等待转写，确认输入框非空、Mac 前台是所选 App；不会把 Return 发给其他进程。
- Codex 未确认启动／停止：立即在 Codex 检查录音状态。自动保护是尽力停止，不保证在目标 App 挂起或控件消失时能成功。
- 表冠滚错区域：收起侧边编辑器、终端和浏览器面板，让任务正文与单个输入框可见。滚动已经移除对输入框的强制依赖；实际正文落点仍需用户复测。

## 协议

每台手表独立随机 256 位密钥，Mac 明确批准后通过要求链路加密的 GATT 特征读取。每次连接换 128 位随机 challenge。命令包含版本、操作码、单调序号、滚动值与 96 位 HMAC-SHA256；总计 20 字节，适配最小 BLE ATT payload。状态回执采用不同方向标记并认证。重复或旧序号拒绝执行，失联队列清空；写入成功不等于 App 执行成功，手表等待状态通知。

协议单元测试通过不代表已经验证真实无线链路、Apple 系统配对对话框、前台 App 的可访问性树或真实语音识别。

### Watch 音频协议（0.2）

控制仍使用 20 字节原协议。新增独立音频 GATT 特征，要求 BLE 链路加密；16 kHz 单声道 IMA ADPCM 独立块按实际 ATT 容量切分。每块携带录音流 ID、序号、采样偏移和 HMAC，绑定连接 challenge；拒绝跨连接／跨录音重放。有限丢包补静音，超过半秒缺口或出现积压则停止。结束标记到达且 Mac 音频队列播放完后才请求 Codex 停止听写。音频仅保留在有界内存队列，不写录音文件，不调用转写 API。
