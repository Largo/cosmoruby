#include "third_party/cosmo_plugin/cosmo_plugin.h"

#include "libc/calls/calls.h"
#include "libc/stdio/stdio.h"
#include "libc/stdlib.h"
#include <pthread.h>

struct thread_args {
  struct cosmo_plugin *plugin;
  int (*tls_get)(void);
  int (*tls_inc)(void);
  int result;
};

static void *thread_fn(void *arg) {
  struct thread_args *a = arg;
  if (a->tls_get() != 0) {
    a->result = 1;
    return NULL;
  }
  if (a->tls_inc() != 1) {
    a->result = 2;
    return NULL;
  }
  if (a->tls_get() != 1) {
    a->result = 3;
    return NULL;
  }
  a->result = 0;
  return NULL;
}

int main(int argc, char **argv) {
  const char *plugin_path =
      argc > 1 ? argv[1] : "o/default/third_party/cosmo_plugin/tls_plugin.a";
  printf("Loading plugin: %s\n", plugin_path);
  struct cosmo_plugin *p = cosmo_load_plugin(plugin_path, NULL, NULL);
  if (!p) {
    fprintf(stderr, "failed to load plugin: %s\n", plugin_path);
    return 1;
  }
  printf("Plugin loaded successfully\n");
  printf("Looking up tls_get symbol\n");
  int (*tls_get)(void) = cosmo_plugin_sym(p, "tls_get");
  printf("Looking up tls_inc symbol\n");
  int (*tls_inc)(void) = cosmo_plugin_sym(p, "tls_inc");
  if (!tls_get || !tls_inc) {
    fprintf(stderr, "missing symbols\n");
    return 2;
  }

  int v0 = tls_get();
  printf("tls_get initial: %d\n", v0);
  if (v0 != 0) return 3;
  int v1 = tls_inc();
  printf("tls_inc-> %d\n", v1);
  if (v1 != 1) return 4;
  int v2 = tls_inc();
  printf("tls_inc-> %d\n", v2);
  if (v2 != 2) return 5;
  int v3 = tls_get();
  printf("tls_get after: %d\n", v3);
  if (v3 != 2) return 6;

  pthread_t tid;
  struct thread_args args = {.plugin = p, .tls_get = tls_get, .tls_inc = tls_inc, .result = -1};
  if (pthread_create(&tid, NULL, thread_fn, &args)) {
    perror("pthread_create");
    return 7;
  }
  pthread_join(tid, NULL);
  if (args.result != 0) return 8 + args.result;

  // Ensure main thread counter unchanged by child thread
  if (tls_get() != 2) return 20;

  printf("TLS test passed\n");
  return 0;
}
