# 验证记录

日期：2026-09-25。Xcode 27.0 / Swift 6.4 编译器（Swift 5 语言模式）；应用最低 watchOS 9 / macOS 13。

## 已通过

- `swift test --scratch-path /tmp/watch-whisper-tests`：**16 项测试，0 失败**。覆盖最小 BLE 包长度、全部指令／状态、字节篡改、不同密钥／连接挑战、方向反射、重复 Enter、手势锁定、表冠反向与超速、失联和最长录音租约。
- Mac Debug 构建通过；签名安装到 `~/Applications/Watch Whisper.app`，`codesign --verify --deep --strict` 通过。
- Mac 原生面板真实启动；演示开始／停止经 UI 操作，状态从「准备好了」→「Mac 正在听」→「准备好了」。这只证明演示交互。
- **Mac 真实模式**已启动 Core Bluetooth 服务并成功广播。UI 显示「等待已配对手表 · 蓝牙直连」。尚无新手表配对回执。
- watchOS Simulator 双架构构建、在 40mm 模拟器安装并启动成功。检查了最小屏幕布局，修复了顶部时间覆盖、底部说明被裁切的问题。[当前演示截图](images/watch-demo.png)。
- watchOS 真机构建及签名通过，包含 `arm64` 和 `arm64_32`。最终分发包装构建也通过；Mac 本地已有开发签名。
- 独立 Watch 配置经模拟器安装校验：`WKWatchOnly = true`，无 `WKCompanionAppBundleIdentifier`、无 `WKRunsIndependentlyOfCompanionApp`。
- iOS root target 是 Apple 自动生成的 Watch-only 分发 stub，未编写 iPhone App。尝试经已连接手机传递包装时，iOS 正确拒绝 `WatchOnlyAppContainerNotInstallable`；**未安装 iPhone App**。手表必须直接作为开发目标。

## 当前真实设备状态

- 用户当前 iPhone 已通过 USB 连接，Developer Mode 已开启。
- Mac 之前记录的 `Sihang’s Apple Watch`（Series 4）仍离线。用户已确认 **这不是现在使用的那块手表**；它的注册／签名情况不能作为当前手表可安装的证据。
- 用户已明确指定当前手表是 **Apple Watch Ultra 4**。本次重新检查 CoreDevice、Xcode 设备列表及附近开发配对服务，仍只发现已连接的 iPhone 和旧 Series 4 记录，没有 Ultra 4 真机。
- 用户确认 Ultra 4 上没有 Developer Mode 选项。Apple 官方说明指出，首次开发配对开始前该开关可能不存在。
- 已通过官方 `devicectl manage pair` 再次完成现有 iPhone 的开发配对，但 Ultra 4 仍未出现在设备列表。
- 已通过 Activity Monitor 正常退出并重新启动 Device Hub；新进程的电脑操作接口仍返回 `timeoutReached`，因此尚未能自动点击首次配对入口。已请用户在 Mac 完成「＋ → Pair Nearby Device… → Apple Watch」这一处操作，随后继续处理安装。
- 已在 macOS 系统设置实际读取并确认：Watch Whisper 的 Device Control and Data Access（辅助功能）开关为 on；Xcode 的 Local Network 开关也为 on。没有修改其他应用权限。

## 尚未验证，不能宣称完成

1. 当前真实 Apple Watch 的安装和启动。
2. Watch ↔ Mac 真机蓝牙发现、系统加密配对、丢包／重连与真实延迟。
3. Codex 上的实际 Accessibility 树、任务正文滚动落点、真实麦克风转写和 Enter 发送。
4. Claude 桌面版的滚动／Enter；没有适配 Claude 听写。

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
