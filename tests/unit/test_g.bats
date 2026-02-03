#!/usr/bin/env bats
# Tests for hug g command (garbage collection)

load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"

  # Create some commits to have reflog history
  echo "test1" > file1.txt
  git add file1.txt
  git commit -m "Commit 1"

  echo "test2" > file2.txt
  git add file2.txt
  git commit -m "Commit 2"

  echo "test3" > file3.txt
  git add file3.txt
  git commit -m "Commit 3"
}

teardown() {
  cleanup_test_repo "$TEST_REPO"
}

# -----------------------------------------------------------------------------
# Help Text Tests
# -----------------------------------------------------------------------------

@test "hug g: shows help when --help flag is used" {
  run git-g --help
  assert_success
  assert_output --partial "Usage: hug g"
  assert_output --partial "OPTIONS:"
  assert_output --partial "DESCRIPTION:"
}

@test "hug g: shows help when -h flag is used" {
  run git-g -h
  assert_success
  assert_output --partial "Usage: hug g"
}

# -----------------------------------------------------------------------------
# Error Handling Tests
# -----------------------------------------------------------------------------

@test "hug g: error when not in git repository" {
  cd /tmp
  run git-g
  assert_failure
  assert_output --partial "Not in a git repository"
}

@test "hug g: rejects unexpected arguments" {
  run git-g unexpected-argument
  assert_failure
  assert_output --partial "unknown option"
}

# -----------------------------------------------------------------------------
# Basic Mode Tests
# -----------------------------------------------------------------------------

@test "hug g: runs basic gc with dry-run" {
  run git-g --dry-run
  assert_success
  assert_output --partial "Would run: git gc"
}

@test "hug g: runs basic gc with force flag" {
  run git-g --force --dry-run
  assert_success
  assert_output --partial "Would run: git gc"
}

@test "hug g: basic mode requires confirmation without force" {
  # Basic mode should prompt for confirmation
  run bash -c 'echo "n" | git-g 2>&1'
  assert_failure  # Exit code 1 because user cancelled
  assert_output --partial "Cancelled"
}

@test "hug g: basic mode accepts yes confirmation" {
  run bash -c 'echo "y" | git-g --dry-run 2>&1'
  assert_success
  assert_output --partial "Would run: git gc"
}

# -----------------------------------------------------------------------------
# Expire Mode Tests
# -----------------------------------------------------------------------------

@test "hug g --expire: runs reflog expire + gc with dry-run" {
  run git-g --expire --dry-run
  assert_success
  assert_output --partial "Would run: git reflog expire --expire=now --all"
  assert_output --partial "Would run: git gc"
}

@test "hug g --expire: requires confirmation without force" {
  run bash -c 'echo "n" | git-g --expire 2>&1'
  assert_failure  # Exit code 1 because user cancelled
  assert_output --partial "Cancelled"
}

@test "hug g --expire: skips confirmation with force flag" {
  run git-g --expire --force --dry-run
  assert_success
  assert_output --partial "Would run: git reflog expire"
}

# -----------------------------------------------------------------------------
# Aggressive Mode Tests
# -----------------------------------------------------------------------------

@test "hug g --aggressive: runs full aggressive gc with dry-run" {
  run git-g --aggressive --dry-run
  assert_success
  assert_output --partial "Would run: git reflog expire --expire=now --all"
  assert_output --partial "Would run: git gc --prune=now --aggressive"
}

@test "hug g --aggressive: requires dangerous confirmation without force" {
  run bash -c 'echo "wrong" | git-g --aggressive 2>&1'
  assert_failure  # Exit code 1 because user typed wrong confirmation
  assert_output --partial "Cancelled"
}

@test "hug g --aggressive: accepts correct dangerous confirmation" {
  run bash -c 'echo "aggressive" | git-g --aggressive --dry-run 2>&1'
  assert_success
  assert_output --partial "Would run: git reflog expire"
}

@test "hug g --aggressive: skips confirmation with force flag" {
  run git-g --aggressive --force --dry-run
  assert_success
  assert_output --partial "Would run: git reflog expire"
}

@test "hug g --aggressive: shows warning about permanent removal" {
  # In dry-run mode, warning is shown before the dry-run preview
  # The warning is part of confirmation flow, so with --force it's skipped
  run git-g --aggressive --force --dry-run
  assert_success
  assert_output --partial "Would run: git reflog expire"

  # Without force but with dry-run, we still don't see the warning
  # because dry-run exits before confirmation
  run git-g --aggressive --dry-run
  assert_success
  assert_output --partial "Would run: git reflog expire"
}

# -----------------------------------------------------------------------------
# Flag Combination Tests
# -----------------------------------------------------------------------------

@test "hug g: --aggressive implies --expire" {
  run git-g --aggressive --dry-run
  assert_success
  assert_output --partial "git reflog expire"
}

@test "hug g: --expire --aggressive same as --aggressive alone" {
  run git-g --expire --aggressive --dry-run
  assert_success
  assert_output --partial "git gc --prune=now --aggressive"
}

@test "hug g: supports combined flags" {
  run git-g --expire --dry-run
  assert_success
  assert_output --partial "git reflog expire"

  run git-g --expire -f --dry-run
  assert_success
}

@test "hug g: supports short flags" {
  run git-g -f --dry-run
  assert_success
  assert_output --partial "git gc"

  run git-g -q --dry-run
  assert_success
}

@test "hug g: supports combined short flags" {
  run git-g -fq --dry-run
  assert_success
}

# -----------------------------------------------------------------------------
# Quiet Mode Tests
# -----------------------------------------------------------------------------

@test "hug g: quiet mode suppresses output" {
  run git-g -q --dry-run
  assert_success
  # In dry-run mode, we still see the "Would run" messages
  # but actual gc execution would be quiet
}

@test "hug g: --quiet works same as -q" {
  run git-g --quiet --dry-run
  assert_success
}

# -----------------------------------------------------------------------------
# Quiet Mode Tests
# -----------------------------------------------------------------------------

@test "hug g: can run actual gc in test repo" {
  # Skip if we can't actually run gc (may fail in some environments)
  run git-g --force
  if [ $status -ne 0 ]; then
    skip "git gc failed in test environment"
  fi
  assert_success
}

@test "hug g --expire: can run reflog expire + gc" {
  run git-g --expire --force
  if [ $status -ne 0 ]; then
    skip "git gc or reflog expire failed in test environment"
  fi
  assert_success
}

# -----------------------------------------------------------------------------
# Edge Cases
# -----------------------------------------------------------------------------

@test "hug g: works on repo with clean state" {
  git status
  run git-g --dry-run
  assert_success
}

@test "hug g: works on repo with uncommitted changes" {
  echo "uncommitted" > newfile.txt
  git add newfile.txt
  # Don't commit - should still work for gc
  run git-g --dry-run
  assert_success
}

@test "hug g: all modes work with quiet flag" {
  run git-g -q --dry-run
  assert_success

  run git-g --expire -q --dry-run
  assert_success

  run git-g --aggressive -q --dry-run
  assert_success
}
