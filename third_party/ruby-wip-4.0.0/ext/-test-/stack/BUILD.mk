#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_TEST_STACK

THIRD_PARTY_RUBY_EXT_TEST_STACK_A = o/$(MODE)/third_party/ruby/ext/-test-/stack/stack.a
THIRD_PARTY_RUBY_EXT_TEST_STACK_SRCS = \
	third_party/ruby/ext/-test-/stack/stack.c

THIRD_PARTY_RUBY_EXT_TEST_STACK_OBJS = $(THIRD_PARTY_RUBY_EXT_TEST_STACK_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_TEST_STACK_A):		\
		$(THIRD_PARTY_RUBY_EXT_TEST_STACK_OBJS)

# Compiler flags for test stack extension
o/$(MODE)/third_party/ruby/ext/-test-/stack/%.o: private	\
	CFLAGS +=				\
		-Ithird_party/ruby/include	\
		-Ithird_party/ruby		\
		-DRUBY_EXPORT			\
		-DRUBY_COSMOPOLITAN

$(THIRD_PARTY_RUBY_EXT_TEST_STACK_OBJS): third_party/ruby/ext/-test-/stack/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/-test-/stack
o/$(MODE)/third_party/ruby/ext/-test-/stack: $(THIRD_PARTY_RUBY_EXT_TEST_STACK_A)
