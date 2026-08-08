# CosmoRuby

**One file. It's Ruby. It runs on Linux, Windows, macOS and the BSDs without
being installed.**

`ruby.com` is a complete Ruby 4.0.6 interpreter — VM, standard library, default
gems, RubyGems, IRB and a set of statically linked C extensions — built as a
[Cosmopolitan](https://justine.lol/cosmopolitan/index.html) *actually portable
executable*. There is no installer, no `PATH` surgery, no runtime, no DLLs, no
`.so` files and no stdlib directory to ship alongside it. You download roughly
20 MB, mark it executable, and run it.

This repository is a fork of [igravious/cosmoruby](https://github.com/igravious/cosmoruby),
which is itself a fork of [jart/cosmopolitan](https://github.com/jart/cosmopolitan)
with Ruby vendored into `third_party/` and built by cosmopolitan's own build
system. All of the heavy lifting is theirs.

## Download

Latest release assets — <https://github.com/Largo/cosmoruby/releases/latest>
(tag `v4.0.6-cosmo1`):

| File | What it is | Size |
| --- | --- | ---: |
| [`ruby.com`](https://github.com/Largo/cosmoruby/releases/latest/download/ruby.com) | the Ruby interpreter | 21,225,070 B (20.2 MiB) |
| [`irb.com`](https://github.com/Largo/cosmoruby/releases/latest/download/irb.com) | the same binary, starting IRB | 21,225,070 B (20.2 MiB) |
| [`miniruby.com`](https://github.com/Largo/cosmoruby/releases/latest/download/miniruby.com) | minimal interpreter, no C extensions | 18,738,813 B (17.9 MiB) |
| [`SHA256SUMS`](https://github.com/Largo/cosmoruby/releases/latest/download/SHA256SUMS) | checksums for the three binaries | — |

Most people only want `ruby.com`.

**Architecture.** The `v4.0.6-cosmo1` assets linked above are **x86-64 only** —
they will not run natively on Apple Silicon, an ARM Chromebook, a Raspberry Pi
or Windows-on-ARM. The tree now builds **fat x86-64 + aarch64** APEs again
(as igravious's older `v1.3.0` release did): `FAT=1
.github/scripts/build-cosmoruby.sh`, and CI produces them on every push. The
next tagged release will be fat; until then, build one yourself or take the CI
artifact. See "Fat (x86-64 + aarch64) binaries" in `BUILDING.md`.

A fat `ruby.com` is about 33 MB instead of 21 MB — the aarch64 half is an
entire second copy of the interpreter.

## 30-second quickstart

### Linux, macOS, FreeBSD/OpenBSD/NetBSD

```sh
curl -L -o ruby.com https://github.com/Largo/cosmoruby/releases/latest/download/ruby.com
chmod +x ruby.com
./ruby.com -e 'puts "hello from #{RUBY_DESCRIPTION}"'
./ruby.com script.rb
```

```
hello from ruby 4.0.6 (2026-07-14) +PRISM +MIMALLOC [x86_64-cosmo]
```

If your shell refuses to run it (`zsh` before 5.9, old `fish`, Python's
`subprocess`), use `sh ./ruby.com ...`, or register the APE format with
`binfmt_misc` — see [Platform Notes](#platform-notes) below. On WSL run
`sudo sh -c "echo -1 > /proc/sys/fs/binfmt_misc/WSLInterop"` first, otherwise
WSL hands the file to the Windows loader.

### Windows

Download it and run it. **No renaming is required** — `.COM` is already an
executable extension on Windows, and the file is a real PE binary.

```powershell
# PowerShell
curl.exe -L -o ruby.com https://github.com/Largo/cosmoruby/releases/latest/download/ruby.com
.\ruby.com -e "puts RUBY_DESCRIPTION"
.\ruby.com script.rb
```

```bat
REM cmd.exe
ruby.com -e "puts RUBY_DESCRIPTION"
```

Verified on Windows 11 Pro (build 26200) with PowerShell 5.1 and `cmd.exe`:
runs from `C:\`, from `%USERPROFILE%\Downloads`, from a path containing spaces
(`C:\Program Files\CosmoRuby\ruby.com`), and with the "downloaded from the
internet" mark (`Zone.Identifier`) attached. Renaming it to `ruby.exe` also
works and behaves identically — do that only if some tool of yours insists on
`.exe`. Dropping it on your `PATH` lets you type plain `ruby`, because `.COM`
is in the default `PATHEXT`.

The binary is unsigned, so launching it by double-clicking in Explorer may
raise a SmartScreen prompt. Running it from a terminal, which is what you want
anyway, does not.

#### Exit codes on Windows are shifted left by 8

```powershell
PS C:\> .\ruby.com -e "exit 7"
PS C:\> $LASTEXITCODE
1792                      # 7 * 256
```

`%ERRORLEVEL%` under `cmd.exe` reports the same 1792. `exit 0` correctly gives
0. This is a pre-existing quirk of how cosmopolitan APEs report status to
Windows — igravious's Ruby 4.0.0 release binary behaves identically — so if you
script around a bare `ruby.com` on Windows, compare `$LASTEXITCODE / 256`.
Applications packaged with [ocran](#packaging-your-app-into-one-file) report
their status correctly and are not affected.

## What's inside

```
$ ./ruby.com --version
ruby 4.0.6 (2026-07-14) +PRISM +MIMALLOC [x86_64-cosmo]
```

- **Ruby 4.0.6**, Prism parser, mimalloc allocator.
- **The full standard library and 80 default gems**, embedded in the binary as
  a ZIP archive and loaded from `/zip/lib/ruby/4.0.0`. Nothing is unpacked to
  disk. `env -i ./ruby.com script.rb` from an empty directory works.
- **RubyGems 4.0.16** (`./ruby.com -S gem --version`) and **IRB 1.16.0**.
- **Statically linked C extensions** (there is no `dlopen` here, so everything
  is linked in at build time and pre-registered in `$LOADED_FEATURES`):
  `json`, `psych`/`yaml`, `zlib`, `digest` (+`md5`, `sha1`, `sha2`),
  `stringio`, `strscan`, `socket`, `sqlite3`, `date`, `etc`, `fcntl`,
  `io/console`, `io/nonblock`, `io/wait`, `ripper`, `objspace`, `monitor`,
  `continuation`, `coverage`, `rbconfig/sizeof`, and cosmopolitan's `mbedtls`.
- **`sqlite3` (gem 2.9.5)** is built in — `require "sqlite3"` just works, on
  Linux *and* on Windows, with no `.so` anywhere. See the limitations below.
- **YJIT** — pass `--yjit`. **Linux x86-64 only**; see below.

### `openssl` is an MbedTLS-backed shim, not Ruby's OpenSSL extension

`require "openssl"` succeeds, and `net/http` talks HTTPS over it — a plain
`Net::HTTP.get_response(URI("https://…"))` returns 200 on Linux. But the
implementation is a ~400-line compatibility shim (`/zip/lib/ruby/4.0.0/openssl.rb`)
over cosmopolitan's MbedTLS, not the real `openssl` C extension. It provides
only `OpenSSL::Digest`, `OpenSSL::PKey`, `OpenSSL::X509`, `OpenSSL::SSL` and
`OpenSSL::OpenSSLError`. `OpenSSL::VERSION`, `OpenSSL::Cipher` and
`OpenSSL::HMAC` do not exist. Anything doing real cryptography with the OpenSSL
API will need checking.

### YJIT is Linux-only, and the banner does not admit it

The YJIT compiler is Rust code built for `x86_64-unknown-linux-gnu` and is only
initialised when the APE is running on Linux.

| | Linux x86-64 | Windows x86-64 | any aarch64 |
| --- | --- | --- | --- |
| `RubyVM::YJIT.enabled?` | `true` | `false` | `false` |
| `RUBY_DESCRIPTION` | `+YJIT` | `+YJIT` (misleading) | `+YJIT` (misleading) |

Passing `--yjit` anywhere else is harmless — it is accepted and does nothing.
Do not trust `RUBY_DESCRIPTION`; trust `RubyVM::YJIT.enabled?`. On the aarch64
half the Rust staticlib is not even linked in (`yjit/BUILD.mk` disables it for
`ARCH=aarch64`).

## What is *not* supported

- **No native gems.** There is no `dlopen` in an APE, so any gem with a C
  extension you have not compiled *into* this binary cannot be used. Pure-Ruby
  gems are fine. Adding a native gem means adding it to this repo's build —
  `PORTING-NOTES.md` has a step-by-step recipe (that's how `sqlite3` got here).
- **`Kernel#system`, backticks, `Process.spawn` and `IO.popen` cannot launch
  native Windows programs.** On Windows, `Process.spawn("C:/Windows/System32/cmd.exe", "/c", "exit 3")`
  fails (`$?.exitstatus` is `nil`, `system` returns `false`, backticks return
  `""`). Launching *another APE* from an APE does work
  (`Process.spawn("C:/ruby.com","-e","exit 5")` → 5). Subprocesses work
  normally on Linux.
- **TCP sockets do not work on Windows.** `require "socket"` loads, socket
  creation and DNS work, but `bind()` and `connect()` fail:
  `TCPServer.new("127.0.0.1", 0)` raises `Errno::EAFNOSUPPORT` and
  `TCPSocket`/`Net::HTTP` raise `Errno::EINVAL`. Sockets work correctly on
  Linux. This is pre-existing — igravious's Ruby 4.0.0 release binary fails the
  same way — and is a cosmopolitan/port-level bug, not something introduced
  here. No network client or server code will run on Windows.
- **32-bit anything, BIOS/metal.** Not tested, not claimed.

### `sqlite3` limitations

The extension links cosmopolitan's `libsqlite3.a`, which is compiled with a
particular set of `OMIT` flags, so:

- **SQLite is 3.40.0**, not the 3.53.x the gem normally bundles.
- `SQLite3::Database#load_extension` / `#enable_load_extension` are **not
  defined** (`SQLITE_OMIT_LOAD_EXTENSION`) — loadable SQLite extensions are
  `.so` files and could not be used from an APE regardless.
- `SQLite3::Statement#database_name` is **not defined** (no
  `SQLITE_ENABLE_COLUMN_METADATA`).
- **No FTS3/4/5, RTREE or GEOPOLY.** JSON1, math functions, session/preupdate
  hooks and `sqlite3_deserialize` *are* available.
- UTF-16 input is transcoded to UTF-8 rather than passed through
  (`SQLITE_OMIT_UTF16`); no observable behaviour difference.
- `SQLITE_OMIT_GET_TABLE` (unused by the gem).

Everything else works: in-memory and file-backed databases, positional and
named binds, prepared-statement reuse, transactions and rollback, BLOB and
UTF-8 round-trips, read-only handles, custom SQL functions and aggregates,
`SQLException` mapping, `busy_timeout=` and pragmas. Exercised by
`third_party/ruby/cosmo_tests/test_sqlite3.rb`, which passes 5/5 on Linux and
5/5 on Windows 11.

## Platform support, honestly

| Platform | Status |
| --- | --- |
| Linux x86-64 | **Verified.** 14/14 smoke checks, sqlite3 5/5, `env -i` from an empty dir, YJIT on. |
| Windows 11 x86-64 | **Verified.** Smoke script, sqlite3 5/5, `irb.com`, `miniruby.com`. Caveats above (sockets, subprocesses, exit-code shift). |
| macOS x86-64 | **Untested locally**; covered by the `macos-15-intel` CI job. Cosmopolitan APEs are designed to run on macOS 23.1.0+ and nothing in this build is Linux-specific outside YJIT. |
| FreeBSD / OpenBSD 7.3+ / NetBSD, x86-64 | **Untested**, same reasoning as macOS. |
| Linux aarch64 (fat builds) | **Verified against the fat binary** under `qemu-user`: 14/14 smoke checks, 30/30 `ci_smoke.rb`, sqlite3 5/5, `env -i`, `irb`/`miniruby`. `RUBY_PLATFORM` is `aarch64-cosmo`. No YJIT (see above). CI additionally runs the same acceptance script on GitHub's real `ubuntu-24.04-arm` runner, as a blocking job. |
| macOS aarch64 / Apple Silicon (fat builds) | Covered by the `macos-latest` CI job; the fat APE carries the `ape-m1` loader. |
| Windows-on-ARM | **Untested / not claimed.** There is a non-blocking `windows-11-arm` CI job and nothing more. |
| Anything aarch64, using the **x86-64-only** `v4.0.6-cosmo1` assets | **Not supported** — build fat, or wait for the next release. |

If you run it somewhere untested, please open an issue either way.

## Packaging your app into one file

[Largo/ocran](https://github.com/Largo/ocran) can bundle *your* Ruby
application together with this interpreter into a single portable `.com`:

```sh
ruby exe/ocran myapp.rb --cosmo /path/to/cosmocc --cosmo-ruby ./ruby.com \
     --output myapp.com
```

The `--cosmo-ruby` flag arrived in [ocran PR #50](https://github.com/Largo/ocran/pull/50)
(open at time of writing). The resulting binary carries your app, its
pure-Ruby gems and this whole interpreter; it runs under `env -i` from an empty
directory on Linux and on Windows, and it reports your script's exit status
correctly on both. Gems that the payload already provides (`json`, `sqlite3`, …)
are detected and skipped instead of being packed twice.

## Building it yourself

See [`BUILDING.md`](BUILDING.md) for a start-to-finish recipe from a clean
checkout, and [`PORTING-NOTES.md`](PORTING-NOTES.md) for the full engineering
log: every breakage found in the fork, how it was diagnosed, the Windows
verification procedure, and a recipe for adding another native-extension gem.

Quick verification of a build you made:

```sh
sh third_party/ruby/cosmo_tests/smoke_test.sh o/third_party/ruby/ruby.com
env -i o/third_party/ruby/ruby.com third_party/ruby/cosmo_tests/test_sqlite3.rb
sh third_party/ruby/cosmo_tests/win_smoke.sh o/third_party/ruby/ruby.com   # needs a Windows box
```

## Credits and licence

- [Justine Tunney](https://github.com/jart) and the Cosmopolitan Libc project —
  the APE format, the libc, the toolchain and the build system this is all
  built on.
- [igravious](https://github.com/igravious) — the CosmoRuby port itself:
  vendoring Ruby into the cosmopolitan monorepo, the static-extension build
  mode, the `/zip` stdlib packaging, YJIT, and releases up to v1.3.0.
- This fork adds an upstream sync, Ruby 4.0.6, the built-in `sqlite3`
  extension, a Windows crash fix, and the fixes needed to build from a clean
  checkout.

Cosmopolitan is ISC-licensed (see [`LICENSE`](LICENSE)); Ruby is under the Ruby
licence / BSD-2-Clause; bundled gems carry their own licences.

---

![Cosmopolitan Honeybadger](usr/share/img/honeybadger.png)

[![build](https://github.com/jart/cosmopolitan/actions/workflows/build.yml/badge.svg)](https://github.com/jart/cosmopolitan/actions/workflows/build.yml)
[![CosmoRuby CI](https://github.com/Largo/cosmoruby/actions/workflows/cosmoruby-ci.yml/badge.svg?branch=main)](https://github.com/Largo/cosmoruby/actions/workflows/cosmoruby-ci.yml)
# Cosmopolitan

*(Everything below this line is the upstream jart/cosmopolitan README, kept
verbatim. CosmoRuby is built by this repository's own build system, so the
instructions below apply to the C toolchain, not to `ruby.com`.)*

[Cosmopolitan Libc](https://justine.lol/cosmopolitan/index.html) makes C/C++
a build-once run-anywhere language, like Java, except it doesn't need an
interpreter or virtual machine. Instead, it reconfigures stock GCC and
Clang to output a POSIX-approved polyglot format that runs natively on
Linux + Mac + Windows + FreeBSD + OpenBSD 7.3 + NetBSD + BIOS with the
best possible performance and the tiniest footprint imaginable.

## Background

For an introduction to this project, please read the [actually portable
executable](https://justine.lol/ape.html) blog post and [cosmopolitan
libc](https://justine.lol/cosmopolitan/index.html) website. We also have
[API
documentation](https://justine.lol/cosmopolitan/documentation.html).

## Getting Started

You can start by obtaining a release of our `cosmocc` compiler from
<https://cosmo.zip/pub/cosmocc/>.

```sh
mkdir -p cosmocc
cd cosmocc
wget https://cosmo.zip/pub/cosmocc/cosmocc.zip
unzip cosmocc.zip
```

Here's an example program we can write:

```c
// hello.c
#include <stdio.h>

int main() {
  printf("hello world\n");
}
```

It can be compiled as follows:

```sh
cosmocc -o hello hello.c
./hello
```

The Cosmopolitan Libc runtime links some heavyweight troubleshooting
features by default, which are very useful for developers and admins.
Here's how you can log system calls:

```sh
./hello --strace
```

Here's how you can get a much more verbose log of function calls:

```sh
./hello --ftrace
```

You can use the Cosmopolitan's toolchain to build conventional open
source projects which use autotools. This strategy normally works:

```sh
export CC=x86_64-unknown-cosmo-cc
export CXX=x86_64-unknown-cosmo-c++
./configure --prefix=/opt/cosmos/x86_64
make -j
make install
```

## Cosmopolitan Source Builds

Cosmopolitan can be compiled from source on any of our supported
platforms. The Makefile will download cosmocc automatically.

It's recommended that you install a systemwide APE Loader. This command
requires `sudo` access to copy the `ape` command to a system folder and
register with binfmt_misc on Linux, for even more performance.

```sh
ape/apeinstall.sh
```

You can now build the mono repo with any modern version of GNU Make. To
bootstrap your build, you can install Cosmopolitan Make from this site:

https://cosmo.zip/pub/cosmos/bin/make

E.g.:

```sh
curl -LO https://cosmo.zip/pub/cosmos/bin/make
./make -j8
o//examples/hello
```

After you've built the repo once, you can also use the make from your
cosmocc at `.cosmocc/current/bin/make`. You might even prefer to alias
make to `$COSMO/.cosmocc/current/bin/make`.

Since the Cosmopolitan repository is very large, you might only want to
build one particular thing. Here's an example of a target that can be
compiled relatively quickly, which is a simple POSIX test that only
depends on core LIBC packages.

```sh
rm -rf o//libc o//test
.cosmocc/current/bin/make o//test/posix/signal_test
o//test/posix/signal_test
```

Sometimes it's desirable to build a subset of targets, without having to
list out each individual one. For example if you wanted to build and run
all the unit tests in the `TEST_POSIX` package, you could say:

```sh
.cosmocc/current/bin/make o//test/posix
```

Cosmopolitan provides a variety of build modes. For example, if you want
really tiny binaries (as small as 12kb in size) then you'd say:

```sh
.cosmocc/current/bin/make m=tiny
```

You can furthermore cut out the bloat of other operating systems, and
have Cosmopolitan become much more similar to Musl Libc.

```sh
.cosmocc/current/bin/make m=tinylinux
```

For further details, see [//build/config.mk](build/config.mk).

## Debugging

To print a log of system calls to stderr:

```sh
cosmocc -o hello hello.c
./hello --strace
```

To print a log of function calls to stderr:

```sh
cosmocc -o hello hello.c
./hello --ftrace
```

Both strace and ftrace use the unbreakable kprintf() facility, which is
able to be sent to a file by setting an environment variable.

```sh
export KPRINTF_LOG=log
./hello --strace
```

## GDB

Here's the recommended `~/.gdbinit` config:

```gdb
set host-charset UTF-8
set target-charset UTF-8
set target-wide-charset UTF-8
set osabi none
set complaints 0
set confirm off
set history save on
set history filename ~/.gdb_history
define asm
  layout asm
  layout reg
end
define src
  layout src
  layout reg
end
src
```

You normally run the `.dbg` file under gdb. If you need to debug the
`` file itself, then you can load the debug symbols independently as

```sh
gdb foo -ex 'add-symbol-file foo.dbg 0x401000'
```

## Platform Notes

### Shells

If you use zsh and have trouble running APE programs try `sh -c ./prog`
or simply upgrade to zsh 5.9+ (since we patched it two years ago). The
same is the case for Python `subprocess`, old versions of fish, etc.

### Linux

Some Linux systems are configured to launch MZ executables under WINE.
Other distros configure their stock installs so that APE programs will
print "run-detectors: unable to find an interpreter". For example:

```sh
jart@ubuntu:~$ wget https://cosmo.zip/pub/cosmos/bin/dash
jart@ubuntu:~$ chmod +x dash
jart@ubuntu:~$ ./dash
run-detectors: unable to find an interpreter for ./dash
```

You can fix that by registering APE with `binfmt_misc`:

```sh
sudo wget -O /usr/bin/ape https://cosmo.zip/pub/cosmos/bin/ape-$(uname -m).elf
sudo chmod +x /usr/bin/ape
sudo sh -c "echo ':APE:M::MZqFpD::/usr/bin/ape:' >/proc/sys/fs/binfmt_misc/register"
sudo sh -c "echo ':APE-jart:M::jartsr::/usr/bin/ape:' >/proc/sys/fs/binfmt_misc/register"
```

You should be good now. APE will not only work, it'll launch executables
400µs faster now too. However if things still didn't work out, it's also
possible to disable `binfmt_misc` as follows:

```sh
sudo sh -c 'echo -1 > /proc/sys/fs/binfmt_misc/cli'     # remove Ubuntu's MZ interpreter
sudo sh -c 'echo -1 > /proc/sys/fs/binfmt_misc/status'  # remove ALL binfmt_misc entries
```

### WSL

It's normally unsafe to use APE in a WSL environment, because it tries
to run MZ executables as WIN32 binaries within the WSL environment. In
order to make it safe to use Cosmopolitan software on WSL, run this:

```sh
sudo sh -c "echo -1 > /proc/sys/fs/binfmt_misc/WSLInterop"
```

## Discord Chatroom

The Cosmopolitan development team collaborates on the Redbean Discord
server. You're welcome to join us! <https://discord.gg/FwAVVu7eJ4>

## Support Vector

| Platform       | Min Version    | Circa |
| :---           | ---:           | ---:  |
| AMD            | K8             | 2003  |
| Intel          | Core           | 2006  |
| Linux          | 2.6.18         | 2007  |
| Windows        | 8 [1]          | 2012  |
| Darwin (macOS) | 23.1.0+        | 2023  |
| OpenBSD        | 7.3 or earlier | 2023  |
| FreeBSD        | 13             | 2020  |
| NetBSD         | 9.2            | 2021  |

[1] See our [vista branch](https://github.com/jart/cosmopolitan/tree/vista)
    for a community supported version of Cosmopolitan that works on Windows
    Vista and Windows 7.

## Special Thanks

Funding for this project is crowdsourced using
[GitHub Sponsors](https://github.com/sponsors/jart) and
[Patreon](https://www.patreon.com/jart). Your support is what makes this
project possible. Thank you! We'd also like to give special thanks to
the following groups and individuals:

- [Joe Drumgoole](https://github.com/jdrumgoole)
- [Rob Figueiredo](https://github.com/robfig)
- [Wasmer](https://wasmer.io/)

For publicly sponsoring our work at the highest tier.
