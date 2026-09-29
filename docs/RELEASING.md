# Releasing Micodex

The Watch-only App Store record uses bundle ID `com.nexorial.watchwhisper`; its embedded Watch app uses `com.nexorial.watchwhisper.watchkitapp`. The Mac receiver is distributed separately. Keep these identifiers for upgrades.

1. Update version/build in `project.yml`. Configure your signing team in ignored `Config/Local.xcconfig`.
2. Run the [validation checklist](VALIDATION.md), localization, builds, and relevant transport tests. Review the source and Git history for credentials before making a repository public.
3. Run `./scripts/prepare-app-store.sh artifacts/app-store-VERSION-BUILD`. This archives the Watch-only distribution container and exports an App Store-compatible IPA, **not an internal-only build**. It never injects a developer IP or certificate pin.
4. `scripts/verify-export.py` checks the actual outer/Watch metadata, matching versions, required permission descriptions, icon, background audio, privacy manifests, empty developer connection defaults, and absence of private identity files. Check distribution signatures too.
5. Upload with Xcode Organizer or an authenticated Apple delivery tool. Confirm Apple's processing completes, then select this exact version/build in App Store Connect. A successful export or upload does not prove processing.
6. Fill English and Simplified Chinese descriptions, support/marketing links, privacy URL and disclosures, category, age rating, rights, review contact/instructions, distribution availability, and a free base price. Do not add subscriptions or in-app purchases.
7. Add the user's real Watch screenshots. Do not manufacture evidence or submit for review while screenshots or device acceptance are incomplete.
8. Submit only when release assets are ready. Report App Review and public availability as separate states.

Public URLs:

- Project / support: https://kiskir.dev/projects/micodex
- Privacy: https://kiskir.dev/projects/micodex/privacy
- Terms: https://kiskir.dev/projects/micodex/terms

The privacy manifest declares UserDefaults for app-local settings (`CA92.1`) and system uptime for elapsed-time calculations (`35F9.1`). There is no advertising, analytics SDK, tracking, account, or developer-operated audio service. Codex's own dictation processing is described separately in the privacy policy.

## 1.0 (16) preparation — September 28, 2026

- Source published under MIT; GitHub Actions passed the core tests and both app builds.
- 67 local unit tests passed. Local TLS, pairing, wrong-pin, replay, audio finalization, duplicate receiver and port recovery tests passed.
- Public Watch-only IPA passed metadata, privacy-manifest and Apple Distribution signature checks. Apple confirmed upload success and processed build 16; the build was selected in version 1.0.
- The official project, privacy and terms pages are live, with desktop/mobile checks. Website PR #3 was merged into the existing production branch.
- App Privacy was published as Data Not Collected. Free pricing was configured for all 175 price regions. Age rating is 4+.
- Owner screenshots and physical acceptance of the public setup flow remain outstanding. No App Review submission or public App Store release is claimed. At that preparation checkpoint the Mac receiver was installed from source; the Homebrew distribution workflow below supersedes that installation limitation.

See `marketing/app-store/` for the reviewable listing copy. Keep private contact details and raw delivery receipts outside Git.

## Mac app and Homebrew

Public installation is **Homebrew on Mac + App Store on Watch**. The Mac ZIP is a universal prebuilt app, independent of the Watch listing. Its cask lives in `Casks/micodex.rb` in this repository and is tapped with an explicit Git URL. Do not advertise the Watch listing as available until it is public.

Use the existing Xcode account and signing team to submit a universal Mac archive for Developer ID signing and Apple notarization:

```sh
./scripts/prepare-mac-release.sh /tmp/Micodex-RELEASE.xcarchive
```

Xcode can use its cloud-managed Developer ID certificate when no local distribution identity is installed. This is separate from Apple Development signing and from the Watch's App Store distribution signature. After Apple has accepted notarization:

```sh
./scripts/export-mac-release.sh /tmp/Micodex-RELEASE.xcarchive /absolute/path/new-output
```

The export script checks the actual signature, both CPU architectures, stapled notarization ticket and Gatekeeper acceptance before packaging. It exports outside synced folders so Finder metadata does not contaminate bundle verification. It does not disable Gatekeeper, remove quarantine from a downloaded app, or publish an unsigned fallback.

Publish an immutable GitHub Release named `mac-vVERSION-BUILD` with the generated `Micodex-VERSION-BUILD-macOS-universal.zip`. Update the cask's `version`, SHA-256 and matching URL; use `brew style`, a Cask audit and a real install from the public URL before claiming the command works. Never overwrite an existing release asset with different bytes. Keep raw signing and upload logs under ignored `artifacts/`.

```sh
brew tap nexorial/micodex https://github.com/nexorial/ios-watch-whisper
brew install --cask nexorial/micodex/micodex
```

For a verification install on a development Mac, use a fresh temporary `--appdir` so the existing receiver is not overwritten. Do not run two receivers; inspect signatures and notarization independently from any physical Watch acceptance.
