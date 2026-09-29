#!/bin/bash
# Package only an Apple-notarized universal app. Never publish a development build.
set -euo pipefail
cd "$(dirname "$0")/.."
micodex_archive="${1:?Usage: scripts/export-mac-release.sh ARCHIVE OUTPUT_DIRECTORY}"
micodex_output="${2:?Provide a new absolute output directory}"
case "$micodex_output" in /*) ;; *) echo 'Use an absolute output directory.' >&2; exit 1;; esac
if test -e "$micodex_output"; then
    echo "Output already exists: $micodex_output" >&2
    exit 1
fi
# Keep the exported bundle outside synced folders: Finder metadata can invalidate
# strict signature validation even when the application bytes are unchanged.
micodex_stage="$(mktemp -d /tmp/micodex-notarized.XXXXXX)"
trap 'rm -rf "$micodex_stage"' EXIT
xcodebuild -exportNotarizedApp -archivePath "$micodex_archive" -exportPath "$micodex_stage/export"
micodex_app="$micodex_stage/export/Micodex.app"
codesign --verify --deep --strict "$micodex_app"
micodex_signature="$(codesign -dv --verbose=2 "$micodex_app" 2>&1)"
[[ "$micodex_signature" == *'Authority=Developer ID Application:'* ]] || { echo 'Expected Developer ID signing.' >&2; exit 1; }
xcrun stapler validate "$micodex_app"
spctl --assess --type execute --verbose=2 "$micodex_app"
micodex_archs="$(lipo -archs "$micodex_app/Contents/MacOS/Micodex")"
[[ " $micodex_archs " == *' arm64 '* && " $micodex_archs " == *' x86_64 '* ]] || { echo 'Expected a universal Mac app.' >&2; exit 1; }
micodex_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$micodex_app/Contents/Info.plist")"
micodex_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$micodex_app/Contents/Info.plist")"
[[ "$micodex_version" =~ ^[0-9]+(\.[0-9]+)*$ && "$micodex_build" =~ ^[0-9]+$ ]] || { echo 'Invalid release version.' >&2; exit 1; }
mkdir -p "$micodex_output"
micodex_zip="$micodex_output/Micodex-$micodex_version-$micodex_build-macOS-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$micodex_app" "$micodex_zip"
shasum -a 256 "$micodex_zip"
printf 'Notarized package: %s\n' "$micodex_zip"
