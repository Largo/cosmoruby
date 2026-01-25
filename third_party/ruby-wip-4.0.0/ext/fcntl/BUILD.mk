#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_FCNTL

THIRD_PARTY_RUBY_EXT_FCNTL_A = o/$(MODE)/third_party/ruby/ext/fcntl/fcntl.a
THIRD_PARTY_RUBY_EXT_FCNTL_SRCS = third_party/ruby/ext/fcntl/fcntl.c
THIRD_PARTY_RUBY_EXT_FCNTL_OBJS = $(THIRD_PARTY_RUBY_EXT_FCNTL_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_FCNTL_A):			\
		$(THIRD_PARTY_RUBY_EXT_FCNTL_OBJS)

# Compiler flags for fcntl extension
o/$(MODE)/third_party/ruby/ext/fcntl/%.o: private	\
	CFLAGS +=					\
		-Ithird_party/ruby/include		\
		-Ithird_party/ruby			\
		-DRUBY_EXPORT				\
		-DRUBY_COSMOPOLITAN

$(THIRD_PARTY_RUBY_EXT_FCNTL_OBJS): third_party/ruby/ext/fcntl/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/fcntl
o/$(MODE)/third_party/ruby/ext/fcntl: $(THIRD_PARTY_RUBY_EXT_FCNTL_A)
