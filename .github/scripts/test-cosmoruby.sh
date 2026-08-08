#!/bin/sh
#
# Run the CosmoRuby acceptance tests against packaged APEs on any unix
# (Linux, macOS, BSD).  The Windows counterpart is test-cosmoruby.ps1 and
# runs the *same* .rb test files.
#
# Usage: .github/scripts/test-cosmoruby.sh [BINDIR]
#   BINDIR  directory holding ruby.com / irb.com / miniruby.com (default: dist)

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BINDIR="$(cd "${1:-$REPO_ROOT/dist}" && pwd)"
TESTS="$REPO_ROOT/third_party/ruby-wip-4.0.6/cosmo_tests"
RUBY="$BINDIR/ruby.com"
IRB="$BINDIR/irb.com"
MINIRUBY="$BINDIR/miniruby.com"

pass=0
fail=0

ok()   { pass=$((pass + 1)); printf '[PASS] %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '[FAIL] %s\n' "$1"; }
head_() { printf '\n----- %s -----\n' "$1"; }

chmod +x "$BINDIR"/*.com 2>/dev/null

head_ "environment"
uname -a
echo "bindir: $BINDIR"
ls -l "$BINDIR"

# ---------------------------------------------------------------- APE shape
head_ "APE header"
for f in "$RUBY" "$IRB" "$MINIRUBY"; do
  magic=$(head -c 6 "$f" 2>/dev/null)
  if [ "$magic" = "MZqFpD" ]; then ok "APE magic: $(basename "$f")"
  else bad "APE magic: $(basename "$f") (got '$magic')"; fi
done

# --------------------------------------------------------------- banner only
# NOTE: --version is deliberately *not* treated as a boot test.  It returns
# before ruby_opt_init(), which is where the 4.0.6 Windows segfault lived.
head_ "banner (informational, NOT a boot test)"
"$RUBY" --version || bad "ruby.com --version"

# --------------------------------------------------------------- boot + smoke
WORK="$(mktemp -d 2>/dev/null || mktemp -d -t cosmoruby)"
cd "$WORK" || exit 1
echo "work dir: $WORK"

head_ "ci_smoke.rb (real VM init: stdlib, filesystem, threads, sockets, sqlite3)"
if "$RUBY" "$TESTS/ci_smoke.rb" ci-arg-1 ci-arg-2; then
  ok "ci_smoke.rb"
else
  bad "ci_smoke.rb (exit $?)"
fi

head_ "exit-status propagation (ci_exit7.rb must exit 7)"
"$RUBY" "$TESTS/ci_exit7.rb"
rc=$?
if [ "$rc" -eq 7 ]; then ok "exit status 7"; else bad "exit status: got $rc, want 7"; fi

head_ "sqlite3 acceptance (cosmo_tests/test_sqlite3.rb)"
if "$RUBY" "$TESTS/test_sqlite3.rb"; then ok "test_sqlite3.rb"; else bad "test_sqlite3.rb"; fi

head_ "irb.com boots (pipe mode)"
out=$(echo 'puts 40 + 2' | "$IRB" 2>&1)
case "$out" in
  *42*) ok "irb.com" ;;
  *)    bad "irb.com :: $(printf '%s' "$out" | head -5)" ;;
esac

head_ "miniruby.com boots"
out=$("$MINIRUBY" -e 'puts "MINI-#{RUBY_VERSION}"' 2>&1)
case "$out" in
  MINI-4.*) ok "miniruby.com :: $out" ;;
  *)        bad "miniruby.com :: $(printf '%s' "$out" | head -5)" ;;
esac

head_ "clean environment (env -i, empty cwd)"
mkdir -p "$WORK/empty" && cd "$WORK/empty" || exit 1
out=$(env -i "$RUBY" -e 'require "json"; puts JSON.generate({"envless" => RUBY_VERSION})' 2>&1)
case "$out" in
  *envless*) ok "env -i :: $out" ;;
  *)         bad "env -i :: $(printf '%s' "$out" | head -5)" ;;
esac

head_ "yjit flag (Linux only by design)"
case "$(uname -s)" in
  Linux)
    out=$("$RUBY" --yjit -e 'puts RUBY_DESCRIPTION' 2>&1)
    case "$out" in
      *+YJIT*) ok "--yjit :: $out" ;;
      *)       bad "--yjit did not report +YJIT :: $out" ;;
    esac
    ;;
  *)
    echo "[SKIP] YJIT is gated on IsLinux() in this port (see PORTING-NOTES.md)"
    ;;
esac

cd "$REPO_ROOT" || exit 1
rm -rf "$WORK"

printf '\n===== RESULT: pass=%s fail=%s =====\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
