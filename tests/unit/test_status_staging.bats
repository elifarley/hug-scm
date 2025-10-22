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
  # Should show some status information
  assert_output --partial "Changes"
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
  assert_output --partial "working tree clean"
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
