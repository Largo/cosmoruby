#!/bin/sh
# Trigger the ruby-platforms CI workflow.
#
# Uploads ruby.com to a GitHub release, triggers CI, and watches
# the workflow run with live output.
#
# Usage: ./trigger_ruby_test.sh [release-tag]
#   Default release tag: ruby-test
#
# To build and package ruby.com:
#   make -j$(nproc) o//third_party/ruby/ruby
#   cd third_party/ruby && bash package_ruby.sh

set -e

REPO="igravious/cosmoruby"
TAG="${1:-ruby-test}"
BINARY="ruby.com"
WORKFLOW="ruby-platforms.yml"

echo "=== CosmoRuby Cross-Platform Test ==="
echo ""

# -- Check binary exists -----------------------------------------------------

if [ ! -f "$BINARY" ]; then
    echo "Error: $BINARY not found in current directory."
    echo ""
    echo "Build and package first:"
    echo "  make -j\$(nproc) o//third_party/ruby/ruby"
    echo "  cd third_party/ruby && bash package_ruby.sh"
    exit 1
fi

# -- Quick local sanity check -------------------------------------------------

echo "Local sanity check..."
OUTPUT=$(./ruby.com --disable-gems -e 'puts "#{RUBY_VERSION} #{RUBY_PLATFORM}"' 2>&1) || true
if [ -n "$OUTPUT" ]; then
    echo "  Ruby: $OUTPUT"
else
    echo "  Warning: no output from ruby.com"
    echo "  Continuing anyway (might work on other platforms)."
fi

echo ""

# -- Check release exists and has the binary ----------------------------------

echo "Checking release '$TAG' on $REPO..."

if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "Release '$TAG' not found. Creating..."
    gh release create "$TAG" "$BINARY" \
        --repo "$REPO" \
        --title "CosmoRuby test" \
        --notes "ruby.com for cross-platform CI testing"
    echo "Release created."
else
    echo "Release '$TAG' exists. Uploading binary..."
    gh release upload "$TAG" "$BINARY" --repo "$REPO" --clobber
    echo "Uploaded."
fi

echo ""

# -- Trigger workflow ---------------------------------------------------------

echo "Triggering workflow..."
gh workflow run "$WORKFLOW" --repo "$REPO" -f release_tag="$TAG"

echo ""

# -- Watch the workflow -------------------------------------------------------

echo "Waiting for workflow to appear..."
sleep 5

RUN_ID=$(gh run list --workflow="$WORKFLOW" --repo="$REPO" --limit=1 --json databaseId -q '.[0].databaseId')

if [ -z "$RUN_ID" ]; then
    echo "Could not find workflow run. Check Actions tab manually:"
    echo "  https://github.com/$REPO/actions/workflows/$WORKFLOW"
    exit 1
fi

echo "Watching workflow run $RUN_ID..."
echo "  https://github.com/$REPO/actions/runs/$RUN_ID"
echo ""

gh run watch "$RUN_ID" --repo "$REPO" --exit-status || true

echo ""
echo "=== Final status ==="
gh run view "$RUN_ID" --repo "$REPO"
