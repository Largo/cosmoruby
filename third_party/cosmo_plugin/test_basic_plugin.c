/*
 * Basic test plugin for cosmo_plugin sanity testing.
 * Tests: basic symbol exports, cross-object references, data access.
 */

#include <string.h>

// External function from helper object (tests cross-object linking)
extern int helper_multiply(int a, int b);

// Global data (tests .data section allocation and relocation)
static int g_counter = 100;
static const char g_message[] = "Hello from basic_plugin";

// Simple function export
int basic_add(int a, int b) {
  return a + b;
}

// Function that accesses global data
int basic_get_counter(void) {
  return g_counter;
}

// Function that modifies global data
void basic_inc_counter(void) {
  g_counter++;
}

// Function that returns string constant address (tests .rodata)
const char *basic_get_message(void) {
  return g_message;
}

// Function that calls helper from another object file
int basic_multiply_via_helper(int a, int b) {
  return helper_multiply(a, b);
}

// Function that uses libc (tests symbol resolution from host)
int basic_string_length(const char *s) {
  return s ? strlen(s) : -1;
}

// Function with multiple arguments (tests calling convention)
int basic_sum_five(int a, int b, int c, int d, int e) {
  return a + b + c + d + e;
}
