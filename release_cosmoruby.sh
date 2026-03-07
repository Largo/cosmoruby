#!/bin/bash
# CosmoRuby GitHub Release Script
#
# Creates an annotated git tag, verifies binaries, runs quick local
# diagnostics, then creates a GitHub release with ruby.com and irb.com.
#
# Usage: ./release_cosmoruby.sh VERSION TITLE [NOTES]
#   VERSION  Semantic version tag (e.g. v1.3.0)
#   TITLE    Short description (e.g. "Mexican Toaster lifecycle")
#   NOTES    Optional release notes (prompted interactively if omitted)
#
# Examples:
#   ./release_cosmoruby.sh v1.3.0 "Mexican Toaster lifecycle"
#   ./release_cosmoruby.sh v1.3.0 "Big release" "Detailed notes here..."

set -e

# Report which command failed and where
trap 'echo "Error: Command failed at line $LINENO"' ERR

REPO="igravious/cosmoruby"
RUBY="releases/ruby.com"
IRB="releases/irb.com"

# With no arguments, list existing releases and exit.
if [ $# -eq 0 ]; then
    echo "=== CosmoRuby Releases ==="
    echo ""
    gh release list --repo "$REPO" --limit 20 || echo "(no releases found)"
    echo ""
    echo "Usage: $0 VERSION TITLE [NOTES]"
    echo "  e.g. $0 v1.3.0 \"Mexican Toaster lifecycle\""
    exit 0
fi

VERSION="${1:?Usage: $0 VERSION TITLE [NOTES]}"
TITLE="${2:?Usage: $0 VERSION TITLE [NOTES]}"
NOTES="${3:-}"

# ── Validate version format ──────────────────────────────────────────

if ! echo "$VERSION" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Error: VERSION must be semver (e.g. v1.3.0), got: $VERSION"
    exit 1
fi

# ── Check tag doesn't already exist ──────────────────────────────────

if git tag -l "$VERSION" | grep -q .; then
    echo "Error: tag $VERSION already exists locally."
    echo "  To delete: git tag -d $VERSION"
    exit 1
fi

if gh release view "$VERSION" --repo "$REPO" >/dev/null 2>&1; then
    echo "Error: release $VERSION already exists on GitHub."
    echo "  To delete: gh release delete $VERSION --repo $REPO"
    exit 1
fi

# ── Show what we're releasing ────────────────────────────────────────

PREV_TAG=$(git tag -l "v*" --sort=-v:refname | head -1)
echo "=== CosmoRuby Release ==="
echo ""
echo "  Version:  $VERSION"
echo "  Title:    $TITLE"
echo "  Previous: ${PREV_TAG:-none}"
echo ""

if [ -n "$PREV_TAG" ]; then
    COMMIT_COUNT=$(git rev-list "$PREV_TAG"..HEAD --count 2>/dev/null || echo "?")
    echo "  Commits since $PREV_TAG: $COMMIT_COUNT"
    echo ""
    echo "  Recent changes:"
    git log --oneline "$PREV_TAG"..HEAD | sed 's/^/    /'
    echo ""
fi

# ── Check binaries exist ────────────────────────────────────────────

for bin in "$RUBY" "$IRB"; do
    if [ ! -f "$bin" ]; then
        echo "Error: $bin not found."
        echo ""
        echo "Build and package first:"
        echo "  bin/build_ruby.sh -j\$(nproc)"
        exit 1
    fi
done

# ── Verify APE binaries ─────────────────────────────────────────────

. ./check_ape.sh

echo "--- ruby.com ---"
check_ape_magic "$RUBY" || exit 1
check_fat_binary "$RUBY"
check_ape_components "$RUBY" || exit 1
echo ""

echo "--- irb.com ---"
check_ape_magic "$IRB" || exit 1
check_fat_binary "$IRB"
echo ""

# ── Ruby diagnostics ────────────────────────────────────────────────

echo "--- Local diagnostics ---"

RUBY_VERSION_STR=$(./"$RUBY" --disable-gems -e 'puts "#{RUBY_VERSION} #{RUBY_PLATFORM}"' 2>&1) || true
echo "  Ruby:        ${RUBY_VERSION_STR:-FAILED}"

STDLIB_COUNT=$(./"$RUBY" --disable-gems -e 'puts Dir["/zip/**/*"].select { |f| File.file?(f) }.size' 2>&1) || true
echo "  Stdlib:      ${STDLIB_COUNT:-?} files in /zip/"

REQUIRE_OK=$(./"$RUBY" --disable-gems -e '
  ok = 0
  %w[json zlib digest yaml stringio date rubygems].each do |lib|
    begin; require lib; ok += 1; rescue; end
  end
  puts ok
' 2>&1) || true
echo "  Requires:    ${REQUIRE_OK:-?}/7 core libraries loaded"

# irb.com starts its REPL even with -e, so we read the version from
# ruby.com's embedded gem directory name instead.
IRB_VERSION=$(./"$RUBY" --disable-gems -e 'puts Dir["/zip/lib/ruby/gems/4.0.0/gems/irb-*"].first&.split("irb-")&.last' 2>&1) || true
echo "  IRB:         ${IRB_VERSION:-FAILED}"

RUBY_SIZE=$(wc -c < "$RUBY" | tr -d ' ')
IRB_SIZE=$(wc -c < "$IRB" | tr -d ' ')
echo "  ruby.com:    $((RUBY_SIZE / 1024 / 1024))MB ($RUBY_SIZE bytes)"
echo "  irb.com:     $((IRB_SIZE / 1024 / 1024))MB ($IRB_SIZE bytes)"

echo ""

# ── Confirm ──────────────────────────────────────────────────────────

printf "Proceed with release %s? [y/N] " "$VERSION"
read -r REPLY
if [ "$REPLY" != "y" ] && [ "$REPLY" != "Y" ]; then
    echo "Aborted."
    exit 0
fi

echo ""

# ── Build release notes if not provided ──────────────────────────────

if [ -z "$NOTES" ]; then
    NOTES="## CosmoRuby $VERSION — $TITLE

### Ruby
- Ruby $RUBY_VERSION_STR
- $STDLIB_COUNT stdlib files embedded in /zip/
- IRB $IRB_VERSION

### Binaries
| Binary | Size |
|--------|------|
| ruby.com | $((RUBY_SIZE / 1024 / 1024))MB |
| irb.com | $((IRB_SIZE / 1024 / 1024))MB |

### Platforms tested (CI)
- Linux x86_64 + aarch64
- macOS x86_64 + Apple Silicon
- Windows x86_64 + arm64"

    if [ -n "$PREV_TAG" ]; then
        CHANGES=$(git log --oneline "$PREV_TAG"..HEAD | sed 's/^/- /')
        NOTES="$NOTES

### Changes since $PREV_TAG
$CHANGES"
    fi
fi

# ── Create annotated tag ─────────────────────────────────────────────

echo "Creating annotated tag $VERSION..."
git tag -a "$VERSION" -m "CosmoRuby $VERSION - $TITLE"

echo "Pushing tag..."
git push cosmoruby "$VERSION"

echo ""

# ── Create GitHub release ────────────────────────────────────────────

echo "Creating GitHub release..."
gh release create "$VERSION" \
    --repo "$REPO" \
    --title "CosmoRuby $VERSION - $TITLE" \
    --notes "$NOTES" \
    "$RUBY" \
    "$IRB"

echo ""
echo "=== Released ==="
echo "  https://github.com/$REPO/releases/tag/$VERSION"
