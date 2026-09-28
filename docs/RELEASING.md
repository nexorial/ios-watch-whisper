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
