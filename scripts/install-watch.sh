#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
micodex_device="${1:?Usage: scripts/install-watch.sh WATCH_UDID}"
micodex_install_dir="$(mktemp -d /tmp/micodex-install.XXXXXX)"
micodex_discovery=""
micodex_cleanup() {
    if test -n "$micodex_discovery" && jobs -pr | rg -q "^${micodex_discovery}$"; then
        kill "$micodex_discovery" 2>/dev/null || true
        wait "$micodex_discovery" 2>/dev/null || true
    fi
    rm -rf "$micodex_install_dir"
}
trap micodex_cleanup EXIT
bash scripts/prepare-wifi.sh "$micodex_install_dir/local.xcconfig"
dns-sd -t 300 -includep2p -includeAWDL -B _rp-tunnel._tcp local. > "$micodex_install_dir/discovery.log" 2>&1 &
micodex_discovery=$!
xcodegen generate
xcodebuild -project Micodex.xcodeproj -scheme MicodexWatch -configuration Debug -destination 'generic/platform=watchOS' -derivedDataPath /tmp/micodex-device -xcconfig "$micodex_install_dir/local.xcconfig" -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
micodex_bundle='/tmp/micodex-device/Build/Products/Debug-watchos/Micodex Watch.app'
security cms -D -i "$micodex_bundle/embedded.mobileprovision" > "$micodex_install_dir/profile.plist"
if ! python3 - "$micodex_device" "$micodex_install_dir/profile.plist" <<'PYPROFILE'
import plistlib,sys
p=plistlib.load(open(sys.argv[2],'rb'))
sys.exit(0 if sys.argv[1] in p.get('ProvisionedDevices',[]) else 1)
PYPROFILE
then
    xcodebuild -project Micodex.xcodeproj -scheme MicodexWatch -configuration Debug -destination "id=$micodex_device" -derivedDataPath /tmp/micodex-device -xcconfig "$micodex_install_dir/local.xcconfig" -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
fi
codesign --verify --deep --strict "$micodex_bundle"
xcrun devicectl device install app --device "$micodex_device" "$micodex_bundle" --timeout 45
xcrun devicectl device process launch --device "$micodex_device" com.nexorial.watchwhisper.watchkitapp --terminate-existing --timeout 30
