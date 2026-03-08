#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_BUILD_MTDEPS

THIRD_PARTY_BUILD_MTDEPS_EARLY_DIRECTDEPS =	\
	LIBC_CALLS				\
	LIBC_FMT				\
	LIBC_INTRIN				\
	LIBC_LOG				\
	LIBC_MEM				\
	LIBC_NEXGEN32E				\
	LIBC_RUNTIME				\
	LIBC_STDIO				\
	LIBC_STR				\
	LIBC_SYSV				\
	LIBC_SYSTEM				\
	THIRD_PARTY_GETOPT

THIRD_PARTY_BUILD_MTDEPS_LATE_DIRECTDEPS =	\
	TOOL_BUILD_LIB

THIRD_PARTY_BUILD_MTDEPS_DIRECTDEPS =		\
	$(THIRD_PARTY_BUILD_MTDEPS_EARLY_DIRECTDEPS)	\
	$(THIRD_PARTY_BUILD_MTDEPS_LATE_DIRECTDEPS)

THIRD_PARTY_BUILD_MTDEPS_EARLY_DEPS :=		\
	$(call uniq,$(foreach x,$(THIRD_PARTY_BUILD_MTDEPS_EARLY_DIRECTDEPS),$($(x))))

THIRD_PARTY_BUILD_MTDEPS_DEPS =		\
	$(call uniq,$(foreach x,$(THIRD_PARTY_BUILD_MTDEPS_DIRECTDEPS),$($(x))))

.SECONDEXPANSION:

# mtdeps - dependency analyser with context-key shim support
o/$(MODE)/third_party/build/mtdeps/mtdeps.dbg:	\
		$$(THIRD_PARTY_BUILD_MTDEPS_DEPS)	\
		o/$(MODE)/third_party/build/mtdeps/mtdeps.o	\
		$(CRT)					\
		$(APE_NO_MODIFY_SELF)
	@$(APELINK)

# automate_mkdeps - generic mkdeps automation for third-party modules
o/$(MODE)/third_party/build/mtdeps/automate_mkdeps.dbg:	\
		$$(THIRD_PARTY_BUILD_MTDEPS_DEPS)	\
		o/$(MODE)/third_party/build/mtdeps/automate_mkdeps.o	\
		$(CRT)					\
		$(APE_NO_MODIFY_SELF)
	@$(APELINK)

THIRD_PARTY_BUILD_MTDEPS_BINS =			\
	$(THIRD_PARTY_BUILD_MTDEPS_COMS)	\
	$(THIRD_PARTY_BUILD_MTDEPS_COMS:%=%.dbg)

THIRD_PARTY_BUILD_MTDEPS_COMS =			\
	o/$(MODE)/third_party/build/mtdeps/mtdeps	\
	o/$(MODE)/third_party/build/mtdeps/automate_mkdeps

.PHONY: o/$(MODE)/third_party/build/mtdeps
o/$(MODE)/third_party/build/mtdeps:		\
	$(THIRD_PARTY_BUILD_MTDEPS_BINS)
