<!-- /autoplan restore point: /home/ecc/.gstack/projects/elifarley-hug-scm/298-uniform-pathspec-contract-pr-b-autoplan-restore-20260817-213321.md -->
# Uniform Pathspec Contract — PR-B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land PR-B of the uniform pathspec contract — `sl*`/`us` migration onto the PR-A helper, `output_json_status` pathspec plumbing, the `hug a -- <file>` fix (#297), the #298 refactors, and the full doc perimeter.

**Architecture:** Refactor-first staging per the ratified delta-spec (`docs/superpowers/specs/2026-08-17-uniform-pathspec-contract-pr-b-design.md`): stage 1 lands the #298 helpers so the migration consumes them; stages 2–4 migrate commands with characterization rows flipping red→green; stage 5 is the doc perimeter. The parent spec (`2026-08-16-…-design.md` §2/§3/§4) governs the contract, helper semantics, and suite shape.

**Tech Stack:** Bash (GNU getopt via `parse_common_flags_with_pathspecs`), BATS conformance suite, VitePress docs.

**Conventions for every task:** bare positionals after flag parsing are pathspecs, family-wide (git parity; loud errors are for `-*` tokens only); work in this worktree only; run `make sanitize` before each commit; test via Makefile targets only (`make test-unit TEST_FILE=… TEST_FILTER=…`, `make test-lib …`); commit via `hug c -F -`; red-first for every behavior flip (the PR-A characterization rows ARE the red baselines — flip the row in the same commit as the behavior).

---

### Task 1: `pathspec_pathspecs_into` accessor + `forward_pathspecs_to_picker` helper

**Goal:** One accessor and one forwarding helper in `hug-cli-flags`, so downstream modules never touch the `_pathspec_pathspecs` global and the `--`+pathspecs forwarding idiom exists once.

**Files:**
- Modify: `git-config/lib/hug-cli-flags` (append after `parse_common_flags_with_pathspecs`)
- Test: `tests/lib/test_hug-cli-flags.bats`

**Acceptance Criteria:**
- [ ] `pathspec_pathspecs_into <nameref>` populates a caller-named array variable with the collected pathspecs (empty array when none) — including when called from a different sourced module than the one that parsed
- [ ] `forward_pathspecs_to_picker <select_opts_nameref>` appends nothing when no pathspecs were collected, and exactly `-- <pathspecs...>` when some were (nullsafe — no bare `--`)
- [ ] Both are pure argument/array surgery — no git calls
- [ ] `declare -ga _pathspec_pathspecs=()` initialization lands at hug-cli-flags load (nounset safety before first parse)
- [ ] Tests cover: unset-global (helper before any parse), empty, one, many, and exotic end-to-end through a MUTATING path — newline, double-quote, backslash, `$()`, backtick, glob chars, leading dash — asserting exact array elements, not output substrings

**Verify:** `make test-lib TEST_FILE=test_hug-cli-flags.bats` → all pass

**Steps:**

- [ ] **Step 1: Write failing tests** in `tests/lib/test_hug-cli-flags.bats`:

```bash
@test "pathspec_pathspecs_into: populates caller nameref, empty when none" {
  source_libraries
  local -a mine=()
  eval "$(parse_common_flags_with_pathspecs -- --picker -- src/a.py 'b c')"
  local -a out=()
  pathspec_pathspecs_into out
  [ "${#out[@]}" -eq 2 ] && [ "${out[0]}" = "src/a.py" ] && [ "${out[1]}" = "b c" ]
  # and the no-pathspec case
  eval "$(parse_common_flags_with_pathspecs -- x)"
  local -a out2=(sentinel)
  pathspec_pathspecs_into out2
  [ "${#out2[@]}" -eq 0 ]   # reset to empty, sentinel gone
}

@test "forward_pathspecs_to_picker: nothing when empty, -- + paths when set" {
  source_libraries
  local -a opts=("--staged")
  eval "$(parse_common_flags_with_pathspecs --)"
  forward_pathspecs_to_picker opts
  [ "${opts[*]}" = "--staged" ]   # unchanged, no bare --
  eval "$(parse_common_flags_with_pathspecs -- src/)"
  forward_pathspecs_to_picker opts
  [ "${#opts[@]}" -eq 3 ] && [ "${opts[1]}" = "--" ] && [ "${opts[2]}" = "src/" ]
}
```

- [ ] **Step 2:** Run `make test-lib TEST_FILE=test_hug-cli-flags.bats` → new tests FAIL (functions undefined).
- [ ] **Step 3:** Implement in `hug-cli-flags`, next to the parser (matching its comment style):

```bash
# Accessor for the collected pathspecs (#298): downstream modules read the
# split through this function instead of touching the _pathspec_pathspecs
# global directly — one read path, so the representation can change later.
pathspec_pathspecs_into() {
  # Reserved prefix __psx_ — a caller variable with this name circulars the
  # nameref (documented; Bash >= 4.3, same floor as the 107 existing
  # local -n uses in git-config/lib).
  local -n __psx_out="$1"
  __psx_out=(${_pathspec_pathspecs[@]+"${_pathspec_pathspecs[@]}"})
}

# Picker-forwarding helper (#298): the ONE place that appends the collected
# pathspecs to a picker's option array behind a protective '--' — a pathspec
# literally named like a picker option ('--staged') must stay data, and a
# missing pathspec list must never leave a bare '--'. Replaces the idiom
# previously repeated across hug-select-files, hug-git-diff, lc/lf/lcr.
forward_pathspecs_to_picker() {
  local -n __fps_opts="$1"
  # ${arr[@]+x} guard: under set -u an UNSET global (helper used before any
  # parse — the exact cross-module case) must not kill the shell.
  if [[ ${_pathspec_pathspecs[@]+x} && ${#_pathspec_pathspecs[@]} -gt 0 ]]; then
    __fps_opts+=("--" ${_pathspec_pathspecs[@]+"${_pathspec_pathspecs[@]}"})
  fi
}
```

- [ ] **Step 4:** Run the suite → PASS. Commit: `feat: pathspec accessor + picker-forwarding helper in hug-cli-flags (#298)`

### Task 2: Non-flag-filter helper; adopt in `llf` + `stats-file`

**Goal:** One shared "count positionals only up to the first flag" function replacing the two semantically-identical loops; `w-get`'s rev-parse shape guard stays command-owned (different cut — spec §2 stage 1).

**Files:**
- Modify: `git-config/lib/hug-cli-flags` (append), `git-config/bin/git-llf`, `git-config/bin/git-stats-file`
- Test: `tests/lib/test_hug-cli-flags.bats`

**Acceptance Criteria:**
- [ ] `count_positional_args_before_flags <args...>` prints the count of leading non-`-*` args (first flag ends the count); prints `0` for no args
- [ ] `llf` and `stats-file` cardinality guards call it; their existing rejection messages are byte-identical (tests already pin them — no message drift)
- [ ] Unit tests: `a b` → 2, `a --staged b` → 1, `-x a` → 0, empty → 0, `-- a b` → 0

**Verify:** `make test-lib TEST_FILE=test_hug-cli-flags.bats` and `make test-unit TEST_FILE=test_pathspec_conformance.bats TEST_FILTER="one file"` → all pass

**Steps:**

- [ ] **Step 1: Failing tests** for the helper (same style as Task 1; case list from the AC).
- [ ] **Step 2:** Implement:

```bash
# Count LEADING positional arguments only — the first flag-looking token
# ends the count (#298): cardinality guards must not count a flag's VALUE
# as a second file ('llf a --staged' has ONE file, not two — the PR-A
# regression this idiom encodes). '--' itself ends the count; post-'--'
# tokens are pathspec data, not command positionals.
count_positional_args_before_flags() {
  local n=0
  for arg in "$@"; do
    case "$arg" in
    -*) break ;;
    *) n=$((n + 1)) ;;
    esac
  done
  printf '%s\n' "$n"
}
```

- [ ] **Step 3:** Replace the two loops (find them via `grep -n 'remaining_args\|#.*flag' git-config/bin/git-llf git-config/bin/git-stats-file` — the PR-A cardinality blocks) with `count=$(count_positional_args_before_flags …)` feeding the existing `reject_multiple_files` calls. Do NOT touch `git-w-get`'s guard.
- [ ] **Step 4:** Suites green. Commit: `refactor: shared positional-count helper for cardinality guards (#298)`

### Task 3: Contract-comment dedup + bounded nullsafe sweep + 3 combo-gap tests

**Goal:** One canonical parsing-order/pathspec comment in `hug-cli-flags`; call sites reference it; bare `"${arr[@]}"` at reachable-empty sites in PR-B-touched files converted; the 3 coverage gaps closed.

**Files:**
- Modify: `git-config/lib/hug-cli-flags` (canonical comment), `git-config/bin/git-{lc,lf,lcr}` + `git-config/lib/hug-{select-files,git-diff}` (comment refs replace the 7 duplicated `--picker` blocks and 5 nullsafe comment blocks), bounded sweep targets found by the Task grep
- Test: `tests/lib/test_hug-git-files.bats`, `tests/unit/test_pathspec_conformance.bats`

**Acceptance Criteria:**
- [ ] The duplicated 6-line comment blocks are replaced by 1-2-line pointers ("see `parse_common_flags_with_pathspecs` in hug-cli-flags for the parsing-order contract")
- [ ] Sweep bounded per spec §2: only files PR-B touches or their directly-sourced libs; qualifier = array reachable-empty under `set -u`; inventory listed in the commit message
- [ ] Combo-gap tests land and pass: `--cwd`+pathspec direct on `list_tracked_files` (`--cwd -- src/` → only src/ files, no literal `--` match), ignored-files pathspec forwarding (selector `--ignored` + pathspec), fblame churn-mode guard cell
- [ ] Zero behavior change — full conformance suite + touched suites green

**Verify:** `make test-lib TEST_FILE=test_hug-git-files.bats` + `make test-unit TEST_FILE=test_pathspec_conformance.bats` → all pass

**Steps:**

- [ ] **Step 1:** Inventory sweep targets: `grep -rn '"${[a-z_]*\[@\]}"' git-config/bin/git-{lc,lf,lcr,w-get,llf,stats-file,sl,sla,sls,slu,slk,sli,slc,us,a,statusbase} git-config/lib/hug-{cli-flags,select-files,git-diff,git-files,git-json,git-kit} 2>/dev/null` — for each hit, keep only if the array is provably non-empty at that point; otherwise convert to `${arr[@]+"${arr[@]}"}`.
- [ ] **Step 2:** Write the 3 combo-gap tests (red where the gap is real — GAP-2/GAP-3 may pass already via PR-A's transitive coverage; if green on arrival, assert they stay green, they are coverage not flips). Ignored-files cell uses the stub-gum harness (`psx_install_stub_gum`, `HUG_TEST_MODE=true`).
- [ ] **Step 3:** Suites green. Commit: `refactor: comment dedup + bounded nullsafe sweep + combo-gap tests (#298)`

### Task 4: `statusbase` + `sl` + `sla` migration (canonical pattern)

**Goal:** The three status-listing roots adopt the helper: pathspecs to all sinks, `--help` works, unknown flags loud, trailing bare `--` inert, summary suppressed when pathspecs active.

**Files:**
- Modify: `git-config/bin/git-statusbase` (owns `sl`/`sla` via gitconfig aliases `sl = statusbase -uno`, `sla = statusbase --long` — no separate binaries exist)
- Test: `tests/unit/test_pathspec_conformance.bats` (flip the sl/sla characterization rows)

**Acceptance Criteria:**
- [ ] `parse_common_flags_with_pathspecs` adopted WITHOUT `--picker`; custom flags (`--long`, `-u`, `-uno` on statusbase) parsed from pre-args in the own-loop; each command's accepted pre-`--` grammar stated in the loop — unknown tokens are ONLY the `-*` class, positionals collect as pathspecs (git parity)
- [ ] Own-loop rejects unknown flag tokens loudly: `-x` → error naming the flag, exit ≠ 0 (was: silent pathspec swallow)
- [x] Pathspecs flow to `list_files_with_status` and `run_count_mode` calls. **AC AMENDED after Task 4's spec adjudication (probed at the git oracle)**: the protective `--` lives at the LIB's git boundary (hug-select-files already inserts it at all 14 forwarding sites + count sites) — callers pass pathspecs RAW. A caller-side `--` protects nothing (the lib's option loop is separator-blind) and is affirmatively harmful: it rides inside the lib's pathspec array as a phantom positive pathspec that EMPTIES `:(exclude)`-only scoping (`git status --porcelain -- -- ':(exclude)src/'` → empty). The residual `hug sl -- --cwd` misparse (option-named pathspec toggles the lib flag) is pre-existing, unfixable at the caller layer, and is a Task 5 acceptance probe: make `list_files_with_status`/`count_files_with_status` separator-aware.
- [ ] Trailing `exec hug s` summary (statusbase:106) suppressed iff the pathspec array is non-empty (NOT `--`-seen — spec §3.1 sink 4); `hug sl --` ≡ `hug sl` INCLUDING the summary
- [ ] Conformance rows flip: sl/sla `-- <path>` filter; bare `--` inert (output equality with unfiltered run); `-h` shows help; unknown flag loud
- [ ] `--json` arm unchanged this task (Task 5 owns the plumbing — sl/sla `--json`+pathspec rows stay characterization-red here ONLY if they are currently red; they are currently green-as-ignored, so they stay pinned until Task 5)

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats` → all pass

**Steps:**

- [ ] **Step 1:** Flip the sl/sla characterization rows red-first (edit the row arrays: change expected behavior to the contract; run; confirm FAIL against current code).
- [ ] **Step 2:** Migrate `git-statusbase` — replace the `for arg in "$@"` loop (statusbase:29-51) with:

```bash
# Uniform pathspec split (#292 PR-B): flags/refs before '--', pathspecs
# after it — see parse_common_flags_with_pathspecs in hug-cli-flags.
# The helper's ONLY mode flag is --picker (verified at hug-cli-flags:278);
# custom flags are consumed by an own-loop over the pre-args the split
# returns, rejecting anything else flag-shaped LOUDLY (silent swallow is
# how '-x' masqueraded as a pathspec) — the exact sls pattern in Task 5.
eval "$(parse_common_flags_with_pathspecs "$@")"
for arg in "$@"; do
  case "$arg" in
  --long) long_output=true ;;    # statusbase's custom flags; substitute
  -u | -uno) untracked_mode="$arg" ;;  # per script from its old loop
  -*) error "Unknown option: $arg (see 'hug <cmd> -h')"; exit 2 ;;
  *) pathspecs+=("$arg") ;;   # git parity (autoplan decision 7): 'hug sls src/'
                             # filters today and keeps filtering — the loud
                             # error is for flag-shaped tokens ONLY; bare
                             # positionals after flag parsing are data
  esac
done
```

Substitute each script's real custom flags from its pre-migration loop; keep the dispatch below identical. **`show_help` is a required step** (eng-voice finding): `parse_common_flags`' `-h` arm only calls `show_help` if the script DEFINES one — statusbase/sls/slu/slk/sli define none today, so `-h` would exit 0 printing nothing. Write a `show_help` for each migrated script in the same task; the `-h` AC asserts NON-EMPTY output. Note: `sl`/`sla` are gitconfig aliases (`sl = statusbase -uno`, `sla = statusbase --long`) — there are no git-sl/git-sla binaries; migrate `statusbase` only, and smoke-test `hug sl` / `hug sla` reach the migrated code with their alias-passed pre-args (`-uno`, `--long` must be in the own-loop's accepted grammar).
- [ ] **Step 3:** Same for `git-sl`/`git-sla` (they delegate to statusbase — verify whether they have their own loops or inherit; migrate only what exists). Add the summary suppression at statusbase:106:

```bash
# Sink 4 (#298): the trailing whole-repo 'hug s' summary is suppressed
# iff pathspecs are active (array-non-empty, NOT '--'-seen — the inert
# bare '--' must keep summary parity with the unfiltered run).
# NOTE: script scope — NO 'local' (Bash: "can only be used in a
# function"; under set -e that error kills every non-quiet listing).
__psx_summary_scope=()
pathspec_pathspecs_into __psx_summary_scope
if [[ ${#__psx_summary_scope[@]} -eq 0 ]]; then
  exec hug s
fi
```

- [ ] **Step 4:** Rows green; `make test-unit TEST_FILE=test_status_staging.bats` still green (no unintended flips). Commit: `feat: statusbase/sl/sla adopt the uniform pathspec contract (#292)`

### Task 5: `sls`/`slu`/`slk`/`sli` migration

**Goal:** The four filtered listings migrate identically to Task 4's pattern.

**Files:**
- Modify: `git-config/bin/git-{sls,slu,slk,sli}`
- Test: `tests/unit/test_pathspec_conformance.bats`

**Acceptance Criteria:** same contract as Task 4, plus per-script custom flags (`--json`, `-c/--count`, `-q`) parsed from pre-args; the `run_count_mode` calls already forward pathspecs (verified in sls:58-61) — keep them fed from the accessor; **every sink call carries a protective `--` before pathspecs** (eng-voice finding: `list_opts+=` at sls:49-51 / statusbase:60-62 and the `run_count_mode` calls have NO separator today — a pathspec named `--json`/`--cwd` toggles scope at those boundaries; conformance row per sink); mode-interaction rows pin scoped × quiet/json/count × empty/non-empty; the "No unstaged files matching '--' 'src/'" phantom-pathspec info message (slu/slk/sli today) disappears — the split never leaves `--` in the pathspec list.

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats` → all pass

**Steps:**

- [ ] **Step 1:** Flip the four commands' characterization rows red-first.
- [ ] **Step 2:** Migrate each script's loop (the sls shape at git-sls:27-43 becomes):

```bash
pathspecs=()
for arg in "$@"; do   # replaced by the split below
  :
done
# ↓ becomes:
eval "$(parse_common_flags_with_pathspecs "$@")"
# Rehydrate quiet AFTER the split: parse_common_flags CONSUMES -q/--quiet
# (its getopt has 'q') and exports HUG_QUIET — the own-loop below never
# sees the flag, and the script's top-of-file 'quiet=false' init ran
# before the user's env carried HUG_QUIET. Without this, 'hug slk -q'
# loses --suppress-status and prints status prefixes (review P2).
[[ ${HUG_QUIET:-} == T ]] && quiet=true
for arg in "$@"; do   # pre-args only now
  case "$arg" in
  --json) json_output=true ;;
  -c | --count) count_only=true ;;
  -q | --quiet) quiet=true ;;   # unreachable via the split (consumed
                                # above) — kept for direct callers only
  -*) error "Unknown option: $arg (see 'hug sls -h'; to pass a path starting with '-', use 'hug sls -- <path>'; see hug help :pathspec)"; exit 2 ;;
  *) pathspecs+=("$arg") ;;   # git parity — SAME rule as Task 4 (DX finding 1:
                             # one rule for the whole family, or the mental
                             # model fractures where devs live)
  esac
done
pathspec_pathspecs_into pathspecs
```

Note: positionals before `--` keep filtering (git parity, decision 7) — the ONLY loud flip in this task is unknown-flag rejection (the `-*` class). Check each command's PR-A characterization row and flip only what the row pins. The positional rule is stated ONCE in the conventions block: bare positionals after flag parsing are pathspecs everywhere in the sl* family.

- [ ] **Step 3:** Rows green. Commit: `feat: sls/slu/slk/sli adopt the uniform pathspec contract (#292)`

### Task 6: `output_json_status` chain plumbing

**Goal:** Pathspecs stop being discarded in the JSON chain; the call boundary honors `--`.

**Files:**
- Modify: `git-config/lib/output_json_status` (the parse loop — NOT hug-json, which holds only escape/serialize helpers), `git-config/lib/hug-git-json` (`output_json_status_unified` at :141-144, `collect_git_files_json` list calls)
- Test: `tests/lib/test_hug_git_json.bats`, `tests/unit/test_status_staging.bats`

**Acceptance Criteria:**
- [ ] `output_json_status`'s parse loop (`git-config/lib/output_json_status:45-47`) collects pathspecs behind a `--` arm (a pathspec named `--cwd`/`--staged`-family is data — mirror `list_staged_files`' `--)` arm at `hug-git-files:40-49`)
- [ ] `output_json_status_unified`'s catch-all (`hug-git-json:141-144`) same: `--` arm + collector
- [ ] `collect_git_files_json` forwards collected pathspecs to every `list_*_files` call after a protective `--` (nullsafe)
- [ ] Two-sided JSON tests per envelope: parses via `python3 -m json.tool`; no file outside the pathspecs AND ≥1 inside; `summary.*` counts match the scoped array
- [ ] `hug sls --json -- --cwd` (file named `--cwd`) scopes, does not toggle

**Verify:** `make test-lib TEST_FILE=test_hug_git_json.bats` + `make test-unit TEST_FILE=test_status_staging.bats` → all pass

**Steps:**

- [ ] **Step 1:** Failing lib tests: fixture repo with staged `src/a.py` + staged file literally named `--cwd`; call `output_json_status --staged -- src/` → JSON contains `src/a.py`, not `--cwd`'s file.
- [ ] **Step 2:** Implement the two `--` arms + forwarding (pattern: `--)) shift; while [[ $# -gt 0 ]]; do pathspecs+=("$1"); shift; done` in each parse loop; append `${pathspecs[@]+"--" "${pathspecs[@]}"}` at the `list_*_files` call sites in `collect_git_files_json`).
- [ ] **Step 3:** Green. Commit: `feat: output_json_status chain honors pathspecs and the -- boundary (#292)`

### Task 7: `slc` migration + the claim-flip sweep

**Goal:** slc migrates like Task 5 (it has `show_help` already); every artifact asserting the old "slc --json ignores pathspecs" contract flips in this commit.

**Files:**
- Modify: `git-config/bin/git-slc` (:31 flag line, :38-39 DESCRIPTION, own loop), `tests/unit/test_status_staging.bats:1855`, `docs/commands/status-staging.md:138`, `docs/superpowers/plans/2026-08-06-slc-conflicted-files.md` (:672 checkbox, :880 annotate), `docs/superpowers/specs/2026-08-06-slc-conflicted-files-design.md` (:56, :131 annotate-as-superseded)
- Test: `tests/unit/test_pathspec_conformance.bats`

**Acceptance Criteria:**
- [ ] slc contract rows green (filter, inert `--`, `-h`, unknown-flag loud)
- [ ] `test_status_staging.bats:1855` now asserts scoping, IN THIS COMMIT
- [ ] The claim-flip table (spec §3.3) fully swept: all 6 rows edited per their Edit column; historical quotes annotated, never rewritten
- [ ] `hug slc --json -- <path>` scoped; `hug slc -h` shows no contradiction

**Verify:** `make test-unit TEST_FILE=test_status_staging.bats` + `TEST_FILE=test_pathspec_conformance.bats` → all pass

**Steps:**

- [ ] **Step 1:** Flip slc's rows + the `:1855` test red-first (edit to assert scoping; run → FAIL).
- [ ] **Step 2:** Migrate slc's loop (Task 5 pattern; slc's extra `-q` and existing `show_help` stay).
- [ ] **Step 3:** Apply the 6 claim-flip edits verbatim from the spec table.
- [ ] **Step 4:** Green. Commit: `feat: slc joins the contract; claim-flip sweep completes (#292, #298)`

### Task 8: `us` migration

**Goal:** `us` adopts the split: mid-stream `--` filters; trailing bare `--` is a no-op token (zero-args dispatch to the existing staged-file selector).

**Files:**
- Modify: `git-config/bin/git-us` (split hoisted above the own loop; both `files_to_unstage` branches fed — plain `:129-133` + from-source concat `:117-126`)
- Test: `tests/unit/test_pathspec_conformance.bats`

**Acceptance Criteria:**
- [ ] `hug us -- src/` unstages only staged files under `src/` (was: "Unknown option: --")
- [ ] `hug us file.txt` (no `--`) behaves EXACTLY as today — the documented invocation keeps working; only the mid-stream `--` filter and loud `-*` rejection change
- [ ] `hug us --` ≡ `hug us` output equality, fixture pinned to ≥1 staged file (non-vacuous), per gum-presence
- [ ] Both `files_to_unstage` branches receive the split's pathspecs, and from-file/from-commit sources **INTERSECT** with them (eng-voice finding: concat is a union that would unstage files OUTSIDE the scope — the opposite of the contract; row pins `us --from-commit <c> -- src/` unstaging only in-scope files)

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats` → all pass

**Steps:**

- [ ] **Step 1:** Flip us's characterization rows red-first.
- [ ] **Step 2:** Hoist the split above the custom loop; feed both branches via `pathspec_pathspecs_into`; trailing bare `--` detected by the helper is simply not a positional (zero args → selector fallback, existing `git-us:144-158` path).
- [ ] **Step 3:** Green. Commit: `feat: us adopts the uniform pathspec contract (#292)`

### Task 9: `a` contract completion — scoped picker + roster (CHANGED at autoplan gate)

**GATE DECISION (user, 2026-08-17): the #297 bug fix (`hug a -- <file>` staging exactly those files) MOVES to a small fast-follow PR off main** so the live bug lands without waiting on this batch. Task 9 retains ONLY what depends on PR-B's stage-1 helpers: the scoped-picker arm and roster enrollment. The fast-follow PR carries: the split adoption (`--picker` first-arg), post-`--` positional staging, the `hug a -- -A` separator test, and pre-`--` byte-parity tests. When it lands BEFORE PR-B, this task shrinks to the picker-forwarding + sentinel work; if PR-B lands first, fold its commits here.

**Goal:** `hug a`'s picker is scoped when pathspecs precede the trailing `--`; `a` joins the conformance roster with sentinel-armed column loops.

**Files:**
- Modify: `git-config/bin/git-a` (split at :132-167; picker branch :199-222)
- Test: `tests/unit/test_pathspec_conformance.bats` (flip `a` rows; arm the 4 sentinel-less loops at `:252/:305/:356/:532`; add `a` to `PATHSPEC_PICKER_ROWS:52`)

**Acceptance Criteria:**
- [ ] (moved to the #297 fast-follow PR) `hug a -- file.txt` stages exactly `file.txt`; pre-`--` behavior byte-identical (existing `a` tests untouched and green)
- [ ] Bare `hug a --` → picker unchanged (HUG_INTERACTIVE_FILE_SELECTION path)
- [ ] Picker branch reads pathspecs via `pathspec_pathspecs_into` + `forward_pathspecs_to_picker`; `hug a -- src/ --` offers only `src/` candidates (cancelling stub — read-only by construction)
- [ ] `a`'s SELECTION semantics get a dedicated standalone test (mutating — not a shared-column cell)
- [ ] All 4 column loops gain `*)` sentinel arms (`__PSX_UNKNOWN_ROW__` breadcrumb) and `a` case arms in the capture columns

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats` + `TEST_FILE=test_staging.bats` (or the `a` suite — locate via `grep -rln 'hug a ' tests/unit/`) → all pass

**Steps:**

- [ ] **Step 1:** Red-first: flip `a`'s characterization row (pathspec-drop) and add the scoped-picker row; arm the 4 loops' sentinels; run → FAIL.
- [ ] **Step 2:** Replace `git-a`'s ad-hoc handling: adopt `parse_common_flags_with_pathspecs --picker "$@"` — the mode flag MUST be the literal FIRST argument (the helper checks `${1:-}` only; appending it after `"$@"` makes `--picker` pathspec data and stages a file by that name). a IS on the picker list — the helper owns the export lifecycle; post-split positionals after `--` stage as explicit paths via `hug_add_with_summary "${paths[@]}"` (defined in `git-a:40` — it snapshots then `git add`s its args; VERIFY its internal `git add` call carries a protective `--` so a post-separator file named `-u` stays data, and add one if missing — raised to an AC with test: `hug a -- -A` stages a file literally named `-A` and NOTHING else); the picker branch gains the two helper calls. Post-parse array layout stated in the task: custom options (--from-file/--from-commit values), pre-args residue, pathspecs, source-derived files — with a combination test of source flags + `--`.
- [ ] **Step 3:** Green; full `make test-unit` (the `a` surface is high-traffic — run the whole unit tier, not just the conformance file). Commit: `feat: hug a honors pathspecs after --; scoped picker (#297)`

### Task 10: Doc perimeter

**Goal:** The full §7 doc sweep.

**Files:**
- Create: `git-config/lib/python/articles/pathspec.md` (the `:pathspec` article)
- Modify: per the pinned roster — PATH FILTERING blocks in `git-config/bin/git-{statusbase,sls,slu,slk,sli,slc,us,a,lc,lf,lcr,cmod,cmoda}` (NOTE: `sl`/`sla` have NO binaries — their help text comes from `git-statusbase` + the gitconfig aliases; the block lands in statusbase only, and the task states where `hug sl --help` / `hug sla --help` text is sourced); `README.md` (`sl`/`sla` rows); `docs/commands/status-staging.md`; `docs/git-to-hug.md`; `git-config/lib/python/categories/{status,show,history}.toml`; `git-config/lib/README.md`; `docs/meta/hug-completion-reference.md`; `completions/hug-completion.bash` + `completions/hug.fish` (re-grep only)

**Acceptance Criteria:**
- [x] `hug help :pathspec` serves the article (mechanism as `agents.md` — verify via an existing article's registration path if not automatic)
- [x] Article covers: syntax, quoting + why, the `--` duality, magic passthrough, per-command support matrix, the edge cases from spec §7 (mid-stream second `--` phantom; trailing never phantom; `--`/`--help`-named files unreachable pre-separator; picker = separator spelling only); does NOT document `HUG_INTERACTIVE_FILE_SELECTION`
- [x] All roster commands show the pointer block; single-file + PR-C commands NOT enrolled
- [x] Canonical FIRST example pinned in README + article opener: `hug sla -- '*.md'` (+ the no-separator form `hug sla '*.md'` + a "quote your globs" note)
- [x] Error template standardized family-wide (incl. statusbase): `Unknown option: <tok>. Pathspecs beginning with '-' require '--': hug <cmd> -- <tok>. See 'hug help :pathspec'.`
- [x] Article carries a compact command-class table FIRST-SCREEN (listing / mutating-explicit-path / mutating-picker behavior for trailing `--`) and a "Breaking changes / script migration" section: before/after semantics, exit-status and JSON-scope implications, safe rewrites — the mutation changes (`a -- file`, `us -- src/`) called out prominently
- [x] Docs smoke test: `hug help`, `hug help :`, `hug sla --help`, `hug help :pathspec` all reachable and non-empty (`-h` is the tested form; `--help` long form routes to git's man page by parent-spec rule 2 — that is documented behavior, not a regression)
- [x] README `sl`/`sla` rows show `[-- <path>...]`; categories mention path filtering; `make docs-build` passes
- [x] **CHANGELOG.md entry per flipped behavior, with before/after command lines** (DX finding 2 — decision 4 wired into an AC): swallow→exit 2 (`hug sls -x`), unscoped→scoped `--json` (jq-level before/after), `a --` drop→stages, listings' inert trailing `--`, `us` flips
- [x] `:pathspec` article states the two escape hatches in one line each: omit pathspecs for full-state JSON; scoped listings omit the summary — `hug s` restores it. Article's support matrix carries explicit **not-yet rows** for PR-C commands (`w-*`/`sh`/`llu`) so readers don't assume `hug w -- src/` works

**Verify:** `make docs-build` + `hug help :pathspec` (manual smoke) → article renders, build green

**Steps:**

- [x] **Step 1:** Write the article (content outline = spec §7 first bullet; ~150 lines).
- [x] **Step 2:** Sweep the roster's help blocks (2 lines + example, `git-sw:42-47` style).
- [x] **Step 3:** Remaining doc edits per Files list. Commit: `docs: :pathspec article + full PR-B doc perimeter (#292, #298)`

### Task 11: Full-suite validation + #298/#297 closure

**Goal:** Everything green; tracking issues closed.

**Files:** none (validation + tracker)

**Acceptance Criteria:**
- [ ] `make test` (all BATS + pytest) green; `make sanitize` clean
- [ ] Spec §5 exit criteria spot-checked live: `hug sls --json -- src/` scoped; `hug sls --` ≡ `hug sls` incl. summary; `hug us --` ≡ `hug us`; `hug a -- file` stages that file
- [ ] elifarley/hug-scm#297 and elifarley/hug-scm#298 closed (or comment-closed with the repo-wide nullsafe remainder note on #298)

**Verify:** `make test` → `✓ All tests passed!` across tiers

**Steps:**

- [ ] **Step 1:** `make test`; fix anything red.
- [ ] **Step 2:** Live spot-checks (scratch repo, one command each).
- [ ] **Step 3:** Close the issues via tracker-ops (`close-item --ref 'elifarley/hug-scm#297'` etc.). Commit nothing (tracker-only), or a final `chore` if anything surfaced.

---

## Task dependencies

1 → 2/3 (helpers first) → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11. Task 3 can run parallel to 2. Task 6 must precede 7 (slc's `--json` rows depend on the plumbing).

<!-- AUTONOMOUS DECISION LOG -->
## Decision Audit Trail

| # | Phase | Decision | Classification | Principle | Rationale | Rejected |
|---|-------|----------|-----------|-----------|----------|----------|
| 1 | CEO | Adopt exotic end-to-end pathspec tests (newline, double-quote) in Task 1 | Mechanical | P1 | eval round-trip is load-bearing; current tests stop at `a b'c` | — |
| 2 | CEO | Add sanitize grep gate: every script with `parse_common_flags_with_pathspecs` carries the PATH FILTERING block | Mechanical | P2 | hand-maintained 6-place doc facts drift; gate is <1h CC | metadata generation (too big for PR-B; #293 is the backstop) |
| 3 | CEO | Keep summary suppression; file follow-up issue for scoped summary | Mechanical | P3 | suppression is pinned + tested; scoped summary is a product decision needing its own row | building scoped summary now (YAGNI) |
| 4 | CEO | Task 10 gains old-vs-new behavior examples in CHANGELOG/release notes | Mechanical | P1 | silent-to-loud flips need consumer-visible migration text | HUG_WARN_ONLY compat window (P4/P5: speculative mode nobody asked for) |
| 5 | CEO | Task 6 ACs add schema-shape assertion for EMPTY scoped JSON results | Mechanical | P1 | `--json` is a machine API; empty-scoped must keep the envelope shape | opt-in full-state flag (no consumer evidence) |
| 6 | CEO | Task 11 adds union metamorphic spot-check: unscoped output = union of disjoint scoped runs | Mechanical | P1 | conformance rows can't prove sink-completeness alone | full metamorphic suite (eng-phase scope) |
| 7 | CEO | pre-`--` positionals: collect as pathspecs (git parity), loud error only for `-*` — EXCEPT commands with positional non-path args | Taste → gate | P1/P5 | "humane wrapper stricter than git" fails the predictability test; both voices lean here | error-on-positional as written in Task 5 |
| 8 | CEO | Split PR-B | USER CHALLENGE → gate | — | both models: #297 lands behind 8 tasks; correlated-failure risk | full batch (user's brainstorm choice) |

## CEO Review (via /autoplan) — Phase 1

### Premise challenge
Premises confirmed by user at gate. Verified in-repo: suite (65 rows), helper at hug-cli-flags:313, the sls swallow, statusbase:106 `exec hug s`, git-a loop, pure-Bash JSON chain. One premise refined: "one review cycle carries safety" — both voices rebutted (correlated failure, review quality decays with size) → became the split challenge.

### Existing code leverage (sub-problem → existing code)
- split/parse → `parse_common_flags_with_pathspecs` (PR-A). candidate scoping → `select_files_with_status` pathspec arm (PR-A). list-layer `--` arms → `list_*_files` (PR-A). suite/stub-gum/sentinels → `psx_*` harness (PR-A). JSON list calls → already pathspec-capable. NEW code is only: 2 helpers + 1 counter + accessor + migrations + article.

### Dream state
CURRENT: 8 commands non-conformant; `--json` silently unscoped; `a --` drops paths (#297) → THIS PLAN: whole family + `us` + `a` conformant, JSON scoped, docs article → 12-MONTH IDEAL: PR-C (w-*/sh/llu) closes the matrix; #293 metadata middleware only if drift recurs; pathspec uniform everywhere with generated doc surfaces.

### Error & Rescue Registry (new codepaths)
| Codepath | Failure | Rescued? | User sees |
|---|---|---|---|
| own-loop unknown flag | `-x` | Y (planned exit 2 + message) | loud error naming flag |
| JSON chain w/ bad pathspec | git exit ≠ 0 | Y (#298 roast MAJOR 1 — was planned as "propagates (git norm)", but every capture suppressed git's exit; implemented as the entry-gate `validate_pathspecs_or_die`: git fatal on stderr + hug error, exit 2, NO envelope on stdout) | git fatal + "Invalid pathspec: … See 'hug help :pathspec'.", exit 2 |
| picker with empty scoped list | no candidates | Y (`_handle_no_files_found`) | "No … available" |
| quiet rehydration missed | silent status prefixes | guarded by slk -q row | test-pinned |
| eval payload corruption | quoting bug | N ← bounded by exotic tests (decision 1) | wrong scope or error |

### Failure Modes Registry
| Mode | Severity | Mitigation in plan |
|---|---|---|
| correlated batch failure | high | suite + red-first flips; SPLIT challenge at gate |
| breaking scripts relying on swallow | high | CHANGELOG + examples (decision 4) |
| doc drift post-merge | medium | sanitize grep gate (decision 2) |
| JSON consumer breakage | medium | schema-shape AC (decision 5) |
| global/_pathspec lifecycle | medium | accessor + exotic tests (decision 1); nameref bundle = PR-C candidate |

### CEO consensus table
| Dimension | Claude | Codex | Consensus |
|---|---|---|---|
| Premises valid? | verified | challenged class-uniformity | DISAGREE → refuted: parent §2 rule 3 already defines command classes |
| Right problem? | yes | yes | CONFIRMED |
| Scope calibration? | split #297 out | split into ~5 units | CONFIRMED → USER CHALLENGE |
| Alternatives explored? | sequencing wrong | split units | CONFIRMED (split rec) |
| Competitive risks? | strictest-of-both-worlds | — | flagged (single voice) |
| 6-month trajectory? | summary+doc follow-ups | doc trap + API decisions | CONFIRMED |

**Phase 1 counts:** Codex: 10 findings (2 critical, 4 high, 4 medium). Claude subagent: 9 (2 high, 7 medium). Consensus: 4/6 confirmed, 1 disagree (refuted), 1 user challenge + 1 taste decision → final gate.

## Eng Review (via /autoplan) — Phase 3

### Architecture (dependency/data flow)
```
user args ─> parse_common_flags_with_pathspecs [--picker FIRST arg]
               │  eval: set -- <pre-args>;  _pathspec_pathspecs=(…)
               v
     own-loop over pre-args  (custom flags; -* loud exit 2; * -> pathspecs, git parity)
               │
   ┌───────────┼──────────────┬────────────────┬───────────────────┐
   v           v              v                v                   v
list_files_with_status  run_count_mode  output_json_status   picker branch (a/su/ss/sw/lc/lf/lcr)
   │ -- + ps            │ -- + ps       │ -> _unified ->      │ forward_pathspecs_to_picker
   v                    v               │   collect_git_files_ v
 git diff/list        count            v   json -> list_*_files   gum (candidates scoped)
                                        v
                             JSON envelope (summary.* == scoped array)
summary sink: exec hug s  — suppressed iff pathspec array NON-empty
```
Coupling: commands gain a dependency on the two new helpers (stage-1) — justified, single read path replaces 5 ad-hoc idioms. The eval-string interface is pre-existing PR-A debt; the accessor is the migration path away from it (nameref-bundle redesign = PR-C candidate, logged). Rollback: single `git revert` per task commit; no flags/migrations.

### Code quality
DRY closures land as tasks 1–3 (picker-forwarding, positional-count, comment dedup). Reserved-prefix nameref collision documented in-helper. The `*) -> pathspecs+=` git-parity arm kills the biggest surprise (finding 1's rejected behavior never ships). Quality gate: byte-identical rejection messages for llf/stats-file (pinned by existing tests).

### Test review
Full map in the test-plan artifact (`~/.gstack/projects/elifarley-hug-scm/…-test-plan-*.md`). Key additions this phase: per-sink protective-`--` rows; exit-2 + stderr assertions; show_help non-empty; `a -- -A` mutator test; us intersection row; metamorphic union spot-check; nested-parse lifecycle test; exotic e2e through a mutating path.

### Performance
Pure argument surgery — no new processes, no git-call multiplication. JSON chain unchanged cost. `sl*` hot path gains one eval + one array copy (µs). No N+1; no caching needed. Examined; nothing flagged beyond noting the eval cost is negligible relative to the git subprocess it precedes.

### Eng consensus table
| Dimension | Claude | Codex | Consensus |
|---|---|---|---|
| Architecture sound? | sound, well-grounded | sound sequence, not ready | CONFIRMED (fixes were plan-text) |
| Test coverage sufficient? | gaps (10 items) | gaps (sink/spy/metamorphic) | CONFIRMED (closed in edits) |
| Performance risks? | none flagged | none flagged | CONFIRMED (none) |
| Security threats? | git-add separator footgun | eval adversarial tests | CONFIRMED (closed: -A AC + exotic asserts) |
| Error paths? | -h vacuous exit | nounset lifecycle | CONFIRMED (closed) |
| Deployment risk? | batch risk | batch risk | CONFIRMED (→ split challenge at gate) |

**Phase 3 counts:** Codex: 12 findings (6 high, 6 medium; #1-2 truncated by output window but overlapped Claude's). Claude subagent: 10 (1 critical, 3 high). All plan-text corrections applied in-plan (11 edits); 1 deferral (JSON -z rework). Refuted: nameref-as-new-Bash-floor (107 existing `local -n` uses).

## DX Review (via /autoplan) — Phase 3.5

Persona: git-fluent CLI developer (hug's actual user — often an agent scripting `hug` in pipelines). TTHW for pathspec scoping after PR-B: ~1 min via `hug <cmd> -h` → pointer → `:pathspec` (target met AFTER the first-example + first-screen table ACs landed).

### DX Scorecard
| Dimension | Before phase | After fixes | Notes |
|---|---|---|---|
| Getting started (first scoping win) | 6 | 9 | canonical example + no-separator form pinned |
| Error quality (problem+cause+fix) | 6 | 9 | standardized template + :pathspec pointer + dash-path fix |
| API/CLI consistency | 5 | 9 | family-wide positional rule unified (the split-brain fix) |
| Docs findability | 6 | 9 | first-screen class table, not-yet rows, smoke test |
| Upgrade path | 4 | 8 | breaking-changes section w/ safe rewrites (script-migration level) |
| Escape hatches | 5 | 8 | full-state JSON = omit pathspecs; summary via `hug s` (documented) |
| Automation-friendliness (JSON/stdout discipline) | 7 | 8 | scoped envelope + exit-2 specificity + stderr routing rows |
| Overall | 5.6 | 8.6 | |

### DX consensus table
| Dimension | Claude | Codex | Consensus |
|---|---|---|---|
| Getting started < 5 min? | yes after fixes | needs canonical example | CONFIRMED (example AC added) |
| Naming guessable? | yes | consistent post-unification | CONFIRMED |
| Errors actionable? | partial | standardize template | CONFIRMED (template AC) |
| Docs findable/complete? | strong, 2 nits | article-dependent → first-screen table | CONFIRMED |
| Upgrade path safe? | CHANGELOG only | needs migration section | CONFIRMED (section AC) |
| Env friction-free? | n/a (installed tool) | n/a | N/A |

**Phase 3.5 counts:** Codex: 7 findings (3 high, 3 medium, 1 low; #5 `--help` REFUTED — parent-spec rule 2: long form routes to git man by design, `-h` is the contract form). Claude subagent: 7 (1 critical — the surviving Task-5 error arm, fixed; 1 high — CHANGELOG wiring, fixed). Consensus: 5/6 confirmed, 1 N/A.

## Cross-phase themes
- **Theme: transcription drift** — the same decision (positional rule) was written into one task but not the other, caught independently by the eng AND DX voices (and once by Codex plan-review before). This project's recorded failure mode ("roster under-transcription") generalizes: EVERY ratified decision must be checked against ALL task bodies before dispatch. Mitigation now: the conventions block states the rule once.
- **Theme: migration story depth** — CEO (compat strategy), DX (script-migration section), eng (schema AC) all pushed the same direction: breaking flips need consumer-level before/after, not test-level green. Landed as Task 10 ACs.

### Journey + empathy (DX, one line each)
Journey: discover (`-h` pointer) → first win (`hug sla -- '*.md'`) → compose (`-c`/`--json` + scope) → migrate (breaking-changes section) — every stage has a pinned artifact after this review. Empathy: "I typed `hug sls src/` and it just filtered — like git. When I typo a flag it tells me the flag AND how to pass a dash-path. The one page I need is one `hug help :pathspec` away."

### NOT in scope (pointer)
Deferred items live in the delta-spec §6 (parent §11) + the test-plan artifact's Deferred section (JSON `-z` rework) + #293/#294. PR-C owns `w-*`/`sh`/`llu` + their README rows.

### Completion summary
| Phase | Findings | Fixed in-plan | Deferred/refuted |
|---|---|---|---|
| CEO | 19 (C10+S9) | 6 auto-decided | 1 user challenge (split), 1 taste (positionals — since applied per decision 7, gate confirms), 1 refuted (command classes) |
| Eng | 22 (C12+S10) | 11 plan-text corrections + AC additions | 1 deferred (JSON -z), 1 refuted (Bash-floor) |
| DX | 14 (C7+S7) | 7 accepted | 1 refuted (`--help` routing) |
| Total | 55 | 24 distinct edits | 2 gate items, 2 deferrals, 3 refuted |

## GSTACK REVIEW REPORT

| Run | Status | Findings | Notes |
|---|---|---|---|
| plan-ceo-review (via autoplan) | clean | 19 | premises user-confirmed; split challenge → gate |
| plan-design-review | skipped | — | no UI scope detected |
| plan-eng-review (via autoplan) | clean | 22 | all plan-text fixes applied; test-plan artifact on disk |
| plan-devex-review (via autoplan) | clean | 14 | score 5.6 → 8.6 after fixes |
| autoplan-voices CEO | codex+subagent | — | 4/6 confirmed, 1 disagree (refuted), 1 challenge |
| autoplan-voices eng | codex+subagent | — | 6/6 confirmed |
| autoplan-voices dx | codex+subagent | — | 5/6 confirmed, 1 N/A |

**VERDICT:** APPROVED WITH GATE ITEMS — plan is implementation-ready after the final gate resolves two decisions (split PR-B or keep full batch; confirm the applied git-parity positional rule). All mechanical findings are fixed in-plan; dual voices converged on quality of staging, diverged only on batching.

**UNRESOLVED DECISIONS:**
- USER CHALLENGE (split PR-B): both CEO voices + eng consensus recommend splitting (minimum: #297 out as a fast-follow PR; Codex: ~5 units). User's brainstorm choice was Full batch. Default = user's direction.
- TASTE (confirm positionals-as-pathspecs): decision 7 applied family-wide per both voices; gate confirms or reverts.
