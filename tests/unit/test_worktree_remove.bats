#!/usr/bin/env bats

setup() {
  load '../test_helper'

  # Create a test repository with branches and worktrees
  TEST_REPO=$(create_test_repo_with_branches)
  cd "$TEST_REPO"

  # Create test worktrees
  FEATURE_WT=$(create_test_worktree "feature-1" "$TEST_REPO")
  HOTFIX_WT=$(create_test_worktree "hotfix-1" "$TEST_REPO")
}

teardown() {
  cleanup_test_worktrees "$TEST_REPO"
  cleanup_test_repo "$TEST_REPO"
}

@test "hug wtr: shows help when --help flag is used" {
  run git-wt-remove --help
  assert_success
  assert_output --partial "hug wtr: Remove worktree safely"
}

@test "hug wtr: shows interactive menu when no path provided" {
  cd "$TEST_REPO"
  echo "1" | run git-wt-remove  # Select first worktree

  # Should show interactive menu with available worktrees
  assert_success
  assert_output --partial "Select worktree to remove"
}

@test "hug wtr: removes worktree at specified path" {
  cd "$TEST_REPO"
  run git-wt-remove "$FEATURE_WT"

  assert_success
  assert_output --partial "Worktree Removal Summary"
  assert_output --partial "Worktree removed"

  # Verify worktree was removed
  assert_worktree_not_exists "$FEATURE_WT"
}

@test "hug wtr: dry run shows what would be removed" {
  cd "$TEST_REPO"
  run git-wt-remove "$FEATURE_WT" --dry-run

  assert_success
  assert_output --partial "DRY RUN"
  assert_output --partial "Would remove worktree"

  # Worktree should still exist
  assert_worktree_exists "$FEATURE_WT"
}

@test "hug wtr: removes worktree without confirmation when --force flag is used" {
  # Mock the confirm_action function to fail if called
  confirm_action() { return 1; }
  export -f confirm_action

  cd "$TEST_REPO"
  run git-wt-remove "$FEATURE_WT" --force

  assert_success
  assert_worktree_not_exists "$FEATURE_WT"
}

@test "hug wtr: fails when trying to remove current worktree" {
  # Switch to feature worktree and try to remove it
  cd "$FEATURE_WT"
  run git-wt-remove "$FEATURE_WT"

  assert_failure
  assert_output --partial "Cannot remove current worktree"

  # Worktree should still exist
  assert_worktree_exists "$FEATURE_WT"
}

@test "hug wtr: warns about uncommitted changes and fails without --force" {
  # Make worktree dirty
  echo "uncommitted changes" > "$FEATURE_WT/dirty.txt"

  cd "$TEST_REPO"
  run git-wt-remove "$FEATURE_WT"

  assert_failure
  assert_output --partial "Worktree has uncommitted changes"
  assert_output --partial "Commit or stash changes first, or use --force"

  # Worktree should still exist
  assert_worktree_exists "$FEATURE_WT"
}

@test "hug wtr: removes worktree with uncommitted changes when --force is used" {
  # Make worktree dirty
  echo "uncommitted changes" > "$FEATURE_WT/dirty.txt"

  cd "$TEST_REPO"
  run git-wt-remove "$FEATURE_WT" --force

  assert_success
  assert_output --partial "Dirty (will be lost)"

  # Worktree should be removed despite changes
  assert_worktree_not_exists "$FEATURE_WT"
}

@test "hug wtr: fails when worktree does not exist" {
  cd "$TEST_REPO"
  run git-wt-remove "/nonexistent/path"

  assert_failure
  assert_output --partial "Worktree path does not exist"
}

@test "hug wtr: fails when path is not a directory" {
  # Create a file at the path
  local fake_path="${TEST_REPO}/not-a-directory"
  touch "$fake_path"

  cd "$TEST_REPO"
  run git-wt-remove "$fake_path"

  assert_failure
  assert_output --partial "Worktree path is not a directory"

  # Clean up
  rm "$fake_path"
}

@test "hug wtr: fails when path is not a git worktree" {
  # Create a directory that's not a git worktree
  local not_worktree="/tmp/hug-test-not-worktree"
  mkdir -p "$not_worktree"

  cd "$TEST_REPO"
  run git-wt-remove "$not_worktree"

  assert_failure
  assert_output --partial "Path is not a Git worktree"

  # Clean up
  rmdir "$not_worktree"
}

@test "hug wtr: interactive menu excludes current worktree" {
  # Switch to feature worktree
  cd "$FEATURE_WT"

  echo "" | run git-wt-remove  # Press Enter to cancel

  assert_success
  assert_output --partial "Select worktree to remove"

  # Should not show current worktree in menu
  assert_output --not--partial "$FEATURE_WT"
}

@test "hug wtr: interactive menu shows dirty worktrees" {
  # Make hotfix worktree dirty
  echo "dirty changes" > "$HOTFIX_WT/dirty.txt"

  cd "$TEST_REPO"
  echo "" | run git-wt-remove  # Press Enter to cancel

  assert_success
  assert_output --partial "[DIRTY]"
  assert_output --partial "hotfix-1"
}

@test "hug wtr: interactive menu cancels when user presses Enter" {
  cd "$TEST_REPO"
  echo "" | run git-wt-remove

  assert_success
  assert_output --partial "Worktree removal cancelled"

  # All worktrees should still exist
  assert_worktree_exists "$FEATURE_WT"
  assert_worktree_exists "$HOTFIX_WT"
}

@test "hug wtr: interactive menu cancels with ESC in gum filter mode" {
  # Create many worktrees to trigger gum filter mode
  for i in {3..15}; do
    create_test_worktree "feature-$i" "$TEST_REPO"
  done

  cd "$TEST_REPO"

  # Mock gum to return empty (ESC pressed)
  if gum_available; then
    gum() {
      if [[ "$1" == "filter" ]]; then
        return 1  # Simulate ESC pressed
      fi
      command gum "$@"
    }
    export -f gum

    run git-wt-remove
    assert_success
    assert_output --partial "Worktree removal cancelled"
  else
    skip "gum not available for interactive test"
  fi
}

@test "hug wtr: handles relative paths correctly" {
  cd "$TEST_REPO"

  # Get relative path to feature worktree
  local relative_path
  relative_path=$(realpath --relative-to="$TEST_REPO" "$FEATURE_WT")

  run git-wt-remove "$relative_path"

  assert_success
  assert_worktree_not_exists "$FEATURE_WT"
}

@test "hug wtr: fails with too many arguments" {
  cd "$TEST_REPO"
  run git-wt-remove "$FEATURE_WT" "$HOTFIX_WT"

  assert_failure
  assert_output --partial "Too many arguments"
}

@test "hug wtr: error when not in git repository" {
  cd /tmp
  run git-wt-remove "/some/path"

  assert_failure
  assert_output --partial "Not a git repository"
}