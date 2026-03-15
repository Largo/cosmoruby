#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ─────────────────┘

#
# SYNOPSIS
#
#   Actually Portable Ruby Examples
#
# DESCRIPTION
#
#   Two examples of building Ruby apps as APE executables:
#
#   1. ruby_c_api_tiny_demo: Demonstrates a tiny subset of the Ruby
#      C embedding API (rb_eval_string, ruby_version, etc.)
#
#   2. dumb_example_app: Demonstrates the rubyobj workflow — compiling
#      a .rb script to ISEQ bytecode and linking it into a standalone
#      APE binary.
#
# GETTING STARTED
#
#   $ make -j8 o//examples/rubyapps
#   $ o//examples/rubyapps/ruby_c_api_tiny_demo
#   $ o//examples/rubyapps/dumb_example_app
#
# HOW RUBYOBJ WORKS
#
#   $ o//third_party/ruby/rubyobj -m -o app.o app.rb
#   $ ld -static -nostdlib -T o//ape/ape.lds ape.o crt.o \
#       app.o launch.o cosmopolitan-ruby.a cosmopolitan.a
#   $ ./app

# Derive directory from this file's location
RUBYAPPS_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))

PKGS += EXAMPLES_RUBYAPPS

# Shared dependencies for both examples
EXAMPLES_RUBYAPPS_DIRECTDEPS =					\
    LIBC_CALLS							\
    LIBC_FMT							\
    LIBC_INTRIN							\
    LIBC_NEXGEN32E						\
    LIBC_RUNTIME						\
    LIBC_STDIO							\
    LIBC_LOG							\
    LIBC_MEM							\
    LIBC_STR							\
    LIBC_SYSV							\
    LIBC_THREAD							\
    THIRD_PARTY_RUBY						\
    TOOL_ARGS

EXAMPLES_RUBYAPPS_DEPS :=					\
    $(call uniq,$(foreach x,$(EXAMPLES_RUBYAPPS_DIRECTDEPS),$($(x))))

################################################################################
# ruby_c_api_tiny_demo — C program that embeds the Ruby VM directly

# Ruby include paths for the C API demo
o/$(MODE)/$(RUBYAPPS_DIR)/ruby_c_api_tiny_demo.main.o: private	\
    CFLAGS +=							\
            -Ithird_party/ruby/include				\
            -Ithird_party/ruby

o/$(MODE)/$(RUBYAPPS_DIR)/ruby_c_api_tiny_demo.pkg:		\
        o/$(MODE)/$(RUBYAPPS_DIR)/ruby_c_api_tiny_demo.main.o	\
        $(foreach x,$(EXAMPLES_RUBYAPPS_DIRECTDEPS),$($(x)_A).pkg)

o/$(MODE)/$(RUBYAPPS_DIR)/ruby_c_api_tiny_demo.dbg:		\
        $(EXAMPLES_RUBYAPPS_DEPS)				\
        o/$(MODE)/$(RUBYAPPS_DIR)/ruby_c_api_tiny_demo.pkg	\
        o/$(MODE)/$(RUBYAPPS_DIR)/ruby_c_api_tiny_demo.main.o	\
        $(CRT)							\
        $(APE_NO_MODIFY_SELF)
	@$(APELINK)

################################################################################
# dumb_example_app — .rb compiled to ISEQ via rubyobj

RUBYOBJ = o/$(MODE)/third_party/ruby/rubyobj

# Compile .rb to .o using rubyobj
o/$(MODE)/$(RUBYAPPS_DIR)/dumb_example_app.o:			\
        $(RUBYAPPS_DIR)/dumb_example_app.rb			\
        $(RUBYOBJ)
	@$(RUBYOBJ) -m -C2 -P.ruby -o $@ $<

# Link the rubyobj-built app with launch.o
o/$(MODE)/$(RUBYAPPS_DIR)/dumb_example_app.dbg:			\
        $(EXAMPLES_RUBYAPPS_DEPS)				\
        o/$(MODE)/$(RUBYAPPS_DIR)/dumb_example_app.o		\
        o/$(MODE)/third_party/ruby/launch.o			\
        $(CRT)							\
        $(APE_NO_MODIFY_SELF)
	@$(APELINK)

################################################################################

.PHONY: o/$(MODE)/$(RUBYAPPS_DIR)
o/$(MODE)/$(RUBYAPPS_DIR):					\
        o/$(MODE)/$(RUBYAPPS_DIR)/ruby_c_api_tiny_demo		\
        o/$(MODE)/$(RUBYAPPS_DIR)/ruby_c_api_tiny_demo.dbg	\
        o/$(MODE)/$(RUBYAPPS_DIR)/dumb_example_app		\
        o/$(MODE)/$(RUBYAPPS_DIR)/dumb_example_app.dbg
