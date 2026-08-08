#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_TEST_SANITIZERS

THIRD_PARTY_RUBY_EXT_TEST_SANITIZERS_A = o/$(MODE)/third_party/ruby/ext/-test-/sanitizers/sanitizers.a
THIRD_PARTY_RUBY_EXT_TEST_SANITIZERS_SRCS = \
	third_party/ruby/ext/-test-/sanitizers/sanitizers.c

THIRD_PARTY_RUBY_EXT_TEST_SANITIZERS_OBJS = $(THIRD_PARTY_RUBY_EXT_TEST_SANITIZERS_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_TEST_SANITIZERS_A):		\
		$(THIRD_PARTY_RUBY_EXT_TEST_SANITIZERS_OBJS)

# Compiler flags for test sanitizers extension
o/$(MODE)/third_party/ruby/ext/-test-/sanitizers/%.o: private	\
	CFLAGS +=				\
		-Ithird_party/ruby/include	\
		-Ithird_party/ruby		\
		-DRUBY_EXPORT			\
		-DRUBY_COSMOPOLITAN

$(THIRD_PARTY_RUBY_EXT_TEST_SANITIZERS_OBJS): third_party/ruby/ext/-test-/sanitizers/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/-test-/sanitizers
o/$(MODE)/third_party/ruby/ext/-test-/sanitizers: $(THIRD_PARTY_RUBY_EXT_TEST_SANITIZERS_A)
