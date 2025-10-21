#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ─────────────────┘

#
# SYNOPSIS
#
#   Actually Portable Ruby Tutorial
#
# DESCRIPTION
#
#   This tutorial demonstrates how to compile Ruby apps as tiny
#   static multiplatform APE executables using Cosmopolitan,
#   which is a BSD-style multitenant codebase
#
# GETTING STARTED
#
#   # run these commands after cloning the cosmo repo on linux
#   $ make -j8 o//examples/rubyapp/rubyapp
#   $ o//examples/rubyapp/rubyapp
#   cosmopolitan is cool with Ruby!
#
# HOW IT WORKS
#
#   $ rubyobj -m -o rubyapp.o rubyapp.rb
#   $ ld -static -nostdlib -T o//ape/ape.lds ape.o crt.o \
#       rubyapp.o \
#       cosmopolitan-ruby.a \
#       cosmopolitan.a
#   $ ./rubyapp
#   cosmopolitan is cool with Ruby!

PKGS           += RUBYAPP
RUBYAPP        = $(RUBYAPP_DEPS) o/$(MODE)/examples/rubyapp/rubyapp.a
RUBYAPP_COMS   = o/$(MODE)/examples/rubyapp/rubyapp
RUBYAPP_BINS   = $(RUBYAPP_COMS) $(RUBYAPP_COMS:%=%.dbg)

# Specify our Cosmopolitan library dependencies
# THIRD_PARTY_RUBY provides the Ruby interpreter and standard library
RUBYAPP_DIRECTDEPS = \
    LIBC_CALLS \
    LIBC_FMT \
    LIBC_INTRIN \
    LIBC_NEXGEN32E \
    LIBC_STDIO \
    LIBC_LOG \
    LIBC_MEM \
    LIBC_STR \
    LIBC_SYSV \
    LIBC_THREAD \
    THIRD_PARTY_RUBY \
    TOOL_ARGS

# Compute the transitive closure of dependencies
RUBYAPP_DEPS := $(call uniq,$(foreach x,$(RUBYAPP_DIRECTDEPS),$($(x))))

# Package checking and dependency resolution
o/$(MODE)/examples/rubyapp/rubyapp.pkg: \
        o/$(MODE)/examples/rubyapp/rubyapp.main.o \
        $(foreach x,$(RUBYAPP_DIRECTDEPS),$($(x)_A).pkg)

# Link the APE executable
o/$(MODE)/examples/rubyapp/rubyapp.dbg: \
        $(RUBYAPP_DEPS) \
        o/$(MODE)/examples/rubyapp/rubyapp.pkg \
        o/$(MODE)/examples/rubyapp/rubyapp.main.o \
        $(CRT) \
        $(APE_NO_MODIFY_SELF)
	@$(APELINK)

# By convention we want to be able to say `make -j8 o//examples/rubyapp`
# and have it build all targets the package defines.
.PHONY: o/$(MODE)/examples/rubyapp
o/$(MODE)/examples/rubyapp: \
        o/$(MODE)/examples/rubyapp/rubyapp \
        o/$(MODE)/examples/rubyapp/rubyapp.dbg