#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_PATHNAME

THIRD_PARTY_RUBY_EXT_PATHNAME_A = o/$(MODE)/third_party/ruby/ext/pathname/pathname.a
THIRD_PARTY_RUBY_EXT_PATHNAME_SRCS = third_party/ruby/ext/pathname/pathname.c
THIRD_PARTY_RUBY_EXT_PATHNAME_OBJS = $(THIRD_PARTY_RUBY_EXT_PATHNAME_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_PATHNAME_A):			\
		third_party/ruby/ext/pathname/		\
		$(THIRD_PARTY_RUBY_EXT_PATHNAME_OBJS)


o/$(MODE)/third_party/ruby/ext/pathname/%.o: private	\
	CFLAGS +=					\
		-Ithird_party/ruby/include		\
		-Ithird_party/ruby			\
		-DRUBY_EXPORT				\
		-DRUBY_COSMOPOLITAN

$(THIRD_PARTY_RUBY_EXT_PATHNAME_OBJS): third_party/ruby/ext/pathname/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/pathname
o/$(MODE)/third_party/ruby/ext/pathname: $(THIRD_PARTY_RUBY_EXT_PATHNAME_A)
