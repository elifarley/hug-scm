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

# Head movement commands require user confirmation unless we use the `--force`.
# TODO create additional tests that don't use the `--force` flag (so we need to pipe a `y` to the run command)

@test "hug h back: moves HEAD back one commit, keeps changes staged" {
  # Get current HEAD
  local original_head
  original_head=$(git rev-parse HEAD)
  
  run hug h back --force
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
  
  run hug h back 2 --force
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
  run hug h undo --force
  assert_success
  
  # Changes should be unstaged or untracked after an undo.
  # For this specific case, 'feature2.txt' must be untracked.
  run git ls-files --others --exclude-standard
  assert_output --partial "feature2.txt"
  
  # Nothing should be staged
  run git diff --cached
  assert_output ""

  # Nothing should be unstaged
  run git diff --name-only
  assert_output ""
}

@test "hug h undo N: undoes N commits" {
  run hug h undo 2 --force
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
  # Add an uncommitted change that should be preserved
  echo "uncommitted" > uncommitted.txt
  
  # Add a change that we'll rollback (committed)
  echo "test" > temp.txt
  git add temp.txt
  git commit -q -m "Temp commit"
  
  run hug h rollback --force
  assert_success
  
  # Commit should be gone
  run git log --oneline
  refute_output --partial "Temp commit"
  
  # Committed file should NOT exist (rollback discards commit changes)
  assert_file_not_exists "temp.txt"
  
  # But uncommitted file should still exist (uncommitted changes preserved)
  assert_file_exists "uncommitted.txt"
}

@test "hug h rollback N: rolls back N commits" {
  # Add an uncommitted change that should be preserved
  echo "uncommitted" > uncommitted.txt
  
  run hug h rollback 2 --force
  assert_success
  
  # Should be at initial commit
  run git log --oneline
  assert_output --partial "Initial commit"
  refute_output --partial "Add feature"
  
  # Committed files should NOT exist (rollback discards commit changes)
  assert_file_not_exists "feature1.txt"
  assert_file_not_exists "feature2.txt"
  
  # But uncommitted file should still exist (uncommitted changes preserved)
  assert_file_exists "uncommitted.txt"
}

@test "hug h rewind: destructive rewind to commit" {
  # Get the commit hash of first commit
  local first_commit
  first_commit=$(git rev-list --max-parents=0 HEAD)
  
  run hug h rewind "$first_commit" --force
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
  
  run hug h back "$target_commit" --force
  assert_success
  
  # HEAD should be at that commit
  run git log --oneline -1
  assert_output --partial "Add feature 1"
}

@test "hug h steps --raw: shows raw step count" {
  run hug h steps --raw feature2.txt
  assert_success
  
  # --raw option returns just the step count (0 for file modified in HEAD)
  assert_output "0"
  
  # Test with a file from an older commit
  run hug h steps --raw feature1.txt
  assert_success
  assert_output "1"
}

@test "hug h undo with no commits handles gracefully" {
  # Create a fresh repo at initial commit
  local test_repo
  test_repo=$(create_test_repo)
  cd "$test_repo"
  
  # Try to undo when there's only one commit
  run hug h undo --force
  
  # Should succeed with info message (no commits to undo)
  assert_success
  assert_output --partial "Already at target"
}

@test "hug h operations preserve untracked files" {
  # Add an untracked file
  echo "untracked" > untracked.txt
  
  run hug h back --force
  assert_success
  
  # Untracked file should still exist
  assert_file_exists "untracked.txt"
}
