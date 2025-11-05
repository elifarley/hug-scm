#!/usr/bin/env bats
# Tests for hug-git-commit library: commit range analysis functions

load '../test_helper'
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-git-repo'
load '../../git-config/lib/hug-git-commit'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
  
  # Create a few commits for testing
  echo "first" > file1.txt
  git add file1.txt
  git commit -q -m "first commit"
  
  echo "second" > file2.txt
  git add file2.txt
  git commit -q -m "second commit"
  
  echo "third" > file3.txt
  git add file3.txt
  git commit -q -m "third commit"
}

teardown() {
  cleanup_test_repo
}

################################################################################
# count_commits_in_range TESTS
################################################################################

@test "count_commits_in_range: counts commits between two refs" {
  run count_commits_in_range HEAD~2 HEAD
  assert_success
  assert_output "2"
}

@test "count_commits_in_range: returns 0 for same ref" {
  run count_commits_in_range HEAD HEAD
  assert_success
  assert_output "0"
}

@test "count_commits_in_range: uses HEAD as default end" {
  run count_commits_in_range HEAD~1
  assert_success
  assert_output "1"
}

################################################################################
# list_changed_files_in_range TESTS
################################################################################

@test "list_changed_files_in_range: lists changed files" {
  run list_changed_files_in_range HEAD~2 HEAD
  assert_success
  assert_line "file2.txt"
  assert_line "file3.txt"
}

@test "list_changed_files_in_range: returns empty for same ref" {
  run list_changed_files_in_range HEAD HEAD
  assert_success
  assert_output ""
}

################################################################################
# count_changed_files_in_range TESTS
################################################################################

@test "count_changed_files_in_range: counts changed files" {
  run count_changed_files_in_range HEAD~2 HEAD
  assert_success
  assert_output "2"
}

@test "count_changed_files_in_range: returns 0 for same ref" {
  run count_changed_files_in_range HEAD HEAD
  assert_success
  assert_output "0"
}
