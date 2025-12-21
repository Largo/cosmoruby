#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

################################################################################
# COSMOPOLITAN BUILD CONSTRAINTS
#
# Hermetic Build:
#   - Cosmopolitan downloads its own toolchain to .cosmocc/
#   - Cannot rely on system Ruby or tools during build
#   - Use HOST_RUBY or COSMO_RUBY variables for Ruby interpreter
#   - All build artifacts go to o/$(MODE)/ directory tree
#
# cocmd Shell Limitations:
#   - Make recipes use cocmd (Cosmopolitan's embedded shell)
#   - Supported: ':', '#' comments, subshells '()', cmd substitution '$()'
#   - Limited: Complex '&& ||' chains with redirects may fail
#   - Workaround: Break into multiple rules or simplify command logic
################################################################################

o/$(MODE)/third_party/ruby/ruby.dbg: | ruby.codegen

# Phase 1: Build without exports to extract symbols
# Note: Does NOT depend on ruby.pkg (which includes exports.o) to break circular dependency
o/$(MODE)/third_party/ruby/ruby.pre.dbg:			\
        $(THIRD_PARTY_RUBY_RUBY_DEPS)				\
        o/$(MODE)/third_party/ruby/ruby.main.o			\
        $(foreach x,$(THIRD_PARTY_RUBY_EXTENSIONS),$($(x)_A))	\
        $(CRT)							\
        $(APE_NO_MODIFY_SELF)
	@$(APELINK)

o/$(MODE)/third_party/ruby/ruby.pre.dbg: private		\
	LDFLAGS +=						\
		--whole-archive				\
		$(foreach x,$(THIRD_PARTY_RUBY_EXTENSIONS),$($(x)_A))	\
		--no-whole-archive

# Phase 2: Generate exports from pre-built binary (ruby.compile.mk has the rule)

# Phase 3: Build final binary with real exports
o/$(MODE)/third_party/ruby/ruby.dbg:				\
        $(THIRD_PARTY_RUBY_RUBY_DEPS)				\
        o/$(MODE)/third_party/ruby/ruby.pkg			\
        o/$(MODE)/third_party/ruby/ruby.main.o			\
        o/$(MODE)/third_party/ruby/ruby_exports.o		\
        $(foreach x,$(THIRD_PARTY_RUBY_EXTENSIONS),$($(x)_A))	\
        $(CRT)							\
        $(APE_NO_MODIFY_SELF)
	@$(APELINK)

# Force linker to extract all extension object files from archives (weak symbols don't trigger extraction)
o/$(MODE)/third_party/ruby/ruby.dbg: private			\
	LDFLAGS +=						\
		--whole-archive				\
		$(foreach x,$(THIRD_PARTY_RUBY_EXTENSIONS),$($(x)_A))	\
		--no-whole-archive

################################################################################
# ruby.zipless

o/$(MODE)/third_party/ruby/ruby.zipless.pkg:			\
    o/$(MODE)/third_party/ruby/ruby.main.zipless.o		\
    $(foreach x,$(THIRD_PARTY_RUBY_RUBY_DIRECTDEPS),$($(x)_A).pkg)

o/$(MODE)/third_party/ruby/ruby.zipless.dbg: | ruby.codegen

o/$(MODE)/third_party/ruby/ruby.zipless.dbg:			\
        $(THIRD_PARTY_RUBY_RUBY_DEPS)				\
        o/$(MODE)/third_party/ruby/ruby.zipless.pkg		\
        o/$(MODE)/third_party/ruby/ruby.main.zipless.o		\
        o/$(MODE)/third_party/ruby/ruby_exports.o		\
        $(foreach x,$(THIRD_PARTY_RUBY_EXTENSIONS),$($(x)_A))	\
        $(CRT)							\
        $(APE_NO_MODIFY_SELF)
	@$(APELINK)

o/$(MODE)/third_party/ruby/ruby.zipless.dbg: private		\
	LDFLAGS +=						\
		--whole-archive				\
		$(foreach x,$(THIRD_PARTY_RUBY_EXTENSIONS),$($(x)_A))	\
		--no-whole-archive

################################################################################
# irb

THIRD_PARTY_RUBY_IRB_DIRECTDEPS =				\
    LIBC_FMT							\
    LIBC_INTRIN							\
    LIBC_NEXGEN32E						\
    LIBC_RUNTIME						\
    LIBC_STDIO							\
    LIBC_MEM							\
    LIBC_STR							\
    LIBC_SYSV							\
    THIRD_PARTY_RUBY						\
    TOOL_ARGS

THIRD_PARTY_RUBY_IRB_DEPS :=					\
    $(call uniq,$(foreach x,$(THIRD_PARTY_RUBY_IRB_DIRECTDEPS),$($(x))))

o/$(MODE)/third_party/ruby/irb.pkg:				\
    o/$(MODE)/third_party/ruby/irb.main.o			\
    o/$(MODE)/third_party/ruby/irb_exports.o			\
    $(foreach x,$(THIRD_PARTY_RUBY_IRB_DIRECTDEPS),$($(x)_A).pkg)

o/$(MODE)/third_party/ruby/irb.dbg: | ruby.codegen

# Phase 1: Build without exports
o/$(MODE)/third_party/ruby/irb.pre.dbg:				\
    $(THIRD_PARTY_RUBY_IRB_DEPS)				\
    o/$(MODE)/third_party/ruby/irb.main.o			\
    $(foreach x,$(THIRD_PARTY_RUBY_EXTENSIONS),$($(x)_A))	\
    $(CRT)							\
    $(APE_NO_MODIFY_SELF)
	@$(APELINK)

o/$(MODE)/third_party/ruby/irb.pre.dbg: private			\
	LDFLAGS +=						\
		--whole-archive				\
		$(foreach x,$(THIRD_PARTY_RUBY_EXTENSIONS),$($(x)_A))	\
		--no-whole-archive

# Phase 3: Build final binary with exports
o/$(MODE)/third_party/ruby/irb.dbg:				\
    $(THIRD_PARTY_RUBY_IRB_DEPS)				\
    o/$(MODE)/third_party/ruby/irb.pkg				\
    o/$(MODE)/third_party/ruby/irb.main.o			\
    o/$(MODE)/third_party/ruby/irb_exports.o			\
    $(foreach x,$(THIRD_PARTY_RUBY_EXTENSIONS),$($(x)_A))	\
    $(CRT)							\
    $(APE_NO_MODIFY_SELF)
	@$(APELINK)

# Force linker to extract all extension object files from archives (weak symbols don't trigger extraction)
o/$(MODE)/third_party/ruby/irb.dbg: private			\
	LDFLAGS +=						\
		--whole-archive				\
		$(foreach x,$(THIRD_PARTY_RUBY_EXTENSIONS),$($(x)_A))	\
		--no-whole-archive

################################################################################
# irb.zipless

o/$(MODE)/third_party/ruby/irb.zipless.pkg:			\
    o/$(MODE)/third_party/ruby/irb.main.zipless.o		\
    o/$(MODE)/third_party/ruby/irb_exports.o			\
    $(foreach x,$(THIRD_PARTY_RUBY_IRB_DIRECTDEPS),$($(x)_A).pkg)

o/$(MODE)/third_party/ruby/irb.zipless.dbg: | ruby.codegen

o/$(MODE)/third_party/ruby/irb.zipless.dbg:			\
    $(THIRD_PARTY_RUBY_IRB_DEPS)				\
    o/$(MODE)/third_party/ruby/irb.zipless.pkg			\
    o/$(MODE)/third_party/ruby/irb.main.zipless.o		\
    o/$(MODE)/third_party/ruby/irb_exports.o			\
    $(foreach x,$(THIRD_PARTY_RUBY_EXTENSIONS),$($(x)_A))	\
    $(CRT)							\
    $(APE_NO_MODIFY_SELF)
	@$(APELINK)

o/$(MODE)/third_party/ruby/irb.zipless.dbg: private		\
	LDFLAGS +=						\
		--whole-archive				\
		$(foreach x,$(THIRD_PARTY_RUBY_EXTENSIONS),$($(x)_A))	\
		--no-whole-archive

THIRD_PARTY_RUBY_MINIRUBY_DIRECTDEPS =				\
    LIBC_CALLS							\
    LIBC_FMT							\
    LIBC_INTRIN							\
    LIBC_NEXGEN32E						\
    LIBC_STDIO							\
    LIBC_LOG							\
    LIBC_MEM							\
    LIBC_STR							\
    LIBC_SYSV							\
    LIBC_THREAD							\
    THIRD_PARTY_RUBY						\
    TOOL_ARGS

THIRD_PARTY_RUBY_MINIRUBY_DEPS :=				\
    $(call uniq,$(foreach x,$(THIRD_PARTY_RUBY_MINIRUBY_DIRECTDEPS),$($(x))))

# miniruby.zipless - filesystem paths only
o/$(MODE)/third_party/ruby/miniruby.zipless.pkg:		\
    o/$(MODE)/third_party/ruby/miniruby.main.zipless.o		\
    o/$(MODE)/third_party/ruby/miniruby_exports.o		\
    $(foreach x,$(THIRD_PARTY_RUBY_MINIRUBY_DIRECTDEPS),$($(x)_A).pkg)

o/$(MODE)/third_party/ruby/miniruby.zipless.dbg: | ruby.codegen

# Phase 1: Build without exports
o/$(MODE)/third_party/ruby/miniruby.zipless.pre.dbg:		\
    $(THIRD_PARTY_RUBY_MINIRUBY_DEPS)				\
    $(THIRD_PARTY_RUBY_EXT_MONITOR_A)				\
    $(THIRD_PARTY_RUBY_EXT_STRINGIO_A)				\
    $(THIRD_PARTY_RUBY_EXT_PATHNAME_A)				\
    o/$(MODE)/third_party/ruby/miniruby.main.zipless.o		\
    $(CRT)							\
    $(APE_NO_MODIFY_SELF)
	@$(APELINK)

o/$(MODE)/third_party/ruby/miniruby.zipless.pre.dbg: private	\
	LDFLAGS +=						\
		--whole-archive				\
		$(THIRD_PARTY_RUBY_EXT_MONITOR_A)	\
		$(THIRD_PARTY_RUBY_EXT_STRINGIO_A)	\
		$(THIRD_PARTY_RUBY_EXT_PATHNAME_A)	\
		--no-whole-archive

# Phase 3: Build final binary with exports
o/$(MODE)/third_party/ruby/miniruby.zipless.dbg:		\
    $(THIRD_PARTY_RUBY_MINIRUBY_DEPS)				\
    $(THIRD_PARTY_RUBY_EXT_MONITOR_A)				\
    $(THIRD_PARTY_RUBY_EXT_STRINGIO_A)				\
    $(THIRD_PARTY_RUBY_EXT_PATHNAME_A)				\
    o/$(MODE)/third_party/ruby/miniruby.zipless.pkg		\
    o/$(MODE)/third_party/ruby/miniruby.main.zipless.o		\
    o/$(MODE)/third_party/ruby/miniruby_exports.o		\
    $(CRT)							\
    $(APE_NO_MODIFY_SELF)
	@$(APELINK)

o/$(MODE)/third_party/ruby/miniruby.zipless.dbg: private	\
	LDFLAGS +=						\
		--whole-archive				\
		$(THIRD_PARTY_RUBY_EXT_MONITOR_A)	\
		$(THIRD_PARTY_RUBY_EXT_STRINGIO_A)	\
		$(THIRD_PARTY_RUBY_EXT_PATHNAME_A)	\
		--no-whole-archive

# miniruby - ZIP paths only
o/$(MODE)/third_party/ruby/miniruby.pkg:			\
    o/$(MODE)/third_party/ruby/miniruby.main.o			\
    o/$(MODE)/third_party/ruby/miniruby_exports.o		\
    $(foreach x,$(THIRD_PARTY_RUBY_MINIRUBY_DIRECTDEPS),$($(x)_A).pkg)

o/$(MODE)/third_party/ruby/miniruby.dbg: | ruby.codegen

# Phase 1: Build without exports
o/$(MODE)/third_party/ruby/miniruby.pre.dbg:			\
    $(THIRD_PARTY_RUBY_MINIRUBY_DEPS)				\
    $(THIRD_PARTY_RUBY_EXT_MONITOR_A)				\
    $(THIRD_PARTY_RUBY_EXT_STRINGIO_A)				\
    $(THIRD_PARTY_RUBY_EXT_PATHNAME_A)				\
    o/$(MODE)/third_party/ruby/miniruby.main.o			\
    $(CRT)							\
    $(APE_NO_MODIFY_SELF)
	@$(APELINK)

o/$(MODE)/third_party/ruby/miniruby.pre.dbg: private		\
	LDFLAGS +=						\
		--whole-archive				\
		$(THIRD_PARTY_RUBY_EXT_MONITOR_A)	\
		$(THIRD_PARTY_RUBY_EXT_STRINGIO_A)	\
		$(THIRD_PARTY_RUBY_EXT_PATHNAME_A)	\
		--no-whole-archive

# Phase 3: Build final binary with exports
o/$(MODE)/third_party/ruby/miniruby.dbg:			\
    $(THIRD_PARTY_RUBY_MINIRUBY_DEPS)				\
    $(THIRD_PARTY_RUBY_EXT_MONITOR_A)				\
    $(THIRD_PARTY_RUBY_EXT_STRINGIO_A)				\
    $(THIRD_PARTY_RUBY_EXT_PATHNAME_A)				\
    o/$(MODE)/third_party/ruby/miniruby.pkg			\
    o/$(MODE)/third_party/ruby/miniruby.main.o			\
    o/$(MODE)/third_party/ruby/miniruby_exports.o		\
    $(CRT)							\
    $(APE_NO_MODIFY_SELF)
	@$(APELINK)

o/$(MODE)/third_party/ruby/miniruby.dbg: private			\
	LDFLAGS +=						\
		--whole-archive				\
		$(THIRD_PARTY_RUBY_EXT_MONITOR_A)	\
		$(THIRD_PARTY_RUBY_EXT_STRINGIO_A)	\
		$(THIRD_PARTY_RUBY_EXT_PATHNAME_A)	\
		--no-whole-archive

# automate_mkdeps has been moved to third_party/mexican_toaster/
# See third_party/mexican_toaster/BUILD.mk for build rules

################################################################################

THIRD_PARTY_RUBY_SRCS =						\
    $(foreach x,$(THIRD_PARTY_RUBY_ARTIFACTS),$($(x)_SRCS))	\
    third_party/ruby/miniruby.main.c				\
    third_party/ruby/ruby.main.c				\
    third_party/ruby/irb.main.c

THIRD_PARTY_RUBY_LIBS = $(foreach x,$(THIRD_PARTY_RUBY_ARTIFACTS),$($(x)))
THIRD_PARTY_RUBY_HDRS = $(foreach x,$(THIRD_PARTY_RUBY_ARTIFACTS),$($(x)_HDRS))
THIRD_PARTY_RUBY_INCS = $(foreach x,$(THIRD_PARTY_RUBY_ARTIFACTS),$($(x)_INCS))
THIRD_PARTY_RUBY_OBJS = $(foreach x,$(THIRD_PARTY_RUBY_ARTIFACTS),$($(x)_OBJS))
$(THIRD_PARTY_RUBY_OBJS): third_party/ruby/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby
o/$(MODE)/third_party/ruby:					\
    ruby.codegen						\
    $(THIRD_PARTY_RUBY_LIBS)					\
    $(THIRD_PARTY_RUBY_BINS)					\
    $(THIRD_PARTY_RUBY_CHECKS)

# Include zoneinfo and terminfo in the ruby zip for portability
o/$(MODE)/third_party/ruby/ruby.a.zip: private ZIPFILES = usr/share/zoneinfo/* usr/share/terminfo/*
