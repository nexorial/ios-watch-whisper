#!/bin/bash
# Export a public Watch-only build without developer-specific connection data.
set -euo pipefail
cd "$(dirname "$0")/.."
micodex_output="${1:-artifacts/app-store-$(date +%Y%m%d-%H%M%S)}"
if test -e "$micodex_output"; then
    echo "Output already exists; choose a new export directory: $micodex_output" >&2
    exit 1
fi
micodex_work="$(mktemp -d /tmp/micodex-app-store.XXXXXX)"
python3 scripts/generate-localizations.py --check
xcodegen generate
xcodebuild -project Micodex.xcodeproj -scheme Micodex -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath /tmp/micodex-release \
    -archivePath "$micodex_work/Micodex.xcarchive" \
    MICODEX_HOST= MICODEX_PIN= -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath "$micodex_work/Micodex.xcarchive" \
    -exportOptionsPlist Config/ExportOptions-AppStore.plist \
    -exportPath "$micodex_output" -allowProvisioningUpdates
python3 scripts/verify-export.py "$micodex_output/Micodex.ipa"
echo "Export prepared at $micodex_output. Archive retained at $micodex_work. Nothing uploaded."
