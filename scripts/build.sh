#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo 'Install XcodeGen: brew install xcodegen'; exit 1; }
xcodegen generate
swift test --scratch-path /tmp/watch-whisper-tests
xcodebuild -project WatchWhisper.xcodeproj -scheme WatchWhisperMac -configuration Debug -derivedDataPath /tmp/watch-whisper-mac CODE_SIGNING_ALLOWED=NO build
xcodebuild -project WatchWhisper.xcodeproj -scheme WatchWhisperWatch -sdk watchsimulator -destination 'generic/platform=watchOS Simulator' -derivedDataPath /tmp/watch-whisper-sim CODE_SIGNING_ALLOWED=NO build
