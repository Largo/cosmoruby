enum OverlayBackend {
  kOverlayAuto,
  kOverlayKernel,
  kOverlayFuse,
  kOverlayUserland,
};

static const char *OverlayBackendName(enum OverlayBackend b) {
  switch (b) {
    case kOverlayKernel:
      return "kernel overlay (best effort)";
    case kOverlayFuse:
      return "FUSE overlay (best effort)";
    case kOverlayUserland:
      return "userland overlay (portable fallback)";
    case kOverlayAuto:
    default:
      return "auto (select best available)";
  }
}

static enum OverlayBackend ParseOverlayBackend(const char *s) {
  if (!s || !*s) return kOverlayAuto;
  if (!strcasecmp(s, "kernel") || !strcasecmp(s, "overlayfs")) return kOverlayKernel;
  if (!strcasecmp(s, "fuse")) return kOverlayFuse;
  if (!strcasecmp(s, "userland") || !strcasecmp(s, "portable")) return kOverlayUserland;
  return kOverlayAuto;
}

static void DescribeOverlayChoice(enum OverlayBackend chosen,
                                  const char *upper) {
  printf("🧈 Overlay backend: %s\n", OverlayBackendName(chosen));
  printf("📂 Upper (writable) path: %s\n", upper);
  if (chosen != kOverlayUserland) {
    printf("⚠️  Selected backend not yet implemented; falling back to portable overlay.\n");
  }
}
