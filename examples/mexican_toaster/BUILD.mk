#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += EXAMPLES_MEXICAN_TOASTER

EXAMPLES_MEXICAN_TOASTER_DIRECTDEPS =			\
	LIBC_CALLS					\
	LIBC_FMT					\
	LIBC_INTRIN					\
	LIBC_MEM					\
	LIBC_NEXGEN32E					\
	LIBC_PROC					\
	LIBC_RUNTIME					\
	LIBC_STDIO					\
	LIBC_STR					\
	LIBC_SYSV

EXAMPLES_MEXICAN_TOASTER_DEPS :=			\
	$(call uniq,$(foreach x,$(EXAMPLES_MEXICAN_TOASTER_DIRECTDEPS),$($(x))))

# Test binaries
EXAMPLES_MEXICAN_TOASTER_BINS =				\
	o/$(MODE)/examples/mexican_toaster/test_unshare.com		\
	o/$(MODE)/examples/mexican_toaster/test_uid_mapping.com		\
	o/$(MODE)/examples/mexican_toaster/test_overlay_mount.com

# Build rules
o/$(MODE)/examples/mexican_toaster/%.com.dbg:		\
		$(EXAMPLES_MEXICAN_TOASTER_DEPS)	\
		o/$(MODE)/examples/mexican_toaster/%.o	\
		$(CRT)					\
		$(APE_NO_MODIFY_SELF)
	@$(APELINK)

.PHONY: o/$(MODE)/examples/mexican_toaster
o/$(MODE)/examples/mexican_toaster:			\
		$(EXAMPLES_MEXICAN_TOASTER_BINS)	\
		$(EXAMPLES_MEXICAN_TOASTER_BINS:%=%.dbg)
