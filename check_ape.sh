# check_ape.sh — shared APE binary verification functions
# Source this file: . ./check_ape.sh

check_ape_magic() {
    local binary="$1"
    local magic
    magic=$(head -c 6 "$binary" | od -A n -t x1 | tr -d ' ')
    if [ "$magic" != "4d5a71467044" ]; then
        echo "Error: $binary does not have APE magic bytes (MZqFpD)."
        echo "Got: $magic"
        return 1
    fi
    echo "APE magic: OK"
    return 0
}

# Usage: check_fat_binary <fat-binary> [x86-stripped] [arm-stripped]
# With 3 args: size comparison against both single-arch stripped binaries
# With 1 arg: just report size (real validation happens when it runs)
check_fat_binary() {
    local binary="$1"
    local size
    size=$(wc -c < "$binary" | tr -d ' ')

    if [ $# -ge 3 ]; then
        local x86_size arm_size
        x86_size=$(wc -c < "$2" | tr -d ' ')
        arm_size=$(wc -c < "$3" | tr -d ' ')
        if [ "$size" -gt "$x86_size" ] && [ "$size" -gt "$arm_size" ]; then
            echo "Fat binary: OK (x86_64 + aarch64)"
            echo "  x86_64 stripped: $x86_size bytes"
            echo "  aarch64 stripped: $arm_size bytes"
            echo "  fat binary:      $size bytes"
            return 0
        else
            echo "WARNING: $binary ($size bytes) not larger than both stripped binaries."
            echo "  x86_64 stripped: $x86_size bytes"
            echo "  aarch64 stripped: $arm_size bytes"
            return 1
        fi
    else
        echo "Fat binary: $size bytes (run on aarch64 to verify)"
        return 0
    fi
}
