# `hug slc` — list conflicted (unmerged) files only — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `hug slc`, a purely additive sl* family command that lists only conflicted (unmerged) files — the native equivalent of `git diff --name-only --diff-filter=U`.

**Architecture:** Four layers, each mirroring an existing family pattern: (1) `list_conflicted_files` in `hug-git-files` (diff-filter=U list primitive, no dedup map needed — the filter dedups); (2) `--conflicts` include in `list_files_with_status` + a `_can_suppress_status` type-level gate extension (enables `-q` → plain paths, the `git-sli` convention); (3) a filter-conditional `conflicted` type in the unified JSON pipeline (`slu --json` stays byte-identical); (4) `git-slc`, a thin mirror of `git-sli`. Docs complete the sl* family page (sls/slu/slk are currently undocumented) and the agent-facing corpus.

**Tech Stack:** Bash (library functions + command scripts), BATS tests, GNU getopt-less arg parsing (family style), fish completions, VitePress docs.

**Spec:** `docs/superpowers/specs/2026-08-06-slc-conflicted-files-design.md` (commit `8e6e69f`, amended `6f2fade`). All git behaviors in it were empirically verified in scratch repos and independently reproduced by a code-roast pass (2026-08-06).

**Worktree:** `~/src/hug-scm.WT.feat-slc-conflicted-files` — do ALL work in here (`cd ~/src/hug-scm.WT.feat-slc-conflicted-files` first). Use `hug` for git operations; raw git is allowed only inside BATS test bodies (the block-commands hook scans the agent's shell commands, not test-file content).

**Conventions (non-negotiable):**
- Scripts keep work in library functions; scripts are thin layers (`git-config/bin/CLAUDE.md`).
- Never use `local` outside a function body (`git-config/bin/CLAUDE.md`).
- Library changes get elegant tests (`git-config/lib/CLAUDE.md`).
- Stdout/stderr discipline: data → stdout only; chatter (`info`, `hug s` summary) → stderr only (project CLAUDE.md).
- Commit messages follow the project WHY/WHAT/HOW/IMPACT structure (project CLAUDE.md).
- Verify with `make` targets only, never direct test invocation.

---

### Task 1: `list_conflicted_files` library function + lib tests

**Goal:** Add the conflict-listing primitive to `hug-git-files` with lib tests, mirroring `list_unstaged_files` minus its dedup map.

**Files:**
- Modify: `git-config/lib/hug-git-files` (insert after `list_unstaged_files`, which ends at line 190; also update the header comment at lines 6-9)
- Test: `tests/lib/test_hug-git-files.bats`

**Acceptance Criteria:**
- [ ] `list_conflicted_files` lists exactly the conflicted files (one per line, git-sorted)
- [ ] `list_conflicted_files --status` outputs `U\tfile` lines
- [ ] `list_conflicted_files --cwd` scopes to the current directory
- [ ] Pathspecs filter the listing
- [ ] No conflicts → empty output, exit 0
- [ ] New lib tests pass; existing lib tests pass

**Verify:** `make test-lib TEST_FILE=test_hug-git-files.bats TEST_SHOW_ALL_RESULTS=1` → all green (new + existing)

**Steps:**

- [ ] **Step 1: Update the file header comment** (lines 6-9)

Change:
```bash
# This library provides functions for:
# - Listing files by state (staged, unstaged, untracked, ignored, tracked)
```
to:
```bash
# This library provides functions for:
# - Listing files by state (staged, unstaged, untracked, ignored, conflicted, tracked)
```

- [ ] **Step 2: Add the conflict fixture helper to the test file**

In `tests/lib/test_hug-git-files.bats`, after the `create_test_repo_with_structure` helper (ends ~line 37), add:

```bash
# Helper: create a repo with a real merge conflict (one conflicted file)
create_test_repo_with_conflict() {
  local test_repo
  test_repo=$(create_test_repo)

  (
    cd "$test_repo" || exit 1

    echo "base" > conflict.txt
    git add conflict.txt
    git commit -q -m "Add base"

    git switch -q -c side
    echo "side" > conflict.txt
    git add conflict.txt
    git commit -q -m "Side change"

    git switch -q main
    echo "main" > conflict.txt
    git add conflict.txt
    git commit -q -m "Main change"

    # Leaves the repo in conflict state; exit 1 is the expected merge failure
    git merge --no-commit --no-ff side 2>/dev/null || true
  )

  echo "$test_repo"
}
```

Note: `create_test_repo` ECHOES the path — callers MUST capture it (`repo=$(create_test_repo_with_conflict)`). This helper also SETS no globals. Do not `git checkout` in new code — use `git switch` (same behavior, not blocked).

- [ ] **Step 3: Write the failing lib tests**

Append at the end of `tests/lib/test_hug-git-files.bats`:

```bash
@test "list_conflicted_files: lists exactly the conflicted files" {
  local repo
  repo=$(create_test_repo_with_conflict)
  cd "$repo"

  local output
  output=$(list_conflicted_files)
  [[ "$output" == "conflict.txt" ]]
}

@test "list_conflicted_files: --status outputs U status" {
  local repo
  repo=$(create_test_repo_with_conflict)
  cd "$repo"

  local output
  output=$(list_conflicted_files --status)
  [[ "$output" == $'U\tconflict.txt' ]]
}

@test "list_conflicted_files: pathspec scoping" {
  local repo
  repo=$(create_test_repo_with_conflict)
  cd "$repo"

  local output
  output=$(list_conflicted_files -- conflict.txt)
  [[ "$output" == "conflict.txt" ]]

  output=$(list_conflicted_files -- no-such-file.txt)
  [[ -z "$output" ]]
}

@test "list_conflicted_files: --cwd scopes to current directory" {
  local repo
  repo=$(create_test_repo_with_conflict)
  cd "$repo"
  mkdir -p sub
  cd sub

  local output
  output=$(list_conflicted_files --cwd)
  [[ -z "$output" ]]

  cd ..
  output=$(list_conflicted_files --cwd)
  [[ "$output" == "conflict.txt" ]]
}

@test "list_conflicted_files: empty output when no conflicts" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"

  local output
  output=$(list_conflicted_files)
  [[ -z "$output" ]]
}
```

- [ ] **Step 4: Run the tests — expect FAIL (function not defined)**

Run: `make test-lib TEST_FILE=test_hug-git-files.bats TEST_FILTER="list_conflicted_files" TEST_SHOW_ALL_RESULTS=1`
Expected: FAIL — `list_conflicted_files: command not found`

- [ ] **Step 5: Implement `list_conflicted_files`**

In `git-config/lib/hug-git-files`, insert immediately after `list_unstaged_files`'s closing brace (line 190, right before the `# Lists untracked files` comment at line 192):

```bash
# Lists conflicted (unmerged) files — files with unresolved merge/rebase conflicts
# Usage: mapfile -t files < <(list_conflicted_files [--status] [--cwd] [pathspecs...])
# Parameters:
#   --status - If provided, outputs "status\tfile" (one per line; status is always 'U')
#   --cwd    - If provided, scopes listing to current directory and subdirectories only
#   pathspecs - If provided, filters to only show conflicted files matching pathspecs
# Output:
#   File paths relative to current directory (one per line, or status\tfile if --status)
# Notes:
#   Always converts paths to current-directory-relative via GIT_PREFIX.
#   Uses `git diff --diff-filter=U` — the native "unmerged" filter, verified to list each
#   conflicted file exactly once, so NO dedup map is needed (list_unstaged_files needs its
#   U-over-M map because its unfiltered diff returns both U and M for the same file).
#   No --find-renames (the U filter never produces renames) and no --ignore-submodules=none
#   (unmerged gitlinks bypass submodule-ignore; verified 2026-08-06).
#   Empty output if no conflicts. Exit 0.
list_conflicted_files() {
    local with_status=false
    local scope_cwd=false
    local -a pathspecs=()

    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status)
                with_status=true
                shift
                ;;
            --cwd)
                scope_cwd=true
                shift
                ;;
            *)
                # Treat remaining arguments as pathspecs
                pathspecs+=("$1")
                shift
                ;;
        esac
    done

    check_git_repo

    # Build git command with optional scoping
    local -a git_cmd_base=("git" "diff" "--diff-filter=U")
    if $with_status; then
        git_cmd_base+=("--name-status")
    else
        git_cmd_base+=("--name-only")
    fi

    # Add pathspecs if provided, otherwise use directory scoping if requested
    if [[ ${#pathspecs[@]} -gt 0 ]]; then
        git_cmd_base+=("--" "${pathspecs[@]}")
    elif $scope_cwd; then
        git_cmd_base+=("--" ".")
    fi

    if $with_status; then
        local -a lines=()
        mapfile -t lines < <("${git_cmd_base[@]}" 2>/dev/null || true)
        for line in "${lines[@]}"; do
            [[ -z "$line" ]] && continue
            local status file
            IFS=$'\t' read -r status file <<< "$line"
            [[ -z "$file" ]] && continue
            local -a single=("$file")
            convert_to_relative_paths single
            printf '%s\t%s\n' "$status" "${single[0]}"
        done
    else
        local -a paths=()
        mapfile -t paths < <("${git_cmd_base[@]}" 2>/dev/null || true)
        # Always convert to current-dir relative paths
        convert_to_relative_paths paths
        printf '%s\n' "${paths[@]}"
    fi
}
```

Note: the `--status` branch parses `status\tfile` directly — no R/C handling needed because `--diff-filter=U` can never emit rename/copy entries (the diff machinery only classifies renames for `M`/`A` candidates; unmerged entries are always `U`).

- [ ] **Step 6: Run the tests — expect PASS**

Run: `make test-lib TEST_FILE=test_hug-git-files.bats TEST_SHOW_ALL_RESULTS=1`
Expected: all 5 new tests + existing tests pass

- [ ] **Step 7: Commit**

```bash
cd ~/src/hug-scm.WT.feat-slc-conflicted-files
hug a git-config/lib/hug-git-files tests/lib/test_hug-git-files.bats
hug c -m "feat: add list_conflicted_files primitive for hug slc

WHY: No native command lists only conflicted (unmerged) files. The
list primitive is the first layer of `hug slc` (elifarley/hug-scm#244).

WHAT: list_conflicted_files in hug-git-files — git diff --diff-filter=U
with --status/--cwd/pathspecs, mirroring list_unstaged_files.

HOW: --diff-filter=U returns each unmerged file exactly once, so no
U-over-M dedup map is needed (unlike list_unstaged_files, whose
unfiltered diff returns both). No --find-renames (U never produces
renames), no --ignore-submodules=none (unmerged gitlinks bypass
submodule-ignore — verified empirically).

IMPACT: Scriptable conflict listing primitive; foundation for the slc
command, renderer, and JSON layers.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Renderer `--conflicts` include + `_can_suppress_status` gate

**Goal:** Teach `list_files_with_status` a `--conflicts` include (rendering `Cnflt` via the existing formatter) and make conflicts-only suppress-status-safe.

**Files:**
- Modify: `git-config/lib/hug-select-files` (doc comment lines 11-31; `_can_suppress_status` lines 106-134; `list_files_with_status` lines 164-387)
- Test: `tests/lib/test_hug-select-files.bats`

**Acceptance Criteria:**
- [ ] `list_files_with_status --conflicts` renders `Cnflt <file>` lines (priority-sorted)
- [ ] `list_files_with_status --conflicts --suppress-status` prints plain paths (suppression is safe for conflicts-only)
- [ ] `_can_suppress_status` returns 0 for conflicts-only, 1 for conflicts+staged
- [ ] No conflicts → returns 1, empty output
- [ ] Existing `git-sli`/`git-slk` `-q` behavior unchanged (regression)

**Verify:** `make test-lib TEST_FILE=test_hug-select-files.bats TEST_SHOW_ALL_RESULTS=1` + `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="hug sli|hug slk" TEST_SHOW_ALL_RESULTS=1` → all green

**Steps:**

- [ ] **Step 1: Update the doc comment** (lines 11-31)

Add `--conflicts` to the `list_files_with_status` options block (after the `--ignored` line, ~line 16):
```bash
#   --conflicts          Include conflicted (unmerged) files
```

- [ ] **Step 2: Extend `_can_suppress_status`** (lines 106-134)

Replace the whole function (lines 106-134) with:

```bash
# Helper: Check if we can safely suppress status column
# Returns 0 (true) if safe, 1 (false) if not safe
# Usage: if _can_suppress_status "$include_staged" "$include_unstaged" "$include_untracked" "$include_ignored" "$include_conflicts" "${status_codes[@]}"; then ...
_can_suppress_status() {
  local include_staged="$1"
  local include_unstaged="$2"
  local include_untracked="$3"
  local include_ignored="$4"
  local include_conflicts="$5"
  shift 5
  local -a status_codes=("$@")

  # Must have exactly one file type
  local type_count=0
  $include_staged && ((type_count++))
  $include_unstaged && ((type_count++))
  $include_untracked && ((type_count++))
  $include_ignored && ((type_count++))
  $include_conflicts && ((type_count++))

  [[ $type_count -ne 1 ]] && return 1

  # Only single-status-type listings are safe to suppress:
  # untracked, ignored, and conflicts (Cnflt is the sole conflict status).
  # This is a TYPE-LEVEL gate — it does not inspect status_codes (the
  # parameter is currently unused). Staged and unstaged span multiple
  # status types and are never safe.
  $include_untracked && return 0
  $include_ignored && return 0
  $include_conflicts && return 0

  return 1
}
```

- [ ] **Step 3: Extend `list_files_with_status`**

Edit 1 — add the flag variable (after `local include_ignored=false`, ~line 177):
```bash
  local include_conflicts=false
```

Edit 2 — add the arg case (after the `--ignored)` case, ~line 197-200):
```bash
      --conflicts)
        include_conflicts=true
        shift
        ;;
```

Edit 3 — include it in `has_includes` (~line 218):
```bash
  if $include_staged || $include_unstaged || $include_untracked || $include_ignored || $include_conflicts; then
    has_includes=true
  fi
```

Edit 4 — add the collection block (after the `include_unstaged` block, which ends ~line 275):
```bash
    if $include_conflicts; then
      local -a status_flags=("${list_flags[@]}" "--status")
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local status file
        IFS=$'\t' read -r status file <<< "$line"
        local status_text status_code
        IFS=$'\t' read -r status_text status_code <<< "$(_format_unstaged_status "$status")"
        files+=("$file")
        if $suppress_status; then
          formatted_options+=("$file")
        else
          formatted_options+=("${status_text} ${file}")
        fi
        status_codes+=("$status_code")
      done < <(list_conflicted_files "${status_flags[@]}" "${pathspecs[@]}")
    fi
```

Edit 5 — pass the new arg to `_can_suppress_status` (the call at ~line 312):
```bash
      if ! _can_suppress_status "$include_staged" "$include_unstaged" "$include_untracked" "$include_ignored" "$include_conflicts" "${status_codes[@]}"; then
```

- [ ] **Step 4: Write the failing lib tests**

Append to `tests/lib/test_hug-select-files.bats` (after the existing "conflict files show U status in unstaged files" test, ~line 239; the file's `create_merge_conflict` fixture at ~line 195 already exists — reuse it):

```bash
@test "list_files_with_status: --conflicts renders Cnflt-prefixed conflict files" {
  create_merge_conflict

  local output
  output=$(list_files_with_status --conflicts)
  [[ "$output" == *"Cnflt"*"conflict-file.txt"* ]]
}

@test "list_files_with_status: --conflicts --suppress-status prints plain paths" {
  create_merge_conflict

  local output
  output=$(list_files_with_status --conflicts --suppress-status)
  [[ "$output" == "conflict-file.txt" ]]
}

@test "list_files_with_status: --conflicts is empty and fails when no conflicts" {
  local output
  output=$(list_files_with_status --conflicts 2>/dev/null)
  [[ -z "$output" ]]

  run list_files_with_status --conflicts 2>/dev/null
  [[ $status -eq 1 ]]
}

@test "_can_suppress_status: conflicts-only is suppress-safe" {
  _can_suppress_status false false false false true
  [[ $? -eq 0 ]]
}

@test "_can_suppress_status: conflicts mixed with staged is not safe" {
  _can_suppress_status true false false false true
  [[ $? -ne 0 ]]
}
```

Note: the last two tests use `[[ $? -eq ... ]]` immediately after the call (no command between), matching the file's assertion style.

- [ ] **Step 5: Run the tests — expect FAIL (unknown option)**

Run: `make test-lib TEST_FILE=test_hug-select-files.bats TEST_FILTER="--conflicts|_can_suppress_status" TEST_SHOW_ALL_RESULTS=1`
Expected: FAIL — `--conflicts` treated as a pathspec (no output match)

- [ ] **Step 6: Apply Step 3's five edits — then run tests — expect PASS**

Run: `make test-lib TEST_FILE=test_hug-select-files.bats TEST_SHOW_ALL_RESULTS=1`
Expected: 5 new tests + existing tests pass

- [ ] **Step 7: Regression — sli/slk -q still suppress status**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="hug sli|hug slk" TEST_SHOW_ALL_RESULTS=1`
Expected: all pass (the `_can_suppress_status` signature change didn't break the existing suppress-safe callers)

- [ ] **Step 8: Commit**

```bash
cd ~/src/hug-scm.WT.feat-slc-conflicted-files
hug a git-config/lib/hug-select-files tests/lib/test_hug-select-files.bats
hug c -m "feat: add --conflicts include to list_files_with_status

WHY: The slc command needs a renderer path that marks conflicts with the
family's Cnflt marker and supports -q plain-path mode (elifarley/hug-scm#244).

WHAT: --conflicts include in list_files_with_status (collects via
list_conflicted_files --status, renders _format_unstaged_status U);
_can_suppress_status gains an include_conflicts parameter and treats
conflicts-only as suppress-safe.

HOW: The gate is TYPE-LEVEL, not substate-based: safe types are
hardcoded (untracked/ignored/conflicts); status_codes is currently
unused. Staged/unstaged span multiple status types and stay unsafe.

IMPACT: Renders Cnflt (priority 90) via existing machinery; enables
hug slc -q plain-path scripting.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: JSON `conflicted` filter type

**Goal:** Plumb a filter-conditional `conflicted` type through `output_json_status` → `output_json_status_unified` → `collect_git_files_json`, keeping existing JSON output byte-identical.

**Files:**
- Modify: `git-config/lib/output_json_status` (parse loop lines 10-44; filter assembly lines 49-65)
- Modify: `git-config/lib/hug-git-json` (`collect_git_files_json` case line 70-81; `output_json_status_unified` lines 103-233)
- Test: `tests/lib/test_hug_git_json.bats`

**Acceptance Criteria:**
- [ ] `output_json_status --conflicts` routes to filter type `conflicted`
- [ ] `collect_git_files_json "conflicted"` returns objects with `"status": "conflict"`
- [ ] `output_json_status_unified` with `--filter conflicted` emits `summary.conflicted` + `conflicted` array; `total` includes conflicted
- [ ] Default filter (no `--conflicts`) emits NO `conflicted` key — `slu --json`/`sls --json` byte-identical (asserted by existing tests)
- [ ] `hug s --json` untouched (separate emitter `output_json_status_summary` — no changes there)

**Verify:** `make test-lib TEST_FILE=test_hug_git_json.bats TEST_SHOW_ALL_RESULTS=1` + `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="supports JSON" TEST_SHOW_ALL_RESULTS=1` → all green

**Steps:**

- [ ] **Step 1: Write the failing lib test**

Append to `tests/lib/test_hug_git_json.bats`, following the file's existing per-test pattern (each test calls `source_hug_json_libs` then creates its own repo — see the "collects staged files correctly" test at line 75):

```bash
@test "collect_git_files_json: collects conflicted files with conflict status" {
  local TEST_REPO
  source_hug_json_libs  # Source libraries before cd
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO" || return 1

  # Build a real merge conflict (raw git is fine inside tests)
  echo "base" > conflict-file.txt
  git add conflict-file.txt
  git commit -q -m "Add base"
  git switch -q -c branch1
  echo "branch1 change" > conflict-file.txt
  git add conflict-file.txt
  git commit -q -m "Change on branch1"
  git switch -q main
  echo "branch2 change" > conflict-file.txt
  git add conflict-file.txt
  git commit -q -m "Change on branch2"
  git merge --no-commit --no-ff branch1 2>/dev/null || true

  run collect_git_files_json "conflicted"
  assert_success
  echo "$output" | grep -q '"path".*"conflict-file.txt"'
  echo "$output" | grep -q '"status".*"conflict"'
}
```

- [ ] **Step 2: Run the test — expect FAIL (unknown file type)**

Run: `make test-lib TEST_FILE=test_hug_git_json.bats TEST_FILTER="conflicted" TEST_SHOW_ALL_RESULTS=1`
Expected: FAIL — empty output (`"conflicted"` falls through the case with no branch)

- [ ] **Step 3: Extend `collect_git_files_json`** (`hug-git-json` line 70-81)

Change:
```bash
  case "$file_type" in
  "staged" | "unstaged")
```
to:
```bash
  case "$file_type" in
  "staged" | "unstaged" | "conflicted")
```

No other change needed in this function: `local list_func="list_${file_type}_files"` resolves to `list_conflicted_files` for `"conflicted"`, and `parse_file_to_json` already maps `U` → `"conflict"` (`hug-git-json:27`).

- [ ] **Step 4: Extend `output_json_status`** (`git-config/lib/output_json_status`)

Edit 1 — add the flag variable (after `local include_ignored=false`, ~line 14):
```bash
  local include_conflicts=false
```

Edit 2 — add the arg case (after the `--ignored)` case, ~line 31-35):
```bash
    --conflicts)
      include_conflicts=true
      shift
      ;;
```

Edit 3 — extend the filter assembly (after the ignored block, ~line 59-62):
```bash
  if $include_conflicts; then
    filter_types+="conflicted,"
  fi
```

Note: pathspecs are deliberately NOT parsed here — `hug slc --json <path>` returns all conflicts, a documented family-consistent contract (spec §3). Do not "fix" this.

- [ ] **Step 5: Extend `output_json_status_unified`** (`hug-git-json` lines 103-233)

Edit 1 — add the array (after `local -a ignored_files=()`, ~line 140):
```bash
  local -a conflicted_files=()
```

Edit 2 — add the collection block (after the ignored block, ~line 160-164):
```bash
  if [[ "$filter_types" == *"conflicted"* ]]; then
    local result
    result="$(collect_git_files_json "conflicted" "${list_flags[@]}")"
    [[ -n "$result" ]] && IFS=',' read -ra conflicted_files <<< "$result"
  fi
```

Edit 3 — replace the summary build (lines 166-173) with a filter-conditional version:
```bash
  # Build summary. The four legacy keys are ALWAYS present (unchanged
  # behavior); "conflicted" is filter-conditional so slu/sls/slk/sli --json
  # output stays byte-identical to today.
  local total=$(( ${#staged_files[@]} + ${#unstaged_files[@]} + ${#untracked_files[@]} + ${#ignored_files[@]} ))
  local -a summary_args=(
    "staged" "${#staged_files[@]}"
    "unstaged" "${#unstaged_files[@]}"
    "untracked" "${#untracked_files[@]}"
    "ignored" "${#ignored_files[@]}"
  )
  if [[ "$filter_types" == *"conflicted"* ]]; then
    total=$(( total + ${#conflicted_files[@]} ))
    summary_args+=("conflicted" "${#conflicted_files[@]}")
  fi
  summary_args+=("total" "$total")
  local summary
  summary=$(to_json_object "${summary_args[@]}")
```

Edit 4 — add the array emission (after the ignored `add_file_array` block, ~line 222-224):
```bash
  if [[ "$filter_types" == *"conflicted"* ]]; then
    add_file_array "conflicted" "${conflicted_files[@]}"
  fi
```

- [ ] **Step 6: Run the tests — expect PASS + regression**

Run: `make test-lib TEST_FILE=test_hug_git_json.bats TEST_SHOW_ALL_RESULTS=1`
Expected: new test + existing tests pass

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="supports JSON" TEST_SHOW_ALL_RESULTS=1`
Expected: existing `sls`/`slu`/`slk`/`sli` JSON tests pass unchanged (byte-identity proof at the command level)

- [ ] **Step 7: Commit**

```bash
cd ~/src/hug-scm.WT.feat-slc-conflicted-files
hug a git-config/lib/output_json_status git-config/lib/hug-git-json tests/lib/test_hug_git_json.bats
hug c -m "feat: add filter-conditional conflicted type to the JSON pipeline

WHY: hug slc --json must mirror the sl family's unified JSON envelope
(elifarley/hug-scm#244).

WHAT: --conflicts flag in output_json_status; a conflicted case in
collect_git_files_json (list_${type}_files resolves to
list_conflicted_files; parse_file_to_json already maps U -> conflict);
conflicted collection + filter-conditional summary key and array in
output_json_status_unified.

HOW: summary.conflicted and the conflicted array appear ONLY when the
filter requests them; the four legacy keys stay always-present, so
slu/sls/slk/sli --json output is byte-identical to today. hug s --json
uses a separate emitter and is untouched.

IMPACT: Machine-clean conflict listings; zero regressions in existing
JSON consumers.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: `git-slc` command + unit tests

**Goal:** Ship the `hug slc` command (thin mirror of `git-sli`) driven by 10 BATS tests covering the spec's §8.1 matrix.

**Files:**
- Create: `git-config/bin/git-slc` (chmod +x)
- Test: `tests/unit/test_status_staging.bats`

**Acceptance Criteria:**
- [ ] `hug slc` lists only conflicted paths with `Cnflt` prefix; excludes unstaged-non-conflict and staged files
- [ ] `hug slc -q` prints plain paths only (no prefix, no summary)
- [ ] No conflicts → empty stdout, exit 0, `info` on stderr only
- [ ] `hug slc --json` parses; `summary.conflicted` correct; entries `"status": "conflict"`
- [x] Pathspec scoping works in text mode; `--json` ignores pathspecs (documented contract)
  - **Flipped by PR-B** ([elifarley/hug-scm#298](https://github.com/elifarley/hug-scm/pull/298), uniform pathspec contract [elifarley/hug-scm#292](https://github.com/elifarley/hug-scm/issues/292)): scoping now applies to `--json` too — the text above records the contract as ratified at design time (2026-08-06), kept for history.
- [ ] `-q` suppresses trailing `hug s`; non-quiet shows it (stderr)
- [ ] `HUG_QUIET=T` → plain paths, no summary
- [ ] `hug slc --json -q` → JSON wins
- [ ] Gitlink conflict (`UU inner`) listed
- [ ] All 10 tests + existing tests green

**Verify:** `make test-unit TEST_FILE=test_status_staging.bats TEST_SHOW_ALL_RESULTS=1` → all green

**Steps:**

- [ ] **Step 1: Write the conflict fixture helper**

In `tests/unit/test_status_staging.bats`, after the `teardown()` (line 13), add:

```bash
# Helper: repo with a real merge conflict (hug mkeep), plus a staged file and a
# cleanly-merged file, so slc's exactness is observable. Leaves the repo in
# conflict state. Callers must capture: repo=$(create_slc_conflict_fixture)
create_slc_conflict_fixture() {
  local test_repo
  test_repo=$(create_test_repo)

  (
    cd "$test_repo" || exit 1

    echo "base" > conflict.txt
    echo "base" > side-only.txt
    git add -A
    git commit -q -m "Add base files"

    git switch -q -c side
    echo "side" > conflict.txt
    echo "side" > side-only.txt
    git add -A
    git commit -q -m "Side changes"

    git switch -q main
    echo "main" > conflict.txt
    git add conflict.txt
    git commit -q -m "Main change"

    echo "staged" > staged.txt
    git add staged.txt
  )

  echo "$test_repo"
}
```

- [ ] **Step 2: Write the failing unit tests**

Append to `tests/unit/test_status_staging.bats` (after the existing sl-family tests):

```bash
@test "hug slc: lists only conflicted files" {
  local repo
  repo=$(create_slc_conflict_fixture)
  cd "$repo"

  # Merge side into main: conflict.txt conflicts; side-only.txt merges cleanly;
  # staged.txt stays staged (no overlap).
  run hug mkeep side -m "merge side"
  assert_failure  # merge conflict expected

  run hug slc
  assert_success
  assert_output --partial "Cnflt"
  assert_output --partial "conflict.txt"
  refute_output --partial "side-only.txt"
  refute_output --partial "staged.txt"
}

@test "hug slc -q: prints plain paths only" {
  local repo
  repo=$(create_slc_conflict_fixture)
  cd "$repo"
  run hug mkeep side -m "merge side"
  assert_failure

  run hug slc -q
  assert_success
  [[ "$output" == "conflict.txt" ]]
}

@test "hug slc: no conflicts gives empty stdout, exit 0, info on stderr" {
  local clean_repo
  clean_repo=$(create_test_repo)
  cd "$clean_repo"

  run hug slc 2>/dev/null
  assert_success
  [[ -z "$output" ]]

  run hug slc 2>&1 1>/dev/null
  assert_success
  assert_output --partial "No conflicted files."
}

@test "hug slc --json: valid JSON with conflicted summary" {
  local repo
  repo=$(create_slc_conflict_fixture)
  cd "$repo"
  run hug mkeep side -m "merge side"
  assert_failure

  run hug slc --json
  assert_success

  # Zero non-JSON bytes: json.tool must parse the whole output
  run bash -c "printf '%s' \"\$1\" | python3 -m json.tool > /dev/null" _ "$output"
  assert_success

  run python3 -c "import json,sys; print(json.loads(sys.argv[1])['summary']['conflicted'])" "$output"
  assert_output "1"

  assert_output --partial '"status": "conflict"'
  assert_output --partial '"conflict.txt"'
}

@test "hug slc with pathspec scoping" {
  local repo
  repo=$(create_slc_conflict_fixture)
  cd "$repo"
  run hug mkeep side -m "merge side"
  assert_failure

  run hug slc conflict.txt
  assert_success
  assert_output --partial "conflict.txt"

  run hug slc no-such-file.txt 2>/dev/null
  assert_success
  [[ -z "$output" ]]

  run hug slc no-such-file.txt 2>&1 1>/dev/null
  assert_output --partial "No conflicted files matching 'no-such-file.txt' found."
}

@test "hug slc: -q suppresses the trailing summary; non-quiet shows it" {
  local repo
  repo=$(create_slc_conflict_fixture)
  cd "$repo"
  run hug mkeep side -m "merge side"
  assert_failure

  run hug slc 2>&1 1>/dev/null
  assert_success
  assert_output --partial "HEAD"  # hug s summary chatter on stderr

  run hug slc -q 2>&1 1>/dev/null
  assert_success
  [[ -z "$output" ]]
}

@test "hug slc: lists conflicted submodule pointers (gitlink)" {
  local outer_repo
  outer_repo=$(create_test_repo)
  cd "$outer_repo"

  # Embedded repo at inner/ — NOT `git submodule add` (git >= 2.38 blocks the
  # file protocol without -c protocol.file.allow=always).
  mkdir inner
  (
    cd inner
    git init -q -b main
    git config user.name "Test User"
    git config user.email "test@example.com"
    echo i1 > i.txt
    git add -A
    git commit -q -m "inner base"
  )
  git add inner
  git commit -q -m "Add submodule pointer"
  git branch side

  # main bumps the pointer
  (
    cd inner
    echo i2 > i.txt
    git add -A
    git commit -q -m "inner main bump"
  )
  git add inner
  git commit -q -m "Bump pointer on main"

  # side bumps a genuinely divergent pointer (rewind inner to its base first)
  git switch -q side
  (
    cd inner
    git reset -q --hard HEAD~1
    echo i3 > i.txt
    git add -A
    git commit -q -m "inner side bump"
  )
  git add inner
  git commit -q -m "Bump pointer on side"

  # merge → gitlink conflict (UU inner)
  git switch -q main
  run hug mkeep side -m "merge side"
  assert_failure

  run hug slc
  assert_success
  assert_output --partial "inner"
}

# [PR-B ANNOTATION 2026-08-18] HISTORICAL QUOTE — do not edit below.
# This embedded test is the pre-PR-B verbatim copy of the
# test_status_staging.bats row; flipped by PR-B (elifarley/hug-scm#298,
# uniform pathspec contract): pathspecs now scope `--json`. Kept verbatim
# as the record of the original contract.
@test "hug slc --json: pathspecs are ignored (documented contract)" {
  local repo
  repo=$(create_slc_conflict_fixture)
  cd "$repo"
  run hug mkeep side -m "merge side"
  assert_failure

  # A pathspec that matches nothing must NOT filter the JSON output
  run hug slc --json no-such-file.txt
  assert_success
  run python3 -c "import json,sys; print(json.loads(sys.argv[1])['summary']['conflicted'])" "$output"
  assert_output "1"
  assert_output --partial '"conflict.txt"'
}

@test "hug slc: HUG_QUIET=T prints plain paths, no summary" {
  local repo
  repo=$(create_slc_conflict_fixture)
  cd "$repo"
  run hug mkeep side -m "merge side"
  assert_failure

  HUG_QUIET=T run hug slc
  assert_success
  [[ "$output" == "conflict.txt" ]]
}

@test "hug slc --json -q: JSON wins" {
  local repo
  repo=$(create_slc_conflict_fixture)
  cd "$repo"
  run hug mkeep side -m "merge side"
  assert_failure

  run hug slc --json -q
  assert_success
  run bash -c "printf '%s' \"\$1\" | python3 -m json.tool > /dev/null" _ "$output"
  assert_success
  assert_output --partial '"conflict.txt"'
}
```

- [ ] **Step 3: Run the tests — expect FAIL (command not found)**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="hug slc" TEST_SHOW_ALL_RESULTS=1`
Expected: FAIL — `git-slc: command not found`

- [ ] **Step 4: Create `git-config/bin/git-slc`** (mirror of `git-sli`)

Create the file with this exact content:

```bash
#!/usr/bin/env bash
_hug_category='["status"]'
_hug_keywords='["conflict","unmerged","merge","rebase"]'
test "${1:-}" = '--search-meta' && {
  printf 'category = %s\nkeywords = %s\n' "$_hug_category" "$_hug_keywords"
  exit 0
}
CMD_BASE="$(readlink -f "$0" 2> /dev/null || greadlink -f "$0")" || CMD_BASE="$0"
CMD_BASE="$(dirname "$CMD_BASE")"
for f in hug-common hug-git-kit hug-select-files output_json_status; do . "$CMD_BASE/../lib/$f"; done
set -euo pipefail

# Part of the Hug tool suite

# Show only conflicted (unmerged) files, then summary

# Early exit if not in Git repo
check_git_repo

# Parse arguments
json_output=false
quiet=false
if [[ ${HUG_QUIET:-} == T ]]; then
  quiet=true
fi
pathspecs=()
for arg in "$@"; do
  case "$arg" in
  --json)
    json_output=true
    ;;
  -q | --quiet)
    quiet=true
    ;;
  *)
    # Treat remaining arguments as pathspecs
    pathspecs+=("$arg")
    ;;
  esac
done

# Build list_files_with_status options for conflicted files only
list_opts=("--conflicts")

# Pass suppress-status flag when in quiet mode
# (single-status-type listing — suppression is safe, same as git-sli/git-slk)
if $quiet; then
  list_opts+=("--suppress-status")
fi

# Add pathspecs if provided
if [[ ${#pathspecs[@]} -gt 0 ]]; then
  list_opts+=("${pathspecs[@]}")
fi

# JSON output mode
if $json_output; then
  output_json_status "${list_opts[@]}"
else
  # Show conflicted files
  if ! list_files_with_status "${list_opts[@]}" 2> /dev/null; then
    if [[ ${#pathspecs[@]} -gt 0 ]]; then
      pathspec_list=""
      printf -v pathspec_list "'%s' " "${pathspecs[@]}"
      info "No conflicted files matching ${pathspec_list% } found."
    else
      info "No conflicted files."
    fi
  fi

  # Show summary line (unless quiet mode)
  if ! $quiet; then
    exec hug s
  fi
fi
```

Then make it executable:
```bash
chmod +x git-config/bin/git-slc
```

Notes:
- `--json` + pathspecs: `output_json_status` drops them by design (documented contract, spec §3).
- The trailing `hug s` writes to stderr (verified `git-s:542`) — stdout stays pipe-safe.
- No `show_help` — the family gets help via `hug help` category meta (`_hug_category`/`_hug_keywords`).

- [ ] **Step 5: Run the tests — expect PASS**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_SHOW_ALL_RESULTS=1`
Expected: 10 new tests + all existing tests pass

- [ ] **Step 6: Commit**

```bash
cd ~/src/hug-scm.WT.feat-slc-conflicted-files
hug a git-config/bin/git-slc tests/unit/test_status_staging.bats
hug c -m "feat: add hug slc — list conflicted (unmerged) files only

WHY: During a merge/rebase conflict no native command lists conflicts
only; slu interleaves them with unstaged modifications, forcing
shell post-processing. Conflict state is the highest-stakes
working-tree state (elifarley/hug-scm#244).

WHAT: git-slc — a thin mirror of git-sli backed by --diff-filter=U:
- hug slc: Cnflt-prefixed conflicted paths + trailing hug s summary
- hug slc -q: plain paths only (suppress-status, no summary) — scriptable
- hug slc --json: unified envelope via the conflicted filter type
- pathspecs scope text mode; --json ignores them (documented contract)

HOW: Follows the git-sli/git-slk convention for single-status-type
listings; verified behavior: --diff-filter=U lists each unmerged file
exactly once (no dedup needed) and surfaces unmerged gitlinks.

IMPACT: One-word native answer to 'which files are in conflict?',
pipe-safe and scriptable; foundation for conflict-UX follow-ups.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Fish completions

**Goal:** Register `slc` and fix the pre-existing `slu`/`slk` gap in the fish completion file.

**Files:**
- Modify: `completions/hug.fish` (line 119 `hug_tops`; line 238 status-options group)

**Acceptance Criteria:**
- [ ] `slc`, `slu`, `slk` present in `hug_tops`
- [ ] `slc`, `slu`, `slk` in the status-options `for sub in ...` group (get `$common_status_opts`)
- [ ] Bash completion untouched (auto-discovers scripts)

**Verify:** `grep -c 'slc' completions/hug.fish` → 2 (tops + group); `grep -c 'slu' completions/hug.fish` → 2; no bash-completion diff

**Steps:**

- [ ] **Step 1: Edit `hug_tops`** (line 119)

Change:
```fish
set -l hug_tops alias l ll lla la llf llfp llfs lf lc lcr lau ld lp lo lol fblame fb fcon fa fborn a aa ai ap us usa untrack back undo rollback rewind squash restore files wip wips unwip get ca cmod cmoda cii cim o cc caa sls sl sla sli s ss su sw sx sh shp shc shf t tc ta ts tr tm tma tpush tpull tpullf tdel tdelr tco twc twp b bs bl bll bla blr bc br bdel bdelf bdelr bwc bwp bwnc bwm bwnm bpush rb rbi rbc rba rbs m mff mkeep ma bpull bpullr pullall type dump remote2ssh h w c statusbase hughelp log-outgoing
```
to (insert `slc`, `slu`, `slk` in the sl cluster):
```fish
set -l hug_tops alias l ll lla la llf llfp llfs lf lc lcr lau ld lp lo lol fblame fb fcon fa fborn a aa ai ap us usa untrack back undo rollback rewind squash restore files wip wips unwip get ca cmod cmoda cii cim o cc caa sls slc slu sla slk sli s ss su sw sx sh shp shc shf t tc ta ts tr tm tma tpush tpull tpullf tdel tdelr tco twc twp b bs bl bll bla blr bc br bdel bdelf bdelr bwc bwp bwnc bwm bwnm bpush rb rbi rbc rba rbs m mff mkeep ma bpull bpullr pullall type dump remote2ssh h w c statusbase hughelp log-outgoing
```

- [ ] **Step 2: Edit the status-options group** (line 238)

Change:
```fish
for sub in sl sla sli statusbase
```
to:
```fish
for sub in sl slc slu sla slk sli statusbase
```

- [ ] **Step 3: Verify + commit**

Run: `grep -c 'slc' completions/hug.fish` → 2; `grep -c 'slu' completions/hug.fish` → 2; `grep -c 'slk' completions/hug.fish` → 2

```bash
cd ~/src/hug-scm.WT.feat-slc-conflicted-files
hug a completions/hug.fish
hug c -m "chore: add slc and fix slu/slk gap in fish completions

WHY: fish completions have an explicit command list; slc was missing
and slu/slk were a pre-existing gap (elifarley/hug-scm#244).

WHAT: slc/slu/slk in hug_tops and in the status-options group
(common_status_opts). Bash completions auto-discover scripts — untouched.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: Documentation

**Goal:** Complete the sl* family documentation across the five enumerated surfaces so `slc` (and its missing siblings) are discoverable everywhere.

**Files:**
- Modify: `docs/commands/status-staging.md` (Quick Reference ~:28-40; family detail section ~:106-113)
- Modify: `git-config/lib/python/articles/agents.md` (~:124-131)
- Modify: `docs/git-to-hug.md` (~:46-48)
- Modify: `README.md` (~:329-339)
- Modify: `docs/meta/hug-completion-reference.md` (~:88-91)

**Acceptance Criteria:**
- [ ] status-staging.md Quick Reference lists sls/slu/slk/slc; family detail section documents all four in the existing block style
- [ ] agents.md "Listing commands" includes `hug slc`: conflict only
- [ ] git-to-hug.md has `git diff --name-only --diff-filter=U` → `hug slc`
- [ ] README Status & Staging code block includes `hug slc`
- [ ] hug-completion-reference.md lists slu/slk/slc in the same format as sla/sli
- [ ] `make docs-build` succeeds

**Verify:** `grep -l 'slc' docs/commands/status-staging.md git-config/lib/python/articles/agents.md docs/git-to-hug.md README.md docs/meta/hug-completion-reference.md` → all five; `make docs-build` → success

**Steps:**

- [ ] **Step 1: `docs/commands/status-staging.md` — Quick Reference table**

After the `hug sla` row (~line 31), add:
```markdown
| `hug sls` | **S**tatus + **L**ist **S**taged | Status with staged files only |
| `hug slu` | **S**tatus + **L**ist **U**nstaged | Status with unstaged files only |
| `hug slk` | **S**tatus + **L**ist untrac**K**ed | Status with untracked files only |
| `hug slc` | **S**tatus + **L**ist **C**onflicts | Status with conflicted (unmerged) files only |
```

- [ ] **Step 2: `docs/commands/status-staging.md` — family detail section**

After the `hug sli` block (ends ~line 113, before the `> **Related:**` note), add:

```markdown
- `hug sls`: **S**tatus + **L**ist **S**taged
    - **Description**: Status with staged files only.
    - **Example**: `hug sls`
    - **Safety**: ✅ Read-only.

- `hug slu`: **S**tatus + **L**ist **U**nstaged
    - **Description**: Status with unstaged files only (includes conflicted files, marked `Cnflt`).
    - **Example**: `hug slu`
    - **Safety**: ✅ Read-only.

- `hug slk`: **S**tatus + **L**ist untrac**K**ed
    - **Description**: Status with untracked files only.
    - **Example**: `hug slk`
    - **Safety**: ✅ Read-only.

- `hug slc`: **S**tatus + **L**ist **C**onflicts
    - **Description**: Status with conflicted (unmerged) files only — the native equivalent of `git diff --name-only --diff-filter=U`. Use `-q` for plain paths (scripting).
    - **Example**: `hug slc`
    - **Safety**: ✅ Read-only.
```

- [ ] **Step 3: `git-config/lib/python/articles/agents.md`**

In the "Listing commands" list (~line 127), after the `hug slu` line, add:
```markdown
- `hug slc`: conflict only  (e.g. `Cnflt conflict.txt`)
```

- [ ] **Step 4: `docs/git-to-hug.md`**

After the `git diff HEAD` row (~line 48), add:
```markdown
| `git diff --name-only --diff-filter=U` | `hug slc` | **S**tatus + **L**ist **C**onflicts | Conflicted (unmerged) files only |
```

- [ ] **Step 5: `README.md`**

In the Status & Staging code block (~line 337, after the `hug sli` line), add:
```markdown
hug slc                     # Status with list of conflicted (unmerged) files
```

- [ ] **Step 6: `docs/meta/hug-completion-reference.md`**

After the `sli` entry (~line 91), add (same format as the sla/sli lines):
```markdown
- `slu [git-status-opts]`: Unstaged files + status. Args: as above.
- `slk [git-status-opts]`: Untracked files + status. Args: as above.
- `slc [git-status-opts]`: Conflicted (unmerged) files + status. Args: as above.
```

- [ ] **Step 7: Verify + commit**

Run: `grep -l 'slc' docs/commands/status-staging.md git-config/lib/python/articles/agents.md docs/git-to-hug.md README.md docs/meta/hug-completion-reference.md` → lists all five files
Run: `make docs-build` → succeeds

```bash
cd ~/src/hug-scm.WT.feat-slc-conflicted-files
hug a docs/commands/status-staging.md git-config/lib/python/articles/agents.md docs/git-to-hug.md README.md docs/meta/hug-completion-reference.md
hug c -m "docs: complete the sl* family documentation with slc

WHY: The sl family page documented only sl/sla/sli; sls/slu/slk were
invisible, and slc would have joined an incomplete family
(elifarley/hug-scm#244).

WHAT: sls/slu/slk/slc in the status-staging Quick Reference and family
detail sections; slc in the agents.md listing commands, git-to-hug.md
diff translation table, README status block, and completion reference.

IMPACT: The whole sl* family is discoverable in every enumerated
surface, including the agent-facing corpus.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: Full verification

**Goal:** Prove the whole feature green: full test suite + sanitize gate, in the worktree.

**Files:** none (fixes only if a gate fails)

**Acceptance Criteria:**
- [ ] `make test` passes (BATS + pytest, all categories)
- [ ] `make sanitize` passes (format, lint, shellcheck, typecheck)
- [ ] No regressions in existing sl-family or JSON tests

**Verify:** `make test` → "✓ All tests passed!"; `make sanitize` → clean

**Steps:**

- [ ] **Step 1: Full suite**

Run: `make test TEST_SHOW_ALL_RESULTS=1`
Expected: all tests pass (watch for the two known local-only failures documented in `.wolf/cerebrum.md`: `test_hug-file-input.bats` `.env` gitignore and `test_hug-common.bats:319` symlinked-checkout path — both are environment artifacts, green in CI; do not "fix" them).

- [ ] **Step 2: Sanitize**

Run: `make sanitize`
Expected: clean (no reformatting, no lint/typecheck errors)

- [ ] **Step 3: Final review of the diff**

Run: `hug sw --stat` → review every changed file; confirm the commit list tells the story:
1. `feat: add list_conflicted_files primitive for hug slc`
2. `feat: add --conflicts include to list_files_with_status`
3. `feat: add filter-conditional conflicted type to the JSON pipeline`
4. `feat: add hug slc — list conflicted (unmerged) files only`
5. `chore: add slc and fix slu/slk gap in fish completions`
6. `docs: complete the sl* family documentation with slc`

- [ ] **Step 4: If any fix was needed, commit it** (else skip)

```bash
cd ~/src/hug-scm.WT.feat-slc-conflicted-files
hug sla
hug a <fixed-files>
hug c -m "fix: <what the gate caught>"
```

---

## Self-review notes

- **Spec coverage:** §3 (command surface) → Task 4; §4.1 → Task 1; §4.2 → Task 2; §4.3/§6 → Task 3; §7 (completions) → Task 5; §7 (docs) → Task 6; §8.1 (10 tests) → Task 4 steps 1-2; §8.2 (lib tests) → Tasks 1-3; §9/§10 (contracts + rejected alternatives) → encoded in Task 3's "do not fix" note and Task 4's test 8; §11 (build order) → task order.
- **Spec amendment (2026-08-06):** §6 example corrected — the four legacy summary keys are always present; `conflicted` is filter-conditional (the byte-identity requirement makes the earlier example impossible). Plan Task 3 Edit 3 implements exactly this.
- **Known environment-only test failures** (do NOT fix; green in CI): see `.wolf/cerebrum.md` entries for `test_hug-file-input.bats` (.env gitignore) and `test_hug-common.bats:319` (symlinked checkout).
