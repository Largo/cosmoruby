#!/bin/bash
# Test script for cocmd command substitution (backticks and $())

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
echo "--- Newline stripping ---"
test_feature_output "strip trailing newline" 'echo $(echo hello)' "hello"
test_feature_output "strip multiple newlines" 'echo `printf "test\n\n\n"`' "test"

echo
echo "--- Practical use cases ---"
test_feature_output "date command" 'echo Today is $(echo Monday)' "Today is Monday"
test_feature_output "pwd command" 'X=$(pwd); echo $X' "$(pwd)"
test_feature_output "command in test" 'test "$(echo yes)" = "yes" && echo match' "match"
test_feature_output "assignment from cmd" 'VAR=`echo value` && echo $VAR' "value"

echo
echo "--- Multiple commands in substitution ---"
test_feature_output "semicolon in \$()" 'echo $(echo a; echo b)' "ab"
test_feature_output "semicolon in backtick" 'echo `echo x; echo y`' "xy"

echo
echo "--- Integration with other features ---"
test_feature_output "substitution with comment" 'echo $(echo test) # comment' "test"
test_feature_output "substitution in subshell" '(echo $(echo nested))' "nested"
test_feature_output "substitution with &&" 'true && echo $(echo success)' "success"

echo
echo "--- Error handling ---"
test_feature "unmatched backtick" 'echo `test' 15
test_feature "unmatched \$()" 'echo $(test' 15

echo
echo "--- NO NESTING (should work with simple search) ---"
# These work because we just find the first ) or `, no nesting support needed
test_feature_output "no nesting test 1" 'echo $(echo outer)' "outer"
test_feature_output "no nesting test 2" 'echo `echo outer`' "outer"

echo
echo "--- Build script patterns ---"
# Common patterns in build scripts
test_feature_output "get hostname" 'echo Building on $(echo localhost)' "Building on localhost"
test_feature_output "check file count" 'echo Files: $(echo 42)' "Files: 42"
test_feature_output "version string" 'VER=$(echo 1.0) && echo v$VER' "v1.0"

# Create temp file for testing
TESTFILE="/tmp/cocmd_subst_test_$$.txt"
echo "content" > "$TESTFILE"
test_feature_output "cat file content" "echo \$(cat $TESTFILE)" "content"
rm -f "$TESTFILE"

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
