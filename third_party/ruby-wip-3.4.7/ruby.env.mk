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
$(error No Ruby interpreter found. Build requires ruby.com or system ruby 3.4.7 on PATH.)
endif

# Verify Ruby version matches exactly (3.4.7) to avoid rbconfig.rb mismatches
# Only check if using system Ruby (not CosmoRuby which has version baked in)
ifeq ($(COSMO_RUBY),)
RUBY_VERSION_CHECK := $(shell $(HOST_RUBY) -e 'puts RUBY_VERSION' 2>/dev/null)
ifneq ($(RUBY_VERSION_CHECK),3.4.7)
$(error System Ruby version is $(RUBY_VERSION_CHECK), but CosmoRuby 3.4.7 build requires exactly 3.4.7. Install with: rbenv install 3.4.7)
endif
endif

export COSMO_RUBY HOST_RUBY
