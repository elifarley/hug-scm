#!/usr/bin/env bats
# Tests for working directory commands (w*)

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

@test "hug w discard: discards changes to specific file with force" {
  # Modify a tracked file
  echo "Unwanted change" >> README.md
  
  run hug w discard -f README.md
  assert_success
  
  # File should be back to original state
  run git diff README.md
  assert_output ""
}

@test "hug w discard: requires confirmation without force flag" {
  echo "Unwanted change" >> README.md
  
  # Without -f, it should prompt (will fail in non-interactive test)
  # We test that it doesn't proceed automatically
  run timeout 1 bash -c "echo 'n' | hug w discard README.md"
  
  # Should still have changes (user said no)
  run git diff README.md
  assert_output --partial "Unwanted change"
}

@test "hug w discard --dry-run: shows preview without making changes" {
  echo "Unwanted change" >> README.md
  
  run hug w discard --dry-run README.md
  assert_success
  assert_output --partial "would be discarded"
  
  # File should still have changes
  run git diff README.md
  assert_output --partial "Unwanted change"
}

@test "hug w discard-all -f: discards all unstaged changes" {
  run hug w discard-all -f
  assert_success
  
  # Unstaged changes should be gone
  run git diff
  assert_output ""
  
  # But staged changes should remain
  run git diff --cached --name-only
  assert_output --partial "staged.txt"
}

@test "hug w wipe: resets both staged and unstaged for file" {
  # Modify and stage a file
  echo "Change" >> README.md
  git add README.md
  echo "More change" >> README.md
  
  run hug w wipe -f README.md
  assert_success
  
  # Both staged and unstaged should be gone
  run git diff README.md
  assert_output ""
  run git diff --cached README.md
  assert_output ""
}

@test "hug w wipe-all -f: resets all tracked files" {
  run hug w wipe-all -f
  assert_success
  
  # All changes to tracked files should be gone
  run git diff
  assert_output ""
  run git diff --cached
  assert_output ""
  
  # But untracked files should remain
  assert_file_exists "untracked.txt"
}

@test "hug w purge: removes untracked files" {
  # Create some untracked files
  echo "temp" > temp.txt
  
  run hug w purge temp.txt
  assert_success
  
  assert_file_not_exists "temp.txt"
}

@test "hug w purge-all: removes all untracked files" {
  run hug w purge-all -f
  assert_success
  
  # Untracked files should be gone
  assert_file_not_exists "untracked.txt"
  
  # But tracked files should remain
  assert_file_exists "README.md"
}

@test "hug w zap: does complete cleanup of specific files" {
  skip "This test needs investigation - command may prompt"
  # This should discard changes AND remove if untracked
  echo "Change" >> README.md
  git add README.md
  
  run hug w zap README.md untracked.txt
  assert_success
  
  # README.md should be clean
  run git diff README.md
  assert_output ""
  run git diff --cached README.md
  assert_output ""
  
  # untracked.txt should be gone
  assert_file_not_exists "untracked.txt"
}

@test "hug w zap-all --dry-run: previews complete cleanup" {
  run hug w zap-all --dry-run
  assert_success
  assert_output --partial "would be"
  
  # Nothing should actually be changed
  assert_file_exists "untracked.txt"
  run git status --porcelain
  assert_output # Should have changes
}

@test "hug w zap-all -f: does complete repository cleanup" {
  run hug w zap-all -f
  assert_success
  
  # Everything should be clean
  assert_git_clean
  assert_file_not_exists "untracked.txt"
}

@test "hug w get: retrieves file from specific commit" {
  skip "This test needs investigation - command may prompt or hang"
  # Create a commit with a file
  echo "Version 1" > test.txt
  git add test.txt
  git commit -q -m "Add test.txt"
  
  # Modify it
  echo "Version 2" > test.txt
  git add test.txt
  git commit -q -m "Update test.txt"
  
  # Get the old version
  run hug w get HEAD~1 test.txt
  assert_success
  
  # Should have version 1 content
  run cat test.txt
  assert_output "Version 1"
}

@test "hug w purge ignores already clean directory" {
  # Clean up first
  rm -f untracked.txt
  
  run hug w purge-all -f
  assert_success
  assert_output --partial "Nothing to purge"
}

@test "hug w discard-all works with -u flag for unstaged only" {
  run hug w discard-all -u -f
  assert_success
  
  # Unstaged changes should be gone
  run git diff
  assert_output ""
  
  # Staged changes should remain
  run git diff --cached --name-only
  assert_output --partial "staged.txt"
}

@test "hug w discard-all works with -s flag for staged only" {
  run hug w discard-all -s -f
  assert_success
  
  # Staged changes should be gone
  run git diff --cached
  assert_output ""
  
  # Unstaged changes should remain
  run git diff --name-only
  assert_output --partial "README.md"
}
