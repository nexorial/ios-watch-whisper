# 验证记录

日期：2026-09-25。Xcode 27.0 / Swift 6.4 编译器（Swift 5 语言模式）；应用最低 watchOS 9 / macOS 13。

## 当前状态：有真实收音与文字试用，松开停止仍在联调

### Build 8：锁定录音与滚动优化（Mac 已更新，Watch 尚未发布）

- 用户报告锁定后熄屏会丢失整段、表冠明显延迟。根因之一是所有非 active 场景都主动发送取消；滚动路径每个事件都扫描最多 6000 个 AX 元素，并同步重写诊断文件。
- 新增真实录音所需的 `UIBackgroundModes=audio`。Wi-Fi 锁定状态由连接层保留，熄屏／视图重建继续已有录音；普通按住进入后台时结束并转写，不自动开始新的后台录音。系统中断、路线离开内置麦克风或网络失败时，停止采集并请求保留 Mac 已收到的音频。保留 2 分钟上限和手动 Enter。
- 新增经原有 HMAC／重放门控的 `finishReceivedAudio`，允许在中断时转写已收到的部分；不把缺失音频伪造为完整录音。Mac 超时改为保留音频，停止确认超时明确要求用户检查，不再自动丢弃整段。
- 滚动缓存受 PID、窗口、窗口位置、编辑器位置、标题和短期限约束；每帧仍检查前台、窗口和落点所属 PID。短程插值有队列上限，反转丢弃旧方向，录音／发送／撤销配对时清空；Crown 步进细化，停止逐事件文件写入，TLS TCP 开启 no-delay。
- **43 项单元测试通过**，包含锁定熄屏策略、插值距离、反向、停止和积压上限；真实 TLS 配对／认证／重放／错误证书／撤销集成测试通过（demo controller，不操作 Codex）。Mac 构建及 Watch Release archive/export 通过；实际 IPA 已检查签名、后台音频模式、地址和证书摘要。
- 用户解锁后，Mac Build 8 已签名安装、独立核验版本并启动，原有 1 块配对保留。当前物理网络地址变为 `192.168.31.186`，监听端口 8766 已核验；已请用户修改手表的 Mac 地址，证书仍与交付包匹配，不需要重新配对。
- 20:29 再次上传仍返回 Xcode `Failed to Use Accounts`。已打开 Xcode Apple Accounts 的现有账号登录窗口，等待用户完成密码／验证。**Build 8 尚未上传成功、尚未分配或安装到真表；性能和熄屏行为尚无新版实机验收。** 本地归档与 IPA 保留，完成登录后继续原授权的本人内部测试分发。

watchOS 的常亮／唤醒时长由系统设置控制；没有使用已废弃的延长前台时间接口，也没有将遥控录音伪装为健身或冥想会话。参考 [Apple 显示设置](https://support.apple.com/en-ie/guide/watch/apd127ec93ac/watchos)、[后台录音支持](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/iPhoneOSKeys.html)、[前台时间设置](https://developer.apple.com/documentation/watchkit/wkextension/isfrontmosttimeoutextended)。

- **2026-09-26 连接恢复**：用户再次报告蓝牙错误 15。首次检查 Mac 没有 8766 监听；启动现有 Build 7 后，Wi-Fi 服务在 `192.168.31.99:8766` 就绪，当前已配对数量为 0。交付的 Build 7 地址／证书摘要与当前 Mac 匹配，系统入站防火墙未阻断。引导手表切回「使用 Wi-Fi 直连」，用户提供核对码后重新完成应用内配对；Mac 独立显示 **Wi-Fi 已连接 / 已配对 1 块**。没有改变证书或系统蓝牙配置。不能据此确认配对记录此前为何变空；松开停止测试仍待反馈。

- Build 6 实测已出现明显输入音量：11.3 秒峰值 3843、20.9 秒峰值 8855、14.4 秒峰值 10192（PCM16 满幅 32768）。最后一次日志记录 `finishDictation phase=ready` 和用户触发的 Enter；用户发来口述测试文字，同时指出松开后没有立即停止。此处不宣称所有录音或停止场景通过。
- 查到明确的手势状态问题：旧 UI 在每次非 listening 的主机状态变化时清掉 `fingerDown`，松开回调随后会被 guard 忽略；同一次按住移动还可能被误判为重新按下。
- **Build 7** 将物理按下／松开与异步回执分开，延迟的 ready / failed / transcribing 等状态不会吞掉松开；短按锁定、右滑锁定保留。松开同步停止 Watch 麦克风，立即显示「收音已停止」，尾音传输独立显示；延迟的 begin/listening 回执不能再把 UI 切回收音。
- Mac 对已请求停止、但仍在异步排空的 Codex 不再仅因超过 1 秒就报告失败；仍保留有界取消保护，识别到明确转写状态后结束录音租约。新增结束标记与播放排空耗时日志，用于区分收音、网络尾音与界面等待。
- **39 项测试通过**，包括全部主机状态穿插按住／松开、锁定期间延迟 ready，以及失败释放锁定的回归检查。Mac 构建／签名安装／启动与 Watch Release archive/export 实际包校验通过。Build 7 已通过 Apple 处理并向本人发出可测试通知；尚待更新后验证「松开后的第二句话不进入转写」。

## Build 6 收音与停止诊断

- 用户后续确认 **表冠已能上下滚动 Codex 正文**。保留该滚动实现，未再修改事件路由。
- 22:53–22:54（Asia/Shanghai）Mac 日志收到两次 `beginDictation`、音频与 `finishDictation`：分别为 **113464 / 238357 个采样（7.1 / 14.9 秒）**，UI 确认听写已启动，但两次峰值均四舍五入显示为 `0%`。用户确认没有转写文字。这证明控制和音频数据传输，不能证明数据里含有可识别的声音；也不能把取整的 0% 当作精确零。
- **0.3.0 (6)**：Watch 改用普通录音模式，并检查系统输入静音但不自动解除；复用经过测试的实际采样转换实现，新增手表输入音量提示。Mac 保留原始峰值、RMS、非零采样数量，避免很低音量被取整成静音。所有诊断只保留数值，不保存语音。
- Mac 结束听写会等待停止控件消失后再确认，未确认停止时保留超时取消保护；识别 Codex 的 `Retry dictation / 重试听写`，明确报告转写错误，不把重试旧音频当作新录音。
- **36 项测试通过**，新增实际 AVAudioConverter 的 16/24/44.1/48 kHz 转换和精确音量统计；Mac 构建、签名安装和启动通过。Watch Release 归档、导出、实际包签名／权限说明／Mac 证书摘要校验通过。Build 6 已上传并经 Apple 处理，网页独立确认 **Testing / James / 1 invite**；尚无新版真表语音转写成功的证据。

## Build 5 Mac 交互修复记录

- 用户确认经 TestFlight 安装后，Mac UI 显示 **Wi-Fi 已连接 · 准备好了 / 已配对 1 块**；随后接收到了表冠指令。此处支持真实 HTTPS 认证连接，不等于正文已移动。
- 用户实测反馈：Codex 听写能被触发，但没有转写；表冠上下转动没有滚动效果。Mac 也曾显示输入框定位失败，说明定位存在间歇性问题。
- 本轮 Mac 修复：等待可识别的任务编辑器；接受矮的空输入框；多个 ProseMirror 编辑器时结合唯一听写工具栏的位置选择，歧义仍拒绝。滚动改经系统事件流投递，并在投递前核对落点属于前台目标进程。
- Mac 播放队列由 1.5 秒调整为 3 秒，以容纳 Watch 在听写启动阶段缓存的音频；排空等待保持在 HTTPS 超时内。新增仅含秒数／峰值／操作阶段的诊断，不记录声音、转写文字或配对密钥。
- **32 项测试通过**，包含矮输入框、正文内写作编辑器、离屏编辑器、侧面板与歧义拒绝。Mac 构建、签名更新及实际启动通过，保留 1 块 Wi-Fi 配对；Watch 兼容构建通过，无需重新安装手表版本。真实正文滚动与转写仍待修复后复测，测试期间不通过电脑操作切换 Mac 窗口。

## 0.3 构建与分发历史

- 用户提供的真表截图确认 `CBErrorDomain 15`。本机 Apple SDK 将 15 定义为 `encryptionTimedOut`。Mac 日志在对应连接中记录超时断开，未收到 App 层的配对读取；不能仅据此认定配对密钥损坏。
- 用户明确批准一次 Mac 蓝牙关闭／开启。工具核验开关确实 off → on；MX 键盘和 MX Master 3S 均已恢复 Connected。用户随后确认仍是错误 15。
- 新增保持证书固定与显式批准的 HTTPS 路径，保留蓝牙加密配置。没有删除系统蓝牙配对、重置整机或关闭连接加密。
- **28 项单元测试通过**。`scripts/test-wifi-security.sh` 使用生产 TLS/配对/会话实现、独立测试凭据与 demo controller，通过错误证书拒绝、未批准设备拒绝、票据绑定、认证回执和重放拒绝；没有操作真实 Codex。
- **Mac / Watch 0.3.0 (4) 构建通过**。Mac 已签名更新并启动，UI 显示 `Wi-Fi 已就绪 · 192.168.31.99`。Watch 构建的地址与完整证书摘要已独立核验匹配本机身份。
- 真表安装先返回 **CoreDeviceError 4016 / unavailable**；随后设备恢复 available，安装通道仍返回 **RemotePairingError 1007 / CBErrorDomain 15**。当前手表最后确认安装的是 0.2.1 (3)，**0.3.0 尚未安装；真实 Watch HTTPS、收音和 Codex 控制仍未通过验收**。
- 已完成 Release archive 与内部 TestFlight 导出（0.3.0 (4)，755524 字节），验证导出包 Watch-only 结构、Mac 证书摘要匹配、不含私有身份，以及 `codesign --verify --deep --strict`。导出配置确认 `testFlightInternalTestingOnly=true`、`destination=export`。
- 用户已明确批准仅本人内部 TestFlight。App Store Connect 记录 `6816016796` 已创建；2026-09-25 17:28:59 Xcode / ContentDelivery 确认 **0.3.0 (4) 上传成功**，随后 Apple 在处理阶段以 **ITMS-90683** 拒绝外层分发包缺少麦克风用途说明。已补齐、递增为 Build 5，重新归档、导出、实际包与签名校验均通过；上传和处理结果见 `docs/TESTFLIGHT.md`。内部组 James 仅含账号持有人，关闭自动分发；没有发起 App Review。
- **0.3.0 (5)** 于 17:37:57 上传成功，17:39:40 收到 Apple 处理完成通知；网页显示 `Complete`。保存仅使用系统加密的问卷信息后，构建变为 `Ready to Test`；加入 James 组并刷新，仍显示 **Testing / James / 1 invite**。真表安装和实际控制功能仍待确认。
- 证据在本机 `artifacts/wifi-*`；TLS 私有身份仅在 App Support 的 0700 目录，未提交 Git。实现边界见 `docs/WIFI-TRANSPORT.md`。

## 0.2.1 蓝牙连接修复记录

- 用户反馈手表显示「暂时无法连接 Mac」，重新配对后仍失败。此文案对应 CBCentralManager 的 `didFailToConnect`，旧版丢弃了底层错误。
- 修复缓存 Mac 失败后仍无限重取旧记录的问题，失败后改为扫描新广播；重新配对创建新的 central manager，并忽略旧 manager／旧 peripheral 回调。收到认证心跳回执后才显示已连接。
- 增加 Mac 广播状态与「重新广播」按钮。蓝牙服务未准备好时，打开配对窗口不会再覆盖错误提示。Debug 连接日志有 100 条上限，不记录密钥、音频或任务文本。
- **24 项单元测试通过**，包括新增的缓存失效回退、旧连接失败不能覆盖新连接、重新配对后忽略已取消尝试。Mac 和 watchOS 真机构建通过。
- Mac 已签名更新并真实启动，UI 与调试日志都确认 `advertising=true`、GATT 服务注册成功。手表已安装、启动并独立查询到 **0.2.1 (3)**。
- 从真表取回的首份日志只有 `central state=5`（poweredOn）和开始扫描；尚无新版的 Mac 发现／连接请求／认证成功记录。Mac 当前配对数量为 0，等待用户在两端完成此次配对测试；**不能宣称当前连接问题或语音链路已解决**。
- 本轮开发安装一度出现 `RemotePairingError 1007 / L2CAP open channel failed`；暂停 Mac 接收端后安装成功。开发通道还出现间歇性的 1001 超时；并行运行限定时长的 `dns-sd -includep2p -includeAWDL -B _rp-tunnel._tcp local.` 时曾在 awdl0 发现服务并完成安装／读取日志。这些是成功操作时的条件，不据此认定唯一根因，也未删除系统蓝牙配对。
- 本机证据：`artifacts/ble-recovery-*`；Mac 日志 `~/Library/Application Support/WatchWhisper/connection-trace.log`；Watch App 沙盒内同名路径。详细日志不提交到 Git。

## 已通过

- `swift test --scratch-path /tmp/watch-whisper-tests`：**16 项测试，0 失败**。覆盖最小 BLE 包长度、全部指令／状态、字节篡改、不同密钥／连接挑战、方向反射、重复 Enter、手势锁定、表冠反向与超速、失联和最长录音租约。
- Mac Debug 构建通过；签名安装到 `~/Applications/Watch Whisper.app`，`codesign --verify --deep --strict` 通过。
- Mac 原生面板真实启动；演示开始／停止经 UI 操作，状态从「准备好了」→「Mac 正在听」→「准备好了」。这只证明演示交互。
- **Mac 真实模式**已启动 Core Bluetooth 服务并成功广播；后续 Ultra 4 已完成应用内配对和自动重连，当前证据见下方。
- watchOS Simulator 双架构构建、在 40mm 模拟器安装并启动成功。检查了最小屏幕布局，修复了顶部时间覆盖、底部说明被裁切的问题。[当前演示截图](images/watch-demo.png)。
- watchOS 真机构建及签名通过，包含 `arm64` 和 `arm64_32`。最终分发包装构建也通过；Mac 本地已有开发签名。
- 独立 Watch 配置经模拟器安装校验：`WKWatchOnly = true`，无 `WKCompanionAppBundleIdentifier`、无 `WKRunsIndependentlyOfCompanionApp`。
- iOS root target 是 Apple 自动生成的 Watch-only 分发 stub，未编写 iPhone App。尝试经已连接手机传递包装时，iOS 正确拒绝 `WatchOnlyAppContainerNotInstallable`；**未安装 iPhone App**。手表必须直接作为开发目标。

## 首次真机安装与连接（0.1）

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
