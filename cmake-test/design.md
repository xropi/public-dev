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

Defects go in `bugs.md` (B*), deferred features in `backlog.md` (BL*, not created
yet).

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

**Extended by D15:** the uniform script set is four files, not three.

### D13. `stage_file()` takes a file *or* a directory

**Decision:** the source may be either, with no second entry point and no flag —
`stage_file(app-b "<dir>" "${CMAKE_BINARY_DIR}/assets")` puts the *contents* of
`<dir>` at `<dst>`, so `<dst>` is what the caller asked for in both cases. The
generated script gains a `_stage(src dst)` preamble function; each registered
entry is now a one-line call into it.

**Rationale, three parts:**

*Why the test lives in the generated script.* `IS_DIRECTORY` cannot be evaluated
in `stage_file()`, because a source holding a `$<CONFIG>` genex (D2 — the normal
case here) is still unresolved text at configure time and the test is
unconditionally false. Inside the script the genex is already a real path. This
is D8's argument reused: the script is where you have a real language *after*
the generator expressions are gone.

*Why a preamble function rather than an inlined branch per entry.* The branch is
~7 lines; emitting it per entry makes the script grow with the file count for no
benefit. One function plus N call lines keeps the generated artifact readable —
it stays diffable by eye, which matters for a harness meant to be read. The
preamble is a literal **inside** `stage_finalize` rather than a variable beside
it: that function runs deferred in the root directory scope (D9), which cannot
see a variable set where the module was included, i.e. in a subproject.

*Why not `file(COPY)`, which already does directories.* Because it decides what
is up to date by **timestamp**, and two per-config source trees have identical
mtimes after a git checkout (git sets them all to checkout time). Measured
directly: with `ad/` and `ar/` created in the same second, a full Release build
left `build/assets/` on the debug copy — silently, which is precisely the
staleness the whole harness exists to prevent. **Content comparison is therefore
the requirement**, not a preference; which content-comparing mechanism does the
directory half is D14.

**Known limit, inherited rather than introduced: orphans are not removed.** A
file deleted from the source tree keeps its staged copy until `build/` is wiped.
Every candidate mechanism behaves this way, so nothing was given up by the choice
among them. **Lifted by D16**, which makes it a per-call decision via a required
`del_stale` argument.

### D14. Directories are copied by `-E copy_directory_if_different`

**Decision:** the directory half of `_stage()` is one call —

```cmake
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E copy_directory_if_different "${src}" "${dst}"
    COMMAND_ERROR_IS_FATAL ANY)
```

— rather than a `file(GLOB_RECURSE)` walk that recurses into itself and copies
each file with `file(COPY_FILE ... ONLY_IF_DIFFERENT)`. The floor rises from
**3.21 to 3.26** accordingly, in all three `CMakeLists.txt` and in CLAUDE.md.

**Rationale:** it satisfies D13's content-comparison requirement — measured on
CMake 4.2.3 with two directory trees sharing mtimes and differing in content,
including nested files. Given that, the recursion bought nothing but its own
explanation, and **clarity is the point of this harness**: five lines of walk,
glob semantics and self-recursion versus one named command that says what it
does. The generated script is meant to be read.

The floor was the only real objection and it is not one here — this machine runs
4.2.3, and CMake 3.26 is from March 2023. This is a comparison harness that
nothing depends on (D12), so it is also the cheapest possible place to hold a
newer floor.

The `IS_DIRECTORY` branch stays: `copy_directory_if_different` errors on a file
source (measured, exit 1), so it cannot serve both halves.
`COMMAND_ERROR_IS_FATAL ANY` is not optional either — `execute_process` reports
failure only through `RESULT_VARIABLE`, so without it a failed copy would be
silent, whereas `file(COPY_FILE)` aborts the script on its own.

**Cost, accepted:** one subprocess per staged *directory*, where the walk stayed
inside the single `cmake -P` of D8. It is bounded by directory count, not file
count, so it does not reintroduce the process-per-file growth D8 was about.

**Consequence:** the walk's incidental properties are gone, and neither was
load-bearing — empty directories are now staged (`GLOB_RECURSE` yielded only
files), and dotfiles are still staged, as they were under the glob (both
measured).

### D15. `gen-vs2022.bat` in every folder, into `+build-vs2022/`

**Decision:** each of the four folders carries the same `gen-vs2022.bat`,
configuring `-G "Visual Studio 17 2022"` into `+build-vs2022/` — a *second* tree
beside the Ninja `build/`, not a replacement for it.

**Rationale:** O1 and O2 are the only unmeasured claims in this record, and they
are open purely because running them takes a Windows machine. Reducing that to
"double-click, open the .sln, build three times" is the difference between a
question that gets answered and one that stays open — `stagekit/` already had
this script and the other three did not, which is backwards, since `output-rule/`
is the variant with an actual *prediction* riding on VS (D4).

Separate trees rather than one reconfigured in place: a generator cannot be
changed in an existing build directory, so sharing `build/` would mean wiping it
on every switch between the `.sh` scripts and the IDE — and the harness's whole
method is running the variants repeatedly. The `+` prefix makes it gitignored by
the repo-wide `**/+*` with no per-folder rule, matching the scratch-file
convention.

Uniform content across folders, including the `.sln` name in the comment header:
one file to read, and any difference between folders is then a real difference
rather than drift. Batch rather than PowerShell per the global scripting rule,
and it stays a linear three lines.

**Not decided here:** what the VS runs actually show. Until someone runs them,
O1 and O2 stand exactly as written.

### D16. `stage_file()` takes a required `del_stale`

**Decision:** a fourth positional argument —
`stage_file(<target> <src> <dst> <del_stale>)`, **required**, no default. ON
makes a directory `<dst>` a mirror of `<src>`: anything in the destination that
the source no longer has is deleted. OFF leaves those files, which is every copy
tool's behaviour. This closes the "orphans are not removed" limit recorded in
D13.

**Why required rather than optional-defaulting-to-OFF.** Deletion is the one
thing in this module that can destroy something a user put in `<dst>` on purpose,
and `<dst>` may legitimately be shared — `build/` itself in the standalone mode
of D11. A default would let a call *not say* which behaviour it wants, so the
answer would live in the module rather than at the call site, exactly where a
reader looks for it. Making it explicit costs one word per call, of which there
are three in the whole tree, and CMake enforces it: a three-argument call is a
hard configure error (*"Function invoked with incorrect arguments"*, verified),
not a silent fallback.

This is the same instinct as D10 folding `add_dependencies` into `stage_file()` —
except inverted, because the cases differ. There, one behaviour was always
correct, so the function should just do it; here both answers are legitimate, so
the function should refuse to guess.

**Why a positional rather than a keyword.** The whole interface is one function
with three positionals (D9/D10); `cmake_parse_arguments` for a single boolean
would be more machinery than the module has anywhere else.

**Why prune after copying rather than wipe before it.** `file(REMOVE_RECURSE
"${dst}")` ahead of the copy is one line and obviously correct, but it makes
every build a full recopy — and `stage_files` has no up-to-date check (D5), so
that cost lands on *every* build, not just ones where something changed. It
would put a performance cliff behind a flag whose name says nothing about
copying. Pruning keeps the content-compared incremental copy of D14 and adds
five lines. `LIST_DIRECTORIES true` on the glob is what lets a single
`REMOVE_RECURSE` take a vanished subtree whole instead of leaving empty
directories behind — the wart that a files-only prune would have.

**It means nothing for a file source**, where `<dst>` *is* the file and
`COPY_FILE` replaces it; the parameter is accepted and ignored there rather than
being an error, since whether `<src>` is a file is only known at build time and
a build-time warning would fire on every build.

**Measured**, all four behaviours: a debug-only file staged under Debug is gone
after a Release build and back after the next Debug one; a hand-planted
`junkdir/inner/x` subtree is removed whole; a hand-planted orphan next to a
`del_stale`-OFF destination survives.

### D17. `app-a` sets `VS_DEBUGGER_WORKING_DIRECTORY`

**Decision:** `stagekit/proj-a` sets the target property
`VS_DEBUGGER_WORKING_DIRECTORY` to `$(ProjectDir)..`, so an F5 from Visual
Studio starts `app-a` one directory above the `.vcxproj` rather than in it. One
target only, and nothing else in the harness depends on it.

**Rationale:** the IDE half of this harness (D15, O1/O2) is driven by F5, and
the working directory is what decides whether an app's *relative* data paths
resolve — the same question staging answers for absolute ones. Recording the
mechanism next to the staging call is cheaper than rediscovering the property
name. `.vcxproj.user` is generated by CMake, so this survives a reconfigure,
which a working directory typed into the IDE's property pages does not.

`$(ProjectDir)` is an MSBuild macro, not a CMake variable: CMake writes it
through verbatim (its own expansion syntax is `$<...>`) and VS expands it at
launch. It ends in a backslash, so `..` appends without a separator. It names
the directory holding the project file — the target's **binary** dir, i.e.
`+build-vs2022/proj-a/` under the umbrella build and `proj-a/build/` standalone,
so the parent differs between the two modes of D11. That is acceptable for a
demonstration; a target that actually needed a fixed location would use a CMake
path like `${CMAKE_CURRENT_SOURCE_DIR}/..`, which the property also accepts
along with generator expressions.

**No `if(CMAKE_GENERATOR MATCHES "Visual Studio")` guard**, because every other
generator ignores the property outright — a guard would only be needed if the
*value* had to differ per generator. The variable form
`CMAKE_VS_DEBUGGER_WORKING_DIRECTORY` would apply it to all targets created
afterwards; not used here, since the point is to show the per-target call.

**Not measured.** Like everything VS in this record, it is written but not run;
it changes no build and no staging, so it cannot affect O1 or O2 either way.

---

## Open

### O1. `output-rule/` on Visual Studio 2022 is predicted, not measured

The MSBuild failure described in D4 follows from per-config `.tlog` tracking
compared by timestamp, but the specific sequence has not been reproduced. The
check is: build Debug, build Release, build Debug again, then look at whether
`+build-vs2022/x.ini` says `flavor = debug`. Note that D5 working under VS 2022
does *not* confirm this — `always-run/` would work either way.

`gen-vs2022.bat` (D15) configures the tree; nothing else is needed to run it.

### O2. `per-config/` and `stagekit/` are unverified outside Ninja

`per-config/` should be the safest of all four (no shared destination for any
generator's tracking to get wrong), and `stagekit/` relies on `cmake_language(DEFER)`
and cross-directory `add_dependencies`, both generator-independent in principle.
Neither has been run under Visual Studio; `gen-vs2022.bat` (D15) is there to
make that a short job. For `stagekit/` the interesting part is not the copying
but F5 with *"Only build startup projects and dependencies on Run"*, which is
the case D10's `add_dependencies` exists for.

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

### O6. `cmake -E copy_directory_if_different` instead of the D13 recursion

Decided → see D14.
