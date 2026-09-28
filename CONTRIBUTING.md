# Contributing

Start with the [README](README.md). Open an issue describing the behavior you want to change, or send a focused pull request with reproduction steps and relevant verification.

- Keep Watch UI, transport coordination, shared protocol logic, and Mac control separate. Preserve existing bundle IDs, Keychain services, wire authentication domains, and certificate identity paths unless designing an explicit migration.
- Edit `project.yml`, then run `xcodegen generate`; commit the regenerated project with the source change.
- Add visible copy to `Localization/*.json` and run `python3 scripts/generate-localizations.py`. English is the source/fallback language; Simplified Chinese is supported. Do not translate protocol identifiers or device data.
- Run `./scripts/build.sh`. For transport/authentication changes, also run `./scripts/test-wifi-security.sh` on a Mac with a local network. This uses a demo controller and isolated test credentials; it does not operate Codex.
- Include meaningful regression tests for behavior changes. State which physical-device checks were performed; build, protocol, audio-route, and real transcription results are different evidence.
- Keep credentials, provisioning profiles, private keys, device identifiers, recordings, and personal diagnostics out of commits and issues. Report security concerns privately as described in `SECURITY.md`.

Pull requests are contributed under the repository's MIT license. BlackHole is a separate installation and is not a linked dependency or bundled binary.
