#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘
#
# OVERVIEW
#
#   sqlite3 ruby gem (native extension), statically linked.
#
# NOTES
#
#   The C sources come from the `sqlite3` rubygem (see README.cosmo in this
#   directory).  They are compiled against *Cosmopolitan's* SQLite
#   (third_party/sqlite3), not against the amalgamation the gem normally
#   downloads and builds with mini_portile2.  The linkage itself is declared in
#   ruby.deps.mk, which adds THIRD_PARTY_SQLITE3 to THIRD_PARTY_RUBY_A_DIRECTDEPS.
#
#   The -D flags below stand in for what ext/sqlite3/extconf.rb would normally
#   discover with have_func()/have_type() against the system libsqlite3.  They
#   must stay consistent with third_party/sqlite3/BUILD.mk's own flag set:
#
#     * SQLITE_OMIT_LOAD_EXTENSION  => do NOT define HAVE_SQLITE3_LOAD_EXTENSION
#                                      or HAVE_SQLITE3_ENABLE_LOAD_EXTENSION;
#                                      SQLite3::Database#load_extension and
#                                      #enable_load_extension are then not
#                                      defined (the gem guards them).
#     * no SQLITE_ENABLE_COLUMN_METADATA
#                                   => do NOT define
#                                      HAVE_SQLITE3_COLUMN_DATABASE_NAME;
#                                      SQLite3::Statement#database_name is then
#                                      not defined (the gem guards it).
#     * SQLITE_OMIT_UTF16           => sqlite3_open16()/sqlite3_bind_text16()
#                                      do not exist.  The gem does not guard
#                                      these, so database.c/statement.c carry a
#                                      small `#ifndef SQLITE_OMIT_UTF16` patch
#                                      and UTF-16 input is transcoded to UTF-8.
#                                      SQLITE_OMIT_UTF16 must therefore be
#                                      passed here too.
#     * SQLITE_OMIT_AUTOINIT        => sqlite3_initialize() must be called; the
#                                      gem does that from Init_sqlite3_native()
#                                      when HAVE_SQLITE3_INITIALIZE is defined.

PKGS += THIRD_PARTY_RUBY_EXT_SQLITE3

THIRD_PARTY_RUBY_EXT_SQLITE3_A = o/$(MODE)/third_party/ruby/ext/sqlite3/sqlite3.a
THIRD_PARTY_RUBY_EXT_SQLITE3_FILES := $(wildcard third_party/ruby/ext/sqlite3/*)
THIRD_PARTY_RUBY_EXT_SQLITE3_HDRS = $(filter %.h,$(THIRD_PARTY_RUBY_EXT_SQLITE3_FILES))

THIRD_PARTY_RUBY_EXT_SQLITE3_SRCS =				\
	third_party/ruby/ext/sqlite3/aggregator.c		\
	third_party/ruby/ext/sqlite3/backup.c			\
	third_party/ruby/ext/sqlite3/database.c			\
	third_party/ruby/ext/sqlite3/exception.c		\
	third_party/ruby/ext/sqlite3/sqlite3.c			\
	third_party/ruby/ext/sqlite3/statement.c

THIRD_PARTY_RUBY_EXT_SQLITE3_OBJS = $(THIRD_PARTY_RUBY_EXT_SQLITE3_SRCS:%.c=o/$(MODE)/%.o)

$(THIRD_PARTY_RUBY_EXT_SQLITE3_A):				\
		$(THIRD_PARTY_RUBY_EXT_SQLITE3_OBJS)

# Compiler flags for the sqlite3 extension.
# NOTE: -Ithird_party/ruby/ext/sqlite3 must come before -Ithird_party/sqlite3
# so that the gem's own <database.h>/<statement.h>/... win over anything in
# Cosmopolitan's SQLite source directory.
o/$(MODE)/third_party/ruby/ext/sqlite3/%.o: private		\
	CFLAGS +=						\
		-Ithird_party/ruby/include			\
		-Ithird_party/ruby				\
		-Ithird_party/ruby/ext/sqlite3			\
		-Ithird_party/sqlite3				\
		-DRUBY_EXPORT					\
		-DRUBY_COSMOPOLITAN				\
		-DSQLITE_OMIT_UTF16				\
		-DHAVE_RB_ENC_INTERNED_STR_CSTR=1		\
		-DHAVE_RB_PROC_ARITY				\
		-DHAVE_RB_INTEGER_PACK				\
		-DHAVE_SQLITE3_INITIALIZE			\
		-DHAVE_SQLITE3_BACKUP_INIT			\
		-DHAVE_SQLITE3_OPEN_V2				\
		-DHAVE_SQLITE3_PREPARE_V2			\
		-DHAVE_SQLITE3_DB_NAME				\
		-DHAVE_SQLITE3_ERROR_OFFSET			\
		-DHAVE_TYPE_SQLITE3_INT64			\
		-DHAVE_TYPE_SQLITE3_UINT64

$(THIRD_PARTY_RUBY_EXT_SQLITE3_OBJS): $(THIRD_PARTY_RUBY_EXT_SQLITE3_HDRS) third_party/ruby/ext/sqlite3/BUILD.mk

.PHONY: o/$(MODE)/third_party/ruby/ext/sqlite3
o/$(MODE)/third_party/ruby/ext/sqlite3: $(THIRD_PARTY_RUBY_EXT_SQLITE3_A)
