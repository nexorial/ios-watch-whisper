#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
micodex_audio_test="$(mktemp -d /tmp/micodex-audio-test.XXXXXX)"
trap 'rm -rf "$micodex_audio_test"' EXIT
swiftc -swift-version 5 -emit-library -emit-module -module-name MicodexCore Sources/MicodexCore/*.swift \
  -emit-module-path "$micodex_audio_test/MicodexCore.swiftmodule" -o "$micodex_audio_test/libMicodexCore.dylib"
swiftc -swift-version 5 -I "$micodex_audio_test" -L "$micodex_audio_test" -lMicodexCore \
  -Xlinker -rpath -Xlinker "$micodex_audio_test" \
  Mac/WatchAudioOutput.swift Tests/Hardware/VirtualMicrophoneSmoke.swift -o "$micodex_audio_test/check"
"$micodex_audio_test/check"
