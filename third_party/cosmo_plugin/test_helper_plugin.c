/*
 * Helper plugin object for cross-object reference testing.
 * This will be linked into the same .a archive as test_basic_plugin.c
 */

// Simple helper function called by basic_plugin
int helper_multiply(int a, int b) {
  return a * b;
}

// Helper with static data
static int g_helper_data = 42;

int helper_get_data(void) {
  return g_helper_data;
}

void helper_set_data(int val) {
  g_helper_data = val;
}
