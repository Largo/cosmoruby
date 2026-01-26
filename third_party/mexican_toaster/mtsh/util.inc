// Shared mtsh helpers and builtins
static ssize_t Write(int fd, const char *s) {
  return write(fd, s, strlen(s));
}

static wontreturn void UnsupportedSyntax(unsigned char c) {
  char ibuf[13], cbuf[2] = {c};
  FormatOctal32(ibuf, c, true);
  tinyprint(2, prog, ": unsupported syntax '", cbuf, "' (", ibuf, "): ", cmd,
            "\n", NULL);
  _Exit(4);
}

static void Open(const char *path, int fd, int flags) {
  int tmpfd;
  // use open+dup2 to support things like >/dev/stdout
  if ((tmpfd = open(path, flags, 0644)) == -1) {
    perror(path);
    _Exit(1);
  }
  if (tmpfd != fd) {
    if (dup2(tmpfd, fd) == -1) {
      perror("dup2");
      _Exit(1);
    }
    close(tmpfd);
  }
}

// Add a file redirection to the pending list
static void AddFileRedirect(int fd, int flags, const char *path) {
  if (num_redirects >= ARRAYLEN(redirects)) {
    tinyprint(2, prog, ": error: too many redirections\n", NULL);
    _Exit(15);
  }
  redirects[num_redirects].type = REDIRECT_FILE;
  redirects[num_redirects].fd = fd;
  redirects[num_redirects].flags = flags;
  redirects[num_redirects].path = path;
  num_redirects++;
}

// Add a file descriptor duplication to the pending list
static void AddDupRedirect(int dst_fd, int src_fd) {
  if (num_redirects >= ARRAYLEN(redirects)) {
    tinyprint(2, prog, ": error: too many redirections\n", NULL);
    _Exit(15);
  }
  redirects[num_redirects].type = REDIRECT_DUP;
  redirects[num_redirects].fd = dst_fd;
  redirects[num_redirects].src_fd = src_fd;
  num_redirects++;
}

// Save standard file descriptors (returns encoded saved fds, or -1 on error)
static int SaveStdFds(void) {
  int saved[3];
  saved[0] = dup(0);
  saved[1] = dup(1);
  saved[2] = dup(2);
  if (saved[0] == -1 || saved[1] == -1 || saved[2] == -1) {
    if (saved[0] != -1) close(saved[0]);
    if (saved[1] != -1) close(saved[1]);
    if (saved[2] != -1) close(saved[2]);
    return -1;
  }
  // Encode three fds into one int (assuming fds < 1024)
  return (saved[0] << 20) | (saved[1] << 10) | saved[2];
}

// Restore standard file descriptors from encoded value
static void RestoreStdFds(int encoded) {
  if (encoded == -1) return;
  int saved[3];
  saved[0] = (encoded >> 20) & 0x3FF;
  saved[1] = (encoded >> 10) & 0x3FF;
  saved[2] = encoded & 0x3FF;
  dup2(saved[0], 0);
  dup2(saved[1], 1);
  dup2(saved[2], 2);
  close(saved[0]);
  close(saved[1]);
  close(saved[2]);
}

// Apply all pending redirections in the current process
// Does NOT clear num_redirects (caller must do that)
static void ApplyRedirects(void) {
  for (int i = 0; i < num_redirects; i++) {
    if (redirects[i].type == REDIRECT_FILE) {
      int tmpfd;
      if ((tmpfd = open(redirects[i].path, redirects[i].flags, 0644)) == -1) {
        perror(redirects[i].path);
        _Exit(1);
      }
      if (tmpfd != redirects[i].fd) {
        if (dup2(tmpfd, redirects[i].fd) == -1) {
          perror("dup2");
          _Exit(1);
        }
        close(tmpfd);
      }
    } else if (redirects[i].type == REDIRECT_DUP) {
      if (dup2(redirects[i].src_fd, redirects[i].fd) == -1) {
        perror("dup2");
        _Exit(1);
      }
    }
  }
}

static int SystemExec(void) {
  execvpe(args[0], args, envs);
  perror(args[0]);
  return (n = 0), 127;
}

static int GetSignalByName(const char *s) {
  for (int i = 0; kSignalNames[i].x != MAGNUM_TERMINATOR; ++i) {
    if (!strcmp(s, MAGNUM_STRING(kSignalNames, i) + 3)) {
      return MAGNUM_NUMBER(kSignalNames, i);
    }
  }
  return 0;
}

static void PutEnv(char **p, char *kv) {
  struct Env e;
  e = __getenv(p, kv);
  char *copy = strdup(kv);
  if (!copy) {
    tinyprint(2, "mtsh: strdup failed\n", NULL);
    _Exit(1);
  }
  /* Save old pointer before overwriting - e.s points to middle of string,
   * but p[e.i] is the original strdup'd pointer we need to free */
  char *old = e.s ? p[e.i] : NULL;
  p[e.i] = copy;
  if (!old) {
    p[e.i + 1] = 0;  /* New variable, add null terminator */
  } else {
    free(old);  /* Free the original pointer, not e.s which points to middle */
  }
}

static void UnsetEnv(char **p, const char *k) {
  int i;
  struct Env e;
  if ((e = __getenv(p, k)).s) {
    p[e.i] = 0;
    for (i = e.i + 1; p[i]; ++i) {
      p[i - 1] = p[i];
      p[i] = 0;
    }
  }
}

static void Append(int c) {
  npassert(q + 1 < argbuf + sizeof(argbuf));
  *q++ = c;
}

static char *Finish(void) {
  char *s = r;
  Append(0);
  r = q;
  if (!assign) {
    return s;
  } else {
    PutEnv(envs, s);
    assign = 0;
    return TOMBSTONE;
  }
}

static int Pause(void) {
  pause();
  return 0;
}

static int True(void) {
  return 0;
}

static int False(void) {
  return 1;
}

static wontreturn void Exit(void) {
  _Exit(n > 1 ? atoi(args[1]) : 0);
}

static int Waiter(int pid) {
  int ws;
  n = 0;
  if (waitpid(pid, &ws, 0) == -1) {
    perror("wait");
    return 1;
  }
  if (WIFEXITED(ws)) {
    return WEXITSTATUS(ws);
  } else {
    return 128 + WTERMSIG(ws);
  }
}

static int Wait(void) {
  int e, ws, pid;
  if (n > 1) {
    if ((pid = atoi(args[1])) <= 0) {
      tinyprint(2, "wait: bad pid\n", NULL);
      return 1;
    }
    return Waiter(pid);
  } else {
    for (n = 0, e = errno;;) {
      if (waitpid(-1, &ws, 0) == -1) {
        if (errno == ECHILD) {
          errno = e;
          break;
        }
        perror("wait");
        return 1;
      }
    }
    return 0;
  }
}

static const char *GetOptArg(int c, int *i, int j) {
  if (args[*i][j] == c) {
    if (args[*i][j + 1]) {
      return args[*i] + j + 1;
    } else if (*i + 1 < n) {
      return args[++*i];
    }
  }
  return 0;
}

static int Echo(void) {
  int i = 1;
  bool once = false;
  bool print_newline = true;
  if (i < n && args[i][0] == '-' && args[i][1] == 'n' && !args[i][2]) {
    ++i, print_newline = false;
  }
  for (; i < n; ++i) {
    if (once) {
      Write(1, " ");
    } else {
      once = true;
    }
    Write(1, args[i]);
  }
  if (print_newline) {
    Write(1, "\n");
  }
  return 0;
}

static int NeedArgument(const char *prog) {
  tinyprint(2, prog, ": missing argument\n", NULL);
  return 1;
}

static int Flock(void) {
  int fd;
  int i = 1;
  char *endptr;
  int mode = LOCK_EX;
  if (i < n && args[i][0] == '-' && args[i][1] == 'x' && !args[i][2]) {
    ++i, mode = LOCK_EX;
  }
  if (i < n && args[i][0] == '-' && args[i][1] == 's' && !args[i][2]) {
    ++i, mode = LOCK_SH;
  }
  if (i == n) {
    return NeedArgument("flock");
  }
  if (i + 1 != n) {
    tinyprint(2, "flock: too many arguments\n", NULL);
    return 1;
  }
  fd = strtol(args[i], &endptr, 10);
  if (*endptr) {
    tinyprint(2, "flock: need a number\n", NULL);
    return 1;
  }
  if (flock(fd, mode)) {
    perror("flock");
    return 1;
  }
  return 0;
}

static int Chmod(void) {
  int i, mode;
  char *endptr;
  if (n < 3) {
    return NeedArgument("chmod");
  }
  mode = strtol(args[1], &endptr, 8);
  if (*endptr) {
    tinyprint(2, "chmod: bad octal mode\n", NULL);
    return 1;
  }
  for (i = 2; i < n; ++i) {
    if (chmod(args[i], mode)) {
      perror(args[i]);
      return 1;
    }
  }
  return 0;
}

static int Pwd(void) {
  int got;
  char path[PATH_MAX];
  if ((got = __getcwd(path, PATH_MAX - 1)) != -1) {
    Write(1, path);
    Write(1, "\n");
    return 0;
  } else {
    perror("pwd");
    return 1;
  }
}

static int CatDump(const char *path, int fd, bool dontclose) {
  ssize_t rc;
  char buf[512];
  for (;;) {
    rc = read(fd, buf, sizeof(buf));
    if (rc == -1) {
      perror(path);
      if (!dontclose) {
        close(fd);
      }
      return 1;
    }
    if (!rc)
      break;
    rc = write(1, buf, rc);
    if (rc == -1) {
      perror("write");
      if (!dontclose) {
        close(fd);
      }
      return 1;
    }
  }
  if (!dontclose && close(fd)) {
    perror(path);
    return 1;
  }
  return 0;
}

static int Cat(void) {
  int i, fd, rc;
  if (n < 2) {
    return CatDump("<stdin>", 0, true);
  } else {
    for (i = 1; i < n; ++i) {
      bool dontclose = false;
      if (args[i][0] == '-' && !args[i][1]) {
        dontclose = true;
        fd = 0;
      } else if ((fd = open(args[i], O_RDONLY)) == -1) {
        perror(args[i]);
        return 1;
      }
      if ((rc = CatDump(args[i], fd, dontclose))) {
        return rc;
      }
    }
  }
  return 0;
}

static int Mktemp(void) {
  int fd;
  char template[PATH_MAX + 1];
  if (n == 2) {
    strlcpy(template, args[1], sizeof(template));
  } else {
    strlcpy(template, __get_tmpdir(), sizeof(template));
    strlcat(template, "tmp.XXXXXX", sizeof(template));
  }
  if ((fd = mkstemp(template)) == -1) {
    perror("mkstemp");
    return 1;
  }
  strlcat(template, "\n", sizeof(template));
  Write(1, template);
  close(fd);
  return 0;
}

static int Read(void) {
  unsigned char c;
  int i, j, rc = 1;
  for (i = 1; i < n; ++i) {
    if (args[i][0] != '-')
      break;
    if (args[i][1] == 'p' && !args[i][2] && i + 1 < n) {
      Write(1, args[++i]);
    }
  }
  if (i >= n)
    return 1;
  for (j = 0; args[i][j]; ++j) {
    Append(args[i][j]);
  }
  Append('=');
  while (read(0, &c, 1) > 0) {
    if (c == '\n')
      break;
    Append(c);
    rc = 0;
  }
  PutEnv(envs, Finish());
  return rc;
}

static int Cd(void) {
  const char *s;
  if (!(s = n > 1 ? args[1] : __getenv(envs, "HOME").s))
    return NeedArgument("cd");
  if (!chdir(s)) {
    return 0;
  } else {
    perror(s);
    return 1;
  }
}

static int Mkdir(void) {
  int i, j;
  int mode = 0755;
  const char *arg;
  int (*mkdir_impl)(const char *, unsigned) = mkdir;
  for (i = 1; i < n; ++i) {
    if (args[i][0] == '-' && args[i][1]) {
      if (args[i][1] == '-' && !args[i][2]) {
        ++i;  // rm -- terminates option parsing
        break;
      }
      for (j = 1; j < args[i][j]; ++j) {
        if (args[i][j] == 'p') {
          mkdir_impl = makedirs;  // mkdir -p creates parents
          continue;
        }
        if ((arg = GetOptArg('m', &i, j))) {
          mode = strtol(arg, 0, 8);  // mkdir -m OCTAL sets mode
          break;
        }
        char option[2] = {args[i][j]};
        tinyprint(2, "mkdir", ": illegal option -- ", option, "\n", NULL);
        return 1;
      }
    } else {
      break;
    }
  }
  if (i == n) {
    return NeedArgument("mkdir");
  }
  for (; i < n; ++i) {
    if (mkdir_impl(args[i], mode)) {
      perror(args[i]);
      return 1;
    }
  }
  return 0;
}

static int Kill(void) {
  int sig, rc = 0, i = 1;
  if (i < n && args[i][0] == '-') {
    sig = GetSignalByName(args[i++] + 1);
    if (!sig)
      return -1;  // fallback to system kill command
  } else {
    sig = SIGTERM;
  }
  for (; i < n; ++i) {
    if (kill(atoi(args[i]), sig)) {
      perror("kill");
      rc = 1;
    }
  }
  return rc;
}

static int Toupper(void) {
  int i, n;
  char b[512];
  while ((n = read(0, b, 512)) > 0) {
    for (i = 0; i < n; ++i) {
      b[i] = toupper(b[i]);
    }
    write(1, b, n);
  }
  return 0;
}

static int Usleep(void) {
  int f;
  struct timespec t;
  if (n > 1) {
    f = 0;
    t = timespec_frommicros(atoi(args[1]));
  } else {
    f = TIMER_ABSTIME;
    t = timespec_max;
  }
  return clock_nanosleep(0, f, &t, 0);
}

static int Test(void) {
  int w, m = n;
  struct stat st;
  if (m && READ16LE(args[m - 1]) == READ16LE("]"))
    --m;
  if (m == 4) {
    w = READ32LE(args[2]) & 0x00ffffff;
    if ((w & 65535) == READ16LE("="))
      return !!strcmp(args[1], args[3]);
    if (w == READ24("=="))
      return !!strcmp(args[1], args[3]);
    if (w == READ24("!="))
      return !strcmp(args[1], args[3]);
  } else if (m == 3) {
    w = READ32LE(args[1]) & 0x00ffffff;
    if (w == READ24("-n"))
      return !(strlen(args[2]) > 0);
    if (w == READ24("-z"))
      return !(strlen(args[2]) == 0);
    if (w == READ24("-e"))
      return !!stat(args[2], &st);
    if (w == READ24("-f"))
      return !(!stat(args[2], &st) && S_ISREG(st.st_mode));
    if (w == READ24("-d"))
      return !(!stat(args[2], &st) && S_ISDIR(st.st_mode));
    if (w == READ24("-h"))
      return !(!stat(args[2], &st) && S_ISLNK(st.st_mode));
  }
  return -1;  // fall back to system test command
}

static int Rm(void) {
  int i, j;
  bool force = false;
  for (i = 1; i < n; ++i) {
    if (args[i][0] == '-' && args[i][1]) {
      if (args[i][1] == '-' && !args[i][2]) {
        ++i;  // rm -- terminates option parsing
        break;
      }
      for (j = 1; j < args[i][j]; ++j) {
        if (args[i][j] == 'f') {
          force = true;  // rm -f forces removal
          continue;
        }
        char option[2] = {args[i][j]};
        tinyprint(2, "rm", ": illegal option -- ", option, "\n", NULL);
        return 1;
      }
    } else {
      break;
    }
  }
  if (i == n) {
    return NeedArgument("rm");
  }
  for (; i < n; ++i) {
    struct stat st;
    if ((!force && (lstat(args[i], &st) ||
                    (!S_ISLNK(st.st_mode) && access(args[i], W_OK)))) ||
        unlink(args[i])) {
      if (force && errno == ENOENT)
        continue;
      perror(args[i]);
      return 1;
    }
  }
  return 0;
}

static int Rmdir(void) {
  int i;
  for (i = 1; i < n; ++i) {
    if (rmdir(args[i])) {
      perror(args[i]);
      return 1;
    }
  }
  return 0;
}

static int Touch(void) {
  int i;
  if (n > 1 && args[1][0] != '-') {
    for (i = 1; i < n; ++i) {
      if (touch(args[i], 0644)) {
        perror(args[i]);
        return 1;
      }
    }
    return 0;
  } else {
    return -1;  // fall back to system rmdir command
  }
}

static int Shift(int i) {
  if (i <= n) {
    memmove(args, args + i, (n - i + 1) * sizeof(*args));
    n -= i;
  }
  return 0;
}

static int Fake(int main(int, char **), bool wantexec) {
  int pid;
  if (wantexec) {
    goto RunProgram;
  }
  if ((pid = fork()) == -1) {
    perror("fork");
    return 127;
  }
  if (!pid) {
  RunProgram:
    // TODO(jart): Maybe nuke stdio too?
    if (_weaken(optind)) {
      *_weaken(optind) = 1;
    }
    environ = envs;
    exit(main(n, args));
  }
  return Waiter(pid);
}

static int Env(void) {
  int i, j;
  const char *arg;
  char term = '\n';
  for (i = 1; i < n; ++i) {
    if (args[i][0] == '-') {
      if (!args[i][1]) {
        envs[0] = 0;  // env - clears environment
        continue;
      }
      for (j = 1; j < args[i][j]; ++j) {
        if (args[i][j] == 'i') {
          envs[0] = 0;  // env -i clears environment
          continue;
        }
        if (args[i][j] == '0') {
          term = 0;  // env -0 uses '\0' line separator
          continue;
        }
        if ((arg = GetOptArg('u', &i, j))) {
          UnsetEnv(envs, arg);  // env -u VAR removes variable
          break;
        }
        char option[2] = {args[i][j]};
        tinyprint(2, "env", ": illegal option -- ", option, "\n", NULL);
        return 1;
      }
      continue;
    }
    if (strchr(args[i], '=')) {
      PutEnv(envs, args[i]);
    } else {
      Shift(i);
      return ShellSpawn();
    }
  }
  for (i = 0; envs[i]; ++i) {
    Write(1, envs[i]);
    write(1, &term, 1);
  }
  return 0;
}

static wontreturn void Exec(void) {
  Shift(1);
  if (!ShellExec()) {
    _Exit(0);  // can happen for builtins
  } else {
    perror("exec");
    _Exit(127);  // sh exec never returns
  }
}

static int Help(void) {
  tinyprint(1, "mtsh - Mexican Toaster Shell\n", NULL);
  tinyprint(1, "Built-in commands:\n", NULL);
  tinyprint(1, "  :           No-op (true)\n", NULL);
  tinyprint(1, "  cat         Concatenate files\n", NULL);
  tinyprint(1, "  cd          Change directory\n", NULL);
  tinyprint(1, "  chmod       Change file mode\n", NULL);
  tinyprint(1, "  command     Find command in PATH (-v flag)\n", NULL);
  tinyprint(1, "  echo        Print arguments\n", NULL);
  tinyprint(1, "  env         Print/modify environment\n", NULL);
  tinyprint(1, "  exec        Replace shell with command\n", NULL);
  tinyprint(1, "  exit        Exit shell\n", NULL);
  tinyprint(1, "  false       Return false\n", NULL);
  tinyprint(1, "  flock       Apply/remove advisory lock\n", NULL);
  tinyprint(1, "  help        Show this help\n", NULL);
  tinyprint(1, "  kill        Send signal to process\n", NULL);
  tinyprint(1, "  mkdir       Create directory\n", NULL);
  tinyprint(1, "  mktemp      Create temporary file\n", NULL);
  tinyprint(1, "  pause       Wait for signal\n", NULL);
  tinyprint(1, "  pwd         Print working directory\n", NULL);
  tinyprint(1, "  read        Read line from input\n", NULL);
  tinyprint(1, "  rm          Remove files\n", NULL);
  tinyprint(1, "  rmdir       Remove directory\n", NULL);
  tinyprint(1, "  test/[      Test conditions\n", NULL);
  tinyprint(1, "  touch       Update file timestamp\n", NULL);
  tinyprint(1, "  toupper     Convert stdin to uppercase\n", NULL);
  tinyprint(1, "  true        Return true\n", NULL);
  tinyprint(1, "  usleep      Sleep microseconds\n", NULL);
  tinyprint(1, "  wait        Wait for process\n", NULL);
  tinyprint(1, "\nExternal commands (if linked):\n", NULL);
  tinyprint(1, "  awk         Pattern scanning\n", NULL);
  tinyprint(1, "  curl        Transfer data from URLs\n", NULL);
  tinyprint(1, "  sed         Stream editor\n", NULL);
  tinyprint(1, "  tr          Translate characters\n", NULL);
  tinyprint(1, "\nFeatures:\n", NULL);
  tinyprint(1, "  ( )         Subshell grouping\n", NULL);
  tinyprint(1, "  $( )        Command substitution\n", NULL);
  tinyprint(1, "  ` `         Command substitution (backticks)\n", NULL);
  tinyprint(1, "  #           Comments\n", NULL);
  tinyprint(1, "  |           Pipes\n", NULL);
  tinyprint(1, "  &&          Conditional AND\n", NULL);
  tinyprint(1, "  ||          Conditional OR\n", NULL);
  tinyprint(1, "  &           Background jobs\n", NULL);
  return 0;
}

static int Command(void) {
  // Implement 'command -v name' to find commands in PATH
  if (n == 3 && !strcmp(args[1], "-v")) {
    char *path = __getenv(envs, "PATH").s;
    if (!path) path = "/bin:/usr/bin";
    char pathbuf[PATH_MAX];
    char *p = path;
    while (*p) {
      char *colon = strchr(p, ':');
      size_t len = colon ? (size_t)(colon - p) : strlen(p);
      if (len > 0 && len + 1 + strlen(args[2]) + 1 < sizeof(pathbuf)) {
        memcpy(pathbuf, p, len);
        pathbuf[len] = '/';
        strcpy(pathbuf + len + 1, args[2]);
        if (!access(pathbuf, X_OK)) {
          tinyprint(1, pathbuf, "\n", NULL);
          return 0;
        }
      }
      if (!colon) break;
      p = colon + 1;
    }
    return 127;
  }
  tinyprint(2, prog, ": command: unsupported usage\n", NULL);
  return 2;
}

static int TryBuiltin(bool wantexec) {
  if (!n)
    return exitstatus;
  if (!strcmp(args[0], "exit"))
    Exit();
  if (!strcmp(args[0], "exec"))
    Exec();
  if (!strcmp(args[0], "help"))
    return Help();
  if (!strcmp(args[0], "command"))
    return Command();
  if (!strcmp(args[0], "cd"))
    return Cd();
  if (!strcmp(args[0], "rm"))
    return Rm();
  if (!strcmp(args[0], "["))
    return Test();
  if (!strcmp(args[0], "cat"))
    return Cat();
  if (!strcmp(args[0], "env"))
    return Env();
  if (!strcmp(args[0], "pwd"))
    return Pwd();
  if (!strcmp(args[0], "wait"))
    return Wait();
  if (!strcmp(args[0], "echo"))
    return Echo();
  if (!strcmp(args[0], "read"))
    return Read();
  if (!strcmp(args[0], "true"))
    return True();
  if (!strcmp(args[0], ":"))
    return True();
  if (!strcmp(args[0], "test"))
    return Test();
  if (!strcmp(args[0], "kill"))
    return Kill();
  if (!strcmp(args[0], "pause"))
    return Pause();
  if (!strcmp(args[0], "flock"))
    return Flock();
  if (!strcmp(args[0], "chmod"))
    return Chmod();
  if (!strcmp(args[0], "touch"))
    return Touch();
  if (!strcmp(args[0], "rmdir"))
    return Rmdir();
  if (!strcmp(args[0], "mkdir"))
    return Mkdir();
  if (!strcmp(args[0], "false"))
    return False();
  if (!strcmp(args[0], "mktemp"))
    return Mktemp();
  if (!strcmp(args[0], "usleep"))
    return Usleep();
  if (!strcmp(args[0], "toupper"))
    return Toupper();
  if (!strcmp(args[0], "tr"))
    return Fake(_tr, wantexec);
  if (!strcmp(args[0], "sed"))
    return Fake(_sed, wantexec);
  if (_weaken(_awk) && strcmp(args[0], "awk"))
    return Fake(_weaken(_awk), wantexec);
  if (_weaken(_curl) && !strcmp(args[0], "curl")) {
    return Fake(_weaken(_curl), wantexec);
  }
  return -1;
}

static int ShellExec(void) {
  int rc;
  if ((rc = TryBuiltin(true)) == -1) {
    ApplyRedirects();
    num_redirects = 0;
    rc = SystemExec();
  } else {
    // Builtin was executed, clear any pending redirects
    num_redirects = 0;
  }
  return (n = 0), rc;
}

static void Pipe(void) {
  int pid, pfds[2];
  if (pipe2(pfds, O_CLOEXEC)) {
    perror("pipe");
    _Exit(127);
  }
  if ((pid = fork()) == -1) {
    perror("fork");
    _Exit(127);
  }
  if (!pid) {
    unassert(dup2(pfds[1], 1) == 1);
    // we can't rely on cloexec because builtins
    if (pfds[0] != 1)
      unassert(!close(pfds[0]));
    if (pfds[1] != 1)
      unassert(!close(pfds[1]));
    _Exit(ShellExec());
  }
  unassert(dup2(pfds[0], 0) == 0);
  if (pfds[0] != 0)
    unassert(!close(pfds[0]));
  if (pfds[1] != 0)
    unassert(!close(pfds[1]));
  n = 0;
}

static int ShellSpawn(void) {
  int rc, pid;
  int saved_fds = -1;

  // If there are redirections, save parent's fds and apply redirects
  if (num_redirects > 0) {
    saved_fds = SaveStdFds();
    ApplyRedirects();
  }

  if ((rc = TryBuiltin(false)) == -1) {
    // Not a builtin - need to fork and exec
    // Restore parent's fds before forking
    RestoreStdFds(saved_fds);

    switch ((pid = fork())) {
      case 0:
        // Child: Re-apply redirects since parent restored them
        ApplyRedirects();
        num_redirects = 0;
        _Exit(SystemExec());
      default:
        num_redirects = 0;
        rc = Waiter(pid);
        break;
      case -1:
        perror("fork");
        num_redirects = 0;
        rc = 127;
        break;
    }
  } else {
    // Builtin was executed with redirects applied - restore parent's fds
    RestoreStdFds(saved_fds);
    num_redirects = 0;
  }
  return (n = 0), rc;
}

static void ShellSpawnAsync(void) {
  switch ((lastchild = fork())) {
    case 0:
      _Exit(ShellExec());
    default:
      break;
    case -1:
      perror("fork");
      break;
  }
  n = 0;
}

static int ExecuteSubshell(char *subcmd) {
  int pid, ws;
  char *subargv[3];
  subargv[0] = (char *)prog;
  subargv[1] = "-c";
  subargv[2] = subcmd;
  switch ((pid = fork())) {
    case 0:
      _Exit(_mtsh(3, subargv, envs));
    case -1:
      perror("fork");
      return 127;
    default:
      if (waitpid(pid, &ws, 0) == -1) {
        perror("wait");
        return 1;
      }
      if (WIFEXITED(ws)) {
        return WEXITSTATUS(ws);
      } else {
        return 128 + WTERMSIG(ws);
      }
  }
}

static void CaptureCommand(char *subcmd, int in_quotes) {
  int pid, pfds[2];
  ssize_t n;
  char buf[512];
  char *subargv[3];

  if (pipe2(pfds, O_CLOEXEC) == -1) {
    perror("pipe");
    return;
  }

  subargv[0] = (char *)prog;
  subargv[1] = "-c";
  subargv[2] = subcmd;

  switch ((pid = fork())) {
    case 0:
      close(pfds[0]);
      dup2(pfds[1], 1);
      close(pfds[1]);
      // Reset global state inherited from parent
      assign = 0;
      _Exit(_mtsh(3, subargv, envs));
    case -1:
      perror("fork");
      close(pfds[0]);
      close(pfds[1]);
      return;
    default:
      close(pfds[1]);
      // Read all output first
      char *outbuf = q;
      while ((n = read(pfds[0], buf, sizeof(buf))) > 0) {
        for (ssize_t i = 0; i < n; ++i) {
          if (q + 1 < argbuf + sizeof(argbuf)) {
            *q++ = buf[i];
          }
        }
      }
      close(pfds[0]);

      // Handle newlines based on quoting context
      if (in_quotes) {
        // In quotes: only trim trailing newlines (preserve internal newlines)
        while (q > outbuf && (q[-1] == '\n' || q[-1] == '\r')) {
          q--;
        }
      } else {
        // Unquoted: convert all newlines to spaces for word splitting
        char *src = outbuf;
        char *dst = outbuf;
        while (src < q) {
          if (*src == '\n' || *src == '\r') {
            *dst++ = ' ';
          } else {
            *dst++ = *src;
          }
          src++;
        }
        q = dst;
        // Trim trailing spaces
        while (q > outbuf && (q[-1] == ' ' || q[-1] == '\t')) {
          q--;
        }
      }
      waitpid(pid, NULL, 0);
      break;
  }
}

static const char *IntToStr(int x) {
  static char ibuf[12];
  FormatInt32(ibuf, x);
  return ibuf;
}

static const char *GetVar(const char *key) {
  static char vbuf[PATH_MAX];
  if (key[0] == '$' && !key[1]) {
    return IntToStr(getpid());
  } else if (key[0] == '!' && !key[1]) {
    return IntToStr(lastchild);
  } else if (key[0] == '?' && !key[1]) {
    return IntToStr(exitstatus);
  } else if (!strcmp(key, "PWD")) {
    npassert(__getcwd(vbuf, sizeof(vbuf)) != -1);
    return vbuf;
  } else if (!strcmp(key, "UID")) {
    FormatInt32(vbuf, getuid());
    return vbuf;
  } else if (!strcmp(key, "GID")) {
    FormatInt32(vbuf, getgid());
    return vbuf;
  } else if (!strcmp(key, "EUID")) {
    FormatInt32(vbuf, geteuid());
    return vbuf;
  } else {
    return __getenv(envs, key).s;
  }
}

static bool IsVarName(int c) {
  return isalnum(c) || c == '_' ||
         (!vari && (c == '?' || c == '!' || c == '$'));
}

static bool CopyVar(void) {
  size_t j;
  const char *s;
  if (IsVarName(*p)) {
    npassert(vari + 1 < sizeof(var));
    var[vari++] = *p;
    var[vari] = 0;
    return false;
  }
  if ((s = GetVar(var))) {
    if ((j = strlen(s))) {
      npassert(q + j < argbuf + sizeof(argbuf));
      q = mempcpy(q, s, j);
    }
  }
  return true;
}
