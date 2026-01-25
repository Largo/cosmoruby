#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_RBCONFIG_SIZEOF

THIRD_PARTY_RUBY_EXT_RBCONFIG_SIZEOF_A = o/$(MODE)/third_party/ruby/ext/rbconfig/sizeof/sizeof.a
THIRD_PARTY_RUBY_EXT_RBCONFIG_SIZEOF_SRCS =		\
	third_party/ruby/ext/rbconfig/sizeof/limits.c	\
	third_party/ruby/ext/rbconfig/sizeof/sizes.c
THIRD_PARTY_RUBY_EXT_RBCONFIG_SIZEOF_OBJS = $(THIRD_PARTY_RUBY_EXT_RBCONFIG_SIZEOF_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_RBCONFIG_SIZEOF_A):				\
		$(THIRD_PARTY_RUBY_EXT_RBCONFIG_SIZEOF_OBJS)



# Compiler flags for rbconfig/sizeof extension
o/$(MODE)/third_party/ruby/ext/rbconfig/sizeof/%.o: private		\
	CFLAGS +=					\
		-Ithird_party/ruby/include		\
		-Ithird_party/ruby			\
		-DRUBY_EXPORT				\
		-DRUBY_COSMOPOLITAN			\
		-Wno-overflow

$(THIRD_PARTY_RUBY_EXT_RBCONFIG_SIZEOF_OBJS): third_party/ruby/ext/rbconfig/sizeof/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/rbconfig/sizeof
o/$(MODE)/third_party/ruby/ext/rbconfig/sizeof: $(THIRD_PARTY_RUBY_EXT_RBCONFIG_SIZEOF_A)
