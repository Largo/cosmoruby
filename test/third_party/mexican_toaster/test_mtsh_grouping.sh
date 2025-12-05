#!/bin/bash
# Test script for mtsh subshell grouping

MTSH="o//third_party/mexican_toaster/mtsh.com"
PASS=0
FAIL=0

test_feature() {
    local name="$1"
    local cmd="$2"
    local expected_exit="$3"

    echo -n "Testing $name... "
    $MTSH -c "$cmd" >/dev/null 2>&1
    local exit_code=$?

    if [ "$exit_code" -eq "$expected_exit" ]; then
        echo "PASS"
        ((PASS++))
    else
        echo "FAIL (expected exit $expected_exit, got $exit_code)"
        ((FAIL++))
    fi
}

test_feature_output() {
    local name="$1"
    local cmd="$2"
    local expected_output="$3"

    echo -n "Testing $name... "
    local output=$($MTSH -c "$cmd" 2>&1)

    if [ "$output" = "$expected_output" ]; then
        echo "PASS"
        ((PASS++))
    else
        echo "FAIL"
        echo "  Expected: '$expected_output'"
        echo "  Got:      '$output'"
        ((FAIL++))
    fi
}

echo "=== Testing mtsh subshell grouping ==="
echo

# Test 1: Basic subshell execution
test_feature_output "simple subshell" "(echo hello)" "hello"

# Test 2: Subshell with exit status
test_feature "subshell success" "(true)" 0
test_feature "subshell failure" "(false)" 1

# Test 3: Nested subshells
test_feature_output "nested subshells" "((echo nested))" "nested"

# Test 4: Subshell with multiple commands
test_feature_output "multiple cmds in subshell" "(echo one; echo two)" "one
two"

# Test 5: Subshell in && chain
test_feature_output "subshell with &&" "true && (echo yes)" "yes"
test_feature "failed && with subshell" "false && (echo no)" 1

# Test 6: Subshell in || chain
test_feature_output "subshell with ||" "false || (echo fallback)" "fallback"
test_feature "success || with subshell" "true || (echo no)" 0

# Test 7: Complex grouping (original use case)
test_feature "grouping for precedence" "true && (false || true)" 0
test_feature "grouping for precedence 2" "false || (true && true)" 0

# Test 8: Subshell isolation (cd doesn't escape)
TESTDIR="/tmp/mtsh_subshell_test_$$"
mkdir -p "$TESTDIR/subdir"
ORIGDIR=$(pwd)
test_feature "cd in subshell" "cd $TESTDIR && (cd subdir && pwd > /dev/null) && test \"\$(pwd)\" = \"$TESTDIR\"" 0
cd "$ORIGDIR"
rm -rf "$TESTDIR"

# Test 9: Subshell with variables
test_feature_output "subshell with env" "FOO=bar && (echo \$FOO)" "bar"

# Test 10: Error handling - unmatched parens
test_feature "unmatched open paren" "(echo test" 15
test_feature "unmatched close paren" "echo test)" 15

# Test 11: Empty subshell
test_feature "empty subshell" "()" 0

# Test 12: Subshell with comments
test_feature_output "subshell with comment" "(echo test # comment)" "test"

# Test 13: Multiple subshells in sequence
test_feature_output "sequential subshells" "(echo one); (echo two)" "one
two"

# Test 14: Subshell with pipe
test_feature_output "pipe in subshell" "(echo hello | cat)" "hello"

# Test 15: Practical Ruby build pattern
TESTFILE1="/tmp/mtsh_test1_$$.tmp"
TESTFILE2="/tmp/mtsh_test2_$$.tmp"
TESTFILE3="/tmp/mtsh_test3_$$.tmp"
echo "same" > "$TESTFILE1"
echo "same" > "$TESTFILE2"
test_feature "diff success pattern" "(diff -u $TESTFILE1 $TESTFILE2 > $TESTFILE3) && rm -f $TESTFILE3 || touch $TESTFILE3" 0
test ! -f "$TESTFILE3" && echo "  No diff file: PASS" || echo "  Diff file exists: FAIL"

echo "different" > "$TESTFILE2"
test_feature "diff failure pattern" "(diff -u $TESTFILE1 $TESTFILE2 > $TESTFILE3) && rm -f $TESTFILE3 || touch $TESTFILE3" 0
test -f "$TESTFILE3" && echo "  Diff file created: PASS" || echo "  Diff file missing: FAIL"
rm -f "$TESTFILE1" "$TESTFILE2" "$TESTFILE3"

echo
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"

if [ "$FAIL" -eq 0 ]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed!"
    exit 1
fi
