#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
micodex_config="${1:-/tmp/micodex-wifi.xcconfig}"
micodex_prepare_dir="$(mktemp -d /tmp/micodex-prepare.XXXXXX)"
trap 'rm -rf "$micodex_prepare_dir"' EXIT
swiftc -swift-version 5 -emit-library -emit-module -module-name MicodexCore Sources/MicodexCore/*.swift \
    -emit-module-path "$micodex_prepare_dir/MicodexCore.swiftmodule" -o "$micodex_prepare_dir/libMicodexCore.dylib"
swiftc -swift-version 5 -I "$micodex_prepare_dir" -L "$micodex_prepare_dir" -lMicodexCore \
    -Xlinker -rpath -Xlinker "$micodex_prepare_dir" \
    Mac/LocalTLSIdentity.swift scripts/prepare-wifi.swift -o "$micodex_prepare_dir/prepare"
"$micodex_prepare_dir/prepare" > "$micodex_prepare_dir/config.json"
python3 - "$micodex_prepare_dir/config.json" "$micodex_config" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]))
with open(sys.argv[2],'w') as f:
    f.write('MICODEX_HOST = '+x['host']+'\nMICODEX_PIN = '+x['pin']+'\n')
print('Prepared local Mac address and certificate pin; private identity stays on Mac.')
PY
