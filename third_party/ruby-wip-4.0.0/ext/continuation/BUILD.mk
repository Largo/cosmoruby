#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_CONTINUATION

THIRD_PARTY_RUBY_EXT_CONTINUATION_A = o/$(MODE)/third_party/ruby/ext/continuation/continuation.a
THIRD_PARTY_RUBY_EXT_CONTINUATION_SRCS = third_party/ruby/ext/continuation/continuation.c
THIRD_PARTY_RUBY_EXT_CONTINUATION_OBJS = $(THIRD_PARTY_RUBY_EXT_CONTINUATION_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_CONTINUATION_A):				\
		$(THIRD_PARTY_RUBY_EXT_CONTINUATION_OBJS)



# Compiler flags for continuation extension
o/$(MODE)/third_party/ruby/ext/continuation/%.o: private		\
	CFLAGS +=					\
		-Ithird_party/ruby/include		\
		-Ithird_party/ruby			\
		-DRUBY_EXPORT				\
		-DRUBY_COSMOPOLITAN

$(THIRD_PARTY_RUBY_EXT_CONTINUATION_OBJS): third_party/ruby/ext/continuation/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/continuation
o/$(MODE)/third_party/ruby/ext/continuation: $(THIRD_PARTY_RUBY_EXT_CONTINUATION_A)
