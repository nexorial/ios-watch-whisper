# Architecture

```text
Watch UI → WatchLink → Wi-Fi
                       ↓ authenticated commands and audio
Mac receiver → AgentController → Codex Accessibility controls
             → WatchAudioOutput → BlackHole 2ch → Codex dictation
```

`MicodexCore` contains pure protocol/state logic and native localization resources. The app targets own platform permissions, audio devices, networking lifecycles, and UI. `WatchLink` presents one observable interface over the Wi-Fi transport. Watch startup, remote controls, and connection setup live in separate views.

## Trust and connection

`WiFiConfiguration` validates the portable connection code (`micodex:IPv4:SHA256`). The user copies it from their own Mac into the Watch; the code contains public connection information, not a credential. Saved configuration overrides optional developer provisioning. Existing installations retain their certificate pin and identity namespaces.

`PinnedHTTPSClient` requires the complete certificate fingerprint and system certificate checks, rejects redirects, and uses ephemeral sessions. The Mac approves time-limited pairing requests after the user compares both six-digit codes. A random per-Watch secret is stored in Keychain. Each authenticated session gets a challenge; HMAC, direction markers, stream identifiers, and monotonic counters separate commands, acknowledgements, and audio.

Wi-Fi audio uses authenticated IMA ADPCM blocks and bounded in-memory queues. The transport does not write recordings to disk.

## Recording and failure behavior

A second tap ends Watch capture immediately. The first actual microphone samples trigger two haptic taps; Mac startup latency is covered by bounded buffering. Tail audio is sent and drained before Codex is asked to stop dictation. Late acknowledgements cannot return a stopped UI to a recording state. A two-minute limit, heartbeat expiry, and bounded queues constrain capture. Microphone interruptions flush locally buffered audio before finalization. Transport failures preserve audio already received on the Mac; they cannot recover undelivered audio.

Tap recording can continue with the Watch display dimmed using background audio. It remains subject to watchOS interruption and runtime rules. Remote scrolling and Enter operate only on the selected Mac target; Enter remains a separate user action.

`ReceiverLease` excludes duplicate receivers. Listener replacement waits for cancellation, checks address changes, and retries after port conflicts. A changing DHCP IP does not change certificate identity.

The focused target window title (or an unambiguous top content heading) is included only in authenticated command replies. Missing or ambiguous titles clear the Watch header. It is not exposed by discovery or pairing, nor written to logs.
