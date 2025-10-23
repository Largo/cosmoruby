# Ruby to Cosmopolitan Port: BUILD.mk Analysis and Plan

## Overview
This document outlines the plan to port Ruby 3.4.7 to Cosmopolitan by analyzing the output of `make -n test` and crafting an improved BUILD.mk file. The goal is to create a hermetic, portable build without relying on GNU Make's complex dependencies.

## Background
- **Context**: Porting Ruby to Cosmopolitan for universal binaries.
- **Key Insight**: `make test` performs a full Ruby build (compiling ~100+ C files) followed by basic tests (bootstrap, known bugs, leaked globals, basic).
- **Analysis Source**: Output from `make -n test` in `/home/groobiest/Code/jart/cosmopolitan/third_party/ruby`.

## Step 1: Parse and Categorize the `make -n test` Output
- **Objective**: Extract all build commands, dependencies, and flags into a structured format.
- **Actions**:
  - Save the full `make -n test` output to a file (e.g., `make_n_test.log`) for reference.
  - Categorize the commands:
    - **Compilation**: All `gcc` compile commands (e.g., `gcc -fstack-protector-strong ... -o file.o -c file.c`).
    - **Linking**: Commands like `gcc-ar rcD libruby-static.a ...` and `gcc ... -o ruby`.
    - **Test Execution**: Commands like `./miniruby ... ./bootstraptest/runner.rb`.
    - **Preprocessing/Generation**: Commands for generating files (e.g., `erb` templates, `file2lastrev.rb`).
  - Identify patterns: Most compiles use the same flags, includes, and outputs.

## Step 2: Extract Build Metadata
- **Objective**: Pull out reusable variables for BUILD.mk (e.g., CFLAGS, INCLUDES, SOURCES).
- **Actions**:
  - **Source Files**: List all `.c` files compiled (e.g., `array.c`, `ast.c`, ..., `vm_trace.c`, plus prism and enc subdirs).
  - **Include Paths**: Common `-I` flags (e.g., `-I. -I.ext/include/x86_64-linux -I.ext/include -I./include -I. -I./prism -I./enc/unicode/15.0.0`).
  - **Compiler Flags**: Extract CFLAGS (e.g., `-fstack-protector-strong -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=2 -O3 -fno-fast-math -ggdb3 -Wall ... -DRUBY_EXPORT -fPIE`).
  - **Linker Flags**: For static lib and executable (e.g., `-L. -fstack-protector-strong -rdynamic -Wl,-export-dynamic -fstack-protector-strong -pie` and libs like `-lz -lrt -ldl -lcrypt -lm -lpthread`).
  - **Generated Files**: Note files created by scripts (e.g., `revision.h`, `builtin_binary.inc`).
  - **Dependencies**: Map prerequisites (e.g., `miniruby` depends on many `.o` files).

## Step 3: Map to Cosmopolitan BUILD.mk Structure
- **Objective**: Translate the make logic into BUILD.mk syntax.
- **Actions**:
  - **Define Variables**: In BUILD.mk, set global vars like:
    ```
    CFLAGS = -fstack-protector-strong -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=2 -O3 ... -DRUBY_EXPORT -fPIE
    INCLUDES = -I. -I.ext/include/x86_64-linux -I.ext/include -I./include -I. -I./prism -I./enc/unicode/15.0.0
    LIBS = -lz -lrt -ldl -lcrypt -lm -lpthread
    ```
  - **Source Lists**: Group sources (e.g., `RUBY_SOURCES = array.c ast.c ...`).
    - Separate lists for miniruby (109 files) and full ruby (115 files).
  - **Object Rules**: Use BUILD.mk patterns for compilation (e.g., implicit rules or explicit lists).
  - **Library/Executable Targets**: Define `libruby-static.a` and `ruby` targets with dependencies.
    - Add `miniruby` target using the subset of sources/objects.
  - **Test Targets**: Add phony targets for tests (e.g., `bootstraptest`, `basictest`) that run after build.

## Step 4: Optimize for Cosmopolitan
- **Objective**: Leverage Cosmopolitan's features for portability and simplicity.
- **Actions**:
  - **Hermetic Builds**: Ensure all paths are relative or handled by Cosmopolitan (e.g., no absolute `/tmp/ruby-reference`).
  - **Cross-Compilation**: Handle arch-specific includes (e.g., `x86_64-linux`).
  - **Reduce Redundancy**: Use wildcards or loops in BUILD.mk instead of listing every file.
  - **Skip Unneeded Steps**: For a port, we might skip some generation (e.g., if revision.h can be static).
  - **Test Integration**: Make tests runnable in the Cosmopolitan environment (e.g., via `o//` outputs).

## Step 5: Implement and Test Incrementally
- **Objective**: Build and validate BUILD.mk step-by-step.
- **Actions**:
  - Start with core compilation (e.g., build `libruby-static.a`).
  - Add linking and executable build.
  - Integrate tests (run them after build).
  - Debug issues (e.g., missing symlinks like `.ext/include/x86_64-linux/ruby/config.h`).
  - Compare outputs: Ensure the Cosmopolitan-built Ruby behaves like the make-built one.

## Step 6: Document and Refine
- **Objective**: Make BUILD.mk maintainable.
- **Actions**:
  - Add comments explaining each section (e.g., "Core VM sources" or "Test runners").
  - Handle edge cases (e.g., Unicode tables, prism parser).
  - Update as needed for future Ruby versions.

## Notes
- **Development Build Flag**: Always use `make -j1` during development to avoid parallel compilation issues and get clearer error output for debugging.
- **Change Management**: Before making any changes/updates/edits to files, always explain the change to the user beforehand and ideally request that the change be made. This ensures transparency and collaboration in the development process.
- **VCS Handling**: Suppressed in `defs/gmake.mk` with `--suppress_not_found`.
- **Symlinks**: Ensure `.ext/include/x86_64-linux/ruby/config.h` is symlinked.
- **Testing**: Focus on bootstraptest, knownbugs, leaked globals, and basictest for validation.
- **Scripts and Logs Location**: Scripts for porting work are in `third_party/ruby/port_scripts/`, and analysis logs are in `third_party/ruby/analysis_logs/`.
- **Mkdeps Errors**: Ignore mkdeps warnings/errors during initial compilation phase; focus on getting CosmoRuby to build and pass tests first, then refine dependency tracking.

## Progress Log
- [Date]: Initial analysis from `make -n test`.
- [Date]: Created this document.
- [21 October 2025]: Added VCS suppression in `defs/gmake.mk` by appending `--suppress_not_found` to the `file2lastrev.rb` command to eliminate spurious stderr output.
- [21 October 2025]: Created symlink `.ext/include/x86_64-linux/ruby/config.h -> ../../../../include/ruby/config.h` to resolve missing config header dependency.
- [21 October 2025]: Created `capture_make_n_test.sh` script in `port_scripts/` to run `make -n test` and save output to `analysis_logs/make_n_test.log` for structured analysis.
- [21 October 2025]: Created `extract_sources.sh` and `extract_miniruby_sources.sh` scripts to extract source file lists from `make -n test` and `make -n miniruby` outputs, saving in build order and sorted formats to `analysis_logs/` (115 files for full test, 109 for miniruby).
- [21 October 2025]: Created `extract_variables.sh` script to extract key build variables (CFLAGS, XCFLAGS, DLDFLAGS, SOLIBS) from `make_n_test.log` to `analysis_logs/variables.txt`.
- [21 October 2025]: Created `extract_includes.sh` script to parse includes from `variables.txt` to `analysis_logs/includes.txt`.
- [21 October 2025]: Verified extraction scripts work and produce clean outputs; deleted unused `extract_build_flags.sh`.
- [21 October 2025]: Drafted `BUILD.mk.new` with extracted data, dynamic source reading, and Cosmopolitan-compatible linking; fixed include paths and added missing `regenc.h` to INCS.
- [22 October 2025]: **[Claude Code Analysis]** Compared `source_files_sorted.txt` (115 files from `make -n test`) with `source_files_from_backup_sorted.txt` (146 files from current BUILD.mk). Current BUILD.mk is MORE complete than reference build, including all extensions (ripper, io/console, io/wait, monitor, pathname, stringio), 21 transcoders for IRB, and custom initialization files.

## Source File Comparison Analysis (Added by Claude Code - 22 October 2025)

### Current BUILD.mk vs Reference Build

**Current BUILD.mk (146 files):**
- Full Ruby core (76 files including loadpath.c, localeinit.c, dmyext.c, encinit.c)
- All encodings (5 files: ascii, encdb, unicode, us_ascii, utf_8)
- Complete transcoder set (22 files: big5, chinese, japanese, korean, emoji*, single_byte, etc.)
- Prism parser (25 files)
- Extensions for IRB (10 files):
  - ripper (5): ripper.c, ripper_init.c, eventids1.c, eventids2.c, eventids2table.c
  - io/console, io/wait, monitor, pathname, stringio
- Portability shims (3 files: addr2line.c, dladdr.c, setproctitle.c)
- Entry points (2 files: ruby.main.c, irb.main.c)
- Coroutine support (1 file: Context.S)

**Reference Build from `make -n test` (115 files):**
- Ruby core with miniinit.c stubs
- Minimal encodings (5 files + newline transcoder only)
- Prism parser
- No extensions
- Includes rjit.c/rjit_c.c (JIT compiler - not needed for Cosmopolitan)
- Uses dmydln.c, dmyenc.c (dummy implementations)

**Key Differences:**
- ✅ **We have MORE**: 21 additional transcoders, 6 extensions, custom init files
- ⚠️ **We removed**: miniinit.c (replaced with loadpath.c + localeinit.c), rjit.c/rjit_c.c (JIT not needed), dmydln.c/dmyenc.c (replaced with dln.c/encinit.c)
- 🎯 **For miniruby**: Should use ~109 files (from `source_files_miniruby_sorted.txt`)

### Variables Analysis from variables.txt

**Useful compiler flags to consider adding:**
- `-O3 -fno-fast-math` (optimization)
- `-fno-strict-overflow -fvisibility=hidden` (security/optimization)
- `-Wno-unused-parameter -Wmisleading-indentation` (suppress noise)
- `-fexcess-precision=standard` (floating point consistency)

**Libraries confirmed (SOLIBS):**
- `-lz -lrt -ldl -lcrypt -lm -lpthread` (all mapped to Cosmopolitan DIRECTDEPS)

**Include paths (already implemented):**
- `-I. -I./include -I./prism -I./enc/unicode/15.0.0` ✅

**Linker flags (DLDFLAGS):**
- `-Wl,--compress-debug-sections=zlib` (could reduce binary size)
- `-pie` (position independent executable - Cosmopolitan handles differently)

### Recommendations

1. **Create miniruby target**: Use 109-file subset for faster builds and testing
2. **Add socket extension**: Required for network functionality
3. **Consider optimization flags**: `-O3 -fno-fast-math` for performance
4. **Verify warning flags**: Add useful `-Wno-*` flags to reduce noise

## Implementation Complete (22 October 2025 - Claude Code)

### Changes Made

**1. Added Socket Extension (18 C files)**
- Added all socket source files to BUILD.mk:
  - ancdata.c, basicsocket.c, constants.c, constdefs.c
  - getaddrinfo.c, getnameinfo.c, ifaddr.c, init.c
  - ipsocket.c, option.c, raddrinfo.c, socket.c
  - sockssocket.c, tcpserver.c, tcpsocket.c, udpsocket.c
  - unixserver.c, unixsocket.c
- Added `CALL(socket);` to `third_party/ruby-port-3.4.7/inits.c`
- Added `rb_provide("socket.so");` to `ext/socket/socket.c` to mark as statically linked
- Total source files now: **94 files** (76 core + 18 socket)

**2. Created miniruby Target**
- Created `third_party/ruby/miniruby.main.c` - minimal Ruby entry point
- Added miniruby to THIRD_PARTY_RUBY_COMS
- Added miniruby.pkg to THIRD_PARTY_RUBY_CHECKS
- Created full build target with DIRECTDEPS and linking rules
- miniruby uses same library as ruby/irb but with simpler main()
- Purpose: Faster startup for basic scripting and testing

**3. BUILD.mk Structure**
Now supports three binaries from one library:
- **miniruby**: Lean Ruby for quick scripts (minimal overhead)
- **ruby**: Full Ruby with all extensions
- **irb**: Interactive Ruby shell with IRB libraries

All three share the same `third_party/ruby/ruby.a` library containing:
- 76 Ruby core files
- 22 transcoders (for encoding conversion)
- 5 encodings (ascii, utf-8, etc.)
- 25 Prism parser files
- 28 extension files (ripper:5, io/console:1, io/wait:1, monitor:1, pathname:1, stringio:1, socket:18)
- 3 portability shims
- 1 coroutine assembly file

**Total library size**: 164 source files (163 C + 1 S)

### Build Commands

```bash
# Build all three binaries
make -j24 o//third_party/ruby

# Build individually
make -j24 o//third_party/ruby/miniruby  # Lean Ruby
make -j24 o//third_party/ruby/ruby      # Full Ruby
make -j24 o//third_party/ruby/irb       # Interactive shell
```

### Testing Socket Extension

```bash
o//third_party/ruby/ruby -e "require 'socket'; puts Socket.gethostname"
o//third_party/ruby/ruby -e "require 'socket'; p TCPSocket"
```
## Socket Extension Integration (22 October 2025 - Claude Code)

### Challenge
The socket extension uses Cosmopolitan's runtime constants (extern const) in switch statements, which require compile-time constants.

### Solution
Created compatibility layer similar to errno_wrapper.h pattern:

1. **extconf.h** - Configures which types/functions Cosmopolitan provides:
   - Socket types: sockaddr_*, addrinfo, socklen_t, ip_mreq, ipv6_mreq
   - Socket functions: All standard POSIX socket functions
   - Message structures: msghdr with control message support
   - Disabled: SA_LEN (Linux doesn't have it), AF_PACKET (no sockaddr_ll)

2. **socket_constants.h** - Compile-time constant wrapper:
   - Undefines Cosmopolitan's runtime constants
   - Redefines them as Linux compile-time values for switch statements
   - Covers: SOL_*, SO_*, SCM_*, AF_*, IP_*, IPV6_* constants
   - Provides struct ucred for SCM_CREDENTIALS
   - Included at END of rubysocket.h (after all system headers)

3. **Removed incompatible files**:
   - constdefs.c (included by constants.c, not compiled separately)  
   - getaddrinfo.c / getnameinfo.c (Cosmopolitan provides these)

### Files Modified
- BUILD.mk: Added 15 socket .c files
- third_party/ruby/ext/socket/extconf.h: Created
- third_party/ruby/ext/socket/socket_constants.h: Created
- third_party/ruby/ext/socket/rubysocket.h: Include socket_constants.h at end
- third_party/ruby/ext/socket/constdefs.c: Added rubysocket.h include
- third_party/ruby-port-3.4.7/inits.c: Added CALL(socket);
- third_party/ruby-port-3.4.7/ext/socket/socket.c: Added rb_provide("socket.so");

### Testing
```bash
o//third_party/ruby/ruby -e "require 'socket'; puts Socket.gethostname"  # ✅ Works
o//third_party/ruby/ruby -e "require 'socket'; p TCPSocket"              # ✅ Works
o//third_party/ruby/ruby -e "require 'socket'; puts Socket::Constants.constants.size"  # ✅ 300+ constants
```

### Known Limitations
- AF_PACKET disabled (Cosmopolitan lacks struct sockaddr_ll)
- Some IPv6 constants may not export to Ruby namespace (compile-time only)
- Sufficient for basic socket operations and gem installation

