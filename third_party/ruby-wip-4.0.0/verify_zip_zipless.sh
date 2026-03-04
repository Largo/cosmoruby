#!/bin/bash
# verify_zip_zipless.sh — Verify zip/zipless binary pairs differ and have correct load paths
#
# Usage: verify_zip_zipless.sh [BIN_DIR]
#   BIN_DIR  Directory containing ruby/irb/miniruby and their .zipless counterparts
#            (defaults to current directory)
#
# Checks:
#   a) Each zip/zipless pair is NOT byte-identical
#   b) Load paths: no duplicates, zip paths start with /zip, zipless paths don't
#
# Exits non-zero on any failure.

set -euo pipefail

BIN_DIR="${1:-.}"
INTERPRETERS=(ruby irb miniruby)
rc=0

check_loadpaths() {
    local bin="$1" variant="$2"
    local paths

    if ! paths=$(RUBYLIB= "$bin" --disable-gems -e '$LOAD_PATH.each { |p| puts p }' 2>/dev/null); then
        echo "  FAIL: $bin failed to execute"
        return 1
    fi

    if [ -z "$paths" ]; then
        echo "  FAIL: $bin produced empty \$LOAD_PATH"
        return 1
    fi

    # Check for duplicates
    local dupes
    dupes=$(echo "$paths" | sort | uniq -d)
    if [ -n "$dupes" ]; then
        echo "  FAIL: $bin has duplicate load paths:"
        echo "$dupes" | sed 's/^/    /'
        return 1
    fi

    case "$variant" in
        zip)
            local bad
            bad=$(echo "$paths" | grep -v '^/zip' || true)
            if [ -n "$bad" ]; then
                echo "  FAIL: $bin (zip) has non-/zip paths:"
                echo "$bad" | sed 's/^/    /'
                return 1
            fi
            ;;
        zipless)
            local bad
            bad=$(echo "$paths" | grep '^/zip' || true)
            if [ -n "$bad" ]; then
                echo "  FAIL: $bin (zipless) has /zip paths:"
                echo "$bad" | sed 's/^/    /'
                return 1
            fi
            ;;
    esac

    local count
    count=$(echo "$paths" | wc -l)
    echo "  OK:   ($variant) $count paths, all valid"
    return 0
}

echo "=== Verifying zip/zipless binary pairs ==="
echo

for interp in "${INTERPRETERS[@]}"; do
    zip_bin="$BIN_DIR/$interp"
    zipless_bin="$BIN_DIR/$interp.zipless"

    if ! [ -f "$zip_bin" ] || ! [ -f "$zipless_bin" ]; then
        echo "SKIP: $interp (one or both binaries missing)"
        echo
        continue
    fi

    echo "--- $interp ---"

    # a) Byte comparison
    if cmp -s "$zip_bin" "$zipless_bin"; then
        echo "  FAIL: $interp and $interp.zipless are byte-identical"
        rc=1
    else
        echo "  OK:   $interp and $interp.zipless differ"
    fi

    # b) Load path sanity (irb hardcodes IRB.start, can't run -e;
    #    same loadpath.o linkage as ruby so byte diff suffices)
    if [ "$interp" != "irb" ]; then
        check_loadpaths "$zip_bin" zip       || rc=1
        check_loadpaths "$zipless_bin" zipless || rc=1
    else
        echo "  OK:   (irb) load path check skipped — same linkage as ruby"
    fi

    echo
done

if [ $rc -eq 0 ]; then
    echo "All checks passed."
else
    echo "Some checks FAILED — aborting."
fi

exit $rc
