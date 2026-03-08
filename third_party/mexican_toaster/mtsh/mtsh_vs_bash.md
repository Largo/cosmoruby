# mtsh usability gaps vs. bash

Bash offers mature CLI ergonomics that could make `mtsh` easier to use and debug.
The table maps notable bash capabilities to what `mtsh` currently provides and where a similar feature would help.

| Bash capability | Bash behavior | mtsh today | Opportunity |
| --- | --- | --- | --- |
| `help`, `--help` topics | Built-in help with per-command<br>summaries and examples. | Only short `-h` usage text;<br>no long options or topic help. | Add `--help`/`--long-help` with<br>examples and flag details. |
| `--version` | Prints a precise<br>version string. | No dedicated flag; version only<br>appears when usage is shown. | Provide `--version` so tooling can<br>detect mtsh without triggering errors. |
| `bash -n` (syntax check) | Parses without executing to<br>surface issues early. | `-n` immediately exits;<br>no check-only mode. | Add `--check`/`--dry-run` to parse inputs<br>and report unresolved includes. |
| `set -x` / `set -v` tracing | Emits commands as they run<br>for debugging. | Silent include resolution<br>except for warnings. | Add `--trace`/`--verbose` to log search paths,<br>shim decisions, and includer. |
| `set -e` / `pipefail` strictness | Fails fast on errors. | Continues after missing headers<br>(prints warning, still exits 0). | Add `--strict`/`--werror` to make unresolved<br>headers fatal. |
| Startup files (`~/.bashrc`, `BASH_ENV`) | Persist user defaults<br>between invocations. | All options must be passed on<br>every call; no rc/env support. | Allow `MTDEPSRC`/`MTDEPS_OPTS` or a config file to set<br>defaults (`-S`, `-P`, hermetic mode, etc.). |
