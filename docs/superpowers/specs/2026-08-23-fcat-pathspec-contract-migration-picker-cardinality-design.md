# Design: fcat pathspec contract migration (picker, cardinality, flag-naming) + shv parser unification

- **Issue:** [elifarley/hug-scm#311](https://github.com/elifarley/hug-scm/issues/311)
- **Date:** 2026-08-23
- **Status:** approved (brainstorming session, sections 1–3 each validated)
- **Approach:** C — full fcat migration + shv rewrite onto the shared parser
- **Ladder context:** pathspec contract [elifarley/hug-scm#292](https://github.com/elifarley/hug-scm/issues/292); PR-A v1.11.0.0 (listings), PR-B v1.12.0.0 ([elifarley/hug-scm#299](https://github.com/elifarley/hug-scm/issues/299)), PR-C v1.13.0.0 ([elifarley/hug-scm#305](https://github.com/elifarley/hug-scm/issues/305))

## Problem

`hug fcat 3 --` errors with `Missing arguments` (exit 1) instead of opening the
interactive path selector. `fcat` was never migrated onto the uniform pathspec
contract: it calls plain `parse_common_flags` (`git-fcat:67`), which consumes the
bare `--` silently, and the positional collector then dies at the `< 2` guard
(`git-fcat:83`). Probing the neighborhood (temp repo, this session) confirmed:

| Probe | Current behavior | Expected (contract) |
|---|---|---|
| `hug fcat 3 --` | `Missing arguments`, exit 1 | picker (file first, then N resolves) |
| `hug fcat 1 a.py b.py` | prints only a.py, exit 0 | exit 2, "accepts only one file" |
| `hug fcat -xX src/a.py` | `Unable to resolve reference '-xX'`, exit 1 | exit 2, flag-naming template |
| `hug stats file --` | **already fixed** by the #310 batch (routes to picker; clean error without gum) | — |

Additional gaps: `fcat` and `shv` have no rows in the `hug help :pathspec` support
matrix (`git-config/lib/python/articles/pathspec.md`); `stats file` and `h steps`
are listed as single-file commands in the article but have no conformance-suite
rows pinning that behavior.

`shv` is conformant but hand-rolls its `--` split (`git-shv:83-104`) — the last
bespoke parser in the show family.

## Design

### 1. fcat migration (the core fix)

New interface (contract-conformant, `w-get`-style target+paths split):

```
hug fcat <N|commit> <path>          # legacy two-positional form keeps working
hug fcat <N|commit> -- <path>       # separator form
hug fcat <N|commit> --              # picker (file first, then N resolves)
hug fcat <N|commit> -- src/*.py     # pathspecs; globs resolve, exactly ONE match required
```

Mechanism in `git-config/bin/git-fcat`:

- Replace `parse_common_flags` with `parse_common_flags_with_pathspecs --picker`
  (one eval, uniform order of operations).
- After the split: exactly one pre-arg (the `<N|commit>` target — a second bare
  token is a usage error, mirroring `shv`'s single-token guard); the path comes
  from `_pathspec_pathspecs`.
- **Cardinality:** >1 pathspec → `reject_multiple_files "hug fcat"` (exit 2,
  family template "accepts only one file", `hug-cli-flags:526`). Also fixes the
  legacy form's silent first-wins.
- **Picker:** on `HUG_INTERACTIVE_FILE_SELECTION`, run `select_files_with_status
  --single` (cwd-scoped; `--browse-root` selects repo scope — same as
  `stats file`). Picker-first solves the N chicken-and-egg: the file is chosen,
  then N targets resolve via `get_commit_n_back "$N" "$file"` and commit targets
  via `rev-parse`. No gum → clean "File argument required"-style error (exit 1,
  same as `stats file`).
- **Flag-naming rejection:** unknown dash-tokens before `--` exit 2 with the
  contract template (`Unknown option: -xX. Pathspecs beginning with '-' require
  '--': hug fcat -- -xX. See 'hug help :pathspec'.`). The existing `-N`-range
  rejection (ranges unsupported) stays, ordered before the generic arm (the `sh`
  DATA-arm pattern, `git-sh:121-126`).
- Colon syntax (`fcat HEAD:src/a.py`) stays rejected — characterization row
  unchanged.
- Help text: USAGE gains the `--`/picker forms; SEE ALSO links
  `hug help :pathspec`.
- No change to the read-only core (`check_file_in_commit`, `git show`) — only
  the argument surface changes.

### 2. shv rewrite onto the shared parser (behavior-preserving)

Retire `shv`'s hand-rolled `--` split without changing any observable behavior —
its characterization rows (`test_pathspec_conformance.bats:2374-2421`) must keep
passing byte-for-byte.

- Replace the hand-rolled loop + `-h` pre-scan with
  `parse_common_flags_with_pathspecs` (no `--picker` — `shv` launches a
  difftool, not a file picker).
- DATA arm first: `-[0-9]{1,3}` range spellings are data, never unknown-flag
  rejections (checked before any `-*` rejection so `-3` keeps its meaning).
- After the split: pre-args hold 0 or 1 token (committish/N/range; default
  `HEAD`). A second bare token keeps the exact current error (`takes a single
  commit/range … Unexpected: '$1'`).
- The `s|u|w` working-tree redirect and the delegation to
  `dd_commit_diff "$token" -- "${pathspecs[@]}"` are untouched.
- Help-scan nuance preserved: `-h` before the first `--` shows help; after `--`
  it is pathspec data.
- **Risk fallback:** if the shared parser's delegation rejects `-3` despite the
  data arm, keep `shv`'s split but source the rejection templates from
  `hug-cli-flags`. The existing characterization rows are the gate — nothing
  ships if they go red.

### 3. Conformance suite, help matrix, testing

Suite (`tests/unit/test_pathspec_conformance.bats`):

- New roster class `PATHSPEC_TARGETPLUSFILE_ROWS=(fcat)` — the two-positional
  shape (target + exactly-one path, picker arm). Column loops get the class so
  the master-roster orphan check covers it.
- Flip the fcat characterization rows (lines 2488–2519) into contract rows in
  the same PR, per suite convention: `fcat 3 --` → picker path; `fcat 1 a b` →
  exit 2; `fcat -xX` → exit 2 flag-naming template; colon-syntax rejection
  stays.
- Enroll `stats file` + `h steps` as single-file-adjacent rows: bare `--` →
  picker path, two files → exit 2, unknown dash-token → exit 2. `h steps` gets
  probed first; if probing reveals gaps, the fix lands in this PR, and the rows
  pin whatever conformant shape ships.
- `shv` characterization rows stay as-is — they are the rewrite's regression
  gate.

Docs (`git-config/lib/python/articles/pathspec.md`):

- Matrix row for `fcat`: `✅ (the <N|commit> target; everything after it —
  separator or not — is the single path) | — | picker (scoped)`.
- Matrix row for `shv` (conformant but row-less): `✅ (single commit/range
  token + scoped paths) | — | inert`.
- Correct the single-file exclusion sentence: `fcat` leaves the "take a file
  ARGUMENT" list (now pathspec-conformant); `stats file` and `h steps` stay
  listed with their exit-2 cardinality noted.

Testing:

- `make test-unit TEST_FILE=test_pathspec_conformance.bats` first, then the
  fcat/stats/shv/sh-specific suites, then full `make test`.
- The session's probes (table above) become the before/after receipts in the PR
  body.

## Out of scope

- Any change to `shv`'s observable behavior (rewrite is mechanism-only).
- Migrating other hand-rolled commands not named in the issue.
- `h steps` redesign beyond conformance gaps revealed by probing.

## Success criteria

1. `hug fcat 3 --` opens the picker (or errors cleanly without gum), never
   `Missing arguments`.
2. `hug fcat 1 a.py b.py` exits 2 with the family cardinality template.
3. `hug fcat -xX src/a.py` exits 2 with the flag-naming template.
4. All existing fcat/shv characterization behavior preserved except the three
   flips above; full `make test` green.
5. `hug help :pathspec` matrix has rows for `fcat` and `shv`; the single-file
   list is corrected.
6. Master-roster orphan check passes with `fcat`, `stats file`, `h steps`
   enrolled.
