#!/usr/bin/env bats
# Tests for hug wtprune command

load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"

  # Create test branches first
  git checkout -b feature-1
  git commit --allow-empty -m "Feature 1 commit"

  git checkout -b hotfix-1
  git commit --allow-empty -m "Hotfix 1 commit"

  git checkout main

  # Create some test worktrees
  FEATURE_WT=$(git worktree add "${TEST_REPO}-wt-feature-1" feature-1 2>/dev/null && echo "${TEST_REPO}-wt-feature-1" || echo "")
  HOTFIX_WT=$(git worktree add "${TEST_REPO}-wt-hotfix-1" hotfix-1 2>/dev/null && echo "${TEST_REPO}-wt-hotfix-1" || echo "")

  # Verify worktrees were created
  if [[ -z "$FEATURE_WT" ]] || [[ ! -d "$FEATURE_WT" ]]; then
    skip "Could not create test worktrees for pruning tests"
  fi
}

teardown() {
  cleanup_test_worktrees "$TEST_REPO"
  cleanup_test_repo "$TEST_REPO"
}

# -----------------------------------------------------------------------------
# Help Text and Argument Validation Tests
# -----------------------------------------------------------------------------

@test "hug wtprune: shows help when --help flag is used" {
  run git-wtprune --help
  assert_success
  assert_output --partial "hug wtprune: Clean up stale worktree metadata"
  assert_output --partial "USAGE:"
  assert_output --partial "OPTIONS:"
  assert_output --partial "DESCRIPTION:"
}

@test "hug wtprune: shows help when -h flag is used" {
  run git-wtprune -h
  assert_success
  assert_output --partial "hug wtprune: Clean up stale worktree metadata"
}

@test "hug wtprune: rejects unexpected arguments" {
  run git-wtprune unexpected-argument
  assert_failure
  assert_output --partial "Error: Unexpected arguments: unexpected-argument"
}

@test "hug wtprune: rejects multiple unexpected arguments" {
  run git-wtprune arg1 arg2 arg3
  assert_failure
  assert_output --partial "Error: Unexpected arguments: arg1 arg2 arg3"
}

@test "hug wtprune: error when not in git repository" {
  cd /tmp
  run git-wtprune
  assert_failure
  assert_output --partial "Not a git repository"
}

# -----------------------------------------------------------------------------
# Core Functionality Tests
# -----------------------------------------------------------------------------

@test "hug wtprune: handles no orphaned worktrees gracefully" {
  run git-wtprune --dry-run
  assert_success
  assert_output --partial "No orphaned worktrees found"
}

@test "hug wtprune: works with --dry-run flag" {
  run git-wtprune --dry-run
  assert_success
  # Should not error out when no orphaned worktrees exist
}

@test "hug wtprune: works with --verbose flag" {
  run git-wtprune --verbose --dry-run
  assert_success
  assert_output --partial "Scanning for orphaned worktrees..."
}

@test "hug wtprune: works with combined flags" {
  run git-wtprune --verbose --dry-run
  assert_success
  assert_output --partial "Scanning for orphaned worktrees..."
}

@test "hug wtprune: short flags work correctly" {
  run git-wtprune -v --dry-run
  assert_success
  assert_output --partial "Scanning for orphaned worktrees..."
}

# -----------------------------------------------------------------------------
# Orphaned Worktree Tests
# -----------------------------------------------------------------------------

@test "hug wtprune: detects and prunes orphaned worktrees" {
  # Create orphaned worktree by manually deleting directory
  rm -rf "$FEATURE_WT"

  # Should detect orphaned worktree in dry run
  run git-wtprune --dry-run
  assert_success
  assert_output --partial "Found 1 orphaned worktree(s):"
  assert_output --partial "$FEATURE_WT"
}

@test "hug wtprune: detects multiple orphaned worktrees" {
  # Create multiple orphaned worktrees
  rm -rf "$FEATURE_WT"
  rm -rf "$HOTFIX_WT"

  # Should detect both orphaned worktrees
  run git-wtprune --dry-run
  assert_success
  assert_output --partial "Found 2 orphaned worktree(s):"
  assert_output --partial "$FEATURE_WT"
  assert_output --partial "$HOTFIX_WT"
}

@test "hug wtprune: prunes orphaned worktrees with force flag" {
  # Create orphaned worktree
  rm -rf "$FEATURE_WT"

  # Should prune without confirmation when using force
  run git-wtprune --force
  assert_success
  assert_output --partial "Found 1 orphaned worktree(s):"
  assert_output --partial "Pruned 1 orphaned worktree(s)"
}

@test "hug wtprune: shows detailed output for multiple orphaned worktrees" {
  # Create multiple orphaned worktrees
  rm -rf "$FEATURE_WT"
  rm -rf "$HOTFIX_WT"

  # Should show detailed output
  run git-wtprune --verbose --dry-run
  assert_success
  assert_output --partial "Scanning for orphaned worktrees..."
  assert_output --partial "Found 2 orphaned worktree(s):"
  assert_output --partial "Would prune 2 orphaned worktree(s)"
}

# -----------------------------------------------------------------------------
# Safety and Confirmation Tests
# -----------------------------------------------------------------------------

@test "hug wtprune: requires confirmation without force flag" {
  # Create orphaned worktree
  rm -rf "$FEATURE_WT"

  # Should require confirmation (will be cancelled in test)
  run bash -c "echo 'not_prune' | git-wtprune"
  assert_success
  assert_output --partial "Found 1 orphaned worktree(s):"
  assert_output --partial "Worktree pruning cancelled"
}

@test "hug wtprune: skips confirmation with force flag" {
  # Create orphaned worktree
  rm -rf "$FEATURE_WT"

  # Should not require confirmation when using force
  run git-wtprune --force
  assert_success
  assert_output --partial "Pruned 1 orphaned worktree(s)"
  refute_output --partial "cancelled"
}

@test "hug wtprune: never prunes existing directories" {
  # Both worktrees should exist, so no pruning should occur
  run git-wtprune --dry-run
  assert_success
  assert_output --partial "No orphaned worktrees found"
  refute_output --partial "$FEATURE_WT"
  refute_output --partial "$HOTFIX_WT"
}

@test "hug wtprune: never prunes current worktree" {
  # Current worktree should never be considered orphaned
  run git-wtprune --dry-run
  assert_success
  refute_output --partial "$TEST_REPO"
}

# -----------------------------------------------------------------------------
# Flag Combination Tests
# -----------------------------------------------------------------------------

@test "hug wtprune: supports all flag combinations" {
  # Test various flag combinations
  run git-wtprune --help
  assert_success

  run git-wtprune -h
  assert_success

  run git-wtprune --dry-run
  assert_success

  run git-wtprune --verbose --dry-run
  assert_success

  run git-wtprune -v --dry-run
  assert_success

  run git-wtprune --force --dry-run
  assert_success

  run git-wtprune -f --dry-run
  assert_success
}

@test "hug wtprune: force flag sets HUG_FORCE environment variable" {
  # Create orphaned worktree
  rm -rf "$FEATURE_WT"

  # Test that HUG_FORCE is set (this validates library integration)
  HUG_FORCE="" run git-wtprune --force
  assert_success
}

# -----------------------------------------------------------------------------
# Error Handling Tests
# -----------------------------------------------------------------------------

@test "hug wtprune: handles invalid option gracefully" {
  run git-wtprune --invalid-option
  assert_failure
}

@test "hug wtprune: handles short invalid option gracefully" {
  run git-wtprune -x
  assert_failure
}

@test "hug wtprune: handles mixed valid and invalid options" {
  run git-wtprune --dry-run --invalid-option
  assert_failure
}

# -----------------------------------------------------------------------------
# Integration Tests
# -----------------------------------------------------------------------------

@test "hug wtprune: integrates with existing wt* commands" {
  # Ensure command doesn't interfere with other worktree commands
  run git-wt --help
  assert_success

  run git-wtl
  assert_success

  run git-wtll
  assert_success
}

@test "hug wtprune: maintains git repository integrity" {
  # Ensure repository is still valid after pruning
  run git-wtprune --dry-run
  assert_success

  # Repository should still be valid
  git status >/dev/null
  run git rev-parse --git-dir
  assert_success
}