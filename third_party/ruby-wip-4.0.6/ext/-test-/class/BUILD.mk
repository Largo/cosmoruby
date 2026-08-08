#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_TEST_CLASS

THIRD_PARTY_RUBY_EXT_TEST_CLASS_A = o/$(MODE)/third_party/ruby/ext/-test-/class/class.a
THIRD_PARTY_RUBY_EXT_TEST_CLASS_SRCS = \
	third_party/ruby/ext/-test-/class/init.c \
	third_party/ruby/ext/-test-/class/class2name.c

THIRD_PARTY_RUBY_EXT_TEST_CLASS_OBJS = $(THIRD_PARTY_RUBY_EXT_TEST_CLASS_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_TEST_CLASS_A):		\
		$(THIRD_PARTY_RUBY_EXT_TEST_CLASS_OBJS)

# Compiler flags for test class extension
o/$(MODE)/third_party/ruby/ext/-test-/class/%.o: private	\
	CFLAGS +=				\
		-Ithird_party/ruby/include	\
		-Ithird_party/ruby		\
		-DRUBY_EXPORT			\
		-DRUBY_COSMOPOLITAN		\
		-D'TEST_INIT_FUNCS(X)=X(class2name);'

$(THIRD_PARTY_RUBY_EXT_TEST_CLASS_OBJS): third_party/ruby/ext/-test-/class/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/-test-/class
o/$(MODE)/third_party/ruby/ext/-test-/class: $(THIRD_PARTY_RUBY_EXT_TEST_CLASS_A)
