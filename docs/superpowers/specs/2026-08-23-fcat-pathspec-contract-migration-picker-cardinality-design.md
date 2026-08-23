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
hug fcat <N|commit> <path> --       # picker SCOPED to the path candidates
```

### 1a. Shape × outcome table (normative — every input shape, one outcome)

| Input shape | Outcome |
|---|---|
| `fcat` (no args) | error exit 1: target required (usage text) |
| `fcat --` | error exit 1: target required — no silent HEAD default; every documented form carries an explicit target |
| `fcat <N|commit>` | error exit 1: file argument required (no picker — picker fires only on the trailing bare `--`) |
| `fcat <N|commit> <path>` | legacy form: print content (unchanged behavior) |
| `fcat <N|commit> -- <path>` | same as legacy form |
| `fcat <N|commit> <p1> <p2>` (any side of `--`) | exit 2, `reject_multiple_files` family template |
| `fcat <N|commit> --` | picker (`--single`, cwd-scoped); pick, then resolve N/commit; cancel → info, exit 0 (stats-file precedent) |
| `fcat <N|commit> <path> --` | picker SCOPED to the path candidates (`forward_pathspecs_to_picker`); the picked file REPLACES the candidates (#292 ratified trailing-`--`-after-pathspecs rule) |
| `fcat <N|commit> -- 'src/*.py'` (quoted glob) | error exit 1: `does not exist in commit` — the path is a LITERAL file path; globs are NOT resolved (see Glob note) |
| `fcat <N|commit> -- -weird.txt` | literal dash-leading filename via the separator (contract datum arm) |
| `fcat -xX <path>` / `fcat -xX` | exit 2, flag-naming template (wired via `parse_scoped_own_flags`, below) |
| `fcat -3 <path>` | exit 1, existing range-unsupported rejection (unchanged text) |
| `fcat HEAD:src/a.py` | error exit 1 — colon syntax stays rejected; characterization row KEEPS `assert_failure` but its `--partial` flips from `Missing arguments` to the new file-argument-required text |
| `fcat --browse-root 3` | error exit 1: `--browse-root` cannot be used with explicit paths (existing `parse_common_flags` behavior, pinned with a row) |
| picker, no gum available | clean error exit 1: file argument required (same as `stats file`) |

**Glob note (YAGNI):** the issue never asked for glob resolution, and unquoted
globs expand in the user's shell before hug runs. The single path is therefore a
literal file path end-to-end; a quoted glob dies loudly in
`check_file_in_commit` (exit 1), pinned by a conformance row. No
glob-resolving mechanism is added.

Mechanism in `git-config/bin/git-fcat`:

- Replace `parse_common_flags` with `parse_common_flags_with_pathspecs --picker`
  (one eval, uniform order of operations).
- **Pre-arg vs pathspec roles:** `parse_pathspecs` puts ALL separator-free args
  into pre-args (hug-cli-flags:64-86), so the split alone cannot produce the
  legacy form. Rule: `pre-args[0]` is the `<N|commit>` target (zero pre-args →
  target-required error); `pre-args[1:]` are FILE CANDIDATES that JOIN
  `_pathspec_pathspecs` for the cardinality check — exactly one file candidate
  in total, from either side of the separator.
- **Cardinality:** >1 candidate → `reject_multiple_files "hug fcat"` (exit 2,
  family template "accepts only one file", `hug-cli-flags:526`). Also fixes the
  legacy form's silent first-wins. 0 candidates and no picker → file-argument-
  required error (exit 1).
- **Picker:** the eval exports `HUG_INTERACTIVE_FILE_SELECTION=true` only on
  the trailing-bare-`--` condition; `unset HUG_INTERACTIVE_FILE_SELECTION`
  BEFORE the eval so an inherited value cannot spuriously fire the picker (the
  export is parse-local truth). On trigger: `select_files_with_status --single`
  (cwd-scoped; `--browse-root` selects repo scope — same as `stats file`);
  scope to the path candidates via `forward_pathspecs_to_picker` when present;
  cancel → info, exit 0 (stats-file precedent). Picker-first solves the N
  chicken-and-egg: the file is chosen, then N targets resolve via
  `get_commit_n_back "$N" "$file"` and commit targets via `rev-parse`. No gum →
  clean "File argument required"-style error (exit 1, same as `stats file`).
- **Flag-naming rejection (explicit wiring — the shared parser does NOT do
  this):** `parse_common_flags` passes unknown dash tokens through
  (hug-cli-flags:193-196 — today's `-xX` probe is the proof), so the exit-2
  template must come from `parse_scoped_own_flags "hug fcat" "" <candidates>`
  called AFTER the eval (empty own-flag spec: arm 2 rejects unknown `-*`/`--*`
  tokens, arm 3 checks misordered flags), exactly as `git-w-discard:100` wires
  it. The existing `-N`-range rejection (ranges unsupported) stays, ordered
  BEFORE that call (the `sh` DATA-arm pattern, `git-sh:121-126`).
- Colon syntax (`fcat HEAD:src/a.py`) stays rejected — see the shape table for
  the row's `--partial` flip.
- Help text: USAGE gains the `--`/picker forms; SEE ALSO links
  `hug help :pathspec`.
- No change to the read-only core (`check_file_in_commit`, `git show`) — only
  the argument surface changes.

### 2. shv rewrite onto the shared parser (behavior-preserving)

Retire `shv`'s hand-rolled `--` split without changing any observable behavior
(the common-flag guard below is what makes that promise true) — its
characterization rows (`test_pathspec_conformance.bats:2374-2421`) must keep
passing byte-for-byte, and new rows cover the spellings those rows miss.

- Replace the hand-rolled loop + `-h` pre-scan with
  `parse_common_flags_with_pathspecs` (no `--picker` — `shv` launches a
  difftool, not a file picker).
- **Common-flag guard (restores the "behavior-preserving" promise):** the
  shared parser CONSUMES `-q`, `-f`, `-y`, `--dry-run`, `--browse-root`, but
  today those tokens reach the engine and die in `reject_flag_ref`
  (hug-git-difftool:292 → hug-git-repo:236-242, `Unknown flag: …` exit 2) —
  without a guard, `hug shv -q` would silently strip the flag and LAUNCH a
  difftool on HEAD. Guard: BEFORE the eval, scan the args up to the first `--`;
  a token matching one of those five spellings is rejected with the engine's
  current `Unknown flag: <tok>` exit-2 error. New characterization rows pin
  `shv -q` and `shv --browse-root 3` (the latter today exits 1 in
  `parse_common_flags`'s explicit-paths check — either current error is
  acceptable; the row pins whichever ships).
- After the split: pre-args hold 0 or 1 token (committish/N/range; default
  `HEAD`). A second bare token keeps the exact current error (`takes a single
  commit/range … Unexpected: '$1'`).
- The `s|u|w` working-tree redirect and the delegation to
  `dd_commit_diff "$token" -- "${pathspecs[@]}"` are untouched.
- Help-scan nuance preserved: `-h` before the first `--` shows help; after `--`
  it is pathspec data.
- `-[0-9]{1,3}` range data needs NO special casing in the primary design: the
  shared parser passes unknown dash tokens through (hug-cli-flags:193-196) and
  the engine's `reject_flag_ref` already exempts `-N`. The DATA-arm ordering
  matters only in the fallback.
- **Risk fallback:** if the shared parser's delegation nonetheless mangles any
  characterization input, keep `shv`'s split but source the rejection templates
  from `hug-cli-flags`, with the `-[0-9]{1,3}` DATA arm ordered before any
  `-*` rejection. The existing characterization rows are the gate — nothing
  ships if they go red.

### 3. Conformance suite, help matrix, testing

Suite (`tests/unit/test_pathspec_conformance.bats`):

- New roster class `PATHSPEC_TARGETPLUSFILE_ROWS=(fcat)` — the two-positional
  shape (target + exactly-one path, picker arm). Column loops get the class so
  the master-roster orphan check covers it.
- Flip the fcat characterization rows (lines 2488–2519) into contract rows in
  the same PR, per suite convention — FOUR flips, not three: `fcat 3 --` →
  picker path; `fcat 1 a b` → exit 2; `fcat -xX` → exit 2 flag-naming template;
  colon-syntax row keeps `assert_failure` but its `--partial` flips from
  `Missing arguments` to the new file-argument-required text.
- Pin every shape×outcome row from §1a as a conformance row, including the two
  previously-unspecified picker compositions (`fcat --` → target-required
  error; `fcat <N> <path> --` → scoped picker, post-pick replacement), the
  quoted-glob literal-path failure, and `fcat --browse-root 3`.
- Enroll `stats file` + `h steps` as single-file-adjacent rows: bare `--` →
  picker path, two files → exit 2, unknown dash-token → exit 2. `h steps` gets
  probed first; if probing reveals gaps, the fix lands in this PR, and the rows
  pin whatever conformant shape ships.
- `shv` characterization rows stay as-is — they are the rewrite's regression
  gate — PLUS new rows for the common-flag spellings (`shv -q`, `shv
  --browse-root 3`) that the shared parser would otherwise silently consume.

Docs (`git-config/lib/python/articles/pathspec.md`):

- Matrix row for `fcat`: `✅ (the <N|commit> target; everything after it —
  separator or not — is the single path) | — | picker (scoped)`.
- Matrix row for `shv` (conformant but row-less): `✅ (single commit/range
  token + scoped paths) | — | inert`.
- Correct the single-file exclusion sentence: `fcat` needs no REMOVAL from the
  "take a file ARGUMENT" list — it was never in it (the Problem section notes
  the omission); the real edits are the two new matrix rows and an exit-2
  cardinality annotation on `stats file` / `h steps`.

Testing:

- `make test-unit TEST_FILE=test_pathspec_conformance.bats` first, then the
  fcat/stats/shv/sh-specific suites, then full `make test`.
- The session's probes (table above) become the before/after receipts in the PR
  body.

## Out of scope

- Any change to `shv`'s observable behavior (rewrite is mechanism-only; the
  common-flag guard exists precisely to keep this true).
- Migrating other hand-rolled commands not named in the issue.
- `h steps` redesign beyond conformance gaps revealed by probing.

## Success criteria

1. `hug fcat 3 --` opens the picker (or errors cleanly without gum), never
   `Missing arguments`.
2. `hug fcat 1 a.py b.py` exits 2 with the family cardinality template.
3. `hug fcat -xX src/a.py` exits 2 with the flag-naming template.
4. All existing fcat/shv characterization behavior preserved except the four
   fcat flips; `shv -q` and `shv --browse-root 3` keep dying loudly (new rows);
   full `make test` green. Every §1a shape×outcome row has a matching
   conformance row.
5. `hug help :pathspec` matrix has rows for `fcat` and `shv`; the single-file
   list is corrected.
6. Master-roster orphan check passes with `fcat`, `stats file`, `h steps`
   enrolled.
