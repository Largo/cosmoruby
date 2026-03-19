#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_COSMO_XNOTIFY

THIRD_PARTY_COSMO_XNOTIFY_ARTIFACTS += THIRD_PARTY_COSMO_XNOTIFY_A
THIRD_PARTY_COSMO_XNOTIFY = $(THIRD_PARTY_COSMO_XNOTIFY_A_DEPS) $(THIRD_PARTY_COSMO_XNOTIFY_A)
THIRD_PARTY_COSMO_XNOTIFY_A = o/$(MODE)/third_party/cosmo_xnotify/cosmo_xnotify.a

THIRD_PARTY_COSMO_XNOTIFY_A_HDRS =				\
	third_party/cosmo_xnotify/cosmo_xnotify.h

THIRD_PARTY_COSMO_XNOTIFY_A_SRCS =				\
	third_party/cosmo_xnotify/cosmo_xnotify.c

THIRD_PARTY_COSMO_XNOTIFY_A_OBJS =				\
	$(THIRD_PARTY_COSMO_XNOTIFY_A_SRCS:%.c=o/$(MODE)/%.o)

THIRD_PARTY_COSMO_XNOTIFY_A_DIRECTDEPS =			\
	LIBC_CALLS						\
	LIBC_INTRIN						\
	LIBC_MEM						\
	LIBC_RUNTIME						\
	LIBC_STDIO						\
	LIBC_STR						\
	LIBC_SYSV						\
	LIBC_SYSV_CALLS

THIRD_PARTY_COSMO_XNOTIFY_A_DEPS :=				\
	$(call uniq,$(foreach x,$(THIRD_PARTY_COSMO_XNOTIFY_A_DIRECTDEPS),$($(x))))

$(THIRD_PARTY_COSMO_XNOTIFY_A):				\
	third_party/cosmo_xnotify/				\
	$(THIRD_PARTY_COSMO_XNOTIFY_A).pkg			\
	$(THIRD_PARTY_COSMO_XNOTIFY_A_OBJS)

$(THIRD_PARTY_COSMO_XNOTIFY_A).pkg:				\
	$(THIRD_PARTY_COSMO_XNOTIFY_A_OBJS)			\
	$(foreach x,$(THIRD_PARTY_COSMO_XNOTIFY_A_DIRECTDEPS),$($(x)_A).pkg)

THIRD_PARTY_COSMO_XNOTIFY_LIBS = $(foreach x,$(THIRD_PARTY_COSMO_XNOTIFY_ARTIFACTS),$($(x)))
THIRD_PARTY_COSMO_XNOTIFY_HDRS = $(foreach x,$(THIRD_PARTY_COSMO_XNOTIFY_ARTIFACTS),$($(x)_HDRS))
THIRD_PARTY_COSMO_XNOTIFY_SRCS = $(foreach x,$(THIRD_PARTY_COSMO_XNOTIFY_ARTIFACTS),$($(x)_SRCS))
THIRD_PARTY_COSMO_XNOTIFY_OBJS = $(foreach x,$(THIRD_PARTY_COSMO_XNOTIFY_ARTIFACTS),$($(x)_OBJS))

$(THIRD_PARTY_COSMO_XNOTIFY_A_OBJS): third_party/cosmo_xnotify/BUILD.mk

.PHONY: o/$(MODE)/third_party/cosmo_xnotify
o/$(MODE)/third_party/cosmo_xnotify: $(THIRD_PARTY_COSMO_XNOTIFY_A)
