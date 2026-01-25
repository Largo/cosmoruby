#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘
#
# OVERVIEW
#
#   mimalloc is a general purpose allocator with excellent performance
#   characteristics developed by Microsoft Research.
#
#   https://github.com/microsoft/mimalloc
#
# LICENSE
#
#   MIT License
#

PKGS += THIRD_PARTY_MIMALLOC

THIRD_PARTY_MIMALLOC_ARTIFACTS += THIRD_PARTY_MIMALLOC_A
THIRD_PARTY_MIMALLOC = $(THIRD_PARTY_MIMALLOC_A_DEPS) $(THIRD_PARTY_MIMALLOC_A)
THIRD_PARTY_MIMALLOC_A = o/$(MODE)/third_party/mimalloc/mimalloc.a

THIRD_PARTY_MIMALLOC_A_HDRS =					\
	third_party/mimalloc/mimalloc.h				\
	third_party/mimalloc/mimalloc/atomic.h			\
	third_party/mimalloc/mimalloc/bits.h			\
	third_party/mimalloc/mimalloc/internal.h		\
	third_party/mimalloc/mimalloc/prim.h			\
	third_party/mimalloc/mimalloc/track.h			\
	third_party/mimalloc/mimalloc/types.h			\
	third_party/mimalloc/cosmo_config.h

# Use static.c which includes all other source files
THIRD_PARTY_MIMALLOC_A_SRCS =					\
	third_party/mimalloc/src/static.c			\
	third_party/mimalloc/cosmo_prim.c

THIRD_PARTY_MIMALLOC_A_OBJS =					\
	$(THIRD_PARTY_MIMALLOC_A_SRCS:%.c=o/$(MODE)/%.o)

THIRD_PARTY_MIMALLOC_A_CHECKS =					\
	$(THIRD_PARTY_MIMALLOC_A).pkg				\
	$(THIRD_PARTY_MIMALLOC_A_HDRS:%=o/$(MODE)/%.ok)

THIRD_PARTY_MIMALLOC_A_DIRECTDEPS =				\
	LIBC_CALLS						\
	LIBC_INTRIN						\
	LIBC_NEXGEN32E						\
	LIBC_STR						\
	LIBC_SYSV						\
	LIBC_SYSV_CALLS						\
	THIRD_PARTY_COMPILER_RT

THIRD_PARTY_MIMALLOC_A_DEPS :=					\
	$(call uniq,$(foreach x,$(THIRD_PARTY_MIMALLOC_A_DIRECTDEPS),$($(x))))

$(THIRD_PARTY_MIMALLOC_A):					\
		third_party/mimalloc/				\
		$(THIRD_PARTY_MIMALLOC_A).pkg			\
		$(THIRD_PARTY_MIMALLOC_A_OBJS)

$(THIRD_PARTY_MIMALLOC_A).pkg:					\
		$(THIRD_PARTY_MIMALLOC_A_OBJS)			\
		$(foreach x,$(THIRD_PARTY_MIMALLOC_A_DIRECTDEPS),$($(x)_A).pkg)

# Include paths for mimalloc headers
$(THIRD_PARTY_MIMALLOC_A_OBJS): private				\
		CFLAGS +=					\
			-I$(CURDIR)/third_party/mimalloc	\
			-include third_party/mimalloc/cosmo_config.h

# -O3 for performance (except tiny modes)
ifneq ($(MODE),tiny)
ifneq ($(MODE),tinylinux)
ifneq ($(MODE),aarch64-tiny)
$(THIRD_PARTY_MIMALLOC_A_OBJS): private				\
		CFLAGS +=					\
			-O3
endif
endif
endif

# Debug mode settings
ifeq ($(MODE),dbg)
$(THIRD_PARTY_MIMALLOC_A_OBJS): private				\
		CFLAGS +=					\
			-DMI_DEBUG=2				\
			-DMI_SECURE=4
endif

# Common compiler flags
# Note: mimalloc stats functions have larger stack frames (~4352 bytes)
# so we increase the limit from 4096 to 8192
$(THIRD_PARTY_MIMALLOC_A_OBJS): private				\
		COPTS +=					\
			-ffreestanding				\
			-fdata-sections				\
			-ffunction-sections			\
			-foptimize-sibling-calls		\
			-Wframe-larger-than=8192		\
			-Walloca-larger-than=8192		\
			-Wno-unused-function			\
			-Wno-unused-variable

# Note: We do NOT use -mgeneral-regs-only here because mimalloc
# returns structs (like mi_memid_t) that require SSE registers
# on the System V AMD64 ABI

THIRD_PARTY_MIMALLOC_LIBS = $(foreach x,$(THIRD_PARTY_MIMALLOC_ARTIFACTS),$($(x)))
THIRD_PARTY_MIMALLOC_SRCS = $(foreach x,$(THIRD_PARTY_MIMALLOC_ARTIFACTS),$($(x)_SRCS))
THIRD_PARTY_MIMALLOC_HDRS = $(foreach x,$(THIRD_PARTY_MIMALLOC_ARTIFACTS),$($(x)_HDRS))
THIRD_PARTY_MIMALLOC_CHECKS = $(foreach x,$(THIRD_PARTY_MIMALLOC_ARTIFACTS),$($(x)_CHECKS))
THIRD_PARTY_MIMALLOC_OBJS = $(foreach x,$(THIRD_PARTY_MIMALLOC_ARTIFACTS),$($(x)_OBJS))
$(THIRD_PARTY_MIMALLOC_OBJS): $(BUILD_FILES) third_party/mimalloc/BUILD.mk

.PHONY: o/$(MODE)/third_party/mimalloc
o/$(MODE)/third_party/mimalloc: $(THIRD_PARTY_MIMALLOC_CHECKS)
