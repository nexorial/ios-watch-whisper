#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
watch_whisper_audio_test="$(mktemp -d /tmp/watch-whisper-audio-test.XXXXXX)"
trap 'rm -rf "$watch_whisper_audio_test"' EXIT
swiftc -swift-version 5 -emit-library -emit-module -module-name WhisperCore Sources/WhisperCore/*.swift \
  -emit-module-path "$watch_whisper_audio_test/WhisperCore.swiftmodule" -o "$watch_whisper_audio_test/libWhisperCore.dylib"
swiftc -swift-version 5 -I "$watch_whisper_audio_test" -L "$watch_whisper_audio_test" -lWhisperCore \
  -Xlinker -rpath -Xlinker "$watch_whisper_audio_test" \
  Mac/WatchAudioOutput.swift Tests/Hardware/VirtualMicrophoneSmoke.swift -o "$watch_whisper_audio_test/check"
"$watch_whisper_audio_test/check"
