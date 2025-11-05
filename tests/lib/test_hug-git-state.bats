#!/usr/bin/env bats
# Tests for hug-git-state library: working tree state checking functions

load '../test_helper'
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-git-repo'
load '../../git-config/lib/hug-git-state'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

################################################################################
# has_pending_changes TESTS
################################################################################

@test "has_pending_changes: returns false for clean repo" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  
  run has_pending_changes
  assert_failure
}

@test "has_pending_changes: returns true for unstaged changes" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  echo "modified" >> file.txt
  
  run has_pending_changes
  assert_success
}

@test "has_pending_changes: returns true for staged changes" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  echo "modified" >> file.txt
  git add file.txt
  
  run has_pending_changes
  assert_success
}

@test "has_pending_changes: returns true for untracked files" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  echo "untracked" > untracked.txt
  
  run has_pending_changes
  assert_success
}

################################################################################
# has_staged_changes TESTS
################################################################################

@test "has_staged_changes: returns false for no staged changes" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  
  run has_staged_changes
  assert_failure
}

@test "has_staged_changes: returns true for staged changes" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  echo "modified" >> file.txt
  git add file.txt
  
  run has_staged_changes
  assert_success
}

################################################################################
# has_unstaged_changes TESTS
################################################################################

@test "has_unstaged_changes: returns false for no unstaged changes" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  
  run has_unstaged_changes
  assert_failure
}

@test "has_unstaged_changes: returns true for unstaged changes" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  echo "modified" >> file.txt
  
  run has_unstaged_changes
  assert_success
}

################################################################################
# is_binary_staged TESTS
################################################################################

@test "is_binary_staged: returns false for text file" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  echo "modified" >> file.txt
  git add file.txt
  
  run is_binary_staged file.txt
  assert_failure
}

@test "is_binary_staged: returns false for no staged changes" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  
  run is_binary_staged file.txt
  assert_failure
}
