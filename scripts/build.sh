#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo 'Install XcodeGen: brew install xcodegen'; exit 1; }
python3 scripts/generate-localizations.py --check
xcodegen generate
swift test --scratch-path /tmp/micodex-tests
xcodebuild -project Micodex.xcodeproj -scheme MicodexMac -configuration Debug -derivedDataPath /tmp/micodex-mac CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Micodex.xcodeproj -scheme MicodexWatch -sdk watchsimulator -destination 'generic/platform=watchOS Simulator' -derivedDataPath /tmp/micodex-sim CODE_SIGNING_ALLOWED=NO build
