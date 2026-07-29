#!/usr/bin/env bats
# Tests for hug h restore — the recovery primitive (exact-SHA no-op, forward reset)

# Load test helpers
load '../test_helper'

setup() {
  enable_gum_for_test
  require_hug
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

# -----------------------------------------------------------------------------
# Core operational tests
# -----------------------------------------------------------------------------

@test "restore --back is a soft reset (changes stay staged)" {
  original_head=$(git rev-parse HEAD)

  hug h back 1 --force                             # HEAD back 1, changes staged
  run hug h restore "$original_head" --back -y
  assert_success
  [ "$(git rev-parse HEAD)" = "$original_head" ]
}

@test "restore: exact-SHA target == HEAD is a true no-op" {
  run hug h restore "$(git rev-parse HEAD)" --back -y
  assert_success
  assert_output --partial "Already at"
}

@test "restore: forward (descendant) target MOVES HEAD (no short-circuit no-op)" {
  hug h back 2 --force                              # HEAD now 2 behind
  ahead=$(git rev-parse "HEAD@{1}")                 # a descendant of current HEAD
  run hug h restore "$ahead" --back -y
  assert_success
  [ "$(git rev-parse HEAD)" = "$ahead" ]            # moved forward — NOT 'Already at'
  refute_output --partial "Already at"
}

@test "restore --rewind is a hard reset" {
  original_head=$(git rev-parse HEAD)
  run hug h restore "$(git rev-parse HEAD~1)" --rewind -y
  assert_success
  [ "$(git rev-parse HEAD)" != "$original_head" ]
}
