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

# The status the shell sees must be exactly the status the script asked for,
# on every platform.  Windows was the odd one out: cosmopolitan encodes a
# POSIX wait status (status << 8) into the Windows exit code, so `exit 3`
# surfaced as 768 in cmd and PowerShell.  Kept identical here and in the
# PowerShell script so the two cannot drift.
head_ "exact exit statuses (0, 1, 3, 7, 255, >255, uncaught exception)"
exit_ok=1
for want in 0 1 3 7 255; do
  "$RUBY" -e "exit $want"; got=$?
  [ "$got" -eq "$want" ] || { exit_ok=0; bad "exit $want: got $got"; }
done
# Ruby and POSIX narrow the status to eight bits: 300 & 0xff == 44.
"$RUBY" -e 'exit 300'; got=$?
[ "$got" -eq 44 ] || { exit_ok=0; bad "exit 300: got $got, want 44"; }
# exit! skips the teardown but must still report honestly.
"$RUBY" -e 'exit! 3'; got=$?
[ "$got" -eq 3 ] || { exit_ok=0; bad "exit! 3: got $got, want 3"; }
# An uncaught exception is 1.
"$RUBY" -e 'raise "boom"' 2>/dev/null; got=$?
[ "$got" -eq 1 ] || { exit_ok=0; bad "uncaught exception: got $got, want 1"; }
[ "$exit_ok" -eq 1 ] && ok "exit statuses are exact (incl. exit!, >255, exceptions)"

head_ "socket diagnostic (cosmo_tests/ci_diag_sockets.rb, informational, never fails)"
"$RUBY" "$TESTS/ci_diag_sockets.rb" || true

head_ "socket/TCP acceptance (cosmo_tests/test_sockets.rb)"
if "$RUBY" "$TESTS/test_sockets.rb"; then ok "test_sockets.rb"; else bad "test_sockets.rb"; fi

head_ "sqlite3 acceptance (cosmo_tests/test_sqlite3.rb)"
if "$RUBY" "$TESTS/test_sqlite3.rb"; then ok "test_sqlite3.rb"; else bad "test_sqlite3.rb"; fi

head_ "nokogiri acceptance (cosmo_tests/test_nokogiri.rb)"
if "$RUBY" "$TESTS/test_nokogiri.rb"; then ok "test_nokogiri.rb"; else bad "test_nokogiri.rb"; fi

head_ "bigdecimal acceptance (cosmo_tests/test_bigdecimal.rb)"
if "$RUBY" "$TESTS/test_bigdecimal.rb"; then ok "test_bigdecimal.rb"; else bad "test_bigdecimal.rb"; fi

head_ "racc acceptance (cosmo_tests/test_racc.rb)"
if "$RUBY" "$TESTS/test_racc.rb"; then ok "test_racc.rb"; else bad "test_racc.rb"; fi

head_ "nio4r acceptance (cosmo_tests/test_nio4r.rb)"
if "$RUBY" "$TESTS/test_nio4r.rb"; then ok "test_nio4r.rb"; else bad "test_nio4r.rb"; fi

head_ "puma acceptance (cosmo_tests/test_puma.rb)"
if "$RUBY" "$TESTS/test_puma.rb"; then ok "test_puma.rb"; else bad "test_puma.rb"; fi

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

# YJIT is a Rust staticlib built for x86_64-unknown-linux-gnu.  It is linked
# only into the x86_64 half of the APE and initialised only under IsLinux(),
# so it genuinely runs on exactly one platform.  Everywhere else `--yjit` must
# still be *accepted* -- it used to raise "invalid YJIT option ''" on the
# aarch64 half of a fat build -- and RubyVM::YJIT.enabled? must be false.
# RUBY_DESCRIPTION's +YJIT is set by option parsing and is not evidence.
# The expectation is computed inside the interpreter (RUBY_PLATFORM + uname),
# not from the shell, so it is also correct when the aarch64 half is driven
# through qemu-user on an x86-64 host.
head_ "yjit flag (accepted everywhere; actually live on Linux/x86_64 only)"
out=$("$RUBY" --yjit -e '
  require "etc"
  want = RUBY_PLATFORM.start_with?("x86_64") && (Etc.uname[:sysname] rescue "") == "Linux"
  got  = RubyVM::YJIT.enabled?
  puts(want == got ? "yjit-ok want=#{want} got=#{got}" : "yjit-MISMATCH want=#{want} got=#{got}")' 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then
  bad "--yjit rejected (exit $rc) :: $out"
else
  case "$out" in
    yjit-ok*) ok "--yjit :: $out" ;;
    *)        bad "--yjit :: $out" ;;
  esac
fi

# A self-executing APE: dist/zipmain.com is ruby.com with a two-file app
# appended by the build job's `zip`.  ruby.c runs /zip/main.rb when the
# command line names no other program, so the packed binary is the app.
# Checked from an empty cwd so nothing can be picked up from the disk.
head_ "self-executing APE (/zip/main.rb auto-run)"
ZM="$BINDIR/zipmain.com"
if [ ! -f "$ZM" ]; then
  bad "zipmain.com missing from $BINDIR"
else
  chmod +x "$ZM" 2>/dev/null
  out=$("$ZM" zm-a zm-b 2>&1); rc=$?
  echo "$out"
  case "$out" in
    *'"marker":"zipmain"'*) ok "zip main auto-run" ;;
    *)                      bad "zip main auto-run :: $(printf '%s' "$out" | head -5)" ;;
  esac
  case "$out" in
    *'"argv":["zm-a","zm-b"]'*) ok "zip main ARGV passthrough" ;;
    *)                          bad "zip main ARGV passthrough" ;;
  esac
  case "$out" in
    *'"zero":"/zip/main.rb"'*'"dir":"/zip"'*) ok 'zip main $0 and __dir__' ;;
    *)                                        bad 'zip main $0 and __dir__' ;;
  esac
  case "$out" in
    *'"lib":"require_relative-ok"'*) ok "zip main multi-file app (require_relative)" ;;
    *)                               bad "zip main multi-file app (require_relative)" ;;
  esac
  if [ "$rc" -eq 7 ]; then ok "zip main exit status 7"; else bad "zip main exit status: got $rc, want 7"; fi

  # A packed binary is an application, so Ruby claims NONE of the command
  # line: option-shaped arguments reach the app instead of Ruby's option
  # parser, which is what makes `myapp.com --version` behave like a native
  # binary's.  This is the single most common shape of a CLI invocation.
  out=$("$ZM" --verbose -e --version -- x 2>&1); rc=$?
  case "$out" in
    *'"argv":["--verbose","-e","--version","--","x"]'*)
      ok "zip main takes the whole command line (leading flags reach the app)" ;;
    *) bad "zip main leading flags :: $(printf '%s' "$out" | head -5)" ;;
  esac
  case "$out" in
    *invalid\ option*) bad "zip main: Ruby parsed an application argument" ;;
    *)                 ok "zip main: no interpreter option parsing" ;;
  esac

  # Exit status is the app's, exactly, on every platform.  On Windows this
  # used to be status<<8 (cosmopolitan encodes a POSIX wait status into the
  # Windows exit code); ruby.c now bypasses that.
  exit_ok=1
  for want in 0 1 3 7 255; do
    "$ZM" "--exit=$want" >/dev/null 2>&1; got=$?
    [ "$got" -eq "$want" ] || { exit_ok=0; bad "zip main --exit=$want: got $got"; }
  done
  [ "$exit_ok" -eq 1 ] && ok "zip main exit statuses 0/1/3/7/255 are exact"

  # Interpreter options stay reachable through RUBYOPT, which is how a packed
  # binary gets -I / -r / -w / --yjit without stealing them from the app.
  out=$(RUBYOPT=-w "$ZM" 2>&1)
  case "$out" in
    *'"verbose":true'*) ok "RUBYOPT still reaches the interpreter" ;;
    *)                  bad "RUBYOPT :: $(printf '%s' "$out" | head -5)" ;;
  esac

  # The escape hatch turns a packed binary back into a plain interpreter.
  out=$(COSMORUBY_NO_ZIP_MAIN=1 "$ZM" -e 'puts "hatch-ok"' 2>&1)
  case "$out" in
    hatch-ok*) ok "COSMORUBY_NO_ZIP_MAIN=1 suppresses auto-run" ;;
    *)         bad "COSMORUBY_NO_ZIP_MAIN=1 :: $(printf '%s' "$out" | head -5)" ;;
  esac

  # ...and an unpacked ruby.com must be completely unaffected: no /zip/main.rb
  # means the old stdin path, which is what every existing use depends on.
  out=$(echo 'puts "stdin-ok"' | "$RUBY" 2>&1)
  case "$out" in
    stdin-ok*) ok "plain ruby.com still reads stdin (no auto-run)" ;;
    *)         bad "plain ruby.com stdin :: $(printf '%s' "$out" | head -5)" ;;
  esac
fi

cd "$REPO_ROOT" || exit 1
rm -rf "$WORK"

printf '\n===== RESULT: pass=%s fail=%s =====\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
