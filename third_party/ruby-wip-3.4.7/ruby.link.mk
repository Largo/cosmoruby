#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘


o/$(MODE)/third_party/ruby/ruby.dbg:				\
        $(THIRD_PARTY_RUBY_RUBY_DEPS)				\
        o/$(MODE)/third_party/ruby/ruby.pkg			\
        o/$(MODE)/third_party/ruby/ruby.main.o			\
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
    $(foreach x,$(THIRD_PARTY_RUBY_IRB_DIRECTDEPS),$($(x)_A).pkg)

o/$(MODE)/third_party/ruby/irb.dbg:				\
    $(THIRD_PARTY_RUBY_IRB_DEPS)				\
    o/$(MODE)/third_party/ruby/irb.pkg				\
    o/$(MODE)/third_party/ruby/irb.main.o			\
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
# miniruby (lean Ruby without extensions for faster builds/testing)

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

o/$(MODE)/third_party/ruby/miniruby.pkg:			\
    o/$(MODE)/third_party/ruby/miniruby.main.o			\
    $(foreach x,$(THIRD_PARTY_RUBY_MINIRUBY_DIRECTDEPS),$($(x)_A).pkg)

o/$(MODE)/third_party/ruby/miniruby.dbg:			\
    $(THIRD_PARTY_RUBY_MINIRUBY_DEPS)				\
    o/$(MODE)/third_party/ruby/miniruby.pkg			\
    o/$(MODE)/third_party/ruby/miniruby.main.o			\
    $(CRT)							\
    $(APE_NO_MODIFY_SELF)
	@$(APELINK)

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
    $(THIRD_PARTY_RUBY_LIBS)					\
    $(THIRD_PARTY_RUBY_BINS)					\
    $(THIRD_PARTY_RUBY_CHECKS)

# Include zoneinfo and terminfo in the ruby zip for portability
o/$(MODE)/third_party/ruby/ruby.a.zip: private ZIPFILES = usr/share/zoneinfo/* usr/share/terminfo/*
