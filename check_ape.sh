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
    echo "APE magic:      OK"
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
            echo "Fat binary:     OK"
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
        echo "Fat binary:     $size bytes"
        return 0
    fi
}

# Deep inspection of APE binary components using ruby.
# Checks: x86_64 ELF, aarch64 ELF, Mach-O header, M1 loader source.
# Returns 0 if all components present, 1 if any missing.
check_ape_components() {
    local binary="$1"
    local ruby_bin=""

    # Find a ruby interpreter
    if command -v ruby.com >/dev/null 2>&1; then
        ruby_bin="ruby.com"
    elif command -v ruby >/dev/null 2>&1; then
        ruby_bin="ruby"
    else
        echo "Components:     skipped (ruby not available)"
        return 0
    fi

    "$ruby_bin" --disable-gems - "$binary" <<'RUBYEOF'
require 'zlib'

path = ARGV[0]
data = File.binread(path)
ok = true

# 1. Find ELF headers by architecture
elf_magic = "\x7fELF".b
arches = {}
i = 0
while (pos = data.index(elf_magic, i))
  if pos + 20 <= data.size
    e_machine = data[pos + 18, 2].unpack1('v')
    arches['x86_64'] = pos if e_machine == 0x3E
    arches['aarch64'] = pos if e_machine == 0xB7
  end
  i = pos + 1
end

if arches['x86_64']
  printf("x86_64 ELF:     OK (offset 0x%x)\n", arches['x86_64'])
else
  puts 'x86_64 ELF:     MISSING'
  ok = false
end

if arches['aarch64']
  printf("aarch64 ELF:    OK (offset 0x%x)\n", arches['aarch64'])
else
  puts 'aarch64 ELF:    MISSING'
  ok = false
end

# 2. Mach-O header (0xFEEDFACF = 64-bit little-endian)
macho_magic = [0xFEEDFACF].pack('V')
pos = data.index(macho_magic)
if pos
  cputype = data[pos + 4, 4].unpack1('V')
  arch = { 0x01000007 => 'x86_64', 0x0100000C => 'aarch64' }
    .fetch(cputype, "unknown(0x#{cputype.to_s(16)})")
  printf("Mach-O header:  OK (%s, offset 0x%x)\n", arch, pos)
else
  puts 'Mach-O header:  MISSING (no macOS x86_64 support)'
  ok = false
end

# 3. M1 loader source (may be gzip-compressed by apelink)
m1_found = false
if data.include?('ape-m1'.b) || data.include?('__APPLE__'.b)
  m1_found = true
else
  # Check gzip streams (apelink uses raw deflate after gzip header)
  gz_magic = "\x1f\x8b".b
  i = 0
  while (pos = data.index(gz_magic, i))
    begin
      # Skip 10-byte gzip header, inflate raw deflate stream
      decompressed = Zlib::Inflate.new(-Zlib::MAX_WBITS).inflate(data[pos + 10, 200_000])
      if decompressed.include?('ape-m1') || decompressed.include?('__APPLE__')
        m1_found = true
        break
      end
    rescue
      # not a valid deflate stream, skip
    end
    i = pos + 1
  end
end

if m1_found
  puts 'M1 loader src:  OK (macOS Apple Silicon support)'
else
  puts 'M1 loader src:  MISSING (no macOS aarch64 support)'
  ok = false
end

exit(ok ? 0 : 1)
RUBYEOF
}
