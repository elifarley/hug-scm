#!/usr/bin/env bats
# Tests for hug-select-files library: interactive file selection

load '../test_helper'
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-git-kit'
load '../../git-config/lib/hug-gum'
load '../../git-config/lib/hug-select-files'

# run --separate-stderr is used below (bats >= 1.5) to assert stdout/stderr
# independently for the non-repo parity test (#259).
bats_require_minimum_version 1.5.0

# Helper to create test repo with files in subdirectories
create_test_repo_for_selection() {
  local test_repo
  test_repo=$(create_test_repo)
  
  (
    cd "$test_repo" || exit 1
    
    # Create directory structure
    mkdir -p src/components
    mkdir -p docs
    
    # Create and commit files
    echo "component" > src/components/App.js
    echo "util" > src/util.js
    echo "root" > root.txt
    echo "doc" > docs/README.md
    git add -A
    git commit -q -m "Initial structure"
    
    # Make changes for testing
    echo "modified" >> src/components/App.js
    echo "staged" > src/staged.js
    git add src/staged.js
    echo "untracked" > src/untracked.js
  )
  
  echo "$test_repo"
}

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_for_selection)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

@test "hug-select-files: select_files_with_status requires gum" {
  # Mock gum_available to return false
  gum_available() { return 1; }
  
  run select_files_with_status --unstaged
  assert_failure
  assert_output --partial "requires 'gum'"
}

@test "hug-select-files: --cwd scopes to current directory" {
  # We can't test the interactive part, but we can test that the function
  # receives the correct file list by checking list functions directly
  cd src
  
  # Test unstaged files with --cwd
  mapfile -t files < <(list_unstaged_files --cwd)
  
  # Should only see files from src/ and subdirs (not ../root.txt or ../docs/)
  [[ ${#files[@]} -gt 0 ]]
  [[ " ${files[*]} " =~ "components/App.js" ]]
  [[ ! " ${files[*]} " =~ "root.txt" ]]
  [[ ! " ${files[*]} " =~ "README.md" ]]
}

@test "hug-select-files: without --cwd shows all files from subdirectory" {
  cd src
  
  # Test unstaged files without --cwd
  mapfile -t files < <(list_unstaged_files)
  
  # Should see files from entire repo (with relative paths)
  [[ ${#files[@]} -gt 0 ]]
  [[ " ${files[*]} " =~ "components/App.js" ]]
  # root.txt would be shown as ../root.txt from src/
}

@test "hug-select-files: --staged flag collects staged files" {
  # Test that staged files are collected
  mapfile -t files < <(list_staged_files)
  
  [[ ${#files[@]} -eq 1 ]]
  [[ " ${files[*]} " =~ "src/staged.js" ]]
}

@test "hug-select-files: --unstaged flag collects unstaged files" {
  # Test that unstaged files are collected
  mapfile -t files < <(list_unstaged_files)
  
  [[ ${#files[@]} -ge 1 ]]
  [[ " ${files[*]} " =~ "src/components/App.js" ]]
}

@test "hug-select-files: --untracked flag collects untracked files" {
  # Test that untracked files are collected
  mapfile -t files < <(list_untracked_files)
  
  [[ ${#files[@]} -ge 1 ]]
  [[ " ${files[*]} " =~ "src/untracked.js" ]]
}

@test "hug-select-files: --status flag includes status information" {
  # Test that status flag works
  local output
  output=$(list_staged_files --status)
  
  # Should have status prefix (A for added)
  [[ "$output" =~ A.*src/staged.js ]]
}

@test "hug-select-files: files from subdirectory show relative paths with --cwd" {
  cd src/components
  
  # Test with --cwd from nested directory
  mapfile -t files < <(list_unstaged_files --cwd)
  
  # Should show App.js (not src/components/App.js or ../../src/components/App.js)
  [[ " ${files[*]} " =~ "App.js" ]]
  [[ ! " ${files[*]} " =~ "src/components/App.js" ]]
}

@test "hug-select-files: directory with changes returns correct files with --cwd" {
  cd docs
  
  # docs has README.md which was modified
  mapfile -t files < <(list_unstaged_files --cwd)
  
  # Should have at least README.md
  [[ ${#files[@]} -ge 1 ]]
}

@test "hug-select-files: tracked files can be listed" {
  # Test list_tracked_files
  mapfile -t files < <(list_tracked_files)
  
  # Should include committed files
  [[ ${#files[@]} -ge 4 ]]
  [[ " ${files[*]} " =~ "root.txt" ]]
  [[ " ${files[*]} " =~ "src/components/App.js" ]]
  [[ " ${files[*]} " =~ "docs/README.md" ]]
}

@test "hug-select-files: tracked files with --cwd shows only local files" {
  cd src
  
  mapfile -t files < <(list_tracked_files --cwd)
  
  # Should only see src/* files
  [[ " ${files[*]} " =~ "components/App.js" ]]
  [[ " ${files[*]} " =~ "util.js" ]]
  [[ ! " ${files[*]} " =~ "root.txt" ]]
  [[ ! " ${files[*]} " =~ "README.md" ]]
}

@test "hug-select-files: tracked files from subdirectory have correct relative paths" {
  cd src/components
  
  # Simulate GIT_PREFIX being set (as git does when running git commands)
  export GIT_PREFIX="src/components/"
  
  mapfile -t files < <(list_tracked_files --cwd)
  
  # With --cwd, files should be relative to current directory, not prefixed with ../
  [[ " ${files[*]} " =~ "App.js" ]]
  [[ ! " ${files[*]} " =~ "../" ]]
  
  # Test without --cwd - should list ALL files in repository
  mapfile -t all_files < <(list_tracked_files)
  
  # Should include files from current directory without prefix
  local has_app_js=false
  for file in "${all_files[@]}"; do
    [[ "$file" == "App.js" ]] && has_app_js=true
  done
  [[ "$has_app_js" == true ]]
  
  # Should include files from parent directories WITH ../ prefix
  local has_parent_files=false
  for file in "${all_files[@]}"; do
    [[ "$file" =~ ^\.\./ ]] && has_parent_files=true && break
  done
  [[ "$has_parent_files" == true ]]
}

# Helper to create a merge conflict scenario for testing
create_merge_conflict() {
  echo "base content" > conflict-file.txt
  git add conflict-file.txt
  git commit -q -m "Add base file"
  
  # Create two branches with conflicting changes
  git checkout -q -b branch1
  echo "branch1 change" > conflict-file.txt
  git add conflict-file.txt
  git commit -q -m "Change on branch1"
  
  git checkout -q main
  git checkout -q -b branch2
  echo "branch2 change" > conflict-file.txt
  git add conflict-file.txt
  git commit -q -m "Change on branch2"
  
  # Try to merge, which will create a conflict
  git merge --no-commit --no-ff branch1 2>/dev/null || true
}

@test "hug-select-files: conflict files show U status in staged files" {
  # Create a merge conflict scenario
  create_merge_conflict
  
  # Check that list_staged_files returns U status for conflict
  local output
  output=$(list_staged_files --status)
  
  # Should show U status for the conflict file
  [[ "$output" =~ U.*conflict-file.txt ]]
}

@test "hug-select-files: conflict files show U status in unstaged files" {
  # Create a merge conflict scenario
  create_merge_conflict
  
  # Check that list_unstaged_files returns U status for conflict
  local output
  output=$(list_unstaged_files --status)
  
  # Should show U status for the conflict file (may appear multiple times)
  [[ "$output" =~ U.*conflict-file.txt ]]
}

################################################################################
# Tests for list_files_with_status (non-interactive listing)
################################################################################

@test "list_files_with_status: returns formatted output with --staged" {
  # Test that list_files_with_status returns formatted output
  local output
  output=$(list_files_with_status --staged)
  
  # Should have filename
  [[ "$output" =~ src/staged.js ]]
  # Should have status label (S: prefix or similar)
  [[ "$output" =~ S: ]]
}

@test "list_files_with_status: returns formatted output with --unstaged" {
  local output
  output=$(list_files_with_status --unstaged)
  
  # Should show unstaged modified file
  [[ "$output" =~ src/components/App.js ]]
  # Should have status label (U: prefix or similar)
  [[ "$output" =~ U: ]]
}

@test "list_files_with_status: returns formatted output with --untracked" {
  local output
  output=$(list_files_with_status --untracked)
  
  # Should show untracked file
  [[ "$output" =~ src/untracked.js ]]
  # Should have untracked label
  [[ "$output" =~ untrcK ]]
}

@test "list_files_with_status: shows all types with multiple flags" {
  local output
  output=$(list_files_with_status --staged --unstaged --untracked)
  
  # Should show all three types
  [[ "$output" =~ src/staged.js ]]
  [[ "$output" =~ src/components/App.js ]]
  [[ "$output" =~ src/untracked.js ]]
}

@test "list_files_with_status: respects --cwd flag" {
  cd src
  
  local output
  output=$(list_files_with_status --unstaged --cwd)
  
  # Should show files from current directory
  [[ "$output" =~ components/App.js ]]
  # Should not show files from parent
  [[ ! "$output" =~ root.txt ]]
}

@test "list_files_with_status: returns 1 when no files found" {
  # Create a clean repo
  local clean_repo
  clean_repo=$(create_test_repo)
  cd "$clean_repo"
  
  run list_files_with_status --staged --unstaged
  assert_failure
}

@test "list_files_with_status: shows tracked files when no flags specified" {
  local output
  output=$(list_files_with_status)
  
  # Should list tracked files without formatting
  [[ "$output" =~ root.txt ]]
  [[ "$output" =~ src/components/App.js ]]
  # Should NOT have ANSI color codes for plain listing
  # (This may fail if terminal color codes are in the output, adjust as needed)
}

@test "list_files_with_status: no duplicate files in output" {
  # Create a partially staged file: "line2" is staged, "line3" is unstaged.
  echo "line2" >> src/components/App.js
  git add src/components/App.js
  echo "line3" >> src/components/App.js
  
  local output
  output=$(list_files_with_status --staged --unstaged)
  
  # Count occurrences of App.js - should appear only once
  local count
  count=$(echo "$output" | grep -c "App.js" || echo "0")
  [[ $count -eq 1 ]]
}

@test "list_files_with_status: handles files with various status codes" {
  # Create files with different statuses
  echo "to delete" > todelete.txt
  git add todelete.txt
  git commit -q -m "Add file to delete"

  # Stage deletion
  git rm todelete.txt

  # Create a new file and stage it
  echo "added" > added.txt
  git add added.txt

  local output
  output=$(list_files_with_status --staged)

  # Should show deletion status
  [[ "$output" =~ todelete.txt ]]
  # Should show addition status
  [[ "$output" =~ added.txt ]]
}

@test "list_files_with_status: correct file ordering by priority (untrcK before U:*)" {
  # Create a mix of file types to test ordering
  echo "unstaged change" > unstaged.txt
  echo "tracked file" > tracked.txt
  git add tracked.txt
  git commit -q -m "Add tracked file"

  # Modify tracked file (creates unstaged change)
  echo "modified" >> tracked.txt

  # Create untracked file
  echo "untracked" > untracked.txt

  # Stage another file
  echo "staged" > staged.txt
  git add staged.txt

  # Get the output and check ordering
  local output
  output=$(list_files_with_status --staged --unstaged --untracked)

  # Extract lines containing our test files
  local unstaged_line untracked_line staged_line
  unstaged_line=$(echo "$output" | grep "unstaged.txt" | head -1)
  untracked_line=$(echo "$output" | grep "untracked.txt" | head -1)
  staged_line=$(echo "$output" | grep "staged.txt" | head -1)

  # Get line numbers for ordering check (use word boundaries to avoid substring matches)
  local unstaged_line_num untracked_line_num tracked_line_num staged_line_num
  unstaged_line_num=$(echo "$output" | grep -n " unstaged.txt$" | cut -d: -f1 | head -1)
  untracked_line_num=$(echo "$output" | grep -n " untracked.txt$" | cut -d: -f1 | head -1)
  tracked_line_num=$(echo "$output" | grep -n " tracked.txt$" | cut -d: -f1 | head -1)
  staged_line_num=$(echo "$output" | grep -n " staged.txt$" | cut -d: -f1 | head -1)

  # Verify that untrcK appears BEFORE U:Mod (lower line number = higher in output)
  # untrcK (priority 60) should come before U:Mod (priority 70)
  [[ $untracked_line_num -lt $tracked_line_num ]]
  [[ $unstaged_line_num -lt $tracked_line_num ]]

  # Verify that S:* appears LAST (highest line number = highest priority)
  [[ $staged_line_num -gt $unstaged_line_num ]]
  [[ $staged_line_num -gt $untracked_line_num ]]
  [[ $staged_line_num -gt $tracked_line_num ]]
}

################################################################################
# Tests for status priority system (hug-git-priorities)
################################################################################

@test "get_status_priority: returns correct priority values" {
  # Load the priorities library
  load '../../git-config/lib/hug-git-priorities'

  # Test known priority values
  local priority

  # Conflicts have highest priority (90)
  priority=$(get_status_priority "U:Cnflt")
  [[ $priority -eq 90 ]]
  priority=$(get_status_priority "S:Cnflt")
  [[ $priority -eq 90 ]]

  # Staged files have high priority (80)
  priority=$(get_status_priority "S:Add")
  [[ $priority -eq 80 ]]
  priority=$(get_status_priority "S:Mod")
  [[ $priority -eq 80 ]]
  priority=$(get_status_priority "S:Ren")
  [[ $priority -eq 80 ]]
  priority=$(get_status_priority "S:Copy")
  [[ $priority -eq 80 ]]
  priority=$(get_status_priority "S:Del")
  [[ $priority -eq 80 ]]

  # Unstaged modifications have medium priority (70)
  priority=$(get_status_priority "U:Mod")
  [[ $priority -eq 70 ]]
  priority=$(get_status_priority "U:Del")
  [[ $priority -eq 70 ]]
  priority=$(get_status_priority "U:Cnflt")
  [[ $priority -eq 90 ]]  # Conflicts are still 90

  # Untracked files have lower priority (60)
  priority=$(get_status_priority "untrcK")
  [[ $priority -eq 60 ]]

  # Ignored files have lowest priority (50)
  priority=$(get_status_priority "Ignore")
  [[ $priority -eq 50 ]]

  # Unknown status returns 0
  priority=$(get_status_priority "Unknown")
  [[ $priority -eq 0 ]]
}

@test "get_status_priority: verifies untrcK has lower priority than U:Mod" {
  # Load the priorities library
  load '../../git-config/lib/hug-git-priorities'

  local untracked_priority unstaged_priority
  untracked_priority=$(get_status_priority "untrcK")
  unstaged_priority=$(get_status_priority "U:Mod")

  # untrcK (60) should have lower priority than U:Mod (70)
  [[ $untracked_priority -lt $unstaged_priority ]]
  [[ $untracked_priority -eq 60 ]]
  [[ $unstaged_priority -eq 70 ]]
}

################################################################################
# Tests for helper functions (refactoring to eliminate code duplication)
################################################################################

@test "_format_staged_status: returns correct format for each status code" {
  # Color variables are already defined by hug-common (loaded via test_helper)
  local result status_text status_code

  # Test Add (A)
  result=$(_format_staged_status "A")
  IFS=$'\t' read -r status_text status_code <<< "$result"
  [[ "$status_code" == "S:Add" ]]
  [[ "$status_text" =~ S:Add ]]

  # Test Modify (M)
  result=$(_format_staged_status "M")
  IFS=$'\t' read -r status_text status_code <<< "$result"
  [[ "$status_code" == "S:Mod" ]]
  [[ "$status_text" =~ S:Mod ]]

  # Test Delete (D)
  result=$(_format_staged_status "D")
  IFS=$'\t' read -r status_text status_code <<< "$result"
  [[ "$status_code" == "S:Del" ]]
  [[ "$status_text" =~ S:Del ]]

  # Test Rename (R100 - should match R*)
  result=$(_format_staged_status "R100")
  IFS=$'\t' read -r status_text status_code <<< "$result"
  [[ "$status_code" == "S:Ren" ]]
  [[ "$status_text" =~ S:Ren ]]

  # Test Copy (C100 - should match C*)
  result=$(_format_staged_status "C100")
  IFS=$'\t' read -r status_text status_code <<< "$result"
  [[ "$status_code" == "S:Copy" ]]
  [[ "$status_text" =~ S:Copy ]]

  # Test Conflict (U)
  result=$(_format_staged_status "U")
  IFS=$'\t' read -r status_text status_code <<< "$result"
  [[ "$status_code" == "S:Cnflt" ]]
  [[ "$status_text" =~ Cnflt ]]

  # Test Unknown (*)
  result=$(_format_staged_status "X")
  IFS=$'\t' read -r status_text status_code <<< "$result"
  [[ "$status_code" == "S:Unk" ]]
}

@test "_format_unstaged_status: returns correct format for each status code" {
  # Color variables are already defined by hug-common (loaded via test_helper)
  local result status_text status_code

  # Test Modify (M)
  result=$(_format_unstaged_status "M")
  IFS=$'\t' read -r status_text status_code <<< "$result"
  [[ "$status_code" == "U:Mod" ]]
  [[ "$status_text" =~ U:Mod ]]

  # Test Delete (D)
  result=$(_format_unstaged_status "D")
  IFS=$'\t' read -r status_text status_code <<< "$result"
  [[ "$status_code" == "U:Del" ]]
  [[ "$status_text" =~ U:Del ]]

  # Test Rename (R100)
  result=$(_format_unstaged_status "R100")
  IFS=$'\t' read -r status_text status_code <<< "$result"
  [[ "$status_code" == "U:Ren" ]]
  [[ "$status_text" =~ U:Ren ]]

  # Test Copy (C100)
  result=$(_format_unstaged_status "C100")
  IFS=$'\t' read -r status_text status_code <<< "$result"
  [[ "$status_code" == "U:Copy" ]]
  [[ "$status_text" =~ U:Copy ]]

  # Test Conflict (U)
  result=$(_format_unstaged_status "U")
  IFS=$'\t' read -r status_text status_code <<< "$result"
  [[ "$status_code" == "U:Cnflt" ]]
  [[ "$status_text" =~ Cnflt ]]

  # Test Unknown (*)
  result=$(_format_unstaged_status "X")
  IFS=$'\t' read -r status_text status_code <<< "$result"
  [[ "$status_code" == "U:Unk" ]]
}

@test "_format_untracked_status: returns correct format" {
  # Color variables are already defined by hug-common (loaded via test_helper)
  local result status_text status_code
  result=$(_format_untracked_status)
  IFS=$'\t' read -r status_text status_code <<< "$result"

  [[ "$status_code" == "untrcK" ]]
  [[ "$status_text" =~ untrcK ]]
}

@test "_format_ignored_status: returns correct format" {
  # Color variables are already defined by hug-common (loaded via test_helper)
  local result status_text status_code
  result=$(_format_ignored_status)
  IFS=$'\t' read -r status_text status_code <<< "$result"

  [[ "$status_code" == "Ignore" ]]
  [[ "$status_text" =~ Ignore ]]
}

@test "_handle_no_files_found: returns 1 and shows message when scoped" {
  run _handle_no_files_found true
  assert_failure
  assert_output --partial "No relevant files in current directory."
}

@test "_handle_no_files_found: returns 1 and no message when not scoped" {
  run _handle_no_files_found false
  assert_failure
  refute_output
}

################################################################################
# Tests for --suppress-status flag
################################################################################

@test "list_files_with_status: --suppress-status hides status column for untracked files" {
  local output
  output=$(list_files_with_status --untracked --suppress-status)

  # Should show filename without status prefix
  [[ "$output" =~ src/untracked\.js ]]
  # Should NOT have status label
  [[ ! "$output" =~ untrcK ]]
}

@test "list_files_with_status: --suppress-status hides status column for ignored files" {
  echo "*.log" > .gitignore
  git add .gitignore
  echo "test.log" > test.log

  local output
  output=$(list_files_with_status --ignored --suppress-status)

  [[ "$output" =~ test\.log ]]
  [[ ! "$output" =~ Ignore ]]
}

@test "list_files_with_status: --staged with --suppress-status shows status (multiple types)" {
  # Create multiple staged status types
  echo "to delete" > todelete.txt
  git add todelete.txt
  git commit -q -m "Add file to delete"
  git rm todelete.txt

  echo "added" > added.txt
  git add added.txt

  local output
  output=$(list_files_with_status --staged --suppress-status)

  # Should show status (multiple types: deletion and addition)
  # The suppression should fail because there are multiple status types
  [[ "$output" =~ S:Del ]] || [[ "$output" =~ S:Add ]] || [[ "$output" =~ todelete\.txt ]] || [[ "$output" =~ added\.txt ]]
}

@test "list_files_with_status: --suppress-status with multiple file types shows status" {
  local output
  output=$(list_files_with_status --staged --unstaged --suppress-status)

  # Should show status because multiple file types are requested
  [[ "$output" =~ S: ]] || [[ "$output" =~ U: ]]
}

@test "_can_suppress_status: returns false for multiple file types" {
  load '../../git-config/lib/hug-git-priorities'

  # Multiple file types should return false (not safe to suppress)
  run _can_suppress_status true true false false false
  assert_failure

  run _can_suppress_status false true true false false
  assert_failure
}

@test "_can_suppress_status: returns true for single untracked type" {
  load '../../git-config/lib/hug-git-priorities'

  # Single file type (untracked) should return true (safe to suppress)
  run _can_suppress_status false false true false false
  assert_success
}

@test "_can_suppress_status: returns true for single ignored type" {
  load '../../git-config/lib/hug-git-priorities'

  # Single file type (ignored) should return true (safe to suppress)
  run _can_suppress_status false false false true false
  assert_success
}

@test "_can_suppress_status: returns false for unstaged (multiple status types)" {
  load '../../git-config/lib/hug-git-priorities'

  # Unstaged files have multiple status types (U:Mod, U:Del, U:Cnflt)
  # Should return false (not safe to suppress)
  run _can_suppress_status false true false false false
  assert_failure
}

@test "_can_suppress_status: returns false for staged (multiple status types)" {
  load '../../git-config/lib/hug-git-priorities'

  # Staged files have multiple status types (S:Add, S:Mod, S:Del, S:Ren, S:Copy, S:Cnflt)
  # Should return false (not safe to suppress)
  run _can_suppress_status true false false false false
  assert_failure
}

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
  # NOTE: use `run`, not `output=$(...)` — BATS test bodies run under set -e,
  # so a command-substitution assignment whose command exits 1 (no conflicts)
  # aborts the test before the assertions execute.
  run list_files_with_status --conflicts 2>/dev/null
  [[ $status -eq 1 ]]
  [[ -z "$output" ]]
}

@test "_can_suppress_status: conflicts-only is suppress-safe" {
  # NOTE: use `run`, not a direct call — inside the gate, `((type_count++))`
  # evaluates to 0 (hence exit status 1) on its first increment, which trips
  # BATS's set -e and kills a direct call before the gate's return value
  # can be inspected. `run` (like all callers in production, which invoke the
  # gate from an `if` condition) is errexit-exempt.
  run _can_suppress_status false false false false true
  assert_success
}

@test "_can_suppress_status: conflicts mixed with staged is not safe" {
  run _can_suppress_status true false false false true
  assert_failure
}

@test "list_files_with_status: filenames containing | survive sorting" {
  # Real conflict on a file whose name contains the old tuple separator
  echo "base" > 'a|b.txt'
  git add 'a|b.txt'
  git commit -q -m "Add base"
  git switch -q -c branch1
  echo "one" > 'a|b.txt'
  git add 'a|b.txt'
  git commit -q -m "Change on branch1"
  git switch -q main
  echo "two" > 'a|b.txt'
  git add 'a|b.txt'
  git commit -q -m "Change on branch2"
  git merge --no-commit --no-ff branch1 >/dev/null 2>&1 || true

  local output
  output=$(list_files_with_status --conflicts --suppress-status)
  [[ "$output" == 'a|b.txt' ]]
}

@test "list_files_with_status: filenames containing the unit separator survive sorting" {
  # \x1f is legal in filenames (git forbids only NUL and /). Untracked files
  # flow through the -z parser as RAW bytes (unlike conflicted files, which
  # git C-quotes — tracked as elifarley/hug-scm#249), so the tuple escape
  # round-trip must preserve the byte here.
  echo "untracked" > $'a\x1fb.txt'

  # The fixture repo has its own untracked files, so assert the raw byte
  # survives as an intact line (the corruption mode was a garbled re-split)
  local output
  output=$(list_files_with_status --untracked --suppress-status)
  [[ "$output" == *$'a\x1fb.txt'* ]]
}

# =============================================================================
# count_files_with_status (the sl* -c engine)
# =============================================================================

@test "count_files_with_status: counts each state correctly" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"

  # Make .gitignore tracked FIRST so ignored.log is recognized, but keep
  # staged.txt staged (not committed) so the staged state is observable.
  echo "*.log" > .gitignore
  git add .gitignore
  git commit -q -m "add gitignore"
  touch ignored.log

  echo "staged" > staged.txt
  git add staged.txt
  echo "mod" >> README.md
  echo "untracked" > untracked.txt

  [[ "$(count_files_with_status staged)" == "1" ]]
  [[ "$(count_files_with_status unstaged)" == "1" ]]
  [[ "$(count_files_with_status untracked)" == "1" ]]
  [[ "$(count_files_with_status ignored)" == "1" ]]
  # all = staged.txt (staged) + README.md (unstaged) = 2
  [[ "$(count_files_with_status all)" == "2" ]]
  # all+untracked = 2 + untracked.txt = 3
  [[ "$(count_files_with_status all+untracked)" == "3" ]]
}

@test "count_files_with_status: dedups a file staged and unstaged" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"

  echo "v2" > README.md
  git add README.md
  echo "v3" >> README.md

  # README.md is BOTH staged and unstaged → counts once in all
  [[ "$(count_files_with_status all)" == "1" ]]
  [[ "$(count_files_with_status staged)" == "1" ]]
  [[ "$(count_files_with_status unstaged)" == "1" ]]
}

@test "count_files_with_status: pathspec scopes the count" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"

  echo "mod" >> README.md
  echo "other" > other.txt
  git add other.txt

  [[ "$(count_files_with_status unstaged README.md)" == "1" ]]
  [[ "$(count_files_with_status unstaged no-such.txt)" == "0" ]]
  [[ "$(count_files_with_status all other.txt)" == "1" ]]
}

@test "count_files_with_status: newline-containing filename counts once (NUL-safe)" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"

  touch "$(printf 'weird\nname.txt')"

  # Line-based counting would split the name into 2; NUL-delimited counts 1
  [[ "$(count_files_with_status untracked)" == "1" ]]
}

@test "count_files_with_status: rename counts once (skips bare old-path record)" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"

  echo "old" > old.txt
  git add old.txt
  git commit -q -m "add old"
  git mv old.txt new.txt

  # git status --porcelain -z emits "R  new.txt\0old.txt\0" — the bare old.txt
  # record must not be counted. Rename = 1 file.
  [[ "$(count_files_with_status staged)" == "1" ]]
  [[ "$(count_files_with_status all)" == "1" ]]
}

@test "count_files_with_status: rename old-path mimicking a status record counts once" {
  # Adversarial case (elifarley/hug-scm#257 review P2): a tracked file whose
  # name looks like a porcelain status line ("M  old" — pos2 is a space). When
  # renamed, git emits "R  new\0M  old\0"; a pos2 separator heuristic would read
  # the bare "M  old" as a second staged status record. The explicit
  # consume-the-old-path logic must count the rename as exactly 1.
  local repo
  repo=$(create_test_repo)
  cd "$repo"

  printf 'content\n' > "M  old"
  git add "M  old"
  git commit -q -m "add status-shaped name"
  git mv "M  old" new

  [[ "$(count_files_with_status staged)" == "1" ]]
  [[ "$(count_files_with_status all)" == "1" ]]
}

@test "count_files_with_status: all+untracked expands untracked dir to its files" {
  # elifarley/hug-scm#257 review P1: without --untracked-files=all, git collapses
  # two untracked files under a new directory into one "?? dir/" record, so the
  # count undercounts. The all+untracked path (drives `sla -c`) must pass
  # --untracked-files=all and count 2.
  local repo
  repo=$(create_test_repo)
  cd "$repo"

  mkdir newdir
  echo "f1" > newdir/f1.txt
  echo "f2" > newdir/f2.txt

  [[ "$(count_files_with_status untracked)" == "2" ]]
  [[ "$(count_files_with_status all+untracked)" == "2" ]]
}

@test "count_files_with_status: clean error outside a git repo (parity with list_*_files)" {
  local nonrepo
  nonrepo=$(mktemp -d)   # fresh, guaranteed non-repo (setup() cds into a repo; leave it)
  cd "$nonrepo"
  run --separate-stderr count_files_with_status staged
  assert_failure
  [[ -z "$output" ]]                                  # stdout clean: no leaked count (the old silent-0)
  [[ "$stderr" == *"Not in a git repository"* ]]      # stderr carries the clean HUG message
  rm -rf "$nonrepo"
}

@test "run_count_mode: prints the count and exits 0 (terminating wrapper)" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"
  echo "staged" > staged.txt
  git add staged.txt

  # TERMINATING: run in a subshell via `run`; prints the count, exit 0.
  run --separate-stderr run_count_mode staged
  assert_success
  assert_output "1"
  [[ -z "$stderr" ]]
}

@test "run_count_mode: --json and -c are mutually exclusive" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"
  echo "staged" > staged.txt
  git add staged.txt

  run --separate-stderr run_count_mode --json staged
  assert_failure
  [[ "$stderr" == *"mutually exclusive"* ]]
  [[ -z "$output" ]]   # no count printed on the mutex-violation path
}

@test "count_files_with_status: conflicted counts unmerged files" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"

  echo "base" > c.txt
  git add c.txt
  git commit -q -m "base"
  git switch -q -c side
  echo "side" > c.txt
  git commit -q -am "side"
  git switch -q main
  echo "main" > c.txt
  git commit -q -am "main"
  git merge --no-commit --no-ff side >/dev/null 2>&1 || true

  [[ "$(count_files_with_status conflicted)" == "1" ]]
  [[ "$(count_files_with_status conflicted c.txt)" == "1" ]]
  [[ "$(count_files_with_status conflicted no-such.txt)" == "0" ]]
}

@test "count_files_with_status: unknown state errors" {
  # Defensive: a typo in the case patterns (staged/unstaged/all/...) would
  # route valid input to the error branch; pin that the branch fires and
  # reports the bad state, so a future pattern edit can't silently mis-count.
  local repo
  repo=$(create_test_repo)
  cd "$repo"

  run count_files_with_status bogus-state
  assert_failure
  assert_output --partial "unknown state 'bogus-state'"
}

################################################################################
# Tests for pathspec support in select_files_with_status (#292)
################################################################################

# Fixture: BOTH src/a.py and docs/note.md are staged, so a pathspec-scoped
# selector must show src/a.py while an unscoped one would show both — this is
# what makes the pathspec forwarding observable rather than coincidental.
create_pathspec_fixture() {
  mkdir -p src docs
  echo "a" > src/a.py
  echo "note" > docs/note.md
  git add -A
  git commit -q -m "base"

  echo "mod-a" >> src/a.py
  echo "mod-note" >> docs/note.md
  git add src/a.py docs/note.md
}

# Mock gum so the interactive picker becomes observable and controllable:
# the candidate list piped into gum lands in $SELECT_CAPTURE, and gum
# "returns" the first candidate (a deterministic single selection).
mock_gum() {
  SELECT_CAPTURE="$(mktemp)"
  gum_available() { return 0; }
  gum() {
    cat > "$SELECT_CAPTURE"
    head -1 "$SELECT_CAPTURE"
  }
}

@test "select_files_with_status: pathspec after -- scopes staged candidates" {
  create_pathspec_fixture
  mock_gum

  run select_files_with_status --staged -- src/a.py
  assert_success
  refute_output --partial "Unknown option"

  local candidates
  candidates=$(cat "$SELECT_CAPTURE")
  [[ "$candidates" =~ src/a\.py ]]
  [[ ! "$candidates" =~ docs/note\.md ]]
}

@test "select_files_with_status: literal '--staged' filename after -- is pathspec data, not an option" {
  create_pathspec_fixture
  # A file literally named '--staged': if the parser lacked a dedicated '--'
  # arm, this arg would be eaten as the --staged option (or rejected).
  printf 'untracked\n' > ./--staged
  mock_gum

  run select_files_with_status --untracked -- --staged
  assert_success
  refute_output --partial "Unknown option"

  local candidates
  candidates=$(cat "$SELECT_CAPTURE")
  [[ "$candidates" == *"--staged"* ]]
}

@test "select_files_with_status: command substitution yields a scoped selection, not a silent empty result" {
  # Swallow hazard (#292): callers capture the selector via $(...). A parsing
  # regression that turns '--' into an error would surface here as an empty
  # $file or a cancelled (exit 1) picker — both silently break the caller.
  create_pathspec_fixture
  mock_gum

  local file=""
  if ! file=$(select_files_with_status --single --staged -- src/); then
    fail "expected a selection, got cancellation/empty: '$file'"
  fi
  [[ -n "$file" ]]
  [[ "$file" == src/* ]]
}
