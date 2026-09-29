# Micodex

**Scroll, dictate, and send in Codex on your Mac — from your Apple Watch.**

Micodex is a free, open-source native Watch remote and Mac receiver. Turn the Digital Crown to scroll a conversation, speak into your Watch, then review the transcription on your Mac and tap Enter when you are ready.

[简体中文](README.zh-CN.md) · [Project & setup](https://kiskir.dev/projects/micodex) · [Privacy](https://kiskir.dev/projects/micodex/privacy) · [Terms](https://kiskir.dev/projects/micodex/terms) · [Report an issue](https://github.com/nexorial/ios-watch-whisper/issues)

> **Availability:** the Mac app is available through Homebrew and GitHub Releases. The Apple Watch app will be installed from the App Store; its first release is still awaiting screenshots and App Review. The Watch download is not live yet.

## What it does

- **Crown scrolling:** scroll the Codex conversation body, with faster movement as you turn faster.
- **Watch dictation:** hold to talk, tap to toggle, or swipe right to lock recording. Release or Stop ends capture; about two seconds of silence after speech also stops it. Recordings are limited to two minutes.
- **Deliberate sending:** transcription stays in the editor. Enter is a separate action; Micodex does not automatically send your words.
- **Private local connection:** pinned HTTPS over your local network, explicit pairing approval, authenticated commands, and replay protection. Bluetooth is an optional fallback.
- **Native interface:** SwiftUI, bright purple controls, and independent English / Simplified Chinese localization on each device.

Micodex routes audio to **Codex's own dictation**. It does not include a transcription model, call a transcription API, or store recordings. Codex may send audio to its own services under its own settings and policies. Micodex is an independent project, unaffiliated with OpenAI or Apple.

## What you need

| Component | Requirement |
| --- | --- |
| Apple Watch | watchOS 9 or later; a physical Watch for microphone and wireless testing |
| Mac | macOS 15 or later for the recommended Wi-Fi connection; macOS 13+ supports the experimental Bluetooth path |
| Codex | The Mac desktop app, with dictation available and microphone permission enabled |
| Audio | [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole), installed separately, for Watch dictation |
| Network | Watch and Mac on a local network that allows devices to reach each other |

The Watch app is standalone. Apple uses an iOS distribution container for it, but Micodex has **no iPhone companion interface**. An iPhone can assist with Watch installation and keyboard input.

## Installation

### 1. Mac — Homebrew

Install [Homebrew](https://brew.sh/) if you do not already have it, then run:

```sh
brew tap nexorial/micodex https://github.com/nexorial/ios-watch-whisper
brew install --cask nexorial/micodex/micodex
open -a Micodex
```

This installs a **prebuilt, Developer ID-signed and Apple-notarized Mac app** for Apple Silicon and Intel. You do **not** need Xcode, XcodeGen, or an Apple Developer account. The cask is maintained in this repository; it is not part of Homebrew's official cask collection.

Prefer a direct download? Get the Mac ZIP from [GitHub Releases](https://github.com/nexorial/ios-watch-whisper/releases/latest), unzip it, and move **Micodex.app** into **Applications**.

For Watch dictation, also install the separate audio driver:

```sh
brew install --cask blackhole-2ch
```

BlackHole may request an administrator password and a restart. Afterward, select **BlackHole 2ch** as the input used by Codex using Micodex's audio controls. Scrolling and Enter do not need BlackHole. See the [audio guide](docs/WATCH-AUDIO.md).

### 2. Apple Watch — App Store

Once the first release is approved, download **Micodex – Watch Remote** from the **App Store on your Apple Watch**. In the Simplified Chinese storefront, search for **Micodex**. The app is free and has no subscription or in-app purchase. No Xcode or developer setup is required for App Store installation.

**Not available yet:** the first Watch release is still awaiting the owner's screenshots and App Review. [App Store destination](https://apps.apple.com/app/id6816016796) will become available after release. Installing the Mac app does not install the Watch app. The project page will reflect public availability when it is verified.

### 3. Pair and start using Micodex

1. Keep Micodex running on the Mac and connect both devices to a reachable local network.
2. **Connect your Mac.** In the Mac receiver, expand **Connect** and click **Copy Connection Code**. In the Watch connection screen, paste the complete code using the iPhone keyboard, or enter it exactly. Tap **Trust This Mac & Connect**. Only copy a code from your own Mac: it contains the full certificate fingerprint that identifies that computer.
3. **Approve pairing.** Click **Allow Wi-Fi Watch** on the Mac. Compare the six-digit code on both devices, then click **Codes Match — Allow**. Your devices reconnect using their saved pairing.
4. **Allow control.** Grant Micodex Accessibility access in macOS System Settings. Open a Codex task and turn the Crown to scroll the conversation.
5. **Enable Watch dictation.** Install BlackHole 2ch, use the Mac receiver's audio controls to select it as the dictation input, and allow the Watch microphone when asked. Codex must use BlackHole or the system default input. See the [audio guide](docs/WATCH-AUDIO.md).
6. **Talk, check, send.** Hold to talk; wait until the Watch says it is recording. Release, wait for transcription, check the text on your Mac, and tap Enter to send.

Changing the default input also affects other apps that use it. Switch back to your usual microphone when finished. Location permission is optional and is used only to display the Wi-Fi name; Micodex does not read or store location coordinates.

### Updating and uninstalling

Finish dictation and quit Micodex before updating:

```sh
brew update
brew upgrade --cask nexorial/micodex/micodex
```

To remove the Mac app:

```sh
brew uninstall --cask nexorial/micodex/micodex
```

Normal upgrades and uninstall keep pairing settings and the Mac certificate. See [local privacy controls](docs/PRIVACY.md) if you also want to remove that data. If you previously installed a development copy in `~/Applications`, quit it and keep only one receiver running. Detailed installation and migration help: [Installation guide](docs/INSTALLATION.md).

## Build from source (developers)

The steps below are for contributors and custom builds. Ordinary users should use **Homebrew on Mac and the App Store on Apple Watch**. Development needs Xcode 27 (tested), XcodeGen, and a signing team for physical-device installation.

```sh
git clone https://github.com/nexorial/ios-watch-whisper.git
cd ios-watch-whisper
brew install xcodegen
./scripts/build.sh
```

The build script checks localization, runs the Swift tests, and builds the Mac and Watch simulator apps without signing. Build products and test output go under `/tmp`, keeping local artifacts out of Git.

For signed device builds:

```sh
cp Config/Local.xcconfig.example Config/Local.xcconfig
# Set MICODEX_DEVELOPMENT_TEAM to your Apple Developer team ID.
xcodegen generate
open Micodex.xcodeproj
```

Select the `MicodexMac` or `MicodexWatch` scheme and your device. If you use a different Apple team, also change the three bundle identifiers in `project.yml` to identifiers registered to your team. `project.yml` is the source of truth; regenerate the Xcode project after editing it.

Optional scripts:

```sh
# Install a locally signed Mac receiver (quit the old receiver first).
./scripts/install-mac.sh 'Apple Development: Your Name (TEAM_ID)'

# Install the Watch app via a trusted developer connection.
./scripts/install-watch.sh YOUR_WATCH_UDID

# Core tests only; no hardware, account, or permissions needed.
swift test --scratch-path /tmp/micodex-tests

# Local TLS / pairing / audio-protocol integration tests on a Mac.
./scripts/test-wifi-security.sh
```

The developer Watch installer can preconfigure your own Mac's public certificate pin. Public App Store exports never contain that developer-specific configuration. Signing files, credentials, builds, and local logs are ignored by Git.

## Limits and troubleshooting

| Symptom | What to check |
| --- | --- |
| Cannot connect | Keep the Mac receiver open with **Wi-Fi Ready**. Check the saved **Mac IP**, local-network permission, firewall, and network client isolation. A DHCP address change only needs an IP update. |
| Certificate cannot be verified | Use the code copied directly from your Mac. For a replacement Mac or certificate, choose **Set Up Another Mac** on the Watch. Never accept a code supplied by an unknown peer. |
| Receiver port is in use | Quit duplicate Micodex / legacy Watch Whisper receivers. Port 8766 recovers automatically once free. |
| No transcription | Check BlackHole 2ch, Codex's input selection and microphone permission, Watch input level, and Micodex Accessibility access. There is no automatic fallback to the Mac microphone. |
| Crown moves the wrong area | Open one Codex task; close side editors, browser, and terminal panels. Codex UI changes can affect Accessibility matching. |
| Enter does nothing | Stop recording, wait for transcription, ensure the editor is nonempty and the chosen target is foreground. |

Locked recording uses watchOS background audio, but the system can dim the display or interrupt recording. Screen-off continuity, release timing, and transcription quality need real-device checks; automated tests do not establish those outcomes. Bluetooth audio and Claude scrolling/Enter are experimental; Claude dictation is disabled. Side-button remapping, automatic sending, remote wake, and internet relay are not supported.

## Code map

| Directory | Responsibility |
| --- | --- |
| `Watch/` | Watch UI, gestures, microphone, and transport coordination |
| `Mac/` | Receiver services, Codex Accessibility adapter, and audio output |
| `Sources/MicodexCore/` | Authenticated protocols, audio codec, state machines, connection configuration, and localization |
| `Shared/` | Shared SwiftUI style and optional Wi-Fi name display |
| `Tests/` | Unit tests, isolated Mac integration tests, and Watch UI tests |
| `Localization/` | Reviewed English → Chinese source catalogs |
| `Config/`, `scripts/` | Reproducible builds, signing templates, and release verification |
| `Casks/` | Homebrew installation of the signed, notarized Mac release |

Read [Architecture](docs/ARCHITECTURE.md), [Contributing](CONTRIBUTING.md), [Security](SECURITY.md), and the [release checklist](docs/RELEASING.md). Legacy bundle IDs and Keychain namespaces intentionally retain `watchwhisper` so existing installations keep their pairing keys. When upgrading from a developer-provisioned build to the public build, copy your Mac connection code once; the same Mac identity reuses its saved key.

## License

[MIT](LICENSE), © 2026 Nexorial. BlackHole, Codex, Apple software, and their trademarks remain subject to their respective licenses and terms; they are not bundled with this repository.
