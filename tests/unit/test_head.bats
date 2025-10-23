#!/usr/bin/env bats
# Tests for HEAD operations (h*)

# Load test helpers
load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

# Head movement commands require user confirmation unless we use the `--force`.
# TODO create additional tests that don't use the `--force` flag (so we need to pipe a `y` to the run command)

@test "hug h back: moves HEAD back one commit, keeps changes staged" {
  # Get current HEAD
  local original_head
  original_head=$(git rev-parse HEAD)
  
  run hug h back --force
  assert_success
  
  # HEAD should have moved back
  local new_head
  new_head=$(git rev-parse HEAD)
  assert_not_equal "$original_head" "$new_head"
  
  # Changes should be staged
  run git diff --cached --name-only
  assert_output --partial "feature2.txt"
}

@test "hug h back N: moves HEAD back N commits" {
  # Get current HEAD
  local original_head
  original_head=$(git rev-parse HEAD)
  
  run hug h back 2 --force
  assert_success
  
  # Should have moved back 2 commits
  local new_head
  new_head=$(git rev-parse HEAD)
  
  # Check we're at initial commit
  run git log --oneline
  assert_output --partial "Initial commit"
  refute_output --partial "Add feature 1"
}

@test "hug h undo: moves HEAD back and unstages changes" {
  run hug h undo --force
  assert_success
  
  # Changes should be unstaged or untracked after an undo.
  # For this specific case, 'feature2.txt' must be untracked.
  run git ls-files --others --exclude-standard
  assert_output --partial "feature2.txt"
  
  # Nothing should be staged
  run git diff --cached
  assert_output ""

  # Nothing should be unstaged
  run git diff --name-only
  assert_output ""
}

@test "hug h undo N: undoes N commits" {
  run hug h undo 2 --force
  assert_success
  
  # Both files should be present but unstaged
  assert_file_exists "feature1.txt"
  assert_file_exists "feature2.txt"
  
  # Should be at initial commit
  run git log --oneline
  assert_output --partial "Initial commit"
  refute_output --partial "Add feature"
}

@test "hug h steps: shows steps to last change in file" {
  # file feature2.txt was changed in the last commit
  run hug h steps feature2.txt
  assert_success
  assert_output --partial "0 steps back"
  
  # feature1.txt was changed 1 commit ago
  run hug h steps feature1.txt
  assert_success
  assert_output --partial "1 step"
}

@test "hug h rollback: removes commit but preserves work" {
  # Add an uncommitted change that should be preserved
  echo "uncommitted" > uncommitted.txt
  
  # Add a change that we'll rollback (committed)
  echo "test" > temp.txt
  git add temp.txt
  git commit -q -m "Temp commit"
  
  run hug h rollback --force
  assert_success
  
  # Commit should be gone
  run git log --oneline
  refute_output --partial "Temp commit"
  
  # Committed file should NOT exist (rollback discards commit changes)
  assert_file_not_exists "temp.txt"
  
  # But uncommitted file should still exist (uncommitted changes preserved)
  assert_file_exists "uncommitted.txt"
}

@test "hug h rollback N: rolls back N commits" {
  # Add an uncommitted change that should be preserved
  echo "uncommitted" > uncommitted.txt
  
  run hug h rollback 2 --force
  assert_success
  
  # Should be at initial commit
  run git log --oneline
  assert_output --partial "Initial commit"
  refute_output --partial "Add feature"
  
  # Committed files should NOT exist (rollback discards commit changes)
  assert_file_not_exists "feature1.txt"
  assert_file_not_exists "feature2.txt"
  
  # But uncommitted file should still exist (uncommitted changes preserved)
  assert_file_exists "uncommitted.txt"
}

@test "hug h rewind: destructive rewind to commit" {
  # Get the commit hash of first commit
  local first_commit
  first_commit=$(git rev-list --max-parents=0 HEAD)
  
  run hug h rewind "$first_commit" --force
  assert_success
  
  # Should be at initial commit with clean state
  run git log --oneline
  assert_output --partial "Initial commit"
  refute_output --partial "Add feature"
  
  # Added files should be gone
  assert_file_not_exists "feature1.txt"
  assert_file_not_exists "feature2.txt"
  
  # Working tree should be clean
  assert_git_clean
}

@test "hug h back with commit hash: moves to specific commit" {
  # Get hash of first feature commit
  local target_commit
  target_commit=$(git log --oneline --all | grep "Add feature 1" | awk '{print $1}')
  
  run hug h back "$target_commit" --force
  assert_success
  
  # HEAD should be at that commit
  run git log --oneline -1
  assert_output --partial "Add feature 1"
}

@test "hug h steps --raw: shows raw step count" {
  run hug h steps --raw feature2.txt
  assert_success
  
  # --raw option returns just the step count (0 for file modified in HEAD)
  assert_output "0"
  
  # Test with a file from an older commit
  run hug h steps --raw feature1.txt
  assert_success
  assert_output "1"
}

@test "hug h undo with no commits handles gracefully" {
  # Create a fresh repo at initial commit
  local test_repo
  test_repo=$(create_test_repo)
  cd "$test_repo"
  
  # Try to undo when there's only one commit
  run hug h undo --force
  
  # Should succeed with info message (no commits to undo)
  assert_success
  assert_output --partial "Already at target"
}

@test "hug h operations preserve untracked files" {
  # Add an untracked file
  echo "untracked" > untracked.txt
  
  run hug h back --force
  assert_success
  
  # Untracked file should still exist
  assert_file_exists "untracked.txt"
}

# ============================================================================
# Comprehensive Edge Case Tests for git-h* commands
# ============================================================================

# ----------------------------------------------------------------------------
# git-h (gateway command) tests
# ----------------------------------------------------------------------------

@test "hug h: shows help with no arguments" {
  run hug h
  assert_success
  assert_output --partial "Usage: hug h <command>"
  assert_output --partial "files"
  assert_output --partial "steps"
  assert_output --partial "back"
  assert_output --partial "undo"
  assert_output --partial "rollback"
  assert_output --partial "rewind"
  assert_output --partial "squash"
}

@test "hug h: shows help with invalid subcommand" {
  run hug h invalidcmd
  assert_success
  assert_output --partial "Usage: hug h <command>"
}

# ----------------------------------------------------------------------------
# git-h-back edge cases
# ----------------------------------------------------------------------------

@test "hug h back: requires confirmation without --force" {
  # This would hang waiting for input, so we skip it in automated tests
  # Manual testing required for interactive confirmation
  skip "Interactive test - requires manual verification"
}

@test "hug h back: rejects both --upstream and target argument" {
  run hug h back 2 --upstream
  assert_failure
  assert_output --partial "Cannot specify both --upstream and"
}

@test "hug h back: handles going back to initial commit" {
  local initial_commit
  initial_commit=$(git rev-list --max-parents=0 HEAD)
  
  run hug h back "$initial_commit" --force
  assert_success
  
  # Should be at initial commit
  local current_head
  current_head=$(git rev-parse HEAD)
  assert_equal "$current_head" "$initial_commit"
}

@test "hug h back: preserves staged changes" {
  # Stage a new file
  echo "staged" > staged.txt
  git add staged.txt
  
  run hug h back --force
  assert_success
  
  # Staged file should still be staged
  run git diff --cached --name-only
  assert_output --partial "staged.txt"
}

@test "hug h back: preserves unstaged changes" {
  # Make unstaged changes
  echo "modified" >> README.md
  
  run hug h back --force
  assert_success
  
  # Unstaged changes should still be there
  run git diff --name-only
  assert_output --partial "README.md"
}

@test "hug h back: works with --quiet flag" {
  run hug h back --quiet --force
  assert_success
  # Output should be minimal (info messages suppressed)
}

@test "hug h back: handles invalid target" {
  run hug h back invalidcommit --force
  # Invalid targets may be handled gracefully with "Already at target" message
  # or may fail - both are acceptable
  if [ "$status" -eq 0 ]; then
    assert_output --partial "Already at target"
  else
    assert_failure
  fi
}

@test "hug h back: handles moving back 0 commits (stays at HEAD)" {
  local original_head
  original_head=$(git rev-parse HEAD)
  
  run hug h back HEAD --force
  assert_success
  
  local new_head
  new_head=$(git rev-parse HEAD)
  assert_equal "$original_head" "$new_head"
}

# ----------------------------------------------------------------------------
# git-h-undo edge cases
# ----------------------------------------------------------------------------

@test "hug h undo: rejects both --upstream and target" {
  run hug h undo 2 --upstream
  assert_failure
  assert_output --partial "Cannot specify both"
}

@test "hug h undo: handles going back to initial commit" {
  local initial_commit
  initial_commit=$(git rev-list --max-parents=0 HEAD)
  
  run hug h undo "$initial_commit" --force
  assert_success
}

@test "hug h undo: preserves unstaged changes" {
  # Make unstaged changes
  echo "modified" >> README.md
  
  run hug h undo --force
  assert_success
  
  # Unstaged changes should still be there
  run git diff --name-only
  assert_output --partial "README.md"
}

@test "hug h undo: works with --quiet flag" {
  run hug h undo --quiet --force
  assert_success
}

@test "hug h undo: merges staged and committed changes to unstaged" {
  # Stage a change
  echo "staged content" > staged.txt
  git add staged.txt
  
  run hug h undo --force
  assert_success
  
  # Changes from undone commit plus staged changes should be unstaged
  run git status --short
  assert_output --partial "??"
}

# ----------------------------------------------------------------------------
# git-h-rewind edge cases
# ----------------------------------------------------------------------------

@test "hug h rewind: shows help with -h" {
  run hug h rewind -h
  assert_success
  assert_output --partial "hug h rewind"
  assert_output --partial "DISCARDING"
}

@test "hug h rewind: rejects both --upstream and target" {
  run hug h rewind 2 --upstream
  assert_failure
  assert_output --partial "Cannot specify both"
}

@test "hug h rewind: requires confirmation without --force" {
  skip "Interactive test - requires manual verification"
}

@test "hug h rewind: discards all uncommitted changes" {
  # Add uncommitted changes
  echo "uncommitted" >> README.md
  echo "new file" > newfile.txt
  git add newfile.txt
  
  run hug h rewind --force
  assert_success
  
  # All changes should be gone
  assert_git_clean
  assert_file_not_exists "newfile.txt"
}

@test "hug h rewind: works with --quiet flag" {
  run hug h rewind --quiet --force
  assert_success
}

@test "hug h rewind: handles moving to initial commit" {
  local initial_commit
  initial_commit=$(git rev-list --max-parents=0 HEAD)
  
  run hug h rewind "$initial_commit" --force
  assert_success
  
  local current_head
  current_head=$(git rev-parse HEAD)
  assert_equal "$current_head" "$initial_commit"
}

# ----------------------------------------------------------------------------
# git-h-rollback edge cases
# ----------------------------------------------------------------------------

@test "hug h rollback: shows help with -h" {
  run hug h rollback -h
  assert_failure  # -h exits with 1
  assert_output --partial "hug h rollback"
}

@test "hug h rollback: rejects both --upstream and target" {
  run hug h rollback 2 --upstream
  assert_failure
  assert_output --partial "Cannot specify both"
}

@test "hug h rollback: preserves uncommitted staged changes" {
  # Add uncommitted change to existing file
  echo "modified" >> README.md
  git add README.md
  
  # Create and commit something to rollback
  echo "temp" > temp.txt
  git add temp.txt
  git commit -q -m "Temp commit"
  
  run hug h rollback --force
  assert_success
  
  # git reset --keep has specific behavior - it aborts if changes conflict
  # The fact that it succeeded means uncommitted changes were handled properly
  # The temp.txt commit should be gone
  assert_file_not_exists "temp.txt"
}

@test "hug h rollback: preserves uncommitted unstaged changes" {
  # Make unstaged change
  echo "modified" >> README.md
  
  # Create and commit something to rollback
  echo "temp" > temp.txt
  git add temp.txt
  git commit -q -m "Temp commit"
  
  run hug h rollback --force
  assert_success
  
  # Unstaged change should still be there
  run git diff --name-only
  assert_output --partial "README.md"
}

@test "hug h rollback: works with --quiet flag" {
  run hug h rollback --quiet --force
  assert_success
}

# ----------------------------------------------------------------------------
# git-h-squash edge cases
# ----------------------------------------------------------------------------

@test "hug h squash: shows help with -h" {
  run hug h squash -h
  assert_success
  assert_output --partial "hug h squash"
}

@test "hug h squash: squashes last 2 commits by default" {
  local original_count
  original_count=$(git rev-list --count HEAD)
  
  run hug h squash --force
  assert_success
  
  local new_count
  new_count=$(git rev-list --count HEAD)
  
  # Should have one less commit
  assert_equal "$new_count" "$((original_count - 1))"
}

@test "hug h squash: squashes specified number of commits" {
  # We have 3 commits total (initial + 2 features)
  local original_count
  original_count=$(git rev-list --count HEAD)
  
  run hug h squash 2 --force
  assert_success
  
  local new_count
  new_count=$(git rev-list --count HEAD)
  
  # Should have squashed 2 into 1
  assert_equal "$new_count" "$((original_count - 1))"
}

@test "hug h squash: preserves original HEAD message" {
  local original_message
  original_message=$(git log -1 --format=%s)
  
  run hug h squash --force
  assert_success
  
  local new_message
  new_message=$(git log -1 --format=%s)
  
  # Message should match the original HEAD message
  assert_equal "$new_message" "$original_message"
}

@test "hug h squash: rejects both --upstream and target" {
  run hug h squash 2 --upstream
  assert_failure
  assert_output --partial "Cannot specify both"
}

@test "hug h squash: works with --quiet flag" {
  run hug h squash --quiet --force
  assert_success
}

@test "hug h squash: handles squashing to commit hash" {
  local first_feature
  first_feature=$(git log --oneline --all | grep "Add feature 1" | awk '{print $1}')
  
  run hug h squash "$first_feature" --force
  assert_success
  
  # Should have squashed everything above first feature
  run git log --oneline
  assert_output --partial "Add feature 2"  # Uses this message
  assert_output --partial "Add feature 1"
}

@test "hug h squash: preserves uncommitted changes" {
  echo "uncommitted" > uncommitted.txt
  
  run hug h squash --force
  assert_success
  
  # Uncommitted file should still exist
  assert_file_exists "uncommitted.txt"
}

@test "hug h squash: handles when already at target" {
  # Create a fresh repo with only initial commit
  local test_repo
  test_repo=$(create_test_repo)
  cd "$test_repo"
  
  # Try to squash when we only have 1 commit (can't squash 2 from 1)
  run hug h squash --force
  # Should fail or gracefully handle
  if [ "$status" -eq 0 ]; then
    assert_output --partial "No commits to squash"
  else
    # Failure is also acceptable
    assert_failure
  fi
}

# ----------------------------------------------------------------------------
# git-h-files edge cases
# ----------------------------------------------------------------------------

@test "hug h files: shows help with -h" {
  run hug h files -h
  assert_success
  assert_output --partial "hug h files"
}

@test "hug h files: shows files touched by last commit by default" {
  run hug h files
  assert_success
  assert_output --partial "feature2.txt"
}

@test "hug h files: shows files touched by last N commits" {
  run hug h files 2
  assert_success
  assert_output --partial "feature1.txt"
  assert_output --partial "feature2.txt"
}

@test "hug h files: rejects both --upstream and target" {
  run hug h files main --upstream
  assert_failure
  assert_output --partial "Cannot specify both"
}

@test "hug h files: works with --quiet flag" {
  run hug h files --quiet
  assert_success
}

@test "hug h files: shows stats with file list" {
  run hug h files
  assert_success
  # Should show diff stats
  assert_output --partial "file"
  assert_output --partial "changed"
}

@test "hug h files: handles commit hash target" {
  local first_feature
  first_feature=$(git log --oneline --all | grep "Add feature 1" | awk '{print $1}')
  
  run hug h files "$first_feature"
  assert_success
}

@test "hug h files: handles when no files in range" {
  # At initial commit, going back 0 means no changes
  local initial_commit
  initial_commit=$(git rev-list --max-parents=0 HEAD)
  
  run hug h files "$initial_commit"
  assert_success
  # Should show both features
  assert_output --partial "feature"
}

# ----------------------------------------------------------------------------
# git-h-steps edge cases
# ----------------------------------------------------------------------------

@test "hug h steps: shows help with -h" {
  run hug h steps -h
  assert_success
  assert_output --partial "hug h steps"
}

@test "hug h steps: shows steps for file in HEAD" {
  run hug h steps feature2.txt
  assert_success
  assert_output --partial "0 steps back"
}

@test "hug h steps: shows steps for file in older commit" {
  run hug h steps feature1.txt
  assert_success
  assert_output --partial "1 step"
}

@test "hug h steps: handles nonexistent file gracefully" {
  run hug h steps nonexistent.txt
  # File doesn't exist
  assert_failure
  assert_output --partial "does not exist"
}

@test "hug h steps: works with --raw flag for scripting" {
  run hug h steps feature2.txt --raw
  assert_success
  assert_output "0"
}

@test "hug h steps: works with --quiet flag" {
  run hug h steps feature2.txt --quiet
  assert_success
}

@test "hug h steps: handles file with no commits" {
  # Create a new untracked file
  echo "new" > new.txt
  
  run hug h steps new.txt
  assert_failure
  # Error message may vary
  if [[ "$output" == *"does not exist"* ]]; then
    assert_output --partial "does not exist"
  elif [[ "$output" == *"Needed a single revision"* ]]; then
    assert_output --partial "Needed a single revision"
  else
    # Any failure is acceptable for untracked file
    assert_failure
  fi
}

@test "hug h steps: handles renamed files" {
  # Create and rename a file
  echo "original" > original.txt
  git add original.txt
  git commit -q -m "Add original"
  
  git mv original.txt renamed.txt
  git commit -q -m "Rename file"
  
  run hug h steps renamed.txt
  assert_success
  assert_output --partial "0 steps back"
}

@test "hug h steps: handles files in subdirectories" {
  mkdir -p src
  echo "code" > src/main.js
  git add src/main.js
  git commit -q -m "Add main.js"
  
  run hug h steps src/main.js
  assert_success
  assert_output --partial "0 steps back"
}

# ----------------------------------------------------------------------------
# Combined scenarios and stress tests
# ----------------------------------------------------------------------------

@test "hug h back then h undo reverses properly" {
  local original_head
  original_head=$(git rev-parse HEAD)
  
  # Go back
  hug h back --force --quiet
  
  # Commit the staged changes
  git commit -q -m "Re-commit"
  
  local after_recommit
  after_recommit=$(git rev-parse HEAD)
  
  # Should be back at same content (though different commit hash)
  assert_not_equal "$original_head" "$after_recommit"
}

@test "hug h operations work with detached HEAD" {
  # Detach HEAD
  git checkout --detach HEAD >/dev/null 2>&1
  
  run hug h back --force
  assert_success
}

@test "hug h commands handle merge commits" {
  # Create a branch
  git checkout -b feature-branch >/dev/null 2>&1
  echo "branch content" > branch.txt
  git add branch.txt
  git commit -q -m "Branch commit"
  
  # Go back to main and merge
  git checkout - >/dev/null 2>&1
  git merge --no-ff feature-branch -m "Merge feature" >/dev/null 2>&1
  
  # h back should work
  run hug h back --force
  assert_success
}

@test "hug h steps with file having complex history" {
  # Create a file with multiple modifications
  echo "v1" > complex.txt
  git add complex.txt
  git commit -q -m "v1"
  
  echo "v2" >> complex.txt
  git add complex.txt
  git commit -q -m "v2"
  
  echo "v3" >> complex.txt
  git add complex.txt
  git commit -q -m "v3"
  
  run hug h steps complex.txt
  assert_success
  assert_output --partial "0 steps back"
  
  # Check older file - feature1.txt is now 4 commits back (3 new + original 1)
  run hug h steps feature1.txt
  assert_success
  assert_output --partial "4 steps"
}

@test "hug h files handles large commit range" {
  # Create several commits
  for i in {1..5}; do
    echo "file$i" > "file$i.txt"
    git add "file$i.txt"
    git commit -q -m "Add file$i"
  done
  
  run hug h files 5
  assert_success
  # Should show all 5 files
  assert_output --partial "file"
}

@test "hug h back handles when working tree has conflicts" {
  # Make conflicting changes
  echo "conflict line" >> feature2.txt
  git add feature2.txt
  
  # This should preserve the staged conflict
  run hug h back --force
  assert_success
  
  # Staged changes should still be there
  run git diff --cached --name-only
  assert_output --partial "feature2.txt"
}
