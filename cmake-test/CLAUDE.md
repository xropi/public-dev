# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

cmake-test: a comparison harness for one narrow CMake problem — **staging a
per-configuration data file (an ini) so the binary you just built finds the
matching one**, in a multi-config generator where Debug and Release coexist in
one build tree.

Nothing depends on this folder. It exists to be read and re-run. Four working
solutions sit side by side, one per folder, so the trade-offs can be compared by
building them rather than by argument.

`design.md` is the decision record (Decided D*/Open O*) and is the first thing
to read — it holds *why* each variant exists and what was actually measured
versus merely predicted. No `bugs.md` or `backlog.md` yet; create them (B*, BL*)
on the first recorded defect or deferred feature.

## The four solutions

| Folder | Mechanism | Destination | Cross-config safe? |
|---|---|---|---|
| `output-rule` | `add_custom_command(OUTPUT)` | shared `build/x.ini` | **Ninja only** (D4) |
| `always-run` | `add_custom_target(ALL)` | shared `build/x.ini` | yes — confirmed on VS 2022 (D5) |
| `per-config` | `OUTPUT` rule | `build/$<CONFIG>/x.ini` | yes, structurally (D6) |
| `stagekit` | one target per build tree, generated per-config script | either | yes, and scales (D7–D10) |

`output-rule` is the baseline that started it all, not a recommendation — it
works by relying on a Ninja implementation detail. `stagekit` is the only
multi-project example; the other three are single-app. It is also the only one
that stages **directories** as well as single files (D13) — `proj-b` does both,
and its `app-b` prints a nested file from the staged directory precisely to
prove the descent happened.

## Running and testing

Every folder has the same three scripts. There is no test suite — the harness
*is* the test, and it is run by hand:

```sh
cd always-run          # or any other
./build-debug.sh       # configures into build/ on first run
./build-release.sh
./build-debug.sh       # the interesting one: does it re-stage?
./build/Debug/app      # should print flavor = debug
```

The scripts wrap `build.sh <Config>`, which configures once with
`-G "Ninja Multi-Config"` and then builds the requested config.

Binary locations differ: `output-rule` and `always-run` put it at
`build/<Config>/app`, `per-config` likewise but with the ini beside it, and
`stagekit` uses `build/proj-<x>/<Config>/app-<x>` because subproject binaries
land under their own directory.

**The scenario that matters** is Debug → Release → Debug. Everything else is
setup. A variant passes if the third build re-stages and the debug binary reads
the debug ini.

`stagekit` additionally supports being configured from a subproject —

```sh
cd stagekit/proj-a
cmake -G "Ninja Multi-Config" -B build -S .
cmake --build build --config Debug
./build/Debug/app-a          # stages into proj-a/build/x.ini
```

— which is the mode that matches how this monorepo's C++ projects are normally
built (D11). Pass the generator explicitly: without it you get a single-config
tree, where `--config` is ignored and the binary lands at `build/app-a`.

## Non-obvious constraints

- **`ALL` does not mean "always runs".** It puts a target in the *default*
  build only. `cmake --build . --target app-a` skips it, as does Visual
  Studio's "Only build startup projects and dependencies on Run" — i.e. plain
  F5. The `add_dependencies` edge is what makes staging happen, which is why
  `stage_file()` takes the consuming target and issues it (D10).
- **`add_subdirectory` is not a dependency.** It is configure-time file
  inclusion and creates no build edge. Target names are global across the tree,
  which is why a duplicate `add_custom_target` name is a hard error.
- **`add_custom_command(TARGET ...)` is directory-scoped** — it can only append
  to a target created in the same directory. Subprojects cannot append to a
  top-level target.
- **A plain variable cannot collect across `add_subdirectory`.** The append is
  visible in the child and silently lost in the parent — no warning, just a
  missing copy. Use a global property (D7).
- **`file(GENERATE)` cannot choose per-config content for one output** (it runs
  for all configs at once and CMake rejects the conflict), but it is exactly the
  right tool for writing a per-config *script* (D3, D8).
- **Running an executable stages nothing.** Only a build does. So with a shared
  destination, switching the config in an IDE and hitting run does not restage
  unless the IDE builds first.
- **`file(COPY)` skips by timestamp, not content** — and per-config source trees
  come out of a git checkout with identical mtimes, so it silently keeps the
  previous config's files. That is why `stagekit` stages directories with
  `-E copy_directory_if_different`, which compares content (D13/D14). It does not
  delete orphans, though, so a file removed from a source tree survives in
  `build/` until it is wiped.
- Minimum CMake differs by folder: **3.26** for `stagekit`
  (`-E copy_directory_if_different`, D14; `file(COPY_FILE)` needs 3.21 and
  `cmake_language(DEFER)` only 3.19), **3.20** for the other three (`per-config`
  needs it for `$<CONFIG>` in a custom command `OUTPUT`).

## Verification status

Everything recorded was measured on Ninja Multi-Config, CMake 4.2.3, Linux —
**except** that `always-run` is confirmed working under Visual Studio 2022, and
the predicted MSBuild failure of `output-rule` has *not* been reproduced (O1).
Do not upgrade that prediction to a fact without running it; `always-run`
working under VS proves nothing about it either way.
