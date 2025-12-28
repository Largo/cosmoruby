#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

# Override SHELL for Ruby build to use Mexican Toaster Shell (mtsh)
# mtsh provides enhanced shell features needed by Ruby code generation:
#   - Subshell execution with ( )
#   - Command substitution with $( ) and backticks
#   - 'command -v' for finding executables in PATH
#   - ':' null command builtin
# Note: mtsh will be built as a dependency before Ruby recipes run
#
# Prefer built mtsh, fallback to bootstrap mtsh, then default shell
ifneq ($(wildcard o/$(MODE)/third_party/mexican_toaster/mtsh.com),)
SHELL = o/$(MODE)/third_party/mexican_toaster/mtsh.com
else ifneq ($(wildcard build/bootstrap/mtsh),)
SHELL = build/bootstrap/mtsh
endif

################################################################################
# COSMOPOLITAN BUILD CONSTRAINTS
#
# Hermetic Build:
#   - Cosmopolitan downloads its own toolchain to .cosmocc/
#   - Cannot rely on system Ruby or tools during build
#   - Use HOST_RUBY or COSMO_RUBY variables for Ruby interpreter
#   - All build artifacts go to o/$(MODE)/ directory tree
#
# mtsh Shell Features:
#   - Enhanced command interpreter based on cocmd
#   - Supports: ':', '#' comments, subshells '()', cmd substitution '$()'
#   - Supports: 'command -v' for PATH lookups
#   - Limited: Complex '&& ||' chains with redirects may fail
#   - Workaround: Break into multiple rules or simplify command logic
################################################################################

# Ruby build system split for faster incremental builds:
# - ruby.deps.mk: Source lists, package definitions (rarely changes)
# - ruby.compile.mk: CFLAGS, .o compilation rules (changes trigger rebuild)
# - ruby.link.mk: LDFLAGS, binary link rules (changes only trigger relink)

include third_party/ruby/ruby.env.mk
include third_party/ruby/ruby.codegen.mk
include third_party/ruby/ruby.deps.mk
include third_party/ruby/ruby.compile.mk
include third_party/ruby/ruby.link.mk

.PHONY: ruby_verify ruby_verify_build ruby_missing
ruby_verify:
	@/bin/sh -c 'HOST_RUBY="$(HOST_RUBY)" sh third_party/ruby-wip-3.4.7/cosmo_tests/check_export_tables.sh'
	@/bin/sh -c 'HOST_RUBY="$(HOST_RUBY)" sh third_party/ruby-wip-3.4.7/cosmo_tests/check_export_tables_binary.sh'

ruby_verify_build:						\
    o/$(MODE)/third_party/ruby/ruby				\
    o/$(MODE)/third_party/ruby/irb				\
    o/$(MODE)/third_party/ruby/miniruby			\
    o/$(MODE)/third_party/ruby/ruby.zipless			\
    ruby_verify

ruby_missing:
	@missing=0; \
	for bin in ruby irb miniruby ruby.zipless; do \
	  path=o/$(MODE)/third_party/ruby/$$bin; \
	  if [ ! -e "$$path" ]; then \
	    echo "missing binary: $$path"; \
	    missing=1; \
	  fi; \
	done; \
	for ext in date digest etc io/nonblock json mbedtls monitor pathname psych socket stringio zlib; do \
	  path=o/$(MODE)/third_party/ruby/ext/$$ext/$$ext.a; \
	  if [ ! -e "$$path" ]; then \
	    echo "missing extension archive: $$path"; \
	    missing=1; \
	  fi; \
	done; \
	if [ $$missing -eq 0 ]; then \
	  echo "no missing ruby artifacts under o/$(MODE)/third_party/ruby"; \
	fi
