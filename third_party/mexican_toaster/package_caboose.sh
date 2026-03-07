#!/bin/bash
# Package caboose with embedded ZIP filesystem
#
# Creates a caboose.com with mtsh, lsdir, README.txt and app/ directory
# embedded in /zip/ so that 'caboose toast' and 'caboose thaw' work.
#
# Usage: package_caboose.sh [output-path]
#   output-path  Where to write the packaged binary
#                (default: o//third_party/mexican_toaster/caboose.com)
#
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../.."
MODE="${MODE:-}"

# Resolve the build output directory
if [ -n "$MODE" ]; then
  BUILD="$REPO_ROOT/o/$MODE"
else
  BUILD="$REPO_ROOT/o"
fi

CABOOSE="$BUILD/third_party/mexican_toaster/caboose"
MTSH="$BUILD/third_party/mexican_toaster/mtsh.com"
LSDIR="$BUILD/third_party/mexican_toaster/lsdir.com"
FASTERZIP="$BUILD/tool/build/fasterzip"
ZIPCOPY="$REPO_ROOT/.cosmocc/current/bin/zipcopy"
OUTPUT="${1:-${CABOOSE}.com}"

# Validate prerequisites
for f in "$CABOOSE" "$MTSH" "$LSDIR"; do
  if [ ! -f "$f" ]; then
    echo "Error: $f not found"
    echo "Build first: make -j1 o//third_party/mexican_toaster"
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
  echo "Build it with: make -j1 o//tool/build/fasterzip"
  exit 1
fi

# Build the ZIP content in a temp directory
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$STAGING/bin"
mkdir -p "$STAGING/app"

# Embed mtsh as /zip/bin/mtsh
cp "$MTSH" "$STAGING/bin/mtsh"
chmod +x "$STAGING/bin/mtsh"

# Embed lsdir as /zip/bin/lsdir (used by 'ls' command)
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
stat -c%s "$CABOOSE" > "$STAGING/.bare_size"

# Copy base binary, then append ZIP entries directly with fasterzip
# OUTPUT must be absolute since fasterzip runs from STAGING directory
OUTPUT="$(cd "$(dirname "$OUTPUT")" && pwd)/$(basename "$OUTPUT")"
cp "$CABOOSE" "$OUTPUT"
(cd "$STAGING" && "$FASTERZIP" -r "$OUTPUT" .)

echo "Packaged: $OUTPUT"
echo "  mtsh:       /zip/bin/mtsh"
echo "  lsdir:      /zip/bin/lsdir"
echo "  fasterzip:  /zip/bin/fasterzip"
echo "  zipcopy:    /zip/bin/zipcopy"
echo "  README.txt: /zip/README.txt"
echo "  app/:       /zip/app/"
echo "  ssl certs:  /zip/usr/share/ssl/root/*.pem"
