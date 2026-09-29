#!/bin/bash
# Public Mac distribution uses Developer ID + Apple notarization, not development signing.
set -euo pipefail
cd "$(dirname "$0")/.."
micodex_archive="${1:?Usage: scripts/prepare-mac-release.sh /absolute/path/Micodex.xcarchive}"
case "$micodex_archive" in /*.xcarchive) ;; *) echo 'Use an absolute .xcarchive path.' >&2; exit 1;; esac
if test -e "$micodex_archive"; then
    echo "Archive already exists: $micodex_archive" >&2
    exit 1
fi
python3 scripts/generate-localizations.py --check
xcodegen generate
xcodebuild -project Micodex.xcodeproj -scheme MicodexMac -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath /tmp/micodex-mac-distribution \
    -archivePath "$micodex_archive" 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath "$micodex_archive" \
    -exportOptionsPlist Config/ExportOptions-DeveloperID.plist -allowProvisioningUpdates
printf 'Submitted to Apple. After notarization completes, run:\n./scripts/export-mac-release.sh "%s" /absolute/path/output\n' "$micodex_archive"
