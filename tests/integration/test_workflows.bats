#!/usr/bin/env bats
# Integration tests for common workflows

# Load test helpers
load '../test_helper'

setup() {
  require_hug
  
  # Create stable work directory to avoid getcwd issues
  TEST_WORK_DIR=$(mktemp -d -t "hug-workflow-test-XXXXXX")
  
  # Create repo in work directory
  TEST_REPO="$TEST_WORK_DIR/test-repo"
  mkdir -p "$TEST_REPO"
  
  # Initialize repo in subshell to avoid directory issues
  (
    cd "$TEST_REPO" || exit 1
    git init -q --initial-branch=main
    git config user.email "test@hug-scm.test"
    git config user.name "Hug Test"
    
    echo "# Test Repository" > README.md
    git add README.md
    git commit -q -m "Initial commit"
  ) || {
    echo "ERROR: Failed to initialize test repo" >&2
    return 1
  }
  
  # Use pushd for automatic directory management
  pushd "$TEST_REPO" > /dev/null
}

teardown() {
  # CRITICAL: Exit directory BEFORE cleanup to prevent getcwd errors
  popd > /dev/null 2>&1 || cd /tmp
  
  # Cleanup work directory (includes TEST_REPO)
  if [[ -n "${TEST_WORK_DIR:-}" && -d "$TEST_WORK_DIR" ]]; then
    rm -rf "$TEST_WORK_DIR"
  fi
}

@test "workflow: make changes, stage, commit, and verify" {
  # Make a change
  echo "New feature" > feature.txt
  
  # Stage it
  run hug aa
  assert_success
  
  # Commit it
  run hug c -m "Add new feature"
  assert_success
  
  # Verify it's in history
  run git log --oneline
  assert_output --partial "Add new feature"
  
  # Working tree should be clean
  assert_git_clean
}

@test "workflow: modify file, discard changes, verify clean" {
  # Modify a file
  echo "Bad changes" >> README.md
  
  # Verify it's modified
  run git status --porcelain
  assert_output --partial "M README.md"
  
  # Discard changes
  run hug w discard -f README.md
  assert_success
  
  # Should be clean
  assert_git_clean
}

@test "workflow: create WIP branch, make changes, switch back" {
  # Make some changes
  echo "Work in progress" > wip.txt
  git add wip.txt
  
  # Park the work (this creates a WIP branch and switches back)
  run hug wip "Draft feature"
  assert_success
  
  # Should be on original branch with clean working tree
  assert_git_clean
  
  # WIP branch should exist
  run git branch
  assert_output --partial "WIP/"
}

@test "workflow: stage selectively, commit, then commit remaining" {
  # Create multiple files
  echo "Feature A" > a.txt
  echo "Feature B" > b.txt
  
  # Stage only one file
  run hug a a.txt
  assert_success
  
  # Commit it
  run hug c -m "Add feature A"
  assert_success
  
  # b.txt should still be untracked
  run git status --porcelain
  assert_output --partial "?? b.txt"
  
  # Stage and commit the second file
  run hug aa
  assert_success
  run hug c -m "Add feature B"
  assert_success
  
  # Now should be clean
  assert_git_clean
}

@test "workflow: commit all changes in one go with caa" {
  # Create multiple files and changes
  echo "Change 1" >> README.md
  echo "New file" > new.txt
  
  # Commit everything at once
  run hug caa -m "Batch changes"
  assert_success
  
  # Should be clean
  assert_git_clean
  
  # Both changes should be in the commit
  run git show --name-only
  assert_output --partial "README.md"
  assert_output --partial "new.txt"
}

@test "workflow: back last commit, fix, and recommit" {
  # Make a commit
  echo "Mistake" > file.txt
  hug a file.txt
  hug c -q -m "Wrong commit"
  
  # Go back 1 commit
  run hug h back --force # Requires user confirmation if we don't use the `--force` flag.
  assert_success
  
  # Fix the content
  echo "Correct content" > file.txt
  
  # Commit again
  run hug ca -m "Correct commit"
  assert_success
  
  # Latest commit should have correct message
  run git log -1 --pretty=%s
  assert_output "Correct commit"
}

@test "workflow: multiple files cleanup with zap-all" {
  # Create various types of changes
  echo "Staged" > staged.txt
  hug aa
  
  echo "Modified" >> README.md
  
  echo "Untracked" > untracked.txt
  
  # Zap everything
  run hug w zap-all --force
  assert_success
  
  # Everything should be clean
  assert_git_clean
  assert_file_not_exists "staged.txt"
  assert_file_not_exists "untracked.txt"
}

@test "workflow: check status variations" {
  # Start with changes
  echo "Change" >> README.md
  echo "New" > new.txt
  
  # Test different status commands
  run hug s
  assert_success
  
  run hug sl
  assert_success
  refute_output --partial "new.txt"
  
  run hug sla
  assert_success
  assert_output --partial "new.txt"
}

@test "workflow: preview destructive operation with dry-run" {
  # Make changes
  echo "Change" >> README.md
  echo "Untracked" > temp.txt
  
  # Preview cleanup
  run hug w zap-all --dry-run
  assert_success
  assert_output --partial "would be"
  
  # Changes should still exist
  assert_file_exists "temp.txt"
  run git status --porcelain
  assert_output --partial "M README.md"
}

@test "workflow: rollback safety vs rewind destructiveness" {
  # Test 1: Rollback base case (no conflicts) - discards committed changes
  local TEST_REPO1
  TEST_REPO1=$(create_test_repo_with_history)
  (
    cd "$TEST_REPO1" || { echo "cd failed"; exit 1; }
    run hug h rollback --force
    assert_success
    assert_file_not_exists "feature2.txt"  # Committed change discarded
    assert_file_exists "feature1.txt"
    assert_git_clean
    run git log --oneline -2
    refute_output --partial "Add feature 2"
  )
  rm -rf "$TEST_REPO1"
  
  # Test 2: Rollback preserves untracked files
  local TEST_REPO2
  TEST_REPO2=$(create_test_repo_with_history)
  (
    cd "$TEST_REPO2" || { echo "cd failed"; exit 1; }
    echo "untracked data" > untracked.txt
    
    run hug h rollback --force
    assert_success
    assert_file_not_exists "feature2.txt"
    assert_file_exists "untracked.txt"
    run cat untracked.txt
    assert_output --partial "untracked data"
    run git status --porcelain
    assert_output --partial "?? untracked.txt"
  )
  rm -rf "$TEST_REPO2"
  
  # Test 3: Rollback safety abort on conflicting uncommitted changes
  local TEST_REPO3
  TEST_REPO3=$(create_test_repo_with_history)
  (
    cd "$TEST_REPO3" || { echo "cd failed"; exit 1; }
    echo "local mod to f2" >> feature2.txt  # Conflicting uncommitted change to file in commit being rolled back
    
    run hug h rollback --force
    [ "$status" -ne 0 ]  # Git aborts to prevent loss
    assert_output --partial "not uptodate"
    run cat feature2.txt
    assert_output --partial "local mod to f2"  # Local change preserved
    run git status --porcelain
    assert_output --partial "M feature2.txt"
  )
  rm -rf "$TEST_REPO3"
  
  # Test 4: Rewind base case - discards committed changes
  local TEST_REPO4
  TEST_REPO4=$(create_test_repo_with_history)
  (
    cd "$TEST_REPO4" || { echo "cd failed"; exit 1; }
    run hug h rewind HEAD~1 --force
    assert_success
    assert_file_not_exists "feature2.txt"
    assert_file_exists "feature1.txt"
    assert_git_clean
    run git log --oneline -2
    refute_output --partial "Add feature 2"
  )
  rm -rf "$TEST_REPO4"
  
  # Test 5: Rewind destructiveness - overwrites uncommitted changes
  local TEST_REPO5
  TEST_REPO5=$(create_test_repo_with_history)
  (
    cd "$TEST_REPO5" || { echo "cd failed"; exit 1; }
    echo "local mod to f1" >> feature1.txt  # Conflicting uncommitted change
    
    run hug h rewind HEAD~1 --force
    assert_success  # Overwrites without aborting
    run cat feature1.txt
    refute_output --partial "local mod to f1"  # Local change lost
    assert_git_clean
  )
  rm -rf "$TEST_REPO5"
  
  # Test 6: Rewind preserves untracked files (like rollback)
  local TEST_REPO6
  TEST_REPO6=$(create_test_repo_with_history)
  (
    cd "$TEST_REPO6" || { echo "cd failed"; exit 1; }
    echo "untracked data" > untracked.txt
    
    run hug h rewind HEAD~1 --force
    assert_success
    assert_file_not_exists "feature2.txt"
    assert_file_exists "untracked.txt"
    run cat untracked.txt
    assert_output --partial "untracked data"
    run git status --porcelain
    assert_output --partial "?? untracked.txt"
  )
  rm -rf "$TEST_REPO6"
}

@test "workflow: safety - confirm dialogs prevent accidents" {
  # Create changes
  echo "Important change" >> README.md
  
  # Try to discard without force (should timeout waiting for input)
  run timeout 2 bash -c "echo '' | hug w discard README.md 2>&1 || true"
  
  # File should still have changes (operation didn't complete)
  run git diff README.md
  assert_output --partial "Important change"
}
