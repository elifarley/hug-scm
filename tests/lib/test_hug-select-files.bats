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
