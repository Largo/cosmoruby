#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_TEST_FATAL

THIRD_PARTY_RUBY_EXT_TEST_FATAL_A = o/$(MODE)/third_party/ruby/ext/-test-/fatal/fatal.a
THIRD_PARTY_RUBY_EXT_TEST_FATAL_SRCS = \
	third_party/ruby/ext/-test-/fatal/init.c \
	third_party/ruby/ext/-test-/fatal/invalid.c \
	third_party/ruby/ext/-test-/fatal/rb_fatal.c

THIRD_PARTY_RUBY_EXT_TEST_FATAL_OBJS = $(THIRD_PARTY_RUBY_EXT_TEST_FATAL_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_TEST_FATAL_A):		\
		$(THIRD_PARTY_RUBY_EXT_TEST_FATAL_OBJS)

# Compiler flags for test fatal extension
o/$(MODE)/third_party/ruby/ext/-test-/fatal/%.o: private	\
	CFLAGS +=				\
		-Ithird_party/ruby/include	\
		-Ithird_party/ruby		\
		-DRUBY_EXPORT			\
		-DRUBY_COSMOPOLITAN		\
		-D'TEST_INIT_FUNCS(X)=X(invalid);X(rb_fatal);'

$(THIRD_PARTY_RUBY_EXT_TEST_FATAL_OBJS): third_party/ruby/ext/-test-/fatal/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/-test-/fatal
o/$(MODE)/third_party/ruby/ext/-test-/fatal: $(THIRD_PARTY_RUBY_EXT_TEST_FATAL_A)
