# Standalone Makefile for cosmo_plugin sanity tests
# Run with: make -f third_party/cosmo_plugin/sanity_test.mk

MODE ?= default
COSMOCC ?= .cosmocc/current/bin/cosmocc
AR ?= .cosmocc/current/bin/ar.ape
OBJDUMP ?= .cosmocc/current/bin/x86_64-linux-cosmo-objdump

OUTDIR := o/$(MODE)/third_party/cosmo_plugin

# Test artifacts
TEST_BASIC_A := $(OUTDIR)/test_basic.a
TEST_INIT_A := $(OUTDIR)/test_init.a
SANITY_TEST := $(OUTDIR)/sanity_test

# Compiler flags
COMMON := -D_COSMO_SOURCE -I.
PLUGIN_CFLAGS := -fPIC
LOADER_CFLAGS := -fPIC

# Optional debug flag: make COSMO_PLUGIN_DEBUG=1 -f sanity_test.mk
ifdef COSMO_PLUGIN_DEBUG
COMMON += -DCOSMO_PLUGIN_DEBUG
endif

.PHONY: all sanity_test clean help

all: sanity_test

help:
	@echo "cosmo_plugin Sanity Test Suite"
	@echo ""
	@echo "Targets:"
	@echo "  all           - Build and run all tests (default)"
	@echo "  sanity_test   - Build and run sanity tests"
	@echo "  clean         - Remove test artifacts"
	@echo ""
	@echo "Test Coverage:"
	@echo "  - Basic plugin loading"
	@echo "  - Symbol resolution"
	@echo "  - Cross-object references (multi-.o archives)"
	@echo "  - Global data (.data/.bss) access"
	@echo "  - Read-only data (.rodata) access"
	@echo "  - Libc symbol resolution from host"
	@echo "  - Calling conventions (5+ arguments)"
	@echo "  - Init function invocation"
	@echo "  - Multiple plugins loaded simultaneously"
	@echo "  - Plugin caching"

$(OUTDIR):
	mkdir -p "$(OUTDIR)"

# Build test_basic.a (contains two object files: basic + helper)
$(OUTDIR)/test_basic_plugin.o: third_party/cosmo_plugin/test_basic_plugin.c | $(OUTDIR)
	$(COSMOCC) $(COMMON) $(PLUGIN_CFLAGS) -c $< -o $@

$(OUTDIR)/test_helper_plugin.o: third_party/cosmo_plugin/test_helper_plugin.c | $(OUTDIR)
	$(COSMOCC) $(COMMON) $(PLUGIN_CFLAGS) -c $< -o $@

$(TEST_BASIC_A): $(OUTDIR)/test_basic_plugin.o $(OUTDIR)/test_helper_plugin.o
	$(AR) rcs $@ $^
	@echo "Created test archive: $@ ($(shell $(AR) t $@ | wc -l) objects)"

# Build test_init.a
$(OUTDIR)/test_init_plugin.o: third_party/cosmo_plugin/test_init_plugin.c | $(OUTDIR)
	$(COSMOCC) $(COMMON) $(PLUGIN_CFLAGS) -c $< -o $@

$(TEST_INIT_A): $(OUTDIR)/test_init_plugin.o
	$(AR) rcs $@ $<
	@echo "Created test archive: $@ ($(shell $(AR) t $@ | wc -l) objects)"

# Build cosmo_plugin.o and sanity_test loader
$(OUTDIR)/cosmo_plugin.o: third_party/cosmo_plugin/cosmo_plugin.c | $(OUTDIR)
	$(COSMOCC) $(COMMON) $(LOADER_CFLAGS) -c $< -o $@

$(OUTDIR)/sanity_test.o: third_party/cosmo_plugin/sanity_test.c | $(OUTDIR)
	$(COSMOCC) $(COMMON) $(LOADER_CFLAGS) -c $< -o $@

$(SANITY_TEST): $(OUTDIR)/cosmo_plugin.o $(OUTDIR)/sanity_test.o
	$(COSMOCC) $^ -o $@
	chmod +x $@
	@echo "Created test loader: $@"

# Run the tests
sanity_test: $(TEST_BASIC_A) $(TEST_INIT_A) $(SANITY_TEST)
	@echo ""
	@echo "========================================="
	@echo "Running cosmo_plugin sanity tests..."
	@echo "========================================="
	$(SANITY_TEST) $(TEST_BASIC_A) $(TEST_INIT_A)
	@echo ""
	@echo "========================================="
	@echo "All sanity tests completed successfully!"
	@echo "========================================="

clean:
	rm -f $(OUTDIR)/test_basic_plugin.o
	rm -f $(OUTDIR)/test_helper_plugin.o
	rm -f $(OUTDIR)/test_init_plugin.o
	rm -f $(OUTDIR)/cosmo_plugin.o
	rm -f $(OUTDIR)/sanity_test.o
	rm -f $(TEST_BASIC_A)
	rm -f $(TEST_INIT_A)
	rm -f $(SANITY_TEST)
	@echo "Cleaned test artifacts"
