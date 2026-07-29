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
  # Soft reset doesn't touch the index; after restoring forward, the previously
  # staged changes are now committed (HEAD equals index), so the tree is clean.
  [ -z "$(git diff --cached --name-only)" ]
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
  # Hard reset matches the working tree to the target commit.
  [ -z "$(git diff --name-only)" ]
}

# -----------------------------------------------------------------------------
# Safety: bare-numeric guard (acceptance criterion 1)
# -----------------------------------------------------------------------------

@test "restore: bare numeric target refused (reads as HEAD~N)" {
  run hug h restore 42 --back -y
  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial "ambiguous target"
}

@test "restore: 4-char SHA resolves normally" {
  hug h back 1 --force
  short=$(git rev-parse --short=4 HEAD@{1})
  run hug h restore "$short" --back -y
  assert_success
}

@test "restore: 3-digit bare numeric refused (reads as HEAD~N)" {
  run hug h restore 123 --back -y
  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial "ambiguous target"
}

@test "restore: 4-plus digit numeric resolves normally (unambiguous)" {
  hug h back 1 --force
  # Use the first 4 chars of a real SHA so the resolution succeeds.
  # The bare-numeric guard only catches 1-3 digits; 4+ is unambiguous.
  short4=$(git rev-parse --short=4 HEAD@{1})
  run hug h restore "$short4" --back -y
  assert_success
}

# -----------------------------------------------------------------------------
# Safety: --rewind+dirty danger escalation (acceptance criteria 3-5)
# -----------------------------------------------------------------------------

@test "restore --rewind on dirty tracked tree + -y -> refused exit 3" {
  echo "edit" >> feature1.txt              # tracked, unstaged
  # Use HEAD~1, not HEAD — HEAD triggers the exact-SHA no-op (exit 0) before
  # the tier escalation, preventing us from testing the danger gate.
  run hug h restore "$(git rev-parse HEAD~1)" --rewind -y
  [ "$status" -eq 3 ]
}

@test "restore --rewind on dirty tree + -f -> proceeds" {
  echo "edit" >> feature1.txt              # tracked, unstaged
  run hug h restore "$(git rev-parse HEAD~1)" --rewind -f
  assert_success
  [ "$(git rev-parse HEAD)" != "$(git rev-parse HEAD~1)" ]
}

@test "restore --back on dirty tree + -y -> proceeds (soft preserves)" {
  hug h back 1 --force
  target=$(git rev-parse HEAD@{1})
  echo "edit" >> feature1.txt              # tracked, unstaged
  run hug h restore "$target" --back -y
  assert_success
  [ "$(git rev-parse HEAD)" = "$target" ]
}

@test "restore --undo on dirty tree + -y -> proceeds (mixed preserves)" {
  hug h back 1 --force
  target=$(git rev-parse HEAD@{1})
  echo "edit" >> feature1.txt              # tracked, unstaged
  run hug h restore "$target" --undo -y
  assert_success
  [ "$(git rev-parse HEAD)" = "$target" ]
}

@test "restore --rollback on dirty tree + -y -> proceeds (keep preserves)" {
  hug h back 1 --force
  target=$(git rev-parse HEAD@{1})
  echo "edit" >> feature1.txt              # tracked, unstaged
  run hug h restore "$target" --rollback -y
  assert_success
  [ "$(git rev-parse HEAD)" = "$target" ]
}

# -----------------------------------------------------------------------------
# Error-case: missing op, missing target, unknown op flag
# -----------------------------------------------------------------------------

@test "restore: missing op flag -> non-zero exit" {
  run hug h restore "$(git rev-parse HEAD)" -y
  assert_failure
}

@test "restore: missing target -> non-zero exit" {
  run hug h restore --back -y
  assert_failure
}

@test "restore: unknown op flag -> error_usage exit 2" {
  run hug h restore "$(git rev-parse HEAD)" --bogus -y
  assert_failure
  [ "$status" -eq 2 ]
}
