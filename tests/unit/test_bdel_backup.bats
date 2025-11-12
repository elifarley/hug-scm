#!/usr/bin/env bats
# Tests for backup branch deletion (bdel-backup)

# Load test helpers
load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_branches)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

# Helper to create backup branches for testing
create_test_backup() {
  local date_path="$1"
  local branch_name="$2"
  local backup_name="hug-backups/${date_path}.${branch_name}"
  git branch "$backup_name" HEAD
  echo "$backup_name"
}

# -----------------------------------------------------------------------------
# Help and basic validation tests
# -----------------------------------------------------------------------------

@test "hug bdel-backup --help: shows help message" {
  run bash -c "hug bdel-backup -h 2>&1"
  assert_success
  assert_output --partial "hug bdel-backup: Delete backup branches"
  assert_output --partial "USAGE:"
  assert_output --partial "EXAMPLES:"
  assert_output --partial "--keep"
  assert_output --partial "--delete-older-than"
}

@test "hug bdel-backup: reports no backups when none exist" {
  # Ensure no backup branches exist
  git for-each-ref --format='%(refname:short)' 'refs/heads/hug-backups/**' |
    xargs -r git branch -D 2>/dev/null || true
  
  run hug bdel-backup -f
  assert_success
  assert_output --partial "No backup branches found"
}

# -----------------------------------------------------------------------------
# Explicit branch name tests
# -----------------------------------------------------------------------------

@test "hug bdel-backup <backup>: deletes single backup branch with full name" {
  # Create a backup
  local backup
  backup=$(create_test_backup "2024-11/02-1234" "feature")
  
  # Delete it
  run hug bdel-backup "$backup" -f
  assert_success
  assert_output --partial "Deleted 1 backup branch"
  assert_output --partial "2024-11/02-1234.feature"
  
  # Verify it's gone
  run git rev-parse --verify "$backup"
  assert_failure
}

@test "hug bdel-backup <backup>: deletes single backup branch with short form" {
  # Create a backup
  local backup
  backup=$(create_test_backup "2024-11/02-1234" "feature")
  
  # Delete using short form
  run hug bdel-backup "2024-11/02-1234.feature" -f
  assert_success
  assert_output --partial "Deleted 1 backup branch"
  
  # Verify it's gone
  run git rev-parse --verify "$backup"
  assert_failure
}

@test "hug bdel-backup: deletes multiple backup branches" {
  # Create multiple backups
  local backup1
  backup1=$(create_test_backup "2024-11/01-1200" "feat-1")
  local backup2
  backup2=$(create_test_backup "2024-11/02-1300" "feat-2")
  
  # Delete both
  run hug bdel-backup "$backup1" "$backup2" -f
  assert_success
  assert_output --partial "Deleted 2 backup branches"
  
  # Verify both are gone
  run git rev-parse --verify "$backup1"
  assert_failure
  run git rev-parse --verify "$backup2"
  assert_failure
}

@test "hug bdel-backup: fails when backup does not exist" {
  run hug bdel-backup "2025-99/99-9999.nonexistent" -f
  assert_failure
  assert_output --partial "Invalid commitish"
}

# -----------------------------------------------------------------------------
# --keep N flag tests
# -----------------------------------------------------------------------------

@test "hug bdel-backup --keep N: keeps N most recent backups" {
  # Create 5 backups with different dates
  create_test_backup "2024-10/01-1000" "old1"
  create_test_backup "2024-10/15-1000" "old2"
  create_test_backup "2024-11/01-1000" "mid1"
  create_test_backup "2024-11/15-1000" "mid2"
  create_test_backup "2024-12/01-1000" "recent"
  
  # Keep 2 most recent
  run hug bdel-backup --keep 2 -f
  assert_success
  assert_output --partial "Deleted 3 backup branches"
  
  # Verify recent ones still exist
  run git rev-parse --verify "hug-backups/2024-11/15-1000.mid2"
  assert_success
  run git rev-parse --verify "hug-backups/2024-12/01-1000.recent"
  assert_success
  
  # Verify old ones are gone
  run git rev-parse --verify "hug-backups/2024-10/01-1000.old1"
  assert_failure
  run git rev-parse --verify "hug-backups/2024-10/15-1000.old2"
  assert_failure
  run git rev-parse --verify "hug-backups/2024-11/01-1000.mid1"
  assert_failure
}

@test "hug bdel-backup --keep N: does nothing when N >= total backups" {
  # Create 3 backups
  create_test_backup "2024-11/01-1000" "b1"
  create_test_backup "2024-11/02-1000" "b2"
  create_test_backup "2024-11/03-1000" "b3"
  
  # Keep 5 (more than exist)
  run hug bdel-backup --keep 5 -f
  assert_success
  assert_output --partial "Nothing to delete"
  
  # Verify all still exist
  run git rev-parse --verify "hug-backups/2024-11/01-1000.b1"
  assert_success
  run git rev-parse --verify "hug-backups/2024-11/02-1000.b2"
  assert_success
  run git rev-parse --verify "hug-backups/2024-11/03-1000.b3"
  assert_success
}

@test "hug bdel-backup --keep: fails without number argument" {
  run hug bdel-backup --keep
  assert_failure
  assert_output --partial "requires an argument"
}

@test "hug bdel-backup --keep: fails with invalid number" {
  run hug bdel-backup --keep abc
  assert_failure
  assert_output --partial "requires a positive integer"
}

# -----------------------------------------------------------------------------
# --delete-older-than PATTERN flag tests
# -----------------------------------------------------------------------------

@test "hug bdel-backup --delete-older-than YYYY: deletes by year" {
  # Create backups across years
  create_test_backup "2023-12/31-2359" "old2023"
  create_test_backup "2024-01/01-0000" "new2024"
  create_test_backup "2024-12/31-2359" "end2024"
  
  # Delete 2023 and older
  run hug bdel-backup --delete-older-than 2023 -f
  assert_success
  assert_output --partial "Deleted 1 backup branch"
  
  # Verify 2023 is gone
  run git rev-parse --verify "hug-backups/2023-12/31-2359.old2023"
  assert_failure
  
  # Verify 2024 still exists
  run git rev-parse --verify "hug-backups/2024-01/01-0000.new2024"
  assert_success
  run git rev-parse --verify "hug-backups/2024-12/31-2359.end2024"
  assert_success
}

@test "hug bdel-backup --delete-older-than YYYY-MM: deletes by month" {
  # Create backups across months
  create_test_backup "2024-10/15-1200" "oct"
  create_test_backup "2024-11/01-0000" "nov-early"
  create_test_backup "2024-11/30-2359" "nov-late"
  create_test_backup "2024-12/01-0000" "dec"
  
  # Delete Nov 2024 and older
  run hug bdel-backup --delete-older-than 2024-11 -f
  assert_success
  assert_output --partial "Deleted 3 backup branches"
  
  # Verify Oct and Nov are gone
  run git rev-parse --verify "hug-backups/2024-10/15-1200.oct"
  assert_failure
  run git rev-parse --verify "hug-backups/2024-11/01-0000.nov-early"
  assert_failure
  run git rev-parse --verify "hug-backups/2024-11/30-2359.nov-late"
  assert_failure
  
  # Verify Dec still exists
  run git rev-parse --verify "hug-backups/2024-12/01-0000.dec"
  assert_success
}

@test "hug bdel-backup --delete-older-than YYYY-MM/DD: deletes by day" {
  # Create backups across days
  create_test_backup "2024-11/02-1200" "day2"
  create_test_backup "2024-11/03-0000" "day3-start"
  create_test_backup "2024-11/03-2359" "day3-end"
  create_test_backup "2024-11/04-0000" "day4"
  
  # Delete Nov 3, 2024 and older
  run hug bdel-backup --delete-older-than 2024-11/03 -f
  assert_success
  assert_output --partial "Deleted 3 backup branches"
  
  # Verify day 2 and 3 are gone
  run git rev-parse --verify "hug-backups/2024-11/02-1200.day2"
  assert_failure
  run git rev-parse --verify "hug-backups/2024-11/03-0000.day3-start"
  assert_failure
  run git rev-parse --verify "hug-backups/2024-11/03-2359.day3-end"
  assert_failure
  
  # Verify day 4 still exists
  run git rev-parse --verify "hug-backups/2024-11/04-0000.day4"
  assert_success
}

@test "hug bdel-backup --delete-older-than YYYY-MM/DD-HH: deletes by hour" {
  # Create backups across hours
  create_test_backup "2024-11/03-1300" "hour13"
  create_test_backup "2024-11/03-1400" "hour14-start"
  create_test_backup "2024-11/03-1459" "hour14-end"
  create_test_backup "2024-11/03-1500" "hour15"
  
  # Delete Nov 3, 2024 14:xx and older
  run hug bdel-backup --delete-older-than 2024-11/03-14 -f
  assert_success
  assert_output --partial "Deleted 3 backup branches"
  
  # Verify hours 13 and 14 are gone
  run git rev-parse --verify "hug-backups/2024-11/03-1300.hour13"
  assert_failure
  run git rev-parse --verify "hug-backups/2024-11/03-1400.hour14-start"
  assert_failure
  run git rev-parse --verify "hug-backups/2024-11/03-1459.hour14-end"
  assert_failure
  
  # Verify hour 15 still exists
  run git rev-parse --verify "hug-backups/2024-11/03-1500.hour15"
  assert_success
}

@test "hug bdel-backup --delete-older-than YYYY-MM/DD-HHMM: deletes by minute" {
  # Create backups across minutes
  create_test_backup "2024-11/03-1413" "min13"
  create_test_backup "2024-11/03-1414" "min14"
  create_test_backup "2024-11/03-1415" "min15"
  create_test_backup "2024-11/03-1416" "min16"
  
  # Delete Nov 3, 2024 14:15 and older
  run hug bdel-backup --delete-older-than 2024-11/03-1415 -f
  assert_success
  assert_output --partial "Deleted 3 backup branches"
  
  # Verify minutes 13, 14, 15 are gone
  run git rev-parse --verify "hug-backups/2024-11/03-1413.min13"
  assert_failure
  run git rev-parse --verify "hug-backups/2024-11/03-1414.min14"
  assert_failure
  run git rev-parse --verify "hug-backups/2024-11/03-1415.min15"
  assert_failure
  
  # Verify minute 16 still exists
  run git rev-parse --verify "hug-backups/2024-11/03-1416.min16"
  assert_success
}

@test "hug bdel-backup --delete-older-than: validates pattern format" {
  run hug bdel-backup --delete-older-than "invalid"
  assert_failure
  assert_output --partial "Invalid pattern"
  assert_output --partial "Valid patterns:"
}

@test "hug bdel-backup --delete-older-than: fails without pattern argument" {
  run hug bdel-backup --delete-older-than
  assert_failure
  assert_output --partial "requires an argument"
}

# -----------------------------------------------------------------------------
# Combined filters tests
# -----------------------------------------------------------------------------

@test "hug bdel-backup: combines --delete-older-than and --keep" {
  # Create backups across time
  create_test_backup "2023-12/31-2359" "old-2023"
  create_test_backup "2024-01/01-0000" "2024-jan"
  create_test_backup "2024-06/01-0000" "2024-jun"
  create_test_backup "2024-11/01-0000" "2024-nov"
  create_test_backup "2024-12/01-0000" "2024-dec"
  
  # Delete 2024-06 and older, then keep 2 most recent of remaining
  run hug bdel-backup --delete-older-than 2024-06 --keep 2 -f
  assert_success
  # Should delete: 2023, 2024-jan, 2024-jun (3 from date filter)
  # Then keep 2 most recent of [2024-nov, 2024-dec]: keep both, delete nothing more
  assert_output --partial "Deleted 3 backup branches"
  
  # Verify old ones are gone
  run git rev-parse --verify "hug-backups/2023-12/31-2359.old-2023"
  assert_failure
  run git rev-parse --verify "hug-backups/2024-01/01-0000.2024-jan"
  assert_failure
  run git rev-parse --verify "hug-backups/2024-06/01-0000.2024-jun"
  assert_failure
  
  # Verify recent ones exist
  run git rev-parse --verify "hug-backups/2024-11/01-0000.2024-nov"
  assert_success
  run git rev-parse --verify "hug-backups/2024-12/01-0000.2024-dec"
  assert_success
}

# -----------------------------------------------------------------------------
# Confirmation and dry-run tests
# -----------------------------------------------------------------------------

@test "hug bdel-backup --dry-run: previews deletion without deleting" {
  # Create a backup
  local backup
  backup=$(create_test_backup "2024-11/02-1234" "feature")
  
  # Dry run
  run hug bdel-backup "$backup" --dry-run
  assert_success
  assert_output --partial "Dry run"
  assert_output --partial "Would delete 1 backup branch"
  assert_output --partial "2024-11/02-1234.feature"
  
  # Verify it still exists
  run git rev-parse --verify "$backup"
  assert_success
}

@test "hug bdel-backup: prompts for confirmation" {
  # Create a backup
  local backup
  backup=$(create_test_backup "2024-11/02-1234" "feature")
  
  # Cancel deletion
  run bash -c "echo 'n' | hug bdel-backup '$backup' 2>&1"
  assert_failure
  assert_output --partial "About to delete 1 backup branch"
  assert_output --partial "Cancelled"
  
  # Verify it still exists
  run git rev-parse --verify "$backup"
  assert_success
}

@test "hug bdel-backup --force: skips confirmation" {
  # Create a backup
  local backup
  backup=$(create_test_backup "2024-11/02-1234" "feature")
  
  # Delete with force (no confirmation)
  run hug bdel-backup "$backup" --force
  assert_success
  assert_output --partial "Deleted 1 backup branch"
  refute_output --partial "About to delete"
  
  # Verify it's gone
  run git rev-parse --verify "$backup"
  assert_failure
}

# -----------------------------------------------------------------------------
# Edge cases
# -----------------------------------------------------------------------------

@test "hug bdel-backup: handles backup branches with slashes in original name" {
  # Create backup of a branch with slash
  local backup
  backup=$(create_test_backup "2024-11/02-1234" "feature/sub-feature")
  
  # Delete it
  run hug bdel-backup "$backup" -f
  assert_success
  assert_output --partial "Deleted 1 backup branch"
  
  # Verify it's gone
  run git rev-parse --verify "$backup"
  assert_failure
}

@test "hug bdel-backup: correct singular/plural in messages" {
  # Single backup
  local backup1
  backup1=$(create_test_backup "2024-11/01-1200" "single")
  
  run hug bdel-backup "$backup1" -f
  assert_success
  assert_output --partial "Deleted 1 backup branch"
  refute_output --partial "branches"
  
  # Multiple backups
  local backup2 backup3
  backup2=$(create_test_backup "2024-11/02-1200" "multi1")
  backup3=$(create_test_backup "2024-11/03-1200" "multi2")
  
  run hug bdel-backup "$backup2" "$backup3" -f
  assert_success
  assert_output --partial "Deleted 2 backup branches"
}

@test "hug bdel-backup --keep 0: deletes all backup branches" {
  # Create backups
  create_test_backup "2024-11/01-1000" "b1"
  create_test_backup "2024-11/02-1000" "b2"
  create_test_backup "2024-11/03-1000" "b3"
  
  # Keep 0 (delete all)
  run hug bdel-backup --keep 0 -f
  assert_success
  assert_output --partial "Deleted 3 backup branches"
  
  # Verify all are gone
  run git rev-parse --verify "hug-backups/2024-11/01-1000.b1"
  assert_failure
  run git rev-parse --verify "hug-backups/2024-11/02-1000.b2"
  assert_failure
  run git rev-parse --verify "hug-backups/2024-11/03-1000.b3"
  assert_failure
}
