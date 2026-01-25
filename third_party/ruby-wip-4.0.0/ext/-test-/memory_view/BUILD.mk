#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_TEST_MEMORY_VIEW

THIRD_PARTY_RUBY_EXT_TEST_MEMORY_VIEW_A = o/$(MODE)/third_party/ruby/ext/-test-/memory_view/memory_view.a
THIRD_PARTY_RUBY_EXT_TEST_MEMORY_VIEW_SRCS = \
	third_party/ruby/ext/-test-/memory_view/memory_view.c

THIRD_PARTY_RUBY_EXT_TEST_MEMORY_VIEW_OBJS = $(THIRD_PARTY_RUBY_EXT_TEST_MEMORY_VIEW_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_TEST_MEMORY_VIEW_A):		\
		$(THIRD_PARTY_RUBY_EXT_TEST_MEMORY_VIEW_OBJS)

# Compiler flags for test memory_view extension
o/$(MODE)/third_party/ruby/ext/-test-/memory_view/%.o: private	\
	CFLAGS +=				\
		-Ithird_party/ruby/include	\
		-Ithird_party/ruby		\
		-DRUBY_EXPORT			\
		-DRUBY_COSMOPOLITAN

$(THIRD_PARTY_RUBY_EXT_TEST_MEMORY_VIEW_OBJS): third_party/ruby/ext/-test-/memory_view/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/-test-/memory_view
o/$(MODE)/third_party/ruby/ext/-test-/memory_view: $(THIRD_PARTY_RUBY_EXT_TEST_MEMORY_VIEW_A)
