#!/bin/bash
# Test script for cocmd enhancements

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

echo "=== Testing cocmd enhancements ==="
echo

# Test 1: colon command (no-op)
test_feature "colon command" ":" 0

# Test 2: colon with redirection (create empty file)
TESTFILE="/tmp/cocmd_test_$$.tmp"
test_feature "colon with redirect" ": > $TESTFILE && test -f $TESTFILE" 0
rm -f "$TESTFILE"

# Test 3: comments (should not output anything)
test_feature_output "comment only" "# this is a comment" ""

# Test 4: command with trailing comment
test_feature_output "echo with comment" "echo hello # this is ignored" "hello"

# Test 5: multiple commands with comments
test_feature "commands with comments" "# start; echo test > /dev/null # middle; : # end" 0

# Test 6: diff with redirect (Ruby build pattern)
TESTFILE1="/tmp/cocmd_test1_$$.tmp"
TESTFILE2="/tmp/cocmd_test2_$$.tmp"
TESTFILE3="/tmp/cocmd_test3_$$.tmp"
echo "line1" > "$TESTFILE1"
echo "line2" > "$TESTFILE2"
test_feature "diff with ||" "diff -u $TESTFILE1 $TESTFILE2 > $TESTFILE3 || touch $TESTFILE3" 0
rm -f "$TESTFILE1" "$TESTFILE2" "$TESTFILE3"

# Test 7: colon in a complex recipe (like ruby.codegen.mk)
TMPDIR="/tmp/cocmd_test_$$"
mkdir -p "$TMPDIR"
test_feature "complex recipe pattern" "tmp=$TMPDIR/test.tmp && echo content > \$tmp && mv \$tmp $TMPDIR/test.out && : > $TMPDIR/.timestamp" 0
test -f "$TMPDIR/.timestamp" && echo "  Timestamp file created: PASS" || echo "  Timestamp file missing: FAIL"
rm -rf "$TMPDIR"

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
