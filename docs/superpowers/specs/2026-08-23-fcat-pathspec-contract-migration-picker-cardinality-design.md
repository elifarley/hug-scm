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
already have cardinality and unknown-flag conformance rows (bats:2042-2173,
2261, 2337-2354 — the #310/#302 batches) but NO bare-`--` picker-path row —
that is the only genuinely missing pin for them.

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
| `fcat <N|commit> <path> --` | picker SCOPED to the path candidates (`forward_pathspecs_to_picker` AFTER the candidates are materialized into `_pathspec_pathspecs` — see the sink table); the picked file REPLACES the candidates (#292 ratified trailing-`--`-after-pathspecs rule) |
| `fcat <N|commit> -- 'src/*.py'` (quoted glob) | error exit 1: `does not exist in commit` — the path is a LITERAL file path; globs are NOT resolved (see Glob note) |
| `fcat <N|commit> -- -weird.txt` | literal dash-leading filename via the separator (contract datum arm) |
| `fcat -xX <path>` / `fcat -xX` | exit 2, flag-naming template (wired via `parse_scoped_own_flags`, below) |
| `fcat -3 <path>` | exit 1, existing range-unsupported rejection (unchanged text) |
| `fcat HEAD:src/a.py` | error exit 1 — colon syntax stays rejected; characterization row KEEPS `assert_failure` but its `--partial` flips from `Missing arguments` to the new file-argument-required text |
| `fcat --browse-root 3` | error exit 1: `--browse-root` cannot be used with explicit paths (existing `parse_common_flags` behavior, pinned with a row) |
| `fcat --browse-root` / `fcat --browse-root --` | error exit 1: target required — `--browse-root` composes with no other pre-arg, and zero pre-args hits the target-required rule; there is NO reachable repo-scoped fcat picker (see Vestigial note) |
| `fcat 3 -- ''` (empty-string arg) | error exit 1: file argument required — `reject_multiple_files` ignores empty strings (hug-cli-flags:531), so the 0-candidates check fires, not cardinality |
| `fcat <N> -- -q` (flag spelling after `--`) | exit 2, `Flags must precede '--'` — `parse_scoped_own_flags` arm 3 exact-spelling rejection (hug-cli-flags:663-675); the family tradeoff noted above |
| picker, no gum available | clean error exit 1: file argument required (same as `stats file`) |

**Glob note (YAGNI):** the issue never asked for glob resolution, and unquoted
globs expand in the user's shell before hug runs. The single path is therefore a
literal file path end-to-end; a quoted glob dies loudly in
`check_file_in_commit` (exit 1), pinned by a conformance row. No
glob-resolving mechanism is added.

**Vestigial note (`--browse-root`):** `--browse-root` composes with no other
pre-arg (explicit-paths check, hug-cli-flags:281-284) and zero pre-args hits
the target-required rule — no input reaches a repo-scoped fcat picker. The
stats-file precedent does not transfer (stats file has no target atom; its
picker fires on the zero-args fallback, git-stats-file:154-168). The repo-scope
clause is therefore DELETED from this design: fcat's picker is cwd-scoped,
full stop. A file named `-q` after `--` is family-tradeoff blocked (arm 3
exact-spelling rejection) — accepted, same as every scoped-family command.

Mechanism in `git-config/bin/git-fcat` — order of operations (each numbered
step is load-bearing; see the sink table below for who writes/reads what):

1. `unset HUG_INTERACTIVE_FILE_SELECTION` (inherited values must not fire the
   picker; `parse_common_flags`' own `--browse-root` arm exports the same
   variable, hug-cli-flags:278-279).
2. `eval "$(parse_common_flags_with_pathspecs --picker "$@")"` — one eval,
   uniform order; the trailing bare `--` is stripped BEFORE the split
   (hug-cli-flags:366-370), and `$@` becomes the separator-free pre-args.
3. Range check FIRST, reading pre-args[0] directly (`[[ "${1:-}" =~
   ^-[0-9]+$ ]]` → the existing range-unsupported rejection, unchanged text).
   This must fire BEFORE step 4's helper — otherwise `fcat -3 src/a.py` flips
   to arm 2's generic unknown-option exit 2 instead of the shape table's
   unchanged exit-1 text (the `sh` DATA-arm pattern, `git-sh:121-126`).
4. `parse_scoped_own_flags "hug fcat" "" ...` over ALL pre-args (`"$@"`), the
   `git-w-discard:100` pattern — arm 2 then rejects ANY dash token including
   one at position 0 (`-xX` becomes the target only if this step is skipped).
   The helper's output array is read by its own arm 3 (post-`--`
   exact-spelling rejection) and otherwise ignored by fcat.
5. Target and candidates are computed from the untouched `$@` and
   `_pathspec_pathspecs` directly, NOT from the helper's array:
   `target="${@:1:1}"` (zero pre-args → target-required error);
   `candidates=("${@:2}" ∪ _pathspec_pathspecs)`.
6. **Materialize the union into `_pathspec_pathspecs`** (append `"${@:2}"`)
   BEFORE any picker forwarding — `forward_pathspecs_to_picker`
   (hug-cli-flags:437-446) reads ONLY that global, and for
   `fcat 3 a.py --` the path sits in pre-args (the trailing `--` was stripped
   pre-split), so without this step the picker opens unscoped and CI without
   gum cannot tell the difference.
7. Cardinality: >1 candidate → `reject_multiple_files "hug fcat"` (exit 2,
   family template "accepts only one file", hug-cli-flags:526 — ignores empty
   strings, so `fcat 3 -- ''` falls through to the 0-candidates check). Also
   fixes the legacy form's silent first-wins. 0 candidates and no picker →
   file-argument-required error (exit 1).
8. Picker (on the parse-local export): `select_files_with_status --single`
   (cwd-scoped only — see Vestigial note), scoped to the candidates via
   `forward_pathspecs_to_picker`; cancel → info, exit 0 (stats-file
   precedent). Picker-first solves the N chicken-and-egg: the file is chosen,
   then N targets resolve via `get_commit_n_back "$N" "$file"` and commit
   targets via `rev-parse`. No gum → clean "File argument required"-style
   error (exit 1, same as `stats file`).

**Sink table (representation → consumer):**

| Representation | Written by | Read by | When |
|---|---|---|---|
| `$@` (pre-args) | the eval (step 2) | range check (step 3), `parse_scoped_own_flags` (step 4), target/candidate slice (step 5) | immediately after eval |
| `_pathspec_pathspecs` | the eval; step 6 appends pre-args[1:] | `forward_pathspecs_to_picker` (step 8), cardinality (step 7) | after materialization |
| `HUG_INTERACTIVE_FILE_SELECTION` | the eval (trailing-bare-`--` condition only) | picker trigger (step 8) | unset first (step 1) |
| helper's output array | `parse_scoped_own_flags` (step 4) | the helper's OWN arm 3 (post-`--` exact-spelling rejection, hug-cli-flags:663-675) — otherwise ignored by fcat | during step 4 |

- Colon syntax (`fcat HEAD:src/a.py`) stays rejected — see the shape table for
  the row's `--partial` flip.
- Help text: USAGE gains the `--`/picker forms; SEE ALSO links
  `hug help :pathspec`.
- No change to the read-only core (`check_file_in_commit`, `git show`) — only
  the argument surface changes.

### 2. shv rewrite onto the shared parser (behavior-preserving)

Retire `shv`'s hand-rolled `--` split with ONE deliberate observable change
(plus one ultra-edge family tradeoff, noted below): flags spelled AFTER the
positional converge to the exit-2 flag-naming family — today `hug shv 3 -q`
dies exit 1 as a second bare token (`Unexpected: '-q'`, git-shv:99; `error()`
exits 1), post-rewrite the position-independent guard fires `Unknown flag:
-q` exit 2. That is the contract-aligned direction and is pinned as a NEW row;
everything else is preserved byte-for-byte via the guard below. The
characterization rows (`test_pathspec_conformance.bats:2374-2429`) must keep
passing, and new rows cover the spellings those rows miss.

- Replace the hand-rolled loop + `-h` pre-scan with
  `parse_common_flags_with_pathspecs` (no `--picker` — `shv` launches a
  difftool, not a file picker).
- **Flag-classification guard (restores the "behavior-preserving" promise):**
  the shared parser CONSUMES `-q`, `-f`, `-y`, `--dry-run`, `--browse-root` —
  and GNU getopt (the engine inside `parse_common_flags`) also consumes
  COMBINED shorts (`-fq` → ` -f -q --`, rc=0 — mechanically verified) — but
  today every such token reaches the engine and dies in `reject_flag_ref`
  (hug-git-difftool:292 → hug-git-repo:232-244, `Unknown flag: …` exit 2).
  Without a guard, `hug shv -q` (and `shv -fq`) would silently strip the flag
  and LAUNCH a difftool on HEAD. Guard: shv has NO legal flags before `--`, so
  the guard CLASSIFIES instead of spell-matching: BEFORE the eval, reject
  every pre-`--` token matching `-[^0-9]*` or `--*` with the engine's current
  `Unknown flag: <tok>` exit-2 error — exempting only `-[0-9]+` range data
  (ANY length, matching `reject_flag_ref`'s `^-[0-9]+$` exemption exactly, so
  `shv -1234` keeps today's range-data handling) and `-h/--help` (handled
  earlier). The guard routes THROUGH `reject_flag_ref` itself (or prints help
  before erroring the same way) so the USAGE banner the characterization row
  asserts (bats:2417) is preserved. Classification subsumes combined shorts,
  `--flag=value` spellings, and any future common flag; no enumeration to keep
  in sync.
- **Family tradeoff, `shv -- --`:** the shared helper's reservation 1 strips
  the trailing bare `--` unconditionally, so a pathspec literally named `--`
  is dropped (today it reaches the engine and the No-changes guard fires).
  Post-rewrite that ultra-edge input launches an unscoped HEAD diff — the
  same reservation-1 tradeoff every `--picker` command in the family already
  ratified in #292; accepted and noted here, not redesigned.
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
- Inventory (grep receipt: fcat rows exist ONLY at bats 2488-2521 —
  HEAD+path, the `--` form, colon syntax, `-xX`): TWO flips — the colon row's
  `--partial` (bats:2515, `Missing arguments` → new file-argument-required
  text) and the `-xX` row (bats:2519, ref-error → exit-2 flag-naming template)
  — plus NEW rows for everything the shape table adds: `fcat 3 --` (picker),
  `fcat 1 a b` (exit 2), `fcat --`, `fcat <N> <path> --` (scoped picker —
  STUB `select_files_with_status` and assert the forwarded opts contain the
  pathspec, the suite's existing git/difftool-argv technique, so the row
  discriminates scoping even without gum), quoted-glob literal failure,
  `fcat --browse-root`, `fcat --browse-root --`, `fcat --browse-root 3`,
  the empty-string arg, the post-`--` flag-spelling arm (`fcat 3 -- -q` →
  exit 2, `Flags must precede '--'`), and the three §1a rows no existing row
  pins: `fcat` bare (target required), `fcat <N|commit>` target-only (file
  argument required), `fcat -3 <path>` (range-unsupported rejection,
  unchanged text).
- Enroll `stats file` + `h steps` with ONLY the bare-`--` picker-path row each
  — their cardinality and unknown-flag rows already exist (bats:2042-2173,
  2261, 2337-2354); new work must not duplicate them. `h steps`'s bare-`--`
  arm gets probed first; if the probe reveals a gap, the fix lands in this PR.
- `shv` characterization rows stay as-is — they are the rewrite's regression
  gate — PLUS new rows for the spellings the shared parser would silently
  consume or flip: `shv -q`, `shv -fq` (combined short), `shv 3 -q`
  (post-positional, exit 1 → 2), and `shv --browse-root 3`.

Docs (`git-config/lib/python/articles/pathspec.md`):

- Matrix row for `fcat`: `✅ (the <N|commit> target; takes exactly ONE path —
  from either side of the separator; two paths exit 2) | — | picker (scoped)`.
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
4. All existing fcat/shv characterization behavior preserved except the two
   fcat `--partial`/message flips and shv's post-positional-flag convergence
   (`shv 3 -q` exit 1 → 2, new row); `shv -q`/`shv -fq`/`shv --browse-root 3`
   keep dying loudly (new rows); full `make test` green. Every §1a
   shape×outcome row has a matching conformance row, and the scoped-picker row
   asserts the forwarded picker opts (stubbed) contain the pathspec.
5. `hug help :pathspec` matrix has rows for `fcat` and `shv`; the single-file
   list is corrected.
6. Master-roster orphan check passes with `fcat`, `stats file`, `h steps`
   enrolled.
