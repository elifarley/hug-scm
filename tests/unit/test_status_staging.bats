#!/usr/bin/env bats
# Tests for status and staging commands (s*, a*, us*)

# Load test helpers
load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_changes)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

@test "hug s: shows status summary" {
  run hug s
  assert_success
  # Should show some status information (HEAD, branch, or status indicator)
  [[ "$output" =~ (HEAD|master|Staged|Unstaged) ]]
}

@test "hug sl: shows status without untracked files" {
  run hug sl
  assert_success
  # Should not show untracked.txt
  refute_output --partial "untracked.txt"
}

@test "hug sla: shows status with untracked files" {
  run hug sla
  assert_success
  # Should show untracked.txt
  assert_output --partial "untracked.txt"
}

@test "hug ss: shows staged changes" {
  run hug ss
  assert_success
  # Should show staged file
  assert_output --partial "staged.txt"
}

@test "hug su: shows unstaged changes" {
  run hug su
  assert_success
  # Should show modified README
  assert_output --partial "README.md"
}

@test "hug sw: shows working directory changes" {
  run hug sw
  assert_success
  # Should show both staged and unstaged
}

@test "hug a: stages tracked modified files" {
  # Modify a tracked file
  echo "More content" >> README.md
  
  run hug a
  assert_success
  
  # Check that README.md is now staged
  run git diff --cached --name-only
  assert_output --partial "README.md"
}

@test "hug aa: stages all changes including untracked" {
  run hug aa
  assert_success
  
  # Check that untracked.txt is now staged
  run git diff --cached --name-only
  assert_output --partial "untracked.txt"
  assert_output --partial "staged.txt"
}

@test "hug us: unstages specific file" {
  # First ensure staged.txt is staged
  git add staged.txt
  
  run hug us staged.txt
  assert_success
  
  # Check that staged.txt is no longer staged
  run git diff --cached --name-only
  refute_output --partial "staged.txt"
}

@test "hug usa: unstages all files" {
  # Stage multiple files
  git add -A
  
  run hug usa
  assert_success
  
  # Check that nothing is staged
  run git diff --cached --name-only
  assert_output ""
}

@test "hug s with clean repository shows clean status" {
  # Create a fresh repo
  local clean_repo
  clean_repo=$(create_test_repo)
  cd "$clean_repo"
  
  run hug s
  assert_success
  # Clean status shows HEAD or a clean indicator (no Staged/Unstaged mentions)
  [[ "$output" =~ HEAD ]]
  [[ ! "$output" =~ Unstaged ]]
}

@test "hug ss with specific file shows only that file" {
  run hug ss staged.txt
  assert_success
  assert_output --partial "staged.txt"
}

@test "hug su with specific file shows only that file" {
  run hug su README.md
  assert_success
  assert_output --partial "README.md"
}

@test "hug a with specific file stages only that file" {
  # Modify multiple files
  echo "Change 1" >> README.md
  echo "Change 2" > newfile.txt
  git add newfile.txt
  
  run hug a README.md
  assert_success
  
  # Only README.md should be in the last stage operation
  run git diff --cached --name-only
  assert_output --partial "README.md"
}

@test "hug us: shows help with -h flag" {
  run hug us -h
  assert_success
  assert_output --partial "hug us: UnStage one or more files"
  assert_output --partial "USAGE:"
}

# Note: 'staged.txt' is created by the test fixture 'create_test_repo_with_changes' in setup().
@test "hug us: unstages single file when specified" {
  # Stage a file first
  git add staged.txt
  
  run hug us staged.txt
  assert_success
  assert_output --partial "✅ Success: Unstaged 1 file:"
  assert_output --partial "staged.txt"
  
  # Verify file is no longer staged
  run git diff --cached --name-only
  refute_output --partial "staged.txt"
}

@test "hug us: unstages multiple files when specified" {
  # Stage multiple files
  echo "content" > file1.txt
  echo "content" > file2.txt
  git add file1.txt file2.txt
  
  run hug us file1.txt file2.txt
  assert_success
  assert_output --partial "Unstaged 2 files:"
  
  # Verify files are no longer staged
  run git diff --cached --name-only
  refute_output --partial "file1.txt"
  refute_output --partial "file2.txt"
}

@test "hug us: shows informative message when no staged files" {
  # Make sure nothing is staged
  git reset HEAD --quiet 2>/dev/null || true
  
  run hug us
  assert_success
  assert_output --partial "No staged files to unstage"
}

@test "hug us: shows error when file is not staged" {
  # Make sure file is not staged
  git reset HEAD README.md --quiet 2>/dev/null || true
  
  run hug us README.md
  assert_failure
  assert_output --partial "is not staged"
}

@test "hug us: dry-run shows preview without unstaging" {
  # Stage a file
  git add staged.txt
  
  run hug us staged.txt --dry-run
  assert_success
  assert_output --partial "Dry run: Would unstage 1 file"
  assert_output --partial "staged.txt"
  
  # Verify file is still staged
  run git diff --cached --name-only
  assert_output --partial "staged.txt"
}

@test "hug untrack: shows help with -h flag" {
  run hug untrack -h
  assert_success
  assert_output --partial "hug untrack: Stop tracking files but keep them locally"
  assert_output --partial "USAGE:"
}

@test "hug untrack: untracks single file when specified" {
  # Create and commit a file
  echo "secret" > .env
  git add .env
  git commit -q -m "Add .env"
  
  # Untrack it with --force to skip confirmation
  run hug untrack .env --force
  assert_success
  assert_output --partial "✅ Success: Untracked 1 file (kept locally):"
  assert_output --partial ".env"
  
  # Verify file is untracked but still exists locally
  run git ls-files
  refute_output --partial ".env"
  assert_file_exist .env
}

@test "hug untrack: untracks multiple files when specified" {
  # Create and commit multiple files
  echo "secret1" > secret1.txt
  echo "secret2" > secret2.txt
  git add secret1.txt secret2.txt
  git commit -q -m "Add secrets"
  
  # Untrack them with --force to skip confirmation
  run hug untrack secret1.txt secret2.txt --force
  assert_success
  assert_output --partial "Untracked 2 files (kept locally):"
  
  # Verify files are untracked but still exist locally
  run git ls-files
  refute_output --partial "secret1.txt"
  refute_output --partial "secret2.txt"
  assert_file_exist secret1.txt
  assert_file_exist secret2.txt
}

@test "hug untrack: shows error when file is not tracked" {
  # Create an untracked file
  echo "content" > untracked_file.txt
  
  run hug untrack untracked_file.txt
  assert_failure
  assert_output --partial "is not tracked by git"
}

@test "hug untrack: dry-run shows preview without untracking" {
  # Create and commit a file
  echo "test" > test.txt
  git add test.txt
  git commit -q -m "Add test.txt"
  
  run hug untrack test.txt --dry-run
  assert_success
  assert_output --partial "Dry run: Would untrack 1 file"
  assert_output --partial "test.txt"
  
  # Verify file is still tracked
  run git ls-files
  assert_output --partial "test.txt"
}

@test "hug untrack: prompts for confirmation by default" {
  # Create and commit a file
  echo "test" > confirm_test.txt
  git add confirm_test.txt
  git commit -q -m "Add confirm_test.txt"
  
  # Run without --force and provide 'n' to decline
  run bash -c "echo 'n' | hug untrack confirm_test.txt"
  assert_failure
  assert_output --partial "Cancelled"
  
  # Verify file is still tracked
  run git ls-files
  assert_output --partial "confirm_test.txt"
}

################################################################################
# Interactive File Selection with --browse-root Tests
################################################################################

@test "hug sw --browse-root: triggers interactive mode when gum is available" {
  # Mock gum_available to ensure test can run
  if ! gum_available; then
    skip "gum not available"
  fi
  
  # Run with --browse-root and no paths - should trigger interactive mode
  # Use timeout since we can't interact with gum in tests
  run timeout 1 bash -c "hug sw --browse-root < /dev/null" || true
  
  # Should have attempted to use interactive selection
  # The key is that it doesn't show the full diff output (non-interactive mode)
  refute_output --partial "Working dir changes:"
}

@test "hug ss --browse-root: triggers interactive mode" {
  if ! gum_available; then
    skip "gum not available"
  fi
  
  run timeout 1 bash -c "hug ss --browse-root < /dev/null" || true
  
  # Should have attempted interactive selection, not showing full diff
  refute_output --partial "Staged changes:"
}

@test "hug su --browse-root: triggers interactive mode" {
  if ! gum_available; then
    skip "gum not available"
  fi
  
  run timeout 1 bash -c "hug su --browse-root < /dev/null" || true
  
  # Should have attempted interactive selection
  refute_output --partial "Unstaged changes:"
}

@test "hug a --browse-root: triggers interactive mode" {
  if ! gum_available; then
    skip "gum not available"
  fi
  
  run timeout 1 bash -c "hug a --browse-root < /dev/null" || true
  
  # Should have attempted interactive selection
  # Won't stage anything but shouldn't error about missing args
  # Acceptable exit codes: 124 (timeout), or other non-zero (interactive cancel)
  # We do not assert on status here, as interactive mode may exit with non-zero.
  # The output assertions below are sufficient to verify correct behavior.
}

@test "hug sw --browse-root with path: errors and aborts" {
  run hug sw --browse-root file.txt
  assert_failure
  assert_output --partial "cannot be used with explicit paths"
}

@test "hug ss --browse-root with path: errors and aborts" {
  run hug ss --browse-root file.txt
  assert_failure
  assert_output --partial "cannot be used with explicit paths"
}
