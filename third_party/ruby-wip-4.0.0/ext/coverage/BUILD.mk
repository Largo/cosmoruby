#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_COVERAGE

THIRD_PARTY_RUBY_EXT_COVERAGE_A = o/$(MODE)/third_party/ruby/ext/coverage/coverage.a
THIRD_PARTY_RUBY_EXT_COVERAGE_SRCS = third_party/ruby/ext/coverage/coverage.c
THIRD_PARTY_RUBY_EXT_COVERAGE_OBJS = $(THIRD_PARTY_RUBY_EXT_COVERAGE_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_COVERAGE_A):			\
		$(THIRD_PARTY_RUBY_EXT_COVERAGE_OBJS)

# Compiler flags for coverage extension
o/$(MODE)/third_party/ruby/ext/coverage/%.o: private	\
	CFLAGS +=					\
		-Ithird_party/ruby/include		\
		-Ithird_party/ruby			\
		-DRUBY_EXPORT				\
		-DRUBY_COSMOPOLITAN

$(THIRD_PARTY_RUBY_EXT_COVERAGE_OBJS): third_party/ruby/ext/coverage/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/coverage
o/$(MODE)/third_party/ruby/ext/coverage: $(THIRD_PARTY_RUBY_EXT_COVERAGE_A)
