#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

# Ruby build system split for faster incremental builds:
# - ruby.deps.mk: Source lists, package definitions (rarely changes)
# - ruby.compile.mk: CFLAGS, .o compilation rules (changes trigger rebuild)
# - ruby.link.mk: LDFLAGS, binary link rules (changes only trigger relink)

include third_party/ruby/ruby.deps.mk
include third_party/ruby/ruby.compile.mk
include third_party/ruby/ruby.link.mk
