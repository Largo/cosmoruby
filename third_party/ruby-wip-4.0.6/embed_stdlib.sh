#!/bin/bash
# Embed ruby-stdlib.zip into an APE binary using zipcopy
#
# Usage: embed_stdlib.sh <binary> [stdlib.zip]
#   binary      Path to the APE binary (e.g. releases/ruby.com)
#   stdlib.zip  Path to the stdlib ZIP (default: <repo>/o/ruby-stdlib.zip)
#
# Run assemble_stdlib.sh first to create the ZIP.

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)" || { echo "Error: not inside a git repo"; exit 1; }

BINARY="${1:?Usage: embed_stdlib.sh <binary> [stdlib.zip]}"
STDLIB_ZIP="${2:-$REPO_ROOT/o/ruby-stdlib.zip}"

# Convert relative paths to absolute
[[ "$BINARY" != /* ]] && BINARY="$PWD/$BINARY"
[[ "$STDLIB_ZIP" != /* ]] && STDLIB_ZIP="$PWD/$STDLIB_ZIP"

ZIPCOPY="$REPO_ROOT/.cosmocc/current/bin/zipcopy"

if [ ! -f "$BINARY" ]; then
  echo "Error: binary not found: $BINARY"
  exit 1
fi

if [ ! -f "$STDLIB_ZIP" ]; then
  echo "Error: stdlib ZIP not found: $STDLIB_ZIP"
  echo "Run assemble_stdlib.sh first."
  exit 1
fi

if [ ! -f "$ZIPCOPY" ]; then
  echo "Error: zipcopy not found at $ZIPCOPY"
  echo "Run 'make' once to download the cosmocc toolchain."
  exit 1
fi

echo "Embedding stdlib into $(basename "$BINARY")"
"$ZIPCOPY" "$STDLIB_ZIP" "$BINARY"
