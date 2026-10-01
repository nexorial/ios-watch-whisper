# Micodex

**用 Apple Watch 滚动 Mac 上的 Codex 对话、语音输入，再手动发送。**

免费、MIT 开源，使用原生 SwiftUI。手表负责表冠、按钮和收音，Mac 接收端通过辅助功能操作 Codex。无需 iPhone 配套界面。

[English / 完整文档](README.md) · [项目页](https://kiskir.dev/projects/micodex) · [隐私政策](https://kiskir.dev/projects/micodex/privacy) · [使用条款](https://kiskir.dev/projects/micodex/terms)

Mac 应用通过 Homebrew 或 GitHub Releases 安装。Apple Watch 端通过 App Store 安装；首个手表版本仍在等待截图及审核，目前尚未公开下载。推荐使用 macOS 15+ 和 watchOS 9+。

## Installation / 安装

### 1. Mac：用 Homebrew 安装

如果还没有 Homebrew，请先通过 [Homebrew 官网](https://brew.sh/) 安装，然后运行：

```sh
brew tap nexorial/micodex https://github.com/nexorial/ios-watch-whisper
brew install --cask nexorial/micodex/micodex
open -a Micodex
```

安装的是已经完成 **Developer ID 签名和 Apple 公证**的 Mac 通用应用，支持 Apple Silicon 和 Intel。普通用户**无需安装 Xcode、XcodeGen，也不需要 Apple 开发者账号**。此 Cask 由本项目维护，不属于 Homebrew 官方 Cask 仓库。

**Homebrew 会自动将 BlackHole 2ch 作为依赖一并安装，无需再输入第二条安装命令。** 系统安装器可能要求管理员密码和重启，请按提示完成后重新打开 Micodex。

### 2. Mac：下载 DMG 安装

下载 [Micodex 1.0（19）Mac DMG](https://github.com/nexorial/ios-watch-whisper/releases/download/mac-v1.0-19/Micodex-1.0-19-macOS-universal.dmg)。先退出旧接收端，打开 DMG，将 **Micodex.app** 拖到 **Applications（应用程序）**，推出磁盘映像，再从应用程序打开 Micodex。

包内应用保留了与 Homebrew 版相同的 Developer ID 签名和 Apple 公证票据。**DMG 容器本身未签名，也没有装订公证票据**，macOS 可能显示正常的下载确认提示。若出现安全阻拦，请勿关闭 Gatekeeper 或删除隔离属性来绕过。详见 [安装检查](docs/INSTALLATION.md#installation-checks)。

DMG 不会自动安装 BlackHole。手表语音输入需要另行安装 [BlackHole 2ch](https://existential.audio/blackhole/)，或运行 `brew install --cask blackhole-2ch`，按系统提示完成管理员授权和重启。原有 [Mac ZIP](https://github.com/nexorial/ios-watch-whisper/releases/download/mac-v1.0-19/Micodex-1.0-19-macOS-universal.zip) 仍保留供备用下载，同样需要单独安装驱动。

### Mac 设置：两种安装方式通用

首次打开时，Mac 应用会显示 **设置指南**，分四步完成：

1. **音频：**检查 BlackHole，点击按钮将其设为听写输入。
2. **权限：**开启 Mac 上 Micodex 的辅助功能权限、Mac 上 Codex 的麦克风权限、手表上 Micodex 的麦克风权限，并允许本地网络。定位仅用于显示 Wi-Fi 名称，是可选项。
3. **配对手表：**复制连接码，核对两端六位码后批准配对。
4. **试用：**实际测试表冠滚动和一句语音转写，再确认完成。

可以选择“稍后设置”，也能随时从 Mac 面板重新打开“设置指南”。向导会读取真实的本机状态，不会自动代替用户授予权限或切换默认麦克风。明确选择 BlackHole 后，其他使用系统默认输入的 App 也会改用它。

向导会在未检测到驱动时提供安装或重启指引。详见 [安装指南](docs/INSTALLATION.md)。

### 3. Apple Watch：从 App Store 下载

首个版本审核通过后，在手表上的 **App Store** 搜索 **Micodex**；英文商店名称为 **Micodex – Watch Remote**。免费，无订阅和内购，不需要开发者模式或 Xcode。

**当前尚未上架：**正在等待截图和 App Review。[App Store 目标页面](https://apps.apple.com/app/id6816016796) 会在正式发布后开放。安装 Mac 应用不会自动安装手表应用。

### 4. 配对并开始使用

1. 两端连接可互访的局域网，Mac 接收端保持运行。
2. Mac 点“连接 → 复制连接码”，在手表连接页通过 iPhone 键盘粘贴完整内容，点“信任此 Mac 并连接”。只使用你自己 Mac 上复制的连接码。
3. Mac 点“允许 Wi-Fi 手表”，核对两端六位码后批准。
4. 在 Mac 系统设置中允许 Micodex 的辅助功能权限。打开 Codex 任务，转动表冠滚动正文。
5. 按“设置指南 → 音频与权限”将 BlackHole 2ch 设为听写输入。Codex 需使用 BlackHole 或系统默认输入；手表首次录音需允许麦克风。
6. 点击开始录音，麦克风实际收音时震动两下并显示「请开始说话」；再次点击结束。停顿不会自动结束，最长两分钟，熄屏继续录音。顶部显示当前 Mac 线程名称。转写后检查文字，再点 Enter 发送。

选择 BlackHole 作为默认输入也会影响其他使用默认输入的 App；用完可切回原麦克风。显示 Wi-Fi 名称的定位授权是可选的，不读取或保存坐标。

### 更新和卸载

先结束听写并退出 Micodex，再更新：

```sh
brew update
brew upgrade --cask nexorial/micodex/micodex
```

卸载 Mac 应用：

```sh
brew uninstall --cask nexorial/micodex/micodex
```

常规更新和卸载会保留配对设置与 Mac 证书。清除这些数据的方法见 [本地隐私控制](docs/PRIVACY.md)。如果之前在 `~/Applications` 安装过开发版，请先退出旧版，只运行一个接收端。更多说明见 [安装指南](docs/INSTALLATION.md)。

## 从源码构建（开发者）

普通用户使用上面的 **Mac Homebrew 或 DMG + Watch App Store** 路径。只有开发、贡献或自定义构建才需要 Xcode、XcodeGen 和真机签名设置，完整步骤见 [英文开发者指南](README.md#build-from-source-developers)。

## 隐私与限制

Micodex 的命令和音频通过固定证书的 HTTPS 在你的设备间传输，配对需明确批准。音频只在内存中短暂缓冲，不保存录音、不内置转写服务、不含广告或分析 SDK。Codex 自带听写可能按其服务条款将音频发送到云端；本项目不隶属于 OpenAI 或 Apple。

IP 改变时，在手表更新“Mac IP 地址”；更换 Mac 时用“设置另一台 Mac”重新导入连接码。不要因普通断线反复删除配对。Wi-Fi 需要 macOS 15+；Claude 滚动/Enter 属于实验功能，Claude 听写禁用。

录音利用系统后台音频能力，屏幕仍可能变暗，系统也可能中断。熄屏连续录音、再次点击停止和真实转写必须分别做真机验收。更多构建、故障排查与限制见 [英文 README](README.md)。

Siri 的抬腕对话及语音唤醒可能中断录音；可在手表「设置 → Siri」中关闭相应开关，Micodex 无法修改这些系统设置。系统中断时会结束并发送已缓冲音频供 Mac 转写，不会自动发送消息。
