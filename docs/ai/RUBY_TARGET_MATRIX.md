# Cosmopolitan Ruby Target Matrix

This note documents which Ruby binaries we build in the Cosmopolitan
tree, the expectations for each flavour, and which pieces of the
toolchain wire those behaviours together. It is meant to save future
contributors from rediscovering why some targets look “nonstandard” at
first glance.

## Target Catalogue

| Binary path                             | Nickname        | Purpose                                                                 | Load path root        | Packaging |
|----------------------------------------|-----------------|-------------------------------------------------------------------------|-----------------------|-----------|
| `o//third_party/ruby/ruby`             | hermetic ruby   | End-user runtime with stdlib zipped inside the ELF/PE/Mach-O container  | `/zip/lib/ruby/3.4.0` | `zipcopy` |
| `o//third_party/ruby/ruby.zipless`     | dev ruby        | Developer runtime that reads the stdlib directly from the checkout tree | repo `third_party/...`| none      |
| `o//third_party/ruby/irb`              | hermetic irb    | Interactive shell bundled with the hermetic stdlib                      | `/zip/...`            | `zipcopy` |
| `o//third_party/ruby/irb.zipless`      | dev irb         | IRB that follows the repo filesystem                                    | repo                  | none      |
| `o//third_party/ruby/miniruby`         | hermetic stub   | Small interpreter used for build tooling                                | `/zip/...`            | `zipcopy` |
| `o//third_party/ruby/miniruby.zipless` | dev stub        | Small interpreter aimed at tests and generators                         | repo                  | none      |

All six binaries are built from the same sources but link different
flavours of `loadpath.o` and receive different compile-time macros so
their `$LOAD_PATH` defaults make sense out of the box.

## Load Path Strategy

1. **Hermetic targets (`*.com` and non-zipless variants)**
* `third_party/ruby/loadpath.c` runs with
  `-DRUBY_COSMO_LOADPATH_PREFIX="/zip"` plus a pair of fallback entries
  pointing at the repository (`RUBY_COSMO_DEV_LIB`,
  `RUBY_COSMO_DEV_MONITOR`). MRI’s built-in
  `ruby_initial_load_paths[]` table therefore lists the ZIP directories
  first and the checkout paths second.
   * Because we leave `loadpath.c` intact, `gem_prelude.rb` can require
     `rubygems`, `tmpdir`, and the other default gems *before* any
     Cosmopolitan-specific glue runs. The old `NO_INITIAL_LOAD_PATH`
     workaround is no longer necessary.
   * Packaging (`third_party/ruby/package_ruby.sh`) builds the stdlib
     ZIP using the filesystem copies and injects it into the binaries
     via `zipcopy`, matching the load-path table.

2. **Zipless (developer) targets**
* The fallback entries described above ensure `gem_prelude.rb` sees the
  checkout dirs during `ruby_init()`, so the default gems load without
  warning even before the Cosmopolitan helper runs.
* `third_party/ruby/ruby_cosmo_main.h` still injects `-I` arguments to
  keep the repository paths at the head of `$LOAD_PATH` once option
  parsing finishes.
   * These binaries intentionally skip ZIP embedding so tools can edit
     sources and re-run Ruby without repackaging.

3. **Post-initialisation helper**
   * For both flavours we keep `rb_cosmo_configure_load_path()` to
     normalise `$LOAD_PATH` after `ruby_options()` runs. It honours the
     seeded `RUBYLIB` entries, keeps hermetic binaries sealed, and lets
     developers append extra directories in environnement variables if
     they wish.

## Building & Testing

* `make -j1 o//third_party/ruby/ruby` builds the hermetic interpreter,
  including the generated ZIP.
* `make -j1 o//third_party/ruby/ruby.zipless` produces the dev variant.
* `bin/build_ruby.sh` runs all four major targets (`ruby`, `ruby.zipless`,
  `irb`, `irb.zipless`, plus both miniruby variants) and then repackages
  the hermetic executables.
* For quick verification, run:

  ```sh
  o//third_party/ruby/ruby -e 'require "tmpdir"; require "rubygems"'
  o//third_party/ruby/ruby.zipless -e 'require "tmpdir"; require "rubygems"'
  ```

  Neither command should emit the “`RubyGems' were not loaded`”
  warnings anymore.

## Why the Complication?

* **Hermetic binaries** must stay self-contained and runnable on any
  host, so the embedded ZIP (`/zip/...`) is the only acceptable load
  root. Relying on the configure-time prefix (`/tmp/ruby-cosmo-config`)
  or the developer checkout would break portability.
* **Developer binaries** need to cooperate with the workspace (rbconfig,
  extension compilation, tests that inspect `LOAD_PATH`, etc.), so they
  point at `third_party/ruby/**` instead. Synthesising a fake prefix
  would confuse build tooling and extension authors.
* By knitting the two behaviours together in the build system we keep
  MRI’s assumptions intact, avoid hand-rolled bootstrapping code, and
  eliminate the noisy warnings that led to this investigation.

Feel free to update this document when new targets are added or the
load-path strategy evolves. The goal is to avoid repeating the “why do
we have `NO_INITIAL_LOAD_PATH`?” debugging session ever again.
