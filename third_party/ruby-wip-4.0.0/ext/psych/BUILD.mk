#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_PSYCH

THIRD_PARTY_RUBY_EXT_PSYCH_A = o/$(MODE)/third_party/ruby/ext/psych/psych.a
THIRD_PARTY_RUBY_EXT_PSYCH_FILES := $(wildcard third_party/ruby/ext/psych/*)
THIRD_PARTY_RUBY_EXT_PSYCH_HDRS = $(filter %.h,$(THIRD_PARTY_RUBY_EXT_PSYCH_FILES))

THIRD_PARTY_RUBY_EXT_PSYCH_SRCS =			\
	third_party/ruby/ext/psych/psych.c		\
	third_party/ruby/ext/psych/psych_emitter.c	\
	third_party/ruby/ext/psych/psych_parser.c	\
	third_party/ruby/ext/psych/psych_to_ruby.c	\
	third_party/ruby/ext/psych/psych_yaml_tree.c

THIRD_PARTY_RUBY_EXT_PSYCH_OBJS = $(THIRD_PARTY_RUBY_EXT_PSYCH_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_PSYCH_A):			\
		$(THIRD_PARTY_RUBY_EXT_PSYCH_OBJS)


# Compiler flags for psych extension
o/$(MODE)/third_party/ruby/ext/psych/%.o: private	\
	CFLAGS +=					\
		-Ithird_party/ruby/include		\
		-Ithird_party/ruby			\
		-Ithird_party/ruby/ext/psych		\
		-Ithird_party/libyaml			\
		-DHAVE_LIBYAML				\
		-DRUBY_EXPORT				\
		-DRUBY_COSMOPOLITAN

$(THIRD_PARTY_RUBY_EXT_PSYCH_OBJS): third_party/ruby/ext/psych/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/psych
o/$(MODE)/third_party/ruby/ext/psych: $(THIRD_PARTY_RUBY_EXT_PSYCH_A)
