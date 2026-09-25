# 0.3.0 本人内部测试

2026-09-25，用户明确批准创建必要 App Store Connect 记录、向 Apple 上传，并仅分配本人内部测试。

## 上传证据

- App：Watch Whisper，App Store Connect ID `6816016796`，Bundle ID `com.nexorial.watchwhisper`。
- Xcode Organizer 使用已有 Release 归档，选择 **TestFlight Internal Only**。分发日志确认 `testFlightInternalTestingOnly=true`、`destination=upload`。
- 2026-09-25 17:28:59（Asia/Shanghai）ContentDelivery 返回 `UPLOAD SUCCEEDED with no errors`；Xcode UI 独立显示 `WatchWhisper 0.3.0 (4) uploaded`。
- Upload ID：`9468b6bd-1030-4424-863c-380ae2dfc034`。
- 内部组 `James` 已创建，关闭自动分发；组内仅 1 位测试者，为账号持有人 Sihang Chen。没有外部测试组，没有提交 App Review。
- Build 4 在 17:29:24 的 Apple 通知中被拒绝：`ITMS-90683`，外层 `WatchWhisper.app` 缺少 `NSMicrophoneUsageDescription`。Watch 包本身已包含此说明，但 Apple 要求外层 Watch-only stub 也有。上传成功不代表处理成功。

## Build 5 修复

- 在 `project.yml` 的 Watch-only container 添加与 Watch 相同的用途说明，构建号递增为 5；功能代码未更改。
- `scripts/verify-export.py` 同时检查外层和 Watch 麦克风说明；对原 Build 4 正确报错，新 Build 5 导出通过。
- Release archive、App Store 导出、导出包 `codesign --verify --deep --strict` 通过，Mac 地址与完整证书摘要匹配。Mac 仍运行 0.3.0 (4)，协议和功能代码兼容本次配置修复。
- 本地 IPA：`artifacts/testflight-0.3.0-build5/WatchWhisper.ipa`，755717 字节，SHA-256 `7dfa7b9115dab4337a1a6fcfbe00f50c545aa0484cf237e820eb4123480810d9`。
- Build 5 于 17:37:57 上传成功，Upload ID `c07b63d8-af09-4166-a0f4-9a1f5363a9fe`；Apple 在 17:39:40 发出处理完成通知，网页独立显示 `Complete` 与 `Build 5 Internal`。
- 加密问卷按实际 Watch 包填写：URLSession/Security/CryptoKit 提供系统加密、证书验证和 HMAC/SHA-256，没有随 Watch 包交付自实现加密算法或第三方加密库，因此选择 `None of the algorithms mentioned above`（不属于问卷列举的专有或额外实现的标准算法）。参考 [Apple 系统加密豁免说明](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)。
- 合规信息保存后，构建由 `Missing Compliance` 变为 `Ready to Test`；加入 James 组后，刷新网页仍显示 **Testing / James / 1 invite**。邀请邮件已送达本人。
- 用户随后确认已安装，Mac 验证 `Wi-Fi 已连接 · 准备好了` 与 `已配对 1 块`。首轮实测听写能触发但未转写、正文未滚动；后续 Mac 修复和复测证据见 `VALIDATION.md`。

本机脱敏回执分别位于 `artifacts/testflight-0.3.0/upload-receipt.json` 与 `artifacts/testflight-0.3.0-build5/upload-receipt.json`。Xcode 从归档重新导出后上传，因此本地 IPA 的 SHA-256 只标识该本地文件，不冒充上传字节的哈希。

## Build 6 录音修复

- Watch 普通录音模式、系统静音检查、输入音量指示；Mac 精确音量、停止确认和转写错误识别。
- 36 项测试、Mac 构建与安装、Watch Release archive/export、实际包签名校验通过。原有配对与已通过的滚动实现保留。
- 本地 IPA `artifacts/testflight-0.3.0-build6/WatchWhisper.ipa`，796181 字节；SHA-256 `3af5c6da66b44693cddab84915537661daa33112a2fb30a1d744c21354ef8288`。系统加密豁免信息已写入内外层 Info.plist，证书摘要与 Mac 地址仍匹配。
- 23:09:29 上传成功，Upload ID `d29dd43e-f163-4525-9d86-7a2dbd638aba`；23:11:57 Apple 发出处理完成通知，网页显示 `Complete / Build 6 Internal / Ready to Test`。
- 已保存中文测试说明、加入 James 内部组；构建详情显示 `Group (1) / James / Internal / 1`。返回构建列表后独立核验 **Build 6 Internal / Testing / James / 1 invite**。新版本实际安装和语音转写仍待用户确认。

## 可用后安装与验收

1. 在与 Ultra 4 配对的 iPhone 上打开 TestFlight，将 Watch Whisper 更新为 **0.3.0 (6)**。Apple 对 Watch-only App 的说明是直接在 TestFlight App 列表中点 Install；不需要自建 iPhone 配套 App。
2. 保持 Mac 的 Watch Whisper 运行，核对 Wi-Fi 就绪地址。当前包默认 `192.168.31.99`，如地址变化，可在手表连接页修改；证书摘要仍固定为这台 Mac 的身份。
3. Mac 点「允许 Wi-Fi 手表」，手表打开 App；核对两端六位码一致后，在 Mac 批准。
4. 先验证真实认证连接与退出／重开后的重连，再由用户用表冠测试 Codex 正文滚动。
5. 允许 Watch 麦克风，按住说话后松开；核对 Codex 自动定位输入框并完成转写，文字保留待确认。随后单独测试手动 Enter、右滑锁定和中断停止。

工具不能直接控制 Codex；真实 Codex 行为需要用户操作手表确认。现有单元测试、TLS 集成测试和 BlackHole 输出测试不替代上述真机验收。

Apple 官方说明：[Watch TestFlight 安装](https://testflight.apple.com/)、[内部测试者与构建分配](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)。
