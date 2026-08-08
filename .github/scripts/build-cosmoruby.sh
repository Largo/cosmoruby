#!/usr/bin/env bash
#
# Build CosmoRuby (ruby.com / irb.com / miniruby.com) from a clean checkout.
#
# Requirements on the host:
#   * cargo + rustc            YJIT is hard-enabled in the committed config.h
#   * zip                      assemble_stdlib.sh
#   * network                  cosmocc 3.9.2 is auto-downloaded into .cosmocc/
#   * COSMO_RUBY=<ruby.com>    a prebuilt CosmoRuby used for codegen
#                              (host ruby == vendored version also works, but
#                               nothing ships Ruby 4.0.6 as a host package)
#
# Why this is a script and not five lines of YAML: `make` in this tree can
# exit 0 without having linked anything, and it fails transiently (tlscc
# "Error 90", rbconfig.rb.tmp ENOENT).  So we drive make in a loop and decide
# success from the artifacts on disk -- never from $?.
#
# Usage: .github/scripts/build-cosmoruby.sh
# Env:   JOBS, CARGO, MAX_ATTEMPTS, MIN_BIN_BYTES, MIN_COM_BYTES

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
CARGO="${CARGO:-$(command -v cargo || true)}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-4}"
BIN_DIR="o/third_party/ruby"
TARGETS="ruby irb miniruby"
# Reference sizes (2026-08, x86_64): ruby 12.7M, ruby.com 21.2M, miniruby.com 18.7M
MIN_BIN_BYTES="${MIN_BIN_BYTES:-5000000}"
MIN_COM_BYTES="${MIN_COM_BYTES:-10000000}"

log() { printf '\n=== %s ===\n' "$*"; }
die() { printf '\n!!! %s\n' "$*" >&2; exit 1; }
bytes() { wc -c < "$1" | tr -d ' '; }

[ -n "${COSMO_RUBY:-}" ] || die "COSMO_RUBY is not set (path to a bootstrap ruby.com)"
[ -x "$COSMO_RUBY" ] || die "COSMO_RUBY=$COSMO_RUBY is not executable"
[ -n "$CARGO" ] || die "cargo not found; YJIT is hard-enabled (USE_YJIT 1) and cannot be turned off"

export COSMO_RUBY
export HOST_RUBY="$COSMO_RUBY"

log "environment"
echo "repo      : $REPO_ROOT"
echo "jobs      : $JOBS"
echo "cargo     : $CARGO ($($CARGO --version 2>&1 | head -1))"
echo "bootstrap : $COSMO_RUBY"
"$COSMO_RUBY" --version || die "bootstrap ruby does not run on this host"

# ---------------------------------------------------------------- configure

log "regenerating ruby_shims/ (never committed upstream)"
bash third_party/ruby/gen_ruby_shims.sh || die "gen_ruby_shims.sh failed"

log "configure: static-linked extensions"
bash third_party/ruby/cosmo_configure.sh --with-static-linked-ext \
  || die "cosmo_configure.sh --with-static-linked-ext failed"

log "configure: bootstrap (mtdeps + automate_mkdeps)"
BOOTSTRAP_JOBS="$JOBS" bash third_party/ruby/cosmo_configure.sh --bootstrap \
  || die "cosmo_configure.sh --bootstrap failed"

# --bootstrap silently resets the tree to *plugin* mode; the committed
# generated files are static mode.  Re-assert it or the build links the
# wrong extension machinery.
log "configure: re-assert static mode (--bootstrap resets it to plugin)"
bash third_party/ruby/cosmo_configure.sh --with-static-linked-ext \
  || die "cosmo_configure.sh --with-static-linked-ext (2nd) failed"
grep -q "EXTSTATIC 1" third_party/ruby/include/ruby/config.mode.h \
  || die "config.mode.h is not in static mode after configure"

# -------------------------------------------------------------------- build

STAMP="$(mktemp)"
trap 'rm -f "$STAMP"' EXIT

targets_ok() {
  local t f sz
  for t in $TARGETS; do
    f="$BIN_DIR/$t"
    [ -f "$f" ] || { echo "  missing: $f"; return 1; }
    [ "$f" -nt "$STAMP" ] || { echo "  stale (older than build start): $f"; return 1; }
    sz="$(bytes "$f")"
    [ "$sz" -ge "$MIN_BIN_BYTES" ] || { echo "  too small: $f ($sz bytes)"; return 1; }
    echo "  ok: $f ($sz bytes)"
  done
  return 0
}

built=0
for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  log "make attempt $attempt/$MAX_ATTEMPTS (-j$JOBS)"
  start=$(date +%s)
  make -j"$JOBS" COSMO_RUBY="$COSMO_RUBY" CARGO="$CARGO" \
       o//third_party/ruby/ruby \
       o//third_party/ruby/irb \
       o//third_party/ruby/miniruby
  rc=$?
  echo "make exited $rc after $(( $(date +%s) - start ))s"
  log "verifying link products (make's exit status is not evidence)"
  if targets_ok; then built=1; break; fi
  echo "not all targets linked; retrying"
done
[ "$built" = 1 ] || die "build failed: targets missing/stale after $MAX_ATTEMPTS attempts"

# ------------------------------------------------------------------ package

log "package_ruby.sh (embed stdlib zip -> *.com)"
bash third_party/ruby/package_ruby.sh || die "package_ruby.sh failed"

log "verifying packaged APEs"
fail=0
for t in $TARGETS; do
  f="$BIN_DIR/$t.com"
  if [ ! -f "$f" ]; then echo "  missing: $f"; fail=1; continue; fi
  if [ ! "$f" -nt "$STAMP" ]; then echo "  stale: $f"; fail=1; continue; fi
  sz="$(bytes "$f")"
  if [ "$sz" -lt "$MIN_COM_BYTES" ]; then echo "  too small: $f ($sz)"; fail=1; continue; fi
  magic="$(head -c 6 "$f")"
  if [ "$magic" != "MZqFpD" ]; then echo "  not an APE ($magic): $f"; fail=1; continue; fi
  echo "  ok: $f ($sz bytes, APE)"
done
[ "$fail" = 0 ] || die "packaging verification failed"

log "host smoke check"
chmod +x "$BIN_DIR"/*.com
"$BIN_DIR/ruby.com" -e 'puts RUBY_DESCRIPTION; puts RUBY_PLATFORM' || die "packaged ruby.com does not run on the build host"

log "build complete"
ls -l "$BIN_DIR"/ruby.com "$BIN_DIR"/irb.com "$BIN_DIR"/miniruby.com
