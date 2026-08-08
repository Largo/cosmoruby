#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_IO_NONBLOCK

THIRD_PARTY_RUBY_EXT_IO_NONBLOCK_A = o/$(MODE)/third_party/ruby/ext/io/nonblock/nonblock.a
THIRD_PARTY_RUBY_EXT_IO_NONBLOCK_SRCS = third_party/ruby/ext/io/nonblock/nonblock.c
THIRD_PARTY_RUBY_EXT_IO_NONBLOCK_OBJS = $(THIRD_PARTY_RUBY_EXT_IO_NONBLOCK_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_IO_NONBLOCK_A):			\
		third_party/ruby/ext/io/nonblock/	\
		$(THIRD_PARTY_RUBY_EXT_IO_NONBLOCK_OBJS)


o/$(MODE)/third_party/ruby/ext/io/nonblock/%.o: private	\
	CFLAGS +=					\
		-Ithird_party/ruby/include		\
		-Ithird_party/ruby			\
		-DRUBY_EXPORT				\
		-DRUBY_COSMOPOLITAN			\
		-DHAVE_RB_IO_DESCRIPTOR

$(THIRD_PARTY_RUBY_EXT_IO_NONBLOCK_OBJS): third_party/ruby/ext/io/nonblock/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/io/nonblock
o/$(MODE)/third_party/ruby/ext/io/nonblock: $(THIRD_PARTY_RUBY_EXT_IO_NONBLOCK_A)
