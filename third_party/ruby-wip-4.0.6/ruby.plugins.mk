#-*-mode:makefile-gmake;indent-tabs-mode:t;tab-width:8;coding:utf-8-*-┐
#── vi: set noet ft=make ts=8 sw=8 fenc=utf-8 :vi ────────────────────┘

# Optional staging of plugin extensions built as .a archives.

RUBY_PLUGIN_ARCH ?= $(shell sed -n 's/^  CONFIG\["arch"\] = "\(.*\)"/\1/p' third_party/ruby/lib/rbconfig.rb | head -1)
RUBY_PLUGIN_ARCH ?= x86_64-cosmo
RUBY_PLUGIN_DLEXT ?= $(shell sed -n 's/^RbConfig::CONFIG\["DLEXT"\] = "\(.*\)"/\1/p' third_party/ruby/lib/rbconfig.mode.rb | head -1)
RUBY_PLUGIN_DLEXT ?= a
RUBY_PLUGIN_DIR ?= o/$(MODE)/third_party/ruby/plugins/$(RUBY_PLUGIN_ARCH)

RUBY_PLUGIN_ARCHIVES := $(foreach ext,$(RUBY_PLUGIN_EXTENSIONS),$($(ext)_A))

# Features to stage as plugin archives (paths as passed to require)
RUBY_PLUGIN_FEATURES := \
	continuation \
	coverage \
	date \
	digest \
	bigdecimal \
	digest/md5 \
	digest/sha1 \
	digest/sha2 \
	etc \
	fcntl \
	io/console \
	io/nonblock \
	io/wait \
	json/ext/generator \
	json/ext/parser \
	monitor \
	objspace \
	pathname \
	psych \
	rbconfig/sizeof \
	ripper \
	socket \
	nio4r_ext \
	nokogiri/nokogiri \
	puma/puma_http11 \
	racc/cparse \
	sqlite3/sqlite3_native \
	stringio \
	strscan \
	zlib \
	mbedtls

.PHONY: ruby.plugins
ruby.plugins: $(RUBY_PLUGIN_ARCHIVES) ruby.encodings ruby.transcoders ruby.encdb
	@mkdir -p $(RUBY_PLUGIN_DIR)
	@mkdir -p $(RUBY_PLUGIN_DIR)/digest
	@mkdir -p $(RUBY_PLUGIN_DIR)/io
	@mkdir -p $(RUBY_PLUGIN_DIR)/json/ext
	@mkdir -p $(RUBY_PLUGIN_DIR)/rbconfig
	@mkdir -p $(RUBY_PLUGIN_DIR)/sqlite3
	@mkdir -p $(RUBY_PLUGIN_DIR)/nokogiri
	@mkdir -p $(RUBY_PLUGIN_DIR)/puma
	@mkdir -p $(RUBY_PLUGIN_DIR)/racc
ifeq ($(RUBY_EXTSTATIC),0)
	@test -f o/$(MODE)/third_party/ruby/ext/continuation/continuation.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/continuation/continuation.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/continuation.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/coverage/coverage.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/coverage/coverage.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/coverage.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/date/date.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/date/date.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/date.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/digest/digest.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/digest/digest.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/digest.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/digest/digest.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/digest/digest.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/digest/md5.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/digest/digest.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/digest/digest.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/digest/sha1.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/digest/digest.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/digest/digest.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/digest/sha2.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/etc/etc.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/etc/etc.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/etc.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/fcntl/fcntl.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/fcntl/fcntl.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/fcntl.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/io/io.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/io/io.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/io/console.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/io/io.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/io/io.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/io/nonblock.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/io/io.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/io/io.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/io/wait.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/json/json.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/json/json.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/json/ext/generator.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/json/json.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/json/json.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/json/ext/parser.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/monitor/monitor.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/monitor/monitor.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/monitor.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/objspace/objspace.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/objspace/objspace.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/objspace.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/pathname/pathname.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/pathname/pathname.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/pathname.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/psych/psych.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/psych/psych.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/psych.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/rbconfig/sizeof/sizeof.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/rbconfig/sizeof/sizeof.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/rbconfig/sizeof.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/ripper/ripper.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/ripper/ripper.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/ripper.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/socket/socket.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/socket/socket.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/socket.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/sqlite3/sqlite3.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/sqlite3/sqlite3.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/sqlite3/sqlite3_native.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/nokogiri/nokogiri.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/nokogiri/nokogiri.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/nokogiri/nokogiri.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/bigdecimal/bigdecimal.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/bigdecimal/bigdecimal.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/bigdecimal.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/nio4r/nio4r.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/nio4r/nio4r.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/nio4r_ext.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/puma/puma.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/puma/puma.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/puma/puma_http11.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/racc/racc.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/racc/racc.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/racc/cparse.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/stringio/stringio.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/stringio/stringio.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/stringio.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/strscan/strscan.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/strscan/strscan.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/strscan.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/zlib/zlib.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/zlib/zlib.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/zlib.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/ext/mbedtls/mbedtls.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/ext/mbedtls/mbedtls.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/mbedtls.$(RUBY_PLUGIN_DLEXT) || true
else ifeq ($(RUBY_SLIM_STATIC),1)
	@: > $(RUBY_PLUGIN_DIR)/continuation.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/coverage.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/date.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/digest.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/digest/md5.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/digest/sha1.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/digest/sha2.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/etc.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/fcntl.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/io/console.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/io/nonblock.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/io/wait.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/json/ext/generator.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/json/ext/parser.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/monitor.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/objspace.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/pathname.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/psych.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/rbconfig/sizeof.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/ripper.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/socket.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/sqlite3/sqlite3_native.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/nokogiri/nokogiri.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/bigdecimal.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/nio4r_ext.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/puma/puma_http11.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/racc/cparse.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/stringio.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/strscan.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/zlib.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/mbedtls.$(RUBY_PLUGIN_DLEXT)
endif

# Encoding plugins (for EXTSTATIC=0 mode)
RUBY_ENCODING_NAMES := \
	big5 cesu_8 cp949 emacs_mule euc_jp euc_kr euc_tw \
	gb2312 gb18030 gbk iso_8859_1 iso_8859_2 iso_8859_3 \
	iso_8859_4 iso_8859_5 iso_8859_6 iso_8859_7 iso_8859_8 \
	iso_8859_9 iso_8859_10 iso_8859_11 iso_8859_13 iso_8859_14 \
	iso_8859_15 iso_8859_16 koi8_r koi8_u shift_jis \
	utf_16be utf_16le utf_32be utf_32le windows_31j \
	windows_1250 windows_1251 windows_1252 windows_1253 \
	windows_1254 windows_1257

RUBY_ENCODING_ARCHIVES := $(foreach enc,$(RUBY_ENCODING_NAMES),o/$(MODE)/third_party/ruby/enc/$(enc).a)

# Transcoder library names (from transdb.h)
RUBY_TRANSCODER_NAMES := \
	big5 cesu_8 chinese ebcdic emoji emoji_iso2022_kddi \
	emoji_sjis_docomo emoji_sjis_kddi emoji_sjis_softbank \
	escape gb18030 gbk iso2022 japanese japanese_euc \
	japanese_sjis korean single_byte utf8_mac utf_16_32

RUBY_TRANSCODER_ARCHIVES := $(foreach trans,$(RUBY_TRANSCODER_NAMES),o/$(MODE)/third_party/ruby/enc/trans/$(trans).a)

# Rule to create .a archive for each encoding
o/$(MODE)/third_party/ruby/enc/%.a: o/$(MODE)/third_party/ruby/enc/%.o
	@mkdir -p $(@D)
	$(AR) rcs $@ $<

# Rule to create .a archive for each transcoder
o/$(MODE)/third_party/ruby/enc/trans/%.a: o/$(MODE)/third_party/ruby/enc/trans/%.o
	@mkdir -p $(@D)
	$(AR) rcs $@ $<

# Add encodings to ruby.plugins target
.PHONY: ruby.encodings
ruby.encodings: $(RUBY_ENCODING_ARCHIVES)
	@mkdir -p $(RUBY_PLUGIN_DIR)/enc
ifeq ($(RUBY_EXTSTATIC),0)
	@test -f o/$(MODE)/third_party/ruby/enc/big5.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/big5.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/big5.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/cesu_8.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/cesu_8.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/cesu_8.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/cp949.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/cp949.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/cp949.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/emacs_mule.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/emacs_mule.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/emacs_mule.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/euc_jp.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/euc_jp.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/euc_jp.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/euc_kr.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/euc_kr.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/euc_kr.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/euc_tw.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/euc_tw.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/euc_tw.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/gb2312.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/gb2312.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/gb2312.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/gb18030.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/gb18030.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/gb18030.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/gbk.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/gbk.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/gbk.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/iso_8859_1.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/iso_8859_1.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/iso_8859_1.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/iso_8859_2.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/iso_8859_2.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/iso_8859_2.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/iso_8859_3.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/iso_8859_3.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/iso_8859_3.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/iso_8859_4.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/iso_8859_4.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/iso_8859_4.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/iso_8859_5.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/iso_8859_5.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/iso_8859_5.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/iso_8859_6.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/iso_8859_6.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/iso_8859_6.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/iso_8859_7.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/iso_8859_7.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/iso_8859_7.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/iso_8859_8.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/iso_8859_8.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/iso_8859_8.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/iso_8859_9.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/iso_8859_9.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/iso_8859_9.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/iso_8859_10.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/iso_8859_10.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/iso_8859_10.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/iso_8859_11.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/iso_8859_11.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/iso_8859_11.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/iso_8859_13.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/iso_8859_13.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/iso_8859_13.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/iso_8859_14.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/iso_8859_14.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/iso_8859_14.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/iso_8859_15.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/iso_8859_15.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/iso_8859_15.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/iso_8859_16.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/iso_8859_16.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/iso_8859_16.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/koi8_r.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/koi8_r.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/koi8_r.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/koi8_u.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/koi8_u.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/koi8_u.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/shift_jis.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/shift_jis.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/shift_jis.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/utf_16be.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/utf_16be.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/utf_16be.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/utf_16le.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/utf_16le.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/utf_16le.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/utf_32be.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/utf_32be.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/utf_32be.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/utf_32le.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/utf_32le.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/utf_32le.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/windows_31j.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/windows_31j.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/windows_31j.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/windows_1250.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/windows_1250.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/windows_1250.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/windows_1251.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/windows_1251.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/windows_1251.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/windows_1252.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/windows_1252.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/windows_1252.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/windows_1253.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/windows_1253.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/windows_1253.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/windows_1254.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/windows_1254.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/windows_1254.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/windows_1257.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/windows_1257.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/windows_1257.$(RUBY_PLUGIN_DLEXT) || true
else ifeq ($(RUBY_SLIM_STATIC),1)
	@: > $(RUBY_PLUGIN_DIR)/enc/big5.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/cesu_8.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/cp949.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/emacs_mule.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/euc_jp.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/euc_kr.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/euc_tw.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/gb2312.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/gb18030.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/gbk.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/iso_8859_1.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/iso_8859_2.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/iso_8859_3.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/iso_8859_4.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/iso_8859_5.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/iso_8859_6.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/iso_8859_7.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/iso_8859_8.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/iso_8859_9.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/iso_8859_10.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/iso_8859_11.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/iso_8859_13.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/iso_8859_14.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/iso_8859_15.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/iso_8859_16.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/koi8_r.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/koi8_u.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/shift_jis.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/utf_16be.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/utf_16le.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/utf_32be.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/utf_32le.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/windows_31j.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/windows_1250.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/windows_1251.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/windows_1252.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/windows_1253.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/windows_1254.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/windows_1257.$(RUBY_PLUGIN_DLEXT)
endif

# Add transcoders to ruby.plugins target
.PHONY: ruby.transcoders
ruby.transcoders: $(RUBY_TRANSCODER_ARCHIVES)
	@mkdir -p $(RUBY_PLUGIN_DIR)/enc/trans
ifeq ($(RUBY_EXTSTATIC),0)
	@test -f o/$(MODE)/third_party/ruby/enc/trans/big5.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/trans/big5.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/trans/big5.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/trans/cesu_8.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/trans/cesu_8.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/trans/cesu_8.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/trans/chinese.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/trans/chinese.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/trans/chinese.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/trans/ebcdic.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/trans/ebcdic.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/trans/ebcdic.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/trans/emoji.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/trans/emoji.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/trans/emoji.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/trans/emoji_iso2022_kddi.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/trans/emoji_iso2022_kddi.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/trans/emoji_iso2022_kddi.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/trans/emoji_sjis_docomo.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/trans/emoji_sjis_docomo.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/trans/emoji_sjis_docomo.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/trans/emoji_sjis_kddi.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/trans/emoji_sjis_kddi.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/trans/emoji_sjis_kddi.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/trans/emoji_sjis_softbank.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/trans/emoji_sjis_softbank.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/trans/emoji_sjis_softbank.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/trans/escape.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/trans/escape.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/trans/escape.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/trans/gb18030.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/trans/gb18030.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/trans/gb18030.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/trans/gbk.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/trans/gbk.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/trans/gbk.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/trans/iso2022.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/trans/iso2022.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/trans/iso2022.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/trans/japanese.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/trans/japanese.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/trans/japanese.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/trans/japanese_euc.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/trans/japanese_euc.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/trans/japanese_euc.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/trans/japanese_sjis.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/trans/japanese_sjis.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/trans/japanese_sjis.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/trans/korean.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/trans/korean.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/trans/korean.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/trans/single_byte.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/trans/single_byte.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/trans/single_byte.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/trans/utf8_mac.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/trans/utf8_mac.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/trans/utf8_mac.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/trans/utf_16_32.$(RUBY_PLUGIN_DLEXT) && cp -a o/$(MODE)/third_party/ruby/enc/trans/utf_16_32.$(RUBY_PLUGIN_DLEXT) $(RUBY_PLUGIN_DIR)/enc/trans/utf_16_32.$(RUBY_PLUGIN_DLEXT) || true
else ifeq ($(RUBY_SLIM_STATIC),1)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/big5.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/cesu_8.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/chinese.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/ebcdic.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/emoji.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/emoji_iso2022_kddi.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/emoji_sjis_docomo.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/emoji_sjis_kddi.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/emoji_sjis_softbank.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/escape.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/gb18030.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/gbk.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/iso2022.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/japanese.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/japanese_euc.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/japanese_sjis.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/korean.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/single_byte.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/utf8_mac.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/utf_16_32.$(RUBY_PLUGIN_DLEXT)
endif

$(RUBY_PLUGIN_DIR):
	@mkdir -p $@

# Encoding database (encdb and transdb) for plugin mode
.PHONY: ruby.encdb
ruby.encdb: o/$(MODE)/third_party/ruby/enc/encdb.a o/$(MODE)/third_party/ruby/enc/trans/transdb.a
	@mkdir -p $(RUBY_PLUGIN_DIR)/enc/trans
ifeq ($(RUBY_EXTSTATIC),0)
	@test -f o/$(MODE)/third_party/ruby/enc/encdb.$(RUBY_PLUGIN_DLEXT) && \
	 cp -a o/$(MODE)/third_party/ruby/enc/encdb.$(RUBY_PLUGIN_DLEXT) \
	       $(RUBY_PLUGIN_DIR)/enc/encdb.$(RUBY_PLUGIN_DLEXT) || true
	@test -f o/$(MODE)/third_party/ruby/enc/trans/transdb.$(RUBY_PLUGIN_DLEXT) && \
	 cp -a o/$(MODE)/third_party/ruby/enc/trans/transdb.$(RUBY_PLUGIN_DLEXT) \
	       $(RUBY_PLUGIN_DIR)/enc/trans/transdb.$(RUBY_PLUGIN_DLEXT) || true
else ifeq ($(RUBY_SLIM_STATIC),1)
	@: > $(RUBY_PLUGIN_DIR)/enc/encdb.$(RUBY_PLUGIN_DLEXT)
	@: > $(RUBY_PLUGIN_DIR)/enc/trans/transdb.$(RUBY_PLUGIN_DLEXT)
endif

# Build .a archives from .o files
o/$(MODE)/third_party/ruby/enc/encdb.a: o/$(MODE)/third_party/ruby/enc/encdb.o
	@mkdir -p $(@D)
	$(AR) rcs $@ $<

o/$(MODE)/third_party/ruby/enc/trans/transdb.a: o/$(MODE)/third_party/ruby/enc/trans/transdb.o
	@mkdir -p $(@D)
	$(AR) rcs $@ $<
