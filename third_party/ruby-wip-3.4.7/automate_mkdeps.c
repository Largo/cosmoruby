/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Automate mkdeps fixes for Ruby headers                                      │
│                                                                              │
│ This mirrors bin/automate_mkdeps.sh:                                         │
│  - Cleans o/$MODE/srcs|hdrs|incs.txt                                         │
│  - Runs make MODE=$MODE MKDEPS=$MTDEPS -j1 o/$MODE/depend, capturing output  │
│  - Parses mkdeps "path not specified" / "No such file" errors                │
│  - Resolves missing headers using include search order                       │
│  - Adds contextual shim entries to THIRD_PARTY_RUBY_A_INCS (shims) or        │
│    THIRD_PARTY_RUBY_A_HDRS (real headers) in third_party/ruby/ruby.deps.mk   │
│  - Logs stage-1 additions to o/$MODE/automate_mkdeps_stage1.log              │
│                                                                              │
│ Exit codes:                                                                  │
│  0: added entries (or mkdeps failed but fixable)                             │
│  2: no missing headers found                                                 │
│  1: error (stage 2 or resolution failure)                                    │
╚─────────────────────────────────────────────────────────────────────────────*/
#include "libc/calls/calls.h"
#include "libc/calls/struct/stat.h"
#include <ctype.h>
#include <stdbool.h>
#include <stdlib.h>

#include "libc/log/check.h"
#include "libc/mem/mem.h"
#include "libc/limits.h"
#include "libc/stdio/stdio.h"
#include "libc/str/str.h"
#include "libc/time.h"
#include <sys/time.h>

struct Missing {
  char *filename;   /* include token as written */
  char *includer;   /* path of includer */
  int stage2;       /* flag for No such file */
};

struct EntryToAdd {
  char *target;
  char *entry_path;
  char *logline;
};

enum ShimStrategy {
  SHIM_STRATEGY_PER_INCLUDER,  /* One shim per (header, includer) pair */
  SHIM_STRATEGY_PER_HEADER,    /* One shim per unique header */
};

static enum ShimStrategy g_shim_strategy = SHIM_STRATEGY_PER_HEADER;

static const char *kIncludePaths[] = {
    ".",
    "third_party/ruby/include",
    "third_party/ruby",
    "third_party/ruby/prism",
    "third_party/ruby/enc/unicode/15.0.0",
    "third_party/zlib",
    "third_party/ruby/ext/ripper",
    "third_party/ruby/include/ruby",
    "third_party/ruby/enc",
};

static char *ReadWholeFile(const char *path, size_t *out_size) {
  FILE *f = fopen(path, "r");
  if (!f) return NULL;
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  if (n < 0) {
    fclose(f);
    return NULL;
  }
  char *buf = malloc(n + 1);
  if (!buf) {
    fclose(f);
    return NULL;
  }
  size_t r = fread(buf, 1, n, f);
  fclose(f);
  buf[r] = 0;
  if (out_size) *out_size = r;
  return buf;
}

static bool FileExists(const char *path) {
  struct stat st;
  return stat(path, &st) == 0;
}

static char *Join(const char *a, const char *b) {
  size_t na = strlen(a), nb = strlen(b);
  char *s = malloc(na + nb + 2);
  CHECK(s);
  memcpy(s, a, na);
  s[na] = '/';
  memcpy(s + na + 1, b, nb + 1);
  return s;
}

static char *SanitizeComponent(const char *s) {
  size_t n = strlen(s);
  char *out = malloc(n * 4 + 1); /* worst case hex expansion */
  CHECK(out);
  size_t j = 0;
  for (size_t i = 0; i < n; ++i) {
    unsigned char c = s[i];
    if (c == '.' && i + 1 < n && s[i + 1] == '.') {
      memcpy(out + j, "_dotdot", 7);
      j += 7;
      ++i;
      continue;
    }
    if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
        (c >= '0' && c <= '9') || c == '_' || c == '.') {
      out[j++] = tolower(c);
    } else if (c == '/') {
      out[j++] = '+';
    } else {
      out[j++] = '_';
      out[j++] = "0123456789abcdef"[c >> 4];
      out[j++] = "0123456789abcdef"[c & 15];
    }
  }
  out[j] = 0;
  return out;
}

static char *DirName(const char *path) {
  const char *slash = strrchr(path, '/');
  if (!slash) return strdup(".");
  size_t n = slash - path;
  char *d = malloc(n + 1);
  CHECK(d);
  memcpy(d, path, n);
  d[n] = 0;
  return d;
}

static const char *BaseName(const char *path) {
  const char *slash = strrchr(path, '/');
  return slash ? slash + 1 : path;
}

static char *RelativeToRepo(const char *path) {
  char cwd[PATH_MAX];
  CHECK(getcwd(cwd, sizeof(cwd)));
  size_t cwdn = strlen(cwd);
  if (!strncmp(path, cwd, cwdn)) {
    if (path[cwdn] == '/') return strdup(path + cwdn + 1);
    if (path[cwdn] == 0) return strdup(".");
  }
  return strdup(path);
}

static int Mkdirp(const char *path) {
  char *tmp = strdup(path);
  CHECK(tmp);
  for (char *p = tmp + 1; *p; ++p) {
    if (*p == '/') {
      *p = 0;
      mkdir(tmp, 0755);
      *p = '/';
    }
  }
  int rc = mkdir(tmp, 0755);
  free(tmp);
  return rc;
}

static char *StrStripNewline(char *s) {
  size_t n = strlen(s);
  while (n && (s[n - 1] == '\n' || s[n - 1] == '\r')) {
    s[--n] = 0;
  }
  return s;
}

static bool StartsWith(const char *s, const char *p) {
  return strncmp(s, p, strlen(p)) == 0;
}

static int CountBlockEntries(const char *deps_path, const char *block_name) {
  size_t sz = 0;
  char *file = ReadWholeFile(deps_path, &sz);
  if (!file) return -1;
  int count = -1;
  char *save = NULL;
  bool in_block = false;
  for (char *line = strtok_r(file, "\n", &save); line;
       line = strtok_r(NULL, "\n", &save)) {
    if (!in_block) {
      if (!strncmp(line, block_name, strlen(block_name)) &&
          strstr(line, "=")) {
        in_block = true;
        count = 0;
      }
      continue;
    }
    if (line[0] == ' ' || line[0] == '\t') {
      ++count;
    } else {
      break;
    }
  }
  free(file);
  return count;
}

static bool TruncateBlock(const char *deps_path, const char *block_name) {
  size_t sz = 0;
  char *file = ReadWholeFile(deps_path, &sz);
  if (!file) return false;

  size_t lines_cap = 1024, lines_n = 0;
  char **lines = malloc(lines_cap * sizeof(char *));
  CHECK(lines);
  char *p = file;
  while (p && *p) {
    char *nl = strchr(p, '\n');
    if (!nl) nl = p + strlen(p);
    size_t len = nl - p;
    char *line = malloc(len + 1);
    CHECK(line);
    memcpy(line, p, len);
    line[len] = 0;
    if (lines_n == lines_cap) {
      lines_cap *= 2;
      lines = realloc(lines, lines_cap * sizeof(char *));
      CHECK(lines);
    }
    lines[lines_n++] = line;
    p = (*nl) ? nl + 1 : nl;
  }

  bool in_block = false;
  size_t header = (size_t)-1;
  for (size_t i = 0; i < lines_n; ++i) {
    if (!in_block &&
        !strncmp(lines[i], block_name, strlen(block_name)) &&
        strstr(lines[i], "=")) {
      in_block = true;
      header = i;
      free(lines[i]);
      size_t namelen = strlen(block_name);
      size_t line_len = namelen + 3; /* " =\0" */
      lines[i] = malloc(line_len);
      CHECK(lines[i]);
      snprintf(lines[i], line_len, "%s =", block_name);
      continue;
    }
    if (in_block) {
      if (lines[i][0] == ' ' || lines[i][0] == '\t') {
        free(lines[i]);
        lines[i] = NULL;
        continue;
      } else {
        break;
      }
    }
  }

  if (header == (size_t)-1) {
    for (size_t i = 0; i < lines_n; ++i) free(lines[i]);
    free(lines);
    free(file);
    return false;
  }

  /* Compact lines */
  size_t w = 0;
  for (size_t r = 0; r < lines_n; ++r) {
    if (!lines[r]) continue;
    lines[w++] = lines[r];
  }
  lines_n = w;

  FILE *f = fopen(deps_path, "w");
  if (!f) {
    for (size_t i = 0; i < lines_n; ++i) free(lines[i]);
    free(lines);
    free(file);
    return false;
  }
  for (size_t i = 0; i < lines_n; ++i) {
    fputs(lines[i], f);
    fputc('\n', f);
  }
  fclose(f);
  for (size_t i = 0; i < lines_n; ++i) free(lines[i]);
  free(lines);
  free(file);
  return true;
}

static long long GetTimeMillis(void) {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return (long long)tv.tv_sec * 1000LL + tv.tv_usec / 1000;
}

/* Batch-append multiple entries to deps.mk (read once, write once) */
static bool BatchAppendEntries(const char *deps_path,
                               struct EntryToAdd *entries, size_t entries_n) {
  if (!entries_n) return false;

  size_t sz = 0;
  char *file = ReadWholeFile(deps_path, &sz);
  if (!file) return false;

  /* Count lines and split */
  size_t lines_cap = 8192, lines_n = 0;
  char **lines = malloc(lines_cap * sizeof(char *));
  CHECK(lines);
  char *p = file;
  while (p && *p) {
    char *nl = strchr(p, '\n');
    if (!nl) nl = p + strlen(p);
    size_t len = nl - p;
    char *line = malloc(len + 2);
    CHECK(line);
    memcpy(line, p, len);
    line[len] = 0;
    if (lines_n == lines_cap) {
      lines_cap *= 2;
      lines = realloc(lines, lines_cap * sizeof(char *));
      CHECK(lines);
    }
    lines[lines_n++] = line;
    p = (*nl) ? nl + 1 : nl;
  }

  /* Find HDRS and INCS blocks */
  size_t hdrs_header = (size_t)-1;
  size_t incs_header = (size_t)-1;
  for (size_t i = 0; i < lines_n; ++i) {
    if (!strncmp(lines[i], "THIRD_PARTY_RUBY_A_HDRS", 23) && strstr(lines[i], "=")) {
      hdrs_header = i;
    }
    if (!strncmp(lines[i], "THIRD_PARTY_RUBY_A_INCS", 23) && strstr(lines[i], "=")) {
      incs_header = i;
    }
  }

  /* Process each block */
  for (int block = 0; block < 2; ++block) {
    const char *block_name = (block == 0) ? "THIRD_PARTY_RUBY_A_HDRS" : "THIRD_PARTY_RUBY_A_INCS";
    size_t header = (block == 0) ? hdrs_header : incs_header;

    if (header == (size_t)-1) continue;

    /* Ensure header ends with backslash */
    size_t hdrlen = strlen(lines[header]);
    if (lines[header][hdrlen - 1] != '\\') {
      lines[header] = realloc(lines[header], hdrlen + 2);
      CHECK(lines[header]);
      lines[header][hdrlen] = '\\';
      lines[header][hdrlen + 1] = 0;
    }

    /* Find end of block */
    size_t insert_pos = header;
    for (size_t i = header + 1; i < lines_n; ++i) {
      if (lines[i][0] == ' ' || lines[i][0] == '\t') {
        insert_pos = i;
      } else {
        break;
      }
    }

    /* Add all entries for this block */
    for (size_t e = 0; e < entries_n; ++e) {
      if (strcmp(entries[e].target, block_name) != 0) continue;

      /* Check if already exists */
      bool exists = false;
      for (size_t i = header + 1; i <= insert_pos; ++i) {
        char *trim = lines[i];
        while (*trim == ' ' || *trim == '\t') ++trim;
        /* Strip trailing backslash and whitespace for comparison */
        size_t trim_len = strlen(trim);
        while (trim_len > 0 && (trim[trim_len - 1] == '\\' ||
                                trim[trim_len - 1] == ' ' ||
                                trim[trim_len - 1] == '\t')) {
          trim_len--;
        }
        /* Also strip from entry_path for comparison */
        size_t entry_len = strlen(entries[e].entry_path);
        while (entry_len > 0 && (entries[e].entry_path[entry_len - 1] == '\\' ||
                                 entries[e].entry_path[entry_len - 1] == ' ' ||
                                 entries[e].entry_path[entry_len - 1] == '\t')) {
          entry_len--;
        }
        if (trim_len == entry_len && !strncmp(trim, entries[e].entry_path, trim_len)) {
          exists = true;
          break;
        }
      }
      if (exists) continue;

      /* Ensure previous last has backslash if needed */
      if (insert_pos > header) {
        size_t ll = strlen(lines[insert_pos]);
        if (lines[insert_pos][ll - 1] != '\\') {
          lines[insert_pos] = realloc(lines[insert_pos], ll + 2);
          CHECK(lines[insert_pos]);
          lines[insert_pos][ll] = '\\';
          lines[insert_pos][ll + 1] = 0;
        }
      }

      /* Insert new line */
      lines = realloc(lines, (lines_n + 1) * sizeof(char *));
      CHECK(lines);
      for (size_t i = lines_n; i > insert_pos + 1; --i) {
        lines[i] = lines[i - 1];
      }
      lines[insert_pos + 1] = malloc(strlen(entries[e].entry_path) + 2);
      CHECK(lines[insert_pos + 1]);
      sprintf(lines[insert_pos + 1], "\t%s", entries[e].entry_path);
      ++lines_n;
      ++insert_pos;

      /* Update block end positions for remaining blocks */
      if (block == 0 && incs_header != (size_t)-1 && incs_header > header) {
        ++incs_header;
      }
    }
  }

  /* Write out */
  FILE *f = fopen(deps_path, "w");
  if (!f) {
    for (size_t i = 0; i < lines_n; ++i) free(lines[i]);
    free(lines);
    free(file);
    return false;
  }
  for (size_t i = 0; i < lines_n; ++i) {
    fputs(lines[i], f);
    fputc('\n', f);
  }
  fclose(f);

  for (size_t i = 0; i < lines_n; ++i) free(lines[i]);
  free(lines);
  free(file);
  return true;
}

/* Append entry to HDRS/INCS block in deps.mk */
static bool AppendToBlock(const char *deps_path, const char *block_name,
                          const char *entry) {
  size_t sz = 0;
  char *file = ReadWholeFile(deps_path, &sz);
  if (!file) return false;

  /* Count lines and split */
  size_t lines_cap = 1024, lines_n = 0;
  char **lines = malloc(lines_cap * sizeof(char *));
  CHECK(lines);
  char *p = file;
  while (p && *p) {
    char *nl = strchr(p, '\n');
    if (!nl) nl = p + strlen(p);
    size_t len = nl - p;
    char *line = malloc(len + 2);
    CHECK(line);
    memcpy(line, p, len);
    line[len] = 0;
    if (lines_n == lines_cap) {
      lines_cap *= 2;
      lines = realloc(lines, lines_cap * sizeof(char *));
      CHECK(lines);
    }
    lines[lines_n++] = line;
    p = (*nl) ? nl + 1 : nl;
  }

  /* Find block header */
  size_t header = (size_t)-1;
  for (size_t i = 0; i < lines_n; ++i) {
    if (!strncmp(lines[i], block_name, strlen(block_name)) &&
        strstr(lines[i], "=")) {
      header = i;
      break;
    }
  }
  if (header == (size_t)-1) {
    fprintf(stderr, "ERROR: %s not found in %s\n", block_name, deps_path);
    goto fail;
  }

  /* Ensure header ends with backslash */
  size_t hdrlen = strlen(lines[header]);
  if (lines[header][hdrlen - 1] != '\\') {
    lines[header] = realloc(lines[header], hdrlen + 2);
    CHECK(lines[header]);
    lines[header][hdrlen] = '\\';
    lines[header][hdrlen + 1] = 0;
  }

  /* Locate end of block (first non-indented after header) */
  size_t insert_pos = header;
  for (size_t i = header + 1; i < lines_n; ++i) {
    if (lines[i][0] == ' ' || lines[i][0] == '\t') {
      insert_pos = i;
    } else {
      break;
    }
  }
  if (insert_pos == header) {
    insert_pos = header;
  } else {
    /* ensure previous last has backslash */
    size_t ll = strlen(lines[insert_pos]);
    if (lines[insert_pos][ll - 1] != '\\') {
      lines[insert_pos] = realloc(lines[insert_pos], ll + 2);
      CHECK(lines[insert_pos]);
      lines[insert_pos][ll] = '\\';
      lines[insert_pos][ll + 1] = 0;
    }
  }

  /* Check duplicate */
  for (size_t i = header + 1; i <= insert_pos; ++i) {
    char *trim = lines[i];
    while (*trim == ' ' || *trim == '\t') ++trim;
    if (!strcmp(trim, entry)) {
      goto writeout; /* already present */
    }
  }

  /* Insert new line after insert_pos */
  lines = realloc(lines, (lines_n + 1) * sizeof(char *));
  CHECK(lines);
  for (size_t i = lines_n; i > insert_pos + 1; --i) {
    lines[i] = lines[i - 1];
  }
  lines[insert_pos + 1] = malloc(strlen(entry) + 2);
  CHECK(lines[insert_pos + 1]);
  sprintf(lines[insert_pos + 1], "\t%s", entry);
  ++lines_n;

writeout: {
    FILE *f = fopen(deps_path, "w");
    if (!f) goto fail;
    for (size_t i = 0; i < lines_n; ++i) {
      fputs(lines[i], f);
      fputc('\n', f);
    }
    fclose(f);
  }
  for (size_t i = 0; i < lines_n; ++i) free(lines[i]);
  free(lines);
  free(file);
  return true;

fail:
  for (size_t i = 0; i < lines_n; ++i) free(lines[i]);
  free(lines);
  free(file);
  return false;
}

static char *RunMakeCapture(const char *mode, const char *mkdeps, const char *o,
                            const char *outpath) {
  char cmd[4096];

  // First ensure txt files exist (make generates them from Makefile variables)
  snprintf(cmd, sizeof(cmd),
           "make -j1 o/%ssrcs.txt o/%shdrs.txt o/%sincs.txt >/dev/null 2>&1",
           o, o, o);
  system(cmd);

  // Invoke mtdeps directly (bypasses make's caching of o//depend)
  // This ensures we always get fresh dependency errors, even if o//depend exists
  snprintf(cmd, sizeof(cmd),
           "%s -o o/%sdepend -s -r o/%s @o/%ssrcs.txt @o/%shdrs.txt @o/%sincs.txt >%s 2>&1",
           mkdeps, o, o, o, o, o, outpath);
  int rc = system(cmd);
  (void)rc;
  size_t sz = 0;
  char *buf = ReadWholeFile(outpath, &sz);
  if (!buf) {
    fprintf(stderr, "failed to read %s\n", outpath);
  }
  return buf;
}

static char *PathDirname(const char *path) {
  const char *slash = strrchr(path, '/');
  if (!slash) return strdup(".");
  size_t n = slash - path;
  char *d = malloc(n + 1);
  CHECK(d);
  memcpy(d, path, n);
  d[n] = 0;
  return d;
}

/* Normalize path by stripping leading ./ sequences */
static char *NormalizePath(const char *path) {
  if (!path) return NULL;
  const char *p = path;
  /* Strip all leading ./ sequences */
  while (p[0] == '.' && p[1] == '/') {
    p += 2;
  }
  return strdup(p);
}

/* Generate entry path based on shim strategy */
static char *GenerateEntryPath(const char *filename, const char *includer,
                                const char *found, bool is_real_header) {
  if (is_real_header) {
    /* Real header file - always normalize to remove ./ prefix for HDRS list */
    return NormalizePath(found);
  }

  /* Shim file - strategy determines path */
  switch (g_shim_strategy) {
    case SHIM_STRATEGY_PER_INCLUDER: {
      /* One shim per (header, includer) pair */
      char *sf = SanitizeComponent(filename);
      char *si = SanitizeComponent(includer);
      char *path = malloc(strlen("shims/") + strlen(sf) + 1 + strlen(si) + 1);
      CHECK(path);
      sprintf(path, "shims/%s@%s", sf, si);
      free(sf);
      free(si);
      return path;
    }
    case SHIM_STRATEGY_PER_HEADER: {
      /* One shim per unique header - flat sanitized name without @includer */
      char *sf = SanitizeComponent(filename);
      char *path = malloc(strlen("shims/") + strlen(sf) + 1);
      CHECK(path);
      sprintf(path, "shims/%s", sf);
      free(sf);
      return path;
    }
  }
  return NULL; /* unreachable */
}

/* Write stage1 log header if file doesn't exist or is empty */
static void EnsureStage1LogHeader(const char *path) {
  if (FileExists(path)) {
    size_t sz = 0;
    char *existing = ReadWholeFile(path, &sz);
    if (existing && sz > 0 && existing[0] == '#') {
      /* Header already exists */
      free(existing);
      return;
    }
    free(existing);
  }

  /* Create or recreate with header */
  FILE *f = fopen(path, "w");
  if (!f) {
    char *dir = PathDirname(path);
    Mkdirp(dir);
    free(dir);
    f = fopen(path, "w");
  }
  if (f) {
    const char *strategy_name =
        g_shim_strategy == SHIM_STRATEGY_PER_INCLUDER ? "per-includer" : "per-header";

    time_t now = time(NULL);
    struct tm *tm = localtime(&now);
    char timestamp[64];
    strftime(timestamp, sizeof(timestamp), "%a %d %b %Y %H:%M %Z", tm);

    fprintf(f, "# Stage 1 additions log\n");
    fprintf(f, "# Format: FILENAME|INCLUDER|LIST|ENTRY_PATH|FULLPATH\n");
    fprintf(f, "# Created: %s\n", timestamp);
    fprintf(f, "# Strategy: %s\n", strategy_name);
    fclose(f);
  }
}

static void AppendStage1Log(const char *path, const char *line) {
  /* Check if line already exists in the log file */
  if (FileExists(path)) {
    size_t sz = 0;
    char *existing = ReadWholeFile(path, &sz);
    if (existing) {
      char *saveptr = NULL;
      for (char *logline = strtok_r(existing, "\n", &saveptr); logline;
           logline = strtok_r(NULL, "\n", &saveptr)) {
        if (!strcmp(logline, line)) {
          free(existing);
          return; /* Already exists, don't append */
        }
      }
      free(existing);
    }
  }

  FILE *f = fopen(path, "a");
  if (!f) {
    char *dir = PathDirname(path);
    Mkdirp(dir);
    free(dir);
    f = fopen(path, "a");
  }
  if (f) {
    fputs(line, f);
    fputc('\n', f);
    fclose(f);
  }
}

int main(int argc, char *argv[]) {
  bool flag_count = false;
  bool flag_truncate = false;
  bool flag_info = false;
  for (int i = 1; i < argc; ++i) {
    if (!strcmp(argv[i], "--count")) {
      flag_count = true;
    } else if (!strcmp(argv[i], "--truncate")) {
      flag_truncate = true;
    } else if (!strcmp(argv[i], "--info")) {
      flag_info = true;
    } else if (!strcmp(argv[i], "--per-includer")) {
      g_shim_strategy = SHIM_STRATEGY_PER_INCLUDER;
    } else if (!strcmp(argv[i], "--per-header")) {
      g_shim_strategy = SHIM_STRATEGY_PER_HEADER;
    } else if (!strcmp(argv[i], "--help") || !strcmp(argv[i], "-h")) {
      printf("automate_mkdeps: repair Ruby mkdeps missing-header errors\n");
      printf("Usage: %s [OPTIONS]\n", argv[0]);
      printf("\nShim Strategy Options:\n");
      printf("  --per-includer   One shim per (header, includer) pair (most files)\n");
      printf("  --per-header     One shim per unique header with includer comments (default)\n");
      printf("\nOther Options:\n");
      printf("  --count          Print counts of THIRD_PARTY_RUBY_A_HDRS and _INCS entries and exit\n");
      printf("  --truncate       Clear THIRD_PARTY_RUBY_A_HDRS and _INCS sections in ruby.deps.mk and exit\n");
      printf("  --info           Print statistics about current state and exit\n");
      printf("\nThe default mode mirrors bin/automate_mkdeps.sh: cleans txts, runs mkdeps,\n");
      printf("parses missing-header errors, resolves paths using the Ruby include order,\n");
      printf("and appends shim entries to _INCS or real headers to _HDRS.\n");
      return 0;
    } else if (argv[i][0] == '-') {
      fprintf(stderr, "Error: Unknown option '%s'\n", argv[i]);
      fprintf(stderr, "Use --help for usage information\n");
      return 1;
    }
  }

  const char *mode = getenv("MODE");
  if (!mode) mode = "";
  char o_prefix[64];
  if (*mode) {
    snprintf(o_prefix, sizeof(o_prefix), "%s/", mode);
  } else {
    strcpy(o_prefix, "/");
  }
  /* Build o// path prefix like bash script */
  char orel[64];
  if (*mode) {
    snprintf(orel, sizeof(orel), "%s/", mode);
  } else {
    strcpy(orel, "/");
  }

  char mkdeps_default[128];
  snprintf(mkdeps_default, sizeof(mkdeps_default),
           "o/%sthird_party/mexican_toaster/mtdeps", orel);
  const char *mkdeps = getenv("MKDEPS");
  if (!mkdeps || !*mkdeps) mkdeps = mkdeps_default;

  char deps_mk[] = "third_party/ruby/ruby.deps.mk";
  char mkdeps_log[128];
  snprintf(mkdeps_log, sizeof(mkdeps_log), "o/%smkdeps_output.log", orel);
  char stage1_log[160];
  snprintf(stage1_log, sizeof(stage1_log), "o/%sautomate_mkdeps_stage1.log",
           orel);

  if (flag_count || flag_truncate) {
    int hdrs_count = CountBlockEntries(deps_mk, "THIRD_PARTY_RUBY_A_HDRS");
    int incs_count = CountBlockEntries(deps_mk, "THIRD_PARTY_RUBY_A_INCS");
    if (hdrs_count < 0 || incs_count < 0) {
      fprintf(stderr, "Failed to read %s\n", deps_mk);
      return 1;
    }
    if (flag_truncate) {
      if (!TruncateBlock(deps_mk, "THIRD_PARTY_RUBY_A_HDRS") ||
          !TruncateBlock(deps_mk, "THIRD_PARTY_RUBY_A_INCS")) {
        fprintf(stderr, "Failed to truncate sections\n");
        return 1;
      }

      // Truncate stage1 log, keeping first 4 header lines or creating new headers
      if (FileExists(stage1_log)) {
        size_t sz = 0;
        char *logfile = ReadWholeFile(stage1_log, &sz);
        if (logfile && sz > 0 && logfile[0] == '#') {
          // Has existing headers, keep them
          FILE *f = fopen(stage1_log, "w");
          if (f) {
            int line_count = 0;
            char *p = logfile;
            while (p && *p && line_count < 4) {
              char *nl = strchr(p, '\n');
              if (nl) {
                fwrite(p, 1, nl - p + 1, f);
                p = nl + 1;
                ++line_count;
              } else {
                fputs(p, f);
                fputc('\n', f);
                break;
              }
            }
            fclose(f);
          }
          free(logfile);
        } else {
          // No valid headers, create new ones
          if (logfile) free(logfile);
          EnsureStage1LogHeader(stage1_log);
        }
      } else {
        // File doesn't exist, create with headers
        EnsureStage1LogHeader(stage1_log);
      }

      // Delete o//depend and txt files to force make to regenerate dependencies
      char depend_path[128];
      char pathbuf[64];
      snprintf(depend_path, sizeof(depend_path), "o/%sdepend", orel);
      unlink(depend_path);

      snprintf(pathbuf, sizeof(pathbuf), "o/%ssrcs.txt", orel);
      unlink(pathbuf);
      snprintf(pathbuf, sizeof(pathbuf), "o/%shdrs.txt", orel);
      unlink(pathbuf);
      snprintf(pathbuf, sizeof(pathbuf), "o/%sincs.txt", orel);
      unlink(pathbuf);

      printf("Truncated HDRS (%d entries) and INCS (%d entries)\n", hdrs_count,
             incs_count);
      printf("Truncated stage1 log (kept header lines)\n");
      printf("Deleted %s and txt files to force regeneration\n", depend_path);
      return 0;
    } else {
      printf("HDRS entries: %d\nINCS entries: %d\n", hdrs_count, incs_count);
      return 0;
    }
  }

  if (flag_info) {
    // Count HDRS and INCS entries
    int hdrs_count = CountBlockEntries(deps_mk, "THIRD_PARTY_RUBY_A_HDRS");
    int incs_count = CountBlockEntries(deps_mk, "THIRD_PARTY_RUBY_A_INCS");
    if (hdrs_count < 0 || incs_count < 0) {
      fprintf(stderr, "Failed to read %s\n", deps_mk);
      return 1;
    }

    // Count lines in stage1 log
    int stage1_lines = 0;
    if (FileExists(stage1_log)) {
      size_t sz = 0;
      char *logfile = ReadWholeFile(stage1_log, &sz);
      if (logfile) {
        char *p = logfile;
        while (p && *p) {
          char *nl = strchr(p, '\n');
          if (nl) {
            stage1_lines++;
            p = nl + 1;
          } else {
            if (*p) stage1_lines++;
            break;
          }
        }
        free(logfile);
      }
    }

    // Count shim files under shims/
    char shims_count_cmd[256];
    snprintf(shims_count_cmd, sizeof(shims_count_cmd),
             "find shims/ -name '*.h' -o -name '*.c' 2>/dev/null | wc -l");
    FILE *fp = popen(shims_count_cmd, "r");
    int shims_count = 0;
    if (fp) {
      fscanf(fp, "%d", &shims_count);
      pclose(fp);
    }

    printf("Ruby dependency automation status:\n");
    printf("  THIRD_PARTY_RUBY_A_HDRS entries: %d\n", hdrs_count);
    printf("  THIRD_PARTY_RUBY_A_INCS entries: %d\n", incs_count);
    printf("  Stage1 log lines (%s): %d\n", stage1_log, stage1_lines);
    printf("  Shim files (shims/): %d\n", shims_count);
    return 0;
  }

  /* Clean txts */
  printf("Cleaning previous dependency files...\n");
  char pathbuf[64];
  snprintf(pathbuf, sizeof(pathbuf), "o/%ssrcs.txt", orel);
  unlink(pathbuf);
  snprintf(pathbuf, sizeof(pathbuf), "o/%shdrs.txt", orel);
  unlink(pathbuf);
  snprintf(pathbuf, sizeof(pathbuf), "o/%sincs.txt", orel);
  unlink(pathbuf);

  /* Ensure mtdeps is built */
  if (!FileExists(mkdeps)) {
    printf("Building mtdeps (required for dependency analysis)...\n");
    char build_cmd[512];
    snprintf(build_cmd, sizeof(build_cmd), "make MODE=%s -j8 %s", mode, mkdeps);
    int rc = system(build_cmd);
    if (rc != 0) {
      fprintf(stderr, "ERROR: Failed to build mtdeps\n");
      return 1;
    }
  }

  /* Run make/mkdeps */
  printf("Running: make MODE=%s -j1 MKDEPS=%s o/%sdepend\n", mode, mkdeps, orel);
  Mkdirp("o");
  Mkdirp("o/tmp");
  Mkdirp("o/");
  char *output = RunMakeCapture(mode, mkdeps, orel, mkdeps_log);
  if (!output) {
    fprintf(stderr, "failed to run make\n");
    return 1;
  }
  printf("Full make output saved to: o/%smkdeps_output.log\n", orel);

  /* Parse errors */
  size_t miss_cap = 16, miss_n = 0;
  struct Missing *miss = malloc(miss_cap * sizeof(struct Missing));
  CHECK(miss);
  bool stage2 = false;

  char *stage2_filename = NULL;
  char *stage2_line = NULL;
  char *saveptr = NULL;
  for (char *line = strtok_r(output, "\n", &saveptr); line;
       line = strtok_r(NULL, "\n", &saveptr)) {
    if (strstr(line, "path not specified by HDRS/SRCS/INCS")) {
      char *colon = strchr(line, ':');
      if (!colon) continue;
      *colon = 0;
      char *fname = NormalizePath(line);
      *colon = ':';
      char *inc = strstr(line, "included by ");
      char *incpath = NULL;
      if (inc) {
        inc += strlen("included by ");
        char *rp = strchr(inc, ')');
        if (rp) *rp = 0;
        incpath = NormalizePath(inc);
      } else {
        incpath = strdup("");
      }
      if (miss_n == miss_cap) {
        miss_cap *= 2;
        miss = realloc(miss, miss_cap * sizeof(struct Missing));
        CHECK(miss);
      }
      miss[miss_n++] = (struct Missing){fname, incpath, 0};
    } else if (strstr(line, "No such file or directory")) {
      stage2 = true;
      if (!stage2_line) {
        stage2_line = strdup(line);
        char *colon = strchr(line, ':');
        if (colon) {
          *colon = 0;
          stage2_filename = strdup(line);
          *colon = ':';
        }
      }
    }
  }

  if (stage2) {
    fprintf(stderr, "\n");
    fprintf(stderr, "═══════════════════════════════════════════════════════════════\n");
    fprintf(stderr, "STAGE 2 ERROR DETECTED - No such file or directory\n");
    fprintf(stderr, "═══════════════════════════════════════════════════════════════\n");
    fprintf(stderr, "Full error line:\n");
    fprintf(stderr, "  %s\n", stage2_line ? stage2_line : "(unknown)");
    fprintf(stderr, "\n");
    fprintf(stderr, "Parsed FILENAME: %s\n", stage2_filename ? stage2_filename : "(unknown)");
    fprintf(stderr, "INCLUDER: (empty for Stage 2)\n");
    fprintf(stderr, "\n");

    if (stage2_filename) {
      fprintf(stderr, "Context from build output (lines mentioning this file):\n");
      char *ctx_save = NULL;
      char *output_copy = strdup(output);
      int ctx_count = 0;
      for (char *ctx_line = strtok_r(output_copy, "\n", &ctx_save);
           ctx_line && ctx_count < 20;
           ctx_line = strtok_r(NULL, "\n", &ctx_save)) {
        if (strstr(ctx_line, stage2_filename)) {
          fprintf(stderr, "  %s\n", ctx_line);
          ++ctx_count;
        }
      }
      free(output_copy);
      fprintf(stderr, "\n");

      fprintf(stderr, "Searching for %s in third_party/ruby/:\n",
              stage2_filename);
      char find_cmd[512];
      const char *basename_start = strrchr(stage2_filename, '/');
      const char *basename = basename_start ? basename_start + 1 : stage2_filename;
      snprintf(find_cmd, sizeof(find_cmd),
               "find third_party/ruby/ -name '%s' -type f 2>/dev/null | head -10",
               basename);
      system(find_cmd);
      fprintf(stderr, "\n");

      fprintf(stderr, "Checking Stage 1 log for previous processing:\n");
      if (FileExists(stage1_log)) {
        char grep_cmd[512];
        snprintf(grep_cmd, sizeof(grep_cmd),
                 "grep '^%s' %s || echo '  (not found in Stage 1 log)'",
                 basename, stage1_log);
        system(grep_cmd);
      } else {
        fprintf(stderr, "  (Stage 1 log not found)\n");
      }
      fprintf(stderr, "\n");
    }

    fprintf(stderr, "Include paths from ruby.compile.mk:\n");
    for (size_t i = 0; i < sizeof(kIncludePaths) / sizeof(kIncludePaths[0]); ++i) {
      fprintf(stderr, "  %s\n", kIncludePaths[i]);
    }
    fprintf(stderr, "\n");

    fprintf(stderr, "This means the compiler cannot find this file.\n");
    fprintf(stderr, "We need to create a shim/stub header for Cosmopolitan compatibility.\n");
    fprintf(stderr, "\n");
    fprintf(stderr, "Full make output saved to: %s\n", mkdeps_log);
    fprintf(stderr, "Exiting to allow manual inspection...\n");
    fprintf(stderr, "═══════════════════════════════════════════════════════════════\n");

    free(stage2_line);
    free(stage2_filename);
    free(output);
    for (size_t i = 0; i < miss_n; ++i) {
      free(miss[i].filename);
      free(miss[i].includer);
    }
    free(miss);
    return 1;
  }

  if (!miss_n) {
    printf("✓ No missing headers found!\n");
    free(output);
    free(miss);
    return 2;
  }

  printf("Found mkdeps errors. Processing...\n\n");

  // Collect all entries to add before modifying deps.mk
  struct EntryToAdd *entries = malloc(miss_n * sizeof(struct EntryToAdd));
  CHECK(entries);
  size_t entries_n = 0;

  bool any_added = false;
  for (size_t i = 0; i < miss_n; ++i) {
    char *filename = miss[i].filename;
    char *includer = miss[i].includer;

    printf("Stage 1 :- Processing: %s (included by %s)\n", filename, includer);

    char *found = NULL;
    char *incdir = DirName(includer);
    char *cand = Join(incdir, filename);
    if (FileExists(cand)) {
      found = cand;
      printf("  Found in source directory: %s\n", found);
    } else {
      free(cand);
      for (size_t k = 0; k < sizeof(kIncludePaths) / sizeof(kIncludePaths[0]);
           ++k) {
        char *cand2 = Join(kIncludePaths[k], filename);
        if (FileExists(cand2)) {
          found = cand2;
          printf("  Found in -I path %s: %s\n", kIncludePaths[k], found);
          break;
        }
        free(cand2);
      }
    }
    if (!found) {
      fprintf(stderr, "  ✗ ERROR: File not found using C header resolution\n");
      fprintf(stderr, "  Searched:\n");
      fprintf(stderr, "    1. Source directory: %s/%s\n",
              incdir, filename);
      for (size_t k = 0; k < sizeof(kIncludePaths) / sizeof(kIncludePaths[0]);
           ++k) {
        fprintf(stderr, "    2. -I %s/%s\n", kIncludePaths[k], filename);
      }
      fprintf(stderr, "\n");
      free(incdir);
      continue;
    }
    free(incdir);

    bool is_real_header = StartsWith(includer, "shims/");
    char *entry_path = GenerateEntryPath(filename, includer, found, is_real_header);

    const char *target =
        StartsWith(entry_path, "shims/") ? "THIRD_PARTY_RUBY_A_INCS"
                                         : "THIRD_PARTY_RUBY_A_HDRS";

    printf("  Will add to %s: %s\n", target, entry_path);

    char *normalized_found = NormalizePath(found);
    char *rel = RelativeToRepo(normalized_found);
    free(normalized_found);
    char *logline = malloc(2048);
    CHECK(logline);
    snprintf(logline, 2048, "%s|%s|%s|%s|%s", filename, includer,
             target, entry_path, rel);
    free(rel);

    entries[entries_n++] = (struct EntryToAdd){
      .target = strdup(target),
      .entry_path = entry_path,
      .logline = logline
    };

    printf("\n");
    free(found);
  }

  free(output);
  for (size_t i = 0; i < miss_n; ++i) {
    free(miss[i].filename);
    free(miss[i].includer);
  }
  free(miss);

  // Now batch-append all entries to deps.mk (read once, write once!)
  if (entries_n > 0) {
    /* Save original count for stage1 log (need all entries for create_shims.sh) */
    size_t original_entries_n = entries_n;

    /* For per-header and monolithic modes, deduplicate INCS entries for deps.mk
     * (multiple includers may generate same entry_path) */
    if (g_shim_strategy != SHIM_STRATEGY_PER_INCLUDER) {
      size_t deduped_n = 0;
      for (size_t i = 0; i < entries_n; ++i) {
        /* Keep all HDRS entries, deduplicate INCS entries */
        if (strcmp(entries[i].target, "THIRD_PARTY_RUBY_A_HDRS") == 0) {
          entries[deduped_n++] = entries[i];
          continue;
        }
        /* Check if this INCS entry_path already exists in earlier entries */
        bool duplicate = false;
        for (size_t j = 0; j < deduped_n; ++j) {
          if (strcmp(entries[j].target, "THIRD_PARTY_RUBY_A_INCS") == 0 &&
              strcmp(entries[j].entry_path, entries[i].entry_path) == 0) {
            duplicate = true;
            /* Don't free logline yet - we need it for stage1 log! */
            /* Just mark as duplicate by not adding to deduped list */
            break;
          }
        }
        if (!duplicate) {
          entries[deduped_n++] = entries[i];
        }
      }
      if (deduped_n < entries_n) {
        printf("Deduplicated %zu → %zu entries for deps.mk (per-header mode)\n",
               entries_n, deduped_n);
        entries_n = deduped_n;
      }
    }

    printf("Batch-adding %zu entries to deps.mk...\n", entries_n);
    long long t0 = GetTimeMillis();

    /* Ensure stage1 log has header before appending entries */
    EnsureStage1LogHeader(stage1_log);

    if (BatchAppendEntries(deps_mk, entries, entries_n)) {
      any_added = true;
      /* Write ALL original entries to stage1 log (create_shims.sh needs them all) */
      for (size_t i = 0; i < original_entries_n; ++i) {
        AppendStage1Log(stage1_log, entries[i].logline);
      }
    }

    long long t1 = GetTimeMillis();
    printf("  ↳ batch append took %lldms\n", t1 - t0);
    printf("  ✓ Added %zu entries\n", entries_n);

    for (size_t i = 0; i < entries_n; ++i) {
      free(entries[i].target);
      free(entries[i].entry_path);
      free(entries[i].logline);
    }
  }
  free(entries);

  if (any_added) {
    printf("Done! Rerun make to check for more errors.\n");
  }

  return any_added ? 0 : 2;
}
