#!/usr/bin/env bats
# Integration tests for the brestore command

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

@test "brestore: no backups found" {
  run hug brestore
  assert_success
  assert_output --partial "No backup branches found."
}

@test "brestore: restore to original branch name" {
  # Create a feature branch and a backup
  git checkout -b my-feature
  echo "feature content" > feature.txt
  git add feature.txt
  git commit -m "add feature"
  echo "y" | hug rb main

  # Switch to main before deleting the branch
  git checkout main

  # Delete the feature branch
  git branch -D my-feature

  # Restore the branch
  run hug brestore << EOF
1
EOF
  assert_success
  assert_output --partial "Branch 'my-feature' has been restored"

  # Verify the branch exists and has the correct content
  run git checkout my-feature
  assert_success
  assert_file_contains "feature.txt" "feature content"
}

@test "brestore: restore to a new branch name" {
  # Create a feature branch and a backup
  git checkout -b my-feature
  echo "feature content" > feature.txt
  git add feature.txt
  git commit -m "add feature"
  echo "y" | hug rb main

  # Restore the branch to a new name
  run hug brestore my-new-feature << EOF
1
EOF
  assert_success
  assert_output --partial "Branch 'my-new-feature' has been restored"

  # Verify the new branch exists
  run git checkout my-new-feature
  assert_success
  assert_file_contains "feature.txt" "feature content"
}

@test "brestore: restore with existing branch and confirmation" {
  # Create a feature branch and a backup
  git checkout -b my-feature
  echo "feature content" > feature.txt
  git add feature.txt
  git commit -m "add feature"
  echo "y" | hug rb main

  # Switch to main before creating the conflicting branch
  git checkout main

  # Delete the branch if it exists
  git branch -D my-feature 2>/dev/null || true

  # Create a conflicting branch
  git checkout -b my-feature
  echo "conflicting content" > feature.txt
  git add feature.txt
  git commit -m "conflicting commit"

  # Switch away from the branch before trying to overwrite it
  git checkout main

  # Try to restore, confirming the overwrite
  run hug brestore << EOF
1
y
EOF
  assert_success
  assert_output --partial "Branch 'my-feature' already exists and will be overwritten."
  assert_output --partial "Branch 'my-feature' has been restored"

  # Verify the branch was overwritten
  run git log -1 --pretty=%s my-feature
  assert_output "add feature"
}

@test "brestore: restore with existing branch and abort" {
  # Create a feature branch and a backup
  git checkout -b my-feature
  echo "feature content" > feature.txt
  git add feature.txt
  git commit -m "add feature"
  echo "y" | hug rb main

  # Switch to main before creating the conflicting branch
  git checkout main

  # Delete the branch if it exists
  git branch -D my-feature 2>/dev/null || true

  # Create a conflicting branch
  git checkout -b my-feature
  echo "conflicting content" > another-file.txt
  git add another-file.txt
  git commit -m "conflicting commit"

  # Switch away from the branch before trying to overwrite it
  git checkout main

  # Try to restore, but abort
  run hug brestore << EOF
1
n
EOF
  assert_failure
  assert_output --partial "Branch 'my-feature' already exists and will be overwritten."

  # Verify the branch was NOT overwritten
  run git log -1 --pretty=%s my-feature
  assert_output "conflicting commit"
}
