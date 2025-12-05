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

# Detect preferred Ruby interpreter for build tooling.
# Favor a prebuilt Cosmopolitan ruby.com, fall back to system ruby.

COSMO_RUBY_CANDIDATES :=					\
	$(abspath o/$(MODE)/third_party/ruby/ruby.com)		\
	$(abspath o/default/third_party/ruby/ruby.com)		\
	$(abspath o/third_party/ruby/ruby.com)

COSMO_RUBY ?= $(firstword $(foreach path,$(COSMO_RUBY_CANDIDATES),$(if $(wildcard $(path)),$(path))))

HOST_RUBY ?= $(if $(COSMO_RUBY),$(COSMO_RUBY),$(strip $(shell command -v ruby 2>/dev/null)))
# HOST_RUBY ?= $(strip $(shell command -v ruby 2>/dev/null))

ifeq ($(strip $(HOST_RUBY)),)
$(error No Ruby interpreter found. Build requires ruby.com or system ruby on PATH.)
endif

export COSMO_RUBY HOST_RUBY
