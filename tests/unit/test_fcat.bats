#!/usr/bin/env bats
# Tests for hug fcat: view file content at a specific commit

load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

# -----------------------------------------------------------------------------
# Basic functionality
# -----------------------------------------------------------------------------

@test "hug fcat: shows file content at HEAD" {
  run hug fcat 0 feature1.txt
  assert_success
  assert_output "Feature 1"
}

@test "hug fcat: shows file content at specific commit hash" {
  local commit
  commit=$(git log --oneline | grep "Add feature 1" | awk '{print $1}')

  run hug fcat "$commit" feature1.txt
  assert_success
  assert_output "Feature 1"
}

@test "hug fcat: shows file content at branch" {
  run hug fcat main feature2.txt
  assert_success
  assert_output "Feature 2"
}

@test "hug fcat: shows file content at explicit HEAD~1 ref" {
  # Use explicit HEAD~1 ref (not N=1) to test commit-ref resolution.
  # N=1 with file-specific counting would fail here because feature1.txt
  # was only changed in one commit, so there's no "second-to-last" change.
  run hug fcat HEAD~1 feature1.txt
  assert_success
  assert_output "Feature 1"
}

# -----------------------------------------------------------------------------
# File-specific N counting
# -----------------------------------------------------------------------------

@test "hug fcat: N counts file-specific commits" {
  # feature1.txt was only touched in "Add feature 1" commit (HEAD~1)
  # So fcat 0 = HEAD, fcat 1 = commit before its last change
  # Create another commit touching feature1.txt
  echo "Feature 1 updated" > feature1.txt
  git add feature1.txt
  git commit -m "Update feature 1" -q

  # N=0 should show current (updated) content
  run hug fcat 0 feature1.txt
  assert_success
  assert_output "Feature 1 updated"

  # N=1 should show content before last change (original)
  run hug fcat 1 feature1.txt
  assert_success
  assert_output "Feature 1"
}

@test "hug fcat: N=2 goes back two file-specific changes" {
  echo "Feature 1 v2" > feature1.txt
  git add feature1.txt
  git commit -m "Update feature 1 v2" -q

  echo "Feature 1 v3" > feature1.txt
  git add feature1.txt
  git commit -m "Update feature 1 v3" -q

  # N=2 should go back 2 file-specific commits
  run hug fcat 2 feature1.txt
  assert_success
  # After v3 at HEAD, v2 is N=1, original is N=2
  assert_output "Feature 1"
}

# -----------------------------------------------------------------------------
# Error handling
# -----------------------------------------------------------------------------

@test "hug fcat: errors for non-existent file" {
  run hug fcat 0 nonexistent.txt
  assert_failure
  assert_output --partial "does not exist"
}

@test "hug fcat: errors for non-existent commit" {
  run hug fcat abc123def feature1.txt
  assert_failure
}

@test "hug fcat: errors for negative N (ranges not supported)" {
  run hug fcat -3 feature1.txt
  assert_failure
  assert_output --partial "Range"
}

@test "hug fcat: errors with no arguments" {
  run hug fcat
  assert_failure
  assert_output --partial "USAGE"
}

@test "hug fcat: errors with only one argument (missing path)" {
  run hug fcat HEAD
  assert_failure
  assert_output --partial "USAGE"
}

@test "hug fcat: shows help with -h" {
  run hug fcat -h
  assert_success
  assert_output --partial "USAGE:"
  assert_output --partial "file content"
}
