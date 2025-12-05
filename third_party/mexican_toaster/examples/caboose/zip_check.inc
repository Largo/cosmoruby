static int CheckZip(bool quiet, bool print_ready) {
  struct stat st;
  if (stat("/zip", &st) == -1) {
    fprintf(stderr, "❌ /zip directory not accessible\n");
    fprintf(stderr, "   The embedded ZIP filesystem is not present.\n");
    fprintf(stderr, "   Did you run the packaging script?\n");
    return EX_NOINPUT;
  }
  if (!quiet) printf("✅ /zip directory accessible\n");

  if (stat("/zip/bin/mtsh", &st) == -1) {
    fprintf(stderr, "❌ /zip/bin/mtsh not found\n");
    fprintf(stderr, "   mtsh shell is not embedded.\n");
    return EX_NOINPUT;
  }
  if (!quiet) printf("✅ /zip/bin/mtsh found (%ld bytes)\n", (long)st.st_size);

  if (!(st.st_mode & S_IXUSR)) {
    fprintf(stderr, "⚠️  /zip/bin/mtsh is not executable\n");
  } else if (!quiet) {
    printf("✅ /zip/bin/mtsh is executable\n");
  }

  if (stat("/zip/README.txt", &st) == -1) {
    fprintf(stderr, "⚠️  /zip/README.txt not found (expected content missing)\n");
  } else if (!quiet) {
    printf("✅ /zip/README.txt found (%ld bytes)\n", (long)st.st_size);
  }

  if (stat("/zip/app", &st) == -1) {
    fprintf(stderr, "⚠️  /zip/app directory not found\n");
  } else if (!quiet) {
    printf("✅ /zip/app directory found\n");
  }

  if (print_ready) {
    printf("\n🍞 Ready to toast! Run: caboose.com toast\n");
  }
  return EX_OK;
}

static int EnsureDir(const char *path, mode_t mode) {
  if (mkdir(path, mode) == -1 && errno != EEXIST) {
    perror(path);
    return -1;
  }
  return 0;
}

static int EnsureUpperLayout(const char *upper) {
  char path[PATH_MAX];
  if (EnsureDir(upper, 0700) == -1) return -1;
  if (snprintf(path, sizeof(path), "%s/.toast", upper) >= (int)sizeof(path)) {
    fprintf(stderr, "Path too long: %s/.toast\n", upper);
    return -1;
  }
  if (EnsureDir(path, 0700) == -1) return -1;
  if (snprintf(path, sizeof(path), "%s/.toast/journal", upper) >= (int)sizeof(path)) {
    fprintf(stderr, "Path too long: %s/.toast/journal\n", upper);
    return -1;
  }
  if (EnsureDir(path, 0700) == -1) return -1;
  if (snprintf(path, sizeof(path), "%s/.toast/tomb", upper) >= (int)sizeof(path)) {
    fprintf(stderr, "Path too long: %s/.toast/tomb\n", upper);
    return -1;
  }
  if (EnsureDir(path, 0700) == -1) return -1;
  if (snprintf(path, sizeof(path), "%s/bin", upper) >= (int)sizeof(path)) {
    fprintf(stderr, "Path too long: %s/bin\n", upper);
    return -1;
  }
  if (EnsureDir(path, 0755) == -1) return -1;
  if (snprintf(path, sizeof(path), "%s/tmp", upper) >= (int)sizeof(path)) {
    fprintf(stderr, "Path too long: %s/tmp\n", upper);
    return -1;
  }
  if (EnsureDir(path, 0700) == -1) return -1;
  return 0;
}

static int ProbeUpperWrite(const char *upper) {
  char path[PATH_MAX];
  int fd = -1;
  int rc = -1;
  ssize_t n;
  const char payload[] = "toast overlay probe\n";
  if (snprintf(path, sizeof(path), "%s/.toast/checkXXXXXX", upper) >=
      (int)sizeof(path)) {
    fprintf(stderr, "Path too long for probe\n");
    return -1;
  }
  if ((fd = mkstemp(path)) == -1) {
    perror("mkstemp");
    return -1;
  }
  if ((n = write(fd, payload, sizeof(payload) - 1)) != (ssize_t)(sizeof(payload) - 1)) {
    perror("write");
    goto cleanup;
  }
  if (fsync(fd) == -1) {
    perror("fsync");
    goto cleanup;
  }
  close(fd);
  fd = open(path, O_RDONLY);
  if (fd == -1) {
    perror("reopen");
    goto cleanup;
  }
  char buf[sizeof(payload)];
  memset(buf, 0, sizeof(buf));
  if ((n = read(fd, buf, sizeof(buf) - 1)) < 0) {
    perror("read");
    goto cleanup;
  }
  if (strncmp(buf, payload, sizeof(payload) - 1)) {
    fprintf(stderr, "Probe content mismatch\n");
    goto cleanup;
  }
  rc = 0;
cleanup:
  if (fd != -1) close(fd);
  unlink(path);
  return rc;
}
