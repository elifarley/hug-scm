#!/usr/bin/env bats
load '../test_helper'

@test "tests do not modify global git config" {
  original_name=$(git config --global user.name || echo "")
  # Run a representative test action (e.g., create and clean a repo)
  TEST_REPO=$(create_test_repo)
  pushd "$TEST_REPO" > /dev/null
  git config --local user.name "Temp Test"
  popd > /dev/null
  # NOTE: cleanup_test_repo uses $TEST_REPO from environment if set
  cleanup_test_repo "$TEST_REPO"
  assert_equal "$(git config --global user.name || echo "")" "$original_name"
}
