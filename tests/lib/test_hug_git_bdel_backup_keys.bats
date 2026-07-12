#!/usr/bin/env bats
# Lib tests for git-bdel-backup's normalize_backup_key / is_older_than_pattern.
# Pins the widened timestamp parsing introduced alongside hug-git-backup's
# new DD-HHMM[SS[-N]] naming (see test_hug_git_backup.bats).

load '../test_helper'

# Path to the git-bdel-backup script (resolved at load time, not via sourcing).
BDScript="${HUG_HOME:-$(hug rev-parse --hug-home 2>/dev/null)}/git-config/bin/git-bdel-backup"

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
  # SAFE EXTRACTION: git-bdel-backup is a script (executes at the bottom),
  # NOT a library. Sourcing it would run hug_bdel_backup and possibly exit
  # the BATS shell. Extract ONLY the two pure helper functions (eng-review
  # Codex #4). If the script ever grows a `BASH_SOURCE[0] == "$0"` main
  # guard, this can switch to plain sourcing.
  if [[ -f "$BDScript" ]]; then
    eval "$(sed -n '/^normalize_backup_key()/,/^}/p; /^is_older_than_pattern()/,/^}/p' "$BDScript")"
  fi
  # Verify extraction worked; skip the file gracefully if not.
  if ! type normalize_backup_key >/dev/null 2>&1; then
    skip "could not extract normalize_backup_key from $BDScript"
  fi
}

teardown() {
  cleanup_test_repo
}

@test "normalize_backup_key: parses legacy DD-HHMM form (eng-review Codex #2 — must not break)" {
  run normalize_backup_key "hug-backups/2024-11/02-1234.feature"
  assert_success
  assert_output "2024-11/02-1234"
}

@test "normalize_backup_key: maps DD-HHMMSS to minute precision" {
  run normalize_backup_key "hug-backups/2024-11/02-123456.feature"
  assert_success
  assert_output "2024-11/02-1234"
}

@test "normalize_backup_key: maps DD-HHMMSS-N to minute precision" {
  run normalize_backup_key "hug-backups/2024-11/02-123456-7.feature"
  assert_success
  assert_output "2024-11/02-1234"
}

@test "normalize_backup_key: non-matching input passes through unchanged" {
  run normalize_backup_key "some-other-branch"
  assert_success
  assert_output "some-other-branch"
}

@test "is_older_than_pattern: seconds-precision backup AT threshold minute IS older-or-equal (eng-review Codex #3)" {
  # Contract: a backup at 10:06:37 normalizes to minute 10:06. The existing
  # is_older_than_pattern uses `<=` (line 205 of git-bdel-backup), so a backup
  # at the threshold minute IS considered "older than or equal" — same as a
  # minute-precision backup at 10:06 would be against threshold 10:06. The
  # function returns 0 (true) in that case.
  run is_older_than_pattern "hug-backups/2024-11/03-100637.x" "2024-11/03-1006"
  assert_success
}

@test "is_older_than_pattern: minute-precision backup older than later threshold" {
  # Backup at 10:06 IS older than threshold 10:07.
  run is_older_than_pattern "hug-backups/2024-11/03-1006.x" "2024-11/03-1007"
  assert_success
}

@test "is_older_than_pattern: backup after threshold is NOT older" {
  # Backup at 10:08 is NOT older than threshold 10:07.
  run is_older_than_pattern "hug-backups/2024-11/03-1008.x" "2024-11/03-1007"
  [[ "$status" -ne 0 ]]
}
