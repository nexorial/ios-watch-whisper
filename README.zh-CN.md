# Micodex

**用 Apple Watch 滚动 Mac 上的 Codex 对话、语音输入，再手动发送。**

免费、MIT 开源，使用原生 SwiftUI。手表负责表冠、按钮和收音，Mac 接收端通过辅助功能操作 Codex。无需 iPhone 配套界面。

[English / 完整文档](README.md) · [项目页](https://kiskir.dev/projects/micodex) · [隐私政策](https://kiskir.dev/projects/micodex/privacy) · [使用条款](https://kiskir.dev/projects/micodex/terms)

首个 App Store 版本正在准备，尚无公开商店下载。现在可以从源码构建。需要 watchOS 9+、macOS 15+（推荐 Wi-Fi 模式）、Codex Mac 版；语音输入还需要单独安装 BlackHole 2ch。

## 快速开始

```sh
git clone https://github.com/nexorial/ios-watch-whisper.git
cd ios-watch-whisper
brew install xcodegen
./scripts/build.sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

在 `Config/Local.xcconfig` 填写自己的 Apple 开发者团队 ID。使用不同团队时，也要将 `project.yml` 中的 Bundle ID 改为你的团队拥有的标识。运行 `xcodegen generate`，打开 `Micodex.xcodeproj`，分别运行 `MicodexMac` 和 `MicodexWatch`。

1. 两端连接可互访的局域网，Mac 接收端保持运行。
2. Mac 点“连接 → 复制连接码”，在手表连接页通过 iPhone 键盘粘贴完整内容，点“信任此 Mac 并连接”。只使用你自己 Mac 上复制的连接码。
3. Mac 点“允许 Wi-Fi 手表”，核对两端六位码后批准。
4. 在 Mac 系统设置中允许 Micodex 的辅助功能权限。打开 Codex 任务，转动表冠滚动正文。
5. 安装 [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole)，在 Mac 接收端设为听写输入。Codex 需使用 BlackHole 或系统默认输入；手表首次录音需允许麦克风。
6. 按住说话，松开停止；也可轻点开始/停止或右滑锁定。说话后约两秒安静会结束，最长两分钟。转写后检查文字，再点 Enter 发送。

选择 BlackHole 作为默认输入也会影响其他使用默认输入的 App；用完可切回原麦克风。显示 Wi-Fi 名称的定位授权是可选的，不读取或保存坐标。

## 隐私与限制

Micodex 的命令和音频通过固定证书的 HTTPS 在你的设备间传输，配对需明确批准。音频只在内存中短暂缓冲，不保存录音、不内置转写服务、不含广告或分析 SDK。Codex 自带听写可能按其服务条款将音频发送到云端；本项目不隶属于 OpenAI 或 Apple。

IP 改变时，在手表更新“Mac IP 地址”；更换 Mac 时用“设置另一台 Mac”重新导入连接码。不要因普通断线反复删除配对。Wi-Fi 推荐 macOS 15+；macOS 13+ 的蓝牙备用及 Claude 滚动/Enter 属于实验功能，Claude 听写禁用。

锁定录音利用系统后台音频能力，屏幕仍可能变暗，系统也可能中断。熄屏连续录音、松开停止和真实转写必须分别做真机验收。更多构建、故障排查与限制见 [英文 README](README.md)。
