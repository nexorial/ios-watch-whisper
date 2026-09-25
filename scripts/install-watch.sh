#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
watch_whisper_device="${1:?Usage: scripts/install-watch.sh WATCH_UDID}"
xcodegen generate
xcodebuild -project WatchWhisper.xcodeproj -scheme WatchWhisperWatch -configuration Debug -destination "id=$watch_whisper_device" -derivedDataPath /tmp/watch-whisper-device -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
watch_whisper_bundle='/tmp/watch-whisper-device/Build/Products/Debug-watchos/Watch Whisper Watch.app'
xcrun devicectl device install app --device "$watch_whisper_device" "$watch_whisper_bundle"
xcrun devicectl device process launch --device "$watch_whisper_device" com.nexorial.watchwhisper.watchkitapp
