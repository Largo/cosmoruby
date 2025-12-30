V = 0
V0 = $(V:0=)
Q1 = $(V:1=)
Q = $(Q1:0=@)
ECHO1 = $(V:1=@:)
ECHO = $(ECHO1:0=@echo)


MINIRUBY = /home/groobiest/.rbenv/shims/ruby -I/home/groobiest/Code/jart/cosmopolitan/third_party/ruby -I/home/groobiest/Code/jart/cosmopolitan/o/third_party/ruby/generated
SCRIPT_ARGS = --dest-dir="" --extout=".ext" --ext-build-dir="./ext" --mflags="" --make-flags=""
EXTMK_ARGS = $(SCRIPT_ARGS) --gnumake=$(gnumake) --extflags="$(EXTLDFLAGS)" \
	   --make-flags="MINIRUBY='$(MINIRUBY)'"

all: exts gems
exts:
gems:

exts: ext/-test-/exts.mk
ext/-test-/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/cgi/exts.mk
ext/cgi/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/continuation/exts.mk
ext/continuation/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/coverage/exts.mk
ext/coverage/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/date/exts.mk
ext/date/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/digest/exts.mk
ext/digest/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/erb/exts.mk
ext/erb/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/etc/exts.mk
ext/etc/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/fcntl/exts.mk
ext/fcntl/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/io/exts.mk
ext/io/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/json/exts.mk
ext/json/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/monitor/exts.mk
ext/monitor/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/objspace/exts.mk
ext/objspace/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/openssl/exts.mk
ext/openssl/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/psych/exts.mk
ext/psych/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/pty/exts.mk
ext/pty/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/rbconfig/exts.mk
ext/rbconfig/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/ripper/exts.mk
ext/ripper/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/rubyvm/exts.mk
ext/rubyvm/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/socket/exts.mk
ext/socket/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/stringio/exts.mk
ext/stringio/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/strscan/exts.mk
ext/strscan/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/win32/exts.mk
ext/win32/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
exts: ext/zlib/exts.mk
ext/zlib/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --extstatic $(EXTSTATIC) \
		-- configure $(@D)
gems: .bundle/gems/bigdecimal-4.0.1/exts.mk
.bundle/gems/bigdecimal-4.0.1/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --no-extstatic \
		-- configure $(@D)
gems: .bundle/gems/debug-1.11.1/exts.mk
.bundle/gems/debug-1.11.1/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --no-extstatic \
		-- configure $(@D)
gems: .bundle/gems/fiddle-1.1.8/exts.mk
.bundle/gems/fiddle-1.1.8/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --no-extstatic \
		-- configure $(@D)
gems: .bundle/gems/nkf-0.2.0/exts.mk
.bundle/gems/nkf-0.2.0/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --no-extstatic \
		-- configure $(@D)
gems: .bundle/gems/racc-1.8.1/exts.mk
.bundle/gems/racc-1.8.1/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --no-extstatic \
		-- configure $(@D)
gems: .bundle/gems/rbs-3.10.0/exts.mk
.bundle/gems/rbs-3.10.0/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --no-extstatic \
		-- configure $(@D)
gems: .bundle/gems/syslog-0.3.0/exts.mk
.bundle/gems/syslog-0.3.0/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --no-extstatic \
		-- configure $(@D)
gems: .bundle/gems/win32ole-1.9.2/exts.mk
.bundle/gems/win32ole-1.9.2/exts.mk: FORCE
	$(Q)$(MINIRUBY) $(srcdir)/ext/extmk.rb --make='$(MAKE)' \
		--command-output=$@ $(EXTMK_ARGS) --no-extstatic \
		-- configure $(@D)

.PHONY: FORCE all exts gems
FORCE:
