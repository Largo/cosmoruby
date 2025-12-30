# Position-Independent Archive Loading Plan V3 (Post-Implementation Notes)

## What’s Done (Validated)
- **Export table generation**: Derived from linked `.dbg` binaries; relocation-free blob; linked (not objcopied) into hosts. Builds for Ruby now produce `ruby_exports.c/o` automatically.
- **Plugin loader library**: Lives in `third_party/cosmo_plugin/`; page-aligned `mmap`, W^X, GOT, init array execution, per-thread TLS shim, registry; filters fat archives per-arch.
- **Ruby integration**: `.a` now a loadable extension; `load.c` dispatches `.a` to the Cosmo loader; `dln_cosmo.c` bridge; dual lookup `.rb/.so/.a`.
- **Relocations**: Complete x86_64 coverage including GOTPCREL[X], GOTTPOFF, TLSDESC descriptor wiring (resolver + GOTPC32_TLSDESC), TLSGD/TLSLD, DTPOFF/TPOFF; PC32 overflow checks; COPY rejected. Aarch64 coverage added (ADRP/ADD/GOT/TLS equivalents) with TLS shim parity.
- **PLT stubs**: Added executable trampolines for out-of-range PC-relative calls so large archives still link/run.
- **Non-ALLOC sections**: Relocations targeting debug/other non-alloc sections are skipped to avoid bogus writes.
- **Compiler flags**: Plugins built with `-fPIC`; extern type mismatch fixed (function pointers, not arrays).
- **mawk compatibility**: Export generator fixed uninitialized count variable so awk variants work.
- **TLS fixups**: TLS template zero-initialized after memalign; TLSGD stores module/offset directly in GOT; `__tls_get_addr` reads GOT words; displacement calc includes addend; TLS idx/desc allocation uses stable capacity to avoid pointer invalidation.
- **Smoke tests**: `.a` plugin loads, resolves ~2.7k Ruby symbols, runs `Init_*`, `TestHello.world` and `add`, and TLS test passes on x86_64/aarch64.

## Open/Partial
- **TLS dtors**: No per-thread destructor support; static-TLS style only.
- **Unloading**: No destructor/fini_array run on unload; registry is load-only.
- **Export coverage**: Default export filter is open; optional prefix filtering not exposed in Ruby build knobs yet.
- **Debug noise**: Remove/guard remaining debug prints when ready.

## Next Targets
1) Optional TLS cleanup: document static-TLS limitations and consider dtors hook if feasible.
2) Test matrix: json/msgpack/nokogiri gems; thin archives; long filenames; multi-init archives; concurrent loads; W^X assertions.
3) Optional: dual export filters per language (Ruby-only vs language-agnostic).
4) Cleanup: strip debug logging once stability is proven.

## Files/Infrastructure in Play
- Loader: `third_party/cosmo_plugin/cosmo_plugin.[ch]`, `BUILD.mk`, `export_symbols.sh`.
- Ruby binding: `third_party/ruby-wip-3.4.7/dln_cosmo.c`, `load.c` `.a` handling, `ruby.deps.mk` (sources), `ruby.compile.mk` (exports + deps), `ruby.link.mk` (link exports), `THIRD_PARTY_COSMO_PLUGIN` dep.

## Lessons Learned
- Generate exports from the linked image; link them—do not paste objects.
- Ensure PIC builds and skip non-ALLOC relocations.
- Provide PLT/trampoline support for far calls in large archives.
- Keep changes in third_party/ to respect the no-core-edits rule.
