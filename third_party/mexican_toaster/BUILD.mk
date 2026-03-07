#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_MEXICAN_TOASTER

# Split deps into early (available when local-includes.mk loads at
# Makefile line 317) and late (loaded after that point).  The early
# set uses := for immediate expansion; the late set is expanded at
# link time via $$ in .SECONDEXPANSION rules.
THIRD_PARTY_MEXICAN_TOASTER_EARLY_DIRECTDEPS =	\
	LIBC_CALLS					\
	LIBC_DLOPEN					\
	LIBC_FMT					\
	LIBC_INTRIN					\
	LIBC_MEM					\
	LIBC_NEXGEN32E					\
	LIBC_RUNTIME					\
	LIBC_STDIO					\
	LIBC_STR					\
	LIBC_SYSV					\
	LIBC_TEMP					\
	THIRD_PARTY_GETOPT				\
	THIRD_PARTY_MUSL				\
	THIRD_PARTY_SED					\
	THIRD_PARTY_TOMLC99				\
	THIRD_PARTY_TR

THIRD_PARTY_MEXICAN_TOASTER_LATE_DIRECTDEPS =	\
	TOOL_BUILD_LIB					\
	THIRD_PARTY_AWK					\
	THIRD_PARTY_CURL				\
	THIRD_PARTY_LINENOISE

THIRD_PARTY_MEXICAN_TOASTER_DIRECTDEPS =		\
	$(THIRD_PARTY_MEXICAN_TOASTER_EARLY_DIRECTDEPS)	\
	$(THIRD_PARTY_MEXICAN_TOASTER_LATE_DIRECTDEPS)

THIRD_PARTY_MEXICAN_TOASTER_EARLY_DEPS :=		\
	$(call uniq,$(foreach x,$(THIRD_PARTY_MEXICAN_TOASTER_EARLY_DIRECTDEPS),$($(x))))

# Full deps -- expanded late via .SECONDEXPANSION
THIRD_PARTY_MEXICAN_TOASTER_DEPS =			\
	$(call uniq,$(foreach x,$(THIRD_PARTY_MEXICAN_TOASTER_DIRECTDEPS),$($(x))))


# ksignalnames.S is pure data (rodata + strings), no x86 instructions.
# Needs an explicit rule so aarch64 builds compile it instead of using
# the libc/empty.s stub (see build/rules.mk).
o/$(MODE)/third_party/mexican_toaster/ksignalnames.o:		\
		third_party/mexican_toaster/ksignalnames.S
	@$(COMPILE) -AOBJECTIFY.S $(OBJECTIFY.S) $(OUTPUT_OPTION) -c $<

.SECONDEXPANSION:

# mtsh - Mexican Toaster Shell (enhanced command interpreter)
o/$(MODE)/third_party/mexican_toaster/mtsh.o:		\
		third_party/mexican_toaster/mtsh.c		\
		third_party/mexican_toaster/mtsh_version.h	\
		third_party/mexican_toaster/mtsh/util.inc	\
		third_party/mexican_toaster/mtsh/tokenize.inc	\
		third_party/mexican_toaster/mtsh/entry.inc

o/$(MODE)/third_party/mexican_toaster/mtsh.com.dbg:	\
		$$(THIRD_PARTY_MEXICAN_TOASTER_DEPS)		\
		o/$(MODE)/third_party/mexican_toaster/mtsh.o	\
		o/$(MODE)/third_party/mexican_toaster/ksignalnames.o	\
		$(CRT)						\
		$(APE_NO_MODIFY_SELF)
	@$(APELINK)

# mtdeps - Mexican Toaster dependency analyzer (mkdeps with context-key shim support)
o/$(MODE)/third_party/mexican_toaster/mtdeps.dbg:	\
		$$(THIRD_PARTY_MEXICAN_TOASTER_DEPS)		\
		o/$(MODE)/third_party/mexican_toaster/mtdeps.o	\
		$(CRT)						\
		$(APE_NO_MODIFY_SELF)
	@$(APELINK)

# automate_mkdeps - Generic mkdeps automation for third-party modules
o/$(MODE)/third_party/mexican_toaster/automate_mkdeps.dbg:	\
		$$(THIRD_PARTY_MEXICAN_TOASTER_DEPS)		\
		o/$(MODE)/third_party/mexican_toaster/automate_mkdeps.o	\
		$(CRT)						\
		$(APE_NO_MODIFY_SELF)
	@$(APELINK)

# caboose - Proof of concept for "getting toasted"
# Build without .com extension first so zipcopy can embed the ZIP
o/$(MODE)/third_party/mexican_toaster/caboose.o:	\
		third_party/mexican_toaster/examples/caboose.c		\
		third_party/mexican_toaster/examples/caboose/usage.inc	\
		third_party/mexican_toaster/examples/caboose/overlay_backend.inc	\
		third_party/mexican_toaster/examples/caboose/paths.inc	\
		third_party/mexican_toaster/examples/caboose/zip_check.inc	\
		third_party/mexican_toaster/examples/caboose/env_probe.inc	\
		third_party/mexican_toaster/examples/caboose/namespace_setup.inc	\
		third_party/mexican_toaster/examples/caboose/recursive_copy.inc	\
		third_party/mexican_toaster/examples/caboose/piz_setup.inc	\
		third_party/mexican_toaster/examples/caboose/overlay_cmd.inc	\
		third_party/mexican_toaster/examples/caboose/toast_piz.inc	\
		third_party/mexican_toaster/examples/caboose/zip_tools.inc	\
		third_party/mexican_toaster/examples/caboose/state.inc	\
		third_party/mexican_toaster/examples/caboose/state_file.inc	\
		third_party/mexican_toaster/examples/caboose/thaw.inc	\
		third_party/mexican_toaster/examples/caboose/freeze.inc	\
		third_party/mexican_toaster/examples/caboose/persist.inc	\
		third_party/mexican_toaster/examples/caboose/discard.inc	\
		third_party/mexican_toaster/examples/caboose/status_cmd.inc	\
		third_party/mexican_toaster/examples/caboose/main.inc
	@$(COMPILE) -AOBJECTIFY.c $(OBJECTIFY.c) -c $< -o $@

o/$(MODE)/third_party/mexican_toaster/mtsh_embed.o:	\
		third_party/mexican_toaster/mtsh_embed.c	\
		third_party/mexican_toaster/mtsh.c		\
		third_party/mexican_toaster/mtsh/util.inc	\
		third_party/mexican_toaster/mtsh/tokenize.inc	\
		third_party/mexican_toaster/mtsh/entry.inc

o/$(MODE)/third_party/mexican_toaster/caboose.dbg:	\
		$$(THIRD_PARTY_MEXICAN_TOASTER_DEPS)		\
		o/$(MODE)/third_party/mexican_toaster/caboose.o	\
		o/$(MODE)/third_party/mexican_toaster/mtsh_embed.o	\
		o/$(MODE)/third_party/mexican_toaster/ksignalnames.o	\
		$(CRT)						\
		$(APE_NO_MODIFY_SELF)				\
		| o/$(MODE)/third_party/mexican_toaster/lsdir.com
	@$(APELINK)


# lsdir - Simple directory listing (works as ls, dir, or lsdir)
o/$(MODE)/third_party/mexican_toaster/lsdir.com.dbg:	\
		$$(THIRD_PARTY_MEXICAN_TOASTER_DEPS)		\
		o/$(MODE)/third_party/mexican_toaster/lsdir.o	\
		$(CRT)						\
		$(APE_NO_MODIFY_SELF)
	@$(APELINK)

# caboose_state_test - Unit tests for state machine + state file
o/$(MODE)/third_party/mexican_toaster/caboose_state_test.o:	\
		third_party/mexican_toaster/examples/caboose_state_test.c	\
		third_party/mexican_toaster/examples/caboose/state.inc	\
		third_party/mexican_toaster/examples/caboose/state_file.inc
	@$(COMPILE) -AOBJECTIFY.c $(OBJECTIFY.c) -c $< -o $@

o/$(MODE)/third_party/mexican_toaster/caboose_state_test.dbg:	\
		$$(THIRD_PARTY_MEXICAN_TOASTER_DEPS)		\
		o/$(MODE)/third_party/mexican_toaster/caboose_state_test.o	\
		$(CRT)						\
		$(APE_NO_MODIFY_SELF)
	@$(APELINK)

THIRD_PARTY_MEXICAN_TOASTER_BINS =			\
	$(THIRD_PARTY_MEXICAN_TOASTER_COMS)		\
	$(THIRD_PARTY_MEXICAN_TOASTER_COMS:%=%.dbg)

THIRD_PARTY_MEXICAN_TOASTER_COMS =			\
	o/$(MODE)/third_party/mexican_toaster/mtsh.com		\
	o/$(MODE)/third_party/mexican_toaster/mtdeps		\
	o/$(MODE)/third_party/mexican_toaster/automate_mkdeps	\
	o/$(MODE)/third_party/mexican_toaster/caboose		\
	o/$(MODE)/third_party/mexican_toaster/lsdir.com

THIRD_PARTY_MEXICAN_TOASTER_TESTS =			\
	o/$(MODE)/third_party/mexican_toaster/caboose_state_test

.PHONY: o/$(MODE)/third_party/mexican_toaster
o/$(MODE)/third_party/mexican_toaster:			\
	$(THIRD_PARTY_MEXICAN_TOASTER_BINS)		\
	$(THIRD_PARTY_MEXICAN_TOASTER_CHECKS)
