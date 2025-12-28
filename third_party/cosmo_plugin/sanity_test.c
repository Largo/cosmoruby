/*
 * Comprehensive sanity tests for cosmo_plugin system.
 * Tests: loading, symbol resolution, cross-object refs, init functions,
 *        export tables, multiple plugins, unloading.
 */

#include "third_party/cosmo_plugin/cosmo_plugin.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TEST(name) \
  do { \
    printf("TEST: %s ... ", name); \
    fflush(stdout); \
  } while (0)

#define PASS() \
  do { \
    printf("PASS\n"); \
    return 0; \
  } while (0)

#define FAIL(msg, ...) \
  do { \
    printf("FAIL: "); \
    printf(msg, ##__VA_ARGS__); \
    printf("\n"); \
    return 1; \
  } while (0)

#define ASSERT(cond, msg, ...) \
  do { \
    if (!(cond)) { \
      FAIL(msg, ##__VA_ARGS__); \
    } \
  } while (0)

// Test export table retrieval
static int test_export_table(void) {
  TEST("export table retrieval");

  size_t count = 0;
  const struct cosmo_export *exports = NULL;

  // This may fail if host doesn't have exports - that's OK
  // We're just testing that it doesn't crash
  exports = cosmo_get_exports(&count);

  // Even if no exports, the function should not crash
  printf("(found %zu exports) ", count);

  if (exports != NULL && count > 0) {
    // Verify first export has valid name and address
    ASSERT(exports[0].name != NULL, "first export has NULL name");
    ASSERT(exports[0].addr != NULL, "first export has NULL addr");
    printf("[%s@%p] ", exports[0].name, exports[0].addr);
  } else {
    printf("(no exports, OK for test loader) ");
  }

  PASS();
}

// Test basic plugin loading
static int test_basic_loading(const char *basic_path) {
  TEST("basic plugin loading");

  struct cosmo_plugin *p = cosmo_load_plugin(basic_path, NULL, NULL);
  ASSERT(p != NULL, "failed to load plugin: %s", basic_path);

  cosmo_unload_plugin(p);
  PASS();
}

// Test symbol resolution
static int test_symbol_resolution(const char *basic_path) {
  TEST("symbol resolution");

  struct cosmo_plugin *p = cosmo_load_plugin(basic_path, NULL, NULL);
  ASSERT(p != NULL, "failed to load plugin");

  // Look up basic_add function
  int (*add_fn)(int, int) = cosmo_plugin_sym(p, "basic_add");
  ASSERT(add_fn != NULL, "failed to find basic_add symbol");

  // Test the function
  int result = add_fn(5, 7);
  ASSERT(result == 12, "basic_add(5, 7) returned %d, expected 12", result);

  cosmo_unload_plugin(p);
  PASS();
}

// Test cross-object references (basic_plugin calls helper_plugin)
static int test_cross_object_refs(const char *basic_path) {
  TEST("cross-object symbol references");

  struct cosmo_plugin *p = cosmo_load_plugin(basic_path, NULL, NULL);
  ASSERT(p != NULL, "failed to load plugin");

  // basic_multiply_via_helper calls helper_multiply from another .o file
  int (*multiply_fn)(int, int) = cosmo_plugin_sym(p, "basic_multiply_via_helper");
  ASSERT(multiply_fn != NULL, "failed to find basic_multiply_via_helper");

  int result = multiply_fn(6, 7);
  ASSERT(result == 42, "multiply(6, 7) returned %d, expected 42", result);

  // Also test direct access to helper function
  int (*helper_get)(void) = cosmo_plugin_sym(p, "helper_get_data");
  ASSERT(helper_get != NULL, "failed to find helper_get_data");

  int data = helper_get();
  ASSERT(data == 42, "helper_get_data() returned %d, expected 42", data);

  cosmo_unload_plugin(p);
  PASS();
}

// Test global data access
static int test_global_data(const char *basic_path) {
  TEST("global data access and modification");

  struct cosmo_plugin *p = cosmo_load_plugin(basic_path, NULL, NULL);
  ASSERT(p != NULL, "failed to load plugin");

  int (*get_counter)(void) = cosmo_plugin_sym(p, "basic_get_counter");
  void (*inc_counter)(void) = cosmo_plugin_sym(p, "basic_inc_counter");
  ASSERT(get_counter != NULL && inc_counter != NULL, "failed to find counter functions");

  int initial = get_counter();
  ASSERT(initial == 100, "initial counter is %d, expected 100", initial);

  inc_counter();
  int after_inc = get_counter();
  ASSERT(after_inc == 101, "after increment counter is %d, expected 101", after_inc);

  cosmo_unload_plugin(p);
  PASS();
}

// Test string constant (.rodata) access
static int test_rodata_access(const char *basic_path) {
  TEST("read-only data (.rodata) access");

  struct cosmo_plugin *p = cosmo_load_plugin(basic_path, NULL, NULL);
  ASSERT(p != NULL, "failed to load plugin");

  const char *(*get_msg)(void) = cosmo_plugin_sym(p, "basic_get_message");
  ASSERT(get_msg != NULL, "failed to find basic_get_message");

  const char *msg = get_msg();
  ASSERT(msg != NULL, "get_message returned NULL");
  ASSERT(strcmp(msg, "Hello from basic_plugin") == 0,
         "message is '%s', expected 'Hello from basic_plugin'", msg);

  cosmo_unload_plugin(p);
  PASS();
}

// Test libc symbol resolution (strlen from host)
static int test_libc_symbols(const char *basic_path) {
  TEST("libc symbol resolution from host");

  struct cosmo_plugin *p = cosmo_load_plugin(basic_path, NULL, NULL);
  ASSERT(p != NULL, "failed to load plugin");

  int (*strlen_fn)(const char *) = cosmo_plugin_sym(p, "basic_string_length");
  ASSERT(strlen_fn != NULL, "failed to find basic_string_length");

  int len = strlen_fn("hello");
  ASSERT(len == 5, "strlen('hello') returned %d, expected 5", len);

  cosmo_unload_plugin(p);
  PASS();
}

// Test calling convention (multiple arguments)
static int test_calling_convention(const char *basic_path) {
  TEST("calling convention (5+ arguments)");

  struct cosmo_plugin *p = cosmo_load_plugin(basic_path, NULL, NULL);
  ASSERT(p != NULL, "failed to load plugin");

  int (*sum_fn)(int, int, int, int, int) = cosmo_plugin_sym(p, "basic_sum_five");
  ASSERT(sum_fn != NULL, "failed to find basic_sum_five");

  int result = sum_fn(1, 2, 3, 4, 5);
  ASSERT(result == 15, "sum_five(1,2,3,4,5) returned %d, expected 15", result);

  cosmo_unload_plugin(p);
  PASS();
}

// Test init function invocation
static int test_init_function(const char *init_path) {
  TEST("init function invocation");

  // Load without init - should not be initialized
  struct cosmo_plugin *p1 = cosmo_load_plugin(init_path, NULL, NULL);
  ASSERT(p1 != NULL, "failed to load plugin without init");

  int (*was_called)(void) = cosmo_plugin_sym(p1, "init_was_called");
  ASSERT(was_called != NULL, "failed to find init_was_called");

  int called1 = was_called();
  ASSERT(called1 == 0, "init was called when it shouldn't be (returned %d)", called1);

  cosmo_unload_plugin(p1);

  // Load with init - should be initialized
  struct cosmo_plugin *p2 = cosmo_load_plugin(init_path, NULL, "Init_test_plugin");
  ASSERT(p2 != NULL, "failed to load plugin with init");

  int (*was_called2)(void) = cosmo_plugin_sym(p2, "init_was_called");
  int (*get_value)(void) = cosmo_plugin_sym(p2, "init_get_value");
  ASSERT(was_called2 != NULL && get_value != NULL, "failed to find init check functions");

  int called2 = was_called2();
  ASSERT(called2 == 1, "init was not called (returned %d)", called2);

  int value = get_value();
  ASSERT(value == 12345, "init value is %d, expected 12345", value);

  cosmo_unload_plugin(p2);
  PASS();
}

// Test loading multiple plugins simultaneously
static int test_multiple_plugins(const char *basic_path, const char *init_path) {
  TEST("multiple plugins loaded simultaneously");

  struct cosmo_plugin *p1 = cosmo_load_plugin(basic_path, NULL, NULL);
  struct cosmo_plugin *p2 = cosmo_load_plugin(init_path, NULL, "Init_test_plugin");

  ASSERT(p1 != NULL && p2 != NULL, "failed to load multiple plugins");
  ASSERT(p1 != p2, "plugins have same handle");

  // Test that both plugins work independently
  int (*add_fn)(int, int) = cosmo_plugin_sym(p1, "basic_add");
  int (*double_fn)(int) = cosmo_plugin_sym(p2, "init_double");

  ASSERT(add_fn != NULL && double_fn != NULL, "failed to find symbols in multiple plugins");

  int r1 = add_fn(10, 20);
  int r2 = double_fn(21);

  ASSERT(r1 == 30, "add returned %d, expected 30", r1);
  ASSERT(r2 == 42, "double returned %d, expected 42", r2);

  cosmo_unload_plugin(p1);
  cosmo_unload_plugin(p2);
  PASS();
}

// Test plugin caching (loading same path twice should return cached plugin)
static int test_plugin_caching(const char *basic_path) {
  TEST("plugin caching (same path loaded twice)");

  struct cosmo_plugin *p1 = cosmo_load_plugin(basic_path, NULL, NULL);
  struct cosmo_plugin *p2 = cosmo_load_plugin(basic_path, NULL, NULL);

  ASSERT(p1 != NULL, "first load failed");
  ASSERT(p2 != NULL, "second load failed");
  ASSERT(p1 == p2, "second load didn't return cached plugin");

  // Don't unload twice - just once since it's the same plugin
  cosmo_unload_plugin(p1);

  PASS();
}

int main(int argc, char **argv) {
  const char *basic_path = argc > 1 ? argv[1] :
      "o/default/third_party/cosmo_plugin/test_basic.a";
  const char *init_path = argc > 2 ? argv[2] :
      "o/default/third_party/cosmo_plugin/test_init.a";

  printf("=== cosmo_plugin Sanity Tests ===\n");
  printf("Basic plugin: %s\n", basic_path);
  printf("Init plugin:  %s\n", init_path);
  printf("\n");

  int failures = 0;

  failures += test_export_table();
  failures += test_basic_loading(basic_path);
  failures += test_symbol_resolution(basic_path);
  failures += test_cross_object_refs(basic_path);
  failures += test_global_data(basic_path);
  failures += test_rodata_access(basic_path);
  failures += test_libc_symbols(basic_path);
  failures += test_calling_convention(basic_path);
  failures += test_init_function(init_path);
  failures += test_multiple_plugins(basic_path, init_path);
  failures += test_plugin_caching(basic_path);

  printf("\n=== Summary ===\n");
  if (failures == 0) {
    printf("All tests PASSED\n");
    return 0;
  } else {
    printf("%d test(s) FAILED\n", failures);
    return 1;
  }
}
