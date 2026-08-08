#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_IO_WAIT

THIRD_PARTY_RUBY_EXT_IO_WAIT_A = o/$(MODE)/third_party/ruby/ext/io/wait/wait.a
THIRD_PARTY_RUBY_EXT_IO_WAIT_SRCS = third_party/ruby/ext/io/wait/wait.c
THIRD_PARTY_RUBY_EXT_IO_WAIT_OBJS = $(THIRD_PARTY_RUBY_EXT_IO_WAIT_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_IO_WAIT_A):			\
		third_party/ruby/ext/io/wait/		\
		$(THIRD_PARTY_RUBY_EXT_IO_WAIT_OBJS)

o/$(MODE)/third_party/ruby/ext/io/wait/%.o: private	\
	CFLAGS +=						\
		-Ithird_party/ruby/include			\
		-Ithird_party/ruby				\
		-DRUBY_EXPORT					\
		-DRUBY_COSMOPOLITAN				\
		-Wno-deprecated-declarations

$(THIRD_PARTY_RUBY_EXT_IO_WAIT_OBJS): third_party/ruby/ext/io/wait/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/io/wait
o/$(MODE)/third_party/ruby/ext/io/wait: $(THIRD_PARTY_RUBY_EXT_IO_WAIT_A)
