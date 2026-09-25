#!/usr/bin/env python3
"""Check the actual exported bundles, not just the Xcode source settings."""
import hashlib
import json
import plistlib
from pathlib import Path
import sys
import zipfile

ipa = Path(sys.argv[1])
with zipfile.ZipFile(ipa) as archive:
    roots = [n for n in archive.namelist() if n.startswith('Payload/') and n.endswith('.app/Info.plist') and n.count('/') == 2]
    watches = [n for n in archive.namelist() if '/Watch/' in n and n.endswith('.app/Info.plist') and n.count('/') == 4]
    assert len(roots) == len(watches) == 1, 'Expected exactly one container and one Watch app'
    root = plistlib.loads(archive.read(roots[0]))
    watch = plistlib.loads(archive.read(watches[0]))
    for key in ('CFBundleShortVersionString', 'CFBundleVersion'):
        assert root[key] == watch[key], f'Container/Watch mismatch: {key}'
        assert '$(' not in root[key], f'Unexpanded build setting: {key}'
    assert root.get('ITSWatchOnlyContainer') is True, 'Container is not a Watch-only stub'
    assert watch.get('WKWatchOnly') is True, 'Watch is not standalone'
    assert 'WKCompanionAppBundleIdentifier' not in watch, 'Unexpected iPhone companion'
    assert 'WKRunsIndependentlyOfCompanionApp' not in watch, 'Ambiguous Watch-only configuration'
    assert watch.get('CFBundleSupportedPlatforms') == ['WatchOS']
    assert watch['CFBundleIcons']['CFBundlePrimaryIcon']['CFBundleIconName'] == 'AppIcon'
    assert watch.get('NSBluetoothAlwaysUsageDescription'), 'Missing Bluetooth purpose string'
    # Apple checks the outer watch-only container too (ITMS-90683).
    assert root.get('NSMicrophoneUsageDescription'), 'Missing container microphone purpose string'
    assert watch.get('NSMicrophoneUsageDescription'), 'Missing Watch microphone purpose string'
    if 'WatchWhisperWiFiPin' in watch:
        pin = watch['WatchWhisperWiFiPin']
        assert len(pin) == 64 and all(c in '0123456789abcdefABCDEF' for c in pin), 'Invalid Wi-Fi certificate pin'
        assert watch.get('WatchWhisperWiFiHost') and '$(' not in watch['WatchWhisperWiFiHost'], 'Missing local Mac address'
    assert not any(n.endswith(('.p12', '.password')) for n in archive.namelist()), 'Private TLS identity must never be bundled'

    print(json.dumps({
        'version': root['CFBundleShortVersionString'],
        'build': root['CFBundleVersion'],
        'bundle': root['CFBundleIdentifier'],
        'watch_bundle': watch['CFBundleIdentifier'],
        'watch_only': True,
        'sha256': hashlib.sha256(ipa.read_bytes()).hexdigest(),
        'bytes': ipa.stat().st_size,
    }, indent=2))
