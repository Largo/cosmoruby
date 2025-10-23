/* Dl_info definition for Cosmopolitan (dladdr not natively supported) */
#ifndef RUBY_MISSING_DLADDR_H
#define RUBY_MISSING_DLADDR_H

#include <dlfcn.h>

/* Define Dl_info structure since Cosmopolitan doesn't provide it */
typedef struct {
    const char *dli_fname;  /* Pathname of shared object */
    void       *dli_fbase;  /* Base address of shared object */
    const char *dli_sname;  /* Name of symbol */
    void       *dli_saddr;  /* Address of symbol */
} Dl_info;

int dladdr(const void *addr, Dl_info *info);

#endif /* RUBY_MISSING_DLADDR_H */
