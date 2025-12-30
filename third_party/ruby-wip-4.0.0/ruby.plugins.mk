#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

# Optional staging of plugin extensions built as .a archives.

RUBY_PLUGIN_ARCH ?= $(shell sed -n 's/^  CONFIG\["arch"\] = "\(.*\)"/\1/p' third_party/ruby/lib/rbconfig.rb | head -1)
RUBY_PLUGIN_ARCH ?= x86_64-cosmo
RUBY_PLUGIN_DLEXT ?= $(shell sed -n 's/^  CONFIG\["DLEXT"\] = "\(.*\)"/\1/p' third_party/ruby/lib/rbconfig.rb | head -1)
RUBY_PLUGIN_DLEXT ?= a
RUBY_PLUGIN_DIR ?= o/$(MODE)/third_party/ruby/plugins/$(RUBY_PLUGIN_ARCH)

RUBY_PLUGIN_ARCHIVES := $(foreach ext,$(RUBY_PLUGIN_EXTENSIONS),$($(ext)_A))

# Features to stage as plugin archives (paths as passed to require)
RUBY_PLUGIN_FEATURES := \
	date \
	digest \
	digest/md5 \
	digest/sha1 \
	digest/sha2 \
	etc \
	io/console \
	io/nonblock \
	io/wait \
	json/ext/generator \
	json/ext/parser \
	monitor \
	pathname \
	psych \
	ripper \
	socket \
	stringio \
	zlib \
	mbedtls

.PHONY: ruby.plugins
ruby.plugins: $(RUBY_PLUGIN_ARCHIVES)
	@mkdir -p $(RUBY_PLUGIN_DIR)
	@set -e; \
	if [ "$(RUBY_EXTSTATIC)" = "0" ]; then \
	  for f in $(RUBY_PLUGIN_FEATURES); do \
	    base=$${f%%/*}; \
	    src="o/$(MODE)/third_party/ruby/ext/$${base}/$${base}.$(RUBY_PLUGIN_DLEXT)"; \
	    dst="$(RUBY_PLUGIN_DIR)/$${f}.$(RUBY_PLUGIN_DLEXT)"; \
	    mkdir -p "$${dst%/*}"; \
	    cp -a "$$src" "$$dst"; \
	  done; \
	elif [ "$(RUBY_SLIM_STATIC)" = "1" ]; then \
	  for f in $(RUBY_PLUGIN_FEATURES); do \
	    dst="$(RUBY_PLUGIN_DIR)/$${f}.$(RUBY_PLUGIN_DLEXT)"; \
	    mkdir -p "$${dst%/*}"; \
	    : > "$$dst"; \
	  done; \
	fi

$(RUBY_PLUGIN_DIR):
	@mkdir -p $@
