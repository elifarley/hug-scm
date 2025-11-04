#!/usr/bin/env bats

load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
  
  # Create test commits
  echo "content" > file1.txt
  echo "content" > file2.txt
  git add .
  git commit -m "test commit"
}

teardown() {
  cleanup_test_repo
}

@test "hug lf: triggers interactive file selection with --" {
  # Without gum, should show error about needing gum
  run hug lf "test" --
  assert_failure
  assert_output --partial "Interactive file selection requires 'gum'"
}

@test "hug lc: triggers interactive file selection with --" {
  run hug lc "content" --
  assert_failure
  assert_output --partial "Interactive file selection requires 'gum'"
}

@test "hug lcr: triggers interactive file selection with --" {
  run hug lcr "test.*" --
  assert_failure
  assert_output --partial "Interactive file selection requires 'gum'"
}

@test "hug ss: triggers interactive file selection with --" {
  echo "new content" >> file1.txt
  git add file1.txt
  
  run hug ss --
  # Status commands show info message instead of error when gum unavailable
  assert_success
  assert_output --partial "No staged files available or cancelled"
}

@test "hug su: triggers interactive file selection with --" {
  echo "unstaged" >> file1.txt
  
  run hug su --
  # Status commands show info message instead of error when gum unavailable
  assert_success
  assert_output --partial "No unstaged files available or cancelled"
}

@test "hug sw: triggers interactive file selection with --" {
  echo "working" >> file1.txt
  
  run hug sw --
  # Status commands show info message instead of error when gum unavailable
  assert_success
  assert_output --partial "No files with working directory changes available or cancelled"
}
