// thaw_userland.inc - Portable userspace overlay (no kernel features needed)
//
// Creates a temp directory, copies /zip/ contents into it, and sets it as
// the upper layer. The user modifies files directly in this directory.
// On persist, the upper layer already contains everything (no merge needed).

static void RemoveDirectoryRecursive(const char *path) {
  DIR *dir = opendir(path);
  if (!dir) return;
  struct dirent *ent;
  char child[PATH_MAX];
  while ((ent = readdir(dir)) != NULL) {
    if (!strcmp(ent->d_name, ".") || !strcmp(ent->d_name, ".."))
      continue;
    snprintf(child, sizeof(child), "%s/%s", path, ent->d_name);
    struct stat st;
    if (lstat(child, &st) == 0 && S_ISDIR(st.st_mode))
      RemoveDirectoryRecursive(child);
    else
      unlink(child);
  }
  closedir(dir);
  rmdir(path);
}

static int ThawUserland(const char *prog, struct ToasterStateFile *sf,
                        bool verbose) {
  char upper[PATH_MAX];
  char tmpl[PATH_MAX];
  const char *tmpdir = __get_tmpdir();

  if (!tmpdir || !*tmpdir)
    tmpdir = "/tmp";

  if (snprintf(tmpl, sizeof(tmpl), "%s/toaster-upper-XXXXXX", tmpdir) >=
      (int)sizeof(tmpl)) {
    fprintf(stderr, "Temp path too long\n");
    return -1;
  }

  if (!mkdtemp(tmpl)) {
    fprintf(stderr, "Failed to create upper directory: %s\n", strerror(errno));
    return -1;
  }
  snprintf(upper, sizeof(upper), "%s", tmpl);

  if (verbose)
    printf("Userland overlay: %s\n", upper);

  if (verbose)
    printf("Copying /zip to upper directory...\n");

  if (CopyDirectoryRecursive("/zip", upper) == -1) {
    fprintf(stderr, "Failed to copy /zip to upper directory\n");
    RemoveDirectoryRecursive(upper);
    return -1;
  }

  if (verbose)
    printf("Copied /zip to %s\n", upper);

  snprintf(sf->upper_path, sizeof(sf->upper_path), "%s", upper);
  sf->lower_path[0] = '\0';
  sf->work_path[0] = '\0';
  sf->mount_path[0] = '\0';

  return 0;
}
