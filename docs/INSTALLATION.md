# Installation

For ordinary users: **Homebrew on the Mac, App Store on Apple Watch**. Xcode and an Apple Developer account are only needed when developing Micodex from source.

## Availability

- **Mac:** signed, notarized universal app distributed through the Cask in this repository and GitHub Releases.
- **Apple Watch:** the first App Store release is still awaiting owner screenshots and App Review. The Watch download is not live yet. The intended store name is **Micodex – Watch Remote** in English and **Micodex** in Simplified Chinese; its Apple ID is `6816016796`.

The Mac app requires a Watch app to provide remote controls. Installing one does not install the other.

## Mac installation

Install [Homebrew](https://brew.sh/) once, then:

```sh
brew tap nexorial/micodex https://github.com/nexorial/ios-watch-whisper
brew install --cask nexorial/micodex/micodex
open -a Micodex
```

The tap uses this project's existing repository. The fully qualified cask name selects this project's package explicitly. Homebrew checks the release ZIP's SHA-256 and installs `Micodex.app` into Applications. The package contains Apple Silicon and Intel executables, a Developer ID signature, hardened runtime, and a stapled Apple notarization ticket.

Wi-Fi setup requires **macOS 15+**. No compilation, personal signing team, or developer-mode setup is part of the normal Mac installation.

Without Homebrew, download the Mac ZIP from [Releases](https://github.com/nexorial/ios-watch-whisper/releases/latest), unzip it, and drag `Micodex.app` into Applications.

### Automatic BlackHole installation

The Micodex Cask declares `depends_on cask: "blackhole-2ch"`. Homebrew installs that driver before Micodex when needed. You do not need a separate driver command for the normal Homebrew installation.

BlackHole is a system audio driver with its own license and official installer. macOS may request an administrator password and a restart. Neither Micodex nor Homebrew bypasses those prompts. If installation is interrupted, finish the system installer and run the Micodex installation command again.

For the **direct ZIP download**, install BlackHole separately with `brew install --cask blackhole-2ch` or its official installer. A ZIP cannot install the system dependency by itself.

### First-launch Setup Guide

The guide opens for a new, unpaired installation. Existing paired users keep their normal panel and can click **Setup Guide** at any time. Choosing **Set Up Later** remembers the dismissal without marking setup complete.

| Step | What the guide does | What you do |
| --- | --- | --- |
| Audio | Detects the BlackHole audio device and whether it is the default input; distinguishes driver files waiting to load | Finish installer/restart if needed; click **Use BlackHole for Dictation** |
| Permissions | Checks Micodex Accessibility access and provides settings links | Allow Micodex Accessibility and Local Network; allow **Codex** microphone access on Mac and **Micodex** microphone access on Watch |
| Pair Watch | Shows receiver readiness, copies its connection code and offers explicit pairing approval | Open the Watch app, paste the code, compare the six digits, then approve |
| Try It | Keeps detection separate from real control/transcription | Test Crown scrolling and one spoken sentence; confirm only after seeing the results |

The guide never automatically changes the default input or grants permissions. The input button affects other apps using the system default microphone, but leaves speaker output unchanged. Select System Default or BlackHole 2ch in Codex. Switching back to your normal microphone later may require choosing BlackHole again before Watch dictation.

Codex may appear as **ChatGPT** in macOS permission lists. Mac Micodex does not need the Mac microphone. Codex and Watch microphone permission cannot be verified by checking the Mac receiver's own permissions, so the final step uses your actual test. Location is optional and only displays the Wi-Fi name. A saved Watch pairing does not prove a currently live connection or successful speech recognition.

You can uncheck **Set up voice input too** and finish the guide for scrolling/Enter first. Homebrew still installs BlackHole as a dependency; the guide does not force microphone use.

## Apple Watch installation

After release, open the **App Store on Apple Watch**, search for **Micodex – Watch Remote** (or **Micodex** in Simplified Chinese), and download the free app. [The App Store destination](https://apps.apple.com/app/id6816016796) becomes usable when Apple makes the release public.

The Watch app requires watchOS 9+. There is no iPhone companion interface to build or configure. An iPhone can assist with Watch setup and with pasting the Mac connection code via the Watch keyboard notification. Do not enable Developer Mode for a normal App Store installation.

While the first release is pending, the developer build instructions remain available for contributors; they are not the recommended public installation path.

## Pair your devices

1. Keep Micodex open on an awake Mac. Connect both devices to a local network that allows device-to-device traffic.
2. On the Mac, open **Connect → Copy Connection Code**. On Watch, paste that code and tap **Trust This Mac & Connect**. Obtain the code directly from your own Mac.
3. On Mac, click **Allow Wi-Fi Watch**, compare the six-digit codes on both devices, and approve the matching request.
4. Grant Micodex Accessibility access in macOS System Settings. Open a Codex task and try Crown scrolling.
5. For dictation, finish the BlackHole setup, allow the Watch microphone, speak, and check the transcript on Mac before tapping Enter.

## Update, uninstall, and migrate

Finish dictation and **quit Micodex** before upgrading or uninstalling:

```sh
brew update
brew upgrade --cask nexorial/micodex/micodex
# To remove only the app:
brew uninstall --cask nexorial/micodex/micodex
```

Pairing preferences, Keychain items, and the Mac TLS identity are preserved. The Cask has no data-wiping `zap` action. See [Privacy controls](PRIVACY.md) for deliberate data removal.

If you previously built Micodex yourself, quit the old receiver before opening the Homebrew copy in `/Applications`. A development copy in `~/Applications` is a separate app bundle; archive or remove that old bundle yourself when no longer needed. Do not run both receivers. Keep the existing bundle identity and local TLS directory to retain pairing; a new signature can require confirming the app's Accessibility permission again in macOS.

If Homebrew reports an existing `/Applications/Micodex.app`, do not force an overwrite of a running or unreviewed copy. Quit it and move that old app bundle aside before retrying. Pairing data lives separately from the app.

## Installation checks

```sh
brew info --cask nexorial/micodex/micodex
codesign --verify --deep --strict /Applications/Micodex.app
spctl --assess --type execute --verbose=2 /Applications/Micodex.app
```

The last command should report an accepted Notarized Developer ID app. Do not disable Gatekeeper or strip quarantine to work around a damaged or unverified download. Re-download the official package if validation fails.
