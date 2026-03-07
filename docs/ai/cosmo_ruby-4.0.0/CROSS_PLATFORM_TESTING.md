# CosmoRuby Cross-Platform Testing Guide

CosmoRuby's `ruby.com` is a fat APE binary that runs natively on 6 OSes x 2
architectures = 12 combinations. This guide covers how to test all of them.

## Quick Start (5 minutes)

Run the diagnostic locally on your current machine:

```bash
# If you have ruby.com packaged with embedded stdlib:
./ruby.com --disable-gems third_party/ruby-wip-4.0.0/cosmo_tests/platform_diagnostic.rb

# Or use the shell wrapper (Unix only):
cd third_party/ruby-wip-4.0.0/cosmo_tests
./run_platform_diagnostic.sh /path/to/ruby.com

# JSON output for CI consumption:
./ruby.com --disable-gems platform_diagnostic.rb --json > results.json

# Skip network tests (useful behind firewalls / in VMs):
./ruby.com --disable-gems platform_diagnostic.rb --no-network
```

On **Windows**, run ruby.com directly (no shell wrapper needed):

```powershell
.\ruby.com --disable-gems platform_diagnostic.rb --json
```

## The 12 Combinations

| # | OS | Arch | Method | Status |
|---|------|---------|--------|--------|
| 1 | Linux | x86_64 | CI: `ubuntu-latest` | Available |
| 2 | Linux | aarch64 | CI: `ubuntu-24.04-arm` | Available |
| 3 | macOS | x86_64 | CI: `macos-15-intel` | Available |
| 4 | macOS | aarch64 | CI: `macos-15` | Available |
| 5 | Windows | x86_64 | CI: `windows-latest` | Available |
| 6 | Windows | aarch64 | CI: `windows-11-arm` | Available |
| 7 | FreeBSD | x86_64 | VirtualBox VM | Manual |
| 8 | OpenBSD | x86_64 | VirtualBox VM | Manual |
| 9 | NetBSD | x86_64 | VirtualBox VM | Manual |
| 10 | FreeBSD | aarch64 | QEMU system emulation | Manual |
| 11 | OpenBSD | aarch64 | Future | Not tested |
| 12 | NetBSD | aarch64 | Future | Not tested |

## CI Testing (combinations 1-6)

### How it works

Two GitHub Actions workflows:

1. **`cosmo-hello-world.yml`** (Phase 0) -- Validates the APE format itself by
   building `examples/hello.c` and running it on all runners. Run this first
   when changing APE loader or Cosmopolitan infrastructure.

2. **`ruby-platforms.yml`** (Phase 1) -- Builds `ruby.com`, packages it with
   `package_ruby.sh`, then runs `platform_diagnostic.rb` on all 6 CI runners.

### Triggers

Both workflows trigger on:
- Push to `master` or `feature/ruby-*` branches
- Pull requests touching `third_party/ruby/**`
- Manual dispatch via GitHub Actions UI

### Reading CI results

1. Go to the repository's **Actions** tab
2. Click the workflow run
3. The **summary** job produces a markdown table showing pass/fail per platform
4. Click individual test jobs for detailed output
5. Download `results-<platform>` artifacts for JSON data

### APE loader setup (Linux runners only)

Linux CI runners need the APE loader registered with binfmt_misc. The workflows
handle this automatically:

```bash
sudo cp -a build/bootstrap/ape.elf /usr/bin/ape
sudo sh -c "echo ':APE:M::MZqFpD::/usr/bin/ape:' >/proc/sys/fs/binfmt_misc/register"
```

macOS and Windows runners need no setup -- APE binaries run natively (Mach-O
and PE respectively).

### Windows CI notes

- Windows runners use `shell: pwsh` (PowerShell)
- `ruby.com` is renamed to `ruby.exe` before execution
- No shell wrapper; `platform_diagnostic.rb` is invoked directly
- Expected failures: fork, YJIT, POSIX signals (documented in expected failures
  registry within `platform_diagnostic.rb`)

## Linux Prerequisites

### Install APE loader (recommended)

For faster APE binary startup on your local Linux machine:

```bash
sudo ape/apeinstall.sh
```

Or manually:

```bash
sudo cp build/bootstrap/ape.elf /usr/bin/ape
sudo sh -c "echo ':APE:M::MZqFpD::/usr/bin/ape:' >/proc/sys/fs/binfmt_misc/register"
```

### WSL2

If running under WSL2, disable Windows binary interop first:

```bash
sudo sh -c 'echo -1 > /proc/sys/fs/binfmt_misc/WSLInterop'
```

## VirtualBox BSD Setup (combinations 7-9)

### Prerequisites

- VirtualBox 7.x installed
- ISO images downloaded:
  - FreeBSD 14.x amd64
  - OpenBSD 7.x amd64
  - NetBSD 10.x amd64

### VM creation

1. Create a VM: 2 CPUs, 2GB RAM, 20GB disk
2. Install the OS from ISO
3. Enable SSH: ensure `sshd` is running
4. Configure port forwarding: Host 2222 -> Guest 22

### File transfer

Transfer these three files to the VM:

```bash
scp -P 2222 o/third_party/ruby/ruby.com user@localhost:~/
scp -P 2222 third_party/ruby-wip-4.0.0/cosmo_tests/platform_diagnostic.rb user@localhost:~/
scp -P 2222 third_party/ruby-wip-4.0.0/cosmo_tests/run_platform_diagnostic.sh user@localhost:~/
```

### Running on BSD

```bash
# On the VM:
chmod +x ruby.com run_platform_diagnostic.sh
./run_platform_diagnostic.sh ./ruby.com --json > results.json

# Or directly:
./ruby.com --disable-gems platform_diagnostic.rb --json > results.json
```

### Collecting results

```bash
scp -P 2222 user@localhost:~/results.json ./freebsd-x86-results.json
```

### Snapshots

Take a VirtualBox snapshot after initial setup so you can quickly revert:

```
Snapshot: "clean-install-with-ssh"
```

## QEMU aarch64 BSD Setup (combination 10)

VirtualBox cannot emulate aarch64 guests. Use QEMU system emulation instead.

### FreeBSD aarch64

```bash
# Download FreeBSD aarch64 image
fetch https://download.freebsd.org/releases/VM-IMAGES/14.1-RELEASE/aarch64/Latest/FreeBSD-14.1-RELEASE-aarch64.qcow2.xz
xz -d FreeBSD-14.1-RELEASE-aarch64.qcow2.xz

# Download UEFI firmware
# On Ubuntu: sudo apt install qemu-efi-aarch64
# Firmware at: /usr/share/qemu-efi-aarch64/QEMU_EFI.fd

# Launch VM
qemu-system-aarch64 \
  -M virt \
  -cpu cortex-a72 \
  -m 2G \
  -nographic \
  -bios /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
  -drive if=virtio,file=FreeBSD-14.1-RELEASE-aarch64.qcow2 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -device virtio-net-device,netdev=net0
```

Transfer files and run diagnostic the same way as VirtualBox (via SCP on port
2222).

**Note:** QEMU system emulation is slow. Allow 5-10 minutes for the diagnostic
to complete. Use `--no-network` to save time if network tests are flaky.

## Interpreting Results

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | All tests passed (or only expected failures/warnings) |
| 1 | One or more unexpected failures |
| 2 | Script crash (Ruby exception) |
| 3 | Bad command-line arguments |

### Status tags

| Tag | Meaning |
|-----|---------|
| `[PASS]` | Test passed |
| `[FAIL]` | Unexpected failure -- investigate |
| `[EXPECTED_FAIL]` | Known platform limitation (e.g. fork on Windows) |
| `[WARN]` | Non-critical issue (e.g. network flaky) |
| `[SKIP]` | Test not applicable on this platform |
| `[INFO]` | Informational only (e.g. YJIT status) |

### When to worry

- **FAIL on Linux x86_64**: Always investigate. This is the primary platform.
- **FAIL on macOS**: Likely a real issue. Investigate.
- **EXPECTED_FAIL on Windows**: Normal (fork, signals, YJIT).
- **WARN on network**: Likely CI environment issue, not a Ruby bug.
- **WARN on BSDs**: May be emulation artefacts. Test on real hardware if possible.

### Expected failures registry

`platform_diagnostic.rb` contains a built-in registry of known platform
limitations:

```ruby
EXPECTED_FAILURES = {
  'windows' => {
    'fork'    => 'Windows does not support fork()',
    'yjit'    => 'YJIT not yet supported on Windows',
    'signals' => 'Limited POSIX signal support on Windows'
  },
  'netbsd' => {
    'network' => 'Intermittent socket issues on NetBSD under emulation'
  }
}
```

Use `--strict` to treat expected failures as real failures (useful for tracking
progress on platform support).

## Troubleshooting

### "cannot execute binary file" on Linux

APE loader not registered. Run:
```bash
sudo cp build/bootstrap/ape.elf /usr/bin/ape
sudo sh -c "echo ':APE:M::MZqFpD::/usr/bin/ape:' >/proc/sys/fs/binfmt_misc/register"
```

### "permission denied" on macOS

macOS quarantine. Clear it:
```bash
xattr -d com.apple.quarantine ruby.com
chmod +x ruby.com
```

### ruby.com hangs on Windows

Ensure you're running from PowerShell or cmd.exe, not Git Bash. Git Bash's
MSYS2 layer can interfere with APE binaries.

### /zip/ filesystem empty or missing

ruby.com was not packaged. Rebuild and repackage:
```bash
make -j8 o//third_party/ruby/ruby
cd third_party/ruby && bash package_ruby.sh
```

### Network tests fail in CI

This is common and non-critical. The diagnostic uses retry logic (3 attempts,
5s delay). If it still fails, the test reports `[WARN]` not `[FAIL]`.

To skip network tests entirely: `--no-network`

### QEMU aarch64 extremely slow

Expected. QEMU system emulation without KVM is full software emulation.
Tips:
- Use `-cpu max` instead of `-cpu cortex-a72` for slightly better performance
- Increase memory: `-m 4G`
- Use `--no-network --timeout 120` for the diagnostic

## Generating Summary Tables

After collecting results from multiple platforms:

```bash
# Markdown table (default)
ruby.com --disable-gems summarise_results.rb results/*.json

# JSON summary
ruby.com --disable-gems summarise_results.rb --format json results/*.json

# CSV for spreadsheets
ruby.com --disable-gems summarise_results.rb --format csv results/*.json
```

## Adding New Platforms

To add a new platform to CI testing:

1. Add a matrix entry in `.github/workflows/ruby-platforms.yml`:
   ```yaml
   - { os: new-runner-label, arch: x86_64, name: newos-x86, shell: bash }
   ```

2. If the platform has known limitations, add them to
   `EXPECTED_FAILURES` in `platform_diagnostic.rb`.

3. If the platform needs special setup (like the APE loader on Linux),
   add a conditional step in the workflow.

4. Push to a feature branch and verify the new job runs.

## Maintenance

| Cadence | Task |
|---------|------|
| Monthly | Verify GitHub runner labels still valid |
| Monthly | Update BSD VM images to latest releases |
| Per release | Run full 12-combination test suite |
| Per Cosmopolitan update | Re-run Phase 0 hello test |
