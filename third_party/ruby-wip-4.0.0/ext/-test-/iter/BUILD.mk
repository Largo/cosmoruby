#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_TEST_ITER

THIRD_PARTY_RUBY_EXT_TEST_ITER_A = o/$(MODE)/third_party/ruby/ext/-test-/iter/iter.a
THIRD_PARTY_RUBY_EXT_TEST_ITER_SRCS = \
	third_party/ruby/ext/-test-/iter/break.c \
	third_party/ruby/ext/-test-/iter/init.c \
	third_party/ruby/ext/-test-/iter/yield.c

THIRD_PARTY_RUBY_EXT_TEST_ITER_OBJS = $(THIRD_PARTY_RUBY_EXT_TEST_ITER_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_TEST_ITER_A):		\
		$(THIRD_PARTY_RUBY_EXT_TEST_ITER_OBJS)

# Compiler flags for test iter extension
o/$(MODE)/third_party/ruby/ext/-test-/iter/%.o: private	\
	CFLAGS +=				\
		-Ithird_party/ruby/include	\
		-Ithird_party/ruby		\
		-DRUBY_EXPORT			\
		-DRUBY_COSMOPOLITAN		\
		-D'TEST_INIT_FUNCS(X)=X(break);X(yield);'

$(THIRD_PARTY_RUBY_EXT_TEST_ITER_OBJS): third_party/ruby/ext/-test-/iter/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/-test-/iter
o/$(MODE)/third_party/ruby/ext/-test-/iter: $(THIRD_PARTY_RUBY_EXT_TEST_ITER_A)