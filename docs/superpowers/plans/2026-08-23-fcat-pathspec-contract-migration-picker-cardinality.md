# fcat Pathspec Contract Migration + shv Parser Unification — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close [elifarley/hug-scm#311](https://github.com/elifarley/hug-scm/issues/311) — migrate `fcat` onto the uniform pathspec contract (picker, exactly-one cardinality, exit-2 flag-naming), rewrite `shv` onto the shared parser behavior-preservingly, enroll everything in the conformance suite, and fix the `:pathspec` help matrix.

**Architecture:** `git-fcat` replaces its hand-rolled positional collector with `parse_common_flags_with_pathspecs --picker` plus an 8-step order of operations (spec §1, sink table normative). `git-shv` replaces its hand-rolled `--` split with the shared parser behind a `reject_flag_ref`-routed flag-classification guard. Suite gains a `PATHSPEC_TARGETPLUSFILE_ROWS` roster class, two flipped rows, and new discriminating rows. Spec: `docs/superpowers/specs/2026-08-23-fcat-pathspec-contract-migration-picker-cardinality-design.md` (authoritative — read the §1a shape×outcome table and the sink table before starting).

**Tech Stack:** Bash (GNU getopt via `hug-cli-flags`), BATS test suite, Makefile targets.

**Worktree:** `~/src/hug-scm.WT.311-fcat-pathspec-contract-migration-picker-cardinality` — ALL work happens there.

---

### Task 1: fcat contract migration (rows first, then the parser)

**Goal:** `hug fcat` satisfies every row of the spec's §1a shape×outcome table.

**Files:**
- Modify: `git-config/bin/git-fcat` (replace lines 66–122, the parse/collect/guard section; keep `show_help`, repo check placement, resolution core)
- Modify: `tests/unit/test_pathspec_conformance.bats:2506-2521` (two flips)
- Test: new `@test` blocks appended after the existing fcat section (ends at bats:2523)

**Acceptance Criteria:**
- [ ] `fcat 3 --` with no gum → `File argument required` exit 1 (never `Missing arguments`)
- [ ] `fcat 3 a.py b.py` and `fcat 1 a.py b.py` → exit 2, `hug fcat accepts only one file`
- [ ] `fcat -xX src/a.py` → exit 2, `Unknown option: -xX. Pathspecs beginning with '-' require '--'`
- [ ] `fcat -3 <path>` → unchanged range-unsupported text, exit 1
- [ ] `fcat HEAD:src/a.py` → exit 1, `File argument required` (flipped partial)
- [ ] `fcat 3 a.py --` with stubbed gum → picker receives `a.py` as scope (asserted via argv recording)
- [ ] `fcat` bare / `fcat <N>` target-only / `fcat 3 -- ''` / `fcat 3 -- -q` rows all pass per §1a
- [ ] Legacy `fcat HEAD src/a.py` and `fcat HEAD -- src/a.py` rows still pass byte-for-byte

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER=fcat` → all green

**Steps:**

- [ ] **Step 1: Flip the two existing rows** (bats:2506-2521). Colon row: replace `assert_output --partial "Missing arguments"` with `assert_output --partial "File argument required"`; rename the test to drop "characterization" (suite convention: flipped rows become contract rows). `-xX` row: replace `assert_output --partial "Unable to resolve reference '-xX'"` with `assert_output --partial "Unknown option: -xX"` and update its comment (the recorded flip target is now delivered).

- [ ] **Step 2: Add the new rows.** Model: existing fcat rows use `psx_setup` / `run hug fcat …` / `psx_reset` and a fixture where `src/a.py` contains `py1` at HEAD~1 (copy the `psx_setup` fixture contract from bats:2488-2504). New blocks:

```bash
@test "contract fcat: bare and target-only → loud usage errors" {
  psx_setup
  run hug fcat
  assert_failure; assert_output --partial "Missing target"
  run hug fcat 3
  assert_failure; assert_output --partial "File argument required"
  run hug fcat --
  assert_failure; assert_output --partial "Missing target"
  psx_reset
}

@test "contract fcat: cardinality — two candidates exit 2, either side of '--'" {
  psx_setup
  run hug fcat 1 src/a.py src_b.py
  assert_failure; assert_output --partial "accepts only one file"
  run hug fcat 1 -- src/a.py src_b.py
  assert_failure; assert_output --partial "accepts only one file"
  psx_reset
}

@test "contract fcat: picker arm — no gum → clean error; empty arg → file required" {
  psx_setup
  command -v gum >/dev/null && skip "deterministic only without gum"
  run hug fcat 3 --
  assert_failure; assert_output --partial "File argument required"
  run hug fcat 3 -- ''
  assert_failure; assert_output --partial "File argument required"
  psx_reset
}

@test "contract fcat: range rejection unchanged; post-'--' flag spelling exits 2" {
  psx_setup
  run hug fcat -3 src/a.py
  assert_failure; assert_output --partial "Ranges are not supported"
  run hug fcat 3 -- -q
  assert_failure; assert_output --partial "Flags must precede '--'"
  psx_reset
}

@test "contract fcat: quoted glob stays literal; --browse-root compositions" {
  psx_setup
  run hug fcat 1 -- 'src/*.py'
  assert_failure; assert_output --partial "does not exist"
  run hug fcat --browse-root 3
  assert_failure   # parse_common_flags explicit-paths error, exit 1
  run hug fcat --browse-root
  assert_failure; assert_output --partial "Missing target"
  run hug fcat --browse-root --
  assert_failure; assert_output --partial "Missing target"
  psx_reset
}

@test "contract fcat: 'fcat <N> <path> --' scopes the picker to the path" {
  psx_setup
  # Fake gum: records argv, "selects" src/a.py. Reuse the suite's existing
  # gum-stub technique if one exists (grep 'stub' near the `a` selection test);
  # otherwise this PATH-shim is the pattern.
  stub_bin="$PSX_TMP/bin"; mkdir -p "$stub_bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "$GUM_ARGV_FILE"\necho src/a.py\n' \
    > "$stub_bin/gum" && chmod +x "$stub_bin/gum"
  GUM_ARGV_FILE="$PSX_TMP/gum.argv" PATH="$stub_bin:$PATH" \
    run hug fcat 1 src/a.py --
  assert_success
  assert_output "py1"
  grep -q 'src/a.py' "$PSX_TMP/gum.argv"   # the picker SAW the scope
  psx_reset
}
```

- [ ] **Step 3: Run to red.** `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER=fcat` → new rows fail, two flipped rows fail.

- [ ] **Step 4: Implement.** Replace `git-fcat` lines 66–122 (from `# Parse common flags` through `file_path="${args[1]}"` and the old range guard — keep the resolution block from `# Resolve the target commit` down) with:

```bash
# ── Uniform pathspec contract (#311) — spec §1 steps 1-8; the sink table in
# the spec is normative for who-writes/who-reads each representation. ──
# Step 1: an inherited export must not fire the picker (parse_common_flags'
# --browse-root arm exports the same variable, hug-cli-flags:278-279).
unset HUG_INTERACTIVE_FILE_SELECTION

# Step 2: ONE eval — strips the trailing bare '--' (hug-cli-flags:366-370),
# splits at the first '--', consumes common flags; "$@" becomes the
# separator-free pre-args.
eval "$(parse_common_flags_with_pathspecs --picker "$@")"

check_git_repo

# Step 3: range check reads pre-args[0] DIRECTLY, before the helper's arm 2 —
# else `fcat -3 <path>` flips to the generic unknown-option exit 2 instead of
# this dedicated message (the `sh` DATA-arm pattern, git-sh:121-126).
if [[ "${1:-}" =~ ^-[0-9]+$ ]]; then
  error "Ranges are not supported. Use a single commit ref.
  hug fcat <commit> <path>   View file at specific commit
  hug fcat <N> <path>        View file N changes back (single commit)"
fi

# Step 4: LOUD unknown dash-tokens (any pre-args position, incl. the target
# slot) + post-'--' exact-spelling rejection — the git-w-discard:100 pattern.
# The helper completes its own array (arm 3 reads it for `fcat 3 -- -q`);
# fcat's cardinality does NOT use it (the target would be miscounted).
pathspec_pathspecs_into _fcat_guard
parse_scoped_own_flags "hug fcat" "" _fcat_guard "$@"

# Step 5: target + candidates from the UNTOUCHED "$@" ∪ pathspecs.
if [[ $# -eq 0 ]]; then
  error "Missing target. USAGE: hug fcat <N|commit> <path>

ARGUMENTS:
    <N|commit>    Number (0-99) or commit reference
    <path>        File path to view

Run 'hug help fcat' for details."
fi
target="$1"
candidates=("${@:2}" ${_pathspec_pathspecs[@]+"${_pathspec_pathspecs[@]}"})

# Step 6: materialize the union so forward_pathspecs_to_picker (which reads
# ONLY _pathspec_pathspecs, hug-cli-flags:437-446) sees pre-args-side
# candidates: `fcat 3 a.py --` must scope the picker to a.py, never open it
# cwd-wide (silent scope-widen; CI without gum cannot tell the difference).
_pathspec_pathspecs=(${candidates[@]+"${candidates[@]}"})

# Step 7: cardinality — exactly one file candidate in total, from either side
# of the separator. reject_multiple_files ignores empty strings, so
# `fcat 3 -- ''` falls through to the 0-candidates arm in step 8.
if [[ ${#candidates[@]} -gt 1 ]]; then
  reject_multiple_files "hug fcat" ${candidates[@]+"${candidates[@]}"}
fi

# Step 8: picker on the parse-local export; pick-file-FIRST, then resolve the
# target (N counts file-specific commits — the chicken-and-egg this ordering
# solves). Cancel → info + exit 0 (stats-file precedent). cwd-scoped only;
# --browse-root has no reachable composition (spec Vestigial note).
file_path=""
if [[ "${HUG_INTERACTIVE_FILE_SELECTION:-}" = "true" ]] && gum_available; then
  declare -a select_opts=("--single" "--cwd" "--prompt" "Select file to view...")
  forward_pathspecs_to_picker select_opts
  if ! file_path=$(select_files_with_status "${select_opts[@]}"); then
    info "No file selected or cancelled."
    exit 0
  fi
elif [[ ${#candidates[@]} -eq 1 && -n "${candidates[0]}" ]]; then
  file_path="${candidates[0]}"
else
  error "File argument required.
Usage: hug fcat <N|commit> <path>"
fi
```

Keep the existing resolution block unchanged below it (`get_commit_n_back` / `ensure_commit_exists` / `check_file_in_commit` / `git show`). Update `show_help`: USAGE gains `hug fcat <N|commit> --` (interactive selection) and the `-- <path>` separator form; SEE ALSO gains `hug help :pathspec`.

- [ ] **Step 5: Run to green:** `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER=fcat`
- [ ] **Step 6: Manual probe receipts** (temp repo, per the spec's Problem table): `hug fcat 3 --`, `hug fcat 1 a.py b.py`, `hug fcat -xX src/a.py` — capture output for the PR body.
- [ ] **Step 7: Commit** (skill `hug-commit`): `feat(fcat): migrate onto the uniform pathspec contract (#311)`

---

### Task 2: shv parser rewrite + flag-classification guard

**Goal:** `shv` uses the shared parser; every flag-shaped pre-`--` token dies with today's USAGE banner + exit 2; ONE deliberate change (post-positional flags converge to exit 2) pinned.

**Files:**
- Modify: `git-config/bin/git-shv:71-104` (pre-scan + hand-rolled split → guard + shared parser)
- Test: `tests/unit/test_pathspec_conformance.bats` (rows 2374-2429 must stay green; 4 new rows)

**Acceptance Criteria:**
- [ ] All existing shv characterization rows pass unchanged (incl. bats:2417 `--partial "USAGE:"`)
- [ ] `shv -q`, `shv -fq`, `shv --browse-root 3` → exit 2 with USAGE banner (new rows)
- [ ] `shv 3 -q` → exit 2 `Unknown flag: -q` (pinned flip; today exit 1 `Unexpected`)
- [ ] `shv -1234` behaves as today (range data passes the guard to the engine)

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER=shv` → all green

**Steps:**

- [ ] **Step 1: Add the new rows** after bats:2429 (same fixture/stub technique the neighboring shv rows use — they invoke `git-shv` directly with a git/difftool shim):

```bash
@test "contract shv: flag-classification guard kills silent consumption" {
  # -q alone, the -fq COMBINED short (getopt would consume both silently),
  # and a flag AFTER the positional (the one deliberate flip: exit 1 → 2).
  psx_setup
  run hug shv -q
  assert_failure; assert_output --partial "USAGE:"; assert_output --partial "Unknown flag: -q"
  run hug shv -fq
  assert_failure; assert_output --partial "Unknown flag: -fq"
  run hug shv 3 -q
  assert_failure; assert_output --partial "Unknown flag: -q"
  run hug shv -1234
  assert_failure   # range data reaches the engine, dies there as today
  psx_reset
}
```

(If the fixture's difftool shim makes `shv -1234` exit differently than today's run, match today's observed rc — the AC is "as today", verified by running both.)

- [ ] **Step 2: Run to red.**
- [ ] **Step 3: Implement.** Replace `git-shv` lines 71-104 (the `-h` pre-scan `for` loop and the hand-rolled split loop) with:

```bash
# Flag-classification guard (#311 spec §2): shv has NO legal flags before
# '--'. GNU getopt (inside parse_common_flags) would CONSUME -q/-f/-y/
# --dry-run/--browse-root — and combined shorts like -fq (mechanically
# verified: getopt emits ' -f -q --' rc=0) — then silently launch a
# difftool on HEAD. Routing through reject_flag_ref preserves today's
# exact behavior: help banner FIRST, then `Unknown flag: <tok>` exit 2
# (the characterization row asserts the USAGE banner). reject_flag_ref
# already exempts -N ranges at ANY length (^-[0-9]+$), so -1234 passes;
# only -h/--help need our own exemption (the eval handles them).
for _arg in "$@"; do
  [[ "$_arg" == "--" ]] && break
  case "$_arg" in
  -h | --help) ;;
  *) reject_flag_ref "$_arg" ;;
  esac
done
unset _arg

# Split via the shared parser (no --picker: shv launches a difftool, not a
# file picker). "$@" becomes the separator-free pre-args. Family tradeoff
# (ratified #292, reservation 1): a trailing bare '--' is stripped, so a
# pathspec literally named '--' is dropped — same as every family member.
eval "$(parse_common_flags_with_pathspecs "$@")"

if [[ $# -gt 1 ]]; then
  # shv shows ONE commit/range — a second bare token is a usage error.
  error "hug shv takes a single commit/range, then optional '-- <path>...'. Unexpected: '$2'"
fi
token="${1:-HEAD}"
```

Keep everything from the `s|u|w` redirect `case` through the `dd_commit_diff` delegation exactly as is, but source the pathspecs via the accessor before delegating:

```bash
pathspec_pathspecs_into pathspecs
if [[ ${#pathspecs[@]} -gt 0 ]]; then
  dd_commit_diff "$token" -- "${pathspecs[@]}"
else
  dd_commit_diff "$token"
fi
```

- [ ] **Step 4: Run to green**, then `make test-unit TEST_FILTER="shv"` for the sibling suites (`test_shv.bats` invokes the script directly — it must stay green too).
- [ ] **Step 5: Commit:** `refactor(shv): rewrite onto the shared pathspec parser behind a flag-classification guard (#311)`

---

### Task 3: stats file + h steps bare-`--` picker rows

**Goal:** The only genuinely missing pins for the two multi-word single-file commands — their bare-`--` picker arm — are locked in.

**Files:**
- Test: `tests/unit/test_pathspec_conformance.bats` (append near the stats-file rows at 2337-2354)
- Modify (only if the probe finds a gap): `git-config/bin/git-h-steps`

**Acceptance Criteria:**
- [ ] `stats file --` with no gum → clean `File argument required` error (row; behavior already fixed in #310)
- [ ] `h steps --` probed; row pins whatever conformant shape ships (fix lands in this task if the probe shows a gap)

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER="stats file"` and `TEST_FILTER="h steps"` → green

**Steps:**

- [ ] **Step 1: Probe** in a temp repo: `hug stats file --` and `hug h steps --` (no gum) plus with the fake-gum shim from Task 1. Record outcomes.
- [ ] **Step 2: Add rows** (skip-without-gum pattern from Task 1; if `h steps --` misbehaves, migrate its parser arm minimally — same steps 1-8 shape, own flags preserved — before pinning):

```bash
@test "contract stats file: bare '--' routes to the picker (no gum → clean error)" {
  psx_setup
  command -v gum >/dev/null && skip "deterministic only without gum"
  run hug stats file --
  assert_failure; assert_output --partial "File argument required"
  psx_reset
}

@test "contract h steps: bare '--' routes to the picker" {
  psx_setup
  command -v gum >/dev/null && skip "deterministic only without gum"
  run hug h steps --
  assert_failure; assert_output --partial "File argument required"   # adjust to probe outcome
  psx_reset
}
```

- [ ] **Step 3: Run to green; commit:** `test(pathspec): pin the bare-'--' picker arm for stats file and h steps (#311)`

---

### Task 4: roster enrollment + help-matrix rows

**Goal:** The suite's membership machinery owns `fcat`; `hug help :pathspec` tells the truth.

**Files:**
- Modify: `tests/unit/test_pathspec_conformance.bats` (roster block ~37-146, master literal ~140-146)
- Modify: `git-config/lib/python/articles/pathspec.md` (matrix after line 195, single-file sentence 197-198)

**Acceptance Criteria:**
- [ ] `PATHSPEC_TARGETPLUSFILE_ROWS=(fcat)` exists and is consumed by ≥1 column loop; master-roster orphan check (bats:3233) green
- [ ] Matrix rows for `fcat` and `shv` present; single-file sentence annotated (`stats file`, `h steps` — exit-2 cardinality), `fcat` correctly absent
- [ ] `make test-unit TEST_FILE=test_pathspec_conformance.bats` fully green

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats` → green, incl. `PR-C master roster` row

**Steps:**

- [ ] **Step 1:** Add `PATHSPEC_TARGETPLUSFILE_ROWS=(fcat)` next to `PATHSPEC_SINGLEFILE_ROWS` (bats:128), with a comment naming the class (two-positional: target + exactly-one path, picker arm). Wire it into the column loops the way `PATHSPEC_SINGLEFILE_ROWS` is consumed (find its consumer loop by grepping the array name; add a matching loop or cell for the new class — the picker-arm and cardinality cells are the discriminating ones). Add `fcat` to the hand-written master literal (bats:140-146) so the orphan check covers it.

- [ ] **Step 2:** In `pathspec.md`, add after the `w-wip` row (line 195):

```markdown
| `fcat` | ✅ (the `<N\|commit>` target; takes exactly ONE path — from either side of the separator; two paths exit 2) | — | picker (scoped) |
| `shv` | ✅ (single commit/range token + scoped paths; `-N` is DATA) | — | inert |
```

Annotate the single-file sentence (197-198): note `stats file` / `h steps` reject extra files with exit 2 and route a bare `--` to the picker. Add `fcat`'s flip to the "Breaking changes" list (item 17: `hug fcat` picker + exit-2 cardinality/flag-naming — was silent first-wins / ref-error).

- [ ] **Step 3:** Verify article renders (it is data for `hug help :pathspec`): `hug help :pathspec | grep -c fcat` → ≥1.
- [ ] **Step 4: Commit:** `docs(pathspec): enroll fcat in the conformance rosters; add fcat/shv matrix rows (#311)`

---

### Task 5: full-suite gate + PR receipts

**Goal:** Everything green; before/after receipts captured for the PR body.

**Files:** none (validation only; receipts go in the PR body)

**Acceptance Criteria:**
- [ ] `make sanitize` clean
- [ ] `make test` fully green
- [ ] Spec §1a table: every row has a matching conformance row (spot-check list against the suite)
- [ ] Probe receipts (Task 1 Step 6 + today's Problem-table probes) written into the PR body

**Verify:** `make test` → `✓ All tests passed!`

**Steps:**

- [ ] **Step 1:** `make sanitize` (fix anything it reformats; fold into the offending task's commit via `hug cmod --no-edit` only if that task is HEAD, else a fixup commit).
- [ ] **Step 2:** `make test` (full gate; ~20 min — run in background and wait).
- [ ] **Step 3:** Cross-check §1a coverage; capture receipts; hand to the PR flow.
