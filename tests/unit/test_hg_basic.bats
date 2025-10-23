#!/usr/bin/env bats
# Tests for Mercurial status and basic commands

# Load test helpers
load '../test_helper'

setup() {
  require_hg
  require_hug
  TEST_REPO=$(create_test_hg_repo_with_changes)
  cd "$TEST_REPO"
  # Update PATH to include hg-config bin
  export PATH="$PROJECT_ROOT/hg-config/bin:$PATH"
}

teardown() {
  cleanup_test_repo
}

@test "hug s: shows status in Mercurial repo" {
  run hug s
  assert_success
  # Should show some status information
  [[ "$output" =~ (M|A|\?) ]]
}

@test "hug a: works in Mercurial repo" {
  run hug a untracked.txt
  assert_success
  # Verify file was added
  run hg status untracked.txt
  assert_output --partial "A untracked.txt"
}

@test "hug aa: adds all files in Mercurial repo" {
  run hug aa
  assert_success
  # Should have added untracked.txt
  run hg status
  assert_output --partial "A untracked.txt"
}

@test "hug b: lists bookmarks and branches" {
  run hug b
  assert_success
  # Should show bookmarks and branches sections
  [[ "$output" =~ (Bookmarks|Branches) ]]
}

@test "hug bc: creates a new bookmark" {
  run hug bc test-bookmark
  assert_success
  # Verify bookmark was created
  run hg bookmarks
  assert_output --partial "test-bookmark"
}

@test "hug l: shows log with graph" {
  run hug l
  assert_success
  # Should show commit hash and message
  assert_output --partial "Initial commit"
}

@test "hug c: commits changes" {
  # First add the untracked file
  hg add untracked.txt
  
  # Commit with message
  run hug c -m "Test commit"
  assert_success
  
  # Verify commit was created
  run hg log --template '{desc}\n' -r .
  assert_output "Test commit"
}

@test "hug w discard: reverts file changes" {
  # Make a change
  echo "New content" > README.md
  
  # Discard it with force flag
  run hug w discard -f README.md
  assert_success
  
  # Verify file was reverted
  run cat README.md
  assert_output "# Test Repository"
}

@test "hug w discard-all: reverts all changes" {
  # Verify we have changes
  run hg status
  assert_success
  [[ -n "$output" ]]
  
  # Discard all with force flag
  run hug w discard-all -f
  assert_success
  
  # Verify repo is clean (only untracked files remain)
  run hg status -mard
  [[ -z "$output" ]]
}

@test "hug w purge: removes untracked files" {
  # Verify untracked file exists
  assert_file_exists untracked.txt
  
  # Purge with force flag
  run hug w purge -f
  assert_success
  
  # Verify file was removed
  assert_file_not_exists untracked.txt
}
