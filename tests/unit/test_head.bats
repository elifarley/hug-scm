#!/usr/bin/env bats
# Tests for HEAD operations (h*)

# Load test helpers
load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

@test "hug h back: moves HEAD back one commit, keeps changes staged" {
  # Get current HEAD
  local original_head
  original_head=$(git rev-parse HEAD)
  
  run hug h back
  assert_success
  
  # HEAD should have moved back
  local new_head
  new_head=$(git rev-parse HEAD)
  assert_not_equal "$original_head" "$new_head"
  
  # Changes should be staged
  run git diff --cached --name-only
  assert_output --partial "feature2.txt"
}

@test "hug h back N: moves HEAD back N commits" {
  # Get current HEAD
  local original_head
  original_head=$(git rev-parse HEAD)
  
  run hug h back 2
  assert_success
  
  # Should have moved back 2 commits
  local new_head
  new_head=$(git rev-parse HEAD)
  
  # Check we're at initial commit
  run git log --oneline
  assert_output --partial "Initial commit"
  refute_output --partial "Add feature 1"
}

@test "hug h undo: moves HEAD back and unstages changes" {
  run hug h undo
  assert_success
  
  # Changes should be unstaged
  run git diff --name-only
  assert_output --partial "feature2.txt"
  
  # Nothing should be staged
  run git diff --cached
  assert_output ""
}

@test "hug h undo N: undoes N commits" {
  run hug h undo 2
  assert_success
  
  # Both files should be present but unstaged
  assert_file_exists "feature1.txt"
  assert_file_exists "feature2.txt"
  
  # Should be at initial commit
  run git log --oneline
  assert_output --partial "Initial commit"
  refute_output --partial "Add feature"
}

@test "hug h steps: shows steps to last change in file" {
  # file feature2.txt was changed in the last commit
  run hug h steps feature2.txt
  assert_success
  assert_output --partial "0 steps back"
  
  # feature1.txt was changed 1 commit ago
  run hug h steps feature1.txt
  assert_success
  assert_output --partial "1 step"
}

@test "hug h rollback: removes commit but preserves work" {
  # Add a change that we'll rollback
  echo "test" > temp.txt
  git add temp.txt
  git commit -q -m "Temp commit"
  
  run hug h rollback
  assert_success
  
  # Commit should be gone
  run git log --oneline
  refute_output --partial "Temp commit"
  
  # But file should still exist
  assert_file_exists "temp.txt"
}

@test "hug h rollback N: rolls back N commits" {
  run hug h rollback 2
  assert_success
  
  # Should be at initial commit
  run git log --oneline
  assert_output --partial "Initial commit"
  refute_output --partial "Add feature"
  
  # But files should still exist (preserved work)
  assert_file_exists "feature1.txt"
  assert_file_exists "feature2.txt"
}

@test "hug h rewind: destructive rewind to commit" {
  # Get the commit hash of first commit
  local first_commit
  first_commit=$(git rev-list --max-parents=0 HEAD)
  
  run hug h rewind "$first_commit"
  assert_success
  
  # Should be at initial commit with clean state
  run git log --oneline
  assert_output --partial "Initial commit"
  refute_output --partial "Add feature"
  
  # Added files should be gone
  assert_file_not_exists "feature1.txt"
  assert_file_not_exists "feature2.txt"
  
  # Working tree should be clean
  assert_git_clean
}

@test "hug h back with commit hash: moves to specific commit" {
  # Get hash of first feature commit
  local target_commit
  target_commit=$(git log --oneline --all | grep "Add feature 1" | awk '{print $1}')
  
  run hug h back "$target_commit"
  assert_success
  
  # HEAD should be at that commit
  run git log --oneline -1
  assert_output --partial "Add feature 1"
}

@test "hug h steps --raw: shows raw commit hash" {
  run hug h steps --raw feature2.txt
  assert_success
  
  # Output should contain a commit hash (40 char hex)
  assert_output --regexp "[0-9a-f]{40}"
}

@test "hug h undo with no commits fails gracefully" {
  # Create a fresh repo at initial commit
  local test_repo
  test_repo=$(create_test_repo)
  cd "$test_repo"
  
  # Try to undo when there's only one commit
  run hug h undo
  
  # Should fail or handle gracefully
  assert_failure
}

@test "hug h operations preserve untracked files" {
  # Add an untracked file
  echo "untracked" > untracked.txt
  
  run hug h back
  assert_success
  
  # Untracked file should still exist
  assert_file_exists "untracked.txt"
}
