#!/usr/bin/env bats
# Integration tests for common workflows

# Load test helpers
load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
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

@test "workflow: rollback vs rewind behavior difference" {
  # Create two commits
  echo "Feature 1" > f1.txt
  git add f1.txt
  git commit -q -m "Feature 1"
  
  echo "Feature 2" > f2.txt
  git add f2.txt
  git commit -q -m "Feature 2"
  
  # Save commit hash
  local before_rollback
  before_rollback=$(git rev-parse HEAD)
  
  # Rollback discards changes from the commits
  # but preserves untracked and uncommitted changes
  run hug h rollback --force
  assert_success
  assert_file_exists "f2.txt"
  
  # Recommit to set up for rewind test
  git add f2.txt
  git commit -q -m "Feature 2 again"
  
  # Rewind removes files
  run hug h rewind HEAD~1 --force
  assert_success
  assert_file_not_exists "f2.txt"
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
