# cmake-test design

cmake-test is a comparison harness for one narrow CMake problem: **staging a
per-configuration data file (an ini) so that the binary of the configuration you
just built finds the matching one**. It is not a library and nothing depends on
it — it exists to be read and re-run. Four working solutions sit side by side,
one per folder, so the trade-offs can be compared by building them rather than
by argument. There is no `-orig`. Cross-project references use `<project>-D<n>`:
`dev-D4` means decision D4 in the monorepo's `../../design.md`.

Everything recorded here was measured on **Ninja Multi-Config, CMake 4.2.3,
Linux**, except where an entry says otherwise. The Visual Studio side is the
main gap and is tracked in Open.

Defects go in `bugs.md` (B*, not created yet), deferred features in `backlog.md`
(BL*, not created yet).

---

## Decided

### D1. What the problem is

**Decision:** the harness targets exactly one scenario — a data file that must
differ per build configuration, consumed by the app at *runtime*, in a
**multi-config generator** (Ninja Multi-Config, Visual Studio) where one build
tree holds Debug and Release simultaneously.

**Rationale:** single-config generators (plain Ninja, Makefiles) do not have the
problem at all: the config is fixed at configure time, so `configure_file` or a
plain `if(CMAKE_BUILD_TYPE STREQUAL Debug)` settles it. Everything interesting
here follows from the destination being shared by configs that coexist.

### D2. Per-config source selection is a generator expression

**Decision:** choose the source with
`$<IF:$<CONFIG:Debug>,<debug src>,<release src>>`, and let the else-branch cover
everything that is not Debug.

**Rationale:** `$<CONFIG:Debug>` is evaluated per config at generate time, never
at configure time, which is the only way one build tree can hold both answers.
The else-branch (rather than a chain testing Release explicitly) is what makes
`RelWithDebInfo` and `MinSizeRel` land on the release ini instead of silently
getting nothing.

### D3. Staging is a build step, never a configure step

**Decision:** the copy is performed by a build rule, not by `configure_file` or
`file(GENERATE)`.

**Rationale:** the destination path contains no `$<CONFIG>` in the shared-
destination designs, so only one config may write it, and only a *build* step
knows which config is being built. `file(GENERATE)` runs for all configs at once
and CMake rejects the two branches as conflicting commands for one output.
`file(GENERATE)` is still the right tool for generating a per-config *script*
(D8) — the distinction is generating content versus choosing which content wins.

### D4. `output-rule/` — the baseline, and why it is generator-specific

**Decision:** keep the original approach as a folder of its own: an
`add_custom_command(OUTPUT ...)` copying into a shared `${CMAKE_BINARY_DIR}/x.ini`,
with the output listed in the consuming target's sources.

**Rationale:** it is the obvious first solution and it does work — on Ninja. It
re-stages after a config switch because Ninja Multi-Config keeps a *single
shared* `.ninja_log`, keyed by output path, that records the command line; the
two configs emit the same output with different commands, so switching config is
a command change and the edge is dirty regardless of timestamps. Measured
directly: with `x.ini` newer than both sources, building the other config still
re-ran the copy, so the behaviour is not timestamp-driven.

That mechanism is a Ninja implementation detail. MSBuild tracks custom build
steps with per-configuration `.tlog` files compared by timestamp, and each
config's log only ever sees its own command, so Debug → Release → Debug is
predicted to skip the copy and leave the release ini under the debug binary.
See O1 — this specific failure has not been reproduced.

`OUTPUT` was chosen over `POST_BUILD` deliberately: it makes the ini a real
dependency, so editing the ini re-copies on the next build, whereas `POST_BUILD`
only fires when the executable itself relinks.

### D5. `always-run/` — a custom target has no up-to-date check

**Decision:** replace the `OUTPUT` rule with `add_custom_target(stage_ini ALL ...)`
plus `add_dependencies`, keeping the same shared destination.

**Rationale:** a custom *target* runs its commands on every build in every
generator — documented behaviour, not an inference about tracking internals — so
the question of whose up-to-date logic is in play disappears. `copy_if_different`
keeps the unconditional run cheap and preserves the edit-re-stages property.
Cost is one `cmake -E` process per file per build.

**Confirmed working under Visual Studio 2022.** This is the only variant with
non-Ninja confirmation.

### D6. `per-config/` — put `$<CONFIG>` in the destination

**Decision:** stage to `${CMAKE_BINARY_DIR}/$<CONFIG>/x.ini`, next to the
executable, and set `CMAKE_RUNTIME_OUTPUT_DIRECTORY` explicitly so the two
cannot drift apart.

**Rationale:** no two configs share a destination, so cross-config staleness
stops being a scheduling problem a generator must get right and becomes
structurally impossible. It also fixes a defect the shared-destination designs
all keep: with one `x.ini`, running the *release* binary after a debug build
feeds it the debug ini, because running an executable stages nothing. Here Debug
and Release stay independently runnable with no rebuild between them (measured).
An `OUTPUT` rule is safe again, since each config owns its own output path.

**Cost:** the path can no longer be a configure-time `INI_PATH` define, because
a compile definition cannot carry `$<CONFIG>`. The app resolves the file next to
`argv[0]` at runtime instead.

### D7. `stagekit/` — one staging target per build tree

**Decision:** for a multi-project tree, collect `(source, destination)` pairs
from anywhere in the tree into a **global property**, and materialise a single
`stage_files` target.

**Rationale:** the per-project approach of D5 does not scale — a copy target
beside every subproject, and process count growing with file count. Collection
has to survive directory boundaries, and the two obvious mechanisms do not:

- a plain variable cannot escape `add_subdirectory` — the append is visible
  inside the subdirectory and silently lost in the parent (measured; the missing
  copy produces no warning);
- `add_custom_command(TARGET ...)` errors with *"TARGET 'x' was not created in
  this directory"*, so subprojects cannot append to a top-level target.

A global property has no scope and resets per configure run, so a re-configure
does not accumulate duplicates (measured).

### D8. The copies go into a generated per-config script

**Decision:** `stage_finalize` writes `stage-$<CONFIG>.cmake` via
`file(GENERATE)`; the target's single fixed command is `cmake -P` on it.

**Rationale:** splicing one `COMMAND` per file into the target would spawn one
process per file on every build, unconditionally, since the target never skips.
One generated script means **one process per build regardless of file count**,
with `file(COPY_FILE ... ONLY_IF_DIFFERENT)` doing the comparison in-process.
`file(GENERATE)` evaluating generator expressions per config is exactly its
strength — see the distinction drawn in D3.

### D9. `stagekit/` is self-finalizing — no init/finalize ceremony

**Decision:** no `stage_init()` / `stage_finalize()` calls in any
`CMakeLists.txt`. The target is created lazily on the first `stage_file()` call,
and finalize is registered from inside the module with
`cmake_language(DEFER DIRECTORY "${CMAKE_SOURCE_DIR}" CALL stage_finalize)`.

**Rationale:** the explicit form required `stage_init()` *before* the
`add_subdirectory` list and `stage_finalize()` *after* it, which put a silent
failure mode in the top-level file: an `add_subdirectory` added below the
finalize call drops that subtree's `stage_file()` calls with no error — the same
class of bug as the variable-scope trap in D7. Deferring removes the ordering
rule rather than documenting it; CMake runs the deferred call after the
top-level directory is fully processed, which is after any line anyone could
write (measured).

Deferring onto `CMAKE_SOURCE_DIR` rather than the current directory matters
twice: registration happens from whichever subproject calls `stage_file()`
first, and `CMAKE_SOURCE_DIR` is always the root of *whatever configure is
running* — so the same code is correct for an umbrella build and a standalone
subproject build, with no `PROJECT_IS_TOP_LEVEL` guard anywhere.

### D10. `stage_file()` takes the consuming target

**Decision:** the signature is `stage_file(<target> <src> <dst>)`, and the
function issues the `add_dependencies` itself.

**Rationale:** the dependency edge is not optional and is easy to forget. `ALL`
only puts `stage_files` in the *default* build; `cmake --build . --target app-a`
skips it entirely, leaving the app to run against a stale or missing file
(measured: `ninja: no work to do`, then the app exits 1). This is not an exotic
case — it is Visual Studio's *"Only build startup projects and dependencies on
Run"*, i.e. ordinary F5. Folding it into `stage_file()` makes the edge
unforgettable. It also orders staging before the link, which matters as soon as
anything consumes a staged file at build time.

### D11. Subprojects are dual-mode

**Decision:** each subproject carries its own `cmake_minimum_required` and
`project()`, and includes the module by relative path
(`${CMAKE_CURRENT_LIST_DIR}/../cmake/stagekit.cmake`) rather than through
`CMAKE_MODULE_PATH`.

**Rationale:** in this monorepo every C++ project is its own top level and pulls
siblings in via `add_subdirectory(../base ...)`, so "configured on its own" is
the normal mode, not an edge case. A standalone configure has no parent to set
`CMAKE_MODULE_PATH`, and without `project()` CMake warns and pretends. Both
modes now work and are exercised. With `${CMAKE_BINARY_DIR}` as the destination
root, standalone builds stage into `proj-a/build/` and umbrella builds into the
shared root — correct in both cases for free.

### D12. Layout: one solution per folder, root is directories only

**Decision:** `cmake-test/` contains nothing but solution folders, each
self-contained with its own `CMakeLists.txt` and `build.sh` /
`build-debug.sh` / `build-release.sh`. Folders are named after their mechanism
(`output-rule`, `always-run`, `per-config`, `stagekit`), not by ordinal.

**Rationale:** the original solution lived at the root while the alternatives
were subfolders, which read as "the real one plus some variants" and left the
root a mix of files and folders. They are peers. Mechanism names keep the
comparison legible from `ls` alone and do not imply a ranking or an order.

---

## Open

### O1. `output-rule/` on Visual Studio 2022 is predicted, not measured

The MSBuild failure described in D4 follows from per-config `.tlog` tracking
compared by timestamp, but the specific sequence has not been reproduced. The
check is: build Debug, build Release, build Debug again, then look at whether
`build/x.ini` says `flavor = debug`. Note that D5 working under VS 2022 does
*not* confirm this — `always-run/` would work either way.

### O2. `per-config/` and `stagekit/` are unverified outside Ninja

`per-config/` should be the safest of all four (no shared destination for any
generator's tracking to get wrong), and `stagekit/` relies on `cmake_language(DEFER)`
and cross-directory `add_dependencies`, both generator-independent in principle.
Neither has been run under Visual Studio.

### O3. Per-project staging targets instead of one global target

Discussed, not built. A `stage_files_for(<target> <pairs...>)` helper would
create a per-project target with its own generated script: no global property,
no ordering, each subproject fully self-contained, and building one project
would stop re-staging the whole tree's files. Cost is one target and one process
per *project* (bounded, and parallel) rather than one per tree, plus IDE clutter
mitigable with a `FOLDER` property. This is arguably the better fit for this
monorepo's topology (D11), where there is rarely an umbrella tree at all.

Note `add_custom_command(TARGET x POST_BUILD)` cannot substitute for the custom
target in such a design: it only fires when `x` actually relinks, so an
up-to-date target would skip staging — the original bug.

### O4. Module discovery in standalone mode

`include(${CMAKE_CURRENT_LIST_DIR}/../cmake/stagekit.cmake)` is the one piece of
hardcoded topology left in a subproject. It is the price of D11 — there is no
parent to set `CMAKE_MODULE_PATH`. In a real tree this would presumably resolve
toward `base/` or a shared `cmake/` directory; the right answer depends on where
such a module would live monorepo-wide.

### O5. `stage_files` lands in a nondeterministic directory

The target is created by whichever directory calls `stage_file()` first. This is
functionally invisible — `ALL` propagates to the root and `add_dependencies`
works across directories — but it is real, and it would matter if anything ever
queried the target's directory properties.
