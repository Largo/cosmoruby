# CosmoRuby

**One file. It's Ruby. It runs on Linux, Windows, macOS and the BSDs without
being installed.**

`ruby.com` is a complete Ruby 4.0.6 interpreter — VM, standard library, default
gems, RubyGems, IRB and a set of statically linked C extensions — built as a
[Cosmopolitan](https://justine.lol/cosmopolitan/index.html) *actually portable
executable*. There is no installer, no `PATH` surgery, no runtime, no DLLs, no
`.so` files and no stdlib directory to ship alongside it. You download roughly
20 MB, mark it executable, and run it.

It is also an application packer. Because an APE is a valid ZIP archive,
`cp ruby.com myapp.com && zip myapp.com main.rb` produces a self-contained
`myapp.com` that runs your app — see
[Packaging your app into one file](#packaging-your-app-into-one-file).

This repository is a fork of [igravious/cosmoruby](https://github.com/igravious/cosmoruby),
which is itself a fork of [jart/cosmopolitan](https://github.com/jart/cosmopolitan)
with Ruby vendored into `third_party/` and built by cosmopolitan's own build
system. All of the heavy lifting is theirs.

## Download

Latest release assets — <https://github.com/Largo/cosmoruby/releases/latest>
(tag `v4.0.6-cosmo2`):

| File | What it is | Size |
| --- | --- | ---: |
| [`ruby.com`](https://github.com/Largo/cosmoruby/releases/latest/download/ruby.com) | the Ruby interpreter | 32,976,823 B (31.4 MiB) |
| [`irb.com`](https://github.com/Largo/cosmoruby/releases/latest/download/irb.com) | the same binary, starting IRB | 32,976,770 B (31.4 MiB) |
| [`miniruby.com`](https://github.com/Largo/cosmoruby/releases/latest/download/miniruby.com) | minimal interpreter, no C extensions | 27,895,317 B (26.6 MiB) |
| [`SHA256SUMS`](https://github.com/Largo/cosmoruby/releases/latest/download/SHA256SUMS) | checksums for the three binaries | — |

Most people only want `ruby.com`.

**Architecture: `v4.0.6-cosmo2` assets are fat — x86-64 *and* aarch64 in one
file.** The same download runs natively on an Intel/AMD PC, on a Raspberry Pi
or ARM Chromebook, and on an Apple Silicon Mac (through cosmopolitan's `ape-m1`
loader). `RUBY_PLATFORM` reports `x86_64-cosmo` or `aarch64-cosmo` accordingly.
Verified on real hardware in CI on six platforms — see [Platform support,
honestly](#platform-support-honestly).

That is what makes the file ~31 MB rather than ~20 MB: the aarch64 half is an
entire second copy of the interpreter. The single shared `/zip` stdlib is
appended once and read by both halves.

The **older `v4.0.6-cosmo1` assets were x86-64 only** and will not run natively
on any ARM machine. If you have those, upgrade.

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

The same file on an aarch64 machine (Raspberry Pi, ARM Chromebook, Apple
Silicon) prints `[aarch64-cosmo]` — one download, both architectures.

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

#### Exit codes on Windows are the plain status (fixed)

```powershell
PS C:\> .\ruby.com -e "exit 7"
PS C:\> $LASTEXITCODE
7
```

Up to and including igravious's Ruby 4.0.0 release binary this printed `1792`
(`7 << 8`), and `%ERRORLEVEL%` under `cmd.exe` reported the same: cosmopolitan
Libc encodes a POSIX *wait status* into the Windows process exit code so that a
cosmopolitan parent can decode it with `WEXITSTATUS()`. Native Windows parents
read the number as it is, so `ruby.com` now hands them the plain status, like
every other Windows program. `exit`, `exit!`, an uncaught exception (1) and
statuses above 255 (narrowed to eight bits, as on Linux) all agree across
platforms.

If you *are* the cosmopolitan parent — you spawn `ruby.com` from another APE
and decode the result with `WEXITSTATUS()` — set
`COSMORUBY_WAIT_STATUS_EXIT=1` in the child's environment to get the old
encoding back. Nothing changes on Linux, macOS or the BSDs.

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
  Linux, Windows and macOS, on both architectures, with no `.so` anywhere. See
  the limitations below.
- **YJIT** — pass `--yjit`. **Linux x86-64 only**; see below.

### `openssl` is MbedTLS-backed, not Ruby's OpenSSL extension

`require "openssl"` succeeds, and `net/http` talks HTTPS over it — a plain
`Net::HTTP.get_response(URI("https://rubygems.org/"))` returns 200 on Linux
*and on Windows* (verified since the socket fix). The implementation is
`/zip/lib/ruby/4.0.0/openssl.rb` plus a C binding of cosmopolitan's MbedTLS
(`ext/mbedtls`), not the real `openssl` C extension. **Every cryptographic
operation is an MbedTLS call**; nothing is reimplemented in Ruby.

**Symmetric cryptography works, and is wire-compatible with OpenSSL.**

| | |
| --- | --- |
| `OpenSSL::Cipher` | AES-128/192/256 in **GCM**, **CBC**, **CTR** and ECB, DES/3DES, ChaCha20, ChaCha20-Poly1305 (`OpenSSL::Cipher.ciphers` lists all 20). `encrypt`/`decrypt`, `key=`/`iv=`, `random_key`/`random_iv`, `key_len`/`iv_len`/`block_size`, `padding=`, `update`/`final`, `reset`, and the AEAD set `auth_data=`/`auth_tag`/`auth_tag=`/`auth_tag_len=`/`authenticated?` |
| `OpenSSL::Digest` | a real class hierarchy — `OpenSSL::Digest < Digest::Class`, with `SHA1`, `SHA224`, `SHA256`, `SHA384`, `SHA512`, `MD5` and `BLAKE2B256` subclasses, subclassable yourself |
| `OpenSSL::HMAC` | the class *and* `.digest`/`.hexdigest`/`.base64digest` |
| `OpenSSL::KDF` | `pbkdf2_hmac` (also `OpenSSL::PKCS5.pbkdf2_hmac` / `pbkdf2_hmac_sha1`) |
| `OpenSSL::Random` | `random_bytes`, straight from the OS CSPRNG (`getrandom(2)`, `RtlGenRandom` on Windows) |
| `OpenSSL` | `fixed_length_secure_compare`, `secure_compare` |
| `OpenSSL::SSL` / `OpenSSL::X509` | TLS *client* only, verifying against cosmopolitan's built-in root store |

This is enough for **Rails**: `require "rails"` works,
`ActiveSupport::MessageEncryptor` round-trips under both AES-256-GCM and
AES-256-CBC, `ActiveSupport::KeyGenerator` derives keys, encrypted cookies
and `Rails.application.credentials` work, and a message encrypted on a
machine with real OpenSSL decrypts here (and vice versa) — verified byte for
byte, which is what makes a `credentials.yml.enc` portable into a packaged
binary.

Correctness is pinned by `cosmo_tests/test_openssl.rb`, which is built from
published vectors — NIST's AES-GCM cases, NIST SP 800-38A for CBC and CTR,
RFC 4231 for HMAC, RFC 6070 and RFC 7914 §11 for PBKDF2 — plus ciphertexts
generated by a real OpenSSL 3.5.0, plus negative cases (every single-bit tag
corruption, tampered ciphertext, tampered AAD, wrong key, wrong key/iv
length, truncated ciphertext, corrupt padding). It runs on all six CI
platforms and also passes unchanged against genuine OpenSSL.

**What is still missing** — these raise `NotImplementedError`, they never
return a wrong-but-plausible answer:

- **Public-key cryptography.** `OpenSSL::PKey::RSA`/`DSA`/`EC`/`DH` exist as
  names only; key generation, loading, signing, verification and encryption
  all raise. So: no signed-gem verification, no JWT RS256/ES256, no
  `ssh`-style key handling.
- **Certificates.** `OpenSSL::X509::Certificate`/`Name`/`Store` are
  configuration stubs. They do not parse, build or verify certificates —
  peer verification happens inside the MbedTLS handshake against the built-in
  root store, so you cannot add your own CA at runtime.
- **PKCS#7/CMS, OCSP, `OpenSSL::ASN1`, `OpenSSL::BN`, `OpenSSL::Engine`.**
  Absent entirely.
- **`OpenSSL::KDF.hkdf` and `.scrypt`**, and `Cipher#pkcs5_keyivgen`
  (EVP_BytesToKey) — MbedTLS has none of them.
- **Cipher modes CFB, OFB, XTS, CCM** are not compiled into this MbedTLS;
  `OpenSSL::Cipher.new` refuses their names rather than substituting.
- **TLS server sockets, client certificates, session resumption, ALPN,
  `OpenSSL::VERSION` and the `OPENSSL_VERSION*` constants.**

### YJIT is Linux-only, and the banner does not admit it

The YJIT compiler is Rust code built for `x86_64-unknown-linux-gnu` and is only
initialised when the APE is running on Linux.

| | Linux x86-64 | Windows x86-64 | macOS x86-64 | any aarch64 |
| --- | --- | --- | --- | --- |
| `RubyVM::YJIT.enabled?` | `true` | `false` | `false` | `false` |
| `RUBY_DESCRIPTION` | `+YJIT` | `+YJIT` (misleading) | `+YJIT` (misleading) | `+YJIT` (misleading) |

Passing `--yjit` anywhere else is harmless — it is accepted and does nothing.
Do not trust `RUBY_DESCRIPTION`; trust `RubyVM::YJIT.enabled?`. On the aarch64
half the Rust staticlib is not even linked in (`yjit/BUILD.mk` disables it for
`ARCH=aarch64`), so the weak stubs in `yjit.c` *are* the implementation there.
One of them used to return `false` from `rb_yjit_parse_option()`, which
`ruby.c` turns into `invalid YJIT option ''` — so `ruby.com --yjit` was a hard
startup error on the ARM half until `v4.0.6-cosmo2`. It is now accepted and
inert, exactly as on Windows.

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
- **32-bit anything, BIOS/metal.** Not tested, not claimed.

### Sockets: fixed everywhere, with one intermittent Windows rough edge

Up to and including `v4.0.6-cosmo1`, **TCP was completely broken on Windows and
on macOS** and worked only on Linux. That is fixed. Loopback in both
directions, `::1`, outbound connections, `Net::HTTP` and HTTPS to
rubygems.org all work on Windows, macOS (Intel and Apple Silicon) and Linux
(x86-64 and aarch64).

The cause was not cosmopolitan. Two headers in this port `#undef`'d
cosmopolitan's *runtime* socket constants and hard-coded the **Linux** numbers,
so `AF_INET6` was 10 where the host wanted 23 (Winsock) or 30 (XNU) and
`SOL_SOCKET` was 1 where the host wanted `0xffff`. `PORTING-NOTES.md` has the
full table and the reason a wrong `AF_INET6` corrupted plain **IPv4** addresses.

**Known issue — intermittent, Windows only.** A blocking socket operation can
occasionally raise:

```
NoMethodError: undefined method 'kernel_sleep' for nil
```

What is known about it:

- It **raises cleanly and a retry succeeds**; it does not corrupt data or hang.
- It is **not** a Ruby bug and not a bug in this port's socket code. Six CI
  rounds plus disassembly of the actual failing CI artifact show `%rax`
  comparing *unequal* to `Qnil` (4) and then reading back as 4 four
  instructions later, with nothing in between writing it. That points at
  asynchronous register corruption in cosmopolitan's Windows interrupt
  delivery — `vm_check_ints_blocking()` is by construction the code that runs
  immediately after an interrupt was delivered during a blocking region.
- **Frequency, measured.** On GitHub's `windows-latest` runner a 200-connect
  diagnostic loop hit it in **3 of 3** runs on the release commit, at
  **28–40 events per 200 blocking connects (14–20 %)**. The gating smoke test
  only does a handful of connects, which is why it shows a warning in about
  half of runs — the underlying rate is steadier than that suggests. Assume
  roughly 1 in 6 blocking connects can raise if you do sustained socket work on
  Windows, and retry.
- Curiously, `windows-11-arm` — the *same* x86-64 PE half, run through
  Windows-on-ARM's x64 emulation — is clean: **0/200 in all three runs**. A
  defect that disappears under emulation but fires on native x64 fits the
  register-corruption hypothesis, and is a strong argument against any
  remaining "Ruby logic error" theory.
- It has **never** reproduced on a local Win11 VM: ~2100 connects across eight
  strategies, plus 10 consecutive clean runs of the full smoke suite against
  this release binary.
- It was deliberately **not** papered over with a `NIL_P` guard. If a register
  really is being corrupted, that guard would hide one symptom of something
  that can corrupt any other register anywhere else.
- CI treats exactly this signature as a warning on Windows (retrying once) and
  keeps every other socket failure hard, so a real regression still goes red.

If your Windows code does heavy socket work, wrap connects in a retry. See
"Windows follow-up: `kernel_sleep` for nil" in `PORTING-NOTES.md`.

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

Every row below is a real machine running the **same fat artifact**. Each CI job
first proves the file contains both an x86-64 and an aarch64 ELF header, so a
silently-thin build cannot fake an ARM pass.

| Platform | `RUBY_PLATFORM` | Status |
| --- | --- | --- |
| Linux x86-64 (Debian 13, GitHub `ubuntu-latest`) | `x86_64-cosmo` | **Verified.** 36/36 `ci_smoke.rb`, 19/19 `test_sockets.rb`, sqlite3 5/5, `env -i` from an empty dir, YJIT on. |
| Linux aarch64 (GitHub `ubuntu-24.04-arm`, real ARM hardware) | `aarch64-cosmo` | **Verified**, blocking CI job. 36/36, 19/19, sqlite3 5/5, exit status. No YJIT. |
| Windows 11 x86-64 (Win11 Pro 26200 + GitHub `windows-latest`) | `x86_64-cosmo` | **Verified.** 38/38 `ci_smoke.rb`, 22/22 `test_sockets.rb`, sqlite3 5/5, `irb.com`, `miniruby.com`, HTTPS. Caveats: the intermittent socket flake above, native subprocesses. |
| macOS x86-64 (GitHub `macos-15-intel`) | `x86_64-cosmo` | **Verified.** 36/36, 19/19, sqlite3 5/5. TCP now works (it did not in `cosmo1`). |
| macOS aarch64 / Apple Silicon (GitHub `macos-latest`) | `aarch64-cosmo` | **Verified.** Boots the aarch64 half through the `ape-m1` loader; 36/36, 19/19, sqlite3 5/5. |
| Windows-on-ARM (GitHub `windows-11-arm`) | `x86_64-cosmo` | **Runs, via the OS's x64 emulation.** Cosmopolitan's Windows PE half is x86-64 only, so the aarch64 half is not what executes. 38/38 anyway. |
| FreeBSD / OpenBSD 7.3+ / NetBSD | — | **Untested.** No runner was available. Nothing in the build is BSD-hostile and cosmopolitan targets them, but nobody has run it. |
| Raspberry Pi, ARM Chromebook, other physical ARM devices | — | **Expected to work** (`ubuntu-24.04-arm` is the same aarch64 ELF), but not tried on such a device. |

If you run it somewhere untested, please open an issue either way.

## Packaging your app into one file

### The zero-tool way: `zip` your app onto `ruby.com`

An APE is also a valid ZIP archive, and this Ruby reads its own archive as
`/zip`. So the smallest possible way to ship a Ruby application as one
self-contained binary is to append it with a stock `zip`:

```sh
cp ruby.com myapp.com
zip myapp.com main.rb lib/thing.rb   # any layout you like, entry point at the root
./myapp.com hello world              # -> runs main.rb with ARGV == ["hello", "world"]
```

No compiler, no launcher stub, no unpacking to a temp directory at run time:
the script is read straight out of the binary. `myapp.com` is still a normal
APE, so the same file runs on Linux, macOS, Windows and the BSDs.

The rules:

| | |
| --- | --- |
| **Convention** | `/zip/main.rb` — the entry point is `main.rb` at the *root* of the archive |
| **When it fires** | whenever `/zip/main.rb` exists. A packed binary *is* an application, so it always runs it |
| **Arguments** | **the whole command line goes to your app, untouched.** Ruby claims none of it: `myapp.com --version` gives `ARGV == ["--version"]`, `myapp.com -- -x` gives `ARGV == ["--", "-x"]`. There is no argument your CLI cannot have |
| **Interpreter options** | via `RUBYOPT` (`RUBYOPT="-I lib -w --yjit" ./myapp.com …`) or `RUBY_YJIT_ENABLE=1`, since the command line belongs to the app |
| **`$0` / `__FILE__`** | `/zip/main.rb`, so `__dir__` is `/zip` |
| **Multi-file apps** | `require_relative` works throughout the archive (`require_relative "lib/thing"`). Plain `require "thing"` does **not**: `/zip` is not on `$LOAD_PATH` — add `$LOAD_PATH.unshift(__dir__)` at the top of `main.rb` if you want it |
| **Escape hatch** | `COSMORUBY_NO_ZIP_MAIN=1` disables the hook, turning a packed binary back into an ordinary interpreter for debugging: `COSMORUBY_NO_ZIP_MAIN=1 ./myapp.com -e 'p $LOAD_PATH'` |
| **Exit status** | your app's, exactly, on every platform — including Windows |

A `ruby.com` with no `/zip/main.rb` behaves exactly as it always has, so this
costs existing users nothing. `irb.com` names its own program and is therefore
never affected by an appended `main.rb`; `miniruby.com` supports the convention
just like `ruby.com`.

Caveats worth knowing:

- The archive is **read-only**. Your app cannot write to `/zip`; use a real
  directory for state.
- Native extensions cannot be added this way — there is no `dlopen` in an APE.
  You get exactly the C extensions that were linked in (see *What's inside*).
- Anyone can `unzip` your binary. This is packaging, not obfuscation.
- On Windows, cosmopolitan rewrites path-shaped arguments (`C:\a\b` arrives as
  `/C/a/b`). That is pre-existing APE behaviour, not specific to this feature.

### The full way: ocran

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

A fat build is one command:

```sh
FAT=1 COSMO_RUBY=/path/to/bootstrap-ruby.com bash .github/scripts/build-cosmoruby.sh
# -> dist/{ruby,irb,miniruby}.com + dist/SHA256SUMS
```

Quick verification of a build you made:

```sh
sh third_party/ruby/cosmo_tests/smoke_test.sh dist/ruby.com     # 15 checks
dist/ruby.com third_party/ruby/cosmo_tests/ci_smoke.rb a b      # 36 checks
dist/ruby.com third_party/ruby/cosmo_tests/test_sockets.rb      # 19 checks (22 on Windows)
env -i dist/ruby.com third_party/ruby/cosmo_tests/test_sqlite3.rb
sh third_party/ruby/cosmo_tests/win_smoke.sh dist/ruby.com      # needs a Windows box

# the aarch64 half, without ARM hardware (needs qemu-user-static)
qemu-aarch64 build/bootstrap/ape.aarch64 dist/ruby.com -e 'puts RUBY_PLATFORM'
# => aarch64-cosmo
```

## Credits and licence

- [Justine Tunney](https://github.com/jart) and the Cosmopolitan Libc project —
  the APE format, the libc, the toolchain and the build system this is all
  built on.
- [igravious](https://github.com/igravious) — the CosmoRuby port itself:
  vendoring Ruby into the cosmopolitan monorepo, the static-extension build
  mode, the `/zip` stdlib packaging, YJIT, and releases up to v1.3.0.
- This fork adds an upstream sync, Ruby 4.0.6, the built-in `sqlite3`
  extension, a Windows crash fix, the socket-ABI fix that made TCP work on
  Windows and macOS, fat x86-64 + aarch64 release binaries with six-platform
  CI, and the fixes needed to build from a clean checkout.

Two cosmopolitan `getsockopt` bugs were found while verifying the socket work
(Windows `SO_ERROR` falling through untranslated, and a 1-byte→int widening
gated on `optlen == 4`; plus `SO_ERROR` untranslated on the unix path). Patches
and standalone `cosmocc` reproducers are prepared for jart/cosmopolitan.

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
