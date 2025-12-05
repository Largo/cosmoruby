#!/bin/bash
# Test script for cocmd command substitution (backticks and $())
# Tests realistic build script usage

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

echo "=== Testing cocmd command substitution ==="
echo

echo "--- Backtick syntax ---"
test_feature_output "simple backtick" 'echo `echo hello`' "hello"
test_feature_output "backtick in arg" 'echo x`echo y`z' "xyz"
test_feature_output "multiple backticks" 'echo `echo a` `echo b`' "a b"
test_feature_output "backtick with pipe" 'echo `echo test | cat`' "test"

echo
echo "--- \$() syntax ---"
test_feature_output "simple \$()" 'echo $(echo hello)' "hello"
test_feature_output "\$() in arg" 'echo x$(echo y)z' "xyz"
test_feature_output "multiple \$()" 'echo $(echo a) $(echo b)' "a b"
test_feature_output "\$() with pipe" 'echo $(echo test | cat)' "test"

echo
echo "--- Newline handling ---"
test_feature_output "strip single trailing newline" 'echo X$(echo hello)X' "XhelloX"
test_feature_output "strip multiple trailing newlines" 'echo X`printf "test\n\n\n"`X' "XtestX"
# Internal newlines are preserved (like bash)
test_feature_output "preserve internal newlines" 'echo "$(echo a; echo b)"' "a
b"

echo
echo "--- Practical build script patterns ---"
test_feature_output "simple command capture" 'echo $(echo Monday)' "Monday"
test_feature_output "command in message" 'echo Build: $(echo success)' "Build: success"
test_feature_output "test with capture" 'test "$(echo yes)" = "yes" && echo match' "match"

echo
echo "--- Integration with other features ---"
test_feature_output "substitution with comment" 'echo $(echo test) # comment' "test"
test_feature_output "substitution in subshell" '(echo $(echo nested))' "nested"
test_feature_output "substitution with &&" 'true && echo $(echo success)' "success"
test_feature_output "substitution with ||" 'false || echo $(echo fallback)' "fallback"

echo
echo "--- Error handling ---"
test_feature "unmatched backtick" 'echo `test' 15
test_feature "unmatched \$()" 'echo $(test' 15

echo
echo "--- Complex but realistic patterns ---"
# File content reading
TESTFILE="/tmp/cocmd_subst_test_$$.txt"
echo "hello world" > "$TESTFILE"
test_feature_output "read file" "echo Contents: \$(cat $TESTFILE)" "Contents: hello world"
rm -f "$TESTFILE"

# Multiple substitutions in one line
test_feature_output "multiple in line" 'echo $(echo A)$(echo B)$(echo C)' "ABC"

# Substitution in conditional
test_feature "in conditional true" 'test "$(echo foo)" = "foo"' 0
test_feature "in conditional false" 'test "$(echo foo)" = "bar"' 1

# Nested in grouping
test_feature_output "in grouped command" '(echo outer $(echo inner))' "outer inner"

# With pipes
test_feature_output "piped substitution" 'echo $(echo data | cat)' "data"

echo
echo "--- NO NESTING (explicitly not supported) ---"
# We don't support nesting, document it works without nesting
test_feature_output "no nesting needed" 'echo $(echo result)' "result"

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
