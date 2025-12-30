#!/bin/bash
# Test all CosmoRuby build modes and verify expected behavior

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "================================================================================"
echo "CosmoRuby Build Mode Test Suite - All Modes"
echo "================================================================================"
echo

# Check if ruby.com exists
if [ ! -f "../../o/third_party/ruby/ruby.com" ]; then
    echo "ERROR: ruby.com not found. Please build first:"
    echo "  make -j8 o//third_party/ruby/ruby"
    echo "  cd third_party/ruby && ./package_ruby.sh"
    exit 1
fi

RUBY_COM="$SCRIPT_DIR/../../o/third_party/ruby/ruby.com"
TEST_SCRIPT="$SCRIPT_DIR/test_build_modes.rb"

# Function to run test and capture output
run_test() {
    local mode_name="$1"
    local ruby_binary="$2"

    echo "================================================================================
"
    echo "Testing: $mode_name"
    echo "Binary: $ruby_binary"
    echo "================================================================================"
    echo

    if [ ! -f "$ruby_binary" ]; then
        echo "❌ Binary not found: $ruby_binary"
        echo "   Skipping this mode."
        echo
        return 1
    fi

    # Get binary size
    local size=$(stat -f%z "$ruby_binary" 2>/dev/null || stat -c%s "$ruby_binary" 2>/dev/null)
    local size_mb=$(echo "scale=2; $size / 1024 / 1024" | bc)
    echo "Binary size: ${size_mb} MB"
    echo

    # Run the test
    if "$ruby_binary" --disable-gems "$TEST_SCRIPT"; then
        echo
        echo "✅ $mode_name: PASSED"
        return 0
    else
        echo
        echo "❌ $mode_name: FAILED"
        return 1
    fi
}

# Track results
MODES_TESTED=0
MODES_PASSED=0
MODES_FAILED=0

echo "Current build configuration:"
echo "----------------------------"
DLEXT=$(awk '/^#define[[:space:]]+DLEXT[[:space:]]+"/{gsub(/"/, "", $3); print $3}' include/ruby/config.h)
EXTSTATIC=$(awk '/^#define[[:space:]]+EXTSTATIC[[:space:]]+/{print $3}' include/ruby/config.h)
SLIM_STATIC=$(awk '/^#define[[:space:]]+SLIM_STATIC[[:space:]]+/{print $3}' include/ruby/config.h)

echo "  DLEXT: $DLEXT"
echo "  EXTSTATIC: $EXTSTATIC"
echo "  SLIM_STATIC: $SLIM_STATIC"
echo

if [ "$EXTSTATIC" = "0" ]; then
    MODE_DESC="Dynamic (plugin mode)"
elif [ "$SLIM_STATIC" = "1" ]; then
    MODE_DESC="Static Slim (zero-byte stubs)"
else
    MODE_DESC="Static Bare (no stubs)"
fi

echo "Current mode: $MODE_DESC"
echo

# Test current build
if run_test "$MODE_DESC" "$RUBY_COM"; then
    ((MODES_PASSED++))
else
    ((MODES_FAILED++))
fi
((MODES_TESTED++))

echo
echo "================================================================================"
echo "FINAL SUMMARY"
echo "================================================================================"
echo "Modes tested: $MODES_TESTED"
echo "Passed: $MODES_PASSED"
echo "Failed: $MODES_FAILED"
echo

if [ $MODES_FAILED -eq 0 ]; then
    echo "✅ ALL MODES PASSED"
    echo
    echo "To test other modes, rebuild with different configuration:"
    echo
    echo "  Dynamic mode:"
    echo "    ./cosmo_configure.sh --with-plugin-ext"
    echo "    make -j8 && ./package_ruby.sh"
    echo
    echo "  Static Slim mode:"
    echo "    ./cosmo_configure.sh --with-static-linked-ext --with-slim-static"
    echo "    make -j8 && ./package_ruby.sh"
    echo
    echo "  Static Bare mode:"
    echo "    ./cosmo_configure.sh --with-static-linked-ext --without-slim-static"
    echo "    make -j8 && ./package_ruby.sh"
    exit 0
else
    echo "❌ SOME MODES FAILED"
    echo
    echo "Please review the test output above for details."
    exit 1
fi
