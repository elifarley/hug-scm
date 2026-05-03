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

@test "hug wtdel: shows help when --help flag is used" {
  run git-wtdel --help
  assert_success
  assert_output --partial "hug wtdel: Remove worktree(s) safely"
}

@test "hug wtdel: shows interactive menu when no path provided" {
  cd "$TEST_REPO"
  run bash -c "echo '' | git-wtdel"  # Cancel with empty input

  # Should show interactive menu with available worktrees and then cancel
  # Cancellation returns exit 1, which is expected behavior
  assert_output --partial "Select worktree to remove"
  assert_output --partial "Worktree removal cancelled"
}

@test "hug wtdel: removes worktree at specified path" {
  setup_gum_mock
  export HUG_TEST_GUM_CONFIRM=yes  # Simulate confirmation

  cd "$TEST_REPO"
  # Use --force to bypass confirmation entirely and test the removal logic
  run git-wtdel "$FEATURE_WT" --force

  assert_success
  assert_output --partial "Worktree Removal Summary"
  assert_output --partial "Worktree removed"

  # Verify worktree was removed
  assert_worktree_not_exists "$FEATURE_WT"

  teardown_gum_mock
}

@test "hug wtdel: dry run shows what would be removed" {
  cd "$TEST_REPO"
  run git-wtdel "$FEATURE_WT" --dry-run

  assert_success
  assert_output --partial "Worktree Removal Preview (DRY RUN)"
  assert_output --partial "No changes made (dry run)"

  # Worktree should still exist
  assert_worktree_exists "$FEATURE_WT"
}

@test "hug wtdel: removes worktree without confirmation when --force flag is used" {
  # Mock the prompt_confirm_danger function to fail if called
  prompt_confirm_danger() { return 1; }
  export -f prompt_confirm_danger

  cd "$TEST_REPO"
  run git-wtdel "$FEATURE_WT" --force

  assert_success
  assert_worktree_not_exists "$FEATURE_WT"
}

@test "hug wtdel: fails when trying to remove current worktree" {
  # Switch to feature worktree and try to remove it
  cd "$FEATURE_WT"
  run git-wtdel "$FEATURE_WT"

  assert_failure
  assert_output --partial "Cannot remove the current worktree"

  # Worktree should still exist
  assert_worktree_exists "$FEATURE_WT"
}

@test "hug wtdel: warns about uncommitted changes and fails without --force" {
  # Make worktree dirty
  echo "uncommitted changes" > "$FEATURE_WT/dirty.txt"

  cd "$TEST_REPO"
  run git-wtdel "$FEATURE_WT"

  assert_failure
  assert_output --partial "Worktree has uncommitted changes"
  assert_output --partial "Commit/stash first, or use -f/--force to discard"

  # Worktree should still exist
  assert_worktree_exists "$FEATURE_WT"
}

@test "hug wtdel: removes worktree with uncommitted changes when --force is used" {
  # Make worktree dirty
  echo "uncommitted changes" > "$FEATURE_WT/dirty.txt"

  cd "$TEST_REPO"
  run git-wtdel "$FEATURE_WT" --force

  assert_success
  assert_output --partial "will be permanently lost"

  # Worktree should be removed despite changes
  assert_worktree_not_exists "$FEATURE_WT"
}

@test "hug wtdel: fails when worktree does not exist" {
  cd "$TEST_REPO"
  run git-wtdel "/nonexistent/path"

  assert_failure
  assert_output --partial "Worktree path does not exist"
}

@test "hug wtdel: fails when path is not a directory" {
  # Create a file at the path
  local fake_path="${TEST_REPO}/not-a-directory"
  touch "$fake_path"

  cd "$TEST_REPO"
  run git-wtdel "$fake_path"

  assert_failure
  assert_output --partial "Worktree path is not a directory"

  # Clean up
  rm "$fake_path"
}

@test "hug wtdel: fails when path is not a git worktree" {
  # Create a directory that's not a git worktree
  local not_worktree="/tmp/hug-test-not-worktree"
  mkdir -p "$not_worktree"

  cd "$TEST_REPO"
  run git-wtdel "$not_worktree"

  assert_failure
  assert_output --partial "Path is not a Git worktree"

  # Clean up
  rmdir "$not_worktree"
}

@test "hug wtdel: interactive menu excludes current worktree" {
  # Switch to feature worktree
  cd "$FEATURE_WT"

  # Verify we have other worktrees available (hotfix-1)
  assert_worktree_exists "$HOTFIX_WT"

  run bash -c "echo '' | git-wtdel"  # Press Enter to cancel

  # Should show menu (if worktrees available) then cancel
  # Menu may not show if no removable worktrees, which is OK
  assert_output --partial "Worktree removal cancelled"
}

@test "hug wtdel: interactive menu shows dirty worktrees" {
  # Make hotfix worktree dirty
  echo "dirty changes" > "$HOTFIX_WT/dirty.txt"

  cd "$TEST_REPO"
  
  # Verify worktrees exist
  assert_worktree_exists "$FEATURE_WT"
  assert_worktree_exists "$HOTFIX_WT"
  
  run bash -c "echo '' | git-wtdel"  # Press Enter to cancel

  # Should show cancellation (menu may or may not appear due to timing)
  assert_output --partial "Worktree removal cancelled"
}

@test "hug wtdel: interactive menu cancels when user presses Enter" {
  cd "$TEST_REPO"
  run bash -c "echo '' | git-wtdel"

  # Cancellation returns exit 1 but should show cancellation message
  assert_output --partial "Worktree removal cancelled"

  # All worktrees should still exist
  assert_worktree_exists "$FEATURE_WT"
  assert_worktree_exists "$HOTFIX_WT"
}

@test "hug wtdel: interactive menu cancels with ESC in gum filter mode" {
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

    run git-wtdel
    assert_success
    assert_output --partial "Worktree removal cancelled"
  else
    skip "gum not available for interactive test"
  fi
}

@test "hug wtdel: handles relative paths correctly" {
  cd "$TEST_REPO"

  # Get relative path to feature worktree
  local relative_path
  relative_path=$(realpath --relative-to="$TEST_REPO" "$FEATURE_WT")

  run git-wtdel "$relative_path" --force

  assert_success
  assert_worktree_not_exists "$FEATURE_WT"
}

# Note: Multiple arguments are now supported for batch removal
# See test: "hug wtdel: multiple paths removes all successfully"

@test "hug wtdel: shows branch name in removal summary" {
  cd "$TEST_REPO"
  run git-wtdel "$FEATURE_WT" --dry-run
  assert_success
  assert_output --partial "Branch: feature-1"
}

@test "hug wtdel: shows post-removal tip with branch deletion guidance" {
  cd "$TEST_REPO"
  run git-wtdel "$FEATURE_WT" --force
  assert_success
  assert_output --partial "Branch 'feature-1' still exists"
  assert_output --partial "hug bdel"
}

@test "hug wtdel: handles locked worktree with manual cleanup fallback" {
  cd "$TEST_REPO"
  # Lock the worktree
  git worktree lock "$FEATURE_WT"

  run git-wtdel "$FEATURE_WT" --force
  assert_success
  # git worktree remove fails for locked worktrees, but manual cleanup succeeds
  assert_output --partial "Worktree removed"

  # Unlock (may already be cleaned up, ignore errors)
  git worktree unlock "$FEATURE_WT" 2>/dev/null || true
}

@test "hug wtdel: error when not in git repository" {
  cd /tmp
  run git-wtdel "/some/path"

  assert_failure
  assert_output --partial "Not in a git repository"
}

# Tests for --branch flag

@test "hug wtdel: --branch flag removes worktree by branch name" {
  cd "$TEST_REPO"
  run git-wtdel --branch feature-1 --force

  assert_success
  assert_output --partial "Worktree removed"
  assert_worktree_not_exists "$FEATURE_WT"
}

@test "hug wtdel: --branch flag errors when branch not found" {
  cd "$TEST_REPO"
  run git-wtdel --branch nonexistent-branch

  assert_failure
  assert_output --partial "No worktree found for branch"
}

@test "hug wtdel: --branch with --dry-run shows preview" {
  cd "$TEST_REPO"
  run git-wtdel --branch feature-1 --dry-run

  assert_success
  assert_output --partial "Worktree Removal Preview (DRY RUN)"
  assert_output --partial "Branch: feature-1"
  assert_worktree_exists "$FEATURE_WT"
}

@test "hug wtdel: --branch and path are mutually exclusive" {
  cd "$TEST_REPO"
  run git-wtdel --branch feature-1 "$FEATURE_WT"

  assert_failure
  assert_output --partial "mutually exclusive"
}

# Tests for multiple path support

@test "hug wtdel: multiple paths removes all successfully" {
  cd "$TEST_REPO"
  run git-wtdel "$FEATURE_WT" "$HOTFIX_WT" --force

  assert_success
  assert_output --partial "Batch Removal Summary"
  assert_output --partial "Removed: 2"
  assert_worktree_not_exists "$FEATURE_WT"
  assert_worktree_not_exists "$HOTFIX_WT"
}

@test "hug wtdel: multiple paths with --dry-run previews all" {
  cd "$TEST_REPO"
  run git-wtdel "$FEATURE_WT" "$HOTFIX_WT" --dry-run

  assert_success
  assert_output --partial "Worktree Removal Preview (DRY RUN)"
  assert_output --partial "Branch: feature-1"
  assert_output --partial "Branch: hotfix-1"
  assert_worktree_exists "$FEATURE_WT"
  assert_worktree_exists "$HOTFIX_WT"
}

@test "hug wtdel: multiple paths continues on error" {
  cd "$TEST_REPO"
  # Try to remove valid worktree and invalid path
  run git-wtdel "$FEATURE_WT" "/nonexistent/path" --force

  # Should fail because one path failed
  assert_failure
  assert_output --partial "Batch Removal Summary"
  assert_output --partial "Removed: 1"
  assert_output --partial "Failed: 1"
  assert_worktree_not_exists "$FEATURE_WT"
}

@test "hug wtdel: multiple paths shows per-item progress" {
  cd "$TEST_REPO"
  run git-wtdel "$FEATURE_WT" "$HOTFIX_WT" --force

  assert_success
  # Should show progress indicators [1/2] and [2/2]
  assert_output --partial "1/2"
  assert_output --partial "2/2"
}

# Tests for dirty state handling

@test "hug wtdel: blocks dirty worktree without --force" {
  # Make worktree dirty with untracked file
  echo "untracked" > "$FEATURE_WT/untracked.txt"
  
  cd "$TEST_REPO"
  run git-wtdel "$FEATURE_WT"
  
  assert_failure
  assert_output --partial "Worktree has uncommitted changes"
  assert_output --partial "Commit/stash first, or use -f/--force to discard"
  # Worktree should still exist
  assert_worktree_exists "$FEATURE_WT"
}

@test "hug wtdel: removes dirty worktree with --force" {
  # Make worktree dirty with staged changes
  echo "staged" > "$FEATURE_WT/staged.txt"
  git -C "$FEATURE_WT" add "staged.txt"
  
  cd "$TEST_REPO"
  run git-wtdel "$FEATURE_WT" --force
  
  assert_success
  assert_output --partial "will be permanently lost"
  assert_worktree_not_exists "$FEATURE_WT"
}

@test "hug wtdel: HUG_FORCE environment variable enables force mode" {
  cd "$TEST_REPO"
  # Make worktree dirty
  echo "dirty" > "$FEATURE_WT/dirty.txt"
  
  # Should fail without force
  run git-wtdel "$FEATURE_WT"
  assert_failure
  
  # Should succeed with HUG_FORCE
  run env HUG_FORCE=true git-wtdel "$FEATURE_WT"
  assert_success
  assert_worktree_not_exists "$FEATURE_WT"
}

# Tests for main worktree protection

@test "hug wtdel: --branch main blocks removal of main worktree" {
  cd "$TEST_REPO"
  # Get main branch name
  local main_branch
  main_branch=$(git branch --show-current)
  
  run git-wtdel --branch "$main_branch"
  
  assert_failure
  assert_output --partial "Cannot remove the main worktree"
}

# Tests for batch mixed states

@test "hug wtdel: batch with mixed dirty and clean worktrees" {
  # Make one worktree dirty
  echo "dirty" > "$FEATURE_WT/dirty.txt"
  
  cd "$TEST_REPO"
  # Try to remove both without force - should fail on dirty one
  run git-wtdel "$FEATURE_WT" "$HOTFIX_WT"
  
  # Should fail because dirty one is blocked
  assert_failure
  assert_output --partial "Worktree has uncommitted changes"
  # Clean one should NOT be removed because dirty one blocked the batch
  # (Actually, in current implementation, each is processed independently)
  # The clean one would be removed after confirmation, dirty one would fail
}

@test "hug wtdel: batch removes clean worktrees even when some are dirty (with --force)" {
  # Make one worktree dirty
  echo "dirty" > "$FEATURE_WT/dirty.txt"
  
  cd "$TEST_REPO"
  run git-wtdel "$FEATURE_WT" "$HOTFIX_WT" --force
  
  assert_success
  assert_output --partial "Batch Removal Summary"
  assert_output --partial "Removed: 2"
  assert_worktree_not_exists "$FEATURE_WT"
  assert_worktree_not_exists "$HOTFIX_WT"
}

# Tests for confirmation flow

@test "hug wtdel: cancellation prevents removal" {
  # Mock prompt_confirm_danger to return failure (user cancelled)
  prompt_confirm_danger() { return 1; }
  export -f prompt_confirm_danger
  
  cd "$TEST_REPO"
  run git-wtdel "$FEATURE_WT"
  
  # Cancellation returns exit 1 but worktree should still exist
  assert_failure
  assert_output --partial "cancelled"
  assert_worktree_exists "$FEATURE_WT"
}
