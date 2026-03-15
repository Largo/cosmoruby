#!/bin/sh
# common.sh - shared functions for ccc and rcc wrapper scripts
#
# Provides the toolchain resolution, compilation, linking, and packaging
# pipeline for building Cosmopolitan APE binaries.

set -e

################################################################################
# Path resolution

resolve_toolchain() {
  REPO_ROOT="$(git rev-parse --show-toplevel)" || {
    echo "error: not inside a git repo" >&2
    exit 1
  }

  COSMOCC="$REPO_ROOT/.cosmocc/current/bin"
  if [ ! -d "$COSMOCC" ]; then
    echo "error: cosmocc toolchain not found at $COSMOCC" >&2
    echo "hint: run 'make -j1' once to download the toolchain" >&2
    exit 1
  fi

  O="$REPO_ROOT/o//"

  # Compilers
  CC_X86="$COSMOCC/x86_64-linux-cosmo-gcc"
  CC_ARM="$COSMOCC/aarch64-linux-cosmo-gcc"

  # Linkers
  LD_X86="$COSMOCC/x86_64-linux-cosmo-ld.bfd"
  LD_ARM="$COSMOCC/aarch64-linux-cosmo-ld.bfd"

  # Tools
  FIXUPOBJ="$COSMOCC/fixupobj"
  ZIPCOPY="$COSMOCC/zipcopy"
  APELINK_BIN="$COSMOCC/apelink"
  OBJCOPY_X86="$COSMOCC/x86_64-linux-cosmo-objcopy"
  OBJCOPY_ARM="$COSMOCC/aarch64-linux-cosmo-objcopy"

  # CRT and APE objects (x86_64)
  CRT_X86="$O/libc/crt/crt.o"
  APE_LDS_X86="$O/ape/ape.lds"
  APE_OBJ_X86="$O/ape/ape-no-modify-self.o"

  # CRT and APE objects (aarch64)
  CRT_ARM="$O/aarch64/libc/crt/crt.o"
  APE_LDS_ARM="$O/aarch64/ape/aarch64.lds"

  # Verify critical files exist
  for f in "$CC_X86" "$LD_X86" "$FIXUPOBJ" "$APELINK_BIN" "$OBJCOPY_X86"; do
    if [ ! -x "$f" ]; then
      echo "error: missing tool: $f" >&2
      exit 1
    fi
  done

  for f in "$CRT_X86" "$APE_LDS_X86" "$APE_OBJ_X86"; do
    if [ ! -f "$f" ]; then
      echo "error: missing build artifact: $f" >&2
      echo "hint: run 'make -j1' to build the base system" >&2
      exit 1
    fi
  done
}

################################################################################
# Compiler flags

CFLAGS_COMMON="\
  -Wall \
  -fno-omit-frame-pointer \
  -O2 \
  -nostdinc \
  -std=gnu23"

cflags_x86() {
  echo "$CFLAGS_COMMON \
    -iquote$REPO_ROOT \
    -isystem $REPO_ROOT/libc/isystem \
    -include $REPO_ROOT/libc/integral/normalize.inc"
}

cflags_arm() {
  echo "$CFLAGS_COMMON \
    -iquote$REPO_ROOT \
    -isystem $REPO_ROOT/libc/isystem \
    -include $REPO_ROOT/libc/integral/normalize.inc"
}

################################################################################
# Linker flags

LDFLAGS_COMMON="\
  -static \
  -nostdlib \
  -z norelro \
  --gc-sections \
  -z noexecstack \
  --build-id=none \
  --no-dynamic-linker"

################################################################################
# Compilation

compile_x86() {
  local src="$1"
  local out="$2"
  verbose_run "$CC_X86" $(cflags_x86) -c -o "$out" "$src"
  verbose_run "$FIXUPOBJ" "$out"
}

compile_arm() {
  local src="$1"
  local out="$2"
  if [ ! -x "$CC_ARM" ]; then
    echo "warning: aarch64 compiler not found, skipping arm build" >&2
    return 1
  fi
  verbose_run "$CC_ARM" $(cflags_arm) -c -o "$out" "$src"
  verbose_run "$FIXUPOBJ" "$out"
}

################################################################################
# Library resolution
#
# Three tiers:
#   "default"       - FAT_BASE + STDIO_LIBC_LIBS (like gcc implying -lc)
#   "kitchen_sink"  - everything in the repo, like examples/BUILD.mk
#   "nostdlib"      - no .a archives at all, user provides everything via -l
#   "ruby"          - default + Ruby VM + extensions (rcc default)

# Helper: collect archives that exist under a prefix directory.
# Usage: collect_libs <prefix> lib1.a lib2.a ...
# e.g.:  collect_libs "$O" libc/calls/syscalls.a libc/fmt/fmt.a
collect_libs() {
  local prefix="$1"
  shift
  local libs=""
  for lib in "$@"; do
    if [ -f "$prefix/$lib" ]; then
      libs="$libs $prefix/$lib"
    fi
  done
  echo "$libs"
}

# FAT_BASE: the bare cost of a fat APE binary that does nothing.
# This is what empty.c (int main(){return 0;}) needs to link.
# Determined empirically — if it doesn't link, add what's missing.
FAT_BASE="\
  libc/runtime/runtime.a
  libc/intrin/intrin.a
  libc/sysv/sysv.a
  libc/nexgen32e/nexgen32e.a
  libc/sysv/calls.a
  libc/calls/syscalls.a
  libc/str/str.a
  libc/fmt/fmt.a
  libc/nt/kernel32.a
  libc/nt/advapi32.a
  libc/nt/BCryptPrimitives.a
  libc/nt/synchronization.a
  libc/nt/realtime.a
  third_party/compiler_rt/compiler_rt.a
  third_party/puff/puff.a
"

# STDIO_LIBC_LIBS: what hello.c (printf) needs on top of FAT_BASE.
# stdio, malloc, threads, etc. — the extra cost of a working C stdlib.
# Determined empirically — if hello.c doesn't link, add what's missing.
STDIO_LIBC_LIBS="\
  libc/stdio/stdio.a
  libc/mem/mem.a
  third_party/mimalloc/mimalloc.a
"

# DEFAULT_LIBS: what you get with no flags — like gcc implying -lc.
# This is FAT_BASE + STDIO_LIBC_LIBS combined.
DEFAULT_LIBS="$FAT_BASE $STDIO_LIBC_LIBS"

# Everything else that the examples/BUILD.mk kitchen sink includes.
# These are added on top of DEFAULT_LIBS when -l kitchen_sink is used.
#
# TODO: support MODE= (dbg, opt, rel, tiny, etc.). Currently we always
# link against o// (default mode). Tiny modes use dlmalloc instead of
# mimalloc, different APE bootloader, etc. — none of that is handled yet.
KITCHEN_SINK_EXTRAS="\
"

# Ruby-specific libraries (on top of minimal).
# Ruby-specific libraries on top of DEFAULT_LIBS.
# Determined empirically — add what the linker demands, nothing more.
RUBY_LIBS="
  libc/dlopen/dlopen.a
  libc/elf/elf.a
  libc/log/log.a
  libc/nt/iphlpapi.a
  libc/nt/ntdll.a
  libc/nt/ole32.a
  libc/nt/psapi.a
  libc/nt/shell32.a
  libc/nt/winmm.a
  libc/nt/ws2_32.a
  libc/proc/proc.a
  libc/sock/sock.a
  libc/system/system.a
  libc/thread/thread.a
  libc/tinymath/tinymath.a
  libc/x/x.a
  net/http/http.a
  net/https/https.a
  third_party/cosmo_plugin/cosmo_plugin.a
  third_party/dlmalloc/dlmalloc.a
  third_party/gdtoa/gdtoa.a
  third_party/getopt/getopt.a
  third_party/libunwind/libunwind.a
  third_party/libyaml/libyaml.a
  third_party/mbedtls/mbedtls.a
  third_party/musl/musl.a
  third_party/nsync/mem/nsync.a
  third_party/nsync/nsync.a
  third_party/regex/regex.a
  third_party/ruby/ruby.a
  third_party/sed/sed.a
  third_party/tr/tr.a
  third_party/tz/tz.a
  third_party/zlib/zlib.a
"

# Ruby C extension archives — linked with --whole-archive so their
# Init_ registration functions survive --gc-sections.
RUBY_EXT_LIBS="\
  third_party/ruby/ext/date/date.a
  third_party/ruby/ext/fcntl/fcntl.a
  third_party/ruby/ext/etc/etc.a
  third_party/ruby/ext/objspace/objspace.a
  third_party/ruby/ext/json/json.a
  third_party/ruby/ext/digest/digest.a
  third_party/ruby/ext/coverage/coverage.a
  third_party/ruby/ext/continuation/continuation.a
  third_party/ruby/ext/io/console/console.a
  third_party/ruby/ext/io/nonblock/nonblock.a
  third_party/ruby/ext/io/wait/wait.a
  third_party/ruby/ext/monitor/monitor.a
  third_party/ruby/ext/psych/psych.a
  third_party/ruby/ext/rbconfig/sizeof/sizeof.a
  third_party/ruby/ext/ripper/ripper.a
  third_party/ruby/ext/socket/socket.a
  third_party/ruby/ext/stringio/stringio.a
  third_party/ruby/ext/strscan/strscan.a
  third_party/ruby/ext/zlib/zlib.a
  third_party/ruby/ext/mbedtls/mbedtls.a
"

# Resolve the library set for a given arch prefix.
# Usage: get_libs <prefix> <tier>
#   prefix: "$O" for x86_64, "$O/aarch64" for arm
#   tier:   "default", "kitchen_sink", "nostdlib", "ruby"
get_libs() {
  local prefix="$1"
  local tier="$2"

  case "$tier" in
    nostdlib)
      # No .a archives at all. User provides everything via -l.
      # (CRT + APE bootloader are still linked — that's the executable
      # format, not a library.)
      ;;
    default)
      collect_libs "$prefix" $DEFAULT_LIBS
      ;;
    kitchen_sink)
      collect_libs "$prefix" $DEFAULT_LIBS $KITCHEN_SINK_EXTRAS
      ;;
    ruby)
      local base ext_found
      base="$(collect_libs "$prefix" $DEFAULT_LIBS $RUBY_LIBS)"
      ext_found="$(collect_libs "$prefix" $RUBY_EXT_LIBS)"
      if [ -n "$ext_found" ]; then
        echo "$base --whole-archive $ext_found --no-whole-archive"
      else
        echo "$base"
      fi
      return
      ;;
  esac
}

################################################################################
# Linking

link_x86() {
  local output="$1"
  shift
  # $@ = object files followed by library arguments
  # --start-group/--end-group lets the linker resolve circular
  # dependencies between static archives (e.g. runtime needs mem,
  # mem needs intrin, intrin needs runtime)
  verbose_run "$LD_X86" \
    $LDFLAGS_COMMON \
    -T "$APE_LDS_X86" \
    "$APE_OBJ_X86" \
    "$CRT_X86" \
    --start-group \
    "$@" \
    --end-group \
    -o "$output"
  verbose_run "$FIXUPOBJ" "$output"
}

link_arm() {
  local output="$1"
  shift
  if [ ! -f "$CRT_ARM" ] || [ ! -f "$APE_LDS_ARM" ]; then
    echo "warning: aarch64 build artifacts not found, skipping arm link" >&2
    return 1
  fi
  verbose_run "$LD_ARM" \
    $LDFLAGS_COMMON \
    -T "$APE_LDS_ARM" \
    "$CRT_ARM" \
    --start-group \
    "$@" \
    --end-group \
    -o "$output"
  verbose_run "$FIXUPOBJ" "$output"
}

################################################################################
# Fat binary creation and packaging

merge_fat() {
  local output="$1"
  local x86_dbg="$2"
  local arm_elf="$3"
  local loader_flags=""

  # Use the same loader paths as ./bake
  local ape_x86="$COSMOCC/ape-x86_64.elf"
  local ape_arm="$COSMOCC/ape-aarch64.elf"
  local ape_m1="$COSMOCC/ape-m1.c"

  if [ -f "$ape_x86" ]; then
    loader_flags="$loader_flags -l $ape_x86"
  fi
  if [ -f "$ape_arm" ]; then
    loader_flags="$loader_flags -l $ape_arm"
  fi
  if [ -f "$ape_m1" ]; then
    loader_flags="$loader_flags -M $ape_m1"
  fi

  verbose_run "$APELINK_BIN" \
    -o "$output" \
    $loader_flags \
    "$x86_dbg" \
    "$arm_elf"
}

strip_and_package() {
  local fat_bin="$1"
  local output="$2"
  cp "$fat_bin" "$output"
}

################################################################################
# Utility functions

verbose_run() {
  if [ "${VERBOSE:-0}" = "1" ]; then
    echo "+ $*" >&2
  fi
  "$@"
}

cleanup() {
  if [ -n "$TMP" ] && [ -d "$TMP" ]; then
    rm -rf "$TMP"
  fi
}

setup_tmp() {
  TMP="$(mktemp -d)"
  trap cleanup EXIT
}

################################################################################
# Argument parsing helpers

parse_common_args() {
  OUTPUT="a.out"
  VERBOSE=0
  EXTRA_LIBS=""
  STDLIB_TIER=""  # set by caller as default, overridden by flags
  DISCOVER=0
  FILES=""

  while [ $# -gt 0 ]; do
    case "$1" in
      -o)
        shift
        OUTPUT="$1"
        ;;
      -v)
        VERBOSE=1
        ;;
      -l)
        shift
        if [ "$1" = "kitchen_sink" ]; then
          STDLIB_TIER="kitchen_sink"
        else
          EXTRA_LIBS="$EXTRA_LIBS $1"
        fi
        ;;
      --nostdlib)
        STDLIB_TIER="nostdlib"
        ;;
      --discover)
        DISCOVER=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        echo "error: unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
      *)
        FILES="$FILES $1"
        ;;
    esac
    shift
  done

  FILES="$(echo "$FILES" | sed 's/^ //')"

  if [ -z "$FILES" ]; then
    echo "error: no input files" >&2
    usage >&2
    exit 1
  fi
}

# Resolve a -l library name to archive path(s).
#
# Conceptual names map to groups of archives (like gcc's -lm, -lpthread).
# Anything else is resolved by searching common locations for a .a file.
#
# Usage: resolve_extra_lib <name> <arch>
#   arch: "x86" or "arm"
resolve_extra_lib() {
  local name="$1"
  local arch="$2"  # "x86" or "arm"
  local prefix
  if [ "$arch" = "arm" ]; then
    prefix="$O/aarch64"
  else
    prefix="$O"
  fi

  # Conceptual -l names → archive groups
  case "$name" in
    c)
      # The C standard library: stdio, malloc, strings, threads, signals, etc.
      # This is what gcc links implicitly. We don't — you ask for it.
      collect_libs "$prefix" $STDIO_LIBC_LIBS
      return ;;
    m|math)
      collect_libs "$prefix" libc/tinymath/tinymath.a third_party/gdtoa/gdtoa.a
      return ;;
    net|network)
      collect_libs "$prefix" \
        libc/sock/sock.a \
        net/http/http.a \
        net/https/https.a \
        third_party/mbedtls/mbedtls.a \
        third_party/haclstar/haclstar.a
      return ;;
    crypto|tls|ssl)
      collect_libs "$prefix" \
        third_party/mbedtls/mbedtls.a \
        third_party/haclstar/haclstar.a
      return ;;
    dl|dlopen)
      collect_libs "$prefix" libc/dlopen/dlopen.a
      return ;;
    pthread|thread)
      # threads are in the default set; this maps to the same archive
      # so -lpthread works for people used to gcc
      collect_libs "$prefix" libc/thread/thread.a
      return ;;
    regex)
      collect_libs "$prefix" third_party/regex/regex.a
      return ;;
    z|compression)
      collect_libs "$prefix" third_party/zlib/zlib.a
      return ;;
  esac

  # File-based resolution: search common locations for <name>.a
  for candidate in \
    "$prefix/third_party/$name/$name.a" \
    "$prefix/third_party/$name/lib$name.a" \
    "$prefix/net/$name/$name.a" \
    "$prefix/libc/$name/$name.a" \
    "$prefix/tool/$name/$name.a" \
  ; do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return
    fi
  done

  echo "error: cannot resolve library: $name" >&2
  exit 1
}

################################################################################
# --discover: find missing archives by parsing linker errors
#
# Given linker stderr output, extracts the first undefined reference,
# searches o// archives for the symbol, and if found, inserts the
# archive into RUBY_LIBS in common.sh (lexicographically sorted).

# Find which .a provides a symbol. Prints the relative archive path
# (e.g. "libc/proc/proc.a") or nothing.
find_archive_for_symbol() {
  local sym="$1"
  # Search x86_64 archives, return path relative to o//
  # e.g. "libc/proc/proc.a" not "/home/.../o//libc/proc/proc.a"
  find "$O" -name '*.a' -not -path '*/aarch64/*' -not -path '*/tmp/*' -exec sh -c '
    nm "$1" 2>/dev/null | grep -q " [TBDG] '"$sym"'\$" && echo "$1"
  ' _ {} \; | head -1 | sed "s|^$REPO_ROOT/o//||"
}

# Insert an archive path into a named variable block in common.sh, sorted.
# Usage: insert_into_lib_var <varname> <archive>
#   e.g. insert_into_lib_var RUBY_LIBS libc/proc/proc.a
insert_into_lib_var() {
  local varname="$1"
  local archive="$2"
  local common_sh="$SCRIPT_DIR/common.sh"

  # Check if already present in this var's block specifically
  if sed -n "/^${varname}=\"/,/^\"/p" "$common_sh" | grep -qF "$archive"; then
    echo "discover: $archive already in $varname" >&2
    return 1
  fi

  # Extract current entries, add new one, sort, rewrite the block.
  local tmp_list="$(mktemp)"

  sed -n "/^${varname}=\"/,/^\"/{
    /^${varname}=\"/d
    /^\"/d
    s/^[[:space:]]*//
    p
  }" "$common_sh" > "$tmp_list"

  echo "$archive" >> "$tmp_list"
  sort -o "$tmp_list" "$tmp_list"

  # Build replacement block
  local new_block="${varname}=\""
  while IFS= read -r line; do
    new_block="$new_block
  $line"
  done < "$tmp_list"
  new_block="$new_block
\""

  # Replace the block in common.sh using awk
  awk -v var="$varname" -v new="$new_block" '
    $0 ~ "^"var"=\"" { printing=1; print new; next }
    printing && /^"/ { printing=0; next }
    printing { next }
    { print }
  ' "$common_sh" > "$common_sh.tmp" && mv "$common_sh.tmp" "$common_sh"

  rm -f "$tmp_list"
  echo "discover: added $archive to $varname" >&2
}

# Try linking; on undefined reference errors, discover and add the
# missing archive, then retry. Stops when linking succeeds or the
# error is not an undefined reference.
#
# Usage: discover_link <link_command...>
#   The command should be the full link invocation. It will be retried
#   after each discovered archive.
discover_link() {
  local max_rounds=50
  local round=0

  while [ "$round" -lt "$max_rounds" ]; do
    round=$((round + 1))

    # Try linking, capture stderr
    local errfile="$TMP/link_errors.txt"
    if "$@" 2>"$errfile"; then
      # Link succeeded
      return 0
    fi

    # Check for undefined reference
    local undef
    undef="$(grep -oP "undefined reference to \`\K[^']*" "$errfile" | head -1)"

    if [ -z "$undef" ]; then
      # Not an undefined reference error — real failure
      cat "$errfile" >&2
      return 1
    fi

    echo "discover: undefined reference to '$undef'" >&2

    # Search for the symbol
    local archive_path
    archive_path="$(find_archive_for_symbol "$undef")"

    if [ -z "$archive_path" ]; then
      echo "discover: no archive found providing '$undef'" >&2
      cat "$errfile" >&2
      return 1
    fi

    # Convert absolute path to relative (e.g. strip o// prefix)
    local rel_path
    rel_path="$(echo "$archive_path" | sed "s|^$O/||")"

    echo "discover: '$undef' found in $rel_path" >&2

    # Insert into RUBY_LIBS in common.sh
    if ! insert_into_ruby_libs "$rel_path"; then
      # Already present but still failing — some other issue
      cat "$errfile" >&2
      return 1
    fi

    # Re-source common.sh to pick up the new RUBY_LIBS
    . "$SCRIPT_DIR/common.sh"
  done

  echo "discover: gave up after $max_rounds rounds" >&2
  return 1
}
