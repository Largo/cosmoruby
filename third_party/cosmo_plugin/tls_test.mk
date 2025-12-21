MODE ?= default
COSMOCC ?= .cosmocc/current/bin/cosmocc
AR ?= .cosmocc/current/bin/ar.ape
OBJDUMP ?= .cosmocc/current/bin/x86_64-linux-cosmo-objdump

OUTDIR := o/$(MODE)/third_party/cosmo_plugin
PLUGIN := $(OUTDIR)/tls_plugin.a
LOADER := $(OUTDIR)/tls_loader_test

COMMON := -D_COSMO_SOURCE -I.
TLS_CFLAGS := -fPIC -ftls-model=global-dynamic -Xx86_64-mtls-dialect=gnu2 -Xaarch64-mtls-dialect=desc
LOADER_CFLAGS := -fPIC -pthread
LINK_FLAGS := -pthread

.PHONY: all tls_test clean
all: tls_test

$(OUTDIR):
	mkdir -p "$(OUTDIR)"

$(OUTDIR)/tls_plugin.o: third_party/cosmo_plugin/tls_plugin.c | $(OUTDIR)
	$(COSMOCC) $(COMMON) $(TLS_CFLAGS) -c $< -o $@

$(OUTDIR)/cosmo_plugin.o: third_party/cosmo_plugin/cosmo_plugin.c | $(OUTDIR)
	$(COSMOCC) $(COMMON) $(LOADER_CFLAGS) -c $< -o $@

$(OUTDIR)/tls_loader_test.o: third_party/cosmo_plugin/tls_loader_test.c | $(OUTDIR)
	$(COSMOCC) $(COMMON) $(LOADER_CFLAGS) -c $< -o $@

$(PLUGIN): $(OUTDIR)/tls_plugin.o
	$(AR) rcs $@ $<
	$(OBJDUMP) -r $< | grep -E 'TLSDESC|TPOFF' >/dev/null || (echo "TLS relocations missing in $<" >&2; exit 2)

$(LOADER): $(OUTDIR)/cosmo_plugin.o $(OUTDIR)/tls_loader_test.o
	$(COSMOCC) $(LINK_FLAGS) $^ -o $@
	chmod +x $@

tls_test: $(PLUGIN) $(LOADER)
	$(LOADER) $(PLUGIN)

clean:
	rm -f $(OUTDIR)/tls_plugin.o $(OUTDIR)/cosmo_plugin.o $(OUTDIR)/tls_loader_test.o $(PLUGIN) $(LOADER)
