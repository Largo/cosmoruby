#!/bin/bash
# Trigger the cosmo-hello-world CI workflow.
#
# Checks that the hello binary is a fat APE (both x86_64 and aarch64),
# uploads it to a GitHub release, triggers CI on 6 runners, and watches
# the workflow run with live output.
#
# Usage: ./trigger_hello_test.sh [release-tag]
#   Default release tag: hello-test
#
# To build a fat binary:
#   ./bake o//examples/hello

set -e

# Report which command failed and where
trap 'echo "Error: Command failed at line $LINENO"' ERR

TAG="${1:-hello-test}"
BINARY="releases/hello.com"
WORKFLOW="cosmo-hello-world.yml"

. ./check_ape.sh
. ./trigger_ci.sh

echo "=== Phase 0: APE Hello World Cross-Platform Test ==="
echo ""

# ── Check binary exists ──────────────────────────────────────────────

if [ ! -f "$BINARY" ]; then
    echo "Error: $BINARY not found."
    echo ""
    echo "Build a fat binary first:"
    echo "  ./bake o//examples/hello"
    exit 1
fi

# ── Verify APE binary ───────────────────────────────────────────────

check_ape_magic "$BINARY" || exit 1
check_fat_binary "$BINARY"
check_ape_components "$BINARY" || exit 1

# ── Quick local sanity check ────────────────────────────────────────

OUTPUT=$(./"$BINARY" 2>&1) || true
if [ "$OUTPUT" = "hello world" ]; then
    echo "Local run:   OK"
else
    echo "Warning: local run output unexpected: $OUTPUT"
    echo "Continuing anyway (might work on other platforms)."
fi

echo ""

# ── Upload, trigger, watch ──────────────────────────────────────────

upload_release "$TAG" "$BINARY" \
    "Phase 0 hello test" \
    "APE fat binary for cross-platform testing"

trigger_workflow "$WORKFLOW"
watch_workflow "$WORKFLOW"
