// Entry points and command execution wiring
static enum MtshMode ParseMode(const char *s) {
  if (!s) return kMtshModeVanilla;
  if (!strcasecmp(s, "toast")) return kMtshModeToast;
  return kMtshModeVanilla;
}

static void InitMtshConfig(int argc, char **argv) {
  const char *env;
  g_mtsh_config.mode = kMtshModeVanilla;

  env = getenv("MTSH_MODE");
  if (!env || !*env) {
    env = getenv("TOASTER_MODE");
  }

  if ((g_mtsh_config.mode = ParseMode(env)) == kMtshModeVanilla && argc > 0) {
    // Heuristic: if invoked as mtsh-toast or caboose toast child, treat as toast.
    const char *p = strrchr(argv[0], '/');
    p = p ? p + 1 : argv[0];
    if (p && strstr(p, "toast")) {
      g_mtsh_config.mode = kMtshModeToast;
    }
  }
}

static const char *GetRedirectArg(const char *prog, const char *arg, int n) {
  if (arg[n]) {
    return arg + n;
  } else if ((arg = Tokenize())) {
    return arg;
  } else {
    tinyprint(2, prog, ": error: redirect missing path\n", NULL);
    _Exit(14);
  }
}

int _mtsh(int argc, char **argv, char **envp) {
  size_t i;
  char *arg;
  size_t globCount = 0;
  int globFlags = 0;
  glob_t globTheBuilder;
  prog = argc > 0 ? argv[0] : "mtsh";

  for (i = 1; i < 32; ++i) {
    unsupported[i] = true;
  }
  unsupported['\t'] = false;
  unsupported['\n'] = false;
  unsupported[0177] = true;
  unsupported['~'] = true;
  unsupported['{'] = true;
  // Perl t/op/exec.t depends on unpaired } being
  // passed from the shell to Perl
  unsupported['}'] = false;

  if (argc >= 3 && !strcmp(argv[1], "--")) {
    for (i = 2; i < argc; ++i) {
      args[n++] = argv[i];
    }
    _Exit(ShellExec());
  }

  if (argc != 3) {
    tinyprint(2, prog, ": error: wrong number of args\n", NULL);
    _Exit(10);
  }

  if (strcmp(argv[1], "-c")) {
    tinyprint(2, prog, ": error: argv[1] should -c\n", NULL);
    _Exit(11);
  }

  p = cmd = argv[2];
  if (strlen(cmd) >= ARG_MAX) {
    tinyprint(2, prog, ": error: cmd too long: ", cmd, "\n", NULL);
    _Exit(12);
  }

  // copy environment variables (must strdup so PutEnv can free them later)
  int envi = 0;
  if (envp) {
    for (; envp[envi]; ++envi) {
      npassert(envi + 1 < ARRAYLEN(envs));
      envs[envi] = strdup(envp[envi]);
      if (!envs[envi]) {
        tinyprint(2, prog, ": strdup failed for env\n", NULL);
        _Exit(1);
      }
    }
  }
  envs[envi] = 0;

  // get command line arguments
  n = 0;
  r = q = argbuf;
  while ((arg = Tokenize())) {
    if (arg == TOMBSTONE)
      continue;
    if (n + 1 < ARRAYLEN(args)) {
      if (isdigit(arg[0]) && arg[1] == '>' && arg[2] == '&' &&
          isdigit(arg[3])) {
        AddDupRedirect(arg[0] - '0', arg[3] - '0');
      } else if (arg[0] == '>' && arg[1] == '&' && isdigit(arg[2])) {
        AddDupRedirect(1, arg[2] - '0');
      } else if (isdigit(arg[0]) && arg[1] == '>' && arg[2] == '>') {
        AddFileRedirect(arg[0] - '0', O_WRONLY | O_CREAT | O_APPEND,
                        GetRedirectArg(prog, arg, 3));
      } else if (arg[0] == '>' && arg[1] == '>') {
        AddFileRedirect(1, O_WRONLY | O_CREAT | O_APPEND,
                        GetRedirectArg(prog, arg, 2));
      } else if (isdigit(arg[0]) && arg[1] == '>') {
        AddFileRedirect(arg[0] - '0', O_WRONLY | O_CREAT | O_TRUNC,
                        GetRedirectArg(prog, arg, 2));
      } else if (arg[0] == '>') {
        AddFileRedirect(1, O_WRONLY | O_CREAT | O_TRUNC,
                        GetRedirectArg(prog, arg, 1));
      } else if (arg[0] == '<') {
        AddFileRedirect(0, O_RDONLY, GetRedirectArg(prog, arg, 1));
      } else {
        int globrc = GLOB_NOMATCH;
        globrc = glob(arg, globFlags, NULL, &globTheBuilder);
        if (globrc == 0) {
          for (; globCount < globTheBuilder.gl_pathc; globCount++) {
            if (n + 1 >= ARRAYLEN(args)) {
              tinyprint(2, prog, ": error: too many args after glob expansion\n", NULL);
              _Exit(13);
            }
            args[n++] = globTheBuilder.gl_pathv[globCount];
          }
        } else if (globrc != GLOB_NOMATCH) {
          tinyprint(2, prog, ": error: with glob\n", NULL);
          _Exit(16);
        }
        globFlags |= GLOB_APPEND;
        if (globrc == GLOB_NOMATCH) {
          args[n++] = arg;
        }
        args[n] = 0;
      }
    } else {
      tinyprint(2, prog, ": error: too many args\n", NULL);
      _Exit(13);
    }
  }

  // In interactive mode, use ShellSpawn() so external commands don't replace the shell
  // In script mode, use ShellExec() for compatibility with shell scripts that use 'exec'
  if (argc >= 2 && !strcmp(argv[1], "-c")) {
    // Interactive mode (invoked as: mtsh -c "command")
    return ShellSpawn();
  } else {
    return ShellExec();
  }
}

static int InteractiveShell(char **envp) {
  char *line;
  char *interactive_argv[3];
  int rc = 0;
  const char *prompt = g_mtsh_config.mode == kMtshModeToast ? "toast$ " : "mtsh$ ";
  const char *history_name = g_mtsh_config.mode == kMtshModeToast ? "mtsh-toast" : "mtsh";

  interactive_argv[0] = (char *)prog;
  interactive_argv[1] = "-c";

  // Print welcome message and version if on a tty
  if (isatty(0)) {
    tinyprint(1, "mtsh interactive shell v", MTSH_VERSION_STRING, "\n", NULL);
    tinyprint(1, "Type 'help' for commands, 'exit' or ^D to quit\n", NULL);
  }

  // Use linenoise for professional line editing if on a tty
  // Otherwise fall back to simple line reading (for pipes/redirection)
  if (isatty(0)) {
    // linenoise interactive mode
    while ((line = linenoiseWithHistory(prompt, history_name))) {
      // Skip empty lines
      if (!*line) {
        free(line);
        continue;
      }

      // Execute the line
      interactive_argv[2] = line;
      rc = _mtsh(3, interactive_argv, envp);
      free(line);
    }
    // ^D pressed, clean exit
    if (isatty(0)) {
      Write(1, "\n");
    }
    return rc;
  } else {
    // Non-tty mode: simple line reading for pipes/redirects
    char linebuf[ARG_MAX];
    while (1) {
      ssize_t i = 0;
      char c;
      while (i < sizeof(linebuf) - 1) {
        ssize_t n = read(0, &c, 1);
        if (n == 0) {
          // EOF
          if (i == 0) {
            return rc;
          }
          break;
        }
        if (n < 0) {
          perror("read");
          return 1;
        }
        if (c == '\n') {
          break;
        }
        linebuf[i++] = c;
      }
      linebuf[i] = 0;

      // Skip empty lines
      if (i == 0) {
        continue;
      }

      // Execute the line
      interactive_argv[2] = linebuf;
      rc = _mtsh(3, interactive_argv, envp);
    }
  }
}

static int RunRcFile(const char *path, char **envp) {
  FILE *f;
  char line[ARG_MAX];
  int rc = 0;
  if (!(f = fopen(path, "r"))) {
    return 0;
  }
  while (fgets(line, sizeof(line), f)) {
    size_t len = strlen(line);
    while (len && (line[len - 1] == '\n' || line[len - 1] == '\r')) {
      line[--len] = 0;
    }
    if (!len) continue;
    char *argv_rc[3];
    argv_rc[0] = (char *)prog;
    argv_rc[1] = "-c";
    argv_rc[2] = line;
    rc = _mtsh(3, argv_rc, envp);
    if (rc) break;
  }
  fclose(f);
  return rc;
}

int main(int argc, char **argv, char **envp) {
  prog = argc > 0 ? argv[0] : "mtsh";
  InitMtshConfig(argc, argv);
  if (g_mtsh_config.mode == kMtshModeToast) {
    RunRcFile("/zip/etc/profile", environ);
    RunRcFile("/zip/etc/mtsh.mtshrc", environ);
  }
  // If no arguments, run interactive shell
  if (argc == 1) {
    return InteractiveShell(environ);
  }

  return _mtsh(argc, argv, environ);
}
