#!/bin/sh
# Trigger the ruby-platforms CI workflow.
#
# Checks that the ruby binary is a fat APE (both x86_64 and aarch64),
# runs local diagnostics (version, stdlib, core libraries), uploads it
# to a GitHub release, triggers CI on 6 runners, and watches the
# workflow run with live output.
#
# Usage: ./trigger_ruby_test.sh [release-tag]
#   Default release tag: ruby-test
#
# To build and package ruby.com:
#   bin/build_ruby.sh -j$(nproc)

set -e

# Report which command failed and where
trap 'echo "Error: Command failed at line $LINENO"' ERR

TAG="${1:-ruby-test}"
BINARY="releases/ruby.com"
WORKFLOW="ruby-platforms.yml"

. ./check_ape.sh
. ./trigger_ci.sh

echo "=== CosmoRuby Cross-Platform Test ==="
echo ""

# ── Check binary exists ──────────────────────────────────────────────

if [ ! -f "$BINARY" ]; then
    echo "Error: $BINARY not found."
    echo ""
    echo "Build and package first:"
    echo "  bin/build_ruby.sh -j\$(nproc)"
    exit 1
fi

# ── Verify APE binary ───────────────────────────────────────────────

check_ape_magic "$BINARY" || exit 1
check_fat_binary "$BINARY"
check_ape_components "$BINARY" || exit 1

# ── Local diagnostics ───────────────────────────────────────────────

echo "Local sanity check..."

# Version and platform
OUTPUT=$(./"$BINARY" --disable-gems -e 'puts "#{RUBY_VERSION} #{RUBY_PLATFORM}"' 2>&1) || true
if [ -n "$OUTPUT" ]; then
    echo "  Ruby:        $OUTPUT"
else
    echo "  Warning: no output from ruby.com"
    echo "  Continuing anyway (might work on other platforms)."
fi

# Embedded stdlib file count
STDLIB_COUNT=$(./"$BINARY" --disable-gems -e 'puts Dir["/zip/**/*"].select { |f| File.file?(f) }.size' 2>&1) || true
if [ -n "$STDLIB_COUNT" ] && [ "$STDLIB_COUNT" -gt 0 ] 2>/dev/null; then
    echo "  Stdlib:      $STDLIB_COUNT files in /zip/"
else
    echo "  Warning: could not count /zip/ files (got: ${STDLIB_COUNT:-empty})"
fi

# Core library requires
REQUIRE_OK=$(./"$BINARY" --disable-gems -e '
  ok = 0
  %w[json zlib digest yaml stringio date rubygems].each do |lib|
    begin; require lib; ok += 1; rescue; end
  end
  puts ok
' 2>&1) || true
if [ -n "$REQUIRE_OK" ]; then
    echo "  Requires:    $REQUIRE_OK/7 core libraries loaded"
fi

echo ""

# ── Upload, trigger, watch ──────────────────────────────────────────

upload_release "$TAG" "$BINARY" \
    "CosmoRuby test" \
    "ruby.com for cross-platform CI testing"

trigger_workflow "$WORKFLOW" -f release_tag="$TAG"
watch_workflow "$WORKFLOW"
