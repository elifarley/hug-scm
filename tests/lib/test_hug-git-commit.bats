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

################################################################################
# parse_temporal_flag TESTS
################################################################################

@test "parse_temporal_flag: parses -t flag with time spec" {
  eval "$(parse_temporal_flag -t "3 days ago" some other args)"
  
  assert_equal "$temporal_spec" "3 days ago"
  assert_equal "$1" "some"
  assert_equal "$2" "other"
  assert_equal "$3" "args"
}

@test "parse_temporal_flag: parses --temporal flag" {
  eval "$(parse_temporal_flag --temporal "1 week ago" remaining)"
  
  assert_equal "$temporal_spec" "1 week ago"
  assert_equal "$1" "remaining"
}

@test "parse_temporal_flag: errors when -t missing time spec" {
  run bash -c "cd $TEST_REPO && source $HUG_HOME/git-config/lib/hug-common && source $HUG_HOME/git-config/lib/hug-git-commit && eval \"\$(parse_temporal_flag -t)\""
  assert_failure
  assert_output --partial "requires a time specification"
}

@test "parse_temporal_flag: errors when -t followed by flag" {
  run bash -c "cd $TEST_REPO && source $HUG_HOME/git-config/lib/hug-common && source $HUG_HOME/git-config/lib/hug-git-commit && eval \"\$(parse_temporal_flag -t --force)\""
  assert_failure
  assert_output --partial "requires a time specification"
}

@test "parse_temporal_flag: preserves other arguments" {
  eval "$(parse_temporal_flag arg1 -t "time spec" arg2 --flag arg3)"
  
  assert_equal "$temporal_spec" "time spec"
  assert_equal "$1" "arg1"
  assert_equal "$2" "arg2"
  assert_equal "$3" "--flag"
  assert_equal "$4" "arg3"
}

@test "parse_temporal_flag: handles no temporal flag" {
  eval "$(parse_temporal_flag arg1 arg2)"
  
  assert_equal "$temporal_spec" ""
  assert_equal "$1" "arg1"
  assert_equal "$2" "arg2"
}

################################################################################
# resolve_target_with_temporal TESTS
################################################################################

@test "resolve_target_with_temporal: resolves explicit target" {
  run resolve_target_with_temporal false "" "HEAD~1" "HEAD~2"
  assert_success
  
  # Should resolve to HEAD~1's commit hash
  expected=$(git rev-parse HEAD~1)
  assert_output "$expected"
}

@test "resolve_target_with_temporal: uses default when no args" {
  run resolve_target_with_temporal false "" "" "HEAD~1"
  assert_success
  
  expected=$(git rev-parse HEAD~1)
  assert_output "$expected"
}

@test "resolve_target_with_temporal: resolves temporal spec" {
  # Create a commit with known date
  echo "test" > test.txt
  git add test.txt
  GIT_COMMITTER_DATE="2024-01-15 10:00:00" GIT_AUTHOR_DATE="2024-01-15 10:00:00" \
    git commit -q -m "Test commit"
  
  run resolve_target_with_temporal false "5 days ago" "" "HEAD~1"
  assert_success
  # Should return a commit hash
  [[ "$output" =~ ^[0-9a-f]{40}$ ]] || fail "Expected 40-char commit hash, got: $output"
}

@test "resolve_target_with_temporal: rejects upstream + target" {
  run resolve_target_with_temporal true "" "HEAD~1" "HEAD~2"
  assert_failure
  assert_output --partial "Cannot specify both --upstream and a target"
}

@test "resolve_target_with_temporal: rejects upstream + temporal" {
  run resolve_target_with_temporal true "3 days ago" "" "HEAD~2"
  assert_failure
  assert_output --partial "Cannot specify both --upstream and --temporal"
}

@test "resolve_target_with_temporal: rejects temporal + target" {
  run resolve_target_with_temporal false "3 days ago" "HEAD~1" "HEAD~2"
  assert_failure
  assert_output --partial "Cannot specify both --temporal and a target"
}
