# Watch 麦克风接入 Codex

保留 Codex 内置听写。0.3 链路：Watch 内置麦克风 → 固定证书的 HTTPS 音频流（BLE 备用）→ Mac Watch Whisper → BlackHole 2ch → Codex。

## 本机准备

1. 安装 [BlackHole 2ch 官方驱动](https://github.com/ExistentialAudio/BlackHole)。已准备的 0.7.1 安装包在本机 `artifacts/BlackHole2ch-0.7.1.pkg`。它是系统音频组件，安装需要管理员授权，安装器声明需要重启；由用户确认后执行。
2. 在 Mac Watch Whisper 点击 **「设为听写输入」**，或在系统「声音 → 输入」选择 **BlackHole 2ch**。Codex 的音频输入选择默认输入或 BlackHole 2ch。其他使用默认输入的应用也会受到影响；使用完毕可切回原麦克风。接收端仅在明确点击设置按钮时修改默认输入，不会因连接手表或开始听写而自动切换；不会修改扬声器输出。
3. Mac Watch Whisper 点击「检查音频设备」，应显示 **Watch 音频 → BlackHole 2ch**。
4. 首次在 Watch 按住说话，确认系统麦克风授权。等「Watch 正在收音」出现后说话。
5. 松开后，音频队列播放完毕再结束 Codex 听写。先核对转写文字，手动点 Enter。

尚未安装驱动或路由不正确时，明确报错并停止；不回退到 Mac 麦克风。手表 App 需要保持前台，退到表盘会取消录音。

Mac 面板保留最近一次录音的接收秒数和峰值，重新激活面板不会清除这些数字。仅是音频链路诊断，不保存音频或识别文字。首次 Wi-Fi 真机测试中听写已能触发但没有转写；后续修复输入框等待与启动音频队列上限，真实转写仍待复测。

Build 6 将 Watch 会话从 `measurement` 改为 `default`。Apple 说明 [measurement 会关闭部分动态处理](https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/measurement)；这提供了调整录音模式的依据，尚未证明它是本次无转写的唯一原因。系统输入静音时只提示用户，不自动解除。手表显示是否有输入音量；Mac 记录精确峰值、RMS 与非零采样数，以区分完全静音和低音量。松开后还会确认 Codex 停止控件消失，并识别转写重试状态。

## 安装包核验

- 来源：`https://existential.audio/downloads/BlackHole2ch-0.7.1.pkg`
- SHA-256：`57b540f27a3e29c37e310e01bee0fdfab76733087e47f997ef9dccf851400dcf`
- 签名：Developer ID Installer: Existential Audio Inc. (Q5C99V536K)
- 本机 `pkgutil --check-signature`：可信 Apple 签名及 notarization。

## 验收

- 不聚焦输入框时转表冠，对话正文上下滚动，输入框内容不滚动。
- 在另一个普通 App 前台开始录音，Codex 激活并自动聚焦当前任务编辑器。
- 对手表说话，Mac 接收秒数增长，Codex 生成文字；在 Mac 旁讲话、远离手表时不应替代 Watch 收音。
- 短按锁定和右滑锁定、松开停止、结束标记／尾音、手动 Enter 分别验收。
- 手表退后台、蓝牙中断、音频设备切换、两分钟上限：停止录音，不能自动发送。
- 安装、编码测试、蓝牙连通都不能代替以上端到端验收。

## Mac 虚拟通道实测

2026-09-25 重启后，系统已加载 BlackHole 2ch 0.7.1。用户授权后用接收端按钮切换，独立系统查询确认默认输入为 BlackHole 2ch、输出仍为 DELL U2718Q。

以下测试直接编译生产输出类，向 BlackHole 播放一秒 16 kHz 单声道测试音，并确认音频队列排空；不读取麦克风、不启动 Codex 听写：

```sh
bash scripts/test-audio-output.sh
```

实测返回 `PASS: 16000 mono samples routed to BlackHole and playback queue drained`。这只确认 Mac 定向输出及播放完成；真实 Watch 收音、BLE 音频流和 Codex 转写仍需设备验收。
