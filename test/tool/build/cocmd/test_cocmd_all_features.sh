#!/bin/bash
# Comprehensive test suite for cocmd enhancements

COCMD="./o/tool/build/cocmd"
PASS=0
FAIL=0

test_feature() {
    local name="$1"
    local cmd="$2"
    local expected_exit="$3"

    echo -n "Testing $name... "
    $COCMD -c "$cmd" >/dev/null 2>&1
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
    local output=$($COCMD -c "$cmd" 2>&1)

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

echo "=== Testing cocmd: colon, comments, and grouping ==="
echo

echo "--- Colon command ---"
test_feature "colon no-op" ":" 0
test_feature "colon with redirect" ": > /tmp/cocmd_colon_test_$$.tmp && rm -f /tmp/cocmd_colon_test_$$.tmp" 0

echo
echo "--- Comments ---"
test_feature_output "comment only" "# this is a comment" ""
test_feature_output "echo with comment" "echo hello # ignored" "hello"
test_feature "multi-line with comments" "# start"$'\n'"echo test > /dev/null # middle"$'\n'"# end" 0

echo
echo "--- Subshell grouping ---"
test_feature_output "simple subshell" "(echo hello)" "hello"
test_feature "subshell exit status" "(true)" 0
test_feature "subshell failure" "(false)" 1
test_feature_output "nested subshells" "((echo nested))" "nested"
test_feature_output "multiple cmds" "(echo one; echo two)" "one
two"

echo
echo "--- Subshells with operators ---"
test_feature_output "subshell with &&" "true && (echo yes)" "yes"
test_feature "failed && with subshell" "false && (echo no)" 1
test_feature_output "subshell with ||" "false || (echo fallback)" "fallback"
test_feature "grouping precedence" "true && (false || true)" 0

echo
echo "--- Practical patterns ---"
# Ruby build pattern: diff files, create empty patch if identical
TESTFILE1="/tmp/cocmd_test1_$$.tmp"
TESTFILE2="/tmp/cocmd_test2_$$.tmp"
TESTFILE3="/tmp/cocmd_test3_$$.tmp"

echo "same" > "$TESTFILE1"
echo "same" > "$TESTFILE2"
test_feature "diff identical files" "diff -u $TESTFILE1 $TESTFILE2 > $TESTFILE3 || touch $TESTFILE3" 0
test -f "$TESTFILE3" && test ! -s "$TESTFILE3" && echo "  Empty diff file: PASS" || echo "  Diff file issue: FAIL"

echo "different" > "$TESTFILE2"
test_feature "diff different files" "diff -u $TESTFILE1 $TESTFILE2 > $TESTFILE3 || touch $TESTFILE3" 0
test -f "$TESTFILE3" && test -s "$TESTFILE3" && echo "  Diff file has content: PASS" || echo "  Diff file missing content: FAIL"
rm -f "$TESTFILE1" "$TESTFILE2" "$TESTFILE3"

# Grouping for complex conditionals
test_feature "complex grouping" "(true && false) || (true && true)" 0
test_feature_output "nested logic" "((echo a) && (echo b)) || echo c" "a
b"

echo
echo "--- Error handling ---"
test_feature "unmatched open paren" "(echo test" 15
test_feature "unmatched close paren" "echo test)" 15
test_feature "empty subshell" "()" 0

echo
echo "--- Integration ---"
test_feature_output "subshell with comment" "(echo test # comment)" "test"
test_feature_output "subshell with pipe" "(echo hello | cat)" "hello"
test_feature_output "sequential subshells" "(echo one); (echo two)" "one
two"

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
