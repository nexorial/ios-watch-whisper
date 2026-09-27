# 加密 Wi-Fi 直连（0.3 本机开发版）

## 原因与保留的行为

0.2.1 真机已捕获 `CBErrorDomain 15 / encryptionTimedOut`。Mac 日志显示 Watch 作为 central 的连接进入底层加密前后超时，App 尚未收到 GATT 配对读取。用户授权的 Mac 蓝牙关闭／开启测试未改善；键盘和鼠标已恢复。继续保留蓝牙安全要求，不通过关闭链路加密来交换配对密钥。

原始需求允许 Wi-Fi 或蓝牙。新增 HTTPS 路径，保持独立 Watch App、表冠正文滚动、Watch 麦克风、Codex 内置听写、手动 Enter 和失联停止。蓝牙作为备用保留。

## 信任与配置

使用期间保持 Mac 的 Micodex 运行，手表选择「使用 Wi-Fi 直连」。若再次显示 `CBErrorDomain 15`，说明当前错误来自蓝牙路径，先切回 Wi-Fi 并检查 Mac 服务是否运行。2026-09-26 已按此路径恢复真实 Wi-Fi 连接；若 Mac 的应用内配对记录为空，需要重新核对两端六位码。

- Mac 使用本机生成的 TLS 身份，私钥只留在权限受限的 App Support 目录，不写入仓库或 Watch。
- 本机开发安装脚本把 Mac 地址与完整证书 SHA-256 公钥摘要配置到手表构建。Watch 只接受这个证书，并进行系统信任评估；不接受任意自签名证书。
- 初次配对由 Mac 开放有限时窗口；两端显示同一请求的六位核对码，用户在 Mac 明确批准。
- 每个请求带随机配对票据；批准后的共享密钥仅经已固定证书的 TLS 传输并存入双方 Keychain。非配对请求不能获取密钥。
- 后续会话继续使用随机 challenge、HMAC 命令／回执和重放防护。音频继续使用独立认证帧，HTTPS 批量发送。

## 实现与验收

- [x] 核实 watchOS 高层 URLSession 的使用边界
- [x] Mac TLS 身份、受限 HTTP 解析与配对／会话服务
- [x] Watch 证书固定客户端、控制与音频队列
- [x] 双端连接界面与本机开发安装配置
- [x] 协议、未授权访问、证书不匹配、分片请求和双端构建验证
- [x] 用户确认 TestFlight 安装；Mac 验证真实 Wi-Fi 配对与认证连接
- [x] 用户确认表冠可上下滚动 Codex 正文
- [ ] Watch 收音到 Codex 转写和 Enter 验收；数据已到达 Mac，但音量取整为 0%，Build 6 修复后待复测

## 已取得的证据与剩余限制

- `swift test --scratch-path /tmp/micodex-tests`：28 项测试通过。
- `bash scripts/test-wifi-security.sh`：真实 TLS/HTTP/配对服务通过本机集成测试，包括错误证书拒绝、关闭配对窗口、错误票据拒绝、认证会话／回执、重放拒绝和撤销后拒绝。使用独立测试凭据及 demo controller，不操作 Codex。
- Mac 和 Watch 0.3.0 (4) 构建通过。Mac 已签名更新并运行，原生 UI 显示 Wi-Fi 已就绪。手表包的地址与完整证书摘要已和当前 Mac 独立比对一致。
- 手表安装先返回 CoreDeviceError 4016 / unavailable；恢复 available 后，安装通道又返回 CoreDeviceError 4 / RemotePairingError 1007 / CBErrorDomain 15。尚未把 0.3.0 装到真表，真实 HTTPS、Watch 麦克风、滚动和 Codex 转写不能宣称通过。
- Release 归档和仅内部 TestFlight 导出完成。已核验 Watch-only stub、Mac 地址与证书摘要、无私有 TLS 身份，以及导出包代码签名。用户随后批准仅本人内部测试；Build 4 上传后被 Apple 以外层包缺少麦克风说明拒绝，已补齐并重新导出 Build 5。内部组 James 仅含账号持有人。上传、处理、分配与安装的分层证据见 `TESTFLIGHT.md`。

此版本的 HTTPS 需要 macOS 15+（进程内 TLS 身份导入）；蓝牙源码仍保留 macOS 13 基线。证书私钥和保护密码只在 Mac 的 `~/Library/Application Support/WatchWhisper/tls`，目录 0700、私密文件 0600，不写入仓库；Watch 只携带公开摘要。

本机安装脚本会自动准备证书与本机地址、把公开配置写到临时 xcconfig，然后签名构建。当前是绑定这台 Mac 的开发安装流程，还不是面向任意 Mac 的 App Store 配网流程。Mac 地址变化时可在手表连接页修改地址；完整证书固定仍然保持，不能自动信任新证书。更换 Mac 或证书时需要重新配置签名构建。

Build 9 在 Mac 面板和菜单常驻显示「Mac IP」，提供复制与空闲时刷新；手表明确显示「目标 Mac IP」，要填电脑地址而不是手表自身的地址。刷新保留已批准的设备密钥，使旧会话失效，并等待旧监听器取消后重建。认证音频还增加约两秒静音结束保护，已结束的录音不再追加播放迟到音频、取消已开始的转写。对应的真实 TLS 音频／刷新／重连测试使用 demo controller 和内存采样计数器，不操作目标 App。

Apple 的 [TN3135](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos) 将 URLSession HTTP/HTTPS 列为所有 watchOS App 都可用的高层网络 API；本实现不使用 Watch 的 NWBrowser 或 WebSocket。

## TestFlight 备选安装路径

本次已准备 `artifacts/testflight-0.3.0/WatchWhisper.ipa`（755524 字节），SHA-256：`a6d2c51d29a66003c9015c51f7ad9f2bbbfb8fe8df1c212b437f0ffb3bc1d4c5`。

后续可以用 `bash scripts/prepare-testflight.sh <新输出目录>` 重现准备流程；脚本只导出，不上传，并拒绝覆盖已有输出。用户已授权本次创建记录、上传及仅本人内部测试；此范围不包括外部测试者或 App Review。

## Build 12：接收服务恢复与网络指引

`EADDRINUSE`（错误 48）表示 Mac 无法占用接收端口，并不说明手表输入的 IP 错误。旧实现虽在手动刷新时等待取消，监听失败后却保留失败对象，导致后续 `start()` 被 guard 挡住，也没有后台自动恢复。

- 每个端口使用 OS advisory lock，避免 Micodex 多个进程 / 副本同时启动接收服务。进程退出或崩溃自动释放锁，遗留锁文件不会阻止下次启动。
- 保留同一个 cancellation handler，聚合重复 stop 的完成回调；完整取消 listener 后才丢弃旧对象和重新绑定。开启本地 endpoint reuse 以处理刚结束的 HTTP 连接。
- 失败后按 1、2、4、8、16、30 秒间隔重试；成功后重置间隔。后台每 5 秒检查局域网地址，空闲时自动重建服务。配对记录与证书身份保留，停止 / 失败不会误显示为就绪，未就绪不能开放配对。
- UI 明确区分接收端服务状态、两端各自的 Wi-Fi 名称、Mac IP 与手表保存的目标。错误提示给出下一步，不引导用户因暂时断线删除配对。
- Wi-Fi 名称使用 Mac CoreWLAN 和 Watch `NEHotspotNetwork.fetchCurrent`；仅显式点击后请求 Core Location 授权，不调用位置更新或读取坐标。Watch 包含 Access Wi-Fi Information entitlement；未授权、精确位置关闭或系统返回 nil 均显示明确原因。
- 自动化回归使用独立端口与测试凭据，覆盖 8 次连续 HTTP 重连、重复接收端、不可用时禁止配对、真实端口占用 / 释放后的自动恢复，以及重复 shutdown 后不会再次启动。不会操作 Codex 或修改生产配对。

第三方进程持续占用端口、路由器设备隔离、系统权限拒绝仍可能阻止连接；应用会明确显示问题，不承诺任何网络环境下永不失败。

Apple 文档：[macOS SSID 的定位权限要求](https://developer.apple.com/forums/thread/732431)、[读取当前 Wi-Fi 网络及权限要求](https://developer.apple.com/documentation/networkextension/nehotspotnetwork/fetchcurrent(completionhandler:))、[本地 endpoint reuse](https://developer.apple.com/documentation/network/nwparameters/allowlocalendpointreuse)。
