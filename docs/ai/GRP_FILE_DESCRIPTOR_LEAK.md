# File Descriptor Leak in grp.c

## Problem

`third_party/musl/grp.c` leaks a file descriptor to `/etc/group` on every call to `getgrgid()` or `getgrnam()`. The leak is in `__getgr_a()` which opens the file but never closes it.

Justine left a TODO comment: `/* todo(jart): why does this leak? */`

## Current Fix (Minimal)

Added `fclose(f)` before the `done:` label in `__getgr_a()`. This is the simplest fix but means each lookup opens and closes the file.

## Better Fix (Sketch)

A more elegant solution would refactor the code so that:

1. `__getgr_a()` takes a `FILE*` parameter instead of opening its own
2. Reentrant functions (`getgr_r`) open/close their own file handle
3. Non-reentrant functions (`getgrgid`, `getgrnam`) share `g_getgrent->f` like `getgrent()` does

### Proposed API Change

```c
// Change signature to accept FILE* from caller
int __getgr_a(FILE *f, const char *name, gid_t gid, struct group *gr,
              char **buf, size_t *size, char ***mem, size_t *nmem,
              struct group **res);
```

### Reentrant Version (getgr_r)

```c
static int getgr_r(const char *name, gid_t gid, struct group *gr, char *buf,
                   size_t size, struct group **res) {
    FILE *f;
    char *line = 0;
    size_t len = 0;
    char **mem = 0;
    size_t nmem = 0;
    int rv = 0;
    int cs;

    pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &cs);

    f = fopen("/etc/group", "rbe");
    if (!f) {
        rv = errno;
        *res = 0;
        goto done;
    }

    rv = __getgr_a(f, name, gid, gr, &line, &len, &mem, &nmem, res);
    fclose(f);  // Reentrant version manages its own file handle

    if (*res && size < len + (nmem + 1) * sizeof(char *) + 32) {
        *res = 0;
        rv = ERANGE;
    }
    if (*res) {
        buf += (16 - (uintptr_t)buf) % 16;
        gr->gr_mem = (void *)buf;
        buf += (nmem + 1) * sizeof(char *);
        memcpy(buf, line, len);
        FIX(name);
        FIX(passwd);
        for (size_t i = 0; mem[i]; i++)
            gr->gr_mem[i] = mem[i] - line + buf;
        gr->gr_mem[i] = 0;
    }
    free(mem);
    free(line);
done:
    pthread_setcancelstate(cs, 0);
    if (rv)
        errno = rv;
    return rv;
}
```

### Non-reentrant Versions (getgrgid, getgrnam)

```c
struct group *getgrgid(gid_t gid)
{
    struct group *res;
    size_t size = 0, nmem = 0;

    // Use global file handle like getgrent() does
    if (!g_getgrent->f) {
        g_getgrent->f = fopen("/etc/group", "rbe");
    } else {
        rewind(g_getgrent->f);  // Reset position for fresh search
    }
    if (!g_getgrent->f)
        return 0;

    __getgr_a(g_getgrent->f, 0, gid, &g_getgrent->gr, &g_getgrent->line,
              &size, &g_getgrent->mem, &nmem, &res);
    return res;
}

struct group *getgrnam(const char *name)
{
    struct group *res;
    size_t size = 0, nmem = 0;

    if (!g_getgrent->f) {
        g_getgrent->f = fopen("/etc/group", "rbe");
    } else {
        rewind(g_getgrent->f);
    }
    if (!g_getgrent->f)
        return 0;

    __getgr_a(g_getgrent->f, name, 0, &g_getgrent->gr, &g_getgrent->line,
              &size, &g_getgrent->mem, &nmem, &res);
    return res;
}
```

### Updated __getgr_a()

```c
int __getgr_a(FILE *f, const char *name, gid_t gid, struct group *gr,
              char **buf, size_t *size, char ***mem, size_t *nmem,
              struct group **res) {
    int rv = 0;
    int cs;
    *res = 0;
    pthread_setcancelstate(PTHREAD_CANCEL_DISABLE, &cs);

    // File handle now provided by caller - no fopen/fclose here
    while (!(rv = __getgrent_a(f, gr, buf, size, mem, nmem, res)) && *res) {
        if ((name && !strcmp(name, (*res)->gr_name)) ||
            (!name && (*res)->gr_gid == gid)) {
            break;
        }
    }

    pthread_setcancelstate(cs, 0);
    if (rv)
        errno = rv;
    return rv;
}
```

## Trade-offs

| Approach | Pros | Cons |
|----------|------|------|
| Minimal fix (fclose) | Simple 1-line change | Opens/closes file on every lookup |
| Refactor to shared handle | More efficient, matches getgrent() | ~30 lines changed, needs testing |

## Notes

- The non-reentrant functions (`getgrgid`, `getgrnam`, `getgrent`) are thread-unsafe per POSIX
- Interleaving calls (e.g., `getgrgid()` during `getgrent()` iteration) is undefined behaviour
- The `rewind()` in the refactored version would reset iteration position, but that's expected
- The global state is already cleaned up at exit by `grp_atexit()`

## See Also

- `third_party/musl/grp.c` - implementation
- `third_party/musl/passwd.h` - related structures
