#!/bin/bash
# TestFlight and App Review use the same portable, public-compatible export.
set -euo pipefail
exec "$(dirname "$0")/prepare-app-store.sh" "$@"
