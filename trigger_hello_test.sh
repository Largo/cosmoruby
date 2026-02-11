#!/bin/sh
# Trigger the cosmo-hello-world CI workflow.
#
# Checks that the hello binary is uploaded to a GitHub release,
# creates an empty commit if needed so push has something to send,
# pushes, and watches the workflow run.
#
# Usage: ./trigger_hello_test.sh [release-tag]
#   Default release tag: hello-test

set -e

REPO="igravious/cosmoruby"
TAG="${1:-hello-test}"
BINARY="o//examples/hello"
WORKFLOW="cosmo-hello-world.yml"

echo "=== Phase 0: APE Hello World Cross-Platform Test ==="
echo ""

# ── Check release exists and has the binary ──────────────────────────

echo "Checking release '$TAG' on $REPO..."

if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo ""
    echo "Release '$TAG' not found."
    if [ -f "$BINARY" ]; then
        echo "Creating release with local binary: $BINARY"
        gh release create "$TAG" "$BINARY" \
            --repo "$REPO" \
            --title "Phase 0 hello test" \
            --notes "APE fat binary for cross-platform testing"
        echo "Release created."
    else
        echo "Error: $BINARY not found. Build it first:"
        echo "  make -j1 o//examples/hello"
        exit 1
    fi
else
    # Release exists -- check it has the hello asset
    if gh release view "$TAG" --repo "$REPO" --json assets -q '.assets[].name' | grep -q '^hello$'; then
        echo "Release '$TAG' exists with hello binary. Good."
    else
        echo "Release '$TAG' exists but missing hello binary."
        if [ -f "$BINARY" ]; then
            echo "Uploading $BINARY to release..."
            gh release upload "$TAG" "$BINARY" --repo "$REPO" --clobber
            echo "Uploaded."
        else
            echo "Error: $BINARY not found. Build it first:"
            echo "  make -j1 o//examples/hello"
            exit 1
        fi
    fi
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
