#include "third_party/cosmo_plugin/cosmo_plugin.h"

#include "libc/str/str.h"
#include "third_party/ruby/include/ruby/ruby.h"

// Simple bridge from Ruby to the Cosmo plugin loader.
// This keeps the loader in third_party/ and avoids core libc changes.

void *dln_load_cosmo(const char *path, const char *init_name) {
  const struct cosmo_export *exports = cosmo_get_exports(NULL);
  return cosmo_load_plugin(path, exports, init_name);
}
