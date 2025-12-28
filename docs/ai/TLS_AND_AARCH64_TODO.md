# TLS and AArch64 Status & Follow-Ups for Cosmo Plugin Loader

## Status
- **x86_64 TLS**: Complete. TLSGD/TLSLD/DTPOFF/TPOFF/GOTTPOFF/GOTPC32_TLSDESC/TLSDESC/TLSDESC_CALL implemented. TLS template zero-init fixed; TLSGD stores module+offset directly in GOT; `__tls_get_addr` reads GOT words. Overflow checks in place.
- **AArch64**: Implemented relocation/TLS handling (ADRP/ADD/GOT/TLS equivalents) with the same offset-based TLS shim semantics. Fat archives are filtered per-arch when loading.
- **TLS model**: Static-template per-thread copy via `cosmo_plugin_tls_get`; no dynamic TLS dtors.
- **Tests**: TLS test now passes on x86_64 and aarch64; PLT far-call stubs present; non-ALLOC relocations skipped.

## Remaining TODOs
- TLS destructors: still not available; document limitation and consider optional per-thread cleanup hook if we ever wire dtors.
- Unload/fini: not exposed; could run `.fini_array` and free TLS blocks if a destructor story emerges.
- Export filtering knobs: optional `EXPORT_PREFIXES` passthrough per language (Ruby/Python/Lua).
- Test matrix expansion: thin archives, long filenames, real-world gems (json/msgpack/nokogiri), concurrency/W^X assertions, overflow/error-path checks.

## Notes / Risks
- Cosmopolitan lacks dynamic TLS dtors; unloading TLS safely remains limited.
- Keep debug logging guarded/optional once the matrix is green.
