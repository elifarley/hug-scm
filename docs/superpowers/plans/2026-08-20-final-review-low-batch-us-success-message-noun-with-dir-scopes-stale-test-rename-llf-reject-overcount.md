# #302 Final-Review LOW Batch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the three remaining LOW findings from the final review of PR elifarley/hug-scm#299 plus the F-005 spelling convention: (1) `hug us` success/dry-run summaries name the scope when pathspecs are scope-shaped; (2) rename one confirmed stale conformance test; (3) `reject_multiple_files` gains a truthful count and the three overcount call sites (`llf`, `stats-file`, `h-steps`) pass files-only collections.

**Architecture:** Argument-surgery only — no new git calls, no new processes, no new error paths. Finding 3 rests on one new shared slice helper (`collect_positional_args_before_flags`) that becomes the single engine for the cut rule (`count` delegates to it); the three call sites adopt it (or, for h-steps, an inline post-loop tally-filter because `--raw` legitimately follows the file). Finding 1 rests on one local classifier function (`is_scope_shaped`) shared by the existing error-path noun and the new success/dry-run clause, both reading the converged `pathspecs` array. Every change is mutation-testable by construction.

**Tech Stack:** Bash (git-config/bin + git-config/lib), BATS (tests/unit + tests/lib), GNU getopt (existing). Mercurial parity (`hg-config`) is unaffected — the changed commands are Git-only.

**Spec:** `docs/superpowers/specs/2026-08-20-final-review-low-batch-us-success-message-noun-with-dir-scopes-stale-test-rename-llf-reject-overcount-design.md` (committed `025f2e27`, roast round 1 applied `e2682f34`).

**Commit note:** the spec said "three implementation commits" (one per finding) as an approximation; this plan refines to seven atomic TDD commits. Two of the six existing `accepts only one file.` pins are the overcount shape (conformance:1949 is `hug llf … -1`, a trailing-flag shape) and flip with their call-site fix, not the message commit — the plan keeps every commit green.

---

## File Structure

| File | Responsibility | Touched by |
|---|---|---|
| `git-config/lib/hug-cli-flags` | add `collect_positional_args_before_flags`; reimplement `count_positional_args_before_flags` via it; `reject_multiple_files` message + docstring | T1, T2 |
| `git-config/bin/git-llf` | adopt the slice; delete the stale "tally only triggers" caveat | T2 |
| `git-config/bin/git-stats-file` | adopt the slice over `remaining_args`; delete the twin caveat comment | T3 |
| `git-config/bin/git-h-steps` | post-loop tally-filter (exclude `-*` from reject input) | T4 |
| `git-config/bin/git-us` | add `is_scope_shaped`; refactor the noun loop to use it; build `scope_clause`; append to success + dry-run | T5 |
| `tests/lib/test_hug-cli-flags.bats` | lib tests for `collect`; `count`↔`collect` parity; `reject_multiple_files` counted-message; flip pin :661 | T1, T2 |
| `tests/unit/test_pathspec_conformance.bats` | flip pins :1911/:1949/:1980/:1990/:2002 + prose :118; add llf/stats-file/h-steps proof rows; add us clause pins (incl. F-005 subdir); rename :797 | T2,T3,T4,T5,T6 |
| `CHANGELOG.md` | new entry under the message fix | T7 |

---

## Task 1: `collect_positional_args_before_flags` helper + `count` reimplementation

**Goal:** Add the single-engine slice helper and reimplement `count` as collect-then-count, with lib tests proving parity — no command behavior changes yet.

**Files:**
- Modify: `git-config/lib/hug-cli-flags` (after the existing `count_positional_args_before_flags` at :495-504)
- Test: `tests/lib/test_hug-cli-flags.bats`

**Acceptance Criteria:**
- [ ] `collect_positional_args_before_flags <out> [args…]` collects leading non-`-*` tokens into the nameref array, cutting at the first flag (including `--`, which matches `-*`)
- [ ] `count_positional_args_before_flags` is reimplemented as `collect` + `${#arr[@]}`; its five existing lib tests still pass (behavior-identical)
- [ ] new lib tests: flag cut, `--` cut, empty input, dash token after a flag is NOT collected, `count`↔`collect` parity
- [ ] `make test-lib TEST_FILE=test_hug-cli-flags.bats` green

**Verify:** `make test-lib TEST_FILE=test_hug-cli-flags.bats` → all green, including the new collect/parity tests.

**Steps:**

- [ ] **Step 1: Write the failing lib tests** (append to `tests/lib/test_hug-cli-flags.bats`):

```bash
@test "collect_positional_args_before_flags: collects leading positionals, cuts at first flag" {
  local -a out=()
  collect_positional_args_before_flags out a b -1 c
  [[ "${#out[@]}" -eq 2 && "${out[0]}" == a && "${out[1]}" == b ]]
}

@test "collect_positional_args_before_flags: '--' ends the count (it matches -*)" {
  local -a out=()
  collect_positional_args_before_flags out a -- b
  [[ "${#out[@]}" -eq 1 && "${out[0]}" == a ]]
}

@test "collect_positional_args_before_flags: empty input yields empty array" {
  local -a out=()
  collect_positional_args_before_flags out
  [[ ${#out[@]} -eq 0 ]]
}

@test "collect_positional_args_before_flags: dash token after a flag is NOT collected" {
  local -a out=()
  collect_positional_args_before_flags out a -x --bogus c
  [[ "${#out[@]}" -eq 1 && "${out[0]}" == a ]]
}

@test "count_positional_args_before_flags: parity with collect length" {
  local -a c=()
  collect_positional_args_before_flags c a b -1
  [[ "$(count_positional_args_before_flags a b -1)" -eq "${#c[@]}" ]]
}
```

- [ ] **Step 2: Run to verify red** — `make test-lib TEST_FILE=test_hug-cli-flags.bats` → FAIL (`collect_positional_args_before_flags: command not found`).

- [ ] **Step 3: Add the helper and reimplement count** in `git-config/lib/hug-cli-flags`, replacing the body of `count_positional_args_before_flags` (lines 495-504) and inserting the new function just above it:

```bash
# Collect LEADING positional arguments into a nameref array, stopping at the
# first flag-looking token ('--' included — it matches -*). Single engine for
# the cut rule (#302): count_positional_args_before_flags delegates here so the
# classification lives in one place (the #298 extraction's whole point).
# Reserved prefix __cpaf_ — nameref collision guard (Bash >= 4.3 floor, same
# discipline as drain_pathspecs_after_separator's __dps_).
#
# Usage: collect_positional_args_before_flags <out-array-name> [args...]
collect_positional_args_before_flags() {
  local -n __cpaf_out="$1"
  shift
  __cpaf_out=()
  local arg
  for arg in "$@"; do
    case "$arg" in
    -*) break ;;
    *) __cpaf_out+=("$arg") ;;
    esac
  done
}

# Count LEADING positional arguments only — now a thin wrapper over
# collect_positional_args_before_flags (single cut-rule engine, #302).
# Pure computation: no git, no exit on any input. Callers capture via $(...).
count_positional_args_before_flags() {
  local -a __cpaf_count=()
  collect_positional_args_before_flags __cpaf_count "$@"
  printf '%s\n' "${#__cpaf_count[@]}"
}
```

- [ ] **Step 4: Run to verify green** — `make test-lib TEST_FILE=test_hug-cli-flags.bats` → all green (new tests + the five pre-existing count tests).

- [ ] **Step 5: Commit** — `hug a git-config/lib/hug-cli-flags tests/lib/test_hug-cli-flags.bats && hug c -m "feat(cli-flags): collect_positional_args_before_flags — single-engine slice helper; count delegates to it (#302)"`

---

## Task 2: `reject_multiple_files` truthful count + `llf` slice adoption + pin flips

**Goal:** Make the overcount observable and fix the `llf` site in one commit (the message change would otherwise expose `llf`'s latent overcount as a false `(got 3 files)`). Flip the five no-flag pins to `(got 2 files)` and the llf trailing-flag pin :1949 to `(got 2 files)` post-fix; add the llf proof row.

**Why one commit:** the message change and the `llf` fix must land together — `hug llf src/a.py docs/note.md -1` is both a flipped pin (:1949) and the overcount shape; flipping it to `(got 2 files)` is only true after the `llf` slice. Splitting them leaves a red test between commits.

**Files:**
- Modify: `git-config/lib/hug-cli-flags` (`reject_multiple_files` message :531 + docstring)
- Modify: `git-config/bin/git-llf` (gate :69-71 + delete the "tally only triggers" caveat comment)
- Modify: `tests/lib/test_hug-cli-flags.bats:661`, `tests/unit/test_pathspec_conformance.bats:118,1911,1949,1980,1990,2002`

**Acceptance Criteria:**
- [ ] `reject_multiple_files` prints `${cmd_name} accepts only one file (got ${#files[@]} files).`; docstring states callers must pass FILE arguments only, never flags
- [ ] `git-llf` rejects with a files-only collection: `hug llf src/a.py docs/note.md -1` → exit 2, `(got 2 files)` (the -1 flag no longer counted)
- [ ] the llf "tally only triggers" caveat comment is deleted (gate and tally are the same collection now)
- [ ] six pin assertions flip to the counted form; conformance:118 prose flips
- [ ] `make test-lib TEST_FILE=test_hug-cli-flags.bats` and `make test-unit TEST_FILE=test_pathspec_conformance.bats` green

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER="single-file cardinality"` → green; `make test-lib TEST_FILE=test_hug-cli-flags.bats` → green.

**Steps:**

- [ ] **Step 1: Write the llf proof row (red first)** — append to the `single-file cardinality` section in `tests/unit/test_pathspec_conformance.bats`:

```bash
@test "single-file cardinality: llf trailing flag not counted in the reject tally (Task 10/#302)" {
  # #302 overcount: 'hug llf a b -1' used to pass "$file" "$@" to
  # reject_multiple_files, tallying the -1 flag as a 3rd "file". The slice
  # (collect_positional_args_before_flags) makes the tally files-only.
  psx_setup
  run hug llf src/a.py docs/note.md -1
  assert_equal 2 "$status"
  assert_output --partial "hug llf accepts only one file (got 2 files)."
  refute_output --partial "got 3 files"
  psx_reset
}
```

- [ ] **Step 2: Run red** — `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER="trailing flag not counted"` → FAIL (current message has no count).

- [ ] **Step 3: Change the helper message + docstring** in `git-config/lib/hug-cli-flags`. In `reject_multiple_files` (around :526-533), change the `error_usage` line and the docstring:

```bash
# Cardinality guard for single-file commands (spec §3.2 / §5.6 of the
# pathspec-contract design). Rejects more than one file argument with a
# clear, command-naming error instead of git's raw fatals or silent ignores.
#
# Usage: reject_multiple_files "<cmd-name>" [file...]
# Parameters:
#   $1 - Command name for the error message (e.g. "hug fa")
#   $@ - Remaining args are the candidate FILE arguments
# Caller contract (#302): pass candidate FILE arguments ONLY, never flags.
# The truthful "(got N files)" count is only correct for file-only collections
# — see git-llf/git-stats-file/git-h-steps, which slice/filter before calling.
# Note:
#   Empty-string arguments are ignored (not counted as files), so callers
#   can pass through optional-position variables without pre-filtering.
# Effects:
#   Exits with error if more than one non-empty file argument is given
reject_multiple_files() {
  local cmd_name="$1"; shift
  local -a files=()
  local f
  for f in "$@"; do
    [[ -n "$f" ]] && files+=("$f")
  done
  if [[ ${#files[@]} -gt 1 ]]; then
    # error_usage (exit 2, code-roast alignment): a cardinality violation
    # is a USAGE error — the migrated pathspec family rejects unknown
    # options with the same code; exit 1 made scripts unable to
    # distinguish "bad invocation" from "command failed". The truthful
    # count (#302) makes the overcount class observable/mutation-testable.
    error_usage "${cmd_name} accepts only one file (got ${#files[@]} files)."
  fi
}
```

- [ ] **Step 4: Adopt the slice in `git-llf`** — replace the gate block at `git-config/bin/git-llf:63-71`:

```bash
file="$1"
shift

# Cardinality guard (pathspec contract §3.2): llf logs ONE file; flags may
# legitimately follow it. Collect ONLY the leading positional args (the slice
# — count_positional_args_before_flags' single-engine companion, #302) so the
# reject tally counts files, never trailing flags like '-1' (the #302
# overcount: 'hug llf a b -1' used to pass "$file" "$@" and tally the -1 as a
# 3rd "file"). Gate is -ge 1 because $file was already shifted out of "$@".
# The GATE is authoritative; reject_multiple_files' tally now feeds it the
# SAME files-only collection.
extra_files=()
collect_positional_args_before_flags extra_files "$@"
if [ ${#extra_files[@]} -ge 1 ]; then
  reject_multiple_files "hug llf" "$file" ${extra_files[@]+"${extra_files[@]}"}
fi

exec hug ll "$@" --follow -- "$file"
```

Delete the old comment block that began `# Cardinality guard ... The GATE is authoritative; reject_multiple_files' tally only triggers the same message — do not "simplify" the gate away (#292/#298).` and the old `[ "$(count_positional_args_before_flags "$@")" -ge 1 ]` line + the `reject_multiple_files "hug llf" "$file" "$@"` line.

- [ ] **Step 5: Flip the six pin assertions + prose** to the counted form. Each `assert_output --partial "hug <cmd> accepts only one file."` → `assert_output --partial "hug <cmd> accepts only one file (got 2 files)."`:
  - `tests/lib/test_hug-cli-flags.bats:661`
  - `tests/unit/test_pathspec_conformance.bats:1911` (looped: `hug $cmd src/a.py docs/note.md`)
  - `:1949` (the llf trailing-flag shape → `(got 2 files)` post-fix)
  - `:1980` (`hug h steps src/a.py docs/note.md`)
  - `:1990` (`hug stats file src/a.py docs/note.md`)
  - `:2002` (`hug fblame --churn src/a.py docs/note.md`)
  - `:118` prose comment: `"<cmd> accepts only one file."` → `"<cmd> accepts only one file (got N files)."`

- [ ] **Step 6: Run green** — `make test-unit TEST_FILE=test_pathspec_conformance.bats` and `make test-lib TEST_FILE=test_hug-cli-flags.bats` → all green (the llf proof row now passes with `(got 2 files)`; the 2-file shapes pass; the f-family shapes pass because every token is a file candidate there).

- [ ] **Step 7: Mutation receipt** — temporarily revert the llf slice to `reject_multiple_files "hug llf" "$file" "$@"`, re-run `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER="trailing flag not counted"` → the proof row prints `(got 3 files)` and fails. Restore the slice. (This is the receipt, not a commit.)

- [ ] **Step 8: Commit** — `hug a git-config/lib/hug-cli-flags git-config/bin/git-llf tests/lib/test_hug-cli-flags.bats tests/unit/test_pathspec_conformance.bats && hug c -m "feat(cli-flags,llf): reject_multiple_files gains truthful (got N files) count; llf adopts the slice (#302)"`

---

## Task 3: `stats-file` slice adoption + delete twin caveat + proof row

**Goal:** Fix the second overcount site and remove its now-false "tally only triggers" comment, with a mutation proof row.

**Files:**
- Modify: `git-config/bin/git-stats-file` (gate :131-134 + delete the twin caveat comment :127-128)
- Modify: `tests/unit/test_pathspec_conformance.bats` (new proof row near :1990)

**Acceptance Criteria:**
- [ ] `hug stats file a b --bogus` rejects with `(got 2 files)` (the `--bogus` no longer tallied)
- [ ] the "tally only triggers" twin comment at git-stats-file:127-128 is deleted
- [ ] new conformance proof row asserts `(got 2 files)`; mutation receipt: revert → `(got 3 files)` red
- [ ] `make test-unit TEST_FILE=test_pathspec_conformance.bats` green

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER="stats file"` → green including the new proof row.

**Steps:**

- [ ] **Step 1: Write the proof row (red first)** in `tests/unit/test_pathspec_conformance.bats` near the existing stats-file cardinality test:

```bash
@test "single-file cardinality: stats file trailing flag not counted (Task 10/#302)" {
  # #302 overcount: stats-file's own-loop *) arm collects unknown -* tokens
  # into remaining_args; 'hug stats file a b --bogus' tallied 3. The slice fixes it.
  psx_setup
  run hug stats file src/a.py docs/note.md --bogus
  assert_equal 2 "$status"
  assert_output --partial "hug stats file accepts only one file (got 2 files)."
  refute_output --partial "got 3 files"
  psx_reset
}
```

- [ ] **Step 2: Run red** — `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER="stats file trailing flag"` → FAIL (current `remaining_args` tally = 3 → after Task 2's message change, prints `(got 3 files)` → the `(got 2 files)` assertion fails).

- [ ] **Step 3: Adopt the slice + delete the twin comment** in `git-config/bin/git-stats-file`. Replace the gate block (around :131-134) and the preceding comment :127-128:

```bash
# Cardinality guard (pathspec contract §3.2): stats file analyzes ONE file
# — `hug stats file a b` used to churn-analyze ONLY a and silently drop the
# extras. First flag ends the count, WHY in collect_positional_args_before_flags
# (the single-engine slice, #302). Gate is -gt 1 (not -ge 1) because this
# command's file is still INSIDE the collected args, unlike llf where it was
# shifted out. The slice also drops unknown -* tokens (e.g. --bogus) so they
# no longer inflate the tally (the #302 overcount: 'hug stats file a b
# --bogus' tallied 3). The GATE is authoritative; reject_multiple_files'
# tally now feeds it the SAME files-only collection.
# ${file_args[@]+...} nullsafe expansion (Bash 4.3 set -u crash mode).
file_args=()
collect_positional_args_before_flags file_args ${remaining_args[@]+"${remaining_args[@]}"}
if [ ${#file_args[@]} -gt 1 ]; then
  reject_multiple_files "hug stats file" ${file_args[@]+"${file_args[@]}"}
fi
```

Delete the old `# The GATE is authoritative; reject_multiple_files' tally only triggers the same message — do not "simplify" the gate away (#292/#298).` comment and the old `[ "$(count_positional_args_before_flags ...)" -gt 1 ]` + `reject_multiple_files "hug stats file" ${remaining_args[@]+...}` lines.

- [ ] **Step 4: Run green** — `make test-unit TEST_FILE=test_pathspec_conformance.bats` → green.

- [ ] **Step 5: Mutation receipt** — revert to `reject_multiple_files "hug stats file" ${remaining_args[@]+"${remaining_args[@]}"}`, re-run the proof row → `(got 3 files)` red. Restore.

- [ ] **Step 6: Commit** — `hug a git-config/bin/git-stats-file tests/unit/test_pathspec_conformance.bats && hug c -m "fix(stats-file): adopt the slice; drop unknown flags from the reject tally; delete stale twin caveat (#302)"`

---

## Task 4: `h-steps` tally-filter + proof row

**Goal:** Fix the third overcount site (the one the original spec audit wrongly marked "correct"). Use a post-loop tally-filter — NOT the pre-loop slice — because `--raw` legitimately follows the file (`hug h steps README.md --raw`, help:44) and is consumed by the own-loop first.

**Files:**
- Modify: `git-config/bin/git-h-steps` (reject at :86)
- Modify: `tests/unit/test_pathspec_conformance.bats` (new proof row near :1980)

**Acceptance Criteria:**
- [ ] `hug h steps src/a.py --bogus` fails loud `Unknown option: --bogus. See 'hug help :pathspec'.` (exit 2) — pre-fix it was counted as a file and falsely hit the cardinality guard; filtering it from the tally alone would have silently analyzed `src/a.py` and masked the typo; the path-command contract (codex review #3829676849) requires unknown `-*` after the file to be loud, not silently skipped.
- [ ] `hug h steps src/a.py docs/note.md` still rejects with `accepts only one file (got 2 files)` (the ordinary two-files case, unchanged)
- [ ] `hug h steps README.md --raw` still works (`--raw` consumed by its own arm before any guard, not flagged)
- [ ] new conformance proof row asserts the loud unknown-flag path, not silent success; mutation receipt: drop the guard → silent success returns red
- [ ] `make test-unit TEST_FILE=test_pathspec_conformance.bats` green

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER="h steps"` → green including the new proof row.

**Steps:**

- [ ] **Step 1: Write the proof row (red first)** in `tests/unit/test_pathspec_conformance.bats`:

```bash
@test "single-file cardinality: h steps trailing unknown flag is a loud error, not a false single-file count (#302)" {
  # #302 C-004, codex #3829676849: h-steps's own-loop *) arm collects unknown
  # -* tokens into extra_files (parse_common_flags passes them through), so
  # 'hug h steps a --bogus' used to miscount the flag as a file and fire the
  # cardinality guard. Filtering it from the tally alone would have converted a
  # typo into silent success. The fix is loud: unknown -* after the file is a
  # usage error (path-command contract, exit 2). --raw is consumed by its own
  # arm and is exempted.
  psx_setup
  run hug h steps src/a.py --bogus
  assert_equal 2 "$status"
  assert_output --partial "Unknown option: --bogus"
  refute_output --partial "accepts only one file"
  psx_reset
}
```

- [ ] **Step 2: Run red** — `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER="h steps trailing flag"` → FAIL (current code either falsely rejects with `accepts only one file` or — after a tally-filter-only fix — would silently succeed; the new proof expects exit 2 `Unknown option`).

- [ ] **Step 3: Make h-steps loud on unknown flags, correct the tally** in `git-config/bin/git-h-steps`. Two guards, order matters — `--raw` is already consumed above, so only unknown flags remain. The loud check must NOT fire on a dash-leading file that was protected by `--` (`hug h steps -- -foo.txt`, codex #3830105470): the fix therefore detects whether `parse_common_flags` saw a `--` separator before the file and exempts that single file when present. Since `parse_common_flags "$@"` handles ` --` internally but `git-h-steps` currently calls it as `parse_common_flags "$@"` (no split helper), the simplest path that preserves `--` visibility is to switch to `parse_common_flags_with_pathspecs "$@"` for the split and read the separator flag from the shared `_pathspec_pathspecs` state (or capture a local `saw_separator` before the common-flag parse). If `saw_separator` is set and `file` is that first pathspec, `file` is NOT an unknown flag.

```bash
# Cardinality + unknown-flag guard (#302 C-004, codex #3829676849, #3830105470):
# h-steps's own-loop *) arm collects unknown -* tokens (parse_common_flags
# passes them through) into file/extra_files, so 'hug h steps a --bogus'
# used to be miscounted as a file and fire the cardinality guard. Filtering it
# from the tally alone would have turned a typo into silent success, violating
# the path-command contract that unknown flags must fail (exit 2).
# NOT the pre-loop slice (collect_positional_args_before_flags): --raw
# legitimately follows the file ('hug h steps README.md --raw', help:44) and
# is consumed by the own-loop's --raw arm first, so the loop must run in full.
# Fix: (1) loud unknown-flag check first — EXEMPT a dash-leading file that
# arrived via -- (hug h steps -- -foo.txt creates _pathspec_pathspecs[-foo.txt]
# after parse_common_flags_with_pathspecs; the separator-protected file is not
# an "unknown option"), then (2) cardinality on files-only.
# NOTE: migrate git-h-steps to parse_common_flags_with_pathspecs "$@" so the
# separator is visible; file still populated by the own-loop (now over _pathspec_pre_args + _pathspec_pathspecs), but
# with a saw_separator-aware exemption in the unknown-flag loop.
for f in ${extra_files[@]+"${extra_files[@]}"}; do
  if [[ "$f" == -* ]]; then
    error_usage "Unknown option: $f. See 'hug help :pathspec'."
  fi
done
if [[ -n "${file:-}" && "$file" == -* && "${saw_separator:-false}" != true ]]; then
  error_usage "Unknown option: $file. See 'hug help :pathspec'."
fi
# Above: exempt only when the dash-leading value WAS the separator-protected single file; for the
# concrete h-steps shape, every extra_files entry is post-file and therefore never separator-protected,
# so any -* there is genuinely unknown. If the design instead keeps parse_common_flags "$@" as-is,
# preserve the separator by checking _pathspec_pathspecs: a dash-leading file that equals
# _pathspec_pathspecs[0] is pathspec data, not an option.
reject_files=()
[[ -n "${file:-}" ]] && reject_files+=("$file")
for f in ${extra_files[@]+"${extra_files[@]}"}; do
  reject_files+=("$f")
done
reject_multiple_files "hug h steps" ${reject_files[@]+"${reject_files[@]}"}
```

On a second pass, collapse the two reject_files loops (the first already rejects every `-*`, so the second need not filter) — kept expanded in the recipe so the "reject then cardinality" split is reviewable.
For the actual commit, the file-state guard below (`check_git_repo` / `[ ! -e "$file" ]`) stays untouched; unknown `-*` never reaches it. Add a conformance pin proving `hug h steps -- -foo.txt` is NOT rejected (file literally named `-foo.txt` via `--`, codex #3830105470).

- [ ] **Step 4: Run green** — `make test-unit TEST_FILE=test_pathspec_conformance.bats` → green (`hug h steps src/a.py --bogus` now loud unknown-flag exit 2; `src/a.py docs/note.md` still cardinality `(got 2 files)`; `README.md --raw` still consumed).

- [ ] **Step 5: Mutation receipt** — drop the unknown-flag loop (revert to just `reject_multiple_files "hug h steps" "$file" ${extra_files[@]+"${extra_files[@]}"}`), re-run the proof row → either false cardinality or silent success instead of loud `Unknown option` → red. Restore.

- [ ] **Step 6: Commit** — `hug a git-config/bin/git-h-steps tests/unit/test_pathspec_conformance.bats && hug c -m "fix(h-steps): loud unknown-flag rejection instead of silently filtering flags from the tally (#302 C-004)"`

---

## Task 5: `us` scope-naming clause (+ F-005 spelling)

**Goal:** `hug us` success and dry-run summaries name the full scope set (`Unstaged 2 files matching 'src/':`) when any pathspec is scope-shaped; literal-only invocations stay clause-free; root-relative spelling kept (F-005).

**Files:**
- Modify: `git-config/bin/git-us` (add `is_scope_shaped` at script scope; refactor the noun loop :485-488; build `scope_clause` after report_targets at :524; append to dry-run :528 and success :546)
- Modify: `tests/unit/test_pathspec_conformance.bats` (new clause pins near the `us (roast)` rows, incl. F-005 subdir)

**Acceptance Criteria:**
- [ ] `hug us -- src/` → `Unstaged N files matching 'src/':` (+ ✓ resolved lines)
- [ ] `hug us src/a.py` → `Unstaged 1 file:` (no clause — literal file)
- [ ] `hug us docs/note.md src/` → `Unstaged N files matching 'docs/note.md' 'src/':` (full-set rule)
- [ ] `hug us --dry-run src/` → `Dry run: Would unstage N file(s) matching 'src/':`
- [ ] `--`-invariance: `hug us -- src/` ≡ `hug us src/` (clause identical)
- [ ] F-005: from inside `src/`, `hug us -- deep/` → clause `matching 'deep/':`, ✓ lines root-relative (`✓ src/deep/z.py`)
- [ ] existing roast pin :1429 (`Unstaged 1 file`) still a substring match; new pins assert the clause
- [ ] `make test-unit TEST_FILE=test_pathspec_conformance.bats` and `make test-unit TEST_FILE=test_status_staging.bats` green

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER="us"` and `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="us"` → green.

**Steps:**

- [ ] **Step 1: Write the clause pins (red first)** in `tests/unit/test_pathspec_conformance.bats` beside the `us (roast)` rows:

```bash
@test "conformance us (#302): scope-shaped success names the full scope set" {
  psx_setup
  git add docs/note.md   # + src/a.py, src/b.py already staged via psx_setup
  run hug us -- src/
  assert_success
  assert_output --partial "matching 'src/':"
  psx_reset
}

@test "conformance us (#302): literal file keeps the bare noun (no clause)" {
  psx_setup
  run hug us -- src/a.py
  assert_success
  assert_output --partial "Unstaged 1 file:"
  refute_output --partial "matching"
  psx_reset
}

@test "conformance us (#302): mixed list names the full set (union semantics)" {
  psx_setup
  git add docs/note.md
  run hug us docs/note.md src/
  assert_success
  assert_output --partial "matching 'docs/note.md' 'src/':"
  psx_reset
}

@test "conformance us (#302): dry-run mirrors the clause" {
  psx_setup
  run hug us --dry-run src/
  assert_success
  assert_output --partial "Would unstage"   # exact: "Dry run: Would unstage N file(s) matching 'src/':"
  assert_output --partial "matching 'src/':"
  psx_reset
}

@test "conformance us (#302): -- invariance — clause identical with and without the separator" {
  # Codex #3829676857: the previous draft captured $output but never compared it, so a bare invocation that
  # diverged from the -- form still passed. Compare both outputs (status + first-line clause) so the
  # stated -- -invariance property is actually pinned.
  psx_setup
  run hug us src/
  assert_success
  local bare_out="$output"
  local bare_status="$status"
  assert_output --partial "matching 'src/':"
  psx_reset
  psx_setup
  run hug us -- src/
  assert_success
  assert_equal "$bare_status" "$status"
  assert_equal "$bare_out" "$output"
  psx_reset
}

@test "conformance us (F-005): subdir run keeps root-relative spelling, clause echoes user spelling" {
  psx_setup
  mkdir -p src/deep && echo z > src/deep/z.py && git add src/deep/z.py
  cd src
  run hug us -- deep/
  assert_success
  assert_output --partial "matching 'deep/':"
  assert_output --partial "src/deep/z.py"   # root-relative ✓ line
  cd - >/dev/null
  psx_reset
}
```

- [ ] **Step 2: Run red** — `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER="#302"` → the `matching` assertions FAIL (no clause at HEAD).

- [ ] **Step 3: Add `is_scope_shaped` and refactor the noun** in `git-config/bin/git-us`. Define the function at script scope (before `hug_us`), and refactor the inline noun test at :485-488:

```bash
# is_scope_shaped (#302 finding 1): classifies whether an argument is a
# directory/glob/magic scope — the f2771623 noun rule. One classifier shared by
# the error-path noun (below) and the success/dry-run scope clause, so the two
# sites classify identically by construction. Stays git-us-local (rule of three
# — no second command needs it yet).
is_scope_shaped() {
  local arg="$1"
  [[ "$arg" == */ || "$arg" == *'('* || "$arg" == *'*'* || "$arg" == *'?'* || "$arg" == *'['* ]]
}
```

In `hug_us`, apply the fix at BOTH sites — extract `is_scope_shaped` at script scope and replace the inline noun test at :485-488 (wildcard arms must be *anywhere*, not trailing-only: `*'*'*`/`*'?'*`/`*'['*`, codex #3830105463 — otherwise `src/*.py`/`foo?.txt`/`src/[ab].py` are misclassified as literal files):
```bash
    local noun="File"
    is_scope_shaped "$file" && noun="Path"
```

- [ ] **Step 4: Build `scope_clause` and append to both messages.** In `hug_us`, after `report_targets` is finalized (after :524) and before the dry-run branch (:527), insert:

```bash
  # Scope clause (#302 finding 1): name the FULL scope set when any pathspec is
  # scope-shaped. Git unions pathspecs, so "matching 'X' 'Y'" = matching any of
  # the set = exactly what the count counts. Literal-only invocations get no
  # clause (the ✓ lines already say everything). Reads the converged `pathspecs`
  # array (script scope), NEVER files_to_unstage (the from-source arm holds
  # filtered source FILENAMES, not the user's scope). Built once; consumed by
  # both success and dry-run so they cannot diverge.
  local has_scope=false spec
  for spec in ${pathspecs[@]+"${pathspecs[@]}"}; do
    is_scope_shaped "$spec" && { has_scope=true; break; }
  done
  local scope_clause=""
  if $has_scope; then
    local scope_list=""
    printf -v scope_list "'%s' " ${pathspecs[@]+"${pathspecs[@]}"}
    scope_clause=" matching ${scope_list%' }"
  fi
```

At :528 (dry-run), change:
```bash
    info "Dry run: Would unstage ${#report_targets[@]} file(s)${scope_clause}:"
```

At :546 (success), change:
```bash
  success "Unstaged $count $file_word${scope_clause}:"
```

- [ ] **Step 5: Run green** — `make test-unit TEST_FILE=test_pathspec_conformance.bats` and `make test-unit TEST_FILE=test_status_staging.bats` → green (existing roast pin :1429 still substring-matches `Unstaged 1 file`; the new clause pins pass).

- [ ] **Step 6: Mutation receipt** — remove the `if $has_scope` block (force `scope_clause=""`), re-run the `#302` pins → red. Restore.

- [ ] **Step 7: Commit** — `hug a git-config/bin/git-us tests/unit/test_pathspec_conformance.bats && hug c -m "feat(us): success/dry-run summaries name the scope when pathspecs are scope-shaped (#302, F-005)"`

---

## Task 6: Rename the stale conformance test

**Goal:** Rename `test_pathspec_conformance.bats:797` from coincidence-framing to contract-framing, per the :2197 precedent; body unchanged.

**Files:**
- Modify: `tests/unit/test_pathspec_conformance.bats:797` (name + leading comment)

**Acceptance Criteria:**
- [ ] test name is `contract sl-family: -- src/ filters via the split (sl sla; was characterization)`
- [ ] leading comment rewritten to flipped past-tense (the row asserts the contract; `sls` retirement note kept)
- [ ] body byte-identical (the two-sided filter assertions)
- [ ] `grep -n "filters by coincidence" tests/unit/test_pathspec_conformance.bats` → zero hits
- [ ] `make test-unit TEST_FILE=test_pathspec_conformance.bats` green

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER="sl-family"` → green; `grep -rn "filters by coincidence" tests/` → no output.

**Steps:**

- [ ] **Step 1:** In `tests/unit/test_pathspec_conformance.bats`, at :797, rename and rewrite the comment:

```bash
@test "contract sl-family: -- src/ filters via the split (sl sla; was characterization)" {
  # FLIPPED by PR-B Task 4 (was characterization): sl/sla (statusbase) were
  # migrated onto parse_common_flags_with_pathspecs, so the split consumes the
  # separator and the row now asserts the CONTRACT (filtering via the split),
  # not the pre-PR-B coincidence. See the statusbase conformance tests. sls was
  # retired from this row by Task 5 (migrated — see the sls-family conformance
  # tests).
  for cmd in "${PATHSPEC_CHAR_SL_FILTER_ROWS[@]}"; do
    psx_setup
    run hug "$cmd" -- src/
    assert_success
    assert_output --partial "src/a.py"
    refute_output --partial "docs/note.md"
    psx_reset
  done
}
```

- [ ] **Step 2: Run green** — `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER="sl-family"` → green; `grep -rn "filters by coincidence" tests/` → no output.

- [ ] **Step 3: Commit** — `hug a tests/unit/test_pathspec_conformance.bats && hug c -m "test(conformance): rename stale 'filters by coincidence' row to contract framing (#302)"`

---

## Task 7: CHANGELOG + final full gate

**Goal:** Record the user-visible message change in the CHANGELOG (frozen-vs-living policy: the new entry documents forward; the old CHANGELOG:74 stays as-written), and run the full suite as the landing gate.

**Files:**
- Modify: `CHANGELOG.md` (new entry under the appropriate version section)
- Verify: full `make test`

**Acceptance Criteria:**
- [ ] CHANGELOG has a new entry naming the three message/naming changes (reject `(got N files)`, `us` scope clause, the rename is internal — mention only if a section lists test-suite changes)
- [ ] the frozen `CHANGELOG.md:74` line stays untouched (it records what was true at its version)
- [ ] `make test` (full BATS + pytest) green
- [ ] `make test-unit TEST_FILE=test_pathspec_conformance.bats`, `make test-lib TEST_FILE=test_hug-cli-flags.bats`, `make test-unit TEST_FILE=test_status_staging.bats` all green

**Verify:** `make test` → green (all BATS + pytest).

**Steps:**

- [ ] **Step 1:** Add a CHANGELOG entry under the current/next version's section (follow the file's existing format). Example text:

```markdown
- **Single-file cardinality messages report a truthful count** — `hug <cmd> accepts only one file (got N files).` instead of a count-less rejection; `llf`, `stats file`, and `h steps` no longer count trailing flags as extra files.
- **`hug us` success/dry-run summaries name the scope** — `Unstaged 2 files matching 'src/':` when a directory/glob/magic pathspec is given, so the count no longer implies a file argument was passed.
```

- [ ] **Step 2:** Run the full gate — `make test` → green.

- [ ] **Step 3: Commit** — `hug a CHANGELOG.md && hug c -m "docs(changelog): record #302 message changes — truthful reject count, us scope naming"`

---

## Self-Review

**Spec coverage:** §1 background — N/A (context). §2 Finding 1 + F-005 → Task 5. §3 Finding 2 → Task 6. §4 Finding 3 (§4.1 audit, §4.2 helper/message, §4.3 call sites llf/stats-file/h-steps, §4.4 proof rows, §4.5 lib tests) → Tasks 1-4. §5 search trail → recorded in the spec, no task. §6 testing strategy → embedded in every task's red-first + mutation receipt + Verify lines. §6 docs perimeter (frozen-vs-living) → Task 7 (CHANGELOG forward; frozen records untouched). §7 error/stdout/perf — preserved by construction (argument surgery, stderr helpers, no new processes). §8 out-of-scope — recorded, no task. §9 rationale — N/A. All spec sections covered.

**Placeholder scan:** none — every code step shows the actual code; every Verify names a real make target.

**Type consistency:** `collect_positional_args_before_flags` (T1) used verbatim in T2 (llf) and T3 (stats-file); T4 (h-steps) deliberately uses an inline filter, justified. `is_scope_shaped` (T5) used by the noun loop and the clause. `reject_multiple_files` message form `(got ${#files[@]} files)` consistent across T2-T5 proof rows. Pin-flip counts: five no-flag pins in T2 + the llf :1949 pin in T2 (six total in T2); the stats-file/h-steps proof rows are new (T3/T4).

**Note on the spec's "six pin flips in the message commit":** the spec's §6 said the six flips land in the message commit. This plan puts all six in T2 (the message + llf commit), because :1949 is the llf trailing-flag shape whose `(got 2)` is only true post-llf-fix — so the message and the llf fix are one commit (T2). This keeps every commit green and is a faithful refinement, not a deviation.