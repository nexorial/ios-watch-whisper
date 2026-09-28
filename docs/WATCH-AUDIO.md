# Watch audio setup

Micodex keeps Codex's built-in dictation:

**Watch microphone → pinned HTTPS → Mac receiver → BlackHole 2ch → Codex dictation.**

1. Install [BlackHole 2ch from its official project](https://github.com/ExistentialAudio/BlackHole). It is a separate system audio driver with its own license and installer permissions.
2. In the Mac receiver, check the audio device, then explicitly select BlackHole as the dictation input. Codex must use BlackHole or the system default input. Other apps using the default input are also affected; switch back afterward. Micodex does not change the speaker output.
3. Allow Codex microphone access and Micodex Accessibility access on the Mac. Allow the Watch microphone when starting a recording.
4. Hold to talk and wait for the recording indication. Release to stop capture, allow the tail to drain and transcription to finish, then inspect the text before tapping Enter.

There is no fallback to the Mac microphone. Audio is buffered in bounded memory queues, never saved as a recording by Micodex. Codex's own data handling and transcription service remain separate.

The optional `./scripts/test-audio-output.sh` plays one second of test audio into BlackHole and checks queue drain; run it only when no other app is recording that input. It does not validate live Watch capture or transcription.

Real-device checks: release before saying a second sentence; check only the first sentence was captured. Separately test lock → lower wrist → continue speaking → raise wrist → stop, two-second silence, manual stop, interruption, and Enter. The system may dim the Watch screen. Build and protocol tests cannot replace these checks.
