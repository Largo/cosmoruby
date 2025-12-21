__thread int g_tls_counter;

int tls_get(void) {
  return g_tls_counter;
}

int tls_inc(void) {
  return ++g_tls_counter;
}

void Init_tls_plugin(void) {
  // no-op init; presence ensures Init_* discovery works if used
  g_tls_counter = 0;
}
