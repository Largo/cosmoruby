#!/bin/sh
# Generate a linker response file containing -u <symbol> entries for
# undefined symbols referenced by the provided objects/archives.
# Usage: generate_undefs.sh <output.args> <obj_or_archive>...
set -e

if [ $# -lt 2 ]; then
  echo "usage: $0 <output.args> <obj_or_archive>..." >&2
  exit 64
fi

OUT="$1"
shift

NM_BIN="${NM:-nm}"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# Collect undefined symbols (POSIX format: name type ...)
"$NM_BIN" -u -P "$@" 2>/dev/null | awk '$2=="U"{print $1}' | sort -u >"$tmp"

# Emit response file (one -u per line)
awk '{printf "-u %s\n", $0}' "$tmp" >"$OUT"
