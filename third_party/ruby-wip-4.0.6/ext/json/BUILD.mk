#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

PKGS += THIRD_PARTY_RUBY_EXT_JSON

# JSON has two components: generator and parser
THIRD_PARTY_RUBY_EXT_JSON_SRCS =				\
	third_party/ruby/ext/json/generator/generator.c		\
	third_party/ruby/ext/json/parser/parser.c

THIRD_PARTY_RUBY_EXT_JSON_OBJS = $(THIRD_PARTY_RUBY_EXT_JSON_SRCS:%.c=o/$(MODE)/%.o)

THIRD_PARTY_RUBY_EXT_JSON_A = o/$(MODE)/third_party/ruby/ext/json/json.a

$(THIRD_PARTY_RUBY_EXT_JSON_A):					\
		$(THIRD_PARTY_RUBY_EXT_JSON_OBJS)

# Compiler flags for JSON extension
o/$(MODE)/third_party/ruby/ext/json/generator/%.o: private	\
	CFLAGS +=						\
		-Ithird_party/ruby/include			\
		-Ithird_party/ruby				\
		-Ithird_party/ruby/ext/json			\
		-DRUBY_EXPORT					\
		-DRUBY_COSMOPOLITAN				\
		-DJSON_GENERATOR

o/$(MODE)/third_party/ruby/ext/json/parser/%.o: private	\
	CFLAGS +=					\
		-Ithird_party/ruby/include		\
		-Ithird_party/ruby			\
		-Ithird_party/ruby/ext/json		\
		-DRUBY_EXPORT				\
		-DRUBY_COSMOPOLITAN			\
		-DHAVE_STRNLEN				\
		-DHAVE_RB_HASH_BULK_INSERT		\
		-DHAVE_RB_STR_TO_INTERNED_STR

$(THIRD_PARTY_RUBY_EXT_JSON_OBJS): third_party/ruby/ext/json/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/json
o/$(MODE)/third_party/ruby/ext/json: $(THIRD_PARTY_RUBY_EXT_JSON_A)
