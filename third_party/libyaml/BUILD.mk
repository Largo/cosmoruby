#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_LIBYAML

THIRD_PARTY_LIBYAML_ARTIFACTS += THIRD_PARTY_LIBYAML_A
THIRD_PARTY_LIBYAML = $(THIRD_PARTY_LIBYAML_A_DEPS) $(THIRD_PARTY_LIBYAML_A)
THIRD_PARTY_LIBYAML_A = o/$(MODE)/third_party/libyaml/libyaml.a
THIRD_PARTY_LIBYAML_A_FILES := $(wildcard third_party/libyaml/*)
THIRD_PARTY_LIBYAML_A_HDRS = $(filter %.h,$(THIRD_PARTY_LIBYAML_A_FILES))
THIRD_PARTY_LIBYAML_A_SRCS = $(filter %.c,$(THIRD_PARTY_LIBYAML_A_FILES))
THIRD_PARTY_LIBYAML_A_OBJS = $(THIRD_PARTY_LIBYAML_A_SRCS:%.c=o/$(MODE)/%.o)

THIRD_PARTY_LIBYAML_A_CHECKS =				\
	$(THIRD_PARTY_LIBYAML_A).pkg			\
	$(THIRD_PARTY_LIBYAML_A_HDRS:%=o/$(MODE)/%.ok)

THIRD_PARTY_LIBYAML_A_DIRECTDEPS =			\
	LIBC_CALLS					\
	LIBC_FMT					\
	LIBC_INTRIN					\
	LIBC_MEM					\
	LIBC_NEXGEN32E					\
	LIBC_RUNTIME					\
	LIBC_STDIO					\
	LIBC_STR					\
	LIBC_SYSV

THIRD_PARTY_LIBYAML_A_DEPS :=				\
	$(call uniq,$(foreach x,$(THIRD_PARTY_LIBYAML_A_DIRECTDEPS),$($(x))))

$(THIRD_PARTY_LIBYAML_A):				\
		third_party/libyaml/			\
		$(THIRD_PARTY_LIBYAML_A).pkg		\
		$(THIRD_PARTY_LIBYAML_A_OBJS)

$(THIRD_PARTY_LIBYAML_A).pkg:				\
		$(THIRD_PARTY_LIBYAML_A_OBJS)		\
		$(foreach x,$(THIRD_PARTY_LIBYAML_A_DIRECTDEPS),$($(x)_A).pkg)

# Compiler flags for libyaml
o/$(MODE)/third_party/libyaml/%.o: private		\
	CFLAGS +=					\
		-Ithird_party/libyaml			\
		-DYAML_DECLARE_STATIC			\
		-include third_party/libyaml/config.h	\
		-Wno-unused-value

THIRD_PARTY_LIBYAML_LIBS = $(foreach x,$(THIRD_PARTY_LIBYAML_ARTIFACTS),$($(x)))
THIRD_PARTY_LIBYAML_SRCS = $(foreach x,$(THIRD_PARTY_LIBYAML_ARTIFACTS),$($(x)_SRCS))
THIRD_PARTY_LIBYAML_HDRS = $(foreach x,$(THIRD_PARTY_LIBYAML_ARTIFACTS),$($(x)_HDRS))
THIRD_PARTY_LIBYAML_CHECKS = $(foreach x,$(THIRD_PARTY_LIBYAML_ARTIFACTS),$($(x)_CHECKS))
THIRD_PARTY_LIBYAML_OBJS = $(foreach x,$(THIRD_PARTY_LIBYAML_ARTIFACTS),$($(x)_OBJS))
$(THIRD_PARTY_LIBYAML_OBJS): third_party/libyaml/BUILD.mk

.PHONY: o/$(MODE)/third_party/libyaml
o/$(MODE)/third_party/libyaml: $(THIRD_PARTY_LIBYAML_CHECKS)
