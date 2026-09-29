# Watch audio setup

Micodex keeps Codex's built-in dictation:

**Watch microphone → pinned HTTPS → Mac receiver → BlackHole 2ch → Codex dictation.**

1. Homebrew installs BlackHole 2ch automatically with Micodex. Complete its administrator/restart prompts. Direct ZIP users need `brew install --cask blackhole-2ch` or [the official installer](https://github.com/ExistentialAudio/BlackHole). It remains a separate system driver with its own license.
2. Open **Setup Guide → Audio** in the Mac receiver, check the detected device, then explicitly select BlackHole as the dictation input. Codex must use BlackHole or the system default input. Other apps using the default input are also affected; switch back afterward. Micodex does not change the speaker output.
3. Allow Codex microphone access and Micodex Accessibility access on the Mac. Allow the Watch microphone when starting a recording.
4. Tap to talk; two haptic taps and “Speak now” indicate actual local capture. Tap again to stop capture, allow the tail to drain and transcription to finish, then inspect the text before tapping Enter.

There is no fallback to the Mac microphone. Audio is buffered in bounded memory queues, never saved as a recording by Micodex. Codex's own data handling and transcription service remain separate.

The optional `./scripts/test-audio-output.sh` plays one second of test audio into BlackHole and checks queue drain; run it only when no other app is recording that input. It does not validate live Watch capture or transcription.

Real-device checks: tap Stop before saying a second sentence; check only the first sentence was captured. Separately test tap Start → lower wrist → continue speaking → raise wrist → stop, a pause longer than two seconds without stopping, manual stop, interruption, and Enter. The system may dim the Watch screen. Build and protocol tests cannot replace these checks.

Siri can activate through Raise to Speak or the Siri/Hey Siri wake phrase without a Crown press. Disable those options in Watch Settings → Siri if needed. The app requests fewer system-alert interruptions, but cannot suppress Siri or capture while Siri owns the microphone. A system interruption finalizes the locally queued audio and shows a notice; capture is not silently restarted.

References: [Apple Watch Siri](https://support.apple.com/guide/watch/apd02f71f945/watchos), [audio interruption handling](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions).
