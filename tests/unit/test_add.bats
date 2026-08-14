#!/usr/bin/env bats

# Tests for hug a post-stage index summary (Task 4, #207 prevention).
#
# WHY: The #207 root cause was index-state blindness — an agent running
# 'hug a file.txt' after a soft-reset had no signal the index already
# contained N other files. These tests verify the PREVENTION counterpart
# to hug c's RECOVERY preview (Task 2): a one-line summary printed by
# hug a AFTER staging, showing newly-staged count + cumulative total.

load '../test_helper'

@test "hug a: prints post-stage index summary" {
  cd "$(create_test_repo)" || exit 1
  echo "content" > new_file.txt
  run hug a new_file.txt
  assert_success
  assert_output --partial "Staged 1 file."
  assert_output --partial "Index now has 1 file(s) staged total."
}

@test "hug a: summary reflects cumulative index state" {
  cd "$(create_test_repo)" || exit 1
  # Pre-stage one file (quiet to suppress its summary)
  echo "first" > a.txt
  HUG_QUIET=1 hug a a.txt
  # Now stage a second — total should be 2
  echo "second" > b.txt
  run hug a b.txt
  assert_success
  assert_output --partial "Staged 1 file."
  assert_output --partial "Index now has 2 file(s) staged total."
}

@test "hug a: with no args, counts all newly-staged modifications" {
  cd "$(create_test_repo_with_history)" || exit 1
  # Modify the existing tracked README.md to create an unstaged change
  echo "mod1" >> README.md
  # Run hug a (no args) — stages all tracked modifications
  run hug a
  assert_success
  # Should report at least 1 newly-staged file
  assert_output --partial "Staged"
  assert_output --partial "file(s) staged total."
}

@test "hug a: --quiet suppresses the index summary" {
  cd "$(create_test_repo)" || exit 1
  echo "content" > quiet_file.txt
  run hug a quiet_file.txt --quiet
  assert_success
  refute_output --partial "Staged"
  refute_output --partial "file(s) staged total."
}

@test "hug a: empty stage still prints summary" {
  cd "$(create_test_repo)" || exit 1
  # create_test_repo has README.md committed but no pending changes.
  # hug a (no args) with nothing modified stages 0 tracked modifications.
  run hug a
  assert_success
  assert_output --partial "Staged 0 files."
}
