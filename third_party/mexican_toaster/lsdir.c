/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ lsdir - List directory contents                                             │
│ Simple, portable directory listing for Mexican Toaster                      │
│ Can be invoked as ls, dir, or lsdir                                         │
╚─────────────────────────────────────────────────────────────────────────────*/
#include "libc/calls/calls.h"
#include "libc/calls/struct/dirent.h"
#include "libc/calls/struct/stat.h"
#include "libc/errno.h"
#include "libc/fmt/conv.h"
#include "libc/runtime/runtime.h"
#include "libc/stdio/stdio.h"
#include "libc/str/str.h"
#include "libc/sysv/consts/dt.h"
#include "libc/sysv/consts/s.h"

static void PrintUsage(const char *prog) {
  fprintf(stderr, "Usage: %s [directory]\n", prog);
  fprintf(stderr, "List directory contents\n");
}

int main(int argc, char *argv[]) {
  DIR *dir;
  struct dirent *ent;
  const char *path = ".";

  if (argc > 2) {
    PrintUsage(argv[0]);
    return 1;
  }

  if (argc == 2) {
    if (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0) {
      PrintUsage(argv[0]);
      return 0;
    }
    path = argv[1];
  }

  dir = opendir(path);
  if (!dir) {
    perror(path);
    return 1;
  }

  while ((ent = readdir(dir)) != NULL) {
    // Skip . and .. for cleaner output
    if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0) {
      continue;
    }

    // Simple indicator for directories
    if (ent->d_type == DT_DIR) {
      printf("%s/\n", ent->d_name);
    } else {
      printf("%s\n", ent->d_name);
    }
  }

  closedir(dir);
  return 0;
}
