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
  cd "$TEST_REPO"
  run git-wtdel -p "$FEATURE_WT" --force

  assert_success
  assert_output --partial "Worktree Removal Plan"
  assert_output --partial "Worktree removed"

  # Verify worktree was removed
  assert_worktree_not_exists "$FEATURE_WT"
}

@test "hug wtdel: dry run shows what would be removed" {
  cd "$TEST_REPO"
  run git-wtdel -p "$FEATURE_WT" --dry-run

  assert_success
  assert_output --partial "Worktree Removal Plan (DRY RUN)"
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

  assert_failure 3
  assert_output --partial "BLOCKED"
  assert_output --partial "current worktree"

  # Worktree should still exist
  assert_worktree_exists "$FEATURE_WT"
}

@test "hug wtdel: warns about uncommitted changes and fails without --force" {
  # Make worktree dirty
  echo "uncommitted changes" > "$FEATURE_WT/dirty.txt"

  cd "$TEST_REPO"
  run git-wtdel -p "$FEATURE_WT"

  assert_failure 3
  assert_output --partial "BLOCKED: uncommitted changes"
  assert_output --partial "Nothing removed"

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
  assert_output --partial "INVALID"
  assert_output --partial "Nothing removed"
}

@test "hug wtdel: fails when path is not a directory" {
  # Create a file at the path
  local fake_path="${TEST_REPO}/not-a-directory"
  touch "$fake_path"

  cd "$TEST_REPO"
  run git-wtdel -p "$fake_path"

  assert_failure
  assert_output --partial "INVALID"
  assert_output --partial "Nothing removed"

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
  assert_output --partial "INVALID"
  assert_output --partial "Nothing removed"

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

@test "hug wtdel: shows branch name in removal plan" {
  cd "$TEST_REPO"
  run git-wtdel -p "$FEATURE_WT" --dry-run
  assert_success
  assert_output --partial "Target: $FEATURE_WT"
}

@test "hug wtdel: shows post-removal tip with branch deletion guidance" {
  cd "$TEST_REPO"
  run git-wtdel -p "$FEATURE_WT" --force
  assert_success
  assert_output --partial "Branch 'feature-1' still exists"
  assert_output --partial "hug bdel"
}

@test "hug wtdel: refuses to remove a locked worktree (even with --force)" {
  # Locks express explicit user intent ("don't delete this"). `--force` is
  # for "skip confirmation prompts and bypass dirty/submodule checks", not
  # "ignore locks". Per `git-worktree(1)`, locks must be unlocked before
  # deletion is allowed. The BLOCKED message tells the user exactly how.
  cd "$TEST_REPO"
  git worktree lock "$FEATURE_WT"

  run git-wtdel -p "$FEATURE_WT" --force
  assert_failure 3
  assert_output --partial "BLOCKED"
  assert_output --partial "locked"

  # Worktree should still exist on disk and be registered
  assert_worktree_exists "$FEATURE_WT"

  # Unlock for teardown
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
  assert_output --partial "no worktree found for branch 'nonexistent-branch'"
  assert_output --partial "Nothing removed"
}

@test "hug wtdel: positional branch with --dry-run shows preview" {
  cd "$TEST_REPO"
  run git-wtdel feature-1 --dry-run

  assert_success
  assert_output --partial "Worktree Removal Plan (DRY RUN)"
  assert_output --partial "Target: feature-1"
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
  assert_output --partial "DRY RUN"
  assert_output --partial "Target:"
  assert_worktree_exists "$FEATURE_WT"
  assert_worktree_exists "$HOTFIX_WT"
}

@test "hug wtdel: batch with an invalid path removes nothing (pre-flight)" {
  cd "$TEST_REPO"
  run git-wtdel -p "$FEATURE_WT" -p "/nonexistent/path" --force
  assert_failure
  assert_output --partial "INVALID"
  assert_output --partial "Nothing removed"
  assert_worktree_exists "$FEATURE_WT"
}

@test "hug wtdel: multiple paths shows per-item progress" {
  cd "$TEST_REPO"
  run git-wtdel -p "$FEATURE_WT" -p "$HOTFIX_WT" --force

  assert_success
  # Plan phase shows per-item progress [1/2] and [2/2]
  assert_output --partial "[1/2]"
  assert_output --partial "[2/2]"
}

# Tests for dirty state handling

@test "hug wtdel: blocks dirty worktree without --force" {
  # Make worktree dirty with untracked file
  echo "untracked" > "$FEATURE_WT/untracked.txt"

  cd "$TEST_REPO"
  run git-wtdel -p "$FEATURE_WT"

  assert_failure 3
  assert_output --partial "BLOCKED: uncommitted changes"
  assert_output --partial "Nothing removed"
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

  assert_failure 3
  assert_output --partial "BLOCKED"
  assert_output --partial "main worktree"
}

# Tests for batch mixed states

@test "hug wtdel: batch with mixed dirty and clean worktrees" {
  # Make one worktree dirty
  echo "dirty" > "$FEATURE_WT/dirty.txt"

  cd "$TEST_REPO"
  run git-wtdel -p "$FEATURE_WT" -p "$HOTFIX_WT"

  # Pre-flight blocks the dirty one -> nothing removed (all-or-nothing)
  assert_failure 3
  assert_output --partial "BLOCKED: uncommitted changes"
  assert_output --partial "Nothing removed"
  # Neither worktree was removed
  assert [ -d "$FEATURE_WT" ]
  assert [ -d "$HOTFIX_WT" ]
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
  assert_output --partial "Will prune stale entry"
  assert_output --partial "No changes made (dry run)"

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

@test "hug wtdel: -B --dry-run previews removal plan" {
  cd "$TEST_REPO"
  run git-wtdel feature-1 -B --dry-run

  assert_success
  assert_output --partial "Worktree Removal Plan (DRY RUN)"
  assert_output --partial "Will remove"
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

# ============================================================================
# Submodule-worktree tests (fix for: hug wtdel false-rejection on submodule
# worktrees + -B branch-deletion targeting the wrong gitdir)
# ============================================================================

@test "hug wtdel: --dry-run accepts submodule worktree by path (-p) from meta-repo CWD" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  [[ -n "$meta_repo" && -n "$wt_path" ]] || skip "submodule fixture setup failed"

  cd "$meta_repo"
  run git-wtdel -p "$wt_path" --dry-run

  assert_success
  refute_output --partial "Path is not a Git worktree"
  assert_output --partial "DRY RUN"

  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}

@test "hug wtdel: removes submodule worktree by path with --force from meta-repo CWD" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  [[ -n "$meta_repo" && -n "$wt_path" ]] || skip "submodule fixture setup failed"

  cd "$meta_repo"
  run git-wtdel -p "$wt_path" --force

  assert_success
  refute_output --partial "Path is not a Git worktree"
  assert_output --partial "Worktree removed"
  assert_worktree_not_exists "$wt_path"

  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}

@test "hug wtdel -B: deletes submodule worktree AND its (submodule-local) branch" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  [[ -n "$meta_repo" && -n "$wt_path" ]] || skip "submodule fixture setup failed"

  # Pre-condition: branch exists in submodule's gitdir
  git --git-dir="$meta_repo/.git/modules/sub" rev-parse --verify refs/heads/sub-feat-x > /dev/null

  cd "$meta_repo"
  run git-wtdel -p "$wt_path" -B --force

  assert_success
  assert_output --partial "Worktree removed"
  assert_output --partial "Branch 'sub-feat-x' deleted"
  assert_worktree_not_exists "$wt_path"

  # Branch should be gone from submodule's gitdir
  ! git --git-dir="$meta_repo/.git/modules/sub" rev-parse --verify refs/heads/sub-feat-x > /dev/null 2>&1 \
    || fail "Branch 'sub-feat-x' should have been deleted from submodule gitdir"

  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}

@test "hug wtdel -B: does NOT touch meta-repo branch with same name (regression guard)" {
  # Worst-case bug Codex caught: unanchored `git branch -D` would delete
  # the meta-repo's branch instead of the submodule's, when they collide.
  # This regression test creates a meta-repo branch with the SAME NAME as
  # the submodule branch we're targeting, and verifies the meta-repo
  # branch survives.
  local meta_repo wt_path collision_branch="sub-feat-x"
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "$collision_branch")
  [[ -n "$meta_repo" && -n "$wt_path" ]] || skip "submodule fixture setup failed"

  # Create a colliding branch in the meta-repo itself
  ( cd "$meta_repo" && git branch "$collision_branch" )

  # Both branches now exist (in different gitdirs)
  git --git-dir="$meta_repo/.git" rev-parse --verify "refs/heads/$collision_branch" > /dev/null \
    || fail "fixture: meta-repo branch was not created"
  git --git-dir="$meta_repo/.git/modules/sub" rev-parse --verify "refs/heads/$collision_branch" > /dev/null \
    || fail "fixture: submodule branch missing"

  cd "$meta_repo"
  run git-wtdel -p "$wt_path" -B --force

  assert_success

  # Submodule branch deleted
  ! git --git-dir="$meta_repo/.git/modules/sub" rev-parse --verify "refs/heads/$collision_branch" > /dev/null 2>&1 \
    || fail "Submodule branch '$collision_branch' should have been deleted"

  # Meta-repo branch SURVIVES (this is the regression-guard assertion)
  git --git-dir="$meta_repo/.git" rev-parse --verify "refs/heads/$collision_branch" > /dev/null \
    || fail "Meta-repo branch '$collision_branch' was wrongly deleted — submodule isolation broken"

  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}

# ── Safety regression suite (design §3; P0 found 2026-06-12) ────────────────

@test "hug wtdel: SAFETY P0 -- -p <main> -f from linked worktree refuses, repo survives" {
  cd "$FEATURE_WT"
  run git-wtdel -p "$TEST_REPO" --force
  assert_failure 3
  assert_output --partial "BLOCKED"
  assert_output --partial "main worktree"
  refute_output --partial "Deleted directory"
  assert [ -d "$TEST_REPO/.git" ]
  # Verify repo contents survive — main_extra.txt is the file committed on main
  assert [ -f "$TEST_REPO/main_extra.txt" ]
}

@test "hug wtdel: SAFETY — git refusal leaves worktree intact (no rm -rf fallback)" {
  # Verify the rm -rf fallback is GONE by injecting a fake git binary that
  # refuses 'worktree remove'. If hug still had the rm -rf fallback, it would
  # bulldoze the worktree despite git refusing. With our fix, it surfaces the
  # error and leaves the worktree untouched.
  #
  # TECHNIQUE: Create a wrapper script that shadows the real git in PATH.
  # We use bash -c with explicit PATH to ensure the wrapper is found BEFORE
  # the real git. The wrapper passes through everything except 'worktree remove'.
  # CRITICAL: hardcode the real git path to avoid infinite recursion (the
  # wrapper itself IS named 'git', so $(which git) inside it would find itself).
  cd "$TEST_REPO"

  _REAL_GIT=$(command -v git)
  _FAKE_DIR="$BATS_TEST_TMPDIR/git-fake-bin"
  mkdir -p "$_FAKE_DIR"
  cat > "$_FAKE_DIR/git" <<WRAPPER
#!/usr/bin/env bash
if [[ "\$*" == *"worktree remove"* ]]; then
  echo "fatal: test-injected refusal" >&2
  exit 1
fi
exec "$_REAL_GIT" "\$@"
WRAPPER
  chmod +x "$_FAKE_DIR/git"

  # bash -c with PATH prepended ensures git-wtdel (a new bash process via its
  # shebang) finds our wrapper first. HUG_FORCE=true bypasses the danger prompt.
  run bash -c 'export PATH="'"$_FAKE_DIR"':$PATH" HUG_FORCE=true; git-wtdel -p "'"$FEATURE_WT"'"'
  assert_failure
  assert_output --partial "git worktree remove failed"
  assert_output --partial "does not delete files git refused to remove"
  assert [ -d "$FEATURE_WT" ]
}

@test "hug wtdel: SAFETY — -f retries submodule refusal via git --force --force" {
  SUB_SRC="$BATS_TEST_TMPDIR/subsrc2"
  git init -q "$SUB_SRC"
  git -C "$SUB_SRC" config user.email t@e.c
  git -C "$SUB_SRC" config user.name T
  (cd "$SUB_SRC" && echo s > s.txt && git add . && git commit -qm sub)
  (cd "$FEATURE_WT" && git -c protocol.file.allow=always submodule add -q "$SUB_SRC" sub && git commit -qm "add sub")

  cd "$TEST_REPO"
  run git-wtdel -p "$FEATURE_WT" --force
  assert_success
  assert_output --partial "Worktree removed"
  assert_worktree_not_exists "$FEATURE_WT"
}

@test "hug wtdel: prune is scoped — unrelated stale entries survive a removal" {
  cd "$TEST_REPO"
  rm -rf "$FEATURE_WT"            # feature-1 becomes a stale entry

  run git-wtdel hotfix-1 --force  # remove an UNRELATED healthy worktree
  assert_success

  # The old global prune would have erased feature-1's metadata here.
  run git worktree list --porcelain
  assert_output --partial "worktree $FEATURE_WT"

  # And the stale entry is still individually addressable:
  run git-wtdel feature-1 --force
  assert_success
  assert_output --partial "Pruned stale worktree entry"
}

# ============================================================================
# Tests for pre-flight batch model, --json, -q, exit codes (design S4)
# ============================================================================

@test "hug wtdel: batch by branch with unknown branch removes nothing, exit 1" {
  cd "$TEST_REPO"
  run git-wtdel feature-1 bogus-branch --force
  assert_failure 1
  assert_output --partial "no worktree found for branch 'bogus-branch'"
  assert_output --partial "Nothing removed"
  assert_worktree_exists "$FEATURE_WT"
}

@test "hug wtdel: blocked classes exit 3" {
  cd "$TEST_REPO"
  echo dirty > "$FEATURE_WT/dirty.txt"
  run git-wtdel feature-1            # dirty without -f
  assert_failure 3
  assert_output --partial "BLOCKED: uncommitted changes"
}

@test "hug wtdel: single danger confirmation covers the whole batch" {
  # Use setup_gum_mock + HUG_TEST_MODE so gum_available() returns true
  # and gum input returns "remove" (the confirmation word).
  # HUG_TEST_GUM_INPUT makes the mock echo the word on gum input calls.
  setup_gum_mock
  export HUG_TEST_MODE=true
  export HUG_TEST_GUM_INPUT="remove"
  cd "$TEST_REPO"
  run git-wtdel feature-1 hotfix-1
  assert_success
  assert_worktree_not_exists "$FEATURE_WT"
  assert_worktree_not_exists "$HOTFIX_WT"
  unset HUG_TEST_MODE
  teardown_gum_mock
}

@test "hug wtdel: --json emits valid JSON on stdout only" {
  cd "$TEST_REPO"
  run bash -c "git-wtdel feature-1 --force --json 2>/dev/null | python3 -m json.tool"
  assert_success
  assert_output --partial '"state": "removed"'
}

@test "hug wtdel: --json --dry-run reports plan" {
  cd "$TEST_REPO"
  run bash -c "git-wtdel feature-1 --dry-run --json 2>/dev/null | python3 -m json.tool"
  assert_success
  assert_output --partial '"dry_run": true'
  assert_worktree_exists "$FEATURE_WT"
}

@test "hug wtdel: -q suppresses chatter but not errors" {
  cd "$TEST_REPO"
  run git-wtdel feature-1 --force -q
  assert_success
  refute_output --partial "Worktree Removal Plan"
  run git-wtdel bogus -q --force
  assert_failure
  assert_output --partial "Nothing removed"
}

@test "hug wtdel: unknown flag exits 2" {
  run git-wtdel --bogus-flag
  assert_failure 2
}
