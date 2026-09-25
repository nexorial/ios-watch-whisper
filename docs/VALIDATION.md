# 验证记录

日期：2026-09-25。Xcode 27.0 / Swift 6.4 编译器（Swift 5 语言模式）；应用最低 watchOS 9 / macOS 13。

## 已通过

- `swift test --scratch-path /tmp/watch-whisper-tests`：**16 项测试，0 失败**。覆盖最小 BLE 包长度、全部指令／状态、字节篡改、不同密钥／连接挑战、方向反射、重复 Enter、手势锁定、表冠反向与超速、失联和最长录音租约。
- Mac Debug 构建通过；签名安装到 `~/Applications/Watch Whisper.app`，`codesign --verify --deep --strict` 通过。
- Mac 原生面板真实启动；演示开始／停止经 UI 操作，状态从「准备好了」→「Mac 正在听」→「准备好了」。这只证明演示交互。
- **Mac 真实模式**已启动 Core Bluetooth 服务并成功广播；后续 Ultra 4 已完成应用内配对和自动重连，当前证据见下方。
- watchOS Simulator 双架构构建、在 40mm 模拟器安装并启动成功。检查了最小屏幕布局，修复了顶部时间覆盖、底部说明被裁切的问题。[当前演示截图](images/watch-demo.png)。
- watchOS 真机构建及签名通过，包含 `arm64` 和 `arm64_32`。最终分发包装构建也通过；Mac 本地已有开发签名。
- 独立 Watch 配置经模拟器安装校验：`WKWatchOnly = true`，无 `WKCompanionAppBundleIdentifier`、无 `WKRunsIndependentlyOfCompanionApp`。
- iOS root target 是 Apple 自动生成的 Watch-only 分发 stub，未编写 iPhone App。尝试经已连接手机传递包装时，iOS 正确拒绝 `WatchOnlyAppContainerNotInstallable`；**未安装 iPhone App**。手表必须直接作为开发目标。

## 当前真实设备状态

- **Ultra 4 的开发连接已恢复。** 2026-09-25 本次查询为 `connected`，`xctrace` 也将 watchOS 27.2 的目标表列为在线。
- `scripts/install-watch.sh` 已完整执行成功：目标真机构建成功，`devicectl` 明确返回安装成功及启动成功。随后独立查询已安装应用，确认 `com.nexorial.watchwhisper.watchkitapp`，版本 **0.1.0 (1)**；进程查询也确认真表上的 App 进程正在运行。
- 新开发签名的 provisioning profile 已包含当前 Ultra 4，`codesign --verify --deep --strict` 通过。
- Mac 接收端真实 UI 显示「辅助功能已允许」。用户操作后，配对数量从 0 变为 **1 块**，随后一度显示「手表已断开 · 等待自动重连」。重新将真表 App 拉到前台后，Mac 显示 **「手表已连接 · 准备好了」**，确认保存配对后能够恢复实际通信。
- 「手表已连接」状态由 Mac 成功解码、认证并处理手表指令后更新；这次结果支持真机蓝牙通信与认证指令链路已打通，但不代表 Codex 听写、正文滚动或 Enter 已通过实测。已请用户在手表操作并反馈滚动／听写结果。
- 本次安装、应用查询和签名核验记录保存在本机 `artifacts/ultra4-connected-*`；先前准备的 TestFlight 文件保持原状，本次直接安装未经过 TestFlight 上传。

## 0.2 Watch 麦克风更新

- 用户实测 0.1 后报告：表冠滚动与听写都提示找不到输入框。用户明确要求滚动正文、自动定位输入框、使用 Watch 麦克风，并选择保留 Codex 内置听写。
- 0.2 移除滚动对输入框的硬依赖，增加目标激活、ProseMirror 优先匹配和 Chromium AX 初始化。实际 Codex 定位与正文落点尚待复测。
- 新增 Watch 麦克风、16 kHz ADPCM 音频传输和 Mac 定向 BlackHole 输出；没有调用其他转写服务。
- `swift test --scratch-path /tmp/watch-whisper-tests`：**21 项测试，0 失败**。新增语音频段编码误差、64/185/512 字节 ATT 包容量、每个字节篡改、跨连接／跨录音重放、缺帧恢复、结束边界、半秒缺口拒绝。
- Mac Debug、watchOS arm64 / arm64_32 真机构建均通过。Mac 已签名安装并重启，真实 UI 显示新增的「Watch 麦克风」区域，已有配对保持为 1 块。
- 真表已安装并启动 **0.2.0 (2)**，独立已安装应用查询确认版本。日志位于 `artifacts/watch-mic-*`。
- 官方 BlackHole **0.7.1** 安装包的 SHA-256 与 Homebrew Cask 一致，`pkgutil --check-signature` 确认 Apple 可信签名及 notarization。用户已完成安装和重启；重启后 `pkgutil` 与系统音频设备查询确认驱动已加载。
- 用户已明确授权安装及切换默认输入。原生命令行安装需管理员验证，后由用户在安装器完成安装并重启；本轮没有再次请求安装授权。
- System Settings 的电脑操作点击未可靠选中设备，因此新增接收端「设为听写输入」按钮，点击后独立系统查询确认默认输入 **BlackHole 2ch**、默认输出仍为 **DELL U2718Q**。Mac UI 显示「Watch 音频 → BlackHole 2ch」。
- 生产 `WatchAudioOutput` 硬件 smoke test 通过：**16000 个单声道采样定向输出至 BlackHole，播放队列正常排空**。具体命令见 `docs/WATCH-AUDIO.md`。日志在 `artifacts/virtual-microphone-smoke.log`。
- **完整 Watch 收音 → BLE 音频流 → Codex 转写链路仍未通过验收。** 已重新启动真表 App；Mac 保留 1 块配对，当前等待用户抬腕解锁、保持 App 前台并反馈正文滚动和实际语音结果。

## 已解决的开发连接阻塞与历史排查

- 用户指定的 **Apple Watch Ultra 4** 已完成 PIN 开发配对，CoreDevice 已识别到这块新表（Product Type: `Watch8,1`，watchOS **27.2**）。旧 Series 4 记录不是目标设备。
- 配对的关键一步已经补齐：Mac 保持「Waiting to pair」，再在手表 **Developer Mode → Devices → 选择 Mac → Pair**，把 Mac 显示的 PIN 输入手表；依据 Apple WWDC26 官方演示。
- 已执行 `scripts/install-watch.sh`，但在准备目标设备时失败。Xcode 报 `Timed out waiting for ... destinations ... to become available`；独立的已安装应用查询也返回 `CoreDeviceError 4000 / RemotePairingError 1001`：`Timed out while attempting to establish tunnel using negotiated network parameters`。
- 检查现有开发签名包的 provisioning profile，尚未包含这块新 Ultra 4。安装脚本已启用设备注册和自动签名，需要目标连接就绪后重新签名，不能用旧设备的签名包代替。
- 当时是 **开发配对已完成，调试网络通道未建立，App 尚未安装**。曾请用户确认手表实际连接与 Mac 相同的 Wi-Fi 并保持解锁；本次连接与安装结果已在上方更新。
- iPhone 已通过 USB 连接，Developer Mode 开启。Mac 的 Watch Whisper 辅助功能开关和 Xcode 本地网络开关均为 on。
- Mac Wi-Fi 的 IPv6 设置为 Automatic，存在 link-local IPv6 地址。用户明确同意后做了 **21 秒**的 Shadowrocket 对照测试：测试期间与恢复前均确认为 Disconnected，查询手表仍返回同一 tunnel timeout；随后恢复并确认 Connected。该测试没有改善连接，不据此认定 VPN 是根因。
- 已正常终止并重新启动当前用户的 CoreDeviceService，再查询手表应用，仍返回 CoreDeviceError 4000 / RemotePairingError 1001。
- 用户确认临时关闭 iPhone 蓝牙、让手表连接同一 Wi-Fi 后，已再次查询手表应用，仍返回同一调试通道超时；已请用户恢复 iPhone 蓝牙。Apple 网络选择说明：https://support.apple.com/en-gb/109319 。
- Mac 可以连接已发现的 iPhone 局域网开发服务 TCP 端口（79 ms），因此并非所有局域网设备通信都失败；这不证明手表路径可达。
- 当前 watchOS Developer Disk Image 的主机检查结果为 `contentIsCompatible: true`、`isUsable: true`；尚未成功挂载到这块手表，不能把该结果当成真机准备完成或绝对排除版本问题。
- 此前已请用户正常重启 Ultra 4、解锁并连接同一 Wi-Fi，保留已有配对；后续用户报告连接恢复，本次安装已成功，尚不能单凭先后顺序确定唯一根因。
- Device Hub 的电脑操作接口仍会超时；用户提供的配对弹窗截图可用于确认其当时状态。

## 尚未验证，不能宣称完成

1. Watch ↔ Mac 长时间稳定性、丢包、不同断线场景的重连与真实延迟；已完成的一次配对／前台恢复不能替代这些检查。
2. Codex 上的实际 Accessibility 树、任务正文滚动落点、真实麦克风转写和 Enter 发送。
3. Claude 桌面版的滚动／Enter；没有适配 Claude 听写。

电脑操作工具明确拒绝直接控制 Codex（`Computer Use is not allowed to use the app 'com.openai.codex' for safety reasons`）。没有改用其他工具绕过此限制。Codex 按钮名与快捷键来自安装包静态检查；实际联调需用户操作手表或在 Codex 手动确认。

## 真机验收顺序

- 新手表被 Xcode 识别后，以 `WatchWhisperWatch` scheme 运行；可使用 `scripts/install-watch.sh <WATCH_UDID>`，系统提示由用户确认。
- Mac 允许新手表，完成两端确认；关闭再打开手表 App，应自动重连到保存的 Mac。
- Codex 前台单个任务输入框可见，表冠分别上下转动，确认正文而不是侧面板移动。
- 按住说一句话后松开，Codex 完成转写但不发送。
- 向右滑锁定，松开后继续收音；再点麦克风／停止键结束。
- 转写后检查文字，点 Enter；只能发送一次，空输入框不发 Enter。
- 收音时放下手腕、退到表盘、关蓝牙，检查 Mac 是否停止；Mac App 无权限／目标窗口切换时检查错误提示。

详细构建和安装日志在本机 `artifacts/`，不把临时签名、设备识别信息或用户配对密钥上传到 Git。
