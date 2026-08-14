#!/usr/bin/env bats
# Regression tests for gateway help forwarding.

load ../test_helper

setup() {
  require_hug
  TEST_REPO=$(create_demo_repo_simple)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

@test "hug h files --help reaches subcommand help" {
  run hug h files --help

  assert_success
  assert_output --partial "hug h files"
  assert_output --partial "USAGE:"
}

@test "hug w discard --help reaches subcommand help" {
  run hug w discard --help

  assert_success
  assert_output --partial "hug w discard"
  assert_output --partial "--force"
}

@test "hug stats file --help reaches subcommand help" {
  run hug stats file --help

  assert_success
  assert_output --partial "hug stats file"
  assert_output --partial "USAGE:"
}