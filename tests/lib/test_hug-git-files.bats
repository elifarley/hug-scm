#!/usr/bin/env bats
# Tests for hug-git-files library: file listing functions

load '../test_helper'
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-git-repo'
load '../../git-config/lib/hug-git-files'

# Helper to create test repo with files in subdirectories
create_test_repo_with_structure() {
  local test_repo
  test_repo=$(create_test_repo)
  
  (
    cd "$test_repo" || exit 1
    
    # Create directory structure
    mkdir -p src/components
    mkdir -p src/utils
    mkdir -p docs
    
    # Create and commit files
    echo "root file 1" > root1.txt
    echo "root file 2" > root2.txt
    echo "component A" > src/components/ComponentA.js
    echo "component B" > src/components/ComponentB.js
    echo "util 1" > src/utils/helper.js
    echo "doc" > docs/README.md
    git add -A
    git commit -q -m "Initial structure"
    
    # Make changes for testing
    echo "modified" >> root1.txt
    echo "modified" >> src/components/ComponentA.js
    echo "modified" >> src/utils/helper.js
    git add root1.txt  # Stage root1.txt
    echo "untracked" > src/untracked.js
  )
  
  echo "$test_repo"
}

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_structure)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

################################################################################
# list_tracked_files TESTS
################################################################################

@test "list_tracked_files: lists all tracked files from repo root" {
  # From repo root, without --cwd, should list all tracked files
  mapfile -t files < <(list_tracked_files)
  
  # Should include files from all directories
  [[ " ${files[*]} " =~ " root1.txt " ]]
  [[ " ${files[*]} " =~ " root2.txt " ]]
  [[ " ${files[*]} " =~ " src/components/ComponentA.js " ]]
  [[ " ${files[*]} " =~ " src/utils/helper.js " ]]
  [[ " ${files[*]} " =~ " docs/README.md " ]]
}

@test "list_tracked_files: lists all files recursively with --cwd from repo root" {
  # From repo root, with --cwd, should list all files (same as without --cwd from root)
  # This is because -- . from root includes all subdirectories
  mapfile -t files < <(list_tracked_files --cwd)
  
  # Should include root files
  [[ " ${files[*]} " =~ " root1.txt " ]]
  [[ " ${files[*]} " =~ " root2.txt " ]]
  
  # Should include subdirectory files (recursive behavior)
  [[ " ${files[*]} " =~ " src/components/ComponentA.js " ]]
  [[ " ${files[*]} " =~ " docs/README.md " ]]
}

@test "list_tracked_files: lists all files from subdirectory without --cwd" {
  cd src/components
  
  # Without --cwd, should list ALL tracked files in repository
  mapfile -t files < <(list_tracked_files)
  
  # Should include files from root (with relative paths)
  [[ " ${files[*]} " =~ " ../../root1.txt " ]]
  [[ " ${files[*]} " =~ " ../../root2.txt " ]]
  
  # Should include files from current directory
  [[ " ${files[*]} " =~ " ComponentA.js " ]]
  [[ " ${files[*]} " =~ " ComponentB.js " ]]
  
  # Should include files from sibling directories
  [[ " ${files[*]} " =~ " ../utils/helper.js " ]]
  [[ " ${files[*]} " =~ " ../../docs/README.md " ]]
}

@test "list_tracked_files: lists only current directory files with --cwd from subdirectory" {
  cd src/components
  
  # With --cwd, should only list files in current directory and subdirectories
  mapfile -t files < <(list_tracked_files --cwd)
  
  # Should include files from current directory
  [[ " ${files[*]} " =~ " ComponentA.js " ]]
  [[ " ${files[*]} " =~ " ComponentB.js " ]]
  
  # Should NOT include files from parent or sibling directories
  ! [[ " ${files[*]} " =~ " root1.txt " ]]
  ! [[ " ${files[*]} " =~ " helper.js " ]]
  ! [[ " ${files[*]} " =~ " README.md " ]]
}

@test "list_tracked_files: paths are relative to current directory" {
  cd src
  
  # Without --cwd, all files should be listed with paths relative to src/
  mapfile -t files < <(list_tracked_files)
  
  # Files in current directory should have no prefix
  [[ " ${files[*]} " =~ " utils/helper.js " ]]
  
  # Files in parent directory should have ../ prefix
  [[ " ${files[*]} " =~ " ../root1.txt " ]]
  
  # Files in sibling directory should have ../ prefix
  [[ " ${files[*]} " =~ " ../docs/README.md " ]]
}

################################################################################
# list_staged_files TESTS
################################################################################

@test "list_staged_files: lists all staged files from subdirectory without --cwd" {
  cd src/components
  
  # Without --cwd, should list all staged files in repository
  mapfile -t files < <(list_staged_files)
  
  # Should include staged file from root (with relative path)
  [[ " ${files[*]} " =~ " ../../root1.txt " ]]
}

@test "list_staged_files: lists only current directory staged files with --cwd" {
  # Stage a file in subdirectory
  git add src/components/ComponentA.js
  
  cd src/components
  
  # With --cwd, should only list staged files in current directory
  mapfile -t files < <(list_staged_files --cwd)
  
  # Should include file from current directory
  [[ " ${files[*]} " =~ " ComponentA.js " ]]
  
  # Should NOT include staged file from parent directory
  ! [[ " ${files[*]} " =~ " root1.txt " ]]
}

################################################################################
# list_unstaged_files TESTS
################################################################################

@test "list_unstaged_files: lists all unstaged files from subdirectory without --cwd" {
  cd src/components
  
  # Without --cwd, should list all unstaged files in repository
  mapfile -t files < <(list_unstaged_files)
  
  # Should include unstaged files from different directories
  [[ " ${files[*]} " =~ " ComponentA.js " ]]
  [[ " ${files[*]} " =~ " ../utils/helper.js " ]]
}

@test "list_unstaged_files: lists only current directory unstaged files with --cwd" {
  cd src/components
  
  # With --cwd, should only list unstaged files in current directory
  mapfile -t files < <(list_unstaged_files --cwd)
  
  # Should include file from current directory
  [[ " ${files[*]} " =~ " ComponentA.js " ]]
  
  # Should NOT include unstaged files from other directories
  ! [[ " ${files[*]} " =~ " helper.js " ]]
}

################################################################################
# list_untracked_files TESTS
################################################################################

@test "list_staged_files: detects renames when both old and new files are staged" {
  # Create a file and commit it
  echo "original content" > original.txt
  git add original.txt
  git commit -q -m "add original file"

  # Manually rename and stage both files (simulates: mv old new && git add old new)
  mv original.txt renamed.txt
  git add original.txt renamed.txt

  # Verify rename is detected (not separate delete+add)
  mapfile -t lines < <(list_staged_files --status)

  # Should have exactly one line with rename status (R100)
  [[ ${#lines[@]} -eq 1 ]]
  [[ "${lines[0]}" =~ R100.*renamed\.txt ]]

  # Should NOT show separate delete or add entries
  ! [[ "${lines[*]}" =~ $'\t'A\t ]]  # No separate Add
  ! [[ "${lines[*]}" =~ $'\t'D\t ]]  # No separate Delete
}

@test "list_staged_files: git mv is detected as rename" {
  # Create a file and commit it
  echo "original content" > gitmv_original.txt
  git add gitmv_original.txt
  git commit -q -m "add original file"

  # Use git mv (stages the rename automatically)
  git mv gitmv_original.txt gitmv_renamed.txt

  # Verify rename is detected
  mapfile -t lines < <(list_staged_files --status)

  # Should have exactly one line with rename status (R100)
  [[ ${#lines[@]} -eq 1 ]]
  [[ "${lines[0]}" =~ R100.*gitmv_renamed\.txt ]]
}

################################################################################
# list_untracked_files TESTS
################################################################################

@test "list_untracked_files: lists all untracked files from subdirectory without --cwd" {
  cd src/components
  
  # Without --cwd, should list all untracked files in repository
  mapfile -t files < <(list_untracked_files)
  
  # Should include untracked file (with relative path)
  [[ " ${files[*]} " =~ " ../untracked.js " ]]
}

@test "list_untracked_files: lists only current directory untracked files with --cwd" {
  # Create untracked file in current directory
  echo "local untracked" > src/components/local-untracked.js
  
  cd src/components
  
  # With --cwd, should only list untracked files in current directory
  mapfile -t files < <(list_untracked_files --cwd)
  
  # Should include file from current directory
  [[ " ${files[*]} " =~ " local-untracked.js " ]]
  
  # Should NOT include untracked files from parent directory
  ! [[ " ${files[*]} " =~ " untracked.js " ]]
}
