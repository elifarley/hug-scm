#!/usr/bin/env bats
# Tests for fast-forward merge (hug mff / git mff)
#
# TDD baseline: these tests capture the existing one-arg behavior of mff,
# which is currently a gitconfig alias (merge --ff-only). They will fail
# until mff is promoted to a full script with --help and arg validation.

load '../test_helper'

setup() {
  enable_gum_for_test
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

# Helper: create a linear branch structure
# main: A -- B -- C
#                \-- feature: D -- E
setup_linear_branches() {
  # main already has initial commit (A)

  echo "main1" > main1.txt
  git add main1.txt
  git commit -m "Main commit B"

  echo "main2" > main2.txt
  git add main2.txt
  git commit -m "Main commit C"

  # Create feature branch ahead of main
  git checkout -q -b feature
  echo "feat1" > feat1.txt
  git add feat1.txt
  git commit -m "Feature commit D"

  echo "feat2" > feat2.txt
  git add feat2.txt
  git commit -m "Feature commit E"

  # Go back to main
  git checkout -q main
}

# -----------------------------------------------------------------------------
# One-arg form (existing behavior)
# -----------------------------------------------------------------------------

@test "hug mff -h: shows help with cross-references" {
  run hug mff -h
  assert_success
  assert_output --partial "hug mff:"
  assert_output --partial "USAGE:"
  assert_output --partial "SEE ALSO"
  assert_output --partial "hug bmv"
}

@test "hug mff <target>: fast-forwards current branch" {
  setup_linear_branches

  run hug mff feature
  assert_success
  assert_output --partial "Fast-forward"
}

@test "hug mff <target>: current branch now at feature's commit" {
  setup_linear_branches

  hug mff feature
  current_commit=$(git rev-parse HEAD)
  feature_commit=$(git rev-parse feature)
  [ "$current_commit" = "$feature_commit" ]
}

@test "hug mff <target>: fails when not a fast-forward" {
  setup_linear_branches

  # Add a commit to main so it diverges
  echo "diverge" > diverge.txt
  git add diverge.txt
  git commit -m "Diverge from feature"

  run hug mff feature
  assert_failure
}

@test "hug mff: requires at least one argument" {
  run hug mff
  assert_failure
  assert_output --partial "USAGE"
}
