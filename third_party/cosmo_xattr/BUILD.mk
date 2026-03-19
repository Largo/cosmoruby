#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_COSMO_XATTR

THIRD_PARTY_COSMO_XATTR_ARTIFACTS += THIRD_PARTY_COSMO_XATTR_A
THIRD_PARTY_COSMO_XATTR = $(THIRD_PARTY_COSMO_XATTR_A_DEPS) $(THIRD_PARTY_COSMO_XATTR_A)
THIRD_PARTY_COSMO_XATTR_A = o/$(MODE)/third_party/cosmo_xattr/cosmo_xattr.a

THIRD_PARTY_COSMO_XATTR_A_HDRS =				\
	third_party/cosmo_xattr/cosmo_xattr.h

THIRD_PARTY_COSMO_XATTR_A_SRCS =				\
	third_party/cosmo_xattr/cosmo_xattr.c

THIRD_PARTY_COSMO_XATTR_A_OBJS =				\
	$(THIRD_PARTY_COSMO_XATTR_A_SRCS:%.c=o/$(MODE)/%.o)

THIRD_PARTY_COSMO_XATTR_A_DIRECTDEPS =				\
	LIBC_CALLS						\
	LIBC_INTRIN						\
	LIBC_RUNTIME						\
	LIBC_SYSV						\
	LIBC_SYSV_CALLS

THIRD_PARTY_COSMO_XATTR_A_DEPS :=				\
	$(call uniq,$(foreach x,$(THIRD_PARTY_COSMO_XATTR_A_DIRECTDEPS),$($(x))))

$(THIRD_PARTY_COSMO_XATTR_A):					\
	third_party/cosmo_xattr/				\
	$(THIRD_PARTY_COSMO_XATTR_A).pkg			\
	$(THIRD_PARTY_COSMO_XATTR_A_OBJS)

$(THIRD_PARTY_COSMO_XATTR_A).pkg:				\
	$(THIRD_PARTY_COSMO_XATTR_A_OBJS)			\
	$(foreach x,$(THIRD_PARTY_COSMO_XATTR_A_DIRECTDEPS),$($(x)_A).pkg)

THIRD_PARTY_COSMO_XATTR_LIBS = $(foreach x,$(THIRD_PARTY_COSMO_XATTR_ARTIFACTS),$($(x)))
THIRD_PARTY_COSMO_XATTR_HDRS = $(foreach x,$(THIRD_PARTY_COSMO_XATTR_ARTIFACTS),$($(x)_HDRS))
THIRD_PARTY_COSMO_XATTR_SRCS = $(foreach x,$(THIRD_PARTY_COSMO_XATTR_ARTIFACTS),$($(x)_SRCS))
THIRD_PARTY_COSMO_XATTR_OBJS = $(foreach x,$(THIRD_PARTY_COSMO_XATTR_ARTIFACTS),$($(x)_OBJS))

$(THIRD_PARTY_COSMO_XATTR_A_OBJS): third_party/cosmo_xattr/BUILD.mk

.PHONY: o/$(MODE)/third_party/cosmo_xattr
o/$(MODE)/third_party/cosmo_xattr: $(THIRD_PARTY_COSMO_XATTR_A)
