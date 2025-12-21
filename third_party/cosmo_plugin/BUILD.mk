#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_COSMO_PLUGIN

THIRD_PARTY_COSMO_PLUGIN_ARTIFACTS += THIRD_PARTY_COSMO_PLUGIN_A
THIRD_PARTY_COSMO_PLUGIN = $(THIRD_PARTY_COSMO_PLUGIN_A_DEPS) $(THIRD_PARTY_COSMO_PLUGIN_A)
THIRD_PARTY_COSMO_PLUGIN_A = o/$(MODE)/third_party/cosmo_plugin/cosmo_plugin.a

THIRD_PARTY_COSMO_PLUGIN_A_HDRS =					\
	third_party/cosmo_plugin/cosmo_plugin.h

THIRD_PARTY_COSMO_PLUGIN_A_SRCS =					\
	third_party/cosmo_plugin/cosmo_plugin.c

THIRD_PARTY_COSMO_PLUGIN_A_OBJS =					\
	$(THIRD_PARTY_COSMO_PLUGIN_A_SRCS:%.c=o/$(MODE)/%.o)

THIRD_PARTY_COSMO_PLUGIN_A_DIRECTDEPS =				\
	LIBC_CALLS						\
	LIBC_ELF						\
	LIBC_INTRIN						\
	LIBC_LOG						\
	LIBC_MEM						\
	LIBC_STDIO						\
	LIBC_STR						\
	LIBC_SYSV						\
	LIBC_THREAD						\

THIRD_PARTY_COSMO_PLUGIN_A_DEPS :=					\
	$(call uniq,$(foreach x,$(THIRD_PARTY_COSMO_PLUGIN_A_DIRECTDEPS),$($(x))))

THIRD_PARTY_COSMO_PLUGIN_A_CHECKS =					\
	$(THIRD_PARTY_COSMO_PLUGIN_A).pkg				\
	$(THIRD_PARTY_COSMO_PLUGIN_A_HDRS:%=o/$(MODE)/%.ok)

$(THIRD_PARTY_COSMO_PLUGIN_A):						\
	third_party/cosmo_plugin/					\
	$(THIRD_PARTY_COSMO_PLUGIN_A).pkg				\
	$(THIRD_PARTY_COSMO_PLUGIN_A_OBJS)

$(THIRD_PARTY_COSMO_PLUGIN_A).pkg:					\
	$(THIRD_PARTY_COSMO_PLUGIN_A_OBJS)				\
	$(foreach x,$(THIRD_PARTY_COSMO_PLUGIN_A_DIRECTDEPS),$($(x)_A).pkg)

THIRD_PARTY_COSMO_PLUGIN_LIBS = $(foreach x,$(THIRD_PARTY_COSMO_PLUGIN_ARTIFACTS),$($(x)))
THIRD_PARTY_COSMO_PLUGIN_HDRS = $(foreach x,$(THIRD_PARTY_COSMO_PLUGIN_ARTIFACTS),$($(x)_HDRS))
THIRD_PARTY_COSMO_PLUGIN_SRCS = $(foreach x,$(THIRD_PARTY_COSMO_PLUGIN_ARTIFACTS),$($(x)_SRCS))
THIRD_PARTY_COSMO_PLUGIN_CHECKS = $(foreach x,$(THIRD_PARTY_COSMO_PLUGIN_ARTIFACTS),$($(x)_CHECKS))
THIRD_PARTY_COSMO_PLUGIN_OBJS = $(foreach x,$(THIRD_PARTY_COSMO_PLUGIN_ARTIFACTS),$($(x)_OBJS))

$(THIRD_PARTY_COSMO_PLUGIN_OBJS): third_party/cosmo_plugin/BUILD.mk

.PHONY: o/$(MODE)/third_party/cosmo_plugin
o/$(MODE)/third_party/cosmo_plugin: $(THIRD_PARTY_COSMO_PLUGIN_CHECKS)
