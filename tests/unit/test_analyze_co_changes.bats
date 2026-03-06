#!/usr/bin/env bats
# Tests for hug analyze co-changes command contract

load ../test_helper

setup() {
  require_hug
  TEST_REPO=$(create_demo_repo_simple)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

@test "hug analyze co-changes: shows updated help" {
  run git analyze-co-changes -h

  assert_success
  assert_output --partial "hug analyze co-changes <file> [options]"
  assert_output --partial "hug analyze co-changes --all [options]"
  assert_output --partial "--commits <n>"
}

@test "hug analyze co-changes: requires file or --all when gum is unavailable" {
  disable_gum_for_test

  run hug analyze co-changes

  assert_failure
  assert_output --partial "File argument required"
  assert_output --partial "hug analyze co-changes --all"
}

@test "hug analyze co-changes: file mode shows related files" {
  run hug analyze co-changes file1.txt --commits 10 --threshold 0.50

  assert_success
  assert_output --partial "Related files for file1.txt"
  assert_output --partial "Target file changed in 2 analyzed commits"
  assert_output --partial "file2.txt"
}

@test "hug analyze co-changes: --all shows repository-wide coupling" {
  run hug analyze co-changes --all --commits 10 --threshold 0.50

  assert_success
  assert_output --partial "Co-change Analysis"
  assert_output --partial "file1.txt ↔ file2.txt"
}

@test "hug analyze co-changes: rejects legacy positional count syntax" {
  run hug analyze co-changes 10

  assert_failure
  assert_output --partial "Positional commit counts were removed"
}