# Uniform Pathspec Contract — PR-B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land PR-B of the uniform pathspec contract — `sl*`/`us` migration onto the PR-A helper, `output_json_status` pathspec plumbing, the `hug a -- <file>` fix (#297), the #298 refactors, and the full doc perimeter.

**Architecture:** Refactor-first staging per the ratified delta-spec (`docs/superpowers/specs/2026-08-17-uniform-pathspec-contract-pr-b-design.md`): stage 1 lands the #298 helpers so the migration consumes them; stages 2–4 migrate commands with characterization rows flipping red→green; stage 5 is the doc perimeter. The parent spec (`2026-08-16-…-design.md` §2/§3/§4) governs the contract, helper semantics, and suite shape.

**Tech Stack:** Bash (GNU getopt via `parse_common_flags_with_pathspecs`), BATS conformance suite, VitePress docs.

**Conventions for every task:** work in this worktree only; run `make sanitize` before each commit; test via Makefile targets only (`make test-unit TEST_FILE=… TEST_FILTER=…`, `make test-lib …`); commit via `hug c -F -`; red-first for every behavior flip (the PR-A characterization rows ARE the red baselines — flip the row in the same commit as the behavior).

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
- [ ] Tests cover: empty, one, many, exotic (`a b'c`), and set `-u` environments

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
  if [[ ${#_pathspec_pathspecs[@]} -gt 0 ]]; then
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
- Modify: `git-config/bin/git-statusbase`, `git-config/bin/git-sl`, `git-config/bin/git-sla`
- Test: `tests/unit/test_pathspec_conformance.bats` (flip the sl/sla characterization rows)

**Acceptance Criteria:**
- [ ] `parse_common_flags_with_pathspecs` adopted WITHOUT `--picker`; custom flags (`--long`, `-u`, `-uno` on statusbase) parsed from pre-args in the own-loop
- [ ] Own-loop rejects unknown flag tokens loudly: `-x` → error naming the flag, exit ≠ 0 (was: silent pathspec swallow)
- [ ] Pathspecs flow to `list_files_with_status` and `run_count_mode` calls
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
  *) error "unexpected positional '$arg' — put pathspecs after '--'"; exit 2 ;;
  esac
done
```

Substitute each script's real custom flags from its pre-migration loop; keep the dispatch below identical.
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

**Acceptance Criteria:** same contract as Task 4, plus per-script custom flags (`--json`, `-c/--count`, `-q`) parsed from pre-args; the `run_count_mode` calls already forward pathspecs (verified in sls:58-61) — keep them fed from the accessor; the "No unstaged files matching '--' 'src/'" phantom-pathspec info message (slu/slk/sli today) disappears — the split never leaves `--` in the pathspec list.

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
  -*) error "Unknown option: $arg (see 'hug sls -h')"; exit 2 ;;
  *) error "unexpected positional '$arg' — put pathspecs after '--'"; exit 2 ;;
  esac
done
pathspec_pathspecs_into pathspecs
```

Note: positionals before `--` were previously collected as pathspecs-by-coincidence; the contract makes them an error (unknown-flag loudness is the ratified flip; check each command's PR-A characterization row for the exact pinned today-behavior and flip only what the row pins).

- [ ] **Step 3:** Rows green. Commit: `feat: sls/slu/slk/sli adopt the uniform pathspec contract (#292)`

### Task 6: `output_json_status` chain plumbing

**Goal:** Pathspecs stop being discarded in the JSON chain; the call boundary honors `--`.

**Files:**
- Modify: `git-config/lib/hug-json` (`output_json_status`), `git-config/lib/hug-git-json` (`output_json_status_unified` at :141-144, `collect_git_files_json` list calls)
- Test: `tests/lib/test_hug_git_json.bats`, `tests/unit/test_status_staging.bats`

**Acceptance Criteria:**
- [ ] `output_json_status`'s parse loop (`:45-47`) collects pathspecs behind a `--` arm (a pathspec named `--cwd`/`--staged`-family is data — mirror `list_staged_files`' `--)` arm at `hug-git-files:40-49`)
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
- [ ] `hug us --` ≡ `hug us` output equality, fixture pinned to ≥1 staged file (non-vacuous), per gum-presence
- [ ] Both `files_to_unstage` branches receive the split's pathspecs (from-file/from-commit concat ANDs with them)

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats` → all pass

**Steps:**

- [ ] **Step 1:** Flip us's characterization rows red-first.
- [ ] **Step 2:** Hoist the split above the custom loop; feed both branches via `pathspec_pathspecs_into`; trailing bare `--` detected by the helper is simply not a positional (zero args → selector fallback, existing `git-us:144-158` path).
- [ ] **Step 3:** Green. Commit: `feat: us adopts the uniform pathspec contract (#292)`

### Task 9: `a` fix (#297) + scoped-picker arm + roster enrollment

**Goal:** `hug a -- <file>` stages exactly those files; bare trailing `--` keeps the picker; the picker is scoped when pathspecs precede it.

**Files:**
- Modify: `git-config/bin/git-a` (split at :132-167; picker branch :199-222)
- Test: `tests/unit/test_pathspec_conformance.bats` (flip `a` rows; arm the 4 sentinel-less loops at `:252/:305/:356/:532`; add `a` to `PATHSPEC_PICKER_ROWS:52`)

**Acceptance Criteria:**
- [ ] `hug a -- file.txt` stages exactly `file.txt` (red baseline: today ≡ `git add -u`); pre-`--` behavior byte-identical (existing `a` tests untouched and green)
- [ ] Bare `hug a --` → picker unchanged (HUG_INTERACTIVE_FILE_SELECTION path)
- [ ] Picker branch reads pathspecs via `pathspec_pathspecs_into` + `forward_pathspecs_to_picker`; `hug a -- src/ --` offers only `src/` candidates (cancelling stub — read-only by construction)
- [ ] `a`'s SELECTION semantics get a dedicated standalone test (mutating — not a shared-column cell)
- [ ] All 4 column loops gain `*)` sentinel arms (`__PSX_UNKNOWN_ROW__` breadcrumb) and `a` case arms in the capture columns

**Verify:** `make test-unit TEST_FILE=test_pathspec_conformance.bats` + `TEST_FILE=test_staging.bats` (or the `a` suite — locate via `grep -rln 'hug a ' tests/unit/`) → all pass

**Steps:**

- [ ] **Step 1:** Red-first: flip `a`'s characterization row (pathspec-drop) and add the scoped-picker row; arm the 4 loops' sentinels; run → FAIL.
- [ ] **Step 2:** Replace `git-a`'s ad-hoc handling: adopt `parse_common_flags_with_pathspecs --picker "$@"` — the mode flag MUST be the literal FIRST argument (the helper checks `${1:-}` only; appending it after `"$@"` makes `--picker` pathspec data and stages a file by that name). a IS on the picker list — the helper owns the export lifecycle; post-split positionals after `--` stage as explicit paths via `hug_add_with_summary "${paths[@]}"` (defined in `git-a:40` — it snapshots then `git add`s its args; VERIFY its internal `git add` call carries a protective `--` so a post-separator file named `-u` stays data, and add one if missing); the picker branch gains the two helper calls.
- [ ] **Step 3:** Green; full `make test-unit` (the `a` surface is high-traffic — run the whole unit tier, not just the conformance file). Commit: `feat: hug a honors pathspecs after --; scoped picker (#297)`

### Task 10: Doc perimeter

**Goal:** The full §7 doc sweep.

**Files:**
- Create: `git-config/lib/python/articles/pathspec.md` (the `:pathspec` article)
- Modify: per the pinned roster — PATH FILTERING blocks in `git-config/bin/git-{statusbase,sl,sla,sls,slu,slk,sli,slc,us,a,lc,lf,lcr,cmod,cmoda}`; `README.md` (`sl`/`sla` rows); `docs/commands/status-staging.md`; `docs/git-to-hug.md`; `git-config/lib/python/categories/{status,show,history}.toml`; `git-config/lib/README.md`; `docs/meta/hug-completion-reference.md`; `completions/hug-completion.bash` + `completions/hug.fish` (re-grep only)

**Acceptance Criteria:**
- [ ] `hug help :pathspec` serves the article (mechanism as `agents.md` — verify via an existing article's registration path if not automatic)
- [ ] Article covers: syntax, quoting + why, the `--` duality, magic passthrough, per-command support matrix, the edge cases from spec §7 (mid-stream second `--` phantom; trailing never phantom; `--`/`--help`-named files unreachable pre-separator; picker = separator spelling only); does NOT document `HUG_INTERACTIVE_FILE_SELECTION`
- [ ] All roster commands show the pointer block; single-file + PR-C commands NOT enrolled
- [ ] README `sl`/`sla` rows show `[-- <path>...]`; categories mention path filtering; `make docs-build` passes

**Verify:** `make docs-build` + `hug help :pathspec` (manual smoke) → article renders, build green

**Steps:**

- [ ] **Step 1:** Write the article (content outline = spec §7 first bullet; ~150 lines).
- [ ] **Step 2:** Sweep the roster's help blocks (2 lines + example, `git-sw:42-47` style).
- [ ] **Step 3:** Remaining doc edits per Files list. Commit: `docs: :pathspec article + full PR-B doc perimeter (#292, #298)`

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
