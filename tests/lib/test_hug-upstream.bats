#!/usr/bin/env bats
# Tests for hug-git-upstream library: handle_standard_operation aligned-target behavior

load '../test_helper'
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-git-state'
load '../../git-config/lib/hug-git-commit'
load '../../git-config/lib/hug-git-upstream'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

################################################################################
# handle_standard_operation: aligned-target cases
################################################################################

@test "handle_standard_operation: aligned + untracked-only -> 'Already at target' (no tracked-reset message)" {
  git checkout -q -b feature 2>/dev/null || true
  echo "note" > untracked.txt     # untracked only, no tracked changes
  target=$(git rev-parse HEAD)
  run handle_standard_operation "moving" "$target" false
  assert_output --partial "Already at target"
  refute_output --partial "tracked changes will be reset"
}

@test "handle_standard_operation: aligned + tracked-dirty + skip=false -> tracked-reset message" {
  echo "edit" >> feature1.txt     # tracked, unstaged
  target=$(git rev-parse HEAD)
  run handle_standard_operation "moving" "$target" false
  assert_output --partial "local tracked changes will be reset"
}
