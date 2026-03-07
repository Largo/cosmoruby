#!/usr/bin/env bash
# Test runner for CosmoRuby 4.0.0
# Excludes tests that require features not yet implemented

set -e

# Resolve repo root (works regardless of where the script lives)
REPO_ROOT="$(git rev-parse --show-toplevel)" || { echo "Error: not inside a git repo"; exit 1; }

# Determine the Ruby executable to use
if [ -f "$REPO_ROOT/o/third_party/ruby/ruby.com" ]; then
    RUBY_BIN="$REPO_ROOT/o/third_party/ruby/ruby.com"
elif [ -f "$REPO_ROOT/ruby.com" ]; then
    RUBY_BIN="$REPO_ROOT/ruby.com"
else
    echo "Error: Cannot find ruby.com executable"
    echo "Please build Ruby first with: make -j\$(nproc) o//third_party/ruby/ruby"
    echo "Then package it with: cd third_party/ruby && bash package_ruby.sh"
    exit 1
fi

echo "Using Ruby: $RUBY_BIN"
echo "Ruby version: $($RUBY_BIN --version)"
echo ""

# Set RUBY env var for subprocess spawning
export RUBY="$RUBY_BIN"

# Run tests with exclusions
echo "Running Ruby core tests (excluding -ext-, encoding, and other tests)..."
echo ""

"$RUBY_BIN" "$REPO_ROOT/third_party/ruby/test/runner.rb" \
    ruby/ \
    "$@"

#    --exclude '/enc/' \
#    --exclude '/cgi/' \
#    --exclude '/ripper/' \
#    --exclude '/irb/' \
#    --exclude '/csv/' \
#    --exclude '/rss/' \
#    --exclude '/rexml/' \
#    --exclude '/rdoc/' \
#    --exclude '/rubygems/' \
#    --exclude '/bundler/' \
#    --exclude '/did_you_mean/' \
#    --exclude '/error_highlight/' \
#    --exclude '/syntax_suggest/' \
#    --exclude '/prism/' \
#    --verbose \
#    --exclude '/-ext-/' \
#    --exclude '/test_ast/' \
#    --exclude '/test_m17n_comb/' \
#    --exclude '/test_transcode/' \
