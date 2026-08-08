#!/usr/bin/env bash
#
# Build CosmoRuby (ruby.com / irb.com / miniruby.com) from a clean checkout.
#
# By default this produces x86_64-only APEs.  Set FAT=1 to produce *fat*
# APEs that carry x86_64 *and* aarch64 machine code in one file, the way
# igravious's v1.3.0 release did:
#
#     FAT=1 COSMO_RUBY=/path/to/bootstrap-ruby.com .github/scripts/build-cosmoruby.sh
#
# How the fat build works (see PORTING-NOTES.md "Fat (x86_64 + aarch64) APEs"):
#
#   1. configure once  -- the generated/config files are arch-independent and
#      the codegen interpreter ($COSMO_RUBY) always runs on the *build host*,
#      so there is exactly one configure step no matter how many arches.
#   2. make MODE=       -> o//third_party/ruby/*.dbg          (x86_64)
#   3. make m=aarch64   -> o/aarch64/third_party/ruby/*.dbg   (aarch64)
#   4. apelink the two .dbg files together with the x86_64 + aarch64 APE
#      loaders and the ape-m1.c macOS/Apple-Silicon loader source.
#   5. package_ruby.sh appends the one shared /zip stdlib to the fat APEs
#      (the stdlib is pure Ruby, so both halves read the same archive).
#
# Requirements on the host:
#   * cargo + rustc            YJIT is hard-enabled in the committed config.h
#                              (it is auto-disabled for the aarch64 half; see
#                              third_party/ruby/yjit/BUILD.mk)
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
# Env:   FAT, JOBS, CARGO, MAX_ATTEMPTS, MIN_BIN_BYTES, MIN_COM_BYTES

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

FAT="${FAT:-0}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
CARGO="${CARGO:-$(command -v cargo || true)}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-4}"
BIN_DIR="o/third_party/ruby"
ARM_BIN_DIR="o/aarch64/third_party/ruby"
FAT_DIR="releases"
DIST_DIR="${DIST_DIR:-dist}"
TARGETS="ruby irb miniruby"
# Reference sizes (2026-08, x86_64): ruby 12.7M, ruby.com 21.2M, miniruby.com 18.7M
# aarch64 halves are smaller (no YJIT staticlib): ruby 11.3M.
MIN_BIN_BYTES="${MIN_BIN_BYTES:-5000000}"
MIN_COM_BYTES="${MIN_COM_BYTES:-10000000}"

COSMOCC_BIN=".cosmocc/current/bin"
APELINK="$COSMOCC_BIN/apelink"
APE_X86="$COSMOCC_BIN/ape-x86_64.elf"
APE_ARM="$COSMOCC_BIN/ape-aarch64.elf"
APE_M1="$COSMOCC_BIN/ape-m1.c"

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
echo "fat       : $FAT"
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

# targets_ok <bin-dir> [require-dbg]
# Decides success from the files on disk, never from make's exit status.
targets_ok() {
  local dir="$1" want_dbg="${2:-0}"
  local t f sz
  for t in $TARGETS; do
    f="$dir/$t"
    [ -f "$f" ] || { echo "  missing: $f"; return 1; }
    [ "$f" -nt "$STAMP" ] || { echo "  stale (older than build start): $f"; return 1; }
    sz="$(bytes "$f")"
    [ "$sz" -ge "$MIN_BIN_BYTES" ] || { echo "  too small: $f ($sz bytes)"; return 1; }
    if [ "$want_dbg" = 1 ]; then
      [ -f "$f.dbg" ] || { echo "  missing: $f.dbg (apelink input)"; return 1; }
      [ "$f.dbg" -nt "$STAMP" ] || { echo "  stale: $f.dbg"; return 1; }
    fi
    echo "  ok: $f ($sz bytes)"
  done
  return 0
}

# build_arch <label> <make-args...> -- drives make in a loop for one arch
build_arch() {
  local label="$1" dir="$2"; shift 2
  local built=0 attempt rc start
  for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
    log "make [$label] attempt $attempt/$MAX_ATTEMPTS (-j$JOBS)"
    start=$(date +%s)
    make -j"$JOBS" COSMO_RUBY="$COSMO_RUBY" CARGO="$CARGO" "$@"
    rc=$?
    echo "make exited $rc after $(( $(date +%s) - start ))s"
    log "verifying link products [$label] (make's exit status is not evidence)"
    if targets_ok "$dir" "$FAT"; then built=1; break; fi
    echo "not all targets linked; retrying"
  done
  [ "$built" = 1 ] || die "build failed [$label]: targets missing/stale after $MAX_ATTEMPTS attempts"
}

build_arch x86_64 "$BIN_DIR" \
  o//third_party/ruby/ruby \
  o//third_party/ruby/irb \
  o//third_party/ruby/miniruby

if [ "$FAT" = 1 ]; then
  # The aarch64 half: same tree, same generated files, ARCH=aarch64.
  # yjit/BUILD.mk forces RUBY_YJIT_ENABLED=0 here (the Rust staticlib is
  # x86_64-unknown-linux-gnu only), so the weak no-op stubs in yjit.c stay
  # in place and rb_yjit_enabled_p is false for the whole aarch64 half.
  build_arch aarch64 "$ARM_BIN_DIR" \
    m=aarch64 \
    o/aarch64/third_party/ruby/ruby \
    o/aarch64/third_party/ruby/irb \
    o/aarch64/third_party/ruby/miniruby
fi

# ------------------------------------------------------------------ apelink

if [ "$FAT" = 1 ]; then
  log "apelink: combining x86_64 + aarch64 into fat APEs"
  for f in "$APELINK" "$APE_X86" "$APE_ARM" "$APE_M1"; do
    [ -f "$f" ] || die "missing $f (run make once to fetch the cosmocc toolchain)"
  done
  mkdir -p "$FAT_DIR"
  for t in $TARGETS; do
    "$APELINK" \
      -o "$FAT_DIR/$t.com" \
      -l "$APE_X86" \
      -l "$APE_ARM" \
      -M "$APE_M1" \
      "$BIN_DIR/$t.dbg" \
      "$ARM_BIN_DIR/$t.dbg" \
      || die "apelink failed for $t"
    echo "  linked $FAT_DIR/$t.com ($(bytes "$FAT_DIR/$t.com") bytes)"
  done
fi

# ------------------------------------------------------------------ package

# package_ruby.sh embeds the stdlib zip into releases/*.com (the fat APEs)
# and into o//third_party/ruby/*.com (the single-arch dev binaries).
log "package_ruby.sh (embed stdlib zip -> *.com)"
bash third_party/ruby/package_ruby.sh || die "package_ruby.sh failed"

if [ "$FAT" = 1 ]; then
  OUT_DIR="$FAT_DIR"
else
  OUT_DIR="$BIN_DIR"
fi

log "verifying packaged APEs in $OUT_DIR"
fail=0
for t in $TARGETS; do
  f="$OUT_DIR/$t.com"
  if [ ! -f "$f" ]; then echo "  missing: $f"; fail=1; continue; fi
  if [ ! "$f" -nt "$STAMP" ]; then echo "  stale: $f"; fail=1; continue; fi
  sz="$(bytes "$f")"
  if [ "$sz" -lt "$MIN_COM_BYTES" ]; then echo "  too small: $f ($sz)"; fail=1; continue; fi
  magic="$(head -c 6 "$f")"
  if [ "$magic" != "MZqFpD" ]; then echo "  not an APE ($magic): $f"; fail=1; continue; fi
  echo "  ok: $f ($sz bytes, APE)"
done
[ "$fail" = 0 ] || die "packaging verification failed"

chmod +x "$OUT_DIR"/*.com

if [ "$FAT" = 1 ]; then
  log "verifying fat APE contents (x86_64 ELF + aarch64 ELF + Mach-O + M1 loader)"
  # Use the freshly built x86_64 ruby.com as the inspector; it always exists
  # on the build host, so this check never silently skips.
  RUBY_FOR_CHECKS="$REPO_ROOT/$BIN_DIR/ruby.com" \
    bash ./check_ape.sh --verify "$OUT_DIR/ruby.com" \
    || die "$OUT_DIR/ruby.com is not a complete fat APE"
fi

log "host smoke check"
"$OUT_DIR/ruby.com" -e 'puts RUBY_DESCRIPTION; puts RUBY_PLATFORM' \
  || die "packaged ruby.com does not run on the build host"

if [ "$FAT" = 1 ] && command -v qemu-aarch64 >/dev/null 2>&1; then
  # Not a substitute for a real ARM runner, but it catches an aarch64 half
  # that does not boot at all.  qemu-aarch64 can only execute AArch64
  # instructions, so anything that runs here really is the ARM half.
  log "aarch64 smoke check under qemu-user (build/bootstrap/ape.aarch64 loader)"
  qemu-aarch64 build/bootstrap/ape.aarch64 "$OUT_DIR/ruby.com" \
    -e 'puts RUBY_DESCRIPTION' \
    || die "aarch64 half of $OUT_DIR/ruby.com does not boot under qemu-aarch64"
fi

# ------------------------------------------------------------------- stage

log "staging artifacts into $DIST_DIR"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"
for t in $TARGETS; do cp "$OUT_DIR/$t.com" "$DIST_DIR/"; done
chmod +x "$DIST_DIR"/*.com
(cd "$DIST_DIR" && sha256sum ./*.com > SHA256SUMS && cat SHA256SUMS)

log "build complete"
ls -l "$DIST_DIR"/*.com
