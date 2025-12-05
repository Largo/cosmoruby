#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_MEXICAN_TOASTER

THIRD_PARTY_MEXICAN_TOASTER_DIRECTDEPS =		\
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
	THIRD_PARTY_AWK					\
	THIRD_PARTY_CURL				\
	THIRD_PARTY_GETOPT				\
	THIRD_PARTY_LINENOISE				\
	THIRD_PARTY_MUSL				\
	THIRD_PARTY_SED					\
	THIRD_PARTY_TR

THIRD_PARTY_MEXICAN_TOASTER_DEPS :=			\
	$(call uniq,$(foreach x,$(THIRD_PARTY_MEXICAN_TOASTER_DIRECTDEPS),$($(x))))

THIRD_PARTY_MEXICAN_TOASTER_RUBYBEAN_DIRECTDEPS =	\
	$(TOOL_NET_DIRECTDEPS)				\
	THIRD_PARTY_RUBY

THIRD_PARTY_MEXICAN_TOASTER_RUBYBEAN_DEPS :=		\
	$(call uniq,$(foreach x,$(THIRD_PARTY_MEXICAN_TOASTER_RUBYBEAN_DIRECTDEPS),$($(x))))

# mtsh - Mexican Toaster Shell (enhanced command interpreter)
o/$(MODE)/third_party/mexican_toaster/mtsh.o:		\
		third_party/mexican_toaster/mtsh.c		\
		third_party/mexican_toaster/mtsh_version.h	\
		third_party/mexican_toaster/mtsh/util.inc	\
		third_party/mexican_toaster/mtsh/tokenize.inc	\
		third_party/mexican_toaster/mtsh/entry.inc

o/$(MODE)/third_party/mexican_toaster/mtsh.com.dbg:	\
		$(THIRD_PARTY_MEXICAN_TOASTER_DEPS)		\
		o/$(MODE)/third_party/mexican_toaster/mtsh.o	\
		$(CRT)						\
		$(APE_NO_MODIFY_SELF)
	@$(APELINK)

# mtdeps - Mexican Toaster dependency analyzer (mkdeps with context-key shim support)
o/$(MODE)/third_party/mexican_toaster/mtdeps.dbg:	\
		$(THIRD_PARTY_MEXICAN_TOASTER_DEPS)		\
		o/$(MODE)/third_party/mexican_toaster/mtdeps.o	\
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
		third_party/mexican_toaster/examples/caboose/main.inc
	@$(COMPILE) -AOBJECTIFY.c $(OBJECTIFY.c) -c $< -o $@

o/$(MODE)/third_party/mexican_toaster/mtsh_embed.o:	\
		third_party/mexican_toaster/mtsh_embed.c	\
		third_party/mexican_toaster/mtsh.c		\
		third_party/mexican_toaster/mtsh/util.inc	\
		third_party/mexican_toaster/mtsh/tokenize.inc	\
		third_party/mexican_toaster/mtsh/entry.inc

o/$(MODE)/third_party/mexican_toaster/caboose.dbg:	\
		$(THIRD_PARTY_MEXICAN_TOASTER_DEPS)		\
		o/$(MODE)/third_party/mexican_toaster/caboose.o	\
		o/$(MODE)/third_party/mexican_toaster/mtsh_embed.o	\
		$(CRT)						\
		$(APE)					\
		| o/$(MODE)/third_party/mexican_toaster/lsdir.com
	@$(APELINK)

# rubybean - Ruby-enabled Redbean fork for Mexican Toaster
o/$(MODE)/third_party/mexican_toaster/rubybean.dbg:	\
		$(THIRD_PARTY_MEXICAN_TOASTER_RUBYBEAN_DEPS)	\
		$(TOOL_NET_REDBEAN_LUA_MODULES)			\
		o/$(MODE)/tool/net/.init.lua.zip.o		\
		o/$(MODE)/tool/net/favicon.ico.zip.o		\
		o/$(MODE)/tool/net/redbean.png.zip.o		\
		o/$(MODE)/tool/net/help.txt.zip.o		\
		o/$(MODE)/third_party/mexican_toaster/rubybean.o	\
		o/$(MODE)/tool/net/net.pkg			\
		$(CRT)						\
		$(APE_NO_MODIFY_SELF)
	@$(APELINK)

o/$(MODE)/third_party/mexican_toaster/rubybean.o: private	\
		CFLAGS +=					\
			-Ithird_party/ruby/include		\
			-Wno-unused-but-set-variable

# lsdir - Simple directory listing (works as ls, dir, or lsdir)
o/$(MODE)/third_party/mexican_toaster/lsdir.com.dbg:	\
		$(THIRD_PARTY_MEXICAN_TOASTER_DEPS)		\
		o/$(MODE)/third_party/mexican_toaster/lsdir.o	\
		$(CRT)						\
		$(APE_NO_MODIFY_SELF)
	@$(APELINK)

THIRD_PARTY_MEXICAN_TOASTER_BINS =			\
	$(THIRD_PARTY_MEXICAN_TOASTER_COMS)		\
	$(THIRD_PARTY_MEXICAN_TOASTER_COMS:%=%.dbg)

THIRD_PARTY_MEXICAN_TOASTER_COMS =			\
	o/$(MODE)/third_party/mexican_toaster/mtsh.com		\
	o/$(MODE)/third_party/mexican_toaster/mtdeps		\
	o/$(MODE)/third_party/mexican_toaster/caboose		\
	o/$(MODE)/third_party/mexican_toaster/rubybean		\
	o/$(MODE)/third_party/mexican_toaster/lsdir.com

.PHONY: o/$(MODE)/third_party/mexican_toaster
o/$(MODE)/third_party/mexican_toaster:			\
	$(THIRD_PARTY_MEXICAN_TOASTER_BINS)		\
	$(THIRD_PARTY_MEXICAN_TOASTER_CHECKS)
