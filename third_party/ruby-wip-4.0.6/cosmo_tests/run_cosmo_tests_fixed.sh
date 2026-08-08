#!/usr/bin/env bash
# Test runner for CosmoRuby 4.0.0
# Re-enabled test extensions that were fixed

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

# Run tests with re-enabled extensions
# Removed blanket exclusion of '/-ext-/' to allow our fixed extensions
echo "Running Ruby core tests with re-enabled extensions..."
echo ""

RUBYLIB="$REPO_ROOT/third_party/ruby/lib" "$RUBY_BIN" "$REPO_ROOT/third_party/ruby/test/runner.rb" \
    --exclude '/enc/' \
    --exclude '/cgi/' \
    --exclude '/ripper/' \
    --exclude '/irb/' \
    --exclude '/csv/' \
    --exclude '/rss/' \
    --exclude '/rexml/' \
    --exclude '/rdoc/' \
    --exclude '/rubygems/' \
    --exclude '/bundler/' \
    --exclude '/did_you_mean/' \
    --exclude '/error_highlight/' \
    --exclude '/syntax_suggest/' \
    --exclude '/prism/' \
    --exclude '/openssl/' \
    --exclude '/memory.*leak/' \
    --exclude '/test_process.rb' \
    --exclude '/test_pipe.rb' \
    --exclude '/test_require.rb' \
    --exclude '/test_dir.rb' \
    --exclude '/test_io_m17n.rb' \
    --exclude '/test_gc.rb' \
    --exclude '/test_method.rb' \
    --exclude '/test_fiber.rb' \
    --exclude '/test_sprintf.rb' \
    --exclude '/test_require_lib.rb' \
    --exclude '/test_class.rb' \
    --exclude '/test_module.rb' \
    --exclude '/test_call.rb' \
    --exclude '/test_dir_m17n.rb' \
    --exclude '/test_io.rb' \
    --exclude '/test_keyword.rb' \
    --exclude '/test_memory_view.rb' \
    --exclude '/test_file.rb' \
    --exclude '/test_readpartial.rb' \
    --exclude '/test_file_exhaustive.rb' \
    --exclude '/-ext-/box/' \
    --exclude '/-ext-/load/' \
    --exclude '/-ext-/marshal/' \
    --exclude '/-ext-/scheduler/' \
    --exclude '/-ext-/stack/' \
    --exclude '/-ext-/st/' \
    --exclude '/-ext-/thread/' \
    --exclude '/-ext-/vm/' \
    --exclude '/-ext-/wait/' \
    --exclude '/-ext-/win32/' \
    --exclude '/nonascii/' \
    --exclude '/unicode/' \
    --exclude '/encoding/' \
    --exclude '/bootstraptest/' \
    --verbose \
    ruby/ \
    "$@"
