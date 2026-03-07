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

# Get the most recent run ID for a workflow, or empty string if none.
_latest_run_id() {
    gh run list \
        --workflow="$1" \
        --repo="$TRIGGER_CI_REPO" \
        --limit=1 \
        --json databaseId \
        -q '.[0].databaseId' 2>/dev/null || true
}

# Trigger a GitHub Actions workflow.
#
# Tries workflow_dispatch first (cleaner, shows as "manually triggered").
# Falls back to git push if dispatch fails — this happens when the
# workflow file only exists on a feature branch, not on the default
# branch (master). GitHub only recognises workflow_dispatch triggers
# for workflows that are on the default branch.
#
# Sets TRIGGER_CI_BEFORE_ID so watch_workflow knows which run existed
# before we triggered, and can wait for a genuinely new one.
#
# Usage: trigger_workflow WORKFLOW [DISPATCH_ARGS]
#   DISPATCH_ARGS: extra flags for gh workflow run (e.g. -f key=value)
trigger_workflow() {
    _workflow="$1"
    shift
    _dispatch_args="$*"

    # Snapshot the latest run ID before triggering, so watch_workflow
    # can distinguish "new run" from "stale run that was already there".
    TRIGGER_CI_BEFORE_ID=$(_latest_run_id "$_workflow")

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

    # Touch the workflow file so the push satisfies any paths: filter.
    # Many workflows only trigger on push when their own .yml changes.
    # We append/update a timestamp comment — harmless but enough to
    # make git see a diff.
    _wf_path=".github/workflows/$_workflow"
    if [ -f "$_wf_path" ]; then
        _stamp="# last-triggered: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        if grep -q '^# last-triggered:' "$_wf_path"; then
            sed -i "s/^# last-triggered:.*/$_stamp/" "$_wf_path"
        else
            echo "$_stamp" >> "$_wf_path"
        fi
        git add "$_wf_path"
        git commit -m "Trigger $_workflow CI run"
    fi

    git push cosmoruby

    echo ""
}

# Poll until a new workflow run appears, then watch it to completion.
#
# Uses TRIGGER_CI_BEFORE_ID (set by trigger_workflow) to ensure we
# pick up the run we just triggered, not a stale older run.
#
# Usage: watch_workflow WORKFLOW
watch_workflow() {
    _workflow="$1"
    _max_wait=30
    _waited=0

    echo "Waiting for new workflow run..."

    # Poll until a run with a different (newer) ID appears.
    while [ "$_waited" -lt "$_max_wait" ]; do
        RUN_ID=$(_latest_run_id "$_workflow")

        if [ -n "$RUN_ID" ] && [ "$RUN_ID" != "${TRIGGER_CI_BEFORE_ID:-}" ]; then
            break
        fi

        _waited=$((_waited + 2))
        printf "  polling... (%ds)\r" "$_waited"
        sleep 2
    done

    if [ -z "$RUN_ID" ] || [ "$RUN_ID" = "${TRIGGER_CI_BEFORE_ID:-}" ]; then
        echo ""
        echo "Timed out waiting for new run after ${_max_wait}s."
        echo "Check Actions tab manually:"
        echo "  https://github.com/$TRIGGER_CI_REPO/actions/workflows/$_workflow"
        return 1
    fi

    echo "Found run $RUN_ID                    "
    echo "  https://github.com/$TRIGGER_CI_REPO/actions/runs/$RUN_ID"
    echo ""

    gh run watch "$RUN_ID" --repo "$TRIGGER_CI_REPO" --exit-status || true

    echo ""
    echo "=== Final status ==="
    gh run view "$RUN_ID" --repo "$TRIGGER_CI_REPO"
}
