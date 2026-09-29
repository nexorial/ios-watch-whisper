# Validation

Use `./scripts/build.sh` for localization, core tests, and unsigned Mac / Watch simulator builds. Use `./scripts/test-wifi-security.sh` for the real local TLS and authenticated protocol flow against a demo target.

The project has previous physical Watch pairing, reconnection, and Crown-scrolling evidence. The public setup flow and each release still require device acceptance. Do not infer live dictation, tap-to-stop timing, screen-off continuity, or App Store approval from a successful build.

Before a public release, record:

- [ ] Fresh Watch install → connection code → matching pairing code → approval.
- [ ] Reopen both apps and reconnect; update DHCP IP without losing identity.
- [ ] Crown scrolls the Codex conversation body at different turn speeds.
- [ ] Watch speech reaches Codex; Mac microphone is not silently substituted.
- [ ] Second tap excludes speech spoken afterward; speech pauses do not stop capture.
- [ ] Tap-started wrist-down recording preserves speech received by the Mac.
- [ ] Interruptions preserve received audio and never automatically send.
- [ ] Enter sends only after transcription and user confirmation.
- [ ] Double start haptics occur only after actual capture, never after a quick stop.
- [ ] Watch header follows the focused Codex thread; unavailable titles clear.
- [ ] Mac scrollbars fade when idle and disclosure labels toggle the full row.
- [ ] English/Chinese and small/large Watch layouts remain usable.
- [ ] App Store export contains the privacy manifest and no developer endpoint.

Keep raw device logs and account-specific upload receipts in ignored `artifacts/`. The release checklist distinguishes archive, upload, Apple processing, review preparation, submission, and public availability.

## Build 17 interaction update (2026-09-29)

- Core regression suite: 62 tests passed. English/Chinese catalogs checked.
- Mac and Watch simulator builds passed; signed physical Watch build passed.
- Local TLS smoke passed: authenticated thread metadata, no title in discovery,
  speech-pause continuity, interruption finalization, late audio/stop/cancel
  handling, replay rejection, pairing/revocation, and receiver recovery.
- Mac Build 17 installed and opened. Native UI checks confirmed the indicator
  appears during scrolling and disappears when idle, Bluetooth Backup is absent,
  and both More Settings and Last Action toggle by clicking their labels.
- Physical Watch install returned success. Subsequent launch/read-back failed
  with a developer tunnel timeout; double haptics, thread-title accuracy, and
  wrist-down microphone/transcription continuity remain device acceptance items.
- The Watch UI-test target compiled, but the simulator test run did not reach
  a test case and was stopped after remaining stalled. No UI-test pass is claimed.

## Build 18 focused conversation title fix (2026-09-29)

- The Mac receiver now treats both `Codex` and its `ChatGPT` window-title alias as application names, not conversation titles.
- A unique title in the active composer's top content column takes priority over the OS window title. Heading, static-text and title-button representations are supported; sidebar rows, transcript headings, hidden geometry and ambiguous headers are rejected.
- Added regressions for the reported Chinese thread name, stale window titles, application aliases, non-heading headers, ambiguity and duplicate accessibility nodes. All 67 core tests and Mac / Watch simulator builds passed.
- The isolated local TLS integration test passed, including authenticated title metadata and no title disclosure during discovery. It does not read or operate a real Codex window.
- Mac Build 18 was signed, installed and opened with Accessibility still allowed and the receiver ready. The existing Watch title display consumes the corrected metadata; this fix does not require reinstalling the Watch app.
- The exact live conversation title on the physical Watch still needs user confirmation. Automated access to the Codex UI was unavailable, so the fixture tests are not recorded as live title acceptance.

## Build 19 installation and setup guide (2026-09-29)

- Added a Homebrew Cask dependency on the official `blackhole-2ch` package. Installer administrator/restart prompts remain native; ZIP users get a manual recovery path.
- Added a four-step Mac Setup Guide: audio, permissions, pairing, and a real Watch test. Fresh unpaired users see it once; existing users can reopen it. Dismissal and completion are separate local preferences.
- Completion requires actual local driver/input/Accessibility/receiver/pairing checks plus explicit user confirmation of scrolling and transcription. Scrolling-only setup does not require audio. Neither a paired Watch nor a detected driver is treated as transcription proof.
- 71 core tests passed, including missing prerequisites, unconfirmed tests, scrolling-only use and revoked state. English/Chinese localization checks and both app builds passed. A later permission-copy clarification passed localization validation and the universal Mac release build.
- Native UI checks covered all four steps, ready driver/input indicators, disabled Finish Setup before real-test confirmation, and Set Up Later. The microphone-settings link opened the correct macOS pane; no permission switch or audio input was changed during verification.
- Developer ID signing, both CPU architectures, stapled notarization and Gatekeeper assessment passed for the final Mac ZIP. Fresh privileged driver installation/reboot and real Watch speech remain separate user/device acceptance checks; this Mac already has the BlackHole driver installed outside Homebrew.
