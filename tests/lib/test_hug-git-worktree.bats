#!/usr/bin/env bats

load '../test_helper'
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-output'
load '../../git-config/lib/hug-git-worktree'

setup() {
  # Create a test repository
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_worktrees "$TEST_REPO"
  cleanup_test_repo "$TEST_REPO"
}

@test "hug-git-worktree: get_worktrees returns empty when no worktrees exist" {
  declare -a worktree_paths=() branches=() commits=() status_dirty=() locked_status=()

  get_worktrees worktree_paths branches commits status_dirty locked_status

  assert_equal "${#worktree_paths[@]}" 0
  assert_equal "${#branches[@]}" 0
  assert_equal "${#commits[@]}" 0
  assert_equal "${#status_dirty[@]}" 0
  assert_equal "${#locked_status[@]}" 0
}

@test "hug-git-worktree: get_worktrees returns all worktrees when they exist" {
  # Create worktrees
  local feature_wt
  feature_wt=$(create_test_worktree "feature-1" "$TEST_REPO")

  declare -a worktree_paths=() branches=() commits=() status_dirty=() locked_status=()

  get_worktrees worktree_paths branches commits status_dirty locked_status

  assert_equal "${#worktree_paths[@]}" 1  # Feature worktree only (main repo excluded)
  assert_equal "${#branches[@]}" 1
  assert_equal "${#commits[@]}" 1
  assert_equal "${#status_dirty[@]}" 1
  assert_equal "${#locked_status[@]}" 1

  # Check that feature worktree is included
  local found_feature=false
  for path in "${worktree_paths[@]}"; do
    if [[ "$path" == "$feature_wt" ]]; then
      found_feature=true
      break
    fi
  done
  $found_feature || fail "Feature worktree path not found in worktree list"
}

@test "hug-git-worktree: get_current_worktree_path returns current directory" {
  cd "$TEST_REPO"
  local current_path
  current_path=$(get_current_worktree_path)

  assert_equal "$current_path" "$TEST_REPO"
}

@test "hug-git-worktree: worktree_exists correctly identifies existing worktree" {
  local feature_wt
  feature_wt=$(create_test_worktree "feature-1" "$TEST_REPO")

  worktree_exists "$feature_wt"
}

@test "hug-git-worktree: worktree_exists returns false for non-existent worktree" {
  ! worktree_exists "/nonexistent/path"
}

@test "hug-git-worktree: worktree_exists returns false for empty path" {
  ! worktree_exists ""
}

@test "hug-git-worktree: get_worktree_count returns correct count" {
  # Should start with 1 (main repository only)
  assert_equal "$(get_worktree_count)" 1

  # Create worktree
  create_test_worktree "feature-1" "$TEST_REPO"

  # Should now have 2
  assert_equal "$(get_worktree_count)" 2
}

@test "hug-git-worktree: validate_worktree_path accepts valid worktree" {
  local feature_wt
  feature_wt=$(create_test_worktree "feature-1" "$TEST_REPO")

  validate_worktree_path "$feature_wt"  # Should not fail
}

@test "hug-git-worktree: validate_worktree_path rejects empty path" {
  run validate_worktree_path ""

  assert_failure
  assert_output --partial "Worktree path cannot be empty"
}

@test "hug-git-worktree: validate_worktree_path rejects non-existent path" {
  run validate_worktree_path "/nonexistent/path"

  assert_failure
  assert_output --partial "Worktree path does not exist"
}

@test "hug-git-worktree: validate_worktree_path rejects non-directory" {
  local file_path="${TEST_REPO}/test-file"
  touch "$file_path"

  run validate_worktree_path "$file_path"

  assert_failure
  assert_output --partial "Worktree path is not a directory"

  rm "$file_path"
}

@test "hug-git-worktree: validate_worktree_path rejects non-worktree directory" {
  local not_worktree="/tmp/hug-test-not-worktree"
  mkdir -p "$not_worktree"

  run validate_worktree_path "$not_worktree"

  assert_failure
  assert_output --partial "Path is not a Git worktree"

  rmdir "$not_worktree"
}

@test "hug-git-worktree: branch_available_for_worktree accepts available branch" {
  branch_available_for_worktree "main"  # main should be available
}

@test "hug-git-worktree: branch_available_for_worktree rejects checked out branch" {
  # Create worktree for feature-1
  create_test_worktree "feature-1" "$TEST_REPO"

  ! branch_available_for_worktree "feature-1"
}

@test "hug-git-worktree: branch_available_for_worktree rejects non-existent branch" {
  ! branch_available_for_worktree "nonexistent-branch"
}

@test "hug-git-worktree: branch_available_for_worktree rejects empty branch name" {
  ! branch_available_for_worktree ""
}

@test "hug-git-worktree: validate_worktree_creation_path accepts valid path" {
  local parent_dir="/tmp/hug-test-validate"
  mkdir -p "$parent_dir"
  local valid_path="${parent_dir}/new-worktree"

  validate_worktree_creation_path "$valid_path"

  rmdir "$parent_dir"
}

@test "hug-git-worktree: validate_worktree_creation_path rejects empty path" {
  run validate_worktree_creation_path ""

  assert_failure
  assert_output --partial "Worktree path cannot be empty"
}

@test "hug-git-worktree: validate_worktree_creation_path rejects existing path" {
  local existing_path="${TEST_REPO}/existing"
  mkdir -p "$existing_path"

  run validate_worktree_creation_path "$existing_path"

  assert_failure
  assert_output --partial "Target path already exists"

  rmdir "$existing_path"
}

@test "hug-git-worktree: validate_worktree_creation_path rejects non-existent parent" {
  local path_with_nonexistent_parent="/tmp/nonexistent/parent/path"

  # Pass false to disable auto-creation of parent directory
  run validate_worktree_creation_path "$path_with_nonexistent_parent" "false"

  assert_failure
  assert_output --partial "Parent directory does not exist"
}

@test "hug-git-worktree: generate_worktree_path creates sensible default" {
  local generated_path
  generated_path=$(generate_worktree_path "feature-1")

  assert_equal "$generated_path" "../worktrees-$(basename "$TEST_REPO")/feature-1"
}

@test "hug-git-worktree: generate_worktree_path sanitizes branch name" {
  local generated_path
  generated_path=$(generate_worktree_path "feature/auth.v2")

  assert_equal "$generated_path" "../worktrees-$(basename "$TEST_REPO")/feature-auth-v2"
}

@test "hug-git-worktree: generate_unique_worktree_path returns unique path" {
  # Create a directory at the default location
  local default_path
  default_path=$(generate_worktree_path "feature-1")
  mkdir -p "$default_path"

  local unique_path
  unique_path=$(generate_unique_worktree_path "feature-1")

  # Should be different from default path
  assert_not_equal "$unique_path" "$default_path"
  assert_regex_match "$unique_path" ".*-1$"

  # Clean up
  rm -rf "$default_path"
}

@test "hug-git-worktree: generate_unique_worktree_path returns default if available" {
  local default_path
  default_path=$(generate_worktree_path "feature-unique")

  # Should return default path since it doesn't exist
  local unique_path
  unique_path=$(generate_unique_worktree_path "feature-unique")

  assert_equal "$unique_path" "$default_path"
}

@test "hug-git-worktree: create_worktree succeeds with valid inputs" {
  local new_path="${TEST_REPO}-wt-test-create"
  run create_worktree "main" "$new_path" true false

  assert_success
  assert_worktree_exists "$new_path"
  assert_worktree_branch "$new_path" "main"
}

@test "hug-git-worktree: create_worktree performs dry run correctly" {
  local new_path="${TEST_REPO}-wt-test-dry-run"
  run create_worktree "main" "$new_path" true true

  assert_success
  assert_output --partial "Would create worktree"
  assert_worktree_not_exists "$new_path"
}

@test "hug-git-worktree: create_worktree fails with non-existent branch" {
  local new_path="${TEST_REPO}-wt-test-fail"
  run create_worktree "nonexistent-branch" "$new_path" true false

  assert_failure
  assert_output --partial "Branch 'nonexistent-branch' does not exist locally"
  assert_worktree_not_exists "$new_path"
}

@test "hug-git-worktree: create_worktree fails with checked out branch" {
  # Create worktree for feature-1
  create_test_worktree "feature-1" "$TEST_REPO"

  local new_path="${TEST_REPO}-wt-test-checked-out"
  run create_worktree "feature-1" "$new_path" true false

  assert_failure
  assert_output --partial "Branch 'feature-1' is already checked out"
  assert_worktree_not_exists "$new_path"
}

@test "hug-git-worktree: remove_worktree succeeds with valid inputs" {
  local feature_wt
  feature_wt=$(create_test_worktree "feature-1" "$TEST_REPO")

  run remove_worktree "$feature_wt" true false

  assert_success
  assert_output --partial "Worktree removed"
  assert_worktree_not_exists "$feature_wt"
}

@test "hug-git-worktree: remove_worktree performs dry run correctly" {
  local feature_wt
  feature_wt=$(create_test_worktree "feature-1" "$TEST_REPO")

  run remove_worktree "$feature_wt" true true

  assert_success
  assert_output --partial "Would remove worktree"
  assert_worktree_exists "$feature_wt"  # Should still exist
}

@test "hug-git-worktree: remove_worktree fails with current worktree" {
  cd "$TEST_REPO"
  run remove_worktree "$TEST_REPO" true false

  assert_failure
  assert_output --partial "Cannot remove current worktree"
}

@test "hug-git-worktree: remove_worktree fails with dirty worktree without force" {
  local feature_wt
  feature_wt=$(create_test_worktree_with_dirty_changes "feature-1" "$TEST_REPO")

  run remove_worktree "$feature_wt" false false

  assert_failure
  assert_output --partial "Worktree has uncommitted changes"
  assert_worktree_exists "$feature_wt"
}

@test "hug-git-worktree: remove_worktree removes dirty worktree with force" {
  local feature_wt
  feature_wt=$(create_test_worktree_with_dirty_changes "feature-1" "$TEST_REPO")

  run remove_worktree "$feature_wt" true false

  assert_success
  assert_output --partial "Worktree removed"
  assert_worktree_not_exists "$feature_wt"
}

@test "hug-git-worktree: switch_to_worktree succeeds with valid path" {
  local feature_wt
  feature_wt=$(create_test_worktree "feature-1" "$TEST_REPO")

  # Note: We can't test actual directory change in bats, but we can test validation
  run switch_to_worktree "$feature_wt"

  assert_success
  assert_output --partial "Switched to worktree"
}

@test "hug-git-worktree: switch_to_worktree fails with invalid path" {
  run switch_to_worktree "/nonexistent/path"

  assert_failure
  assert_output --partial "Cannot switch to worktree"
}

@test "hug-git-worktree: prune_worktrees handles no orphaned worktrees" {
  # Source the library to access the function
  source "$HUG_HOME/git-config/lib/hug-git-worktree"

  run prune_worktrees false false

  assert_success
  assert_output --partial "No orphaned worktrees found"
}

@test "hug-git-worktree: is_worktree_not_main returns false for main repository" {
  cd "$TEST_REPO"
  ! is_worktree_not_main
}

@test "hug-git-worktree: is_worktree_not_main returns true for worktree" {
  local feature_wt
  feature_wt=$(create_test_worktree "feature-1" "$TEST_REPO")

  cd "$feature_wt"
  is_worktree_not_main
}

@test "hug-git-worktree: is_worktree_not_main returns false when not in git repo" {
  cd /tmp
  ! is_worktree_not_main
}