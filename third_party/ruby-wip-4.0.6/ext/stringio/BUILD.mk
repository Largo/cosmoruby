#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_STRINGIO

THIRD_PARTY_RUBY_EXT_STRINGIO_A = o/$(MODE)/third_party/ruby/ext/stringio/stringio.a
THIRD_PARTY_RUBY_EXT_STRINGIO_SRCS = third_party/ruby/ext/stringio/stringio.c
THIRD_PARTY_RUBY_EXT_STRINGIO_OBJS = $(THIRD_PARTY_RUBY_EXT_STRINGIO_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_STRINGIO_A):			\
		$(THIRD_PARTY_RUBY_EXT_STRINGIO_OBJS)


o/$(MODE)/third_party/ruby/ext/stringio/%.o: private	\
	CFLAGS +=					\
		-Ithird_party/ruby/include		\
		-Ithird_party/ruby			\
		-DRUBY_EXPORT				\
		-DRUBY_COSMOPOLITAN			\
		-DHAVE_TYPE_RB_IO_MODE_T

$(THIRD_PARTY_RUBY_EXT_STRINGIO_OBJS): third_party/ruby/ext/stringio/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/stringio
o/$(MODE)/third_party/ruby/ext/stringio: $(THIRD_PARTY_RUBY_EXT_STRINGIO_A)
