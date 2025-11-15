#!/usr/bin/env bats
# Tests for hug-git-commit library: commit range analysis functions

load '../test_helper'
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-git-repo'
load '../../git-config/lib/hug-git-commit'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
  
  # Create a few commits for testing
  echo "first" > file1.txt
  git add file1.txt
  git commit -q -m "first commit"
  
  echo "second" > file2.txt
  git add file2.txt
  git commit -q -m "second commit"
  
  echo "third" > file3.txt
  git add file3.txt
  git commit -q -m "third commit"
}

teardown() {
  cleanup_test_repo
}

################################################################################
# count_commits_in_range TESTS
################################################################################

@test "count_commits_in_range: counts commits between two refs" {
  run count_commits_in_range HEAD~2 HEAD
  assert_success
  assert_output "2"
}

@test "count_commits_in_range: returns 0 for same ref" {
  run count_commits_in_range HEAD HEAD
  assert_success
  assert_output "0"
}

@test "count_commits_in_range: uses HEAD as default end" {
  run count_commits_in_range HEAD~1
  assert_success
  assert_output "1"
}

################################################################################
# list_changed_files_in_range TESTS
################################################################################

@test "list_changed_files_in_range: lists changed files" {
  run list_changed_files_in_range HEAD~2 HEAD
  assert_success
  assert_line "file2.txt"
  assert_line "file3.txt"
}

@test "list_changed_files_in_range: returns empty for same ref" {
  run list_changed_files_in_range HEAD HEAD
  assert_success
  assert_output ""
}

################################################################################
# count_changed_files_in_range TESTS
################################################################################

@test "count_changed_files_in_range: counts changed files" {
  run count_changed_files_in_range HEAD~2 HEAD
  assert_success
  assert_output "2"
}

@test "count_changed_files_in_range: returns 0 for same ref" {
  run count_changed_files_in_range HEAD HEAD
  assert_success
  assert_output "0"
}

################################################################################
# resolve_temporal_to_commit TESTS
################################################################################

@test "resolve_temporal_to_commit: resolves relative time (days ago)" {
  # Create commits with specific dates
  echo "old" > old.txt
  git add old.txt
  GIT_COMMITTER_DATE="2024-01-01 10:00:00" GIT_AUTHOR_DATE="2024-01-01 10:00:00" \
    git commit -q -m "Old commit"
  
  echo "recent" > recent.txt
  git add recent.txt
  GIT_COMMITTER_DATE="2024-01-15 10:00:00" GIT_AUTHOR_DATE="2024-01-15 10:00:00" \
    git commit -q -m "Recent commit"
  
  # Should find first commit at or after 10 days before HEAD (Jan 15 - 10 days = Jan 5)
  # First commit on/after Jan 5 is the Jan 15 commit
  run resolve_temporal_to_commit "10 days ago" HEAD
  assert_success
  
  # Verify it returns a valid commit hash
  local commit_hash
  commit_hash="$output"
  run git rev-parse --verify "$commit_hash"
  assert_success
}

@test "resolve_temporal_to_commit: resolves relative time (weeks ago)" {
  echo "week1" > week1.txt
  git add week1.txt
  GIT_COMMITTER_DATE="2024-01-01 10:00:00" GIT_AUTHOR_DATE="2024-01-01 10:00:00" \
    git commit -q -m "Week 1"
  
  echo "week2" > week2.txt
  git add week2.txt
  GIT_COMMITTER_DATE="2024-01-15 10:00:00" GIT_AUTHOR_DATE="2024-01-15 10:00:00" \
    git commit -q -m "Week 2"
  
  run resolve_temporal_to_commit "1 week ago" HEAD
  assert_success
  
  # Verify it returns a valid commit hash
  local commit_hash
  commit_hash="$output"
  run git rev-parse --verify "$commit_hash"
  assert_success
}

@test "resolve_temporal_to_commit: resolves absolute date" {
  echo "jan1" > jan1.txt
  git add jan1.txt
  GIT_COMMITTER_DATE="2024-01-01 10:00:00" GIT_AUTHOR_DATE="2024-01-01 10:00:00" \
    git commit -q -m "Jan 1"
  
  echo "jan15" > jan15.txt
  git add jan15.txt
  GIT_COMMITTER_DATE="2024-01-15 10:00:00" GIT_AUTHOR_DATE="2024-01-15 10:00:00" \
    git commit -q -m "Jan 15"
  
  # Should find first commit on or after 2024-01-10
  run resolve_temporal_to_commit "2024-01-10" HEAD
  assert_success
  
  # Verify it returns a valid commit hash
  local commit_hash
  commit_hash="$output"
  run git rev-parse --verify "$commit_hash"
  assert_success
}

@test "resolve_temporal_to_commit: fails when no commits found" {
  # Try to find commits from far in the future
  run resolve_temporal_to_commit "2099-01-01" HEAD
  assert_failure
  assert_output --partial "Unable to parse time specification '2099-01-01' or no commits found after that time"
}

@test "resolve_temporal_to_commit: uses HEAD as default reference" {
  echo "test" > test.txt
  git add test.txt
  GIT_COMMITTER_DATE="2024-01-15 10:00:00" GIT_AUTHOR_DATE="2024-01-15 10:00:00" \
    git commit -q -m "Test commit"
  
  # Should work without explicit reference
  run resolve_temporal_to_commit "5 days ago"
  assert_success
}

@test "resolve_temporal_to_commit: handles various time units" {
  echo "test" > test.txt
  git add test.txt
  GIT_COMMITTER_DATE="2024-01-15 10:00:00" GIT_AUTHOR_DATE="2024-01-15 10:00:00" \
    git commit -q -m "Test commit"
  
  # Test different time units (should not error)
  run resolve_temporal_to_commit "1 hour ago"
  assert_success
  
  run resolve_temporal_to_commit "30 minutes ago"
  assert_success
  
  run resolve_temporal_to_commit "1 month ago"
  assert_success
}
