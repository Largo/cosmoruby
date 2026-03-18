#!/bin/bash
# Package caboose with embedded ZIP filesystem
#
# Creates a caboose.com with mtsh, lsdir, README.txt and app/ directory
# embedded in /zip/ so that 'caboose toast' and 'caboose thaw' work.
#
# Usage: package_caboose.sh [--fat] [output-path]
#   --fat        Use fat binaries from releases/ (x86_64 + aarch64)
#   output-path  Where to write the packaged binary
#                (default: o//...caboose.com or releases/caboose.com for --fat)
#
set -e

REPO_ROOT="$(git rev-parse --show-toplevel)" || { echo "Error: not inside a git repo"; exit 1; }

FAT=false
OUTPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fat)
      FAT=true
      shift
      ;;
    *)
      OUTPUT="$1"
      shift
      ;;
  esac
done

# Resolve input paths based on mode
if $FAT; then
  RELEASES="$REPO_ROOT/releases"
  CABOOSE="$RELEASES/caboose.com"
  MTSH="$RELEASES/mtsh.com"
  LSDIR="$RELEASES/lsdir.com"
  FASTERZIP="$RELEASES/fasterzip.com"
  OUTPUT="${OUTPUT:-$CABOOSE}"
  LABEL="fat binary"
else
  MODE="${MODE:-}"
  if [ -n "$MODE" ]; then
    BUILD="$REPO_ROOT/o/$MODE"
  else
    BUILD="$REPO_ROOT/o"
  fi
  CABOOSE="$BUILD/third_party/mexican_toaster/caboose"
  MTSH="$BUILD/third_party/mexican_toaster/mtsh.com"
  LSDIR="$BUILD/third_party/mexican_toaster/lsdir.com"
  FASTERZIP="$BUILD/tool/build/fasterzip"
  OUTPUT="${OUTPUT:-${CABOOSE}.com}"
  LABEL="single-arch"
fi

ZIPCOPY="$REPO_ROOT/.cosmocc/current/bin/zipcopy"

# Validate prerequisites
for f in "$CABOOSE" "$MTSH" "$LSDIR"; do
  if [ ! -f "$f" ]; then
    echo "Error: $f not found"
    if $FAT; then
      echo "Build fat binaries first: bin/build_mexican_toaster.sh"
    else
      echo "Build first: ./bake o//third_party/mexican_toaster"
    fi
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
(stat -f%z "$CABOOSE" 2>/dev/null || stat -c%s "$CABOOSE") > "$STAGING/.bare_size"

# Resolve OUTPUT to absolute path since fasterzip runs from STAGING directory
OUTPUT="$(cd "$(dirname "$OUTPUT")" && pwd)/$(basename "$OUTPUT")"
CABOOSE="$(cd "$(dirname "$CABOOSE")" && pwd)/$(basename "$CABOOSE")"

# Copy base binary then append ZIP entries with fasterzip
# Skip copy if input and output are the same file (fat mode repackaging in-place)
if [ "$CABOOSE" != "$OUTPUT" ]; then
  cp "$CABOOSE" "$OUTPUT"
fi
(cd "$STAGING" && "$FASTERZIP" -r "$OUTPUT" .)

echo "Packaged ($LABEL): $OUTPUT"
echo "  mtsh:       /zip/bin/mtsh"
echo "  lsdir:      /zip/bin/lsdir"
echo "  fasterzip:  /zip/bin/fasterzip"
echo "  zipcopy:    /zip/bin/zipcopy"
echo "  README.txt: /zip/README.txt"
echo "  app/:       /zip/app/"
echo "  ssl certs:  /zip/usr/share/ssl/root/*.pem"
