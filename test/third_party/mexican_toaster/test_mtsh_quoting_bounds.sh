#!/bin/bash
# Tests for mtsh tokeniser bounds checking and quoting safety
#
# Covers security fixes:
#   M1 - Single/double-quoted strings now go through Append() bounds check
#   M2 - Glob expansion bounds check inside the expansion loop

MTSH="o//third_party/mexican_toaster/mtsh.com"
PASS=0
FAIL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

compare_test() {
    local name="$1"
    local cmd="$2"
    local bash_expected="$3"

    echo -n "Testing $name... "

    if [ -z "$bash_expected" ]; then
        bash_output=$(bash -c "$cmd" 2>&1)
        bash_exit=$?
    else
        bash_output="$bash_expected"
        bash_exit=0
    fi

    mtsh_output=$($MTSH -c "$cmd" 2>&1)
    mtsh_exit=$?

    if [ "$bash_output" = "$mtsh_output" ] && [ "$bash_exit" = "$mtsh_exit" ]; then
        echo -e "${GREEN}PASS${NC}"
        ((PASS++))
    else
        echo -e "${RED}FAIL${NC}"
        echo "  Command: $cmd"
        echo "  Bash output: '$bash_output' (exit $bash_exit)"
        echo "  Mtsh output: '$mtsh_output' (exit $mtsh_exit)"
        ((FAIL++))
    fi
}

test_output() {
    local name="$1"
    local cmd="$2"
    local expected="$3"

    echo -n "Testing $name... "
    local output
    output=$($MTSH -c "$cmd" 2>&1)
    local exit_code=$?

    if [ "$output" = "$expected" ]; then
        echo -e "${GREEN}PASS${NC}"
        ((PASS++))
    else
        echo -e "${RED}FAIL${NC}"
        echo "  Expected: '$expected'"
        echo "  Got:      '$output'"
        ((FAIL++))
    fi
}

test_exit() {
    local name="$1"
    local cmd="$2"
    local expected_exit="$3"

    echo -n "Testing $name... "
    $MTSH -c "$cmd" >/dev/null 2>&1
    local exit_code=$?

    if [ "$exit_code" -eq "$expected_exit" ]; then
        echo -e "${GREEN}PASS${NC}"
        ((PASS++))
    else
        echo -e "${RED}FAIL${NC}"
        echo "  Expected exit: $expected_exit, got: $exit_code"
        ((FAIL++))
    fi
}

if [ ! -x "$MTSH" ]; then
    echo "Error: $MTSH not found. Build with: make -j1 o//third_party/mexican_toaster/mtsh.com"
    exit 1
fi

echo "=== mtsh Quoting and Bounds Tests ==="
echo "(Security fixes M1 + M2 verification)"
echo

# ---------------------------------------------------------------
# M1: Single-quoted string handling (now uses Append() bounds check)
# ---------------------------------------------------------------
echo "--- Single-Quoted Strings (M1) ---"
compare_test "simple single quote" "echo 'hello'"
compare_test "single quote with spaces" "echo 'hello world'"
compare_test "single quote preserves dollars" "echo '\$HOME'"
compare_test "single quote preserves backslash" "echo 'back\\slash'"
compare_test "single quote preserves backticks" "echo 'no \`subst\` here'"
compare_test "empty single quote" "echo ''"
compare_test "adjacent single quotes" "echo 'ab''cd'"
compare_test "single quote in double quote" 'echo "it'"'"'s"'
compare_test "long single-quoted string" "echo 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'"

# ---------------------------------------------------------------
# M1: Double-quoted string + backslash handling (now uses Append())
# ---------------------------------------------------------------
echo
echo "--- Double-Quoted Strings + Escapes (M1) ---"
compare_test "simple double quote" 'echo "hello"'
compare_test "double quote with spaces" 'echo "hello world"'
compare_test "escaped dollar in dquote" 'echo "\$HOME"'
compare_test "escaped backtick in dquote" 'echo "\`test\`"'
compare_test "escaped quote in dquote" 'echo "say \"hi\""'
compare_test "backslash-n in dquote" 'echo "line\\nbreak"'
compare_test "backslash before normal char" 'echo "\a\b\c"'
compare_test "multiple escapes in dquote" 'echo "\$\`\"\\"'
compare_test "empty double quote" 'echo ""'
compare_test "adjacent double quotes" 'echo "ab""cd"'

# ---------------------------------------------------------------
# M1: Mixed quoting styles
# ---------------------------------------------------------------
echo
echo "--- Mixed Quoting (M1) ---"
compare_test "single then double" "echo 'hello' \"world\""
compare_test "unquoted then single" "echo hello' world'"
compare_test "double then single" 'echo "hello"'"'"' world'"'"
compare_test "quotes concatenated" "echo 'a'\"b\"c"
compare_test "variable between quotes" 'X=mid && echo "a"$X"b"'

# ---------------------------------------------------------------
# M1: Stress test with longer strings (still well under ARG_MAX)
# ---------------------------------------------------------------
echo
echo "--- Longer Strings (M1 stress) ---"
# Generate a 500-char single-quoted string
LONG500=$(python3 -c "print('x' * 500)")
test_output "500-char single-quoted" "echo '$LONG500'" "$LONG500"

# Generate a 500-char double-quoted string
test_output "500-char double-quoted" "echo \"$LONG500\"" "$LONG500"

# Repeated backslash escapes in double quotes (2 Append() calls each)
ESCAPED50=$(python3 -c "print('\\\\a' * 50)")
EXPECTED50=$(python3 -c "print('\\\\a' * 50)")
compare_test "50 backslash-char pairs in dquote" "echo \"$ESCAPED50\""

# ---------------------------------------------------------------
# M2: Glob expansion bounds check
# ---------------------------------------------------------------
echo
echo "--- Glob Expansion Bounds (M2) ---"

# Set up a temp directory with known files for glob testing
GLOBDIR="/tmp/mtsh_glob_test_$$"
mkdir -p "$GLOBDIR"
for i in $(seq 1 10); do
    touch "$GLOBDIR/file_$i.txt"
done

# Basic glob should work
test_output "simple glob expansion" \
    "echo $GLOBDIR/file_1.txt" \
    "$GLOBDIR/file_1.txt"

compare_test "wildcard glob" "ls $GLOBDIR/*.txt | wc -l" "10"

# Glob that matches nothing should pass through literally
compare_test "no-match glob passthrough" "echo $GLOBDIR/*.zzz"

# Clean up
rm -rf "$GLOBDIR"

# ---------------------------------------------------------------
# Edge cases: unterminated strings should error
# ---------------------------------------------------------------
echo
echo "--- Error Handling ---"
test_exit "unterminated single quote" "echo 'hello" 6
test_exit "unterminated double quote" 'echo "hello' 6

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
