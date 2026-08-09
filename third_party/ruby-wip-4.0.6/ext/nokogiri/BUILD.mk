#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘
#
# OVERVIEW
#
#   nokogiri 1.19.4 ruby gem (native extension), statically linked.
#
# NOTES
#
#   The C sources come from the `nokogiri` rubygem (see README.cosmo).
#   They are compiled against third_party/libxml2 and third_party/libxslt
#   — the same libxml2 2.13.9 / libxslt 1.1.43 that nokogiri pins in its
#   dependencies.yml, so this is not a "system libraries" downgrade. The
#   linkage is declared in ruby.deps.mk, which adds THIRD_PARTY_LIBXML2
#   and THIRD_PARTY_LIBXSLT to THIRD_PARTY_RUBY_A_DIRECTDEPS.
#
#   gumbo/ is nokogiri's bundled HTML5 parser (libgumbo). extconf.rb
#   normally builds it as a separate libgumbo.a; here it is simply part
#   of this archive. It is self-contained C90 with no external deps.
#
#   The -D flags below stand in for extconf.rb's have_func() results:
#
#     HAVE_XMLCTXTSETOPTIONS       libxml2 >= 2.13  -> yes (2.13.9)
#     HAVE_XMLSWITCHENCODINGNAME   libxml2 >= 2.13  -> yes (2.13.9)
#     HAVE_XMLCTXTGETOPTIONS       libxml2 >= 2.14  -> NO; deliberately
#                                  left undefined so libxml2_polyfill.c
#                                  supplies it.
#     HAVE_RB_CATEGORY_WARNING     ruby >= 3.0      -> yes. Note the guard
#                                  is `#if`, not `#ifdef`, so it needs a
#                                  value.
#
#   NOKOGIRI_PACKAGED_LIBRARIES is deliberately NOT defined: we are not
#   using the mini_portile2-built copies, so Nokogiri::LIBXML2_PATCHES
#   and Nokogiri::LIBXSLT_PATCHES correctly report nil.

PKGS += THIRD_PARTY_RUBY_EXT_NOKOGIRI

THIRD_PARTY_RUBY_EXT_NOKOGIRI_A = o/$(MODE)/third_party/ruby/ext/nokogiri/nokogiri.a
THIRD_PARTY_RUBY_EXT_NOKOGIRI_FILES :=					\
	$(wildcard third_party/ruby/ext/nokogiri/*)			\
	$(wildcard third_party/ruby/ext/nokogiri/gumbo/*)
THIRD_PARTY_RUBY_EXT_NOKOGIRI_HDRS =					\
	$(filter %.h,$(THIRD_PARTY_RUBY_EXT_NOKOGIRI_FILES))

THIRD_PARTY_RUBY_EXT_NOKOGIRI_SRCS =					\
	$(sort $(filter %.c,$(THIRD_PARTY_RUBY_EXT_NOKOGIRI_FILES)))

THIRD_PARTY_RUBY_EXT_NOKOGIRI_OBJS =					\
	$(THIRD_PARTY_RUBY_EXT_NOKOGIRI_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_NOKOGIRI_A):					\
		$(THIRD_PARTY_RUBY_EXT_NOKOGIRI_OBJS)

o/$(MODE)/third_party/ruby/ext/nokogiri/%.o: private			\
	CFLAGS +=							\
		-Ithird_party/ruby/include				\
		-Ithird_party/ruby					\
		-Ithird_party/ruby/ext/nokogiri				\
		-Ithird_party/ruby/ext/nokogiri/gumbo			\
		-Ithird_party/libxml2/include				\
		-Ithird_party/libxslt					\
		-DRUBY_EXPORT						\
		-DRUBY_COSMOPOLITAN					\
		-DHAVE_XMLCTXTSETOPTIONS				\
		-DHAVE_XMLSWITCHENCODINGNAME				\
		-DHAVE_RB_CATEGORY_WARNING=1

$(THIRD_PARTY_RUBY_EXT_NOKOGIRI_OBJS): $(THIRD_PARTY_RUBY_EXT_NOKOGIRI_HDRS) third_party/ruby/ext/nokogiri/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/nokogiri
o/$(MODE)/third_party/ruby/ext/nokogiri: $(THIRD_PARTY_RUBY_EXT_NOKOGIRI_A)
