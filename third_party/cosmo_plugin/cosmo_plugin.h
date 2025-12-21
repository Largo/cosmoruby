#ifndef THIRD_PARTY_COSMO_PLUGIN_COSMO_PLUGIN_H_
#define THIRD_PARTY_COSMO_PLUGIN_COSMO_PLUGIN_H_
/*
 * Position-independent archive loader for Cosmopolitan.
 * Lives in third_party to avoid touching core libc/build files.
 */

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

struct cosmo_export {
  const char *name;
  void *addr;
};

struct cosmo_plugin;

/**
 * Returns embedded host export table if present.
 * The table comes from __cosmo_exports_start/end symbols emitted by the
 * export generator. Returns NULL if the host was linked without exports.
 */
const struct cosmo_export *cosmo_get_exports(size_t *count_out);

/**
 * Loads a position-independent .a archive as a plugin.
 *
 * @param path path to archive
 * @param host_exports optional host export table (NULL to use cosmo_get_exports)
 * @param init_name optional init symbol to invoke (NULL to skip)
 * @return plugin handle or NULL on error
 */
struct cosmo_plugin *cosmo_load_plugin(const char *path,
                                       const struct cosmo_export *host_exports,
                                       const char *init_name);

/**
 * Looks up a symbol inside a plugin.
 */
void *cosmo_plugin_sym(struct cosmo_plugin *plugin, const char *name);

/**
 * Simple TLS accessor for plugin TLS templates.
 * Returns pointer to per-thread block at given offset; allocates/copies on
 * first access per thread.
 */
void *cosmo_plugin_tls_get(struct cosmo_plugin *plugin, size_t offset);

/**
 * Unloads a plugin (partial; currently frees mappings/metadata).
 */
void cosmo_unload_plugin(struct cosmo_plugin *plugin);

#ifdef __cplusplus
}
#endif

#endif /* THIRD_PARTY_COSMO_PLUGIN_COSMO_PLUGIN_H_ */
