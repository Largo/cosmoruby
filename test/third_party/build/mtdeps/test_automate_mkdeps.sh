#!/bin/bash
# Sanity and smoke tests for automate_mkdeps
#
# Covers:
#   - CLI flag parsing and validation
#   - --help, --count, --info flags
#   - H1 security fix: IsShellSafe rejects shell metacharacters in
#     MKDEPS and MODE environment variables

set -u

TOOL="o//third_party/build/mtdeps/automate_mkdeps"
PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Run from the repo root (automate_mkdeps does FindRepoRoot + chdir)
cd "$(git rev-parse --show-toplevel)" || exit 1

test_exit() {
    local name="$1"
    local expected_exit="$2"
    shift 2
    local cmd=("$@")

    echo -n "Testing $name... "
    "${cmd[@]}" >/dev/null 2>&1
    local exit_code=$?

    if [ "$exit_code" -eq "$expected_exit" ]; then
        echo -e "${GREEN}PASS${NC}"
        ((PASS++))
    else
        echo -e "${RED}FAIL${NC} (expected exit $expected_exit, got $exit_code)"
        ((FAIL++))
    fi
}

test_output_contains() {
    local name="$1"
    local needle="$2"
    shift 2
    local cmd=("$@")

    echo -n "Testing $name... "
    local output
    output=$("${cmd[@]}" 2>&1)
    local exit_code=$?

    if echo "$output" | grep -qF -- "$needle"; then
        echo -e "${GREEN}PASS${NC}"
        ((PASS++))
    else
        echo -e "${RED}FAIL${NC} (output does not contain '$needle')"
        echo "  Output: $(echo "$output" | head -5)"
        ((FAIL++))
    fi
}

test_output_not_contains() {
    local name="$1"
    local needle="$2"
    shift 2
    local cmd=("$@")

    echo -n "Testing $name... "
    local output
    output=$("${cmd[@]}" 2>&1)

    if echo "$output" | grep -qF -- "$needle"; then
        echo -e "${RED}FAIL${NC} (output unexpectedly contains '$needle')"
        ((FAIL++))
    else
        echo -e "${GREEN}PASS${NC}"
        ((PASS++))
    fi
}

if [ ! -x "$TOOL" ]; then
    echo "Error: $TOOL not found."
    echo "Build with: make -j1 o//third_party/build/mtdeps/automate_mkdeps"
    exit 1
fi

echo "=== automate_mkdeps Sanity & Smoke Tests ==="
echo

# ---------------------------------------------------------------
# CLI flag parsing
# ---------------------------------------------------------------
echo "--- Flag Parsing ---"

test_output_contains "--help shows usage" \
    "Usage:" \
    "$TOOL" --help

test_output_contains "--help mentions --module" \
    "--module=NAME" \
    "$TOOL" --help

test_exit "no args = error" 1 \
    "$TOOL"

test_exit "--help = success" 0 \
    "$TOOL" --help

test_exit "unknown flag = error" 1 \
    "$TOOL" --bogus-flag

test_exit "manual mode missing --deps-mk = error" 1 \
    "$TOOL" --hdrs-var=FOO --incs-var=BAR

test_exit "manual mode missing --hdrs-var = error" 1 \
    "$TOOL" --deps-mk=foo.mk --incs-var=BAR

test_exit "manual mode missing --incs-var = error" 1 \
    "$TOOL" --deps-mk=foo.mk --hdrs-var=FOO

# ---------------------------------------------------------------
# --module=ruby --count (reads deps.mk, prints counts)
# ---------------------------------------------------------------
echo
echo "--- Module Defaults (--count) ---"

# --count should succeed and print entry counts
test_exit "--module=ruby --count exits 0" 0 \
    "$TOOL" --module=ruby --count

test_output_contains "--count prints HDRS" \
    "HDRS" \
    "$TOOL" --module=ruby --count

test_output_contains "--count prints INCS" \
    "INCS" \
    "$TOOL" --module=ruby --count

# ---------------------------------------------------------------
# --module=ruby --info (prints statistics)
# ---------------------------------------------------------------
echo
echo "--- Module Info (--info) ---"

test_exit "--module=ruby --info exits 0" 0 \
    "$TOOL" --module=ruby --info

test_output_contains "--info prints module name" \
    "ruby" \
    "$TOOL" --module=ruby --info

test_output_contains "--info prints entries" \
    "entries" \
    "$TOOL" --module=ruby --info

# ---------------------------------------------------------------
# H1 Security: IsShellSafe rejects metacharacters in env vars
# ---------------------------------------------------------------
echo
echo "--- Shell Injection Protection (H1) ---"

# MKDEPS and MODE are validated early in main() by IsShellSafe(),
# before any system()/popen() call.  These tests confirm that shell
# metacharacters are rejected with a clear error message.

test_output_contains "MKDEPS with semicolon rejected" \
    "shell metacharacters" \
    env MKDEPS="x; rm -rf /tmp/pwned; #" "$TOOL" --module=ruby

test_output_contains "MKDEPS with backtick rejected" \
    "shell metacharacters" \
    env MKDEPS='x`evil`' "$TOOL" --module=ruby

test_output_contains "MKDEPS with dollar rejected" \
    "shell metacharacters" \
    env 'MKDEPS=x$(evil)' "$TOOL" --module=ruby

test_output_contains "MKDEPS with pipe rejected" \
    "shell metacharacters" \
    env MKDEPS="x|evil" "$TOOL" --module=ruby

test_output_contains "MKDEPS with ampersand rejected" \
    "shell metacharacters" \
    env MKDEPS="x&evil" "$TOOL" --module=ruby

test_output_contains "MKDEPS with newline rejected" \
    "shell metacharacters" \
    env MKDEPS=$'x\nevil' "$TOOL" --module=ruby

# MODE with shell metacharacters
test_output_contains "MODE with semicolon rejected" \
    "shell metacharacters" \
    env MODE="dbg; rm -rf /" "$TOOL" --module=ruby

test_output_contains "MODE with backtick rejected" \
    "shell metacharacters" \
    env MODE='dbg`evil`' "$TOOL" --module=ruby

# Clean MKDEPS should NOT trigger the warning
test_output_not_contains "clean MKDEPS path accepted" \
    "shell metacharacters" \
    env MKDEPS="/usr/bin/mkdeps" "$TOOL" --module=ruby --count

test_output_not_contains "clean MODE accepted" \
    "shell metacharacters" \
    env MODE="dbg" "$TOOL" --module=ruby --count

echo
echo "=== Results ==="
echo -e "${GREEN}PASS: $PASS${NC}"
if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}FAIL: $FAIL${NC}"
fi

if [ "$FAIL" -eq 0 ]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed!"
    exit 1
fi
