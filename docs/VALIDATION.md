# Validation

Use `./scripts/build.sh` for localization, core tests, and unsigned Mac / Watch simulator builds. Use `./scripts/test-wifi-security.sh` for the real local TLS and authenticated protocol flow against a demo target.

The project has previous physical Watch pairing, reconnection, and Crown-scrolling evidence. The public setup flow and each release still require device acceptance. Do not infer live dictation, release timing, locked screen-off continuity, or App Store approval from a successful build.

Before a public release, record:

- [ ] Fresh Watch install → connection code → matching pairing code → approval.
- [ ] Reopen both apps and reconnect; update DHCP IP without losing identity.
- [ ] Crown scrolls the Codex conversation body at different turn speeds.
- [ ] Watch speech reaches Codex; Mac microphone is not silently substituted.
- [ ] Releasing excludes speech spoken afterward; Stop and silence timeout work.
- [ ] Locked wrist-down recording preserves speech received by the Mac.
- [ ] Interruptions preserve received audio and never automatically send.
- [ ] Enter sends only after transcription and user confirmation.
- [ ] English/Chinese and small/large Watch layouts remain usable.
- [ ] App Store export contains the privacy manifest and no developer endpoint.

Keep raw device logs and account-specific upload receipts in ignored `artifacts/`. The release checklist distinguishes archive, upload, Apple processing, review preparation, submission, and public availability.
