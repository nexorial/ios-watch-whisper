#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
watch_whisper_output="${1:-artifacts/testflight-$(date +%Y%m%d-%H%M%S)}"
if test -e "$watch_whisper_output"; then
    echo "Output already exists; choose a new export directory: $watch_whisper_output" >&2
    exit 1
fi
watch_whisper_work="$(mktemp -d /tmp/watch-whisper-testflight.XXXXXX)"
bash scripts/prepare-wifi.sh "$watch_whisper_work/local.xcconfig"
xcodegen generate
xcodebuild -project WatchWhisper.xcodeproj -scheme WatchWhisper -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/watch-whisper-release -archivePath "$watch_whisper_work/WatchWhisper.xcarchive" -xcconfig "$watch_whisper_work/local.xcconfig" -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath "$watch_whisper_work/WatchWhisper.xcarchive" -exportOptionsPlist Config/ExportOptions-TestFlight.plist -exportPath "$watch_whisper_output" -allowProvisioningUpdates
python3 scripts/verify-export.py "$watch_whisper_output/WatchWhisper.ipa"
echo "Export prepared at $watch_whisper_output. Archive retained at $watch_whisper_work. Nothing uploaded."
