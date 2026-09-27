#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
micodex_identity="${1:?Usage: scripts/install-mac.sh 'Apple Development: Your Name (...)'}"
micodex_app="$HOME/Applications/Micodex.app"
# The legacy path is only used to replace the existing installation in place.
micodex_legacy="$HOME/Applications/Watch Whisper.app"
micodex_check_closed() {
    if pgrep -f "$HOME/Applications/(Micodex|Watch Whisper)\.app/Contents/MacOS/" >/dev/null; then
        echo 'Finish dictation and quit the existing Mac receiver before updating.' >&2
        exit 1
    fi
}
micodex_check_closed
xcodegen generate
xcodebuild -project Micodex.xcodeproj -scheme MicodexMac -configuration Debug -derivedDataPath /tmp/micodex-mac CODE_SIGNING_ALLOWED=NO build
micodex_stage="$(mktemp -d /tmp/micodex-mac-install.XXXXXX)"
trap 'rm -rf "$micodex_stage"' EXIT
micodex_bundle="$micodex_stage/Micodex.app"
ditto --norsrc --noextattr '/tmp/micodex-mac/Build/Products/Debug/Micodex.app' "$micodex_bundle"
xattr -cr "$micodex_bundle"
for binary in "$micodex_bundle"/Contents/MacOS/*.dylib; do
    test -f "$binary" || continue
    codesign --force --sign "$micodex_identity" --options runtime --timestamp=none "$binary"
done
codesign --force --sign "$micodex_identity" --options runtime --timestamp=none --entitlements Config/Mac.entitlements "$micodex_bundle"
codesign --verify --deep --strict "$micodex_bundle"
codesign -d --entitlements :- "$micodex_bundle" > "$micodex_stage/entitlements.plist" 2>/dev/null
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.personal-information.location' "$micodex_stage/entitlements.plist")" = true
micodex_check_closed
mkdir -p "$HOME/Applications"
# Verify ownership before touching either installation. Preferences and pairing
# stay in their original namespaces; the backup contains only the app bundle.
for previous in "$micodex_app" "$micodex_legacy"; do
    if test -e "$previous"; then
        test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$previous/Contents/Info.plist")" = 'com.nexorial.watchwhisper.mac'
    fi
done
micodex_backup="$HOME/Library/Application Support/Micodex/Backups/$(date +%Y%m%d-%H%M%S)"
for previous in "$micodex_app" "$micodex_legacy"; do
    if test -e "$previous"; then
        mkdir -p "$micodex_backup"
        ditto -c -k --keepParent "$previous" "$micodex_backup/$(basename "$previous").zip"
        mv "$previous" "$micodex_stage/previous-$(basename "$previous")"
    fi
done
mv "$micodex_bundle" "$micodex_app"
open "$micodex_app"
