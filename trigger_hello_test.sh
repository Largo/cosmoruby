#!/bin/sh
# Trigger the cosmo-hello-world CI workflow.
#
# Checks that the hello binary is a fat APE (both x86_64 and aarch64),
# uploads it to a GitHub release, pushes to trigger CI, and watches
# the workflow run.
#
# Usage: ./trigger_hello_test.sh [release-tag]
#   Default release tag: hello-test
#
# To build a fat binary:
#   .cosmocc/current/bin/cosmocc -o hello.com examples/hello.c

set -e

REPO="igravious/cosmoruby"
TAG="${1:-hello-test}"
BINARY="hello.com"
WORKFLOW="cosmo-hello-world.yml"

echo "=== Phase 0: APE Hello World Cross-Platform Test ==="
echo ""

# ── Check binary exists ──────────────────────────────────────────────

if [ ! -f "$BINARY" ]; then
    echo "Error: $BINARY not found in current directory."
    echo ""
    echo "Build a fat binary first:"
    echo "  .cosmocc/current/bin/cosmocc -o hello.com examples/hello.c"
    exit 1
fi

# ── Verify APE binary ─────────────────────────────────────────────────

. ./check_ape.sh
check_ape_magic "$BINARY" || exit 1
check_fat_binary "$BINARY"
check_ape_components "$BINARY" || exit 1

# ── Quick local sanity check ─────────────────────────────────────────

OUTPUT=$(./hello.com 2>&1) || true
if [ "$OUTPUT" = "hello world" ]; then
    echo "Local run:   OK"
else
    echo "Warning: local run output unexpected: $OUTPUT"
    echo "Continuing anyway (might work on other platforms)."
fi

echo ""

# ── Check release exists and has the binary ──────────────────────────

echo "Checking release '$TAG' on $REPO..."

if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "Release '$TAG' not found. Creating..."
    gh release create "$TAG" "$BINARY" \
        --repo "$REPO" \
        --title "Phase 0 hello test" \
        --notes "APE fat binary for cross-platform testing"
    echo "Release created."
else
    # Release exists -- update the binary
    echo "Release '$TAG' exists. Uploading binary..."
    gh release upload "$TAG" "$BINARY" --repo "$REPO" --clobber
    echo "Uploaded."
fi

echo ""

# ── Push (empty commit if needed) ───────────────────────────────────

echo "Pushing to trigger workflow..."

PUSH_OUTPUT=$(git push cosmoruby 2>&1) || true

if echo "$PUSH_OUTPUT" | grep -q "Everything up-to-date"; then
    echo "Nothing to push. Creating empty trigger commit..."
    git commit --allow-empty -m "Trigger cosmo-hello-world CI run"
    git push cosmoruby
fi

echo ""

# ── Watch the workflow ───────────────────────────────────────────────

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
