# Architecture

```text
Watch UI → WatchLink → Wi-Fi (primary) / Bluetooth (optional)
                       ↓ authenticated commands and audio
Mac receiver → AgentController → Codex Accessibility controls
             → WatchAudioOutput → BlackHole 2ch → Codex dictation
```

`MicodexCore` contains pure protocol/state logic and native localization resources. The app targets own platform permissions, audio devices, networking lifecycles, and UI. `WatchLink` presents one observable interface while activating only the selected transport. Watch startup, remote controls, and connection setup live in separate views.

## Trust and connection

`WiFiConfiguration` validates the portable connection code (`micodex:IPv4:SHA256`). The user copies it from their own Mac into the Watch; the code contains public connection information, not a credential. Saved configuration overrides optional developer provisioning. Existing installations retain their certificate pin and identity namespaces.

`PinnedHTTPSClient` requires the complete certificate fingerprint and system certificate checks, rejects redirects, and uses ephemeral sessions. The Mac approves time-limited pairing requests after the user compares both six-digit codes. A random per-Watch secret is stored in Keychain. Each authenticated session gets a challenge; HMAC, direction markers, stream identifiers, and monotonic counters separate commands, acknowledgements, and audio.

BLE keeps the same command contract with encrypted GATT access. Wi-Fi audio uses authenticated IMA ADPCM blocks and bounded in-memory queues. Neither transport writes recordings to disk.

## Recording and failure behavior

A physical release ends Watch capture immediately. Tail audio is sent and drained before Codex is asked to stop dictation. Late acknowledgements cannot return a stopped UI to a recording state. Silence detection, a two-minute limit, heartbeat expiry, and bounded queues constrain capture. Interruptions try to transcribe audio already received on the Mac; they cannot recover unsent audio.

Locked recording can continue with the Watch display dimmed using background audio. It remains subject to watchOS interruption and runtime rules. Remote scrolling and Enter operate only on the selected Mac target; Enter remains a separate user action.

`ReceiverLease` excludes duplicate receivers. Listener replacement waits for cancellation, checks address changes, and retries after port conflicts. A changing DHCP IP does not change certificate identity.
