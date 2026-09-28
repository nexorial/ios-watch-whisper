#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
micodex_test_dir="$(mktemp -d /tmp/micodex-wifi-test.XXXXXX)"
trap 'rm -rf "$micodex_test_dir"' EXIT
swiftc -swift-version 5 -emit-library -emit-module -module-name MicodexCore Sources/MicodexCore/*.swift \
    -emit-module-path "$micodex_test_dir/MicodexCore.swiftmodule" -o "$micodex_test_dir/libMicodexCore.dylib"
swiftc -swift-version 5 -I "$micodex_test_dir" -L "$micodex_test_dir" -lMicodexCore \
    -Xlinker -rpath -Xlinker "$micodex_test_dir" \
    Mac/LocalTLSIdentity.swift Mac/ReceiverLease.swift Mac/TLSHTTPServer.swift Mac/WiFiHost.swift Mac/AgentController.swift Mac/WatchAudioOutput.swift \
    Tests/Hardware/WiFiSecuritySmoke.swift -o "$micodex_test_dir/check"
"$micodex_test_dir/check"
