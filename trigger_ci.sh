# trigger_ci.sh — shared CI trigger functions
# Source this file: . ./trigger_ci.sh
#
# Provides: upload_release, trigger_workflow, watch_workflow
#
# These scripts upload a locally-built binary to a GitHub release,
# then trigger a CI workflow that downloads and tests it on 6 runners
# (Linux/macOS/Windows x86_64/aarch64). We build locally because
# Cosmopolitan builds are too heavy for GitHub runners.

TRIGGER_CI_REPO="igravious/cosmoruby"

# Upload a binary to a GitHub release, creating the release if needed.
#
# Usage: upload_release TAG BINARY TITLE NOTES
upload_release() {
    _tag="$1"
    _binary="$2"
    _title="$3"
    _notes="$4"

    echo "Checking release '$_tag' on $TRIGGER_CI_REPO..."

    if ! gh release view "$_tag" --repo "$TRIGGER_CI_REPO" >/dev/null 2>&1; then
        echo "Release '$_tag' not found. Creating..."
        gh release create "$_tag" "$_binary" \
            --repo "$TRIGGER_CI_REPO" \
            --title "$_title" \
            --notes "$_notes"
        echo "Release created."
    else
        echo "Release '$_tag' exists. Uploading binary..."
        gh release upload "$_tag" "$_binary" --repo "$TRIGGER_CI_REPO" --clobber
        echo "Uploaded."
    fi

    echo ""
}

# Trigger a GitHub Actions workflow.
#
# Tries workflow_dispatch first (cleaner, shows as "manually triggered").
# Falls back to git push if dispatch fails — this happens when the
# workflow file only exists on a feature branch, not on the default
# branch (master). GitHub only recognises workflow_dispatch triggers
# for workflows that are on the default branch.
#
# Usage: trigger_workflow WORKFLOW [DISPATCH_ARGS]
#   DISPATCH_ARGS: extra flags for gh workflow run (e.g. -f key=value)
trigger_workflow() {
    _workflow="$1"
    shift
    _dispatch_args="$*"

    # Try workflow_dispatch first
    echo "Triggering workflow (trying dispatch)..."
    # shellcheck disable=SC2086
    if gh workflow run "$_workflow" --repo "$TRIGGER_CI_REPO" $_dispatch_args 2>/dev/null; then
        echo "Dispatched."
        echo ""
        return 0
    fi

    # Dispatch failed — workflow probably not on default branch.
    # Fall back to push trigger: the workflow's on:push:branches
    # pattern fires when we push the feature branch.
    echo "Dispatch unavailable (workflow not on default branch)."
    echo "Falling back to push trigger..."

    PUSH_OUTPUT=$(git push cosmoruby 2>&1) || true

    if echo "$PUSH_OUTPUT" | grep -q "Everything up-to-date"; then
        echo "Nothing to push. Creating empty trigger commit..."
        git commit --allow-empty -m "Trigger $_workflow CI run"
        git push cosmoruby
    fi

    echo ""
}

# Wait for a workflow run to appear, then watch it to completion.
#
# Usage: watch_workflow WORKFLOW
watch_workflow() {
    _workflow="$1"

    echo "Waiting for workflow to appear..."
    sleep 5

    RUN_ID=$(gh run list \
        --workflow="$_workflow" \
        --repo="$TRIGGER_CI_REPO" \
        --limit=1 \
        --json databaseId \
        -q '.[0].databaseId')

    if [ -z "$RUN_ID" ]; then
        echo "Could not find workflow run. Check Actions tab manually:"
        echo "  https://github.com/$TRIGGER_CI_REPO/actions/workflows/$_workflow"
        return 1
    fi

    echo "Watching workflow run $RUN_ID..."
    echo "  https://github.com/$TRIGGER_CI_REPO/actions/runs/$RUN_ID"
    echo ""

    gh run watch "$RUN_ID" --repo "$TRIGGER_CI_REPO" --exit-status || true

    echo ""
    echo "=== Final status ==="
    gh run view "$RUN_ID" --repo "$TRIGGER_CI_REPO"
}
