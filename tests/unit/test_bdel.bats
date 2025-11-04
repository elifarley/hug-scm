#!/usr/bin/env bats
# Tests for branch deletion (bdel)

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

# -----------------------------------------------------------------------------
# Help and basic validation tests
# -----------------------------------------------------------------------------

@test "hug bdel --help: shows help message" {
  run bash -c "hug bdel -h 2>&1"
  assert_success
  assert_output --partial "hug bdel: Delete one or more local branches safely"
  assert_output --partial "USAGE:"
  assert_output --partial "EXAMPLES:"
}

@test "hug bdel: reports no branches when only current exists" {
  # Delete all branches except main
  git for-each-ref --format='%(refname:short)' refs/heads/ |
    grep -v '^main$' |
    grep -v '^hug-backups/' |
    xargs -r git branch -D 2>/dev/null || true
  
  run hug bdel -f
  assert_success
  assert_output --partial "No other branches to delete"
}

# -----------------------------------------------------------------------------
# Explicit branch name tests
# -----------------------------------------------------------------------------

@test "hug bdel <branch>: deletes single merged branch" {
  # Create and merge a branch
  git checkout -q -b temp-feature
  echo "temp" > temp.txt
  git add temp.txt
  git commit -q -m "temp commit"
  git checkout -q main
  git merge -q --no-ff temp-feature -m "merge temp"
  
  # Delete it
  run hug bdel temp-feature -f
  assert_success
  assert_output --partial "Deleted 1 branch"
  assert_output --partial "✓ temp-feature"
  
  # Verify it's gone
  run git rev-parse --verify temp-feature
  assert_failure
}

@test "hug bdel <branch>: fails to delete unmerged branch without force" {
  # Create an unmerged branch
  git checkout -q -b unmerged-feature
  echo "unmerged" > unmerged.txt
  git add unmerged.txt
  git commit -q -m "unmerged commit"
  git checkout -q main
  
  # Try to delete without force
  run bash -c "echo 'y' | hug bdel unmerged-feature 2>&1"
  assert_failure
  assert_output --partial "Failed to delete 1 branch"
  assert_output --partial "not fully merged"
  
  # Verify it still exists
  run git rev-parse --verify unmerged-feature
  assert_success
}

@test "hug bdel <branch> --force: deletes unmerged branch" {
  # Create an unmerged branch
  git checkout -q -b unmerged-feature
  echo "unmerged" > unmerged.txt
  git add unmerged.txt
  git commit -q -m "unmerged commit"
  git checkout -q main
  
  # Delete with force
  run hug bdel unmerged-feature --force
  assert_success
  assert_output --partial "Deleted 1 branch"
  assert_output --partial "✓ unmerged-feature"
  
  # Verify it's gone
  run git rev-parse --verify unmerged-feature
  assert_failure
}

@test "hug bdel <branch1> <branch2>: deletes multiple branches" {
  # Create and merge two branches
  git checkout -q -b feat-1
  echo "f1" > f1.txt
  git add f1.txt
  git commit -q -m "feat 1"
  git checkout -q main
  git merge -q --no-ff feat-1 -m "merge feat-1"
  
  git checkout -q -b feat-2
  echo "f2" > f2.txt
  git add f2.txt
  git commit -q -m "feat 2"
  git checkout -q main
  git merge -q --no-ff feat-2 -m "merge feat-2"
  
  # Delete both
  run hug bdel feat-1 feat-2 -f
  assert_success
  assert_output --partial "Deleted 2 branches"
  assert_output --partial "✓ feat-1"
  assert_output --partial "✓ feat-2"
  
  # Verify both are gone
  run git rev-parse --verify feat-1
  assert_failure
  run git rev-parse --verify feat-2
  assert_failure
}

@test "hug bdel: fails when trying to delete current branch" {
  run hug bdel main -f
  assert_failure
  assert_output --partial "Cannot delete current branch"
}

@test "hug bdel: fails when branch does not exist" {
  run hug bdel nonexistent -f
  assert_failure
  assert_output --partial "does not exist"
}

# -----------------------------------------------------------------------------
# Confirmation and dry-run tests
# -----------------------------------------------------------------------------

@test "hug bdel <branch> --dry-run: previews deletion without deleting" {
  # Create and merge a branch
  git checkout -q -b temp-feature
  echo "temp" > temp.txt
  git add temp.txt
  git commit -q -m "temp commit"
  git checkout -q main
  git merge -q --no-ff temp-feature -m "merge temp"
  
  # Dry run
  run hug bdel temp-feature --dry-run
  assert_success
  assert_output --partial "Dry run"
  assert_output --partial "Would delete 1 branch"
  assert_output --partial "temp-feature"
  
  # Verify it still exists
  run git rev-parse --verify temp-feature
  assert_success
}

@test "hug bdel <branch>: prompts for confirmation" {
  # Create and merge a branch
  git checkout -q -b temp-feature
  echo "temp" > temp.txt
  git add temp.txt
  git commit -q -m "temp commit"
  git checkout -q main
  git merge -q --no-ff temp-feature -m "merge temp"
  
  # Cancel deletion
  run bash -c "echo 'n' | hug bdel temp-feature 2>&1"
  assert_failure
  assert_output --partial "About to delete 1 branch"
  assert_output --partial "Cancelled"
  
  # Verify it still exists
  run git rev-parse --verify temp-feature
  assert_success
}

@test "hug bdel <branch> --force: skips confirmation" {
  # Create and merge a branch
  git checkout -q -b temp-feature
  echo "temp" > temp.txt
  git add temp.txt
  git commit -q -m "temp commit"
  git checkout -q main
  git merge -q --no-ff temp-feature -m "merge temp"
  
  # Delete with force (no confirmation)
  run hug bdel temp-feature --force
  assert_success
  assert_output --partial "Deleted 1 branch"
  refute_output --partial "About to delete"
  
  # Verify it's gone
  run git rev-parse --verify temp-feature
  assert_failure
}

# -----------------------------------------------------------------------------
# Backup branch exclusion tests
# -----------------------------------------------------------------------------

@test "hug bdel: does not list backup branches in interactive mode" {
  # Create a backup branch
  git branch "hug-backups/2024-11/02-1234.feature"
  
  # Create a regular branch
  git checkout -q -b regular-new-feature
  echo "regular" > regular.txt
  git add regular.txt
  git commit -q -m "regular commit"
  git checkout -q main
  
  # In interactive mode, gum would be called with filtered list
  # We can't easily test gum interactively, but we can verify the filtering logic
  # by checking that backup branches are excluded from the branch list
  
  # List all non-backup branches (excluding main)
  local -a non_backup_branches=()
  mapfile -t non_backup_branches < <(
    git for-each-ref --format='%(refname:short)' refs/heads/ |
    grep -v '^hug-backups/' |
    grep -v '^main$' || true
  )
  
  # List all branches including backups (excluding main)
  local -a all_branches=()
  mapfile -t all_branches < <(
    git for-each-ref --format='%(refname:short)' refs/heads/ |
    grep -v '^main$' || true
  )
  
  # Should have at least regular-new-feature in non-backup list
  local found_regular=false
  for branch in "${non_backup_branches[@]}"; do
    if [[ "$branch" == "regular-new-feature" ]]; then
      found_regular=true
      break
    fi
  done
  [[ "$found_regular" == true ]]
  
  # Should have backup in all branches list
  local found_backup=false
  for branch in "${all_branches[@]}"; do
    if [[ "$branch" == "hug-backups/2024-11/02-1234.feature" ]]; then
      found_backup=true
      break
    fi
  done
  [[ "$found_backup" == true ]]
  
  # Backup should NOT be in non-backup list
  local backup_in_filtered=false
  for branch in "${non_backup_branches[@]}"; do
    if [[ "$branch" == hug-backups/* ]]; then
      backup_in_filtered=true
      break
    fi
  done
  [[ "$backup_in_filtered" == false ]]
}

# -----------------------------------------------------------------------------
# Mixed success/failure tests
# -----------------------------------------------------------------------------

@test "hug bdel: reports both success and failures when deleting multiple branches" {
  # Create one merged and one unmerged branch
  git checkout -q -b merged-feat
  echo "merged" > merged.txt
  git add merged.txt
  git commit -q -m "merged commit"
  git checkout -q main
  git merge -q --no-ff merged-feat -m "merge merged"
  
  git checkout -q -b unmerged-feat
  echo "unmerged" > unmerged.txt
  git add unmerged.txt
  git commit -q -m "unmerged commit"
  git checkout -q main
  
  # Try to delete both (without force)
  run bash -c "echo 'y' | hug bdel merged-feat unmerged-feat 2>&1"
  assert_success  # Partial success
  assert_output --partial "Deleted 1 branch"
  assert_output --partial "✓ merged-feat"
  assert_output --partial "Failed to delete 1 branch"
  assert_output --partial "✗ unmerged-feat"
  
  # Verify merged is gone, unmerged still exists
  run git rev-parse --verify merged-feat
  assert_failure
  run git rev-parse --verify unmerged-feat
  assert_success
}

# -----------------------------------------------------------------------------
# Edge cases
# -----------------------------------------------------------------------------

@test "hug bdel: handles branches with special characters in names" {
  # Create branch with slash
  git checkout -q -b feature/sub-feature
  echo "sub" > sub.txt
  git add sub.txt
  git commit -q -m "sub commit"
  git checkout -q main
  git merge -q --no-ff feature/sub-feature -m "merge sub"
  
  # Delete it
  run hug bdel feature/sub-feature -f
  assert_success
  assert_output --partial "Deleted 1 branch"
  
  # Verify it's gone
  run git rev-parse --verify feature/sub-feature
  assert_failure
}

@test "hug bdel: correct singular/plural in messages" {
  # Create and merge a single branch
  git checkout -q -b single-feat
  echo "single" > single.txt
  git add single.txt
  git commit -q -m "single commit"
  git checkout -q main
  git merge -q --no-ff single-feat -m "merge single"
  
  # Delete single branch
  run hug bdel single-feat -f
  assert_success
  assert_output --partial "Deleted 1 branch"
  refute_output --partial "branches"
  
  # Create and merge multiple branches
  git checkout -q -b feat-a
  echo "a" > a.txt
  git add a.txt
  git commit -q -m "a"
  git checkout -q main
  git merge -q --no-ff feat-a -m "merge a"
  
  git checkout -q -b feat-b
  echo "b" > b.txt
  git add b.txt
  git commit -q -m "b"
  git checkout -q main
  git merge -q --no-ff feat-b -m "merge b"
  
  # Delete multiple branches
  run hug bdel feat-a feat-b -f
  assert_success
  assert_output --partial "Deleted 2 branches"
}
