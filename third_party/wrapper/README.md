# ccc and rcc — Cosmopolitan Compiler Wrappers

Build APE (Actually Portable Executable) binaries without knowing the
Cosmopolitan build system. No Makefiles, no dependency resolution, no
APELINK macros — just:

```bash
ccc -o hello hello.c        # like gcc
rcc -o app app.rb            # like gcc but for Ruby
```

## What they do

1. Compile source for both x86_64 and aarch64
2. Run fixupobj on each object
3. Link against Cosmopolitan's static libraries (with --start-group
   to handle circular deps between archives)
4. Merge both architectures into a fat APE binary via apelink
5. Produce a single binary that runs on Linux, macOS, Windows, FreeBSD,
   OpenBSD, NetBSD — on both x86_64 and ARM64

## Prerequisites

The wrappers use pre-built artifacts from `o//`. You must build the base
system first:

```bash
make -j1                      # builds toolchain + all libraries
```

For rcc, you also need the Ruby build artifacts:

```bash
make -j1 o//third_party/ruby/rubyobj
make -j1 o//third_party/ruby/launch.o
```

## Usage

```
ccc [-o OUTPUT] [-v] [-l LIB] [--nostdlib] FILE...
rcc [-o OUTPUT] [-v] [-l LIB] [--nostdlib] FILE...

  -o OUTPUT       output binary name (default: a.out)
  -v              verbose — show commands being run
  -l LIB          link additional library (e.g. -l mbedtls)
  -l kitchen-sink link everything (like examples/BUILD.mk)
  --nostdlib      link nothing — you provide all -l flags
  -h              help
```

## Library tiers

**Default (ccc)** — minimal set for a basic C programme:
runtime, calls, stdio, str, mem, fmt, intrin, thread, log, proc, elf,
nexgen32e, sysv, compiler_rt, mimalloc, puff, essential NT stubs.

**Default (rcc)** — minimal + Ruby VM + extensions:
everything in minimal, plus ruby.a, launch.o, cosmo_plugin, libyaml,
mbedtls, https, http, regex, sed, tr, tz, getopt, nsync, zlib, xed,
libunwind, musl, gdtoa, and all Ruby C extension archives.

**`-l kitchen-sink`** — everything in the repo, like examples/BUILD.mk.

**`--nostdlib`** — nothing. Supply all archives yourself via `-l`.

## Limitations

- **Default mode only.** The wrappers link against `o//` (the default
  build mode). They do not support `MODE=dbg`, `MODE=opt`, `MODE=tiny`,
  etc. To use a different mode, build with `make MODE=foo` and then
  the wrappers would need to be pointed at `o/foo/` — which is not
  yet implemented.

- **No incremental builds.** Every invocation recompiles everything
  from scratch into a temp directory.

- **No automatic dependency resolution.** The real build system uses
  hand-curated DIRECTDEPS lists in BUILD.mk files, validated by
  package.ape. The wrappers use fixed library lists instead. If your
  programme needs something not in the default set, use `-l`.

- **Fat binaries require both architectures built.** If aarch64
  artifacts are not present in `o//aarch64/`, the wrappers fall back
  to x86_64-only output.

## Files

```
third_party/wrapper/
  common.sh   — shared functions (toolchain, compile, link, lib lists)
  ccc          — C compiler wrapper
  rcc          — Ruby compiler wrapper
```
