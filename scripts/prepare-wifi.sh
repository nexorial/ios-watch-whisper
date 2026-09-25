#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
watch_whisper_config="${1:-/tmp/watch-whisper-wifi.xcconfig}"
watch_whisper_prepare_dir="$(mktemp -d /tmp/watch-whisper-prepare.XXXXXX)"
trap 'rm -rf "$watch_whisper_prepare_dir"' EXIT
swiftc Mac/LocalTLSIdentity.swift scripts/prepare-wifi.swift -o "$watch_whisper_prepare_dir/prepare"
"$watch_whisper_prepare_dir/prepare" > "$watch_whisper_prepare_dir/config.json"
python3 - "$watch_whisper_prepare_dir/config.json" "$watch_whisper_config" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]))
with open(sys.argv[2],'w') as f:
    f.write('WATCH_WHISPER_HOST = '+x['host']+'\nWATCH_WHISPER_PIN = '+x['pin']+'\n')
print('Prepared local Mac address and certificate pin; private identity stays on Mac.')
PY
