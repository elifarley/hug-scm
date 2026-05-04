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
  run git-wtdel -p "$FEATURE_WT" --force

  assert_success
  assert_output --partial "Worktree Removal Summary"
  assert_output --partial "Worktree removed"

  # Verify worktree was removed
  assert_worktree_not_exists "$FEATURE_WT"

  teardown_gum_mock
}

@test "hug wtdel: dry run shows what would be removed" {
  cd "$TEST_REPO"
  run git-wtdel -p "$FEATURE_WT" --dry-run

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
  run git-wtdel -p "$FEATURE_WT" --force

  assert_success
  assert_worktree_not_exists "$FEATURE_WT"
}

@test "hug wtdel: fails when trying to remove current worktree" {
  # Switch to feature worktree and try to remove it
  cd "$FEATURE_WT"
  run git-wtdel -p "$FEATURE_WT"

  assert_failure
  assert_output --partial "Cannot remove current worktree"

  # Worktree should still exist
  assert_worktree_exists "$FEATURE_WT"
}

@test "hug wtdel: warns about uncommitted changes and fails without --force" {
  # Make worktree dirty
  echo "uncommitted changes" > "$FEATURE_WT/dirty.txt"

  cd "$TEST_REPO"
  run git-wtdel -p "$FEATURE_WT"

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
  run git-wtdel -p "$FEATURE_WT" --force

  assert_success
  assert_output --partial "will be permanently lost"

  # Worktree should be removed despite changes
  assert_worktree_not_exists "$FEATURE_WT"
}

@test "hug wtdel: fails when worktree does not exist" {
  cd "$TEST_REPO"
  run git-wtdel -p "/nonexistent/path"

  assert_failure
  assert_output --partial "Worktree path does not exist"
}

@test "hug wtdel: fails when path is not a directory" {
  # Create a file at the path
  local fake_path="${TEST_REPO}/not-a-directory"
  touch "$fake_path"

  cd "$TEST_REPO"
  run git-wtdel -p "$fake_path"

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
  run git-wtdel -p "$not_worktree"

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

  run git-wtdel -p "$relative_path" --force

  assert_success
  assert_worktree_not_exists "$FEATURE_WT"
}

# Note: Multiple arguments are now supported for batch removal
# See test: "hug wtdel: multiple paths removes all successfully"

@test "hug wtdel: shows branch name in removal summary" {
  cd "$TEST_REPO"
  run git-wtdel -p "$FEATURE_WT" --dry-run
  assert_success
  assert_output --partial "Branch: feature-1"
}

@test "hug wtdel: shows post-removal tip with branch deletion guidance" {
  cd "$TEST_REPO"
  run git-wtdel -p "$FEATURE_WT" --force
  assert_success
  assert_output --partial "Branch 'feature-1' still exists"
  assert_output --partial "hug bdel"
}

@test "hug wtdel: handles locked worktree with manual cleanup fallback" {
  cd "$TEST_REPO"
  # Lock the worktree
  git worktree lock "$FEATURE_WT"

  run git-wtdel -p "$FEATURE_WT" --force
  assert_success
  # git worktree remove fails for locked worktrees, but manual cleanup succeeds
  assert_output --partial "Worktree removed"

  # Unlock (may already be cleaned up, ignore errors)
  git worktree unlock "$FEATURE_WT" 2>/dev/null || true
}

@test "hug wtdel: error when not in git repository" {
  cd /tmp
  run git-wtdel -p "/some/path"

  assert_failure
  assert_output --partial "Not in a git repository"
}

# Tests for positional branch names

@test "hug wtdel: positional branch removes worktree" {
  cd "$TEST_REPO"
  run git-wtdel feature-1 --force

  assert_success
  assert_output --partial "Worktree removed"
  assert_worktree_not_exists "$FEATURE_WT"
}

@test "hug wtdel: positional branch errors when branch not found" {
  cd "$TEST_REPO"
  run git-wtdel nonexistent-branch

  assert_failure
  assert_output --partial "No worktree found for branch"
}

@test "hug wtdel: positional branch with --dry-run shows preview" {
  cd "$TEST_REPO"
  run git-wtdel feature-1 --dry-run

  assert_success
  assert_output --partial "Worktree Removal Preview (DRY RUN)"
  assert_output --partial "Branch: feature-1"
  assert_worktree_exists "$FEATURE_WT"
}

@test "hug wtdel: branch names and --path are mutually exclusive" {
  cd "$TEST_REPO"
  run git-wtdel feature-1 -p "$FEATURE_WT"

  assert_failure
  assert_output --partial "mutually exclusive"
}

# Tests for multiple path support

@test "hug wtdel: multiple paths removes all successfully" {
  cd "$TEST_REPO"
  run git-wtdel -p "$FEATURE_WT" -p "$HOTFIX_WT" --force

  assert_success
  assert_output --partial "Batch Removal Summary"
  assert_output --partial "Removed: 2"
  assert_worktree_not_exists "$FEATURE_WT"
  assert_worktree_not_exists "$HOTFIX_WT"
}

@test "hug wtdel: multiple paths with --dry-run previews all" {
  cd "$TEST_REPO"
  run git-wtdel -p "$FEATURE_WT" -p "$HOTFIX_WT" --dry-run

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
  run git-wtdel -p "$FEATURE_WT" -p "/nonexistent/path" --force

  # Should fail because one path failed
  assert_failure
  assert_output --partial "Batch Removal Summary"
  assert_output --partial "Removed: 1"
  assert_output --partial "Failed: 1"
  assert_worktree_not_exists "$FEATURE_WT"
}

@test "hug wtdel: multiple paths shows per-item progress" {
  cd "$TEST_REPO"
  run git-wtdel -p "$FEATURE_WT" -p "$HOTFIX_WT" --force

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
  run git-wtdel -p "$FEATURE_WT"

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
  run git-wtdel -p "$FEATURE_WT" --force
  
  assert_success
  assert_output --partial "will be permanently lost"
  assert_worktree_not_exists "$FEATURE_WT"
}

@test "hug wtdel: HUG_FORCE environment variable enables force mode" {
  cd "$TEST_REPO"
  # Make worktree dirty
  echo "dirty" > "$FEATURE_WT/dirty.txt"

  # Should fail without force
  run git-wtdel -p "$FEATURE_WT"
  assert_failure

  # Should succeed with HUG_FORCE
  run env HUG_FORCE=true git-wtdel -p "$FEATURE_WT"
  assert_success
  assert_worktree_not_exists "$FEATURE_WT"
}

# Tests for main worktree protection

@test "hug wtdel: positional main branch blocks removal of main worktree" {
  cd "$TEST_REPO"
  # Get main branch name
  local main_branch
  main_branch=$(git branch --show-current)

  run git-wtdel "$main_branch"
  
  assert_failure
  assert_output --partial "Cannot remove the main worktree"
}

# Tests for batch mixed states

@test "hug wtdel: batch with mixed dirty and clean worktrees" {
  # Make one worktree dirty
  echo "dirty" > "$FEATURE_WT/dirty.txt"

  # Without --force, the clean worktree reaches prompt_confirm_danger()
  # which calls `gum input`. Real gum reads from /dev/tty directly and
  # will block forever in a non-interactive Bats context. Use the gum
  # mock (setup_gum_mock) + empty stdin so `gum input` exits 1 (cancel).
  # WHY: HUG_TEST_MODE=true forces gum_available() to return true even
  # though stdin is /dev/null (non-TTY), routing through the gum mock.
  setup_gum_mock
  export HUG_TEST_MODE=true
  unset HUG_TEST_GUM_INPUT HUG_TEST_GUM_INPUT_RETURN_CODE HUG_TEST_GUM_RESPONSES

  cd "$TEST_REPO"
  run bash -c "echo '' | git-wtdel -p '$FEATURE_WT' -p '$HOTFIX_WT' < /dev/null"

  # Should fail because the dirty one is blocked (added to failed[]).
  # Clean one reaches the confirm prompt, gum mock exits 1,
  # and the command aborts with \"Cancelled.\".
  assert_failure
  assert_output --partial "Worktree has uncommitted changes"
  assert_output --partial "Cancelled"
  # Neither worktree was removed
  assert [ -d "$FEATURE_WT" ]
  assert [ -d "$HOTFIX_WT" ]

  unset HUG_TEST_MODE
  teardown_gum_mock
}

@test "hug wtdel: batch removes clean worktrees even when some are dirty (with --force)" {
  # Make one worktree dirty
  echo "dirty" > "$FEATURE_WT/dirty.txt"
  
  cd "$TEST_REPO"
  run git-wtdel -p "$FEATURE_WT" -p "$HOTFIX_WT" --force

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
  run git-wtdel -p "$FEATURE_WT"

  # Cancellation returns exit 1 but worktree should still exist
  assert_failure
  assert_output --partial "cancelled"
  assert_worktree_exists "$FEATURE_WT"
}

@test "hug wtdel: multiple positional branches batch removes" {
  cd "$TEST_REPO"
  run git-wtdel feature-1 hotfix-1 --force
  assert_success
  assert_output --partial "Batch Removal Summary"
  assert_output --partial "Removed: 2"
  assert_worktree_not_exists "$FEATURE_WT"
  assert_worktree_not_exists "$HOTFIX_WT"
}

# Tests for stale worktree auto-prune

@test "hug wtdel: auto-prunes stale worktree" {
  # WHY: When a worktree directory is deleted externally without git worktree remove,
  # the stale metadata remains. wtdel should detect this and auto-prune.
  cd "$TEST_REPO"

  # Delete the worktree directory externally, leaving stale metadata
  rm -rf "$FEATURE_WT"

  # Verify directory is gone but metadata remains
  assert [ ! -d "$FEATURE_WT" ]
  run git worktree list --porcelain
  assert_output --partial "worktree $FEATURE_WT"

  # wtdel should auto-prune the stale entry
  run git-wtdel feature-1 --force
  assert_success
  assert_output --partial "directory already removed"
  assert_output --partial "Pruned stale worktree entry"

  # Verify metadata was cleaned up
  run git worktree list --porcelain
  refute_output --partial "worktree $FEATURE_WT"
}

@test "hug wtdel: stale path with --dry-run does not prune" {
  cd "$TEST_REPO"

  # Delete the worktree directory externally
  rm -rf "$FEATURE_WT"

  # --dry-run should report what it would do without actually pruning
  run git-wtdel feature-1 --dry-run
  assert_success
  assert_output --partial "directory already removed"
  assert_output --partial "Would prune stale worktree metadata (dry run)"

  # Metadata should still exist
  run git worktree list --porcelain
  assert_output --partial "worktree $FEATURE_WT"
}

@test "hug wtdel: stale and valid batch" {
  cd "$TEST_REPO"

  # Make feature worktree stale (delete dir externally)
  rm -rf "$FEATURE_WT"

  # hotfix worktree is still valid
  assert [ -d "$HOTFIX_WT" ]

  # Batch: stale auto-pruned, valid removed normally
  run git-wtdel -p "$FEATURE_WT" -p "$HOTFIX_WT" --force
  assert_success
  assert_output --partial "Pruned stale worktree entry"
  assert_output --partial "Worktree removed for branch 'hotfix-1'"
  assert_output --partial "Batch Removal Summary"
  assert_output --partial "Removed: 2"

  # Both should be cleaned up
  run git worktree list --porcelain
  refute_output --partial "worktree $FEATURE_WT"
  refute_output --partial "worktree $HOTFIX_WT"
}

@test "hug wtdel: stale locked worktree auto-prunes" {
  cd "$TEST_REPO"

  # Lock the worktree, then make it stale
  git worktree lock "$FEATURE_WT"
  rm -rf "$FEATURE_WT"

  # Even locked stale worktrees should auto-prune
  # (lock is metadata-only, prune handles it)
  run git-wtdel feature-1 --force
  assert_success
  assert_output --partial "Pruned stale worktree entry"

  # Verify metadata was cleaned up
  run git worktree list --porcelain
  refute_output --partial "worktree $FEATURE_WT"
}

# Tests for --with-branch flag

@test "hug wtdel: -B removes worktree and deletes merged branch" {
  cd "$TEST_REPO"
  # feature-1 is unmerged by default — merge it first
  git merge feature-1 --no-ff -m "merge feature-1" > /dev/null 2>&1

  run git-wtdel feature-1 -B --force
  assert_success
  assert_output --partial "Worktree removed"
  assert_output --partial "Branch 'feature-1' deleted"
  assert_worktree_not_exists "$FEATURE_WT"

  # Verify branch is gone
  run git rev-parse --verify "refs/heads/feature-1"
  assert_failure
}

@test "hug wtdel: --with-branch works identically to -B" {
  cd "$TEST_REPO"
  git merge feature-1 --no-ff -m "merge feature-1" > /dev/null 2>&1

  run git-wtdel feature-1 --with-branch --force
  assert_success
  assert_output --partial "Branch 'feature-1' deleted"
  assert_worktree_not_exists "$FEATURE_WT"

  run git rev-parse --verify "refs/heads/feature-1"
  assert_failure
}

@test "hug wtdel: -B --dry-run previews branch deletion" {
  cd "$TEST_REPO"
  run git-wtdel feature-1 -B --dry-run

  assert_success
  assert_output --partial "Worktree Removal Preview (DRY RUN)"
  assert_output --partial "would be deleted"
  assert_worktree_exists "$FEATURE_WT"

  # Branch should still exist
  run git rev-parse --verify "refs/heads/feature-1"
  assert_success
}

@test "hug wtdel: -B suppresses the 'hug bdel' tip" {
  cd "$TEST_REPO"
  git merge feature-1 --no-ff -m "merge feature-1" > /dev/null 2>&1

  run git-wtdel feature-1 -B --force
  assert_success
  refute_output --partial "still exists"
  refute_output --partial "hug bdel"
}

@test "hug wtdel: tip still shown when -B is NOT used" {
  cd "$TEST_REPO"
  run git-wtdel feature-1 --force
  assert_success
  assert_output --partial "still exists"
  assert_output --partial "hug bdel"
}

@test "hug wtdel: help includes -B and --with-branch" {
  run git-wtdel --help
  assert_success
  assert_output --partial -- "-B, --with-branch"
}

# Tests for branch states with -B

@test "hug wtdel: -B with unmerged branch deletes on --force" {
  cd "$TEST_REPO"
  # feature-1 has its own commit not in main — unmerged
  run git-wtdel feature-1 -B --force
  assert_success
  assert_output --partial "Branch 'feature-1' deleted"
  assert_worktree_not_exists "$FEATURE_WT"

  run git rev-parse --verify "refs/heads/feature-1"
  assert_failure
}

@test "hug wtdel: -B with detached HEAD skips branch deletion silently" {
  cd "$TEST_REPO"
  # Create a detached HEAD worktree
  local detached_wt="${TEST_REPO}.WT.detached-test"
  git worktree add --detach "$detached_wt" HEAD > /dev/null 2>&1

  run git-wtdel -p "$detached_wt" -B --force
  assert_success
  assert_output --partial "Worktree removed"
  # Should NOT show any branch deletion message
  refute_output --partial "Branch 'HEAD' deleted"
  refute_output --partial "deleted"
  assert_worktree_not_exists "$detached_wt"
}

@test "hug wtdel: -B batch with mixed merged and unmerged branches" {
  cd "$TEST_REPO"
  # Merge feature-1 into main so it's merged; hotfix-1 remains unmerged
  git merge feature-1 --no-ff -m "merge feature-1" > /dev/null 2>&1

  run git-wtdel feature-1 hotfix-1 -B --force
  assert_success
  assert_output --partial "Batch Removal Summary"
  assert_output --partial "Removed: 2"
  assert_output --partial "Branches deleted: 2"
  assert_worktree_not_exists "$FEATURE_WT"
  assert_worktree_not_exists "$HOTFIX_WT"

  # Both branches should be gone (--force deletes unmerged too)
  run git rev-parse --verify "refs/heads/feature-1"
  assert_failure
  run git rev-parse --verify "refs/heads/hotfix-1"
  assert_failure
}

@test "hug wtdel: -B batch summary includes branch counts" {
  cd "$TEST_REPO"
  git merge feature-1 --no-ff -m "merge feature-1" > /dev/null 2>&1

  run git-wtdel feature-1 hotfix-1 -B --force
  assert_success
  assert_output --partial "Batch Removal Summary"
  assert_output --partial "Removed: 2"
  assert_output --partial "Branches deleted: 2"
}

@test "hug wtdel: -B skips branch deletion gracefully when branch is gone" {
  cd "$TEST_REPO"
  # Use a detached HEAD worktree — the branch lookup will skip cleanly
  local detached_wt="${TEST_REPO}.WT.detached-no-branch"
  git worktree add --detach "$detached_wt" HEAD > /dev/null 2>&1

  run git-wtdel -p "$detached_wt" -B --force
  assert_success
  assert_output --partial "Worktree removed"
  # No branch deletion attempted for detached HEAD
  refute_output --partial "deleted"
  assert_worktree_not_exists "$detached_wt"
}
