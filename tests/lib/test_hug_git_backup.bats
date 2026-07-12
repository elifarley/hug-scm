#!/usr/bin/env bats
# Lib tests for hug-git-backup: resolve_backup_name, create_backup_branch,
# extract_original_name. Pins the widened naming format and the
# HUG_FAKE_CLOCK-deterministic clock path introduced for #205 sub-bug 2.

load '../test_helper'
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-git-backup'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
  # Pin the clock so names are byte-for-byte reproducible. 946684800 =
  # 2000-01-01 00:00:00 UTC. Tests in test_bc.bats use the same value.
  export HUG_FAKE_CLOCK=946684800
}

teardown() {
  cleanup_test_repo
}

# -----------------------------------------------------------------------------
# resolve_backup_name — pure read-only preview
# -----------------------------------------------------------------------------

@test "resolve_backup_name: deterministic under HUG_FAKE_CLOCK (UTC)" {
  run resolve_backup_name HEAD main
  assert_success
  assert_output "hug-backups/2000-01/01-0000.main"
}

@test "resolve_backup_name: performs no git writes" {
  local before
  before=$(get_backup_branches | wc -l)
  resolve_backup_name HEAD main >/dev/null
  local after
  after=$(get_backup_branches | wc -l)
  [[ "$before" -eq "$after" ]]
}

@test "resolve_backup_name: widens to seconds on same-minute collision" {
  # Pre-create the minute-precision name so resolve must widen.
  git branch "hug-backups/2000-01/01-0000.main" HEAD
  run resolve_backup_name HEAD main
  assert_success
  assert_output "hug-backups/2000-01/01-000000.main"
}

@test "resolve_backup_name: appends -N on same-second collision" {
  git branch "hug-backups/2000-01/01-0000.main" HEAD
  git branch "hug-backups/2000-01/01-000000.main" HEAD
  run resolve_backup_name HEAD main
  assert_success
  assert_output "hug-backups/2000-01/01-000000-1.main"
}

@test "resolve_backup_name: rejects empty args" {
  run resolve_backup_name "" main
  assert_failure
  run resolve_backup_name HEAD ""
  assert_failure
}

@test "resolve_backup_name: year/month boundary — components stay mutually consistent" {
  # Regression for the boundary race closed by capture-once-format-many.
  # Before the fix, three hug_clock_now calls each hit `date` independently;
  # across a year/month/day boundary they could produce an impossible name
  # like "hug-backups/2024-12/01-0000.main" (Dec year-month paired with
  # Jan 1 day-time) or "hug-backups/2025-01/31-2359.main" (Jan year-month
  # paired with Dec 31 day-time). One captured epoch ⇒ all components refer
  # to the same instant, by construction.
  #
  # 1735689599 = 2024-12-31 23:59:59 UTC. All components must be Dec 31.
  HUG_FAKE_CLOCK=1735689599 run resolve_backup_name HEAD main
  assert_success
  assert_output "hug-backups/2024-12/31-2359.main"
}

@test "resolve_backup_name: one second later rolls every component together" {
  # 1735689600 = 2025-01-01 00:00:00 UTC — one second after the test above.
  # Year, month, day, hour, AND minute all roll simultaneously. If the
  # capture-once invariant held, every component flips to Jan 1, 0000.
  HUG_FAKE_CLOCK=1735689600 run resolve_backup_name HEAD main
  assert_success
  assert_output "hug-backups/2025-01/01-0000.main"
}

# -----------------------------------------------------------------------------
# create_backup_branch — real creation, collision-safe
# -----------------------------------------------------------------------------

@test "create_backup_branch: creates and echoes the expected name" {
  run create_backup_branch HEAD main
  assert_success
  assert_output "hug-backups/2000-01/01-0000.main"
  # Branch actually exists.
  git show-ref --verify "refs/heads/hug-backups/2000-01/01-0000.main"
}

@test "create_backup_branch: two calls under the same clock produce distinct names" {
  run create_backup_branch HEAD main
  assert_success
  local first="$output"

  run create_backup_branch HEAD main
  assert_success
  local second="$output"

  [[ "$first" != "$second" ]]
  # Second call should land on the seconds form.
  [[ "$second" == "hug-backups/2000-01/01-000000.main" ]]
  # Both branches exist.
  git show-ref --verify "refs/heads/$first"
  git show-ref --verify "refs/heads/$second"
}

@test "create_backup_branch: rejects empty args" {
  run create_backup_branch "" main
  assert_failure
  run create_backup_branch HEAD ""
  assert_failure
}

# -----------------------------------------------------------------------------
# extract_original_name — widened to all three timestamp forms
# -----------------------------------------------------------------------------

@test "extract_original_name: handles the DD-HHMM form" {
  run extract_original_name "hug-backups/2024-11/02-1234.feature/v2.3"
  assert_success
  assert_output "feature/v2.3"
}

@test "extract_original_name: handles the DD-HHMMSS form" {
  run extract_original_name "hug-backups/2024-11/02-123456.feature/v2.3"
  assert_success
  assert_output "feature/v2.3"
}

@test "extract_original_name: handles the DD-HHMMSS-N form" {
  run extract_original_name "hug-backups/2024-11/02-123456-7.feature/v2.3"
  assert_success
  assert_output "feature/v2.3"
}

@test "extract_original_name: passes through non-matching input unchanged" {
  run extract_original_name "some-other-branch"
  assert_success
  assert_output "some-other-branch"
}
