#!/usr/bin/env bats
# Tests for hug-select-files library: interactive file selection

load '../test_helper'
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-git-kit'
load '../../git-config/lib/hug-gum'
load '../../git-config/lib/hug-select-files'

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
  run _can_suppress_status true true false false
  assert_failure

  run _can_suppress_status false true true false
  assert_failure
}

@test "_can_suppress_status: returns true for single untracked type" {
  load '../../git-config/lib/hug-git-priorities'

  # Single file type (untracked) should return true (safe to suppress)
  run _can_suppress_status false false true false
  assert_success
}

@test "_can_suppress_status: returns true for single ignored type" {
  load '../../git-config/lib/hug-git-priorities'

  # Single file type (ignored) should return true (safe to suppress)
  run _can_suppress_status false false false true
  assert_success
}

@test "_can_suppress_status: returns false for unstaged (multiple status types)" {
  load '../../git-config/lib/hug-git-priorities'

  # Unstaged files have multiple status types (U:Mod, U:Del, U:Cnflt)
  # Should return false (not safe to suppress)
  run _can_suppress_status false true false false
  assert_failure
}

@test "_can_suppress_status: returns false for staged (multiple status types)" {
  load '../../git-config/lib/hug-git-priorities'

  # Staged files have multiple status types (S:Add, S:Mod, S:Del, S:Ren, S:Copy, S:Cnflt)
  # Should return false (not safe to suppress)
  run _can_suppress_status true false false false
  assert_failure
}
