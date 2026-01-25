# APE vs COM File Extension Naming Convention

## Background

Cosmopolitan produces Actually Portable Executables (APE) - polyglot binaries that run natively on Linux, macOS, Windows, FreeBSD, OpenBSD, NetBSD, and BIOS.

## Current State (2026-01)

Two extensions are used in the Cosmopolitan ecosystem:

### `.com` Extension
- Used for end-user applications (redbean.com, ruby.com, etc.)
- Windows recognizes `.com` as executable (can be double-clicked)
- Historical convention from early Cosmopolitan

### `.ape` Extension
- Used by cosmocc toolchain for internal build tools:
  ```
  .cosmocc/3.9.2/bin/touch.ape
  .cosmocc/3.9.2/bin/compile.ape
  .cosmocc/3.9.2/bin/ar.ape
  etc.
  ```
- More self-documenting - describes what the file actually is
- Not automatically recognized as executable on Windows

## Open Questions

1. **Should CosmoRuby use `.ape` instead of `.com`?**
   - `ruby.ape` is more descriptive than `ruby.com`
   - Ruby is typically invoked from command line, not double-clicked
   - Would align with cosmocc's internal tooling convention

2. **Is there an official Cosmopolitan convention?**
   - Worth checking with Justine or Cosmopolitan repo
   - The toolchain using `.ape` suggests it's acceptable/preferred for CLI tools

3. **Hybrid approach?**
   - Build as `ruby.ape`, provide `ruby.com` symlink for Windows compatibility
   - Added complexity but best of both worlds

## Recommendation

Consider adopting `.ape` for CosmoRuby binaries since:
- More accurate/descriptive naming
- Consistent with cosmocc toolchain conventions
- Ruby is a CLI tool, not a GUI application
- Avoids confusion with legacy DOS `.com` format

## Related

- Cosmopolitan APE documentation
- cosmocc toolchain source
