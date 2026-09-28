# 验证记录

> 当前产品已更名为 **Micodex**（Build 11）。以下历史上传／验证证据保留当时的应用名和原始文件路径。

## 2026-09-28 · 表冠速度修正与 Mac 滚动停顿（Build 15）

- 用户实测 Build 14 快速转动仍然过慢。旧映射仅 12–72 px/单位，且从 SwiftUI binding 更新间隔估速，没有取得真实表冠事件证据；上一轮逻辑测试通过不能代表手感达标。
- 改用 watchOS 9 起支持的连续 `DigitalCrownEvent.offset / velocity`，去掉 `by: 0.1` 的步进输入；按系统速度映射为 240–2880 px/单位，保留小于像素的累计、双向对称、反向立即生效、idle 清理和 600 px 队列上限。参考 [Apple DigitalCrownEvent](https://developer.apple.com/documentation/swiftui/digitalcrownevent)。
- 当前 Mac 日志记录每约 3 秒重新定位滚动目标，单次耗时约 0.5–1.3 秒。取消已验证区域的固定 3 秒过期；继续检查前台 PID、窗口身份／标题／几何、编辑器及滚动区几何和落点所属进程，失效时重新定位。没有可靠几何的回退仍保留短期限。诊断增加实际输出像素数；Watch 仅在 idle 写累计输入／峰值速度，不逐事件写文件。
- 64 项 Swift 测试、英中资源检查及 Mac / Watch Simulator 构建通过。新增独立 `MicodexCrownUITests` scheme，计划对慢转／快转各半圈比较实际回调与距离；常规 Watch 构建／安装不运行该测试。
- **本次表冠 UI 自动测试未执行成功**：watchOS 27 模拟器中的 `MicodexWatchUITests-Runner` 在连接 XCTest 前因 scene-create watchdog (`0x8BADF00D`) 被系统终止，用户看见的 Runner 报错与此对应。报告主线程处于 UIKit / PepperUICore / WatchKit 建立界面路径，未执行 Crown 测试；不能由此归因于滚动映射，也不能宣称真表主程序崩溃。测试已结束，目标模拟器已关闭，未反复重试。
- Mac Build 15 已签名安装并启动；原生 UI 显示辅助功能允许、Wi-Fi 接收端就绪和 BlackHole 输出。Ultra 4 的 Build 15 签名构建与 `devicectl` 安装成功，但启动被系统以 `Locked` 拒绝；随后独立已安装版本查询在 20 秒超时，尚无此次真表运行版本和速度反馈。需用户解锁并打开 Micodex，不能将安装成功视为启动或手感验收。

## 2026-09-28 · 表冠随转速加速（Build 14）

- 表冠由固定 22 px/单位改为按手表本地单调时钟计算转速：慢转 12 px/单位，随速度连续增加至最高 6 倍倍率；约 40 ms 平滑加速，减速立即回落。停顿 250 ms、反向、离开遥控页面会清除加速或残余位移。
- Wi-Fi / BLE 待发滚动合并时，反向会丢弃旧方向的积压，避免快速翻动后的小幅反向被吞掉；每包及 Mac 插值队列仍限制在 600 px，保留现有 Mac 平滑滚动与目标保护。
- 64 项 Swift 测试通过，覆盖相同转动量在不同速度下的距离、双向对称、减速／停顿／反向恢复、细微累计、30/60/120 Hz 回调一致性、异常时钟／回绕、队列反转和插值停止。331 条英中翻译与 330 个源码键检查通过。
- watchOS 模拟器与双架构真机签名构建通过；Ultra 4 安装、启动成功，独立设备查询确认 **0.3.0 (14)** 及运行中的进程。证据为本机 `artifacts/micodex-build14-installed-app.json`、`artifacts/micodex-build14-processes.json`；构建／测试日志为 `/tmp/micodex-crown-{tests,simulator,install}.log`。本次仅需更新手表，现有 Mac 接收端兼容像素指令。
- 真表慢转、快转、急停和反向时的实际手感仍需用户操作验收；自动测试不代表物理表冠手感验证。

## 2026-09-27 · Device-language UI (Build 13)

- Added 331 English/Simplified Chinese catalog entries, native SwiftPM localization resources, and localized InfoPlist permission prompts for Mac, Watch, and the Watch-only distribution container. English is the development/fallback language. Each app uses its own device/app language without writing a global setting or a user-specific override.
- Localized UI labels, accessibility text, connection/recovery states, microphone feedback, and errors. Preserved device names, SSIDs, addresses, protocol identifiers, pairing data, and English/Chinese Codex accessibility matching labels.
- Added structured `LocalizedMessage` metadata to Wi-Fi replies while retaining the legacy rendered message. New Watch builds localize messages on receipt instead of inheriting the Mac’s UI language. Message formatting validates argument counts and only permits string/escaped-percent directives.
- 57 Swift tests pass, including English/Chinese/fallback selection, cross-language JSON reply rendering, old reply compatibility, and unsafe-format rejection. The catalog checker verifies source coverage and placeholder parity. Real HTTPS recovery/security/audio regression also passes.
- Mac, Watch Simulator, and the Watch-only Release distribution container builds passed. The outer container also includes both localized permission files. Watch screenshots show English on the 40mm simulator and Chinese on Ultra; the installed Mac UI was independently observed in English under the user’s existing English preference, with the current Wi-Fi name/IP still displayed. System language was not changed.
- Both device packages are Build **0.3.0 (13)** and include English/Chinese UI resources and permission prompts. The Mac update was signed/installed/launched. The physical Watch install and launch returned success; independent live queries confirmed Build 13 and the running Micodex process (PID 930), recorded in `artifacts/micodex-build13-installed-app.json` and `artifacts/micodex-build13-processes.json`. Simulator language/layout checks do not substitute for a physical Watch screenshot.
- Evidence: `artifacts/micodex-build13-{tests,security,mac,sim,install-mac,install-watch}.log`, `artifacts/micodex-build13-ui/watch-{en-small,zh}.png`. No TestFlight upload.

## 2026-09-27 · Wi-Fi 服务自动恢复与两端网络指引（Build 12）

- 修复 Mac 监听失败后仍保留失效 listener、没有自动恢复的问题。单接收端文件锁、完整取消后重绑、endpoint reuse、退避重试与每 5 秒检查 IP 共同处理重复接收端、短暂端口占用与网络变化；未就绪不能开放配对。
- 两端分别读取并显示自己的 Wi-Fi 名称，未授权或系统未返回名称时显示原因。Mac 用 CoreWLAN；Watch 用 `NEHotspotNetwork.fetchCurrent` 和 Access Wi-Fi Information entitlement。仅请求授权，不读取位置坐标。Mac hardened runtime 的定位 entitlement 同时加入项目和安装脚本的实际 codesign 参数，并在安装前验证，避免有用途说明却无法弹出权限请求。
- 明确提示手表输入 Mac 面板的「Mac IP」，增加地址格式校验和三步连接说明。首次配对与日常自动连接分开，连接失败不会要求清除已有配对。
- **53 项单元测试通过**。HTTPS 集成回归通过，新增 8 次连续刷新、重复接收端排他、未就绪禁止配对、真实 `EADDRINUSE` 后自动恢复、重复 shutdown 不重启；原有配对、认证、证书固定、重放和音频结束回归全部通过。
- Mac / Watch Simulator 构建、真表签名构建通过。Xcode CLI 首次因账号和旧 profile 缺少 Wi-Fi 能力失败；用户验证账号后，通过 Xcode Signing & Capabilities 自动更新 profile，后续构建通过。真表安装首次遇开发隧道超时，保持 AWDL 服务发现后重试成功，**没有卸载或重新配对**。
- 已安装并启动双端 **0.3.0 (12)**。独立真表应用清单确认 Build 12，进程确认 `Micodex Watch.app/Micodex Watch`（PID 920）。Mac 实际签名含定位 entitlement，运行端口只有一个接收进程；UI 曾确认原配对手表自动连接，定位授权后实际显示当前 SSID。
- 本次随后观察到 Mac 局域网地址变化，最新 UI 显示新 IP 与「Wi-Fi 已就绪 · 等待手表」；手表仍需使用 Mac 当前显示的 IP。未将之前网络上的连接证明当作新网络已重连。Watch 名称读取功能已签名安装，其授权后的具体 SSID 显示仍待用户在真表确认。
- 证据保存在 `artifacts/micodex-build12-*`：`tests.log`、`security.log`、`install-mac-authorized.log`、`watch-install.json`、`watch-launch.json`、`installed-app-verified.json`、`processes-verified.json`；失败日志保留，未上传 TestFlight。

## 2026-09-27 · Micodex 已替换真表旧版

- 按用户要求原位更新 Apple Watch Ultra 4，保留原 Bundle ID 和配对身份；没有卸载 App 或移除配对。
- `scripts/install-watch.sh` 完成签名构建、安装和启动。随后独立查询真表应用清单，确认 **Micodex 0.3.0 (11)**；进程查询确认 `Micodex Watch.app/Micodex Watch` 正在运行（PID 912）。
- 本机证据：`artifacts/micodex-build11-install-watch.log`、`artifacts/micodex-build11-installed-app.json`、`artifacts/micodex-build11-processes.json`。安装和运行已确认；本次未进行真实听写／表冠验收，未替换 Mac 接收端或上传 TestFlight。

## 2026-09-26 · Micodex 亮紫色与界面精简（Build 11）

- 品牌、Mac / Watch 显示名、菜单、权限提示、蓝牙广播名、Xcode 工程 / schemes、Swift package 和构建脚本统一为 Micodex。历史安装身份、Keychain 服务、TLS 身份目录、HMAC 协议域保持不变，支持与旧版设备配对兼容。
- Mac 使用 420 × 550 pt 紧凑面板：当前操作、目标、Mac IP、音频与辅助功能状态常驻，详细配对、音频配置和蓝牙备用按需展开；展开内容在面板内滚动。录音时底部常驻停止入口。
- Watch 使用紫色语音主操作、独立停止与 Enter，移除重复状态与默认展开的长说明；保留原有按住、短点、右滑锁定、表冠滚动、转写禁用 Enter 和 VoiceOver 操作。
- 双端新增亮紫色 accent 与统一麦克风 / 代码括号图标。Mac 颜色随系统深浅模式切换；已实际观察深色面板和展开 / 收起、演示开始 / 停止状态。浅色未取得实际截图验证。
- 51 项 Swift 单元测试通过；真实本机 HTTPS 集成测试通过（配对、认证、重放、静音结束、迟到命令、网络刷新、错误证书、撤销）。本轮没有将 UI 演示当作真实听写证明。
- Mac Debug、Watch Simulator、Watch 真机签名 Debug 和 iOS Watch-only 分发容器 Release 构建通过。实际包名均为 Micodex，版本 0.3.0 (11)；Watch 签名校验通过，内置证书摘要与现有 Mac TLS 身份一致。
- 已检查 Ultra 4 / 40mm SE 3 模拟器布局，截图在 `artifacts/micodex-ui/watch-{ultra,small}.png`；本机日志在 `/tmp/micodex-{build,security,mac-final,sim-final,device-build,container-build}.log`。
- 旧 Mac 接收端当前仍显示未确认结束的听写，尚未重启或替换。新 Mac 签名包准备于 `artifacts/micodex-ui/prepared/Micodex.app`，Watch 真机包准备于 `/tmp/micodex-device/Build/Products/Debug-watchos/Micodex Watch.app`。待用户确认录音空闲后安装；本轮未上传 TestFlight 或修改 App Store Connect 的名称。

日期：2026-09-25。Xcode 27.0 / Swift 6.4 编译器（Swift 5 语言模式）；应用最低 watchOS 9 / macOS 13。

## 当前状态：有真实收音与文字试用，松开停止仍在联调

### Build 10：补齐蓝牙锁定熄屏保护（2026-09-26）

- 用户再次报告右滑锁定后熄屏丢失声音。此前 Build 8/9 的 Wi-Fi 后台修复尚无真表安装证据；本轮检查还发现蓝牙未保存锁定状态，非 active 直接停止并清除采样。
- 蓝牙现在保留锁定录音与心跳，普通录音退后台正常结束；等待尾音/停止确认时拒绝重复结束，迟到的开始回执不能恢复收音显示。切换传输方式仍明确停止原录音。中断、积压、音频编码/解码失败和断开改为请求保留 Mac 已收到的音频，未送达的部分不宣称可恢复。
- Wi-Fi 后台结束收音时明确结束当前连接。显式启用常亮显示支持并补充手表设置说明，未尝试强制全亮或覆盖系统设置；真实后台录音继续使用 `UIBackgroundModes=audio`。
- **51 项单元测试通过**，包含重复 inactive/background 通知下的结束状态和视图重建后首次点击停止原录音。真实 TLS/HMAC 音频流程回归通过，覆盖静音结束、迟到 cancel/release/audio、新录音和重连。
- Mac Debug 与 Watch arm64/arm64_32 构建通过。Watch 实际签名包已核验 **0.3.0 (10)**、后台音频、常亮支持、目标地址和既有证书摘要配置。`scripts/install-watch.sh` 明确返回真表安装成功与启动成功；后续独立 `devicectl device info apps` 查询也确认真表安装版本为 **0.3.0 (10)**。
- Mac **Build 10** 已签名安装并启动，保留 1 块配对和 BlackHole 路由。首次启动遇到临时端口占用，点击「刷新网络」后原生 UI 显示 Wi-Fi 已就绪。没有上传或分发新的 TestFlight 构建。
- 已请用户实测右滑锁定、放下手腕继续说话、抬腕停止；**安装和策略测试不能代替真表熄屏期间持续收音的验收**。
- 本机证据：`artifacts/locked-recording-build10-{tests,mac,security,install-watch,installed-app-retry}.log`。首次独立查询曾遇开发隧道超时；同目录 `installed-app.log` 保留失败记录，`installed-app-retry.log` 为保持开发服务发现时取得的安装版本证明。

### Build 9：静音停止与 IP 显示（2026-09-26，待安装／发布）

- 用户再次反馈松开后持续录音，并要求说完安静两秒自动结束；同时指出 Mac IP 缺少独立显示。最新截图中的 `.99` 是目标 Mac 地址，当前 Mac 实际地址为 `192.168.31.186`。两设备自身的 IP 不应相同，手表保存的目标应与 Mac IP 一致。
- Watch 对实际 16 kHz PCM 做 20 ms 窗口能量检测：连续声音 60 ms 后启用约两秒静音结束；初始没有声音则八秒结束。门限随已检测的声音能量有限调整，不存录音、不另做 ASR。停止本地麦克风后发送尾音与完成命令；界面基于采集状态显示，迟到的手势不会假显示仍在录音。较吵环境下的语音／背景区分仍需实测，手动松开／停止保留。
- Mac 对已认证的 Wi-Fi 音频也做同样保护，兼容旧 Watch。开始结束操作后拒绝追加至播放队列，迟到的 release／cancel 只返回状态，防止取消正在生成的转写；新录音重置状态。仍保留音频 HMAC、录音流与重放检查。
- Mac 面板和菜单常驻显示 IP，可复制并在空闲时刷新监听；激活面板时若地址变化，空闲时自动重新绑定，保留密钥与配对。刷新等待旧监听器真正取消才重建，避免端口仍占用；真实 TLS 重启与重新认证测试通过。手表连接页明确「目标 Mac IP」和已保存的地址。
- **49 项单元测试通过**。生产 TLS／HMAC／音频解码流程测试通过，覆盖静音结束、迟到取消／松开／音频、结束后新录音、正常手动结束及原有证书／重放／撤销检查；测试使用 demo controller 和内存采样计数器，不操作 Codex、不输出测试音频。
- Mac Debug 构建通过。Watch Release 归档成功，归档签名、两层麦克风用途说明、后台音频、当前 `.186` 地址与原证书摘要已独立校验。
- Xcode 导出报 `No Accounts`，凭据错误为 `missing Xcode-Username`；没有新的 TestFlight IPA 或成功上传。电脑操作工具同时明确返回 Mac 锁屏，待用户解锁后安装接收端、在 Xcode 完成 Apple 登录；没有绕过锁屏。新版自动停止、IP 版面、锁定熄屏和滚动仍需实际设备验收。
- 本机日志：`artifacts/silence-ip-build9-{tests,mac,security}.log`、`artifacts/testflight-build9-prepare.log`。Watch 归档：`/tmp/watch-whisper-testflight.u3XgNx/WatchWhisper.xcarchive`。

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
