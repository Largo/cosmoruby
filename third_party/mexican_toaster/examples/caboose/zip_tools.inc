static const char *FileTypeChar(mode_t mode) {
  if (S_ISDIR(mode)) return "d";
  if (S_ISLNK(mode)) return "l";
  if (S_ISBLK(mode)) return "b";
  if (S_ISCHR(mode)) return "c";
  if (S_ISFIFO(mode)) return "p";
  if (S_ISSOCK(mode)) return "s";
  return "-";
}

static void FormatPermissions(mode_t mode, char *buf) {
  buf[0] = (mode & S_IRUSR) ? 'r' : '-';
  buf[1] = (mode & S_IWUSR) ? 'w' : '-';
  buf[2] = (mode & S_IXUSR) ? 'x' : '-';
  buf[3] = (mode & S_IRGRP) ? 'r' : '-';
  buf[4] = (mode & S_IWGRP) ? 'w' : '-';
  buf[5] = (mode & S_IXGRP) ? 'x' : '-';
  buf[6] = (mode & S_IROTH) ? 'r' : '-';
  buf[7] = (mode & S_IWOTH) ? 'w' : '-';
  buf[8] = (mode & S_IXOTH) ? 'x' : '-';
  buf[9] = '\0';
}

static int ListZip(const char *prog) {
  DIR *dir;
  struct dirent *entry;
  struct stat st;
  char path[PATH_MAX];
  char perms[10];
  struct tm *tm;
  char timebuf[64];

  if (CheckZip(true, false) != EX_OK) {
    fprintf(stderr, "No embedded filesystem found.\n");
    fprintf(stderr, "Run '%s help' for instructions on embedding content.\n",
            prog);
    return EX_NOINPUT;
  }

  dir = opendir("/zip");
  if (!dir) {
    perror("opendir /zip");
    return EX_IOERR;
  }

  printf("Contents of /zip:\n");

  while ((entry = readdir(dir)) != NULL) {
    snprintf(path, sizeof(path), "/zip/%s", entry->d_name);

    if (stat(path, &st) == -1) {
      fprintf(stderr, "stat failed for %s: %s\n", path, strerror(errno));
      continue;
    }

    FormatPermissions(st.st_mode, perms);
    tm = localtime(&st.st_mtim.tv_sec);
    strftime(timebuf, sizeof(timebuf), "%b %d %H:%M", tm);

    printf("%s%s %3ld %5d %5d %8ld %s %s\n",
           FileTypeChar(st.st_mode),
           perms,
           (long)st.st_nlink,
           (int)st.st_uid,
           (int)st.st_gid,
           (long)st.st_size,
           timebuf,
           entry->d_name);
  }

  closedir(dir);
  return EX_OK;
}

static int CatFile(const char *filename) {
  char path[PATH_MAX];
  char buf[4096];
  ssize_t n;
  int fd;

  snprintf(path, sizeof(path), "/zip/%s", filename);

  if ((fd = open(path, O_RDONLY)) == -1) {
    perror(path);
    return EX_NOINPUT;
  }

  while ((n = read(fd, buf, sizeof(buf))) > 0) {
    write(1, buf, n);
  }

  close(fd);
  return EX_OK;
}
