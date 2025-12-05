#!/bin/bash
# Master test runner for Mexican Toaster

set -e  # Exit on first error

SCRIPT_DIR="$(dirname "$0")"
TOTAL=0
PASSED=0
FAILED=0

echo "╔════════════════════════════════════════════════════════╗"
echo "║     Mexican Toaster - Comprehensive Test Suite        ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

run_test() {
    local test_name="$1"
    local test_script="$2"

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Running: $test_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    TOTAL=$((TOTAL + 1))

    if bash "$SCRIPT_DIR/$test_script"; then
        echo "✅ $test_name PASSED"
        PASSED=$((PASSED + 1))
    else
        echo "❌ $test_name FAILED"
        FAILED=$((FAILED + 1))
    fi
}

# Run all tests
run_test "Basic Piping" "test_pipe_basic.sh"
run_test "Quiet/Verbose Mode" "test_quiet_mode.sh"
run_test "File Operations" "test_file_operations.sh"
run_test "External APE Binaries" "test_external_binaries.sh"
run_test "Builtin Commands" "test_builtin_commands.sh"
run_test "Shell Redirection" "test_redirection.sh"
run_test "Process Control" "test_process_control.sh"
run_test "ZIP Contents" "test_zip_contents.sh"
run_test "Overlay Persistence" "test_overlay_persistence.sh"

# Summary
echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║                    TEST SUMMARY                        ║"
echo "╠════════════════════════════════════════════════════════╣"
printf "║  Total:  %3d                                          ║\n" "$TOTAL"
printf "║  Passed: %3d                                          ║\n" "$PASSED"
printf "║  Failed: %3d                                          ║\n" "$FAILED"
echo "╚════════════════════════════════════════════════════════╝"

if [ "$FAILED" -eq 0 ]; then
    echo ""
    echo "🎉 All tests passed!"
    exit 0
else
    echo ""
    echo "⚠️  Some tests failed"
    exit 1
fi
