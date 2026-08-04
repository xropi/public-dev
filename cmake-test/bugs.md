# cmake-test bugs

Defects in what already exists, numbered B1, B2, … Design decisions live in
`design.md` (D*/O*).

### B1. `output-rule/` declared itself `project(ini-per-config)`

**Status:** Fixed (2026-08-04) — renamed to `ini-output-rule`.

**Symptom:** none on Ninja, which is why it survived: the project name is not in
any path the `.sh` scripts print or use, and the binary is `build/<Config>/app`
either way.

**Root cause:** copy-paste from `per-config/` when the folders were split out per
D12. `per-config/` had meanwhile been renamed to `ini-per-config-dir`, so the two
did not even collide in a way that would have surfaced.

**Why it mattered enough to fix:** the project name *is* the solution file name
under a Visual Studio generator, so `output-rule/` would have opened as
`ini-per-config.sln`. That lands precisely where the VS work is still open (O1),
comparing variants whose folders are deliberately named after their mechanism
(D12) — the one context where the wrong name misleads.

**Found by:** collecting the per-folder `.sln` names while adding
`gen-vs2022.bat` to the other three folders.
