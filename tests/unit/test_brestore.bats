#!/usr/bin/env bats
# Tests for branch restore (brestore)

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

# Helper to create a backup branch for testing
# Uses a realistic past date to avoid confusion
create_backup_branch() {
  local branch_name="$1"
  local backup_name="hug-backups/2024-11/02-1234.$branch_name"
  git branch "$backup_name" "$branch_name"
  echo "$backup_name"
}

# -----------------------------------------------------------------------------
# Basic functionality tests
# -----------------------------------------------------------------------------

@test "hug brestore --help: shows help message" {
  run bash -c "hug brestore -h 2>&1"
  assert_success
  assert_output --partial "hug brestore: Restore a branch from a backup"
  assert_output --partial "USAGE:"
  assert_output --partial "EXAMPLES:"
}

@test "hug brestore: fails when no backup branches exist" {
  # Ensure no backup branches exist
  git for-each-ref --format='%(refname:short)' 'refs/heads/hug-backups/**' | while read -r branch; do
    git branch -D "$branch" 2>/dev/null || true
  done
  
  run hug brestore -f
  assert_failure
  assert_output --partial "No backup branches found"
}

@test "hug brestore <backup>: restores backup to original branch name" {
  # Create a backup of feature/branch
  local backup
  backup=$(create_backup_branch "feature/branch")
  
  # Delete the original branch
  git branch -D "feature/branch"
  
  # Verify it's gone
  run git rev-parse --verify "feature/branch"
  assert_failure
  
  # Restore it
  run hug brestore "$backup" -f
  assert_success
  assert_output --partial "Branch restored: 'feature/branch'"
  
  # Verify it's back
  run git rev-parse --verify "feature/branch"
  assert_success
}

@test "hug brestore <backup> <new-name>: restores backup to different branch name" {
  # Create a backup of feature/branch
  local backup
  backup=$(create_backup_branch "feature/branch")
  
  # Restore to a different name
  run hug brestore "$backup" "recovered-branch" -f
  assert_success
  assert_output --partial "Branch restored: 'recovered-branch'"
  
  # Verify the new branch exists
  run git rev-parse --verify "recovered-branch"
  assert_success
  
  # Verify the original is unchanged
  run git rev-parse --verify "feature/branch"
  assert_success
}

@test "hug brestore: warns when target branch already exists" {
  # Create a backup of feature/branch
  local backup
  backup=$(create_backup_branch "feature/branch")
  
  # Try to restore to existing branch without force
  run bash -c "echo 'n' | hug brestore '$backup'"
  assert_failure
  assert_output --partial "Branch 'feature/branch' already exists"
  assert_output --partial "DESTRUCTIVE operation"
}

@test "hug brestore --force: skips confirmation for existing branch" {
  # Create a backup of feature/branch
  local backup
  backup=$(create_backup_branch "feature/branch")
  
  # Get current hash
  local original_hash
  original_hash=$(git rev-parse "feature/branch")
  
  # Modify the original branch
  git checkout -q "feature/branch"
  echo "new content" > new_file.txt
  git add new_file.txt
  git commit -q -m "New commit on feature/branch"
  
  # Verify it changed
  local new_hash
  new_hash=$(git rev-parse "feature/branch")
  assert_not_equal "$original_hash" "$new_hash"
  
  # Restore with force (should replace with backup)
  git checkout -q main
  run hug brestore "$backup" -f
  assert_success
  assert_output --partial "Branch restored: 'feature/branch'"
  
  # Verify it was restored to original
  local restored_hash
  restored_hash=$(git rev-parse "feature/branch")
  assert_equal "$original_hash" "$restored_hash"
}

@test "hug brestore --dry-run: previews restore without making changes" {
  # Create a backup of feature/branch
  local backup
  backup=$(create_backup_branch "feature/branch")
  
  # Delete the original branch
  git branch -D "feature/branch"
  
  # Dry run restore
  run hug brestore "$backup" --dry-run
  assert_success
  assert_output --partial "Dry run: Previewing restore"
  assert_output --partial "does not exist; it would be created"
  
  # Verify branch is still deleted
  run git rev-parse --verify "feature/branch"
  assert_failure
}

@test "hug brestore --dry-run: shows warning for existing branch" {
  # Create a backup of feature/branch
  local backup
  backup=$(create_backup_branch "feature/branch")
  
  # Dry run restore to existing branch
  run hug brestore "$backup" --dry-run
  assert_success
  assert_output --partial "Dry run: Previewing restore"
  assert_output --partial "Branch 'feature/branch' already exists"
  assert_output --partial "would be deleted and recreated"
}

# -----------------------------------------------------------------------------
# Edge cases and error handling
# -----------------------------------------------------------------------------

@test "hug brestore: fails when backup branch doesn't exist" {
  run hug brestore "hug-backups/2025-11/99-9999.nonexistent" -f
  assert_failure
  assert_output --partial "does not exist"
}

@test "hug brestore: handles switching away from target branch" {
  # Create a backup of main
  local backup
  backup=$(create_backup_branch "main")
  
  # Make sure we're on main
  git checkout -q main
  
  # Modify main
  echo "new content" > new_main_file.txt
  git add new_main_file.txt
  git commit -q -m "New commit on main"
  
  # Restore main (should switch away, restore, and switch back)
  run hug brestore "$backup" -f
  assert_success
  assert_output --partial "Switching away from 'main'"
  assert_output --partial "Branch restored: 'main'"
  assert_output --partial "Switched back to 'main'"
  
  # Verify we're back on main
  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  assert_equal "$current_branch" "main"
}

@test "hug brestore: preserves backup branch after restoration" {
  # Create a backup of feature/branch
  local backup
  backup=$(create_backup_branch "feature/branch")
  
  # Delete the original
  git branch -D "feature/branch"
  
  # Restore
  run bash -c "hug brestore '$backup' -f 2>&1"
  assert_success
  
  # Verify backup still exists
  run git rev-parse --verify "$backup"
  assert_success
  
  # Verify output mentions backup is still available
  run bash -c "hug brestore '$backup' -f 2>&1"
  assert_success
  assert_output --partial "Backup branch '$backup' is still available"
}

@test "hug brestore: extracts original name from backup branch correctly" {
  # Test various backup name formats
  git branch "hug-backups/2024-11/02-1234.simple"
  git branch "hug-backups/2024-11/02-1234.feature/complex"
  git branch "hug-backups/2024-11/02-1234.feat-123"
  
  # Restore simple name
  run hug brestore "hug-backups/2024-11/02-1234.simple" -f --dry-run
  assert_success
  assert_output --partial "to 'simple'"
  
  # Restore complex name with slash
  run hug brestore "hug-backups/2024-11/02-1234.feature/complex" -f --dry-run
  assert_success
  assert_output --partial "to 'feature/complex'"
  
  # Restore name with dash
  run hug brestore "hug-backups/2024-11/02-1234.feat-123" -f --dry-run
  assert_success
  assert_output --partial "to 'feat-123'"
}

@test "hug brestore: fails with informative message for malformed backup name" {
  # Create a backup with non-standard name (missing the timestamp part)
  git branch "hug-backups/weird-name"
  
  run hug brestore "hug-backups/weird-name" -f
  assert_failure
  assert_output --partial "Could not extract original branch name"
  assert_output --partial "Please specify target branch explicitly"
}

@test "hug brestore <malformed-backup> <target>: succeeds with explicit target name" {
  # Create a backup with non-standard name
  git branch "hug-backups/weird-name"
  
  # Should work when target is explicit
  run hug brestore "hug-backups/weird-name" "explicit-target" -f
  assert_success
  assert_output --partial "Branch restored: 'explicit-target'"
  
  # Verify branch exists
  run git rev-parse --verify "explicit-target"
  assert_success
}

# -----------------------------------------------------------------------------
# Interactive menu tests
# -----------------------------------------------------------------------------

@test "hug brestore: shows interactive menu when no arguments given" {
  # Create multiple backups
  create_backup_branch "main"
  create_backup_branch "feature/branch"
  
  # Test that menu is shown (we'll cancel it)
  run bash -c "echo '' | hug brestore 2>&1"
  assert_failure  # Cancelled by empty input
  assert_output --partial "Select a backup branch to restore"
  assert_output --partial "2024-11/02-1234.main"
  assert_output --partial "2024-11/02-1234.feature/branch"
}

@test "hug brestore: interactive menu selection works" {
  # Create a backup
  local backup
  backup=$(create_backup_branch "feature/branch")
  
  # Delete original
  git branch -D "feature/branch"
  
  # Select option 1 from menu and confirm
  run bash -c "echo '1' | hug brestore -f 2>&1"
  assert_success
  assert_output --partial "Branch restored: 'feature/branch'"
  
  # Verify restoration
  run git rev-parse --verify "feature/branch"
  assert_success
}

@test "hug brestore: accepts short form without 'hug-backups/' prefix" {
  # Create a backup of feature/branch
  local backup
  backup=$(create_backup_branch "feature/branch")
  
  # Extract the short form (without hug-backups/ prefix)
  local short_form
  short_form="${backup#hug-backups/}"
  
  # Delete original
  git branch -D "feature/branch"
  
  # Restore using short form
  run hug brestore "$short_form" -f
  assert_success
  assert_output --partial "Branch restored: 'feature/branch'"
  
  # Verify restoration
  run git rev-parse --verify "feature/branch"
  assert_success
}

@test "hug brestore: short form works with --dry-run" {
  # Create a backup of feature/branch
  local backup
  backup=$(create_backup_branch "feature/branch")
  
  # Extract the short form
  local short_form
  short_form="${backup#hug-backups/}"
  
  # Dry run with short form
  run hug brestore "$short_form" --dry-run
  assert_success
  assert_output --partial "Dry run: Previewing restore"
  assert_output --partial "hug-backups/"
}

@test "hug brestore: short form works with custom target name" {
  # Create a backup
  local backup
  backup=$(create_backup_branch "feature/branch")
  
  # Extract the short form
  local short_form
  short_form="${backup#hug-backups/}"
  
  # Restore to different name using short form
  run hug brestore "$short_form" "recovered-branch" -f
  assert_success
  assert_output --partial "Branch restored: 'recovered-branch'"
  
  # Verify the new branch exists
  run git rev-parse --verify "recovered-branch"
  assert_success
}

# -----------------------------------------------------------------------------
# Gum integration tests (for 10+ backup branches)
# -----------------------------------------------------------------------------

@test "hug brestore: uses numbered list for fewer than 10 branches" {
  # Create 9 backup branches
  for i in {1..9}; do
    git branch "feature-$i"
    create_backup_branch "feature-$i" > /dev/null
  done
  
  # Test that numbered list is shown (even if gum is available)
  run bash -c 'echo "" | timeout 5 hug brestore 2>&1 || true'
  assert_output --partial "Select a backup branch to restore"
  assert_output --partial "1)"
  assert_output --partial "9)"
  assert_output --partial "Enter choice"
}
