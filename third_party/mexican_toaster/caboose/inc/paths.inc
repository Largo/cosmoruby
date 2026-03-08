static int DeriveUpperPath(char upper[PATH_MAX]) {
  const char *env;
  const char *home;
  const char *xdg;

  env = getenv("TOASTER_UPPER");
  if (env && *env) {
    return snprintf(upper, PATH_MAX, "%s", env) < (int)PATH_MAX ? 0 : -1;
  }

  xdg = getenv("XDG_DATA_HOME");
  if (xdg && *xdg) {
    return snprintf(upper, PATH_MAX, "%s/toaster", xdg) < (int)PATH_MAX ? 0 : -1;
  }

  home = getenv("HOME");
  if (home && *home) {
    return snprintf(upper, PATH_MAX, "%s/.local/share/toaster", home) <
                   (int)PATH_MAX
               ? 0
               : -1;
  }

  return snprintf(upper, PATH_MAX, "/tmp/toaster") < (int)PATH_MAX ? 0 : -1;
}

static int DeriveLowerPath(char lower[PATH_MAX]) {
  const char *env = getenv("TOASTER_LOWER");
  if (!env || !*env) env = "/zip";
  return snprintf(lower, PATH_MAX, "%s", env) < (int)PATH_MAX ? 0 : -1;
}
