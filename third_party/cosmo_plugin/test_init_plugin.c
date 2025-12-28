/*
 * Plugin with init function for testing init_name parameter.
 */

static int g_initialized = 0;
static int g_init_value = 0;

// Init function that should be called by loader
void Init_test_plugin(void) {
  g_initialized = 1;
  g_init_value = 12345;
}

// Check if init was called
int init_was_called(void) {
  return g_initialized;
}

// Get value set by init
int init_get_value(void) {
  return g_init_value;
}

// Simple function for basic testing
int init_double(int x) {
  return x * 2;
}
