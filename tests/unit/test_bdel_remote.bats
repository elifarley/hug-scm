#!/usr/bin/env bats
# Tests for the --remote flag on hug bdel (remote branch deletion).
#
# WHY A SEPARATE FILE: Remote branch deletion is a distinct code path from local
# deletion (no merged/unmerged concept, no current-branch guard, uses git push
# --delete). Keeping tests in a dedicated file isolates the remote-specific setup
# (bare origin, pushed branches) from local-only tests in test_bdel.bats.

# Load test helpers
load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_remote_upstream)
  cd "$TEST_REPO"

  # Push feature branches to origin for remote-deletion tests.
  # The remote is a bare git repo at a local path, so "pushing" is instant.
  git checkout -q -b feature
  echo "feature work" > feature.txt
  git add feature.txt
  git commit -q -m "Add feature"
  git push -q origin feature

  git checkout -q main
  git checkout -q -b bugfix
  echo "bugfix work" > bugfix.txt
  git add bugfix.txt
  git commit -q -m "Add bugfix"
  git push -q origin bugfix

  # Return to main so we have a stable HEAD for all tests.
  git checkout -q main
  git fetch -q
}

teardown() {
  cleanup_test_repo
}

# -----------------------------------------------------------------------------
# Help and basic validation
# -----------------------------------------------------------------------------

@test "hug bdel --help: shows --remote option in help text" {
  run bash -c "hug bdel -h 2>&1"
  assert_success
  assert_output --partial "--remote"
  assert_output --partial "Delete remote branches"
}

@test "hug bdel --remote: with no branches shows error" {
  run hug bdel --remote
  assert_failure
  assert_output --partial "--remote requires at least one branch name"
}

@test "hug bdel -r: with no branches shows error (short form)" {
  run hug bdel -r
  assert_failure
  assert_output --partial "--remote requires at least one branch name"
}

# -----------------------------------------------------------------------------
# Remote branch deletion (happy path)
# -----------------------------------------------------------------------------

@test "hug bdel --remote -f <branch>: deletes remote branch" {
  # Verify the branch exists on the remote before deletion.
  run git show-ref --verify --quiet refs/remotes/origin/feature
  assert_success

  # Delete with -f to skip confirmation prompt.
  run hug bdel --remote feature -f
  assert_success
  assert_output --partial "Deleted 1 remote branch"
  assert_output --partial "origin/feature"

  # Fetch to update remote-tracking refs, then verify it's gone.
  git fetch -q origin --prune
  run git show-ref --verify --quiet refs/remotes/origin/feature
  assert_failure
}

@test "hug bdel --remote <branch>: prompts for confirmation" {
  # Respond "n" to the confirmation prompt — should cancel.
  run bash -c "echo 'n' | hug bdel --remote feature 2>&1"
  assert_failure
  assert_output --partial "About to delete 1 remote branch"
  assert_output --partial "Cancelled"

  # Verify the branch still exists on the remote.
  run git show-ref --verify --quiet refs/remotes/origin/feature
  assert_success
}

@test "hug bdel --remote <branch>: confirms deletion when user types y" {
  # Respond "y" to the confirmation prompt — should proceed.
  run bash -c "echo 'y' | hug bdel --remote feature 2>&1"
  assert_success
  assert_output --partial "Deleted 1 remote branch"
  assert_output --partial "origin/feature"

  # Verify the branch is gone from the remote.
  git fetch -q origin --prune
  run git show-ref --verify --quiet refs/remotes/origin/feature
  assert_failure
}

@test "hug bdel --remote -f <branch>: skips confirmation prompt" {
  # With -f, the "About to delete" warning should not appear.
  run hug bdel --remote feature -f
  assert_success
  assert_output --partial "Deleted 1 remote branch"
  refute_output --partial "About to delete"
}

# -----------------------------------------------------------------------------
# Dry-run
# -----------------------------------------------------------------------------

@test "hug bdel --remote --dry-run <branch>: previews without deleting" {
  run hug bdel --remote --dry-run feature
  assert_success
  assert_output --partial "Dry run"
  assert_output --partial "Would delete 1 remote branch"
  assert_output --partial "origin/feature"

  # Verify the branch still exists on the remote (dry-run must not delete).
  run git show-ref --verify --quiet refs/remotes/origin/feature
  assert_success
}

@test "hug bdel --remote --dry-run: with multiple branches previews all" {
  run hug bdel --remote --dry-run feature bugfix
  assert_success
  assert_output --partial "Would delete 2 remote branch"
  assert_output --partial "origin/feature"
  assert_output --partial "origin/bugfix"

  # Both must still exist.
  git show-ref --verify --quiet refs/remotes/origin/feature
  git show-ref --verify --quiet refs/remotes/origin/bugfix
}

# -----------------------------------------------------------------------------
# Multiple branches
# -----------------------------------------------------------------------------

@test "hug bdel --remote -f <branch1> <branch2>: deletes multiple remote branches" {
  run hug bdel --remote -f feature bugfix
  assert_success
  assert_output --partial "Deleted 2 remote branches"
  assert_output --partial "origin/feature"
  assert_output --partial "origin/bugfix"

  # Verify both are gone from the remote.
  git fetch -q origin --prune
  run git show-ref --verify --quiet refs/remotes/origin/feature
  assert_failure
  run git show-ref --verify --quiet refs/remotes/origin/bugfix
  assert_failure
}

# -----------------------------------------------------------------------------
# Validation and input normalization
# -----------------------------------------------------------------------------

@test "hug bdel --remote: strips origin/ prefix automatically" {
  # Pass origin/feature — bdel should strip the prefix and delete feature.
  run hug bdel --remote -f origin/feature
  assert_success
  assert_output --partial "Stripping 'origin/' prefix"
  assert_output --partial "Deleted 1 remote branch"
  assert_output --partial "origin/feature"

  # Verify the branch is gone from the remote.
  git fetch -q origin --prune
  run git show-ref --verify --quiet refs/remotes/origin/feature
  assert_failure
}

@test "hug bdel --remote: rejects refs/* paths as unsafe" {
  run hug bdel --remote -f refs/heads/main
  assert_failure
  assert_output --partial "unsafe for remote deletion"
}

@test "hug bdel --remote: rejects wildcard characters as unsafe" {
  run hug bdel --remote -f "feature*"
  assert_failure
  assert_output --partial "unsafe for remote deletion"
}

@test "hug bdel --remote: rejects refspec colon syntax as unsafe" {
  run hug bdel --remote -f "feature:main"
  assert_failure
  assert_output --partial "unsafe for remote deletion"
}

@test "hug bdel --remote: rejects caret (^) as unsafe" {
  run hug bdel --remote -f "feature^"
  assert_failure
  assert_output --partial "unsafe for remote deletion"
}

@test "hug bdel --remote: rejects tilde (~) as unsafe" {
  run hug bdel --remote -f "feature~1"
  assert_failure
  assert_output --partial "unsafe for remote deletion"
}

@test "hug bdel --remote: rejects bracket ([) as unsafe" {
  run hug bdel --remote -f "feature[0]"
  assert_failure
  assert_output --partial "unsafe for remote deletion"
}

@test "hug bdel --remote: rejects brace ({) as unsafe" {
  run hug bdel --remote -f "feature{1}"
  assert_failure
  assert_output --partial "unsafe for remote deletion"
}

@test "hug bdel --remote: rejects flag-like branch name" {
  # The outer argument parser catches --dangerous as an unknown option before
  # it reaches the inner branch-name validation loop. The inner check
  # (`[[ "$branch" == -* ]]`) is a defense-in-depth guard that is unreachable
  # from the CLI (both -x and --x are caught by the outer parser's `-*) case).
  # This test validates the outer defense layer.
  run hug bdel --remote -f "--dangerous"
  assert_failure
  assert_output --partial "Unknown option"
}

@test "hug bdel --remote: rejects empty branch name" {
  # Passing an empty string as branch name — this is edge-case validation.
  run hug bdel --remote -f ""
  assert_failure
  assert_output --partial "cannot be empty"
}

# -----------------------------------------------------------------------------
# Error cases
# -----------------------------------------------------------------------------

@test "hug bdel --remote: nonexistent branch reports failure" {
  # "ghost" was never pushed to origin, so git push --delete will fail.
  run hug bdel --remote -f ghost
  assert_failure
  assert_output --partial "Failed to delete 1 remote branch"
  assert_output --partial "origin/ghost"
}

# -----------------------------------------------------------------------------
# Flag ordering and short forms
# -----------------------------------------------------------------------------

@test "hug bdel -r -f <branch>: short -r works the same as --remote" {
  run hug bdel -r -f feature
  assert_success
  assert_output --partial "Deleted 1 remote branch"
  assert_output --partial "origin/feature"

  git fetch -q origin --prune
  run git show-ref --verify --quiet refs/remotes/origin/feature
  assert_failure
}
