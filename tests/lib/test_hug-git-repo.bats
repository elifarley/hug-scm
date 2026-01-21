#!/usr/bin/env bats
# Tests for hug-git-repo library: repository and commit validation functions

load '../test_helper'
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-git-repo'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

################################################################################
# check_git_repo TESTS
################################################################################

@test "check_git_repo: succeeds in git repository" {
  # Simply calling check_git_repo in setup should work if we're in a git repo
  check_git_repo
}

@test "check_git_repo: sets GIT_PREFIX" {
  mkdir -p subdir
  cd subdir
  check_git_repo
  [[ "$GIT_PREFIX" == "subdir/" ]]
}

################################################################################
# validate_commit TESTS
################################################################################

@test "validate_commitish: errors on empty commitish" {
  run validate_commitish "--target" ""
  assert_failure
  assert_output --partial "--target requires a non-empty commitish"
}

@test "validate_commitish: errors on invalid commitish" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  
  run validate_commitish "--target" "invalidref"
  assert_failure
  assert_output --partial "Invalid commitish for --target: invalidref"
}

@test "validate_commitish: succeeds for valid commitish" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  
  validate_commitish "--target" HEAD
}

################################################################################
# ensure_commit_exists TESTS
################################################################################

@test "ensure_commit_exists: succeeds for HEAD" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  
  ensure_commit_exists HEAD
}

################################################################################
# resolve_head_target TESTS
################################################################################

@test "resolve_head_target: returns default for empty arg" {
  run resolve_head_target ""
  assert_success
  assert_output "HEAD~1"
}

@test "resolve_head_target: returns HEAD~N for number" {
  run resolve_head_target "3"
  assert_success
  assert_output "HEAD~3"
}

@test "resolve_head_target: returns argument for commit hash" {
  run resolve_head_target "abc123"
  assert_success
  assert_output "abc123"
}

@test "resolve_head_target: uses custom default" {
  run resolve_head_target "" "HEAD~5"
  assert_success
  assert_output "HEAD~5"
}

################################################################################
# resolve_head_target_as_range TESTS
################################################################################

@test "resolve_head_target_as_range: returns default for empty arg" {
  run resolve_head_target_as_range ""
  assert_success
  assert_output "HEAD"
}

@test "resolve_head_target_as_range: returns HEAD~N..HEAD for number" {
  run resolve_head_target_as_range "3"
  assert_success
  assert_output "HEAD~3..HEAD"
}

@test "resolve_head_target_as_range: returns argument for commit hash" {
  run resolve_head_target_as_range "abc123"
  assert_success
  assert_output "abc123"
}

@test "resolve_head_target_as_range: passes through existing range" {
  run resolve_head_target_as_range "main..feature"
  assert_success
  assert_output "main..feature"
}

@test "resolve_head_target_as_range: uses custom default" {
  run resolve_head_target_as_range "" "HEAD~1"
  assert_success
  assert_output "HEAD~1"
}

@test "resolve_head_target_as_range: handles large numbers as commit hashes" {
  # Numbers >= 1000 should pass through as potential short hashes
  run resolve_head_target_as_range "1234"
  assert_success
  assert_output "1234"
}
