#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_ETC

THIRD_PARTY_RUBY_EXT_ETC_A = o/$(MODE)/third_party/ruby/ext/etc/etc.a
THIRD_PARTY_RUBY_EXT_ETC_SRCS = third_party/ruby/ext/etc/etc.c
THIRD_PARTY_RUBY_EXT_ETC_OBJS = $(THIRD_PARTY_RUBY_EXT_ETC_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_ETC_A):				\
		third_party/ruby/ext/etc/		\
		$(THIRD_PARTY_RUBY_EXT_ETC_OBJS)



# Compiler flags for etc extension
o/$(MODE)/third_party/ruby/ext/etc/%.o: private		\
	CFLAGS +=					\
		-Ithird_party/ruby/include		\
		-Ithird_party/ruby			\
		-DRUBY_EXPORT				\
		-DRUBY_COSMOPOLITAN			\
		-DHAVE_RB_IO_DESCRIPTOR			\
		-DSYSCONFDIR=\"/etc\"

$(THIRD_PARTY_RUBY_EXT_ETC_OBJS): third_party/ruby/ext/etc/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/etc
o/$(MODE)/third_party/ruby/ext/etc: $(THIRD_PARTY_RUBY_EXT_ETC_A)
