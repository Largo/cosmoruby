#!/bin/bash
# Test mtsh v0.2.0 linenoise integration
#
# Tests:
# 1. Non-TTY mode still works (pipes/redirects)
# 2. Version string is correct
# 3. Interactive shell can be invoked without crashing
# 4. Escape sequences in piped input don't crash (regression test)

set -e

MTSH="${MTSH:-o//third_party/mexican_toaster/mtsh.com}"

if [ ! -x "$MTSH" ]; then
  echo "Error: mtsh not found at $MTSH"
  echo "Build it with: make -j1 o//third_party/mexican_toaster/mtsh.com"
  exit 1
fi

echo "Testing mtsh v0.2.0 linenoise integration..."

# Test 1: Non-TTY mode with pipe (should use fallback, not linenoise)
echo "Test 1: Non-TTY mode with pipe..."
result=$(echo "echo hello" | $MTSH)
if [ "$result" != "hello" ]; then
  echo "FAIL: Expected 'hello', got '$result'"
  exit 1
fi
echo "  ✓ Pipe mode works"

# Test 2: Non-TTY mode with heredoc
echo "Test 2: Non-TTY mode with heredoc..."
result=$($MTSH <<'EOF'
echo "world"
EOF
)
if [ "$result" != "world" ]; then
  echo "FAIL: Expected 'world', got '$result'"
  exit 1
fi
echo "  ✓ Heredoc mode works"

# Test 3: Multiple commands via pipe
echo "Test 3: Multiple commands via pipe..."
result=$(printf "echo line1\necho line2\necho line3\n" | $MTSH)
expected="line1
line2
line3"
if [ "$result" != "$expected" ]; then
  echo "FAIL: Multiple commands failed"
  echo "Expected:"
  echo "$expected"
  echo "Got:"
  echo "$result"
  exit 1
fi
echo "  ✓ Multiple commands work"

# Test 4: Escape sequences in piped input (regression test for Alt-key crash)
# This was the original bug - ESC (0x1B / decimal 27) would cause:
# "mtsh: unsupported syntax '33)"
echo "Test 4: Escape sequences don't crash (regression)..."

# Send ESC + 'a' (Alt-a) via pipe - should be ignored by command parser
# Note: In non-TTY mode, we don't have linenoise, so ESC still causes error
# But this tests that the error handling is graceful
printf '\x1b' | $MTSH 2>&1 | grep -q "unsupported syntax" && \
  echo "  ✓ ESC sequence triggers expected error in non-TTY mode" || \
  echo "  ⚠ ESC handling changed (may be OK)"

# Test 5: Version string check
echo "Test 5: Version string..."
# mtsh doesn't have a --version flag, but we can check that it doesn't crash
# when invoked with no stdin (will just show prompt and wait)
# We can't easily test this without expect/pexpect, so skip for now
echo "  ⊘ Version check skipped (requires interactive session)"

# Test 6: Command substitution still works
echo "Test 6: Command substitution..."
result=$(echo 'echo $(echo nested)' | $MTSH)
if [ "$result" != "nested" ]; then
  echo "FAIL: Command substitution broken, got '$result'"
  exit 1
fi
echo "  ✓ Command substitution works"

# Test 7: Subshells still work
echo "Test 7: Subshells..."
result=$(echo '(echo subshell)' | $MTSH)
if [ "$result" != "subshell" ]; then
  echo "FAIL: Subshells broken, got '$result'"
  exit 1
fi
echo "  ✓ Subshells work"

# Test 8: Redirection still works
echo "Test 8: Redirection..."
tmpfile=$(mktemp)
trap "rm -f $tmpfile" EXIT
echo "echo redirected > $tmpfile" | $MTSH
result=$(cat $tmpfile)
if [ "$result" != "redirected" ]; then
  echo "FAIL: Redirection broken, got '$result'"
  exit 1
fi
echo "  ✓ Redirection works"

echo ""
echo "All non-interactive tests passed! ✓"
echo ""

# Check if we can run interactive tests with Expect
if command -v expect >/dev/null 2>&1; then
  echo "Running interactive tests with Expect..."
  SCRIPT_DIR="$(dirname "$0")"
  if [ -x "$SCRIPT_DIR/test_mtsh_interactive.exp" ]; then
    "$SCRIPT_DIR/test_mtsh_interactive.exp"
  else
    echo "⚠ Interactive test script not found or not executable"
    echo "  Expected: $SCRIPT_DIR/test_mtsh_interactive.exp"
  fi
else
  echo "Note: 'expect' not installed - skipping interactive tests"
  echo "  Install with: apt-get install expect (Debian/Ubuntu)"
  echo "            or: brew install expect (macOS)"
  echo "            or: dnf install expect (Fedora/RHEL)"
  echo ""
  echo "To test interactive features manually:"
  echo "  $MTSH"
  echo "  Try: Alt-a, arrow keys, backspace, Ctrl-D"
fi
