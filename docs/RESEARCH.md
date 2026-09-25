# Apple Watch 遥控 Mac：调查与选择

调查日期：2026-09-25。结论：第一版用 **独立 Watch App + 原生 Mac 接收端 + Bluetooth LE**。无需 iPhone App；iPhone 仍用于 Apple Watch 的系统配对和部分开发安装流程。

## 连接方式

| 方案 | 优点 | 限制 | 第一版 |
| --- | --- | --- | --- |
| Core Bluetooth：Watch 为 central、Mac 为 peripheral | 能按服务 UUID 发现附近 Mac；小指令适合 BLE；不依赖同一 Wi-Fi | 两端蓝牙授权、首次配对与 Mac 接收端；真机测试必需 | 采用，保存设备后前台自动重连 |
| URLSession HTTP/HTTPS 到 Mac | 普通 watchOS App 可使用；适合请求／响应 | 需地址发现或输入、局域网可达、证书与服务端；同 Wi-Fi 不保证能互通 | 可作为后续补充，未实现 |
| Network.framework / WebSocket / Bonjour | 可做双向连接、发现 | 普通 watchOS App 受低层网络限制；模拟器表现不代表真机 | 不作为普通遥控 App 的基础 |
| WatchConnectivity | Apple 官方手表与配对 iPhone 通信通道 | 不是 Watch 与 Mac 的直连通道，使用它会额外需要 iPhone 中转 | 不采用 |

Apple 文档允许独立 Watch-only App。项目中的 `WatchWhisper` iOS container 是分发包装，不含 iPhone 应用代码，也不向 iPhone 安装界面。手表实际程序是 `WatchWhisperWatch`。其 Info.plist 只声明 `WKWatchOnly`，不同时声明 companion identifier 或 independent-companion 键；模拟器安装器会拒绝这些互相矛盾的组合。

蓝牙的连接参数、后台调度由系统管理。这里只承诺前台发现和重连；没有通过假音频、假运动会话维持后台运行。Mac 休眠时不能保证连接，也没有实现远程唤醒。

## 按键与声音

| 操作 | 映射 |
| --- | --- |
| 旋转 Digital Crown | Mac 目标窗口任务区域的垂直滚动 |
| 按住屏幕麦克风 | 启动 Codex 听写，松开后停止并转写至输入框 |
| 按住并向右滑动 ≥ 44pt | 锁定收音，松开后继续 |
| 短点麦克风 | 锁定收音，再点停止 |
| 停止键 | 停止当前听写，不发送消息 |
| Enter | 收音中先停止；转写中禁用；就绪时聚焦非空输入框并发送 Return |
| 表冠按压／普通侧边按钮 | watchOS 保留，不能映射成任意遥控键 |
| 离开前台／断线 | 尝试停止，Mac 有 5 秒无心跳保护及 2 分钟录音上限 |

**第一版实际收音设备是 Mac 当前选择的音频输入。** 手表没有申请麦克风权限，不采集、不传输音频。Codex 自带听写仍由 Codex 处理；本项目不调用转写 API、不处理 Codex 凭据。若要求直接向手表说话，需要另做音频流与 Mac 虚拟麦克风（或改用转写服务）。尚未验证可通过公开接口把音频文件直接交给 Codex 内置听写，因此没有假设存在这种 API。

自动 Enter 未实现，保留明确的手动 Enter，避免异步转写完成时间不确定而误发。

## 本机 Codex 映射依据

静态检查安装包 `/Applications/ChatGPT.app`，bundle ID `com.openai.codex`，版本 `26.917.71314`。未读取用户会话或凭据。

- `composer.startDictation` 默认快捷键 `Ctrl+Shift+D`。
- `composer.dictation.aria`：`Dictate`／`听写`。
- `composer.dictation.cancel.aria`：`Stop dictation`／`停止听写`。对应 `stopDictation("insert")`，停止并插入文字。
- `composer.dictation.abort`：`Cancel dictation`／`取消听写`。
- 独立的 `Transcribe and send`／`转录并发送` **不用于停止按钮**。

适配器采用公开 Accessibility 的按钮名称和 AXPress；不会调用 Codex 私有 IPC，不修改 Codex 安装包。Enter 和滚动使用 macOS CGEvent，限定目标进程。必须让目标任务窗口在前台；无法唯一识别输入框时拒绝操作。已打开多个编辑面板、搜索框、终端或非中英文界面时可能需要收起面板或补充匹配。

官方 Commands / Features 页面在调查时未给出这些听写细节；上面的精确映射来自本机代码的静态检查，仍需用户在真实 Codex 中联调。工具明确禁止直接对 Codex 执行电脑操作，因此此次没有绕过限制去自动点击或发送测试消息。

Claude 仅预留桌面版的滚动／Enter 目标（`com.anthropic.claudefordesktop`），未做真实 Claude 验证；当前检测到的是 Edge PWA，不能声称已经适配。

## 官方资料

- [Creating independent watchOS apps](https://developer.apple.com/documentation/watchos-apps/creating-independent-watchos-apps)：Watch-only、分发 stub 和不依赖 iPhone 的要求。
- [TN3135: Low-level networking on watchOS](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos)：HTTP 高层网络可用，WebSocket／Bonjour 等低层能力的条件与真机验证要求。
- [CBCentralManager](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager)、[CBPeripheralManager](https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager)：扫描、广播、GATT 角色；watchOS 不支持 peripheral 广播，故采用 Mac 广播、Watch 扫描。
- [Digital Crown](https://developer.apple.com/design/human-interface-guidelines/digital-crown)：可接收旋转，按压留给系统。
- [Meet watchOS 10](https://developer.apple.com/videos/play/wwdc2023/10026/)：侧边按钮打开控制中心／Wallet。
- [Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity)：与配对 iPhone 的通信框架。
- [OpenAI / ChatGPT Commands](https://learn.chatgpt.com/docs/reference/commands)、[Features](https://learn.chatgpt.com/docs/features)：官方产品参考，未据此宣称存在音频注入 API。
