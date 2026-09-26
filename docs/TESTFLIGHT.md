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

## Build 7 松开停止修复

- 修复主机状态回执误清除物理触摸状态，防止松开被漏掉；立即停止本地 Watch 收音并显示尾音处理状态，拒绝延迟的 listening 回执把界面切回录音。
- Mac 保留异步停止确认和有界取消保护，增加尾音排空耗时诊断。39 项测试、双端构建、Mac 安装启动和导出包校验通过。
- 本地 IPA `artifacts/testflight-0.3.0-build7/WatchWhisper.ipa`，800485 字节；SHA-256 `5327f2985c88fa247e765617d0bb3ef575d5fcc6171319b42de2fb3e346cb7c1`。保持同一 Mac 证书、地址和配对。
- 23:33:48 上传成功，Upload ID `4e26c0ef-71e5-4ef8-a18d-b821c320555e`。Apple 于 23:35:35 通知处理完成。
- 已保存两句话验收说明并将 Build 7 加入 James 内部组；23:40:12 本人收到 Apple 的 `Watch Whisper 0.3.0 (7) ... is now available to test` 通知，正文包含已保存说明。新版已可内部测试；真表更新与松开后的结果待用户确认。

## Build 8 后台录音与滚动（未上传成功）

- 43 项单元测试、真实 TLS 安全集成测试、Mac 构建与 Watch Release archive/export 通过。
- IPA：`artifacts/testflight-0.3.0-build8/WatchWhisper.ipa`，831867 字节，SHA-256 `38109bf326b056d54647e77589577f43c7e68a280b5642f69d53c6bedcc3f935`。实际包签名、后台音频声明、同一 Mac 地址与证书摘要通过校验。
- 归档保留在 `/tmp/watch-whisper-testflight.8RXitN/WatchWhisper.xcarchive`。上传选项仍为 TestFlight Internal Only，目标仅 James 本人内部组。
- 2026-09-26 上传失败：`Failed to Use Accounts`，Xcode 无法取得有效 Apple 账号凭据；同时 Mac 锁屏导致电脑操作受阻。等待用户解锁后核验账号并重试。旧版 7 仍是最后确认可安装版本，不能把本地导出当作新版发布。
- 后续用户已解锁，Mac Build 8 完成签名安装及启动，保留配对。20:29 上传重试仍因账号访问失败而终止；Xcode 已打开本人 Apple 账号登录窗口，等待登录验证完成。运行中的 Mac 地址为 `192.168.31.186`，包内默认地址仍为 `.99`，手表需使用现有地址编辑功能保存 `.186`；证书摘要不变。

## Build 9 静音结束与 IP 显示（未导出／上传）

- 包含 Build 8 的后台录音与滚动改进，以及 Watch／Mac 两端的静音结束、迟到取消保护和清晰的 Mac IP 显示。
- 49 项单元测试、真实 HTTPS 音频／安全流程、Mac 构建、Watch Release 归档通过。归档：`/tmp/watch-whisper-testflight.u3XgNx/WatchWhisper.xcarchive`。
- 2026-09-26 21:07 导出失败：Xcode `No Accounts`，账号 keychain 凭据缺少 `Xcode-Username`；不能使用云端分发签名。归档签名可验证，但不等于分发签名或 TestFlight 可用。
- 归档中 Watch 的默认目标为当前 Mac `192.168.31.186`，证书摘要保持不变；已有 Watch 的手动地址覆盖会保留。
- 等待 Mac 解锁和 Xcode 原生 Apple 登录后，从该归档继续导出／上传 Build 9，仅分配已有 James 内部组。Build 8 不再单独发布；最后确认可安装的版本仍为 Build 7。

## Build 7 安装与验收

1. 在与 Ultra 4 配对的 iPhone 上打开 TestFlight，将 Watch Whisper 更新为 **0.3.0 (7)**。Apple 对 Watch-only App 的说明是直接在 TestFlight App 列表中点 Install；不需要自建 iPhone 配套 App。
2. 保持 Mac 的 Watch Whisper 运行，核对 Wi-Fi 就绪地址。当前包默认 `192.168.31.99`，如地址变化，可在手表连接页修改；证书摘要仍固定为这台 Mac 的身份。
3. Mac 点「允许 Wi-Fi 手表」，手表打开 App；核对两端六位码一致后，在 Mac 批准。
4. 先验证真实认证连接与退出／重开后的重连，再由用户用表冠测试 Codex 正文滚动。
5. 按住说第一句话后松开，随后说第二句话；确认手表立即显示收音停止，转写只包含第一句。尾音排空与 Codex 转写可能仍需短暂等待。文字保留待确认；随后单独测试手动 Enter、右滑锁定和中断停止。

工具不能直接控制 Codex；真实 Codex 行为需要用户操作手表确认。现有单元测试、TLS 集成测试和 BlackHole 输出测试不替代上述真机验收。

Apple 官方说明：[Watch TestFlight 安装](https://testflight.apple.com/)、[内部测试者与构建分配](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)。
