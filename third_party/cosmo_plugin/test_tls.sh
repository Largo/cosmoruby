#!/bin/sh
set -eu

# TLS sanity test for cosmo_plugin loader using fat cosmocc (x86_64 + aarch64).

find_cosmocc() {
	if [ -x .cosmocc/current/bin/cosmocc ]; then
		echo .cosmocc/current/bin/cosmocc
		return
	fi
	if command -v cosmocc >/dev/null 2>&1; then
		command -v cosmocc
		return
	fi
	echo "cosmocc not found; build toolchain first (e.g. make o//third_party/ruby/ruby)" >&2
	exit 1
}

find_ar() {
	if [ -x .cosmocc/current/bin/ar.ape ]; then
		echo .cosmocc/current/bin/ar.ape
		return
	fi
	if [ -x .cosmocc/current/bin/x86_64-linux-cosmo-ar ]; then
		echo .cosmocc/current/bin/x86_64-linux-cosmo-ar
		return
	fi
	if command -v ar >/dev/null 2>&1; then
		command -v ar
		return
	fi
	echo "ar not found; build toolchain first" >&2
	exit 1
}

find_objdump() {
	if [ -x .cosmocc/current/bin/x86_64-linux-cosmo-objdump ]; then
		echo .cosmocc/current/bin/x86_64-linux-cosmo-objdump
		return
	fi
	if command -v objdump >/dev/null 2>&1; then
		command -v objdump
		return
	fi
	echo "objdump not found; build toolchain first" >&2
	exit 1
}

COSMOCC=${COSMOCC:-$(find_cosmocc)}
AR=${AR:-$(find_ar)}
OBJDUMP=${OBJDUMP:-$(find_objdump)}

MODE=${MODE:-default}
OUTDIR=o/$MODE/third_party/cosmo_plugin
PLUGIN=$OUTDIR/tls_plugin.a
LOADER=$OUTDIR/tls_loader_test

mkdir -p "$OUTDIR"

# Common flags let cosmocc inject the right libc headers/start files.
COMMON="-D_COSMO_SOURCE -I."
TLS_CFLAGS="-fPIC -ftls-model=global-dynamic -Xx86_64-mtls-dialect=gnu2 -Xaarch64-mtls-dialect=desc"
LOADER_CFLAGS="-fPIC -pthread"
LINK_FLAGS="-pthread"

echo "[build] tls_plugin.a"
# Build for both x86_64 and aarch64 using architecture-specific compilers
# to get proper global-dynamic TLS relocations (cosmocc optimizes to local-exec)
X86_CC=${X86_CC:-.cosmocc/current/bin/x86_64-linux-cosmo-gcc}
ARM_CC=${ARM_CC:-.cosmocc/current/bin/aarch64-linux-cosmo-gcc}

# x86_64: use gnu2 TLS dialect (TLSDESC) for global-dynamic
"$X86_CC" $COMMON -fPIC -ftls-model=global-dynamic -c third_party/cosmo_plugin/tls_plugin.c -o "$OUTDIR/tls_plugin.x86_64.o"

# aarch64: use desc TLS dialect for global-dynamic
"$ARM_CC" $COMMON -fPIC -ftls-model=global-dynamic -c third_party/cosmo_plugin/tls_plugin.c -o "$OUTDIR/tls_plugin.aarch64.o"

# Combine into fat archive
"$AR" rcs "$PLUGIN" "$OUTDIR/tls_plugin.x86_64.o" "$OUTDIR/tls_plugin.aarch64.o"

echo "[verify] tls_plugin x86_64 relocations"
if ! "$OBJDUMP" -r "$OUTDIR/tls_plugin.x86_64.o" | grep -E 'TLSDESC|TPOFF|TLSGD' >/dev/null; then
	echo "x86_64 TLS relocations missing; did not get TLSDESC/TPOFF/TLSGD as expected" >&2
	exit 2
fi
echo "[verify] tls_plugin aarch64 relocations"
# objdump doesn't recognize ARM64 TLS relocations, use readelf instead
if ! readelf -r "$OUTDIR/tls_plugin.aarch64.o" | grep -E 'R_AARCH64_TLSDESC|R_AARCH64_TLSLE' >/dev/null; then
	echo "aarch64 TLS relocations missing; did not get R_AARCH64_TLSDESC/TLSLE as expected" >&2
	exit 2
fi

echo "[build] tls_loader_test"
"$COSMOCC" $COMMON $LOADER_CFLAGS -c third_party/cosmo_plugin/cosmo_plugin.c -o "$OUTDIR/cosmo_plugin.o"
"$COSMOCC" $COMMON $LOADER_CFLAGS -c third_party/cosmo_plugin/tls_loader_test.c -o "$OUTDIR/tls_loader_test.o"
"$COSMOCC" $LINK_FLAGS "$OUTDIR/cosmo_plugin.o" "$OUTDIR/tls_loader_test.o" -o "$LOADER"

chmod +x "$LOADER"

echo "[run] $LOADER"
"$LOADER" "$PLUGIN"
