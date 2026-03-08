// State file persistence for Mexican Toaster lifecycle
//
// State is stored as a TOML file at /tmp/toaster-<crc32c>.toml
// keyed by the CRC32C hash of the binary's absolute path.
//
// tomlc99 is parse-only, so we write TOML manually via fprintf.
// Writes use temp-then-rename for atomicity.

#define TOASTER_STATE_FILE_VERSION 1
#define TOASTER_MAX_PERSISTS       64

struct ToasterStateFile {
  enum ToasterState state;
  enum OverlayBackend backend;   // which overlay backend was used
  char binary_path[PATH_MAX];    // absolute path to original binary
  char orig_path[PATH_MAX];      // path to -orig.com backup
  char upper_path[PATH_MAX];     // overlayfs upper layer
  char lower_path[PATH_MAX];     // overlayfs lower layer
  char work_path[PATH_MAX];      // overlayfs work directory
  char mount_path[PATH_MAX];     // overlayfs merged mount point
  int  persist_count;
  char persist_names[TOASTER_MAX_PERSISTS][PATH_MAX];
};

// Derive a deterministic state file path from the binary path.
// Uses CRC32C of the absolute binary path for uniqueness.
//
// We resolve only the directory component (following symlinks in parent
// dirs) and append the original basename, so that the hash is stable
// regardless of the binary's own inode.
static int DeriveStateFilePath(const char *binary_path, char *out,
                               size_t outsz) {
  char abspath[PATH_MAX];
  char dirbuf[PATH_MAX];
  char resolved_dir[PATH_MAX];
  const char *base;

  // Split into directory + basename
  if (snprintf(dirbuf, sizeof(dirbuf), "%s", binary_path) >=
      (int)sizeof(dirbuf))
    return -1;
  base = strrchr(binary_path, '/');
  if (base) {
    base++;  // skip the '/'
    // Truncate dirbuf to just the directory part
    dirbuf[base - binary_path] = '\0';
  } else {
    base = binary_path;
    dirbuf[0] = '.';
    dirbuf[1] = '\0';
  }

  // Resolve only the directory (follows symlinks in parent dirs, not the binary)
  if (!realpath(dirbuf, resolved_dir)) {
    // Directory doesn't exist; fall back to raw path
    if (snprintf(abspath, sizeof(abspath), "%s", binary_path) >=
        (int)sizeof(abspath))
      return -1;
  } else {
    if (snprintf(abspath, sizeof(abspath), "%s/%s", resolved_dir, base) >=
        (int)sizeof(abspath))
      return -1;
  }

  uint32_t hash = crc32c(0, abspath, strlen(abspath));
  if (snprintf(out, outsz, "/tmp/toaster-%08x.toml", hash) >= (int)outsz)
    return -1;
  return 0;
}

// Parse a ToasterState from its string name.
// Returns 0 on success, -1 if unrecognised.
static int ParseStateName(const char *name, enum ToasterState *out) {
  if (!strcmp(name, "cold"))      { *out = kCold;      return 0; }
  if (!strcmp(name, "thawed"))    { *out = kThawed;    return 0; }
  if (!strcmp(name, "frozen"))    { *out = kFrozen;    return 0; }
  if (!strcmp(name, "persisted")) { *out = kPersisted; return 0; }
  return -1;
}

// Load state from a TOML file.  If the file does not exist, the
// state is initialised to kCold with binary_path set.
// Returns 0 on success, -1 on error.
static int LoadStateFile(const char *path, const char *binary_path,
                         struct ToasterStateFile *sf) {
  FILE *fp;
  char errbuf[256];
  toml_table_t *root;
  toml_table_t *section;
  toml_datum_t datum;
  toml_array_t *arr;

  memset(sf, 0, sizeof(*sf));
  sf->state = kCold;
  snprintf(sf->binary_path, sizeof(sf->binary_path), "%s", binary_path);

  fp = fopen(path, "r");
  if (!fp) {
    if (errno == ENOENT)
      return 0;  // no state file yet = kCold
    fprintf(stderr, "Failed to open state file %s: %s\n",
            path, strerror(errno));
    return -1;
  }

  root = toml_parse_file(fp, errbuf, sizeof(errbuf));
  fclose(fp);
  if (!root) {
    fprintf(stderr, "Failed to parse state file %s: %s\n", path, errbuf);
    return -1;
  }

  // [toaster] section
  section = toml_table_in(root, "toaster");
  if (section) {
    datum = toml_string_in(section, "state");
    if (datum.ok) {
      if (ParseStateName(datum.u.s, &sf->state) == -1) {
        fprintf(stderr, "Unknown state '%s' in %s\n", datum.u.s, path);
        free(datum.u.s);
        toml_free(root);
        return -1;
      }
      free(datum.u.s);
    }
    datum = toml_string_in(section, "binary_path");
    if (datum.ok) {
      snprintf(sf->binary_path, sizeof(sf->binary_path), "%s", datum.u.s);
      free(datum.u.s);
    }
    datum = toml_string_in(section, "orig_path");
    if (datum.ok) {
      snprintf(sf->orig_path, sizeof(sf->orig_path), "%s", datum.u.s);
      free(datum.u.s);
    }
  }

  // [overlay] section
  section = toml_table_in(root, "overlay");
  if (section) {
    datum = toml_string_in(section, "backend");
    if (datum.ok) {
      sf->backend = ParseOverlayBackend(datum.u.s);
      free(datum.u.s);
    }
    datum = toml_string_in(section, "upper");
    if (datum.ok) {
      snprintf(sf->upper_path, sizeof(sf->upper_path), "%s", datum.u.s);
      free(datum.u.s);
    }
    datum = toml_string_in(section, "lower");
    if (datum.ok) {
      snprintf(sf->lower_path, sizeof(sf->lower_path), "%s", datum.u.s);
      free(datum.u.s);
    }
    datum = toml_string_in(section, "work");
    if (datum.ok) {
      snprintf(sf->work_path, sizeof(sf->work_path), "%s", datum.u.s);
      free(datum.u.s);
    }
    datum = toml_string_in(section, "mount");
    if (datum.ok) {
      snprintf(sf->mount_path, sizeof(sf->mount_path), "%s", datum.u.s);
      free(datum.u.s);
    }
  }

  // [persist] section
  section = toml_table_in(root, "persist");
  if (section) {
    datum = toml_int_in(section, "count");
    if (datum.ok) {
      sf->persist_count = (int)datum.u.i;
      if (sf->persist_count > TOASTER_MAX_PERSISTS)
        sf->persist_count = TOASTER_MAX_PERSISTS;
    }
    arr = toml_array_in(section, "names");
    if (arr) {
      int n = toml_array_nelem(arr);
      if (n > TOASTER_MAX_PERSISTS)
        n = TOASTER_MAX_PERSISTS;
      for (int i = 0; i < n; i++) {
        datum = toml_string_at(arr, i);
        if (datum.ok) {
          snprintf(sf->persist_names[i], sizeof(sf->persist_names[i]),
                   "%s", datum.u.s);
          free(datum.u.s);
        }
      }
    }
  }

  toml_free(root);
  return 0;
}

// Write a TOML-escaped string value (escapes \, ", and control chars).
static void TomlWriteString(FILE *fp, const char *key, const char *val) {
  fprintf(fp, "%s = \"", key);
  for (const char *s = val; *s; ++s) {
    switch (*s) {
      case '"':  fputs("\\\"", fp); break;
      case '\\': fputs("\\\\", fp); break;
      case '\n': fputs("\\n", fp);  break;
      case '\r': fputs("\\r", fp);  break;
      case '\t': fputs("\\t", fp);  break;
      default:
        if ((unsigned char)*s < 0x20)
          fprintf(fp, "\\u%04x", (unsigned char)*s);
        else
          fputc(*s, fp);
        break;
    }
  }
  fprintf(fp, "\"\n");
}

// Save state to a TOML file.  Uses temp-then-rename for atomicity.
// Returns 0 on success, -1 on error.
static int SaveStateFile(const char *path,
                         const struct ToasterStateFile *sf) {
  char tmp[PATH_MAX];
  FILE *fp;

  if (snprintf(tmp, sizeof(tmp), "%s.tmp", path) >= (int)sizeof(tmp))
    return -1;

  fp = fopen(tmp, "w");
  if (!fp) {
    fprintf(stderr, "Failed to create %s: %s\n", tmp, strerror(errno));
    return -1;
  }

  // [toaster]
  fprintf(fp, "# Mexican Toaster state file (v%d)\n\n", TOASTER_STATE_FILE_VERSION);
  fprintf(fp, "[toaster]\n");
  TomlWriteString(fp, "state", ToasterStateName(sf->state));
  TomlWriteString(fp, "binary_path", sf->binary_path);
  if (sf->orig_path[0])
    TomlWriteString(fp, "orig_path", sf->orig_path);
  fprintf(fp, "\n");

  // [overlay]
  if (sf->backend || sf->upper_path[0] || sf->lower_path[0] ||
      sf->work_path[0] || sf->mount_path[0]) {
    fprintf(fp, "[overlay]\n");
    if (sf->backend)
      TomlWriteString(fp, "backend", OverlayBackendKey(sf->backend));
    if (sf->upper_path[0])
      TomlWriteString(fp, "upper", sf->upper_path);
    if (sf->lower_path[0])
      TomlWriteString(fp, "lower", sf->lower_path);
    if (sf->work_path[0])
      TomlWriteString(fp, "work", sf->work_path);
    if (sf->mount_path[0])
      TomlWriteString(fp, "mount", sf->mount_path);
    fprintf(fp, "\n");
  }

  // [persist]
  if (sf->persist_count > 0) {
    fprintf(fp, "[persist]\n");
    fprintf(fp, "count = %d\n", sf->persist_count);
    fprintf(fp, "names = [\n");
    for (int i = 0; i < sf->persist_count; i++) {
      fprintf(fp, "  \"");
      for (const char *s = sf->persist_names[i]; *s; ++s) {
        switch (*s) {
          case '"':  fputs("\\\"", fp); break;
          case '\\': fputs("\\\\", fp); break;
          case '\n': fputs("\\n", fp);  break;
          case '\r': fputs("\\r", fp);  break;
          case '\t': fputs("\\t", fp);  break;
          default:
            if ((unsigned char)*s < 0x20)
              fprintf(fp, "\\u%04x", (unsigned char)*s);
            else
              fputc(*s, fp);
            break;
        }
      }
      fprintf(fp, "\",\n");
    }
    fprintf(fp, "]\n");
  }

  if (fclose(fp) != 0) {
    fprintf(stderr, "Failed to write %s: %s\n", tmp, strerror(errno));
    unlink(tmp);
    return -1;
  }

  if (rename(tmp, path) == -1) {
    fprintf(stderr, "Failed to rename %s -> %s: %s\n",
            tmp, path, strerror(errno));
    unlink(tmp);
    return -1;
  }

  return 0;
}

// Remove the state file.  Returns 0 on success or if already absent.
static int RemoveStateFile(const char *path) {
  if (unlink(path) == -1 && errno != ENOENT) {
    fprintf(stderr, "Failed to remove %s: %s\n", path, strerror(errno));
    return -1;
  }
  return 0;
}
