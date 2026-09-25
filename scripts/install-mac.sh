#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
watch_whisper_identity="${1:?Usage: scripts/install-mac.sh 'Apple Development: Your Name (...)'}"
watch_whisper_app="$HOME/Applications/Watch Whisper.app"
xcodegen generate
xcodebuild -project WatchWhisper.xcodeproj -scheme WatchWhisperMac -configuration Debug -derivedDataPath /tmp/watch-whisper-mac CODE_SIGNING_ALLOWED=NO build
mkdir -p "$HOME/Applications"
ditto --norsrc --noextattr '/tmp/watch-whisper-mac/Build/Products/Debug/Watch Whisper.app' "$watch_whisper_app"
xattr -cr "$watch_whisper_app"
for binary in "$watch_whisper_app"/Contents/MacOS/*.dylib; do
    test -f "$binary" || continue
    codesign --force --sign "$watch_whisper_identity" --options runtime --timestamp=none "$binary"
done
codesign --force --sign "$watch_whisper_identity" --options runtime --timestamp=none "$watch_whisper_app"
codesign --verify --deep --strict "$watch_whisper_app"
open "$watch_whisper_app"
