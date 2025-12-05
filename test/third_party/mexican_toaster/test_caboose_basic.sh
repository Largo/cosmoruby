#!/bin/bash
# Basic sanity for caboose command entrypoints (no embedded /zip required)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
CABOOSE_BIN="$ROOT/o//third_party/mexican_toaster/caboose"

if [[ ! -x "$CABOOSE_BIN" ]]; then
  make -C "$ROOT" -j1 o//third_party/mexican_toaster/caboose
fi

"$CABOOSE_BIN" >/dev/null
"$CABOOSE_BIN" help >/dev/null
