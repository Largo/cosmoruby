// Recursive copy from /zip to real filesystem
// Needed because /zip is userspace-only and we need kernel-visible files

static int CopyFile(const char *src, const char *dst) {
  int src_fd = -1, dst_fd = -1;
  char buf[8192];
  ssize_t n;
  int ret = -1;

  src_fd = open(src, O_RDONLY);
  if (src_fd == -1) {
    fprintf(stderr, "❌ Failed to open %s: %s\n", src, strerror(errno));
    goto cleanup;
  }

  dst_fd = open(dst, O_WRONLY | O_CREAT | O_TRUNC, 0755);
  if (dst_fd == -1) {
    fprintf(stderr, "❌ Failed to create %s: %s\n", dst, strerror(errno));
    goto cleanup;
  }

  while ((n = read(src_fd, buf, sizeof(buf))) > 0) {
    if (write(dst_fd, buf, n) != n) {
      fprintf(stderr, "❌ Failed to write to %s: %s\n", dst, strerror(errno));
      goto cleanup;
    }
  }

  if (n == -1) {
    fprintf(stderr, "❌ Failed to read %s: %s\n", src, strerror(errno));
    goto cleanup;
  }

  ret = 0;

cleanup:
  if (src_fd != -1) close(src_fd);
  if (dst_fd != -1) close(dst_fd);
  return ret;
}

static int CopyDirectoryRecursive(const char *src, const char *dst) {
  DIR *dir;
  struct dirent *ent;
  char src_path[PATH_MAX];
  char dst_path[PATH_MAX];
  struct stat st;

  // Create destination directory
  if (mkdir(dst, 0755) == -1 && errno != EEXIST) {
    fprintf(stderr, "❌ Failed to create directory %s: %s\n", dst, strerror(errno));
    return -1;
  }

  dir = opendir(src);
  if (!dir) {
    fprintf(stderr, "❌ Failed to open directory %s: %s\n", src, strerror(errno));
    return -1;
  }

  while ((ent = readdir(dir)) != NULL) {
    // Skip . and ..
    if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0) {
      continue;
    }

    // Build paths
    if (snprintf(src_path, sizeof(src_path), "%s/%s", src, ent->d_name) >= (int)sizeof(src_path)) {
      fprintf(stderr, "❌ Source path too long\n");
      closedir(dir);
      return -1;
    }

    if (snprintf(dst_path, sizeof(dst_path), "%s/%s", dst, ent->d_name) >= (int)sizeof(dst_path)) {
      fprintf(stderr, "❌ Destination path too long\n");
      closedir(dir);
      return -1;
    }

    // Get file type
    if (lstat(src_path, &st) == -1) {
      fprintf(stderr, "⚠️  Failed to stat %s: %s\n", src_path, strerror(errno));
      continue;
    }

    if (S_ISDIR(st.st_mode)) {
      // Recursive copy for directories
      if (CopyDirectoryRecursive(src_path, dst_path) == -1) {
        closedir(dir);
        return -1;
      }
    } else if (S_ISREG(st.st_mode)) {
      // Copy regular file
      if (CopyFile(src_path, dst_path) == -1) {
        closedir(dir);
        return -1;
      }
    } else {
      // Skip symlinks, devices, etc.
      fprintf(stderr, "⚠️  Skipping non-regular file %s\n", src_path);
    }
  }

  closedir(dir);
  return 0;
}
