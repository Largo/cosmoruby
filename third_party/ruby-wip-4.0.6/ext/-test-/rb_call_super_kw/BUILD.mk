#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_TEST_RB_CALL_SUPER_KW

THIRD_PARTY_RUBY_EXT_TEST_RB_CALL_SUPER_KW_A = o/$(MODE)/third_party/ruby/ext/-test-/rb_call_super_kw/rb_call_super_kw.a
THIRD_PARTY_RUBY_EXT_TEST_RB_CALL_SUPER_KW_SRCS = \
	third_party/ruby/ext/-test-/rb_call_super_kw/rb_call_super_kw.c

THIRD_PARTY_RUBY_EXT_TEST_RB_CALL_SUPER_KW_OBJS = $(THIRD_PARTY_RUBY_EXT_TEST_RB_CALL_SUPER_KW_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_TEST_RB_CALL_SUPER_KW_A):		\
		$(THIRD_PARTY_RUBY_EXT_TEST_RB_CALL_SUPER_KW_OBJS)

# Compiler flags for test rb_call_super_kw extension
o/$(MODE)/third_party/ruby/ext/-test-/rb_call_super_kw/%.o: private	\
	CFLAGS +=				\
		-Ithird_party/ruby/include	\
		-Ithird_party/ruby		\
		-DRUBY_EXPORT			\
		-DRUBY_COSMOPOLITAN

$(THIRD_PARTY_RUBY_EXT_TEST_RB_CALL_SUPER_KW_OBJS): third_party/ruby/ext/-test-/rb_call_super_kw/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/-test-/rb_call_super_kw
o/$(MODE)/third_party/ruby/ext/-test-/rb_call_super_kw: $(THIRD_PARTY_RUBY_EXT_TEST_RB_CALL_SUPER_KW_A)
