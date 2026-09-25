# Watch Whisper 第一版

## 目标与验收

独立 watchOS App + macOS 菜单栏接收端，无自建 iPhone 程序（仅 Apple 的分发 stub）。首次由 Mac 明确允许配对，之后手表启动时自动寻找已配对 Mac。Digital Crown 控制 Mac 的任务正文滚动；屏幕按钮控制 Codex 自带听写；按住说话，右滑锁定，再点停止；提供独立 Enter。用户在 2026-09-25 真机测试后明确要求使用 Watch 麦克风，并选择保留 Codex 内置听写。更新为 Watch 录音 → BLE 音频流 → BlackHole 2ch → Codex；不用 OpenAI API、不另做转写。Mac 麦克风方案已被替代。

默认手动 Enter，避免异步转写未完成时发送。第一版不自动 Enter。普通侧边按钮与表冠按压不重映射，离开前台停止听写，断线有超时保护。

## 实现边界

- watchOS 9 起，Mac 13 起。当前用户指定安装到 Apple Watch Ultra 4；旧 Watch4,2 记录不是目标设备。
- BLE：手表 CBCentralManager，Mac CBPeripheralManager。Mac 批准 + 加密特征读取交换每设备随机密钥；持久化到 Keychain。
- 固定 20 字节命令（兼容最小 ATT payload），HMAC-SHA256 截断 96 位，随机连接 challenge + 单调序号，拒绝重放和篡改；每条有认证状态回执。
- 收到写入回执不代表目标 App 已执行；成功执行之后才回传状态。连接/听写/错误在两端显示。
- Mac 使用公开 Accessibility 与 CGEvent 接口。仅允许选定目标，检查前台和主窗口。听写用实际控件的可访问性名称匹配，开始/结束独立命令，不盲目切换。
- Codex 自带听写入口来自安装包的静态检查；真机/真实 Codex 的运行时验证另记，不能用模拟测试代替。
- Claude 首版只作为可配置滚动/Enter 目标，未验证听写时明确禁用，避免冒充功能支持。

## 步骤

- [x] 检查设备、工具链、官方平台限制
- [x] 协议、手势状态机、重连及失联保护
- [x] Mac 蓝牙接收端和目标 App 适配器（真实 Codex 联调待验证）
- [x] Watch 原生界面、表冠和按钮
- [x] 16 项单元测试、双端构建、40mm 模拟器安装与界面验证
- [x] Mac 签名安装与真实蓝牙广播
- [x] 当前 Apple Watch Ultra 4 的 PIN 开发配对（watchOS 27.2）
- [x] 开发连接恢复，真表安装并启动，应用内 BLE 配对与一次自动重连
- [x] 依据用户实测移除滚动对输入框的依赖；增加 Codex 激活、编辑器聚焦与 Chromium AX 初始化
- [x] Watch 麦克风、认证音频分包、Mac BlackHole 输出；21 项逻辑测试和双端构建通过
- [x] 0.2.0 (2) 真表安装，Mac 接收端更新并保留配对
- [ ] 用户确认安装系统音频驱动，选择输入设备，允许 Watch 麦克风
- [ ] 复测正文滚动、自动聚焦、Watch 收音及 Codex 转写、手动 Enter、锁定和中断保护
- [x] 记录证据与缺口、Git 提交与推送到私有仓库
