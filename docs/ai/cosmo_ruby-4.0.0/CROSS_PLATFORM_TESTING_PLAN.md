# CosmoRuby Cross-Platform Diagnostic Testing Plan

## Context

CosmoRuby's README.cosmo claims ruby.com runs on 7 platforms from a single
binary. Cosmopolitan targets Linux, macOS, Windows, FreeBSD, OpenBSD, NetBSD,
and bare metal (BIOS). However bare metal only supports serial UART I/O and
mmap/malloc — no filesystem, no threads, no signals (per jart: "Our support on
metal is currently limited to read()/write() to serial UART and mmap()/malloc()
are supported too"). Ruby cannot run on bare metal.

That leaves **6 OSes x 2 architectures = 12 combinations** to test. APE
binaries built with `cosmocc` are **fat by default** — both x86_64 and aarch64
native code in a single file. The `apelink` tool weaves two arch-specific ELF
binaries together; at runtime the APE loader detects the CPU and loads the right
code. So the same ruby.com runs natively on both architectures.

Currently there is zero cross-platform CI; all Ruby testing is manual on Linux
x86_64 only.

## The 12 Combinations

### CI via GitHub Actions (8 combinations)

| # | OS | Arch | Runner label |
|---|-----|------|-------------|
| 1 | Linux | x86_64 | `ubuntu-latest` |
| 2 | Linux | aarch64 | `ubuntu-24.04-arm` |
| 3 | macOS | x86_64 | `macos-15-intel` |
| 4 | macOS | aarch64 | `macos-15` |
| 5 | Windows | x86_64 | `windows-latest` |
| 6 | Windows | aarch64 | `windows-11-arm` |

### Manual via VirtualBox (3 combinations — x86_64 BSDs)

| # | OS | Arch | Method |
|---|-----|------|--------|
| 7 | FreeBSD | x86_64 | VirtualBox VM |
| 8 | OpenBSD | x86_64 | VirtualBox VM |
| 9 | NetBSD | x86_64 | VirtualBox VM |

### Manual via QEMU (3 combinations — aarch64 BSDs)

VirtualBox cannot emulate aarch64 guests. QEMU system emulation is needed
(slow but functional).

| # | OS | Arch | Method |
|---|-----|------|--------|
| 10 | FreeBSD | aarch64 | QEMU `qemu-system-aarch64` |
| 11 | OpenBSD | aarch64 | QEMU `qemu-system-aarch64` |
| 12 | NetBSD | aarch64 | QEMU `qemu-system-aarch64` |

## Files to Create

### 1. `third_party/ruby-wip-4.0.0/cosmo_tests/platform_diagnostic.rb`

The centrepiece — a self-contained Ruby script (~400-500 lines) that ruby.com
runs on any platform to verify it works. No external gems, works with
`--disable-gems`.

**Test sections:**

| Section | What it tests | Failure severity |
|---------|--------------|------------------|
| identity | RUBY_VERSION, RUBY_ENGINE, RUBY_PLATFORM, COSMO constants | FAIL |
| platform | Etc.uname OS detection, architecture, nprocessors, RbConfig | FAIL |
| zip | /zip/ exists, stdlib count >100, key files present | FAIL |
| extensions | require + smoke-test: stringio, pathname, json, zlib, digest, date, etc. | FAIL |
| file_io | tempfile create/read/delete, directory ops, path expansion | FAIL |
| encoding | UTF-8 default, String#encode, unicode ops | FAIL |
| process | PID, ENV, Thread.new, fork (skip on Windows) | FAIL (fork=SKIP) |
| network | Socket.gethostname, ephemeral TCPServer | WARN only |
| gems | require rubygems, require bundler | WARN only |
| yjit | RubyVM::YJIT.enabled? (disabled on Windows = expected) | INFO only |

**Output:** Human-readable with `[PASS]`/`[FAIL]`/`[WARN]`/`[SKIP]` per check.
`--json` flag for machine-parseable CI output.

**Exit codes:** 0 = pass, 1 = any failure, 2 = script crash.

**Pattern reference:** Follows style of existing `test_build_modes.rb` (class
with test methods, structured output, exit codes).

### 2. `third_party/ruby-wip-4.0.0/cosmo_tests/run_platform_diagnostic.sh`

Tiny shell wrapper — the three files you transfer to any machine/VM:
- `ruby.com`
- `platform_diagnostic.rb`
- `run_platform_diagnostic.sh`

```
Usage: ./run_platform_diagnostic.sh [path/to/ruby.com] [--json]
```

### 3. `.github/workflows/ruby-platforms.yml`

GitHub Actions workflow — build once, test on 8 runners:

```
build (ubuntu-latest)
  └─ make + package_ruby.sh → upload ruby.com artifact
      ├─ test-linux-x86    (ubuntu-latest)
      ├─ test-linux-arm64  (ubuntu-24.04-arm)
      ├─ test-macos-x86    (macos-15-intel)
      ├─ test-macos-arm64  (macos-15)
      ├─ test-windows-x86  (windows-latest, shell: pwsh)
      ├─ test-windows-arm64(windows-11-arm, shell: pwsh)
      └─ summary (always) → markdown table in $GITHUB_STEP_SUMMARY
```

Triggers: push to `master`/`feature/ruby-*`, PRs touching `third_party/ruby*`,
manual `workflow_dispatch`.

Key per-platform details:
- **Linux x86_64:** Register APE binfmt_misc (copy ape.elf, register via /proc)
- **Linux aarch64:** Same binfmt_misc registration (with aarch64 ape loader)
- **macOS:** Fat binary runs natively on both Intel and Apple Silicon
- **Windows:** Use `shell: pwsh`, .com runs as native PE; avoid Git Bash

### 4. `third_party/ruby-wip-4.0.0/cosmo_tests/summarise_results.rb`

Small script reads `*-results.json` files, produces markdown summary table.
Used by CI summary job and locally after manual VM runs.

### 5. `docs/ai/cosmo_ruby-4.0.0/CROSS_PLATFORM_TESTING.md`

Step-by-step guide covering all 12 combinations:
- **CI (8):** Push to branch, watch Actions
- **VirtualBox (3):** FreeBSD/OpenBSD/NetBSD x86_64 VM setup
- **QEMU (3):** FreeBSD/OpenBSD/NetBSD aarch64 system emulation setup

## Implementation Order

### Phase 0: Validate the harness with hello world

Prove that the CI runners, VirtualBox VMs, and QEMU emulation all work before
touching Ruby. Use `examples/hello.c` (already in the repo) to build a trivial
fat APE binary and run it on all 12 combinations.

1. Write `.github/workflows/cosmo-hello-world.yml` — minimal workflow that:
   - Builds `o//examples/hello` on `ubuntu-latest`
   - Uploads `hello.com` as artifact
   - Downloads and runs it on all 8 CI runners (6 OSes x 2 arches where available)
   - Each job just runs `./hello.com` and checks exit code 0
2. Push to feature branch, watch all 8 CI jobs go green
3. User copies `hello.com` to VirtualBox FreeBSD/OpenBSD/NetBSD VMs, runs it
4. User copies `hello.com` to QEMU aarch64 FreeBSD/OpenBSD/NetBSD, runs it
5. All 12 show "hello" → harness is validated

This is cheap and fast — hello.com is tiny, builds in seconds, and any failure
is a harness problem (not a Ruby problem).

### Phase 1: CosmoRuby diagnostic

6. Write `platform_diagnostic.rb` — test locally on Linux with existing ruby.com
7. Write `run_platform_diagnostic.sh` wrapper
8. Write `summarise_results.rb`
9. Write `.github/workflows/ruby-platforms.yml` (based on the validated hello workflow)
10. Write `CROSS_PLATFORM_TESTING.md` docs
11. User builds ruby.com, runs diagnostic locally to verify
12. Push to feature branch, watch CI (8 combinations)
13. User runs VirtualBox VMs for x86_64 BSDs (3 combinations)
14. User runs QEMU for aarch64 BSDs (3 combinations)

## Verification

- **Phase 0:** `./hello.com` prints "hello" and exits 0 on all 12 combinations
- **Phase 1 local:** `./ruby.com --disable-gems cosmo_tests/platform_diagnostic.rb`
- **Phase 1 CI:** Push to branch, check Actions → ruby-platforms workflow → summary
- **Phase 1 VMs:** Transfer 3 files to VM, run, read terminal output
- **Success:** All 12 combinations show `Verdict: PASS` with 0 failures
