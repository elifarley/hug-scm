# Add `-s/--stat` Flag to `hug su/ss/sw` Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `-s/--stat` flag to `hug su`, `hug ss`, and `hug sw` commands to display ONLY file statistics (without the full patch), while maintaining current default behavior (patch + stats) with zero breaking changes.

**Architecture:** Direct parameter passing pattern (not environment variable) - consistent with existing `--no-stats` flag in library functions. Three-state behavior: default (patch + stats), `--no-stats` (patch only), `--stats-only` (stats only).

**Tech Stack:** Bash scripting, BATS testing framework, Git diff commands

---

## File Overview

| File | Purpose | Lines to Modify |
|------|---------|-----------------|
| `git-config/lib/hug-git-diff` | Core library functions for diff display | ~100 lines across 3 functions |
| `git-config/bin/git-su` | Unstaged diff command | ~30 lines |
| `git-config/bin/git-ss` | Staged diff command | ~30 lines |
| `git-config/bin/git-sw` | Combined diff command | ~30 lines |
| `tests/unit/test_status_staging.bats` | Test coverage for new feature | +100 lines (new tests) |
| `docs/commands/status-staging.md` | User documentation | ~10 lines |

---

## Task 1: Update `show_unstaged_diff` Library Function

**Files:**
- Modify: `git-config/lib/hug-git-diff:179-243`

**Step 1: Add local variable for `show_patch`**

After line 180 (after `local show_stats=true`), add:

```bash
  local show_patch=true
```

**Step 2: Add `--stats-only` flag case**

After line 190 (after `--no-stats)` case), add:

```bash
      --stats-only)
        show_patch=false
        shift
        ;;
```

**Step 3: Update conditional output for specific file case**

Replace lines 218-224 with:

```bash
      if $show_patch; then
        printf '%s %s Unstaged diff for %s:\n' "$unstaged_emoji" "$diff_emoji" "$file"
        git diff "${git_args[@]}" -- "$file"
      fi

      if $show_stats; then
        if $show_patch; then
          printf '\n%s %s Unstaged file stats:\n' "$unstaged_emoji" "$stats_emoji"
        else
          printf '%s %s Unstaged file stats:\n' "$unstaged_emoji" "$stats_emoji"
        fi
        git diff --stat "${git_args[@]}" -- "$file"
      fi
```

**Step 4: Update conditional output for all files case**

Replace lines 234-240 with:

```bash
      if $show_patch; then
        printf '%s %s Unstaged diff:\n' "$unstaged_emoji" "$diff_emoji"
        git diff "${git_args[@]}"
      fi

      if $show_stats; then
        if $show_patch; then
          printf '\n%s %s Unstaged file stats:\n' "$unstaged_emoji" "$stats_emoji"
        else
          printf '%s %s Unstaged file stats:\n' "$unstaged_emoji" "$stats_emoji"
        fi
        git diff --stat "${git_args[@]}"
      fi
```

**Step 5: Update function documentation**

Replace line 167 with:

```bash
# Usage: show_unstaged_diff [--no-stats] [--stats-only] [--] [file] [git_args...]
```

Add line after 169:

```bash
#   --stats-only - Show only file statistics, omit patch (default: show both)
```

**Step 6: Run library tests to verify no regressions**

Run: `make test-lib TEST_FILTER="diff" TEST_SHOW_ALL_RESULTS=1`
Expected: All existing tests pass

---

## Task 2: Update `show_staged_diff` Library Function

**Files:**
- Modify: `git-config/lib/hug-git-diff:100-164`

**Step 1: Add local variable for `show_patch`**

After line 101 (after `local show_stats=true`), add:

```bash
  local show_patch=true
```

**Step 2: Add `--stats-only` flag case**

After line 110 (after `--no-stats)` case), add:

```bash
      --stats-only)
        show_patch=false
        shift
        ;;
```

**Step 3: Update conditional output for specific file case**

Replace lines 139-145 with:

```bash
      if $show_patch; then
        printf '%s %s Staged diff for %s:\n' "$staged_emoji" "$diff_emoji" "$file"
        git diff --cached "${git_args[@]}" -- "$file"
      fi

      if $show_stats; then
        if $show_patch; then
          printf '\n%s %s Staged file stats:\n' "$staged_emoji" "$stats_emoji"
        else
          printf '%s %s Staged file stats:\n' "$staged_emoji" "$stats_emoji"
        fi
        git diff --cached --stat "${git_args[@]}" -- "$file"
      fi
```

**Step 4: Update conditional output for all files case**

Replace lines 155-161 with:

```bash
      if $show_patch; then
        printf '%s %s Staged diff:\n' "$staged_emoji" "$diff_emoji"
        git diff --cached "${git_args[@]}"
      fi

      if $show_stats; then
        if $show_patch; then
          printf '\n%s %s Staged file stats:\n' "$staged_emoji" "$stats_emoji"
        else
          printf '%s %s Staged file stats:\n' "$staged_emoji" "$stats_emoji"
        fi
        git diff --cached --stat "${git_args[@]}"
      fi
```

**Step 5: Update function documentation**

Replace line 88 with:

```bash
# Usage: show_staged_diff [--no-stats] [--stats-only] [--] [file] [git_args...]
```

Add line after 90:

```bash
#   --stats-only - Show only file statistics, omit patch (default: show both)
```

**Step 6: Run library tests to verify no regressions**

Run: `make test-lib TEST_FILTER="diff" TEST_SHOW_ALL_RESULTS=1`
Expected: All existing tests pass

---

## Task 3: Update `show_combined_diff` Library Function

**Files:**
- Modify: `git-config/lib/hug-git-diff:266-345`

**Step 1: Add local variable for `show_patch`**

After line 267 (after `local show_stats=true`), add:

```bash
  local show_patch=true
```

**Step 2: Add `--stats-only` flag case**

After line 276 (after `--no-stats)` case), add:

```bash
      --stats-only)
        show_patch=false
        shift
        ;;
```

**Step 3: Update stats flag construction to include stats-only**

Replace lines 296-297 with:

```bash
  local stats_flag=""
  local stats_only_flag=""
  if ! $show_stats; then
    stats_flag="--no-stats"
  elif ! $show_patch; then
    stats_only_flag="--stats-only"
  fi
```

**Step 4: Pass stats-only flag to sub-function calls**

Replace line 306 with:

```bash
      show_unstaged_diff $stats_flag $stats_only_flag -- "$file" "${git_args[@]}"
```

Replace line 311 with:

```bash
      show_unstaged_diff $stats_flag $stats_only_flag "${git_args[@]}"
```

Replace line 335 with:

```bash
        show_staged_diff $stats_flag $stats_only_flag -- "$file" "${git_args[@]}"
```

Replace line 341 with:

```bash
        show_staged_diff $stats_flag $stats_only_flag "${git_args[@]}"
```

**Step 5: Update function documentation**

Replace line 254 with:

```bash
# Usage: show_combined_diff [--no-stats] [--stats-only] [--] [file] [git_args...]
```

Add line after 256:

```bash
#   --stats-only - Show only file statistics, omit patch (default: show both)
```

**Step 6: Run library tests to verify no regressions**

Run: `make test-lib TEST_FILTER="diff" TEST_SHOW_ALL_RESULTS=1`
Expected: All existing tests pass

---

## Task 4: Update `git-su` Command Script

**Files:**
- Modify: `git-config/bin/git-su:9-84`

**Step 1: Update `show_help()` OPTIONS section**

Replace line 22-24 with:

```bash
OPTIONS:
    --browse-root  Browse full repository scope in file selector UI (default: current directory)
    -s, --stat     Show only file statistics (omit patch)
    -h, --help     Show this help
```

**Step 2: Update DESCRIPTION section**

Replace line 27-28 with:

```bash
DESCRIPTION:
    Shows the unstaged diff (modifications not yet staged). When
    no file is specified, shows all unstaged diff. By default shows both
    patch and statistics. Use '--stat' to show statistics only, or '--no-stats'
    to show patch only. Use '--' to interactively select a file from unstaged files.
```

**Step 3: Add flag parsing after `parse_common_flags`**

After line 50, add:

```bash
# Parse --stat flag
stats_only=false
remaining_args=()
for arg in "$@"; do
  case "$arg" in
    -s|--stat)
      stats_only=true
      ;;
    *)
      remaining_args+=("$arg")
      ;;
  esac
done
set -- "${remaining_args[@]}"
```

**Step 4: Update interactive file selection handler**

Replace line 71 with:

```bash
    show_unstaged_diff ${stats_only:+--stats-only} -- "$file"
```

**Step 5: Update regular call handlers**

Replace line 78 with:

```bash
  show_unstaged_diff ${stats_only:+--stats-only}
```

Replace line 83 with:

```bash
  show_unstaged_diff ${stats_only:+--stats-only} -- "${GIT_PREFIX}$t" "$@"
```

**Step 6: Update EXAMPLES section**

Replace line 33-37 with:

```bash
EXAMPLES:
    hug su                  # Show all unstaged diff (patch + stats)
    hug su --stat           # Show only unstaged statistics
    hug su file.txt         # Show unstaged diff for specific file
    hug su --stat file.txt  # Show stats for specific file only
    hug su --               # Interactive file selection (current directory)
    hug su --browse-root    # Interactive file selection (full repository)
```

**Step 7: Update USAGE line**

Replace line 14 with:

```bash
    hug su [<file>] [-s, --stat] [-h, --help]
```

**Step 8: Run unit tests for status/staging**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="hug su" TEST_SHOW_ALL_RESULTS=1`
Expected: Existing tests pass (new tests not written yet)

---

## Task 5: Update `git-ss` Command Script

**Files:**
- Modify: `git-config/bin/git-ss:9-84`

**Step 1: Update `show_help()` OPTIONS section**

Replace line 22-24 with:

```bash
OPTIONS:
    --browse-root  Browse full repository scope in file selector UI (default: current directory)
    -s, --stat     Show only file statistics (omit patch)
    -h, --help     Show this help
```

**Step 2: Update DESCRIPTION section**

Replace line 27-28 with:

```bash
DESCRIPTION:
    Shows the staged diff (what will be committed). When no file
    is specified, shows all staged diff. By default shows both patch and
    statistics. Use '--stat' to show statistics only, or '--no-stats' to
    show patch only. Use '--' to interactively select a file from staged files.
```

**Step 3: Add flag parsing after `parse_common_flags`**

After line 50, add:

```bash
# Parse --stat flag
stats_only=false
remaining_args=()
for arg in "$@"; do
  case "$arg" in
    -s|--stat)
      stats_only=true
      ;;
    *)
      remaining_args+=("$arg")
      ;;
  esac
done
set -- "${remaining_args[@]}"
```

**Step 4: Update interactive file selection handler**

Replace line 71 with:

```bash
    show_staged_diff ${stats_only:+--stats-only} -- "$file"
```

**Step 5: Update regular call handlers**

Replace line 78 with:

```bash
  show_staged_diff ${stats_only:+--stats-only}
```

Replace line 83 with:

```bash
  show_staged_diff ${stats_only:+--stats-only} -- "${GIT_PREFIX}$t" "$@"
```

**Step 6: Update EXAMPLES section**

Replace line 33-37 with:

```bash
EXAMPLES:
    hug ss                  # Show all staged diff (patch + stats)
    hug ss --stat           # Show only staged statistics
    hug ss file.txt         # Show staged diff for specific file
    hug ss --stat file.txt  # Show stats for specific file only
    hug ss --               # Interactive file selection (current directory)
    hug ss --browse-root    # Interactive file selection (full repository)
```

**Step 7: Update USAGE line**

Replace line 14 with:

```bash
    hug ss [<file>] [-s, --stat] [-h, --help]
```

**Step 8: Run unit tests for status/staging**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="hug ss" TEST_SHOW_ALL_RESULTS=1`
Expected: Existing tests pass (new tests not written yet)

---

## Task 6: Update `git-sw` Command Script

**Files:**
- Modify: `git-config/bin/git-sw:9-84`

**Step 1: Update `show_help()` OPTIONS section**

Replace line 22-24 with:

```bash
OPTIONS:
    --browse-root  Browse full repository scope in file selector UI (default: current directory)
    -s, --stat     Show only file statistics (omit patch)
    -h, --help     Show this help
```

**Step 2: Update DESCRIPTION section**

Replace line 27-30 with:

```bash
DESCRIPTION:
    Shows the diff of all working directory changes, split into unstaged and
    staged sections. First shows unstaged diff with stats, then shows staged
    changes with stats, separated by a divider. By default shows both patch
    and statistics. Use '--stat' to show statistics only.
```

**Step 3: Add flag parsing after `parse_common_flags`**

After line 49, add:

```bash
# Parse --stat flag
stats_only=false
remaining_args=()
for arg in "$@"; do
  case "$arg" in
    -s|--stat)
      stats_only=true
      ;;
    *)
      remaining_args+=("$arg")
      ;;
  esac
done
set -- "${remaining_args[@]}"
```

**Step 4: Update interactive file selection handler**

Replace line 70 with:

```bash
    show_combined_diff ${stats_only:+--stats-only} -- "$file"
```

**Step 5: Update regular call handlers**

Replace line 77 with:

```bash
  show_combined_diff ${stats_only:+--stats-only}
```

Replace line 82 with:

```bash
  show_combined_diff ${stats_only:+--stats-only} -- "${GIT_PREFIX}$t" "$@"
```

**Step 6: Update EXAMPLES section**

Replace line 32-36 with:

```bash
EXAMPLES:
    hug sw                  # Show all working directory changes (unstaged + staged)
    hug sw --stat           # Show only statistics (no patches)
    hug sw file.txt         # Show working directory changes for specific file
    hug sw --               # Interactive file selection (current directory)
    hug sw --browse-root    # Interactive file selection (full repository)
```

**Step 7: Update USAGE line**

Replace line 14 with:

```bash
    hug sw [<file>] [-s, --stat] [-h, --help]
```

**Step 8: Run unit tests for status/staging**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="hug sw" TEST_SHOW_ALL_RESULTS=1`
Expected: Existing tests pass (new tests not written yet)

---

## Task 7: Write Tests for `hug su --stat` Feature

**Files:**
- Modify: `tests/unit/test_status_staging.bats` (insert after line 267)

**Step 1: Write test for `hug su --stat` shows only statistics**

```bash
@test "hug su --stat: shows only statistics without patch" {
  # Verify unstaged changes exist
  run git diff --name-only
  assert_success
  assert_output --partial "README.md"

  # Run with --stat flag
  run hug su --stat

  assert_success

  # Should show statistics header
  assert_output --partial "Unstaged file stats"

  # Should NOT show diff markers (@@ or +/-)
  refute_output --partial "@@"
  refute_output --partial "+"
  refute_output --partial "-"

  # Should show file summary
  assert_output --partial "README.md"
}
```

**Step 2: Write test for short flag `-s`**

```bash
@test "hug su -s: short flag works for stats-only mode" {
  run hug su -s

  assert_success
  assert_output --partial "Unstaged file stats"
  refute_output --partial "@@"
}
```

**Step 3: Write test for `hug su --stat file.txt` with specific file**

```bash
@test "hug su --stat file.txt: shows stats for specific file" {
  echo "new content" > newfile.txt

  run hug su --stat newfile.txt

  assert_success
  assert_output --partial "Unstaged file stats"
  assert_output --partial "newfile.txt"
  refute_output --partial "@@"
}
```

**Step 4: Write test for default behavior (no regression)**

```bash
@test "hug su: default shows both patch and stats (no regression)" {
  run hug su

  assert_success

  # Should show BOTH diff and stats
  assert_output --partial "Unstaged diff"
  assert_output --partial "@@"  # Diff markers
  assert_output --partial "Unstaged file stats"
}
```

**Step 5: Run the new tests to verify they fail**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="--stat" TEST_SHOW_ALL_RESULTS=1`
Expected: Tests FAIL (feature not yet implemented in commands)

---

## Task 8: Write Tests for `hug ss --stat` Feature

**Files:**
- Modify: `tests/unit/test_status_staging.bats` (append after Task 7 tests)

**Step 1: Write test for `hug ss --stat` shows only statistics**

```bash
@test "hug ss --stat: shows only staged statistics" {
  # Ensure staged.txt is staged
  git add staged.txt

  run hug ss --stat

  assert_success
  assert_output --partial "Staged file stats"
  refute_output --partial "@@"
  assert_output --partial "staged.txt"
}
```

**Step 2: Write test for short flag `-s`**

```bash
@test "hug ss -s: short flag works for staged stats" {
  run hug ss -s

  assert_success
  assert_output --partial "Staged file stats"
  refute_output --partial "@@"
}
```

**Step 3: Run the new tests**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="ss --stat" TEST_SHOW_ALL_RESULTS=1`
Expected: Tests FAIL initially, then PASS after Task 5 implementation

---

## Task 9: Write Tests for `hug sw --stat` Feature

**Files:**
- Modify: `tests/unit/test_status_staging.bats` (append after Task 8 tests)

**Step 1: Write test for `hug sw --stat` shows only statistics**

```bash
@test "hug sw --stat: shows only statistics for combined diff" {
  run hug sw --stat

  assert_success
  assert_output --partial "Unstaged file stats"
  assert_output --partial "Staged file stats"
  refute_output --partial "@@"
}
```

**Step 2: Write test for interactive mode with --stat**

```bash
@test "hug su --stat --browse-root: works with interactive mode" {
  # Mock the file selection to return README.md
  setup_gum_mock
  export HUG_TEST_GUM_SELECTION_INDEX=0

  run_in_hug_repo bash -c 'source ../bin/activate && HUG_INTERACTIVE_FILE_SELECTION=true hug su --browse-root --stat'

  assert_success
  assert_output --partial "Unstaged file stats"

  teardown_gum_mock
}
```

**Step 3: Write test for no changes scenario**

```bash
@test "hug su --stat with no changes: shows appropriate message" {
  # Create a fresh clean repo
  local clean_repo
  clean_repo=$(create_test_repo)
  cd "$clean_repo"

  run hug su --stat

  assert_success
  # Should exit silently or with minimal output when no changes
  [[ -z "$output" ]] || [[ "$output" =~ "No unstaged" || "$output" =~ "clean" ]]

  cd "$TEST_REPO"
}
```

**Step 4: Run the new tests**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="sw --stat" TEST_SHOW_ALL_RESULTS=1`
Expected: Tests FAIL initially, then PASS after Task 6 implementation

---

## Task 10: Run All Tests and Verify No Regressions

**Files:**
- Test: All test files

**Step 1: Run status/staging unit tests with verbose output**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_SHOW_ALL_RESULTS=1`
Expected: All tests PASS (including new --stat tests)

**Step 2: Run full unit test suite**

Run: `make test-unit TEST_SHOW_ALL_RESULTS=1`
Expected: All unit tests PASS

**Step 3: Run full test suite**

Run: `make test TEST_SHOW_ALL_RESULTS=1`
Expected: All tests PASS (BATS + pytest)

**Step 4: Verify help text shows new flag**

Run: `hug su -h | grep -- "-s, --stat"`
Expected: Output includes "-s, --stat"

Run: `hug ss -h | grep -- "-s, --stat"`
Expected: Output includes "-s, --stat"

Run: `hug sw -h | grep -- "-s, --stat"`
Expected: Output includes "-s, --stat"

---

## Task 11: Update Documentation

**Files:**
- Modify: `docs/commands/status-staging.md:91-134`

**Step 1: Update `hug ss` documentation**

Replace lines 94-102 with:

```markdown
- `hug ss [file]`: **S**tatus + **S**taged diff
    - **Description**: Status + staged changes patch (for a file or all files). By default shows both patch and statistics. Use `--stat` for statistics only or `--no-stats` for patch only. Use `--` to interactively select from staged files.
    - **Example**:
      ```
      hug ss                 # Show all staged changes (patch + stats)
      hug ss --stat          # Show only staged statistics
      hug ss src/app.js      # Show staged changes for specific file
      hug ss --stat src/app.js --no-stats  # Patch only, no stats
      hug ss --              # Interactive file selection from staged files
      ```
    - **Safety**: ✅ Read-only diff preview.
```

**Step 2: Update `hug su` documentation**

Replace lines 104-112 with:

```markdown
- `hug su [file]`: **S**tatus + **U**nstaged diff
    - **Description**: Status + unstaged changes patch. By default shows both patch and statistics. Use `--stat` for statistics only or `--no-stats` for patch only. Use `--` to interactively select from unstaged files.
    - **Example**:
      ```
      hug su                 # Show all unstaged changes (patch + stats)
      hug su --stat          # Show only unstaged statistics
      hug su file.txt        # Show unstaged changes for specific file
      hug su --stat file.txt # Show stats for specific file only
      hug su --              # Interactive file selection from unstaged files
      ```
    - **Safety**: ✅ Read-only diff preview.
```

**Step 3: Update `hug sw` documentation**

Replace lines 114-122 with:

```markdown
- `hug sw [file]`: **S**tatus + **W**orking directory diff
    - **Description**: Status + working directory patch (staged + unstaged). By default shows both patch and statistics. Use `--stat` for statistics only. Use `--` to interactively select from changed files.
    - **Example**:
      ```
      hug sw                 # Show all working directory changes (patch + stats)
      hug sw --stat          # Show only statistics (no patches)
      hug sw .               # Show all changes in current directory
      hug sw --              # Interactive file selection from changed files
      ```
    - **Safety**: ✅ Read-only diff preview.
```

**Step 4: Verify documentation builds**

Run: `make docs-build`
Expected: Documentation builds successfully

---

## Task 12: Manual Verification and Final Checks

**Files:**
- Verification: Manual testing

**Step 1: Create a test repository with changes**

```bash
cd /tmp
rm -rf test-hug-stat
git init test-hug-stat
cd test-hug-stat
echo "initial" > file1.txt
git add file1.txt
git commit -m "initial"
echo "modified content" > file1.txt
echo "new file" > file2.txt
```

**Step 2: Test `hug su --stat` shows ONLY stats**

Run: `hug su --stat`
Expected: Shows statistics with NO `@@` markers and NO `+`/`-` lines

**Step 3: Test `hug su` default (regression check)**

Run: `hug su`
Expected: Shows BOTH diff (with `@@`) AND stats

**Step 4: Test `hug su -s` short flag**

Run: `hug su -s`
Expected: Same as `--stat` (stats only)

**Step 5: Test with staged changes**

```bash
git add file1.txt
hug ss --stat
```
Expected: Shows staged statistics only

**Step 6: Test combined diff**

Run: `hug sw --stat`
Expected: Shows both unstaged and staged statistics, no patches

**Step 7: Test specific file**

Run: `hug su --stat file1.txt`
Expected: Shows stats for file1.txt only

**Step 8: Cleanup**

```bash
cd /
rm -rf /tmp/test-hug-stat
```

---

## Task 13: Final Test Suite Run

**Files:**
- Test: Full test suite

**Step 1: Run complete test suite with verbose output**

Run: `make test TEST_SHOW_ALL_RESULTS=1`
Expected: ALL tests pass (no regressions)

**Step 2: Verify coverage**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_SHOW_ALL_RESULTS=1 | grep -E "^(✓|✗|1\.\.[0-9]+)"`

Expected: Test count increased by ~9 tests from baseline

---

## Success Criteria Checklist

After completing all tasks, verify:

- [ ] `hug su --stat` / `hug su -s` shows ONLY statistics (no patch)
- [ ] `hug ss --stat` / `hug ss -s` shows ONLY staged statistics
- [ ] `hug sw --stat` / `hug sw -s` shows ONLY combined statistics
- [ ] Default behavior unchanged (patch + stats)
- [ ] Works with file arguments
- [ ] Works with interactive mode (`--`)
- [ ] Works with `--browse-root` flag
- [ ] All tests pass (no regressions)
- [ ] Help text updated for all three commands
- [ ] Documentation updated

---

## Risk Assessment

**Overall Risk: LOW**

- Pure feature addition with no breaking changes
- Default behavior preserved (patch + stats)
- New flag is additive only
- Library functions follow existing patterns
- Comprehensive test coverage planned

**Potential Issues:**
1. **Flag parsing order**: Must parse `--stat` before passing to library functions
2. **Parameter expansion**: Using `${stats_only:+--stats-only}` pattern correctly
3. **Header spacing**: Stats-only mode should not have leading newline when patch is omitted
4. **Interactive mode**: Must pass flag through interactive selection handler

**Mitigation:**
- Existing tests ensure no regressions
- New tests cover all three modes (default, --stat, --no-stats)
- Manual verification in Task 12 catches edge cases
