#!/usr/bin/env bats

setup() {
  load '../test_helper'

  # Create a test repository with branches
  TEST_REPO=$(create_test_repo_with_branches)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_worktrees "$TEST_REPO"
  cleanup_test_repo "$TEST_REPO"
}

@test "hug wtc: shows help when --help flag is used" {
  run git-wtc --help
  assert_success
  assert_output --partial "hug wtc: Create worktree for existing branch"
}

@test "hug wtc: creates worktree for existing branch" {
  # Test creating worktree for feature-1 branch with force flag to skip confirmation
  run git-wtc feature-1 -f
  assert_success

  # Extract path from output and resolve it to remove ../
  local worktree_path
  worktree_path=$(echo "$output" | grep "Path:" | sed 's/.*Path: //' | sed 's/\s*$//')
  worktree_path="$(cd "$(dirname "$worktree_path")" && pwd)/$(basename "$worktree_path")"

  # Verify worktree was created
  assert_worktree_exists "$worktree_path"

  # Verify worktree is on correct branch
  cd "$worktree_path"
  assert_git_clean
  assert_equal "$(git branch --show-current)" "feature-1"

  # Verify worktree contains expected file from feature-1 branch
  assert_file_exists "feature1.txt"
}

@test "hug wtc: creates worktree at custom path" {
  # Create a custom directory for worktree
  local custom_path="${TEST_REPO}-custom-feature2"
  mkdir -p "$(dirname "$custom_path")"

  # Test creating worktree with custom path
  run git-wtc feature-2 "$custom_path" -f
  assert_success
  assert_output --partial "Path: $custom_path"

  # Verify worktree was created at custom path
  assert_worktree_exists "$custom_path"

  # Verify worktree is on correct branch
  cd "$custom_path"
  assert_git_clean
  assert_equal "$(git branch --show-current)" "feature-2"

  # Verify worktree contains expected file from feature-2 branch
  assert_file_exists "feature2.txt"
}

@test "hug wtc: dry run mode shows what would be done" {
  # Test dry run mode
  run git-wtc feature-1 --dry-run
  assert_success
  assert_output --partial "Mode: DRY RUN"
  assert_output --partial "Would create worktree for branch 'feature-1'"

  # Verify no worktree was actually created
  local worktree_path
  worktree_path=$(echo "$output" | grep "Path:" | sed 's/.*Path: //' | sed 's/\s*$//')
  worktree_path="$(cd "$(dirname "$worktree_path")" && pwd)/$(basename "$worktree_path")"

  # The worktree should NOT exist in dry run mode
  assert_dir_not_exists "$worktree_path"
}

@test "hug wtc: error when branch does not exist" {
  # Test with non-existent branch
  run git-wtc non-existent-branch -f
  assert_failure

  # Should show appropriate error message
  assert_output --partial "does not exist locally"
  assert_output --partial "Create it first with"
}

@test "hug wtc: interactive mode with no branch argument" {
  # Disable gum to avoid hanging in interactive branch selection
  disable_gum_for_test

  # Test interactive mode (no arguments)
  run git-wtc
  assert_failure  # Exits with code 1 due to cancellation

  # Should show cancellation message since no interactive selection possible
  assert_output --partial "Cancelled"
}

@test "hug wtc: error when branch already has worktree" {
  # First, create a worktree for feature-1
  run git-wtc feature-1 -f
  assert_success

  # Try to create another worktree for the same branch - should fail
  run git-wtc feature-1 -f
  assert_failure

  # Should show appropriate error message
  assert_output --partial "already checked out in another worktree"
}