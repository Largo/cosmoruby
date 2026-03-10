#!/bin/bash
# Trigger the mexican-toaster-platforms CI workflow.
#
# Checks that all Mexican Toaster binaries are fat APEs (x86_64 and aarch64),
# runs local diagnostics, uploads them to a GitHub release, triggers CI on
# 6 runners, and watches the workflow run with live output.
#
# Usage: ./trigger_mexican_toaster_test.sh [release-tag]
#   Default release tag: mexican-toaster-test
#
# To build and package Mexican Toaster binaries:
#   bin/build_mexican_toaster.sh -j$(nproc)

set -e

# Report which command failed and where
trap 'echo "Error: Command failed at line $LINENO"' ERR

TAG="${1:-mexican-toaster-test}"
MTSH="releases/mtsh.com"
LSDIR="releases/lsdir.com"
CABOOSE="releases/caboose.com"
WORKFLOW="mexican-toaster-platforms.yml"

. ./check_ape.sh
. ./trigger_ci.sh

echo "=== Mexican Toaster Cross-Platform Test ==="
echo ""

# ── Check binaries exist ─────────────────────────────────────────────

for binary in "$MTSH" "$LSDIR" "$CABOOSE"; do
    if [ ! -f "$binary" ]; then
        echo "Error: $binary not found."
        echo ""
        echo "Build first:"
        echo "  bin/build_mexican_toaster.sh -j\$(nproc)"
        exit 1
    fi
done

# ── Verify APE binaries ──────────────────────────────────────────────

echo "Verifying mtsh.com..."
check_ape_magic "$MTSH" || exit 1
check_fat_binary "$MTSH"
echo ""

echo "Verifying lsdir.com..."
check_ape_magic "$LSDIR" || exit 1
check_fat_binary "$LSDIR"
echo ""

echo "Verifying caboose.com..."
check_ape_magic "$CABOOSE" || exit 1
check_fat_binary "$CABOOSE"
echo ""

# ── Local diagnostics ───────────────────────────────────────────────

echo "Local sanity checks..."

# mtsh - run a simple command
MTSH_OUTPUT=$(./"$MTSH" -c "echo mtsh-ok" 2>&1) || true
if [ "$MTSH_OUTPUT" = "mtsh-ok" ]; then
    echo "  mtsh:        OK"
else
    echo "  Warning: mtsh test failed (output: $MTSH_OUTPUT)"
fi

# lsdir - list current directory
LSDIR_OUTPUT=$(./"$LSDIR" 2>&1 | head -1) || true
if [ -n "$LSDIR_OUTPUT" ]; then
    echo "  lsdir:       OK (found: $LSDIR_OUTPUT)"
else
    echo "  Warning: lsdir test failed"
fi

# caboose - check command
CABOOSE_OUTPUT=$(./"$CABOOSE" check 2>&1) || true
if echo "$CABOOSE_OUTPUT" | grep -q "healthy"; then
    echo "  caboose:     OK (healthy)"
else
    echo "  caboose:     status unclear"
    echo "    $CABOOSE_OUTPUT"
fi

# Check embedded files in caboose
CABOOSE_ZIP_COUNT=$(./"$CABOOSE" ls 2>&1 | wc -l) || true
if [ "$CABOOSE_ZIP_COUNT" -gt 0 ] 2>/dev/null; then
    echo "  caboose ZIP: $CABOOSE_ZIP_COUNT entries"
fi

echo ""

# ── Create release archive ──────────────────────────────────────────

# Create a tarball with all three binaries for easier distribution
ARCHIVE="releases/mexican-toaster-${TAG}.tar.gz"
echo "Creating archive: $ARCHIVE"
tar -czf "$ARCHIVE" -C releases \
    mtsh.com \
    lsdir.com \
    caboose.com

echo "Archive contents:"
tar -tzf "$ARCHIVE" | sed 's/^/  /'
echo ""

# ── Upload, trigger, watch ──────────────────────────────────────────

# Upload all binaries and the archive
upload_release "$TAG" "$ARCHIVE" \
    "Mexican Toaster test" \
    "Fat APE binaries (mtsh.com, lsdir.com, caboose.com) for cross-platform CI testing"

# Also upload individual binaries
for binary in "$MTSH" "$LSDIR" "$CABOOSE"; do
    gh release upload "$TAG" "$binary" --repo "$TRIGGER_CI_REPO" --clobber 2>/dev/null || true
done

trigger_workflow "$WORKFLOW" -f release_tag="$TAG"
watch_workflow "$WORKFLOW"
