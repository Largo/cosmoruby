static int Overlay(void) {
  char upper[PATH_MAX];
  char lower[PATH_MAX];
  enum OverlayBackend requested, chosen;
  int rc = CheckZip(true, true);
  if (rc != EX_OK) {
    return rc;
  }

  requested = ParseOverlayBackend(getenv("TOASTER_BACKEND"));
  chosen = requested == kOverlayAuto ? kOverlayUserland : requested;
  if (DeriveUpperPath(upper) == -1) {
    fprintf(stderr, "Failed to derive upper path for overlay\n");
    return EX_SOFTWARE;
  }
  if (DeriveLowerPath(lower) == -1) {
    fprintf(stderr, "Failed to derive lower path for overlay\n");
    return EX_SOFTWARE;
  }

  if (requested == kOverlayAuto) {
    printf("TOASTER_BACKEND not set; defaulting to portable overlay.\n");
  }

  ReportOverlayCapabilities();

  DescribeOverlayChoice(chosen, upper);
  printf("📂 Lower (read-only) path: %s\n", lower);

  if (EnsureUpperLayout(upper) == -1) {
    fprintf(stderr, "Failed to prepare upper layout at %s\n", upper);
    return EX_CANTCREAT;
  }

  if (ProbeUpperWrite(upper) == -1) {
    fprintf(stderr, "Upper path is not writable or fsync failed: %s\n", upper);
    return EX_IOERR;
  }

  printf("✅ Writable layer prepared and probed.\n");
  printf("⚠️  Overlay mount/userland passthrough not wired yet; persistence is direct in upper.\n");
  return EX_OK;
}
