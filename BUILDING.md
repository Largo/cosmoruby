# Building CosmoRuby from source

This builds `ruby.com`, `irb.com` and `miniruby.com` — the single-file Ruby
APEs described in [`README.md`](README.md) — from a clean checkout of this
repository's `main` branch.

The recipe below was executed start to finish on 2026-08-08 on Debian 13
(trixie) amd64, from an emptied `o/` tree with the bootstrap products deleted.
It took **≈2 minutes wall on 8 cores** in that state. The very first build on a
brand-new clone is longer, because it also downloads the ~390 MB cosmocc
toolchain.

`PORTING-NOTES.md` is the long-form engineering log behind this file: it
records every breakage that had to be fixed to make a clean checkout buildable
at all, with symptoms and root causes. If something here goes wrong, look
there first.

## What you are actually building

This repo is **not** a "ruby + cosmopolitan amalgamation" project. It is the
`jart/cosmopolitan` monorepo with Ruby vendored into
`third_party/ruby-wip-4.0.6/` (reached through the `third_party/ruby` symlink)
and compiled by cosmopolitan's own `BUILD.mk` system. So you are building a
chunk of cosmopolitan libc, the tooling, YJIT's Rust staticlib and Ruby, all in
one `make`.

**The `third_party/ruby` symlink target is load-bearing.** `ruby.env.mk`
derives `COSMO_RUBY_VERSION` from the directory name, so renaming
`ruby-wip-4.0.6` breaks the build in confusing ways.

## Prerequisites

| Requirement | Why | Debian package |
| --- | --- | --- |
| GNU Make ≥ 4 | the build system (verified with 4.4.1) | `make` |
| `cargo` + `rustc` | YJIT is Rust and is **hard-enabled** in the committed `config.h` (`USE_YJIT 1`) — you cannot simply turn it off. `Cargo.toml` declares 1.58 minimum; 1.85 works. | `cargo rustc` |
| Info-ZIP `zip` | `assemble_stdlib.sh` builds the embedded `/zip` stdlib archive | `zip` |
| Network access | the top-level `Makefile` auto-downloads **cosmocc 3.9.2** (sha256-pinned) into `.cosmocc/3.9.2` on first `make`, ~390 MB | — |
| An existing CosmoRuby `ruby.com` | codegen needs a Ruby to run; see below | — |
| ~5 GB free disk | `o/` reaches ~1.2 GB, `.cosmocc/` ~1.2 GB | — |

```sh
sudo apt-get install -y make cargo rustc zip
```

The standalone modern cosmocc you may have at `/opt/cosmocc` or similar is
**not** used by this build system; the pinned `.cosmocc/3.9.2` is.

### The bootstrap Ruby

`ruby.env.mk` insists that the host Ruby is exactly the vendored version
(4.0.6) **unless** you pass `COSMO_RUBY=`, which points it at a prebuilt
CosmoRuby APE instead. That is much easier than installing Ruby 4.0.6 on your
host, and it is what the recipe below does:

```sh
mkdir -p ~/tools/cosmoruby-release
gh release download v1.3.0 -R igravious/cosmoruby -p ruby.com \
   -D ~/tools/cosmoruby-release
chmod +x ~/tools/cosmoruby-release/ruby.com
export COSMO_RUBY=$HOME/tools/cosmoruby-release/ruby.com
export HOST_RUBY=$COSMO_RUBY
```

The **4.0.0** binary from igravious's `v1.3.0` release bootstraps the **4.0.6**
build fine — the version check is skipped when `COSMO_RUBY` is set, and the
codegen scripts are version-agnostic. Once you have built your own `ruby.com`
you can bootstrap subsequent builds with that instead.

## The build

```sh
export COSMO_RUBY=$HOME/tools/cosmoruby-release/ruby.com
export HOST_RUBY=$COSMO_RUBY
export CARGO=/usr/bin/cargo

# 1. regenerate the 395 mkdeps shim headers (see gotcha 2)
bash third_party/ruby/gen_ruby_shims.sh

# 2. configure -- ALWAYS with the mode flag (see gotcha 1)
bash third_party/ruby/cosmo_configure.sh --with-static-linked-ext

# 3. bootstrap: builds build/bootstrap/{mtdeps,automate_mkdeps}
bash third_party/ruby/cosmo_configure.sh --bootstrap

# 4. re-assert the mode -- step 3 silently reset it to "plugin" (gotcha 1)
bash third_party/ruby/cosmo_configure.sh --with-static-linked-ext

# 5. build the three interpreters
make -j"$(nproc)" COSMO_RUBY="$COSMO_RUBY" CARGO="$CARGO" \
     o//third_party/ruby/ruby \
     o//third_party/ruby/irb \
     o//third_party/ruby/miniruby

# 6. embed the stdlib -> the .com files
bash third_party/ruby/package_ruby.sh
```

Results:

```
o/third_party/ruby/ruby.com        21,225,070 B
o/third_party/ruby/irb.com         21,225,070 B
o/third_party/ruby/miniruby.com    18,738,813 B
```

Sizes vary by a byte or two between builds (ZIP metadata); the *unpackaged*
`o/third_party/ruby/ruby` is deterministic at **12,720,749** bytes for x86-64
on this branch. `head -c 6 ruby.com` must print `MZqFpD`.

## Verify

Do not skip this, and in particular do not skip Windows.

```sh
sh third_party/ruby/cosmo_tests/smoke_test.sh o/third_party/ruby/ruby.com
# expect: == RESULT: pass=14 fail=0 ==

mkdir /tmp/empty && cd /tmp/empty
env -i /path/to/o/third_party/ruby/ruby.com \
       /path/to/third_party/ruby/cosmo_tests/test_sqlite3.rb
# expect: RESULT: failures=0

sh third_party/ruby/cosmo_tests/win_smoke.sh o/third_party/ruby/ruby.com
# expect: the banner, JSON, Gem.default_dir, ... 42, RC=1792
```

`RC=1792` is `7 << 8`: Windows reports an APE's exit status shifted left by 8
bits. That is expected — see README.

**Linux green does not imply Windows boots.** A build that passed all 14 Linux
checks once crashed on 100% of Windows runs, because a Rust YJIT entry point
was called unguarded during VM init. `ruby.com --version` short-circuits before
that code runs, so it printed a perfectly correct banner throughout the entire
crashing period — **never use `--version` as the Windows smoke test.** Run a
script that requires a stdlib feature and touches the filesystem.

`third_party/ruby/cosmo_tests/win_smoke.sh` targets a local Vagrant Windows box
by default and is overridable with `WIN_HOST` / `WIN_USER` / `WIN_PORT` /
`WIN_KEY`.

## Gotchas that will bite you

### 1. `cosmo_configure.sh` silently resets the tree to plugin mode

Running `cosmo_configure.sh` with **no mode flag** — and `--bootstrap` counts —
rewrites `include/ruby/config.mode.h` and `lib/rbconfig.mode.rb` into *plugin*
mode, while the committed generated files are in *static* mode. The build then
either fails or produces a Ruby whose extensions are not linked in.

The `--bootstrap` log line that tells you it happened is easy to miss:

```
cosmo_configure: mode configuration complete (mode=plugin)
```

**Always pass `--with-static-linked-ext`, and re-run it after `--bootstrap`.**
`git status` should be clean afterwards; if `config.mode.h` or
`rbconfig.mode.rb` show up as modified, you are in the wrong mode.

### 2. `gen_ruby_shims.sh` when the file set changes

`third_party/ruby/ruby.deps.mk` lists 395 `ruby_shims/*.h` entries. These are
mkdeps shim files that were never committed to any branch, so a fresh checkout
cannot build without regenerating them:

```sh
bash third_party/ruby/gen_ruby_shims.sh
```

Re-run it **whenever the set of Ruby source files changes** (vendoring a new
Ruby, adding an extension). If you don't, `make` enters an infinite remake
loop, repeating

```
NOTE: deleting o//depend because of an unspecified prerequisite: ruby_shims/...
```

forever — 1300+ iterations were observed before this was understood. The
directory is deliberately untracked (`.git/info/exclude`).

One shim never resolves and is created empty:

```
gen_ruby_shims: no source found for
  ruby_shims/+home+groobiest+code+jart+cosmopolitan+o+third_party+ruby+generated+parse.h
gen_ruby_shims: wrote 395 shims (1 empty)
```

That is a leftover absolute path from the original author's machine baked into
`ruby.deps.mk`. Harmless; the message is expected.

### 3. `make` can exit 0 without linking anything

This is the single most dangerous thing about this build. `make` here regularly
stops halfway through compiling objects and **still exits 0**, leaving
`o/third_party/ruby/ruby` at its previous mtime and size. It also fails
transiently — `Error 90` from `tlscc` on random objects under `-j8`, or
`File.rename … rbconfig.rb.tmp (Errno::ENOENT)` from `ruby.codegen.mk` — both
of which go away on the next run.

**Never infer success from `$?`.** Loop `make` until the binary's size and
mtime stop changing:

```sh
prev=""
for i in $(seq 1 8); do
  make -j"$(nproc)" COSMO_RUBY="$COSMO_RUBY" CARGO="$CARGO" \
       o//third_party/ruby/ruby o//third_party/ruby/irb o//third_party/ruby/miniruby
  sig=$(stat -c '%s:%Y' o/third_party/ruby/ruby o/third_party/ruby/irb o/third_party/ruby/miniruby)
  [ "$sig" = "$prev" ] && break
  prev=$sig
done
stat -c '%n %s' o/third_party/ruby/ruby     # must be 12720749
```

Two passes is the normal case: pass 1 builds, pass 2 confirms nothing changed.
Only then run `package_ruby.sh`.

Related: when `make` fails deep inside `o//third_party/ruby/*` the top-level
invocation can also exit 0 while silently not linking, and an error on
`ruby.a.pkg` surfaces as a bare `Error 1`. To see the real message, re-run the
`package.ape` command from the make log by hand.

### 4. Interrupted builds leave untrustworthy state

Killing a cosmopolitan `make` mid-run can leave a stale package file that
believes an object exists when it does not. If you get strange packaging
errors — especially `.pkg: open failed with ENOENT` — `rm -rf o/` and start
over. Incremental state after an interrupt is not reliable.

### 5. `CARGO` must be passed explicitly

`yjit/BUILD.mk` looks up cargo with `$(shell command -v cargo)`, which comes up
empty under this repo's `SHELL = build/bootstrap/cocmd`. Pass
`CARGO=/usr/bin/cargo` on the make command line. You cannot work around it by
disabling YJIT: the committed `config.h` hard-codes `USE_YJIT 1`.

### 6. Any new YJIT Rust symbol must be gated on `IsLinux()`

The YJIT staticlib is built for `x86_64-unknown-linux-gnu` and only works on
Linux inside the APE. C code that calls into it must be guarded:

```c
#ifdef __COSMOPOLITAN__
    if (IsLinux())
#endif
        rb_yjit_init_builtin_cmes();
```

Upstream Ruby 4.0.6 added exactly such a call in `ruby_opt_init()` without a
guard, and every APE built from it segfaulted at VM init on Windows while
running perfectly on Linux. If you vendor a newer Ruby, audit new
`rb_yjit_*` call sites. Also note the `.pkg` symbol check: a Rust-implemented
function referenced from C needs a `__attribute__((weak))` no-op stub in
`yjit.c` (overridden at final link by `--whole-archive`), or the build fails
with `package.ape: undefined symbol`.

## Fat (x86-64 + aarch64) binaries

The manual recipe above builds x86-64 only. To get a **fat** APE — one file
containing both x86-64 and aarch64 machine code, which is what the releases
ship — use the build script with `FAT=1`:

```sh
export COSMO_RUBY=$HOME/tools/cosmoruby-release/ruby.com
FAT=1 JOBS=$(nproc) bash .github/scripts/build-cosmoruby.sh
```

It configures once, runs `make` for x86-64 and again with `m=aarch64`,
`apelink`s the two `.dbg` files together with the x86-64/aarch64 APE loaders
and `ape-m1.c`, then lets `package_ruby.sh` append the shared `/zip` stdlib.
Final artifacts land in `dist/` (and `releases/`) with a `SHA256SUMS`.

```
dist/ruby.com        32,975,939 B   (x86-64 only: 21,224,287 B)
dist/irb.com         32,975,907 B
dist/miniruby.com    27,895,330 B
```

≈2 min on 8 cores with libc already built (55–62 s per architecture, apelink
0.12 s, packaging ~12 s) — the fat build costs almost exactly one extra `make`.
`COSMO_RUBY=… ./bake -j8 <target>` does the same two-arch-plus-apelink dance
for any cosmopolitan target.

### Verifying the aarch64 half without ARM hardware

`build/bootstrap/ape.aarch64` is a static AArch64 APE loader that ships in this
repo, so `qemu-user` is enough to *run* the ARM half:

```sh
sudo apt-get install -y qemu-user-static
qemu-aarch64 build/bootstrap/ape.aarch64 dist/ruby.com -e 'puts RUBY_PLATFORM'
# => aarch64-cosmo
```

`qemu-aarch64` decodes only AArch64 instructions, so anything that runs really
is the ARM half. The negative control makes that concrete — point it at the
x86-64-only binary and the loader refuses:

```
ape error: o/third_party/ruby/ruby.com: couldn't find ELF header with AARCH64 machine type
```

This proves the *code* is correct. It does not prove the *platform*: for that,
`.github/workflows/cosmoruby-test.yml` runs the same acceptance script on
GitHub's `ubuntu-24.04-arm` and `macos-latest` (Apple Silicon) runners, which
are blocking jobs precisely because the artifact is fat. Both pass; the
`ubuntu-24.04-arm` job reports `aarch64-cosmo` and 30/30 on `ci_smoke.rb`.

### Gotcha: weak YJIT stubs are the real implementation on aarch64

`yjit/BUILD.mk` sets `RUBY_YJIT_ENABLED := 0` for `ARCH=aarch64` (the Rust
staticlib targets `x86_64-unknown-linux-gnu`). The `__attribute__((weak))`
stubs in `yjit.c` are therefore not linker placeholders on that half — they are
the whole implementation for the run. Each one must be a valid *runtime*
answer, not just a symbol. `rb_yjit_parse_option()` returning `false` made
`ruby.com --yjit` die with `invalid YJIT option ''` on ARM, because `ruby.c`
turns that into an `rb_raise`. If you add a stub, ask what it does when it is
the only implementation.

## Adding a native-extension gem

`PORTING-NOTES.md` has a complete worked recipe ("Recipe: adding a
native-extension gem to CosmoRuby"), written while adding `sqlite3`. The short
version: there is no `dlopen`, so you write a `BUILD.mk` for the extension,
hand-transcribe `extconf.rb`'s `have_func` results into `-D` flags that agree
with how cosmopolitan built the underlying C library, register the extension in
`ext/extinit.c` under the exact feature path its Ruby code `require`s, copy the
pure-Ruby half in `assemble_stdlib.sh`, and add a static gemspec so RubyGems
(and ocran) can see it.

One include-order trap worth repeating here: `ruby.deps.mk` computes
`THIRD_PARTY_RUBY_A_DEPS :=` with *immediate* expansion, so any third-party
package it names must be included **above** `-include local-includes.mk` in the
top-level `Makefile`, or the variable expands to the empty string and the build
dies with an unhelpful `.pkg: open failed with ENOENT`.

## Known build-level limitations

- **cosmocc is pinned to 3.9.2** and auto-downloaded. Newer standalone cosmocc
  releases are not used by this build system.
- **YJIT is x86-64/Linux only** and always will be until the Rust half is
  cross-compiled: `yjit/BUILD.mk` disables it for `ARCH=aarch64`, and the C
  call sites are gated on `IsLinux()`. `--yjit` is accepted everywhere and is
  simply inert where YJIT cannot run; check `RubyVM::YJIT.enabled?`, never the
  `+YJIT` in `RUBY_DESCRIPTION`.
