#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
watch_whisper_device="${1:?Usage: scripts/install-watch.sh WATCH_UDID}"
watch_whisper_install_dir="$(mktemp -d /tmp/watch-whisper-install.XXXXXX)"
watch_whisper_discovery=""
watch_whisper_cleanup() {
    if test -n "$watch_whisper_discovery" && jobs -pr | rg -q "^${watch_whisper_discovery}$"; then
        kill "$watch_whisper_discovery" 2>/dev/null || true
        wait "$watch_whisper_discovery" 2>/dev/null || true
    fi
    rm -rf "$watch_whisper_install_dir"
}
trap watch_whisper_cleanup EXIT
bash scripts/prepare-wifi.sh "$watch_whisper_install_dir/local.xcconfig"
dns-sd -t 300 -includep2p -includeAWDL -B _rp-tunnel._tcp local. > "$watch_whisper_install_dir/discovery.log" 2>&1 &
watch_whisper_discovery=$!
xcodegen generate
xcodebuild -project WatchWhisper.xcodeproj -scheme WatchWhisperWatch -configuration Debug -destination 'generic/platform=watchOS' -derivedDataPath /tmp/watch-whisper-device -xcconfig "$watch_whisper_install_dir/local.xcconfig" -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
watch_whisper_bundle='/tmp/watch-whisper-device/Build/Products/Debug-watchos/Watch Whisper Watch.app'
security cms -D -i "$watch_whisper_bundle/embedded.mobileprovision" > "$watch_whisper_install_dir/profile.plist"
if ! python3 - "$watch_whisper_device" "$watch_whisper_install_dir/profile.plist" <<'PYPROFILE'
import plistlib,sys
p=plistlib.load(open(sys.argv[2],'rb'))
sys.exit(0 if sys.argv[1] in p.get('ProvisionedDevices',[]) else 1)
PYPROFILE
then
    xcodebuild -project WatchWhisper.xcodeproj -scheme WatchWhisperWatch -configuration Debug -destination "id=$watch_whisper_device" -derivedDataPath /tmp/watch-whisper-device -xcconfig "$watch_whisper_install_dir/local.xcconfig" -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
fi
codesign --verify --deep --strict "$watch_whisper_bundle"
xcrun devicectl device install app --device "$watch_whisper_device" "$watch_whisper_bundle" --timeout 45
xcrun devicectl device process launch --device "$watch_whisper_device" com.nexorial.watchwhisper.watchkitapp --terminate-existing --timeout 30
