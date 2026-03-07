#!/bin/bash
# Package caboose fat binary with embedded ZIP filesystem
#
# This script packages the fat (x86_64 + aarch64) caboose binary with
# fat mtsh.com and lsdir.com binaries embedded in /zip/.
#
# Usage: package_caboose_fat.sh [output-path]
#   output-path  Where to write the packaged binary
#                (default: releases/caboose.com)
#
set -e

REPO_ROOT="$(git rev-parse --show-toplevel)" || { echo "Error: not inside a git repo"; exit 1; }

RELEASES="$REPO_ROOT/releases"
FASTERZIP="$RELEASES/fasterzip.com"
ZIPCOPY="$REPO_ROOT/.cosmocc/current/bin/zipcopy"

# Fat binaries from releases/
CABOOSE="$RELEASES/caboose.com"
MTSH="$RELEASES/mtsh.com"
LSDIR="$RELEASES/lsdir.com"

OUTPUT="${1:-$CABOOSE}"

# Validate prerequisites
for f in "$CABOOSE" "$MTSH" "$LSDIR"; do
  if [ ! -f "$f" ]; then
    echo "Error: $f not found"
    echo "Build fat binaries first: bin/build_mexican_toaster.sh"
    exit 1
  fi
done

if [ ! -f "$ZIPCOPY" ]; then
  echo "Error: zipcopy not found at $ZIPCOPY"
  echo "Run 'make' once to download the cosmocc toolchain."
  exit 1
fi

if [ ! -f "$FASTERZIP" ]; then
  echo "Error: fasterzip not found at $FASTERZIP"
  echo "Build it with: ./bake o//tool/build/fasterzip"
  exit 1
fi

# Build the ZIP content in a temp directory
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$STAGING/bin"
mkdir -p "$STAGING/app"

# Embed fat mtsh as /zip/bin/mtsh
cp "$MTSH" "$STAGING/bin/mtsh"
chmod +x "$STAGING/bin/mtsh"

# Embed fat lsdir as /zip/bin/lsdir
cp "$LSDIR" "$STAGING/bin/lsdir"
chmod +x "$STAGING/bin/lsdir"

# Embed fasterzip and zipcopy for persist (no system zip dependency)
cp "$FASTERZIP" "$STAGING/bin/fasterzip"
chmod +x "$STAGING/bin/fasterzip"
cp "$ZIPCOPY" "$STAGING/bin/zipcopy"
chmod +x "$STAGING/bin/zipcopy"

# Create a README for the embedded filesystem
cat > "$STAGING/README.txt" <<'EOF'
Mexican Toaster - Caboose
An APE binary with an embedded writable filesystem.
Run 'caboose help' for usage.
EOF

# Create a placeholder app directory
cat > "$STAGING/app/hello.txt" <<'EOF'
Hello from the Mexican Toaster!
This file lives inside /zip/app/ in the APE binary.
EOF

# Embed SSL root certificates (needed for gem install over HTTPS)
SSL_ROOT="$REPO_ROOT/usr/share/ssl/root"
if [ -d "$SSL_ROOT" ]; then
  mkdir -p "$STAGING/usr/share/ssl/root"
  cp "$SSL_ROOT"/*.pem "$STAGING/usr/share/ssl/root/"
fi

# Record bare binary size so persist can truncate back to it
# For fat binaries, we use the current size as the "bare" size
(stat -f%z "$CABOOSE" 2>/dev/null || stat -c%s "$CABOOSE") > "$STAGING/.bare_size"

# Resolve both paths to absolute for comparison and for fasterzip
OUTPUT="$(cd "$(dirname "$OUTPUT")" && pwd)/$(basename "$OUTPUT")"
CABOOSE="$(cd "$(dirname "$CABOOSE")" && pwd)/$(basename "$CABOOSE")"

# Copy fat binary as base, then append ZIP entries with fasterzip
# Only copy if input and output are different (input might be the same as output)
if [ "$CABOOSE" != "$OUTPUT" ]; then
  cp "$CABOOSE" "$OUTPUT"
fi

(cd "$STAGING" && "$FASTERZIP" -r "$OUTPUT" .)

echo "Packaged: $OUTPUT"
echo "  mtsh:       /zip/bin/mtsh (fat binary)"
echo "  lsdir:      /zip/bin/lsdir (fat binary)"
echo "  fasterzip:  /zip/bin/fasterzip"
echo "  zipcopy:    /zip/bin/zipcopy"
echo "  README.txt: /zip/README.txt"
echo "  app/:       /zip/app/"
echo "  ssl certs:  /zip/usr/share/ssl/root/*.pem"
