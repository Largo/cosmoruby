# Mexican Toaster Rails Dev Plan

This doc tracks the steps to turn Mexican Toaster into a self-contained, cross-platform Rails development environment that runs unprivileged.

## Goals
- Ship an APE binary with an embedded ZIP that provides a Rails-ready environment (mtsh shell, Ruby/Rails, app files).
- Unprivileged, cross-platform writable layer that persists across runs and power loss.
- mtsh has two modes: vanilla and toast (toaster-aware) with proper rc sourcing.
- Health check command (`check`) verifies embedded ZIP and writable strategy selection.

## Constraints
- No root/capabilities; must work on Linux/macOS/Windows without mounts.
- Prefer kernel/FUSE overlays when available, but fall back to userland overlay.
- Persistence: must survive abrupt power loss; avoid corruption.
- Keep within Cosmo conventions (single-file APE, embedded ZIP, tooling under `bin/`, `third_party/`).

## Workstream A: Writable Layer (Portable Baseline)
1) Implement userland overlay in mtsh/runtime: reads hit lower (`/zip`), writes go to upper (`$TOASTER_UPPER` defaulting to user data dir), delete tombstones, copy-up on first write.
2) Add manifest/journal + fsync policy for durability; startup recovery/validation.
3) Support per-project upper via env/flag; expose roots via env (`TOASTER_LOWER`, `TOASTER_UPPER`).
4) Integrate overlay into mtsh file ops (cd, glob, redirections) and into caboose toast mode.

## Workstream B: Adaptive Backends
1) Backend selection logic: try kernel overlay (Linux overlayfs) → FUSE union (if available) → userland overlay.
2) Detection and fallback on failure; log chosen backend in toast mode.
3) OS notes:
   - Linux: overlayfs when caps/userns allow; else fallback.
   - macOS: optional macFUSE union; else fallback.
   - Windows: WSL overlay if inside WSL; native falls back to userland.
   - BSDs: unionfs/nullfs if available + permitted; else fallback.

## Workstream C: mtsh UX & Modes
1) Mode plumbing: vanilla vs toast (flag/env/argv-based). Default vanilla.
2) Toast mode: banner, prompt tweak, PATH adjustments to overlay/bin, hard-require overlay init.
3) Rc sourcing order: `/etc/profile` → `/etc/mtsh.mtshrc` → `~/.mtshrc` in overlay view; quiet if missing.
4) Add health check: runs ZIP checks, initializes overlay backend, reports chosen strategy.

## Workstream D: Packaging & Rails
1) Ensure Ruby port uses mtsh (already true) and build scripts pack Rails app/assets into ZIP.
2) Add packaging script to embed Rails app and bootstrap scripts into ZIP.
3) Provide `bin` helpers to build/package toaster Rails env (similar to `build_caboose.sh`).
4) Smoke tests: `check` health command, basic Rails commands (`bundle exec rails new`, `rails s` stubs), file write/restore.

## Risks / Open Questions
- Performance of userland overlay on large Rails trees; may need caching/rsync-once.
- FUSE availability on macOS/Windows users.
- Windows path semantics in overlay layer.
- Journaling granularity vs simplicity; consider a simple append-only log with periodic compaction.
- Exec pitfall: execing host binaries (e.g., `/usr/bin/ls /zip`) loses the embedded `/zip` view; keep `/zip` traversal in-process.

## Next Steps
- Land overlay abstraction and health check wiring in caboose/mtsh.
- Add backend selection + userland overlay implementation.
- Wire rc sourcing and dual-mode prompts.
- Build and package a Rails sample to exercise the flow.

## Milestones
- M0: Define overlay API surface in mtsh + stub toast mode plumbing; add health check skeleton that reports "backend: unset".
- M1: Userland overlay works with journaling + fsync policy; toast mode defaults to userland overlay and validates persistence.
- M2: Backend detection and fallback matrix implemented; health check reports chosen backend with diagnostics; rc sourcing/prompt split finalized.
- M3: Packaging flow builds Rails ZIP, embeds app, and exposes helper scripts; smoke tests run on Linux/macOS/Windows (or WSL) for write/boot loops.
- M4: Hardening pass: recovery on crash, path edge cases (Windows), perf profiling on large trees; docs for operators/contributors.

## Backlog (ordered)
- Overlay API: formalize lower/upper/tombstone semantics; add helpers for copy-up, delete, list, and fsync batches.
- Journaling: append-only log with sequence numbers, compaction trigger, and replay on start; expose health check `--recover` mode.
- Backend chooser: detection probes per OS, with explicit reasons on fallback; environment override (e.g., `TOASTER_BACKEND=overlay|fuse|userland`).
- mtsh toast UX: `--toast` flag, banner/prompt hook, PATH overlays, rc sourcing order, and refusal to start without initialized overlay.
- Packaging: script to build Rails sample, vendor gems into ZIP, and update `bin/` entrypoints; add checksum manifest checked by health check.
- Tests: unit tests for overlay semantics, integration loop for "write → restart → read", and smoke scripts for Rails commands under toast mode.

## Testing Matrix (draft)
- Linux: overlayfs happy path; fallback to userland when unprivileged; run Rails smoke + crash-restart persistence.
- macOS: macFUSE union if present; otherwise userland overlay; verify PATH/rc sourcing and gem install writes.
- Windows: WSL overlay path; native userland overlay; focus on path normalization and newline handling.
- BSD: attempt unionfs/nullfs where available; otherwise userland overlay; sanity check journaling replay.

## Overlay API Sketch
- Types: `struct toast_layer { char *lower; char *upper; char *trash; };` plus callbacks for open/read/write/unlink/list.
- Ops: `toast_open(path, flags)`, `toast_unlink(path)`, `toast_readdir(dir, cb)`, `toast_copyup(path)`, `toast_fsync_batch(list)`.
- Tombstones: keep separate dir under upper (e.g., `.toast/tomb`); unlink checks tomb first, then lower.
- Copy-up: ensure parent dirs exist in upper; preserve mtime/mode; avoid re-copy if already present.
- Env: `TOASTER_LOWER` (default `/zip`), `TOASTER_UPPER` (default user data dir), `TOASTER_BACKEND` override, `TOASTER_FSYNC_POLICY` (e.g., `none`, `perfile`, `batch`).

## Journaling Plan
- Append-only log under upper (e.g., `.toast/journal`): records seq, op, path, mtime, size, checksum if useful.
- Recovery: replay log at startup, detect torn writes via seq gaps or fsync marker; compact when log > threshold.
- Fsync strategy: fsync journal entry, then data file on create/append; batch fsync option for perf; configurable via env.
- Health check `--recover` triggers replay/compaction and reports stats.

## Health Check Flow
- Parse env/flags, pick backend (and reason).
- Verify embedded ZIP manifest hashes.
- Initialize overlay backend; create upper/trash/journal dirs if missing.
- Run smoke: create temp file in overlay/bin/tmp, reopen, verify contents, delete, confirm tombstone respected.
- Report: backend, lower/upper paths, fsync policy, journal state, recovery result.

## Packaging Flow (draft)
- Script under `bin/`: builds Rails sample (or user-provided app), vendors gems, compiles assets.
- Produce ZIP layout: `/zip/bin` (mtsh, toast helpers), `/zip/app` (Rails), `/zip/usr` (Ruby/gems), manifest with checksums.
- Embed ZIP into APE via existing packaging path (like caboose); output `toaster` binary.
- Optional: generate `toast.env` snippet to set defaults for PATH, GEM_HOME, BUNDLE_PATH.

## Path Semantics Notes
- Normalize backslashes on Windows native; avoid `:` drive confusion; prefer forward-slash internally.
- Preserve case-insensitive lookup option for Windows/macOS if needed; consider a mode flag.
- Handle long paths by prepending `\\?\\` when invoking native APIs (if/when added).

## Current Caboose/Mtsh Snapshot
- `third_party/mexican_toaster/caboose.c`: commands `check`, `overlay` (portable skeleton), `toast`, `ls`, `cat`, `help`; `check` runs the full overlay health check (ZIP verification + upper prep/probe); `overlay` derives lower/upper paths, prepares upper layout (`.toast`/journal/tomb, bin, tmp), runs a write/read/fsync probe, and reports backend choice (still userland-only); `toast` copies `/zip/bin/mtsh` to `/tmp/.mtsh.<pid>` then execs, with fallbacks to `o//third_party/mexican_toaster/mtsh.com` or `mtsh` on `PATH`.
- `third_party/mexican_toaster/mtsh.c`: supports `MTSH_MODE`/`TOASTER_MODE` or argv-name heuristic to enter toast mode; toast mode only changes prompt (`toast$ `) and banner text; no overlay wiring or rc sourcing split yet.
- `third_party/mexican_toaster/package_caboose.sh`: builds sample ZIP with `/zip/bin/mtsh`, `/zip/app/hello.txt`, `/zip/README.txt`, `.cosmo` marker; uses `zipcopy` to embed ZIP into caboose binary.
- `bin/build_caboose.sh`: convenience wrapper to build `mtsh.com` + `caboose` then run the packaging script.

## Immediate Execution Plan (next two iterations)
- **Userland overlay baseline (PR1)**: add a dedicated overlay module (new `third_party/mexican_toaster/overlay.{c,h}`) with lower/upper/tomb semantics, copy-up, delete/tombstone, and transparent open/read/write via shims used by mtsh; wire `Overlay()` to initialize it and return handles usable by toast mode; keep backend selection fixed to userland for now but honor `TOASTER_BACKEND=userland|portable`.
- **Toast mode gating (PR1)**: require overlay init before entering toast; set `TOASTER_LOWER/UPPER/BACKEND` envs, prepend overlay/bin to PATH, and invoke rc sourcing order from the overlay view; add errors when overlay prep fails.
- **Health check lift (PR1)**: extend `check` to run overlay smoke (create→read→fsync→tombstone), emit backend + fsync policy, and report recovery status placeholder; keep manifest verification stubbed but structured.
- **Backend chooser + detection hooks (PR2)**: add detection stubs per OS (overlayfs/macFUSE/WSL/unionfs) that log reasons for fallback; allow `TOASTER_BACKEND=kernel|fuse|userland|auto`; keep actual mount calls TODO-gated.
- **Rails packaging scaffolding (PR2)**: add helper scripts under `bin/` to build a sample Rails app, vendor gems/assets into `/zip`, generate manifest, and reuse `package_caboose.sh` flow; document expected layout for future Rails app injection.
- **Testing entry points**: add minimal unit tests for overlay semantics (copy-up, tombstone, fsync batches) and an integration smoke that exercises toast mode with write→restart→read, runnable via `make o//third_party/mexican_toaster/...` once mkdeps/toolchain is available.

## TODO (done vs remaining)
- [x] Caboose CLI skeleton (`check`, `overlay` stub, `toast`, `ls`, `cat`, `help`) and zipcopy-based packaging script.
- [x] mtsh toast mode flag/heuristic + prompt tweak; basic interactive loop intact.
- [ ] Implement overlay abstraction (userland baseline) and replace `overlay` stub with real passthrough/journal hooks.
- [ ] Add backend detection/fallback logging and `TOASTER_BACKEND` override support in caboose + mtsh.
- [ ] Wire toast mode to require overlay init, set PATH to overlay/bin, and add rc sourcing order.
- [ ] Extend `check` health command to validate ZIP manifest, run overlay smoke, and report fsync/journal status (beyond current write probe).
- [ ] Replace sample ZIP packaging with Rails packaging flow (vendor gems/assets, helper scripts, manifest).
- [ ] Add tests: overlay unit tests, toast loop persistence smoke, Rails command stubs across OS matrix.
