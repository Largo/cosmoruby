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

# In plugin mode, ensure encoding archives are built before ruby
ifeq ($(RUBY_EXTSTATIC),0)
o/$(MODE)/third_party/ruby/ruby.dbg: | ruby.plugins
else ifeq ($(RUBY_SLIM_STATIC),1)
o/$(MODE)/third_party/ruby/ruby.dbg: | ruby.plugins
endif

RUBY_LINK_EXT_ARCHIVES := $(foreach x,$(THIRD_PARTY_RUBY_EXTENSIONS),$($(x)_A))
RUBY_UNDEFS_DEPS := $(if $(strip $(RUBY_LINK_EXT_ARCHIVES)),$(RUBY_LINK_EXT_ARCHIVES),$(RUBY_PLUGIN_ARCHIVES))
ifneq ($(strip $(RUBY_UNDEFS_DEPS)),)
RUBY_UNDEFS_ARGS = o/$(MODE)/third_party/ruby/ruby.undefs.args
RUBY_UNDEFS_FLAGS = @$(RUBY_UNDEFS_ARGS)
RUBY_WHOLE_ARCHIVE_EXTS = $(if $(strip $(RUBY_LINK_EXT_ARCHIVES)),--whole-archive $(RUBY_LINK_EXT_ARCHIVES) --no-whole-archive,)
else
RUBY_UNDEFS_ARGS =
RUBY_UNDEFS_DEPS =
RUBY_UNDEFS_FLAGS =
RUBY_WHOLE_ARCHIVE_EXTS =
endif
RUBY_UNDEFS_ORDER = $(if $(RUBY_UNDEFS_ARGS),| $(RUBY_UNDEFS_ARGS))

################################################################################
# YJIT Rust Library Linkage
#
# YJIT_LIBOBJ is defined in yjit/BUILD.mk when RUBY_YJIT_ENABLED=1
# We need to link it with --whole-archive to ensure all symbols are included
#
# IMPORTANT: YJIT_LIBOBJ must be an ORDER-ONLY prerequisite (after |) because
# APELINK automatically passes regular prerequisites to the linker. If we add
# it as a regular prerequisite AND in LDFLAGS, it gets linked twice causing
# "multiple definition" errors.
ifeq ($(RUBY_YJIT_ENABLED),1)
RUBY_YJIT_LINK_FLAGS = --whole-archive $(YJIT_LIBOBJ) --no-whole-archive
RUBY_YJIT_ORDER_ONLY = $(YJIT_LIBOBJ)
else
RUBY_YJIT_LINK_FLAGS =
RUBY_YJIT_ORDER_ONLY =
endif

# Combined order-only prerequisites (undefs + yjit)
# This creates a single | followed by all order-only deps
RUBY_ALL_ORDER_ONLY_DEPS = $(strip $(RUBY_UNDEFS_ARGS) $(RUBY_YJIT_ORDER_ONLY))
RUBY_ALL_ORDER_ONLY = $(if $(RUBY_ALL_ORDER_ONLY_DEPS),| $(RUBY_ALL_ORDER_ONLY_DEPS))

# Phase 1: Build without exports to extract symbols
# Note: Does NOT depend on ruby.pkg (which includes exports.o) to break circular dependency
o/$(MODE)/third_party/ruby/ruby.pre.dbg:			\
        $(THIRD_PARTY_RUBY_RUBY_DEPS)				\
        o/$(MODE)/third_party/ruby/ruby.main.o			\
        $(RUBY_LINK_EXT_ARCHIVES)				\
        $(CRT)							\
        $(APE_NO_MODIFY_SELF)					\
        | $(RUBY_YJIT_ORDER_ONLY)
	@$(APELINK)

o/$(MODE)/third_party/ruby/ruby.pre.dbg: private		\
	LDFLAGS +=						\
		$(RUBY_WHOLE_ARCHIVE_EXTS)			\
		$(RUBY_YJIT_LINK_FLAGS)

# Force linker to keep export table symbols (prevents --gc-sections from deleting them)
RUBY_EXPORT_UNDEFS = \
	-u __cosmo_exports_start \
	-u __cosmo_exports_end \
	-u __cosmo_exports_names_start \
	-u __cosmo_exports_names_end

ifneq ($(strip $(RUBY_UNDEFS_DEPS)),)
$(RUBY_UNDEFS_ARGS): third_party/ruby/generate_undefs.sh	\
		$(RUBY_UNDEFS_DEPS)
	@NM="$(NM)" sh third_party/ruby/generate_undefs.sh $@ \
		$(RUBY_UNDEFS_DEPS)
endif

# Phase 2: Generate exports from pre-built binary (ruby.compile.mk has the rule)

# Phase 3: Build stage1 binary with pre-export table
o/$(MODE)/third_party/ruby/ruby.stage1.dbg:			\
        $(THIRD_PARTY_RUBY_RUBY_DEPS)				\
        o/$(MODE)/third_party/ruby/ruby.main.o			\
        o/$(MODE)/third_party/ruby/ruby_exports.pre.o		\
        $(RUBY_LINK_EXT_ARCHIVES)				\
        $(CRT)							\
        $(APE_NO_MODIFY_SELF)					\
        $(RUBY_ALL_ORDER_ONLY)
	@$(APELINK)

# Force linker to extract all extension object files from archives (weak symbols don't trigger extraction)
o/$(MODE)/third_party/ruby/ruby.stage1.dbg: private		\
	LDFLAGS +=						\
		$(RUBY_UNDEFS_FLAGS)				\
		$(RUBY_EXPORT_UNDEFS)				\
		$(RUBY_WHOLE_ARCHIVE_EXTS)			\
		$(RUBY_YJIT_LINK_FLAGS)

# Phase 4: Build stage2 binary with exports generated from stage1
o/$(MODE)/third_party/ruby/ruby.stage2.dbg:			\
        $(THIRD_PARTY_RUBY_RUBY_DEPS)				\
        o/$(MODE)/third_party/ruby/ruby.main.o			\
        o/$(MODE)/third_party/ruby/ruby_exports.stage1.o	\
        $(RUBY_LINK_EXT_ARCHIVES)				\
        $(CRT)							\
        $(APE_NO_MODIFY_SELF)					\
        $(RUBY_ALL_ORDER_ONLY)
	@$(APELINK)

o/$(MODE)/third_party/ruby/ruby.stage2.dbg: private		\
	LDFLAGS +=						\
		$(RUBY_UNDEFS_FLAGS)				\
		$(RUBY_EXPORT_UNDEFS)				\
		$(RUBY_WHOLE_ARCHIVE_EXTS)			\
		$(RUBY_YJIT_LINK_FLAGS)

# Phase 5: Build final binary with exports generated from stage2
o/$(MODE)/third_party/ruby/ruby.dbg:				\
        $(THIRD_PARTY_RUBY_RUBY_DEPS)				\
        o/$(MODE)/third_party/ruby/ruby.pkg			\
        o/$(MODE)/third_party/ruby/ruby.main.o			\
        o/$(MODE)/third_party/ruby/ruby_exports.o		\
        $(RUBY_LINK_EXT_ARCHIVES)				\
        $(CRT)							\
        $(APE_NO_MODIFY_SELF)					\
        $(RUBY_ALL_ORDER_ONLY)
	@$(APELINK)

o/$(MODE)/third_party/ruby/ruby.dbg: private			\
	LDFLAGS +=						\
		$(RUBY_UNDEFS_FLAGS)				\
		$(RUBY_EXPORT_UNDEFS)				\
		$(RUBY_WHOLE_ARCHIVE_EXTS)			\
		$(RUBY_YJIT_LINK_FLAGS)

################################################################################
# ruby.zipless

o/$(MODE)/third_party/ruby/ruby.zipless.pkg:			\
    o/$(MODE)/third_party/ruby/ruby.main.zipless.o		\
    o/$(MODE)/third_party/ruby/loadpath.zipless.o		\
    $(foreach x,$(THIRD_PARTY_RUBY_RUBY_DIRECTDEPS),$($(x)_A).pkg)

o/$(MODE)/third_party/ruby/ruby.zipless.dbg: | ruby.codegen

# In plugin mode, ensure encoding archives are built before ruby.zipless
ifeq ($(RUBY_EXTSTATIC),0)
o/$(MODE)/third_party/ruby/ruby.zipless.dbg: | ruby.plugins
else ifeq ($(RUBY_SLIM_STATIC),1)
o/$(MODE)/third_party/ruby/ruby.zipless.dbg: | ruby.plugins
endif

o/$(MODE)/third_party/ruby/ruby.zipless.dbg:			\
        $(THIRD_PARTY_RUBY_RUBY_DEPS)				\
        o/$(MODE)/third_party/ruby/ruby.zipless.pkg		\
        o/$(MODE)/third_party/ruby/ruby.main.zipless.o		\
        o/$(MODE)/third_party/ruby/loadpath.zipless.o		\
        o/$(MODE)/third_party/ruby/ruby_exports.o		\
        $(RUBY_LINK_EXT_ARCHIVES)				\
        $(CRT)							\
        $(APE_NO_MODIFY_SELF)					\
        $(RUBY_ALL_ORDER_ONLY)
	@$(APELINK)

o/$(MODE)/third_party/ruby/ruby.zipless.dbg: private		\
	LDFLAGS +=						\
		$(RUBY_UNDEFS_FLAGS)				\
		$(RUBY_EXPORT_UNDEFS)				\
		$(RUBY_WHOLE_ARCHIVE_EXTS)			\
		$(RUBY_YJIT_LINK_FLAGS)

################################################################################
# irb

THIRD_PARTY_RUBY_IRB_DIRECTDEPS =				\
    LIBC_CALLS							\
    LIBC_FMT							\
    LIBC_INTRIN							\
    LIBC_LOG							\
    LIBC_NEXGEN32E						\
    LIBC_RUNTIME						\
    LIBC_STDIO							\
    LIBC_MEM							\
    LIBC_STR							\
    LIBC_SYSV							\
    THIRD_PARTY_MIMALLOC					\
    THIRD_PARTY_RUBY						\
    TOOL_ARGS

THIRD_PARTY_RUBY_IRB_DEPS :=					\
    $(call uniq,$(foreach x,$(THIRD_PARTY_RUBY_IRB_DIRECTDEPS),$($(x))))

o/$(MODE)/third_party/ruby/irb.pkg:				\
    o/$(MODE)/third_party/ruby/irb.main.o			\
    o/$(MODE)/third_party/ruby/irb_exports.o			\
    $(foreach x,$(THIRD_PARTY_RUBY_IRB_DIRECTDEPS),$($(x)_A).pkg)

o/$(MODE)/third_party/ruby/irb.dbg: | ruby.codegen

# In plugin mode, ensure encoding archives are built before irb
ifeq ($(RUBY_EXTSTATIC),0)
o/$(MODE)/third_party/ruby/irb.dbg: | ruby.plugins
else ifeq ($(RUBY_SLIM_STATIC),1)
o/$(MODE)/third_party/ruby/irb.dbg: | ruby.plugins
endif

# Phase 1: Build without exports
o/$(MODE)/third_party/ruby/irb.pre.dbg:				\
    $(THIRD_PARTY_RUBY_IRB_DEPS)				\
    o/$(MODE)/third_party/ruby/irb.main.o			\
    $(RUBY_LINK_EXT_ARCHIVES)				\
    $(CRT)							\
    $(APE_NO_MODIFY_SELF)					\
    | $(RUBY_YJIT_ORDER_ONLY)
	@$(APELINK)

o/$(MODE)/third_party/ruby/irb.pre.dbg: private			\
	LDFLAGS +=						\
		$(RUBY_WHOLE_ARCHIVE_EXTS)			\
		$(RUBY_YJIT_LINK_FLAGS)

# Phase 3: Build stage1 binary with pre-export table
o/$(MODE)/third_party/ruby/irb.stage1.dbg:			\
    $(THIRD_PARTY_RUBY_IRB_DEPS)				\
    o/$(MODE)/third_party/ruby/irb.main.o			\
    o/$(MODE)/third_party/ruby/irb_exports.pre.o		\
    $(RUBY_LINK_EXT_ARCHIVES)				\
    $(CRT)							\
    $(APE_NO_MODIFY_SELF)					\
    $(RUBY_ALL_ORDER_ONLY)
	@$(APELINK)

# Force linker to extract all extension object files from archives (weak symbols don't trigger extraction)
o/$(MODE)/third_party/ruby/irb.stage1.dbg: private		\
	LDFLAGS +=						\
		$(RUBY_UNDEFS_FLAGS)				\
		$(RUBY_EXPORT_UNDEFS)				\
		$(RUBY_WHOLE_ARCHIVE_EXTS)			\
		$(RUBY_YJIT_LINK_FLAGS)

# Phase 4: Build stage2 binary with exports generated from stage1
o/$(MODE)/third_party/ruby/irb.stage2.dbg:			\
    $(THIRD_PARTY_RUBY_IRB_DEPS)				\
    o/$(MODE)/third_party/ruby/irb.main.o			\
    o/$(MODE)/third_party/ruby/irb_exports.stage1.o		\
    $(RUBY_LINK_EXT_ARCHIVES)				\
    $(CRT)							\
    $(APE_NO_MODIFY_SELF)					\
    $(RUBY_ALL_ORDER_ONLY)
	@$(APELINK)

# Force linker to extract all extension object files from archives (weak symbols don't trigger extraction)
o/$(MODE)/third_party/ruby/irb.stage2.dbg: private		\
	LDFLAGS +=						\
		$(RUBY_UNDEFS_FLAGS)				\
		$(RUBY_EXPORT_UNDEFS)				\
		$(RUBY_WHOLE_ARCHIVE_EXTS)			\
		$(RUBY_YJIT_LINK_FLAGS)

# Phase 5: Build final binary with exports generated from stage2
o/$(MODE)/third_party/ruby/irb.dbg:				\
    $(THIRD_PARTY_RUBY_IRB_DEPS)				\
    o/$(MODE)/third_party/ruby/irb.pkg				\
    o/$(MODE)/third_party/ruby/irb.main.o			\
    o/$(MODE)/third_party/ruby/irb_exports.o			\
    $(RUBY_LINK_EXT_ARCHIVES)				\
    $(CRT)							\
    $(APE_NO_MODIFY_SELF)					\
    $(RUBY_ALL_ORDER_ONLY)
	@$(APELINK)

o/$(MODE)/third_party/ruby/irb.dbg: private			\
	LDFLAGS +=						\
		$(RUBY_UNDEFS_FLAGS)				\
		$(RUBY_EXPORT_UNDEFS)				\
		$(RUBY_WHOLE_ARCHIVE_EXTS)			\
		$(RUBY_YJIT_LINK_FLAGS)

################################################################################
# irb.zipless

o/$(MODE)/third_party/ruby/irb.zipless.pkg:			\
    o/$(MODE)/third_party/ruby/irb.main.zipless.o		\
    o/$(MODE)/third_party/ruby/loadpath.zipless.o		\
    o/$(MODE)/third_party/ruby/irb_exports.o			\
    $(foreach x,$(THIRD_PARTY_RUBY_IRB_DIRECTDEPS),$($(x)_A).pkg)

o/$(MODE)/third_party/ruby/irb.zipless.dbg: | ruby.codegen

# In plugin mode, ensure encoding archives are built before irb.zipless
ifeq ($(RUBY_EXTSTATIC),0)
o/$(MODE)/third_party/ruby/irb.zipless.dbg: | ruby.plugins
else ifeq ($(RUBY_SLIM_STATIC),1)
o/$(MODE)/third_party/ruby/irb.zipless.dbg: | ruby.plugins
endif

o/$(MODE)/third_party/ruby/irb.zipless.dbg:			\
    $(THIRD_PARTY_RUBY_IRB_DEPS)				\
    o/$(MODE)/third_party/ruby/irb.zipless.pkg			\
    o/$(MODE)/third_party/ruby/irb.main.zipless.o		\
    o/$(MODE)/third_party/ruby/loadpath.zipless.o		\
    o/$(MODE)/third_party/ruby/irb_exports.o			\
    $(RUBY_LINK_EXT_ARCHIVES)				\
    $(CRT)							\
    $(APE_NO_MODIFY_SELF)					\
    $(RUBY_ALL_ORDER_ONLY)
	@$(APELINK)

o/$(MODE)/third_party/ruby/irb.zipless.dbg: private		\
	LDFLAGS +=						\
		$(RUBY_UNDEFS_FLAGS)				\
		$(RUBY_EXPORT_UNDEFS)				\
		$(RUBY_WHOLE_ARCHIVE_EXTS)			\
		$(RUBY_YJIT_LINK_FLAGS)

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
    THIRD_PARTY_MIMALLOC					\
    THIRD_PARTY_RUBY						\
    TOOL_ARGS

THIRD_PARTY_RUBY_MINIRUBY_DEPS :=				\
    $(call uniq,$(foreach x,$(THIRD_PARTY_RUBY_MINIRUBY_DIRECTDEPS),$($(x))))

MINIRUBY_LINK_EXT_ARCHIVES := $(foreach x,$(THIRD_PARTY_RUBY_MINIRUBY_EXTENSIONS),$($(x)_A))
ifneq ($(strip $(MINIRUBY_LINK_EXT_ARCHIVES)),)
MINIRUBY_UNDEFS_ARGS = o/$(MODE)/third_party/ruby/miniruby.undefs.args
MINIRUBY_UNDEFS_DEPS = $(MINIRUBY_LINK_EXT_ARCHIVES)
MINIRUBY_UNDEFS_FLAGS = @$(MINIRUBY_UNDEFS_ARGS)
MINIRUBY_WHOLE_ARCHIVE_EXTS = --whole-archive $(MINIRUBY_LINK_EXT_ARCHIVES) --no-whole-archive
else
MINIRUBY_UNDEFS_ARGS =
MINIRUBY_UNDEFS_DEPS =
MINIRUBY_UNDEFS_FLAGS =
MINIRUBY_WHOLE_ARCHIVE_EXTS =
endif
MINIRUBY_UNDEFS_ORDER = $(if $(MINIRUBY_UNDEFS_ARGS),| $(MINIRUBY_UNDEFS_ARGS))

# Combined order-only prerequisites for miniruby (undefs + yjit)
MINIRUBY_ALL_ORDER_ONLY_DEPS = $(strip $(MINIRUBY_UNDEFS_ARGS) $(RUBY_YJIT_ORDER_ONLY))
MINIRUBY_ALL_ORDER_ONLY = $(if $(MINIRUBY_ALL_ORDER_ONLY_DEPS),| $(MINIRUBY_ALL_ORDER_ONLY_DEPS))

# miniruby.zipless - filesystem paths only
o/$(MODE)/third_party/ruby/miniruby.zipless.pkg:		\
    o/$(MODE)/third_party/ruby/miniruby.main.zipless.o		\
    o/$(MODE)/third_party/ruby/loadpath.zipless.o		\
    o/$(MODE)/third_party/ruby/miniruby_exports.o		\
    $(foreach x,$(THIRD_PARTY_RUBY_MINIRUBY_DIRECTDEPS),$($(x)_A).pkg)

o/$(MODE)/third_party/ruby/miniruby.zipless.dbg: | ruby.codegen

# Phase 1: Build without exports
o/$(MODE)/third_party/ruby/miniruby.zipless.pre.dbg:		\
    $(THIRD_PARTY_RUBY_MINIRUBY_DEPS)				\
    $(MINIRUBY_LINK_EXT_ARCHIVES)				\
    o/$(MODE)/third_party/ruby/miniruby.main.zipless.o		\
    o/$(MODE)/third_party/ruby/loadpath.zipless.o		\
    $(CRT)							\
    $(APE_NO_MODIFY_SELF)					\
    | $(RUBY_YJIT_ORDER_ONLY)
	@$(APELINK)

o/$(MODE)/third_party/ruby/miniruby.zipless.pre.dbg: private	\
	LDFLAGS +=						\
		$(MINIRUBY_UNDEFS_FLAGS)			\
		$(MINIRUBY_WHOLE_ARCHIVE_EXTS)			\
		$(RUBY_YJIT_LINK_FLAGS)

# Phase 3: Build final binary with exports
o/$(MODE)/third_party/ruby/miniruby.zipless.dbg:		\
    $(THIRD_PARTY_RUBY_MINIRUBY_DEPS)				\
    $(MINIRUBY_LINK_EXT_ARCHIVES)				\
    o/$(MODE)/third_party/ruby/miniruby.zipless.pkg		\
    o/$(MODE)/third_party/ruby/miniruby.main.zipless.o		\
    o/$(MODE)/third_party/ruby/loadpath.zipless.o		\
    o/$(MODE)/third_party/ruby/miniruby_exports.o		\
    $(CRT)							\
    $(APE_NO_MODIFY_SELF)					\
    $(MINIRUBY_ALL_ORDER_ONLY)
	@$(APELINK)

o/$(MODE)/third_party/ruby/miniruby.zipless.dbg: private	\
	LDFLAGS +=						\
		$(MINIRUBY_UNDEFS_FLAGS)			\
		$(RUBY_EXPORT_UNDEFS)				\
		$(MINIRUBY_WHOLE_ARCHIVE_EXTS)			\
		$(RUBY_YJIT_LINK_FLAGS)

# miniruby - ZIP paths only
o/$(MODE)/third_party/ruby/miniruby.pkg:			\
    o/$(MODE)/third_party/ruby/miniruby.main.o			\
    o/$(MODE)/third_party/ruby/miniruby_exports.o		\
    $(foreach x,$(THIRD_PARTY_RUBY_MINIRUBY_DIRECTDEPS),$($(x)_A).pkg)

o/$(MODE)/third_party/ruby/miniruby.dbg: | ruby.codegen

# Phase 1: Build without exports
o/$(MODE)/third_party/ruby/miniruby.pre.dbg:			\
    $(THIRD_PARTY_RUBY_MINIRUBY_DEPS)				\
    $(MINIRUBY_LINK_EXT_ARCHIVES)				\
    o/$(MODE)/third_party/ruby/miniruby.main.o			\
    $(CRT)							\
    $(APE_NO_MODIFY_SELF)					\
    | $(RUBY_YJIT_ORDER_ONLY)
	@$(APELINK)

o/$(MODE)/third_party/ruby/miniruby.pre.dbg: private		\
	LDFLAGS +=						\
		$(MINIRUBY_WHOLE_ARCHIVE_EXTS)			\
		$(RUBY_YJIT_LINK_FLAGS)

ifneq ($(strip $(MINIRUBY_UNDEFS_DEPS)),)
$(MINIRUBY_UNDEFS_ARGS): third_party/ruby/generate_undefs.sh	\
		$(MINIRUBY_UNDEFS_DEPS)
	@NM="$(NM)" sh third_party/ruby/generate_undefs.sh $@ \
		$(MINIRUBY_UNDEFS_DEPS)
endif

# Phase 3: Build stage1 binary with pre-export table
o/$(MODE)/third_party/ruby/miniruby.stage1.dbg:		\
    $(THIRD_PARTY_RUBY_MINIRUBY_DEPS)				\
    $(MINIRUBY_LINK_EXT_ARCHIVES)				\
    o/$(MODE)/third_party/ruby/miniruby.main.o			\
    o/$(MODE)/third_party/ruby/miniruby_exports.pre.o		\
    $(CRT)							\
    $(APE_NO_MODIFY_SELF)					\
    $(MINIRUBY_ALL_ORDER_ONLY)
	@$(APELINK)

o/$(MODE)/third_party/ruby/miniruby.stage1.dbg: private		\
	LDFLAGS +=						\
		$(MINIRUBY_UNDEFS_FLAGS)			\
		$(RUBY_EXPORT_UNDEFS)				\
		$(MINIRUBY_WHOLE_ARCHIVE_EXTS)			\
		$(RUBY_YJIT_LINK_FLAGS)

# Phase 4: Build stage2 binary with exports generated from stage1
o/$(MODE)/third_party/ruby/miniruby.stage2.dbg:		\
    $(THIRD_PARTY_RUBY_MINIRUBY_DEPS)				\
    $(MINIRUBY_LINK_EXT_ARCHIVES)				\
    o/$(MODE)/third_party/ruby/miniruby.main.o			\
    o/$(MODE)/third_party/ruby/miniruby_exports.stage1.o	\
    $(CRT)							\
    $(APE_NO_MODIFY_SELF)					\
    $(MINIRUBY_ALL_ORDER_ONLY)
	@$(APELINK)

o/$(MODE)/third_party/ruby/miniruby.stage2.dbg: private		\
	LDFLAGS +=						\
		$(MINIRUBY_UNDEFS_FLAGS)			\
		$(RUBY_EXPORT_UNDEFS)				\
		$(MINIRUBY_WHOLE_ARCHIVE_EXTS)			\
		$(RUBY_YJIT_LINK_FLAGS)

# Phase 5: Build final binary with exports generated from stage2
o/$(MODE)/third_party/ruby/miniruby.dbg:			\
    $(THIRD_PARTY_RUBY_MINIRUBY_DEPS)				\
    $(MINIRUBY_LINK_EXT_ARCHIVES)				\
    o/$(MODE)/third_party/ruby/miniruby.pkg			\
    o/$(MODE)/third_party/ruby/miniruby.main.o			\
    o/$(MODE)/third_party/ruby/miniruby_exports.o		\
    $(CRT)							\
    $(APE_NO_MODIFY_SELF)					\
    $(MINIRUBY_ALL_ORDER_ONLY)
	@$(APELINK)

o/$(MODE)/third_party/ruby/miniruby.dbg: private		\
	LDFLAGS +=						\
		$(MINIRUBY_UNDEFS_FLAGS)			\
		$(RUBY_EXPORT_UNDEFS)				\
		$(MINIRUBY_WHOLE_ARCHIVE_EXTS)			\
		$(RUBY_YJIT_LINK_FLAGS)

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
