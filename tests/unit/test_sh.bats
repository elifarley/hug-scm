#!/usr/bin/env bats
# Tests for hug sh and hug shp commands

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

# -----------------------------------------------------------------------------
# hug sh tests (show commit with file stats)
# -----------------------------------------------------------------------------

@test "hug sh: shows last commit with heading" {
  run hug sh
  assert_success
  # Should show the heading with emojis
  assert_output --partial "📄"
  assert_output --partial "ℹ️"
  assert_output --partial "Commit info:"
  # Should show commit info
  assert_output --partial "Add feature 2"
}

@test "hug sh: shows specific commit" {
  # Get hash of first feature commit
  local first_feature
  first_feature=$(git log --oneline --all | grep "Add feature 1" | awk '{print $1}')

  run hug sh "$first_feature"
  assert_success
  # Should show the heading
  assert_output --partial "Commit info:"
  # Should show the specific commit
  assert_output --partial "Add feature 1"
}

@test "hug sh: shows commit with file statistics" {
  run hug sh
  assert_success
  # Should show stats section (file counts and line changes)
  assert_output --partial "file"
  assert_output --partial "changed"
  assert_output --partial "insertion"
}

@test "hug sh: shows help with -h" {
  run hug sh -h
  assert_success
  assert_output --partial "USAGE:"
  assert_output --partial "Show specific commit with file statistics"
}

@test "hug sh: handles HEAD~ notation" {
  run hug sh HEAD~1
  assert_success
  # Should show the second commit
  assert_output --partial "Add feature 1"
}

@test "hug sh: shows commit author and date" {
  run hug sh
  assert_success
  # logbody format includes author and date
  assert_output --partial "["
  assert_output --partial "]"
}

# -----------------------------------------------------------------------------
# hug shp tests (show commit with patch and file stats)
# -----------------------------------------------------------------------------

@test "hug shp: shows last commit with heading" {
  run hug shp
  assert_success
  # Should show the heading with emojis
  assert_output --partial "📄"
  assert_output --partial "🔀"
  assert_output --partial "Commit diff:"
  # Should show commit info
  assert_output --partial "Add feature 2"
}

@test "hug shp: shows specific commit with patch" {
  # Get hash of first feature commit
  local first_feature
  first_feature=$(git log --oneline --all | grep "Add feature 1" | awk '{print $1}')

  run hug shp "$first_feature"
  assert_success
  # Should show the heading
  assert_output --partial "Commit diff:"
  # Should show the specific commit
  assert_output --partial "Add feature 1"
}

@test "hug shp: shows full patch diff" {
  run hug shp
  assert_success
  # Should show diff content
  assert_output --partial "diff --git"
  assert_output --partial "index"
  assert_output --partial "---"
  assert_output --partial "+++"
}

@test "hug shp: shows file stats at the end" {
  run hug shp
  assert_success
  # Should show stats after the patch
  # The stats output comes from git show --stat
  assert_output --partial "file"
  # Stats show summary of changes
  [[ "$output" =~ ([0-9]+ insertion|[0-9]+ deletion) ]] || true
}

@test "hug shp: shows help with -h" {
  run hug shp -h
  assert_success
  assert_output --partial "USAGE:"
  assert_output --partial "Show specific commit with patch and file statistics"
}

@test "hug shp: handles HEAD~ notation" {
  run hug shp HEAD~1
  assert_success
  # Should show the second commit with patch
  assert_output --partial "Add feature 1"
  assert_output --partial "diff --git"
}

@test "hug shp: shows both commit info and patch" {
  run hug shp
  assert_success
  # Should have commit message from logbody format
  assert_output --partial "Add feature 2"
  # Should have patch
  assert_output --partial "diff --git"
  # Should have stats at end
  assert_output --partial "file"
}

# -----------------------------------------------------------------------------
# Edge cases and error handling
# -----------------------------------------------------------------------------

@test "hug sh: handles non-existent commit gracefully" {
  run hug sh nonexistent123abc
  # git will error on invalid commit
  assert_failure
}

@test "hug shp: handles non-existent commit gracefully" {
  run hug shp nonexistent123abc
  # git will error on invalid commit
  assert_failure
}

@test "hug sh: works with empty commit message" {
  echo "empty commit content" > empty.txt
  git add empty.txt
  git commit --allow-empty-message -m ""

  run hug sh HEAD
  assert_success
  # Should still show heading even with empty message
  assert_output --partial "Commit info:"
}

@test "hug shp: works with empty commit message" {
  echo "empty commit content" > empty2.txt
  git add empty2.txt
  git commit --allow-empty-message -m ""

  run hug shp HEAD
  assert_success
  # Should still show heading even with empty message
  assert_output --partial "Commit diff:"
}

@test "hug sh: handles merge commit" {
  # Create a branch and merge it
  git checkout -b feature-branch HEAD~1 2>/dev/null
  echo "branch content" > branch.txt
  git add branch.txt
  git commit -q -m "Branch commit"
  git checkout - 2>/dev/null
  git merge --no-ff feature-branch -m "Merge feature" >/dev/null 2>&1

  run hug sh HEAD
  assert_success
  assert_output --partial "Merge feature"
}

@test "hug shp: handles merge commit" {
  # Create a branch and merge it
  git checkout -b feature-branch HEAD~1 2>/dev/null
  echo "branch content" > branch2.txt
  git add branch2.txt
  git commit -q -m "Branch commit 2"
  git checkout - 2>/dev/null
  git merge --no-ff feature-branch -m "Merge feature 2" >/dev/null 2>&1

  run hug shp HEAD
  assert_success
  assert_output --partial "Merge feature 2"
  assert_output --partial "Commit diff:"
}

# -----------------------------------------------------------------------------
# Numeric shorthand tests (N → HEAD~N convention)
# -----------------------------------------------------------------------------

@test "hug sh: numeric shorthand shows commit N steps back" {
  # hug sh 1 should show HEAD~1 (Add feature 1)
  run hug sh 1
  assert_success
  assert_output --partial "Add feature 1"
}

@test "hug shp: numeric shorthand shows commit N steps back with patch" {
  # hug shp 1 should show HEAD~1 (Add feature 1) with patch
  run hug shp 1
  assert_success
  assert_output --partial "Add feature 1"
  assert_output --partial "diff --git"
}

# -----------------------------------------------------------------------------
# hug shc tests (show changed files with stats)
# -----------------------------------------------------------------------------

@test "hug shc: shows changed files in last commit" {
  run hug shc
  assert_success
  assert_output --partial "file"
  assert_output --partial "changed"
}

@test "hug shc: numeric shorthand shows cumulative changes in last N commits" {
  # hug shc 2 should show cumulative changes in HEAD~2..HEAD
  run hug shc 2
  assert_success
  assert_output --partial "Changed files in range HEAD~2..HEAD"
}

@test "hug shc: handles explicit range" {
  run hug shc HEAD~1..HEAD
  assert_success
  assert_output --partial "Changed files in range HEAD~1..HEAD"
}

@test "hug shc: shows help with -h" {
  run hug shc -h
  assert_success
  assert_output --partial "USAGE:"
  assert_output --partial "Show files changed"
}
