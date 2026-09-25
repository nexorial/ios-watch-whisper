#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
watch_whisper_test_dir="$(mktemp -d /tmp/watch-whisper-wifi-test.XXXXXX)"
trap 'rm -rf "$watch_whisper_test_dir"' EXIT
swiftc -swift-version 5 -emit-library -emit-module -module-name WhisperCore Sources/WhisperCore/*.swift \
    -emit-module-path "$watch_whisper_test_dir/WhisperCore.swiftmodule" -o "$watch_whisper_test_dir/libWhisperCore.dylib"
swiftc -swift-version 5 -I "$watch_whisper_test_dir" -L "$watch_whisper_test_dir" -lWhisperCore \
    -Xlinker -rpath -Xlinker "$watch_whisper_test_dir" \
    Mac/LocalTLSIdentity.swift Mac/TLSHTTPServer.swift Mac/WiFiHost.swift Mac/AgentController.swift Mac/WatchAudioOutput.swift \
    Tests/Hardware/WiFiSecuritySmoke.swift -o "$watch_whisper_test_dir/check"
"$watch_whisper_test_dir/check"
