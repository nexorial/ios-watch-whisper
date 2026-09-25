# Watch 麦克风接入 Codex

0.2 保留 Codex 内置听写。链路：Watch 内置麦克风 → 加密 BLE 音频流 → Mac Watch Whisper → BlackHole 2ch → Codex。

## 本机准备

1. 安装 [BlackHole 2ch 官方驱动](https://github.com/ExistentialAudio/BlackHole)。已准备的 0.7.1 安装包在本机 `artifacts/BlackHole2ch-0.7.1.pkg`。它是系统音频组件，安装需要管理员授权，安装器声明需要重启；由用户确认后执行。
2. 系统「声音 → 输入」选择 **BlackHole 2ch**。Codex 的音频输入选择默认输入或 BlackHole 2ch。其他使用默认输入的应用也会受到影响；使用完毕可切回原麦克风。接收端不会自动修改默认输入，也不会修改扬声器输出。
3. Mac Watch Whisper 点击「检查音频设备」，应显示 **Watch 音频 → BlackHole 2ch**。
4. 首次在 Watch 按住说话，确认系统麦克风授权。等「Watch 正在收音」出现后说话。
5. 松开后，音频队列播放完毕再结束 Codex 听写。先核对转写文字，手动点 Enter。

尚未安装驱动或路由不正确时，明确报错并停止；不回退到 Mac 麦克风。手表 App 需要保持前台，退到表盘会取消录音。

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
