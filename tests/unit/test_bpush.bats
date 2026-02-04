#!/usr/bin/env bats
# Unit tests for hug bpush command

load '../test_helper'

setup() {
  # Create a test repo with a commit
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

@test "hug bpush with URL sets upstream tracking" {
  # Create a mock bare repo to push to
  local bare_repo="/tmp/test-bare-$$-repo.git"
  git init --bare "$bare_repo"

  # Push with file:// URL - should set upstream tracking
  run hug bpush "file://$bare_repo"

  assert_success
  assert_output --partial "Setting upstream tracking"

  # Verify upstream is set
  run git branch -vv
  assert_output --partial "[origin"
}

@test "hug bpush with URL after initial push works" {
  # Create a mock bare repo to push to
  local bare_repo="/tmp/test-bare-$$-repo.git"
  git init --bare "$bare_repo"

  # First push with file:// URL - should set upstream
  run hug bpush "file://$bare_repo"
  assert_success

  # Make another commit
  echo "second" >> file1.txt
  git add file1.txt
  git commit -m "Second commit"

  # Second push without arguments - should use existing upstream
  run hug bpush
  assert_success
  assert_output --partial "Pushing to existing upstream"
}

@test "hug bpush with remote name sets upstream" {
  # Add origin remote
  local bare_repo="/tmp/test-bare-$$-repo.git"
  git init --bare "$bare_repo"
  git remote add origin "$bare_repo"

  # Push with remote name - should set upstream
  run hug bpush origin
  assert_success

  # Verify upstream is set
  run git branch -vv
  assert_output --partial "[origin"
}

@test "hug bpush without arguments to origin sets upstream" {
  # Add origin remote
  local bare_repo="/tmp/test-bare-$$-origin.git"
  git init --bare "$bare_repo"
  git remote add origin "$bare_repo"

  # Push without arguments when only origin exists
  run hug bpush
  assert_success

  # Verify upstream is set
  run git branch -vv
  assert_output --partial "[origin"
}

@test "hug bpush with URL creates named remote from URL" {
  # Create a bare repo with a specific name
  local bare_repo="/tmp/test-myproject-$$.git"
  git init --bare "$bare_repo"

  # Add a dummy remote first so the derived name is used
  git remote add dummy "/tmp/dummy.git"

  # Push with file:// URL
  run hug bpush "file://$bare_repo"

  assert_success

  # Verify remote was created with derived name
  run git remote
  assert_output --partial "myproject"
}

@test "hug bpush with file:// URL creates remote" {
  # Use file:// URL to test the format detection
  local bare_repo="/tmp/test-repo-$$.git"
  git init --bare "$bare_repo"

  # Add a dummy remote first so the derived name is used
  git remote add dummy "/tmp/dummy.git"

  # Should create a remote named 'repo' from file:///tmp/test-repo-$$-.git
  run hug bpush "file://$bare_repo"
  assert_success

  # Verify remote was created with derived name 'repo'
  run git remote
  assert_output --partial "repo"
}

@test "hug bpush with URL and explicit remote name" {
  local bare_repo="/tmp/test-custom-$$.git"
  git init --bare "$bare_repo"

  # Push with both remote name and URL (no file:// needed for explicit remote)
  run hug bpush myremote "$bare_repo"
  assert_success

  # Verify remote was created with the specified name
  run git remote
  assert_output "myremote"
}

@test "hug bpush with existing upstream uses it" {
  # Set up upstream manually
  local bare_repo="/tmp/test-existing-$$.git"
  git init --bare "$bare_repo"
  git remote add myremote "$bare_repo"
  git push -u myremote main >/dev/null 2>&1

  # Make another commit
  echo "change" >> file1.txt
  git add file1.txt
  git commit -m "Another commit"

  # Push without arguments - should use existing upstream
  run hug bpush
  assert_success
  assert_output --partial "Pushing to existing upstream"
  assert_output --partial "myremote"
}

@test "hug bpush with --track switches upstream" {
  # Set up one upstream
  local bare1="/tmp/test-old-$$.git"
  local bare2="/tmp/test-new-$$.git"
  git init --bare "$bare1"
  git init --bare "$bare2"
  git remote add oldremote "$bare1"
  git push -u oldremote main >/dev/null 2>&1

  # Make another commit
  echo "change" >> file1.txt
  git add file1.txt
  git commit -m "Another commit"

  # Add new remote and push with --track
  git remote add newremote "$bare2"
  run hug bpush --track newremote
  assert_success
  assert_output --partial "Switching upstream tracking"

  # Verify upstream was switched
  run git branch -vv
  assert_output --partial "[newremote"
}
