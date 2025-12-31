#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_DATE

THIRD_PARTY_RUBY_EXT_DATE_A = o/$(MODE)/third_party/ruby/ext/date/date.a
THIRD_PARTY_RUBY_EXT_DATE_FILES := $(wildcard third_party/ruby/ext/date/*)
THIRD_PARTY_RUBY_EXT_DATE_HDRS = $(filter %.h,$(THIRD_PARTY_RUBY_EXT_DATE_FILES))

$(THIRD_PARTY_RUBY_EXT_DATE_A):			\
		$(THIRD_PARTY_RUBY_EXT_DATE_OBJS)

THIRD_PARTY_RUBY_EXT_DATE_SRCS =			\
	third_party/ruby/ext/date/date_core.c		\
	third_party/ruby/ext/date/date_parse.c		\
	third_party/ruby/ext/date/date_strftime.c	\
	third_party/ruby/ext/date/date_strptime.c

THIRD_PARTY_RUBY_EXT_DATE_OBJS = $(THIRD_PARTY_RUBY_EXT_DATE_SRCS:%.c=o/$(MODE)/%.o)

# Compiler flags for date extension
o/$(MODE)/third_party/ruby/ext/date/%.o: private	\
	CFLAGS +=					\
		-Ithird_party/ruby/include		\
		-Ithird_party/ruby			\
		-Ithird_party/ruby/ext/date		\
		-DRUBY_EXPORT				\
		-DRUBY_COSMOPOLITAN

$(THIRD_PARTY_RUBY_EXT_DATE_OBJS): third_party/ruby/ext/date/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/date
o/$(MODE)/third_party/ruby/ext/date: $(THIRD_PARTY_RUBY_EXT_DATE_A)
