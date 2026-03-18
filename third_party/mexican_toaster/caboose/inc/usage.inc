static void ShowUsage(const char *prog) {
  fprintf(stderr, "Usage: %s [command]\n\n", prog);
  fprintf(stderr, "Commands:\n");
  fprintf(stderr, "  check         Health check: verify ZIP and writable overlay\n");
  fprintf(stderr, "  overlay       Health check + prepare writable overlay (portable stub)\n");
  fprintf(stderr, "  toast         Get toasted! Enter interactive shell inside the app\n");
  fprintf(stderr, "  ls            List contents of embedded filesystem\n");
  fprintf(stderr, "  cat FILE      Read a file from embedded filesystem\n");
  fprintf(stderr, "\nLifecycle:\n");
  fprintf(stderr, "  warm          Prepare isolated environment (namespaces + overlay)\n");
  fprintf(stderr, "  thaw          Make /zip writable via overlayfs (from cold or warm)\n");
  fprintf(stderr, "  thaw toast    Thaw then enter interactive shell\n");
  fprintf(stderr, "  freeze        Pause writes, keep changes in memory\n");
  fprintf(stderr, "  persist [NAME] Bake overlay changes into a new .com binary\n");
  fprintf(stderr, "  discard       Throw away overlay changes\n");
  fprintf(stderr, "  status        Show current toaster state\n");
  fprintf(stderr, "  list          List persisted binaries\n");
  fprintf(stderr, "  help          Show this help message\n");
  fprintf(stderr, "\nWith no command, runs the app normally.\n");
}
