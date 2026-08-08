#!/bin/sh
# Whitelist-based test runner for CosmoRuby 4.0.0
# Runs only specific failing tests for quick iteration

set -e

# Resolve repo root (works regardless of where the script lives)
REPO_ROOT="$(git rev-parse --show-toplevel)" || { echo "Error: not inside a git repo"; exit 1; }

# Determine the Ruby executable to use
if [ -f "$REPO_ROOT/o/third_party/ruby/ruby.com" ]; then
    RUBY_BIN="$REPO_ROOT/o/third_party/ruby/ruby.com"
elif [ -f "$REPO_ROOT/ruby.com" ]; then
    RUBY_BIN="$REPO_ROOT/ruby.com"
else
    echo "Using development Ruby: $REPO_ROOT/o/third_party/ruby/ruby"
    RUBY_BIN="$REPO_ROOT/o/third_party/ruby/ruby"
fi

echo "Using Ruby: $RUBY_BIN"
echo "Ruby version: $($RUBY_BIN --version)"
echo ""

# Set RUBY env var for subprocess spawning
export RUBY="$RUBY_BIN"
export RUBYLIB="$REPO_ROOT/third_party/ruby-wip-4.0.6/lib:$REPO_ROOT/third_party/ruby-wip-4.0.6/tool/lib"

# =============================================================================
# FAILING TESTS WHITELIST
# Add/remove test files here as you fix them
# One test file per line
# =============================================================================

# third_party/ruby-wip-4.0.6/test/ruby/test_process.rb

# Current known failures (timeout on memory leak stress tests - 3M iterations)
FAILING_TESTS="
$REPO_ROOT/third_party/ruby-wip-4.0.6/test/ruby/test_class.rb
$REPO_ROOT/third_party/ruby-wip-4.0.6/test/ruby/test_module.rb
"

# =============================================================================
# Run only the whitelisted failing tests
# =============================================================================

echo "Running only failing tests for quick iteration..."
echo ""

for the_file in $FAILING_TESTS; do
    # Skip empty lines
    [ -z "$the_file" ] && continue

    echo "=============================================="
    echo "Running: $the_file"
    echo "=============================================="

    # Use --name to run specific test methods if needed
    # Example: --name '/test_prelude_gems/'
    # "$RUBY_BIN" "$the_file" --verbose "$@" || true
    "$RUBY_BIN" "$the_file" "$@" || true

    echo ""
done

echo "=============================================="
echo "Done running failing tests"
echo "=============================================="
