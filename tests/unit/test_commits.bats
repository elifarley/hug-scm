#!/usr/bin/env bats
# Tests for commit commands (c*)

# Load test helpers
load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

@test "hug c: commits staged changes with -m flag" {
  echo "test content" > file.txt
  run hug a file.txt
  assert_success
  
  run hug c -m "Test commit"
  assert_success
  assert_output --partial "Committing staged changes"
  
  # Verify commit exists
  run git log --oneline
  assert_success
  assert_output --partial "Test commit"
}

@test "hug c: shows error when nothing is staged" {
  run hug c -m "Should fail"
  assert_failure
  assert_output --partial "No staged changes found"
  assert_output --partial "Suggestions"
}

@test "hug c: accepts --message= format" {
  echo "test content" > file.txt
  run hug a file.txt
  assert_success
  
  run hug c --message="Test commit with equals"
  assert_success
  assert_output --partial "Committing staged changes"
}

@test "hug c: works without message flag (opens editor)" {
  echo "test content" > file.txt
  run hug a file.txt
  assert_success
  
  # Use a fake editor that writes a commit message
  # Create a simple script instead of inline bash
  cat > /tmp/test-editor.sh << 'EDITORSCRIPT'
#!/bin/bash
echo "Test commit from editor" > "$1"
EDITORSCRIPT
  chmod +x /tmp/test-editor.sh
  
  export GIT_EDITOR="/tmp/test-editor.sh"
  run timeout 5 hug c
  assert_success
  
  # Verify commit exists with our message
  run git log --oneline
  assert_success
  assert_output --partial "Test commit from editor"
  
  rm -f /tmp/test-editor.sh
}

@test "hug c: passes through other git commit flags" {
  echo "test content" > file.txt
  run hug a file.txt
  assert_success
  
  run hug c -m "Test commit" --allow-empty-message
  assert_success
}
