#!/usr/bin/env bats

setup() {
  load '../test_helper'

  # Create a test repository with multiple branches
  TEST_REPO=$(create_test_repo_with_branches)
  cd "$TEST_REPO"

  # Create test worktrees
  FEATURE_WT=$(create_test_worktree "feature-1" "$TEST_REPO")
  HOTFIX_WT=$(create_test_worktree "hotfix-1" "$TEST_REPO")
}

teardown() {
  cleanup_test_worktrees "$TEST_REPO"
  cleanup_test_repo "$TEST_REPO"
}

@test "hug wt: shows help when --help flag is used" {
  run git-wt --help
  assert_success
  assert_output --partial "hug wt: Git worktree management"
}

@test "hug wt: shows no worktrees message when repository has no worktrees" {
  # Clean up existing worktrees
  cleanup_test_worktrees "$TEST_REPO"

  run git-wt
  assert_success
  assert_output --partial "No worktrees found"
  assert_output --partial "hug wtc <branch>"
}

@test "hug wt: lists worktrees with current indication" {
  # Run from main repository
  cd "$TEST_REPO"
  run git-wt --summary

  assert_success
  # 3 total worktrees (main + 2 additional) = count shows 2
  assert_output --partial "Worktrees (2)"
  assert_output --partial "[CURRENT]"
  assert_output --partial "main"
  assert_output --partial "feature-1"
  assert_output --partial "hotfix-1"
}

@test "hug wt: shows interactive menu with multiple worktrees" {
  # Since we have <10 worktrees, this uses numbered menu, not gum
  # Use EOF simulation to test the interactive selection behavior
  run bash -c "echo | git-wt 2>&1"

  # Should show interactive menu and handle cancellation gracefully
  assert_success
  assert_output --partial "Select worktree to switch to"
  assert_output --partial "Enter number"
  assert_output --partial "Worktree selection cancelled"
}

@test "hug wt: detects dirty worktrees" {
  # Make feature worktree dirty
  echo "dirty changes" > "$FEATURE_WT/dirty.txt"

  cd "$TEST_REPO"
  run git-wt --summary

  assert_success
  assert_output --partial "[DIRTY]"
  assert_output --partial "feature-1"
}

@test "hug wt: shows JSON output" {
  cd "$TEST_REPO"
  run git-wt --json

  assert_success
  assert_valid_json
  assert_json_has_key '.worktrees'
  assert_json_has_key '.current'
  assert_json_has_key '.count'
  # Count shows ADDITIONAL worktrees only (excludes main)
  # 3 total worktrees (main + feature-1 + hotfix-1) = 2 additional
  assert_json_value '.count' '2'
}

@test "hug wt: JSON output includes worktree details" {
  cd "$TEST_REPO"
  run git-wt --json

  assert_success
  assert_valid_json

  # Check that worktrees array has correct structure
  assert_json_type '.worktrees' 'array'
  assert_json_array_length '.worktrees' 3

  # Check individual worktree has required fields
  assert_json_has_key '.worktrees[0].path'
  assert_json_has_key '.worktrees[0].branch'
  assert_json_has_key '.worktrees[0].commit'
  assert_json_has_key '.worktrees[0].dirty'
  assert_json_has_key '.worktrees[0].locked'
  assert_json_has_key '.worktrees[0].current'
}

@test "hug wt: identifies current worktree in JSON output" {
  cd "$TEST_REPO"
  run git-wt --json

  assert_success
  assert_valid_json

  # Should have exactly one current worktree
  local current_count
  current_count=$(echo "$output" | jq '[.worktrees[] | select(.current == true)] | length')
  [[ "$current_count" == "1" ]] || fail "Expected exactly 1 current worktree, got $current_count"

  # Current worktree should be the main repository
  local current_path
  current_path=$(echo "$output" | jq -r '.current')
  [[ "$current_path" == "$TEST_REPO" ]] || fail "Current path mismatch: $current_path != $TEST_REPO"
}

@test "hug wt: handles empty repository (no worktrees) in JSON mode" {
  # Clean up additional worktrees (main worktree will remain)
  cleanup_test_worktrees "$TEST_REPO"

  cd "$TEST_REPO"
  run git-wt --json

  assert_success
  assert_valid_json
  # Should have 1 worktree in array (main worktree only)
  assert_json_array_length '.worktrees' 1
  # But count shows 0 (no additional worktrees)
  assert_json_value '.count' '0'
}

@test "hug wt: error when not in git repository" {
  cd /tmp
  run git-wt

  assert_failure
  assert_output --partial "Not in a git repository"
}

@test "hug wt: switches to worktree when path is provided" {
  cd "$TEST_REPO"
  run git-wt "$FEATURE_WT"

  # Note: We can't test actual directory change in bats, but we can validate the path
  assert_success
}

@test "hug wt: fails when switching to non-existent worktree" {
  cd "$TEST_REPO"
  run git-wt "/nonexistent/path"

  assert_failure
  assert_output --partial "Cannot switch to worktree"
}

# Tests for hug wtl (short worktree listing)

@test "hug wtl: shows help when --help flag is used" {
  run git-wtl --help
  assert_success
  assert_output --partial "hug wtl: List worktrees in short format"
}

@test "hug wtl: lists worktrees in short format" {
  cd "$TEST_REPO"
  run git-wtl

  assert_success
  assert_output --partial "Worktrees:"
  assert_output --partial "* main"
  assert_output --partial "feature-1"
  assert_output --partial "hotfix-1"
  assert_output --partial "("  # Should show commit in parentheses
}

@test "hug wtl: highlights current worktree with asterisk" {
  cd "$TEST_REPO"
  run git-wtl

  assert_success
  # Current worktree should have green asterisk (visible in raw output)
  assert_output --partial "* main"
}

@test "hug wtl: shows dirty worktree indicator" {
  # Make feature worktree dirty
  echo "dirty changes" > "$FEATURE_WT/dirty.txt"

  cd "$TEST_REPO"
  run git-wtl

  assert_success
  assert_output --partial "[DIRTY]"
  assert_output --partial "feature-1"
}

@test "hug wtl: filters worktrees by search term" {
  cd "$TEST_REPO"
  run git-wtl feature

  assert_success
  assert_output --partial "feature-1"
  refute_output --partial "main"
  refute_output --partial "hotfix"
}

@test "hug wtl: filters worktrees by path" {
  cd "$TEST_REPO"
  run git-wtl "$(basename "$FEATURE_WT")"

  assert_success
  assert_output --partial "feature-1"
  refute_output --partial "main"
}

@test "hug wtl: case-insensitive search" {
  cd "$TEST_REPO"
  run git-wtl FEATURE

  assert_success
  assert_output --partial "feature-1"
  refute_output --partial "main"
}

@test "hug wtl: handles no matching search term" {
  cd "$TEST_REPO"
  run git-wtl nonexistent

  # Should fail when no worktrees match the search term
  assert_failure
  assert_output --partial "No worktrees found matching"
}

@test "hug wtl: handles repository with no worktrees" {
  # Clean up worktrees
  cleanup_test_worktrees "$TEST_REPO"

  cd "$TEST_REPO"
  run git-wtl

  assert_success
  assert_output --partial "Worktrees:"
  assert_output --partial "* main"
}

@test "hug wtl: error when not in git repository" {
  cd /tmp
  run git-wtl

  assert_failure
  assert_output --partial "Not in a git repository"
}

# Tests for hug wtll (long worktree listing)

@test "hug wtll: shows help when --help flag is used" {
  run git-wtll --help
  assert_success
  assert_output --partial "hug wtll: List worktrees in long format"
}

@test "hug wtll: lists worktrees in long format with commit subjects" {
  cd "$TEST_REPO"
  run git-wtll

  assert_success
  assert_output --partial "Worktrees (long format):"
  assert_output --partial "* main"
  assert_output --partial "feature-1"
  assert_output --partial "hotfix-1"
  assert_output --partial "Status:"  # Should show status details
}

@test "hug wtll: shows commit subjects for worktrees" {
  cd "$TEST_REPO"
  run git-wtll

  assert_success
  # Should show commit subjects (check for commits from test helper)
  assert_output --partial "initial commit"
  assert_output --partial "Status:"
}

@test "hug wtll: highlights current worktree with asterisk" {
  cd "$TEST_REPO"
  run git-wtll

  assert_success
  assert_output --partial "* main"
}

@test "hug wtll: shows detailed status for dirty worktrees" {
  # Make feature worktree dirty
  echo "dirty changes" > "$FEATURE_WT/dirty.txt"

  cd "$TEST_REPO"
  run git-wtll

  assert_success
  assert_output --partial "[DIRTY]"
  assert_output --partial "feature-1"
  assert_output --partial "Status: Modified"
}

@test "hug wtll: filters worktrees by search term" {
  cd "$TEST_REPO"
  run git-wtll feature

  assert_success
  assert_output --partial "feature-1"
  refute_output --partial "main"
  refute_output --partial "hotfix"
}

@test "hug wtll: handles repository with no worktrees" {
  # Clean up worktrees
  cleanup_test_worktrees "$TEST_REPO"

  cd "$TEST_REPO"
  run git-wtll

  assert_success
  assert_output --partial "Worktrees (long format):"
  assert_output --partial "* main"
}

@test "hug wtll: error when not in git repository" {
  cd /tmp
  run git-wtll

  assert_failure
  assert_output --partial "Not in a git repository"
}

# Tests for hug wtl/wtll JSON output

@test "hug wtl: supports --json output" {
  cd "$TEST_REPO"
  run git-wtl --json

  assert_success
  assert_valid_json
  assert_json_has_key '.worktrees'
  assert_json_has_key '.current'
  assert_json_has_key '.count'
  # wtl excludes main, so 3 total - 1 main = 2 additional
  assert_json_value '.count' '2'
}

@test "hug wtll: supports --json output" {
  cd "$TEST_REPO"
  run git-wtll --json

  assert_success
  assert_valid_json
  assert_json_has_key '.worktrees'
  assert_json_has_key '.current'
  assert_json_has_key '.count'
  # wtll excludes main, so 3 total - 1 main = 2 additional
  assert_json_value '.count' '2'
}

@test "hug wtl: JSON output includes required fields" {
  cd "$TEST_REPO"
  run git-wtl --json

  assert_success
  assert_valid_json

  # Check that worktrees array has correct structure
  assert_json_type '.worktrees' 'array'
  # wtl excludes main, so 3 total - 1 main = 2 additional
  assert_json_array_length '.worktrees' 2

  # Check individual worktree has required fields
  assert_json_has_key '.worktrees[0].path'
  assert_json_has_key '.worktrees[0].branch'
  assert_json_has_key '.worktrees[0].commit'
  assert_json_has_key '.worktrees[0].dirty'
  assert_json_has_key '.worktrees[0].locked'
  assert_json_has_key '.worktrees[0].current'
}

@test "hug wtll: JSON output includes search filtering" {
  cd "$TEST_REPO"
  run git-wtll --json feature

  assert_success
  assert_valid_json
  assert_json_array_length '.worktrees' 1
  assert_json_value '.worktrees[0].branch' 'feature-1'
}

@test "hug wtl: JSON output handles no worktrees" {
  # Clean up additional worktrees (main remains)
  cleanup_test_worktrees "$TEST_REPO"

  cd "$TEST_REPO"
  run git-wtl --json

  assert_success
  assert_valid_json
  # wtl excludes main, so should be 0
  assert_json_array_length '.worktrees' 0
  assert_json_value '.count' '0'
}

@test "hug wtll: JSON output handles no worktrees" {
  # Clean up additional worktrees (main remains)
  cleanup_test_worktrees "$TEST_REPO"

  cd "$TEST_REPO"
  run git-wtll --json

  assert_success
  assert_valid_json
  # wtll excludes main, so should be 0
  assert_json_array_length '.worktrees' 0
  assert_json_value '.count' '0'
}

# NEW MULTI-TERM SEARCH TESTS

@test "hug wtl: supports multi-term search (OR logic)" {
  cd "$TEST_REPO"
  run git-wtl feature hotfix

  assert_success
  # Should show worktrees containing either "feature" OR "hotfix"
  assert_output --partial "feature-1"
  assert_output --partial "hotfix-1"
}

@test "hug wtl: multi-term search matches path or branch" {
  cd "$TEST_REPO"
  # Create worktree with specific path pattern
  local special_wt="${TEST_REPO}-special-feature"
  git branch special-feature
  git worktree add "$special_wt" special-feature

  run git-wtll special feature

  assert_success
  assert_output --partial "special-feature"

  # Cleanup
  git worktree remove "$special_wt"
  git branch -D special-feature
}

@test "hug wtll: supports multi-term search (OR logic)" {
  cd "$TEST_REPO"
  run git-wtll feature hotfix

  assert_success
  # Should show worktrees containing either "feature" OR "hotfix"
  assert_output --partial "feature-1"
  assert_output --partial "hotfix-1"
}

@test "hug wtl: multi-term search with no matches returns error" {
  cd "$TEST_REPO"
  run git-wtl nonexistent1 nonexistent2

  assert_failure
  assert_output --partial "No worktrees found matching"
}

@test "hug wtll: multi-term search with no matches returns error" {
  cd "$TEST_REPO"
  run git-wtll nonexistent1 nonexistent2

  assert_failure
  assert_output --partial "No worktrees found matching"
}

@test "hug wtl: multi-term search is case insensitive" {
  cd "$TEST_REPO"
  run git-wtl FEATURE HOTFIX

  assert_success
  # Should find branches regardless of case
  assert_output --partial "feature-1"
  assert_output --partial "hotfix-1"
}

@test "hug wtll: multi-term search is case insensitive" {
  cd "$TEST_REPO"
  run git-wtll FEATURE HOTFIX

  assert_success
  # Should find branches regardless of case
  assert_output --partial "feature-1"
  assert_output --partial "hotfix-1"
}

@test "hug wtl: JSON output supports multi-term search filtering" {
  cd "$TEST_REPO"
  run git-wtl --json feature

  assert_success
  assert_valid_json
  # Matches feature-1 only (1 additional worktree)
  assert_json_array_length '.worktrees' 1
  assert_json_value '.count' '1'
}

@test "hug wtll: JSON output supports multi-term search filtering" {
  cd "$TEST_REPO"
  run git-wtll --json feature

  assert_success
  assert_valid_json
  # Matches feature-1 only (1 additional worktree)
  assert_json_array_length '.worktrees' 1
  assert_json_value '.count' '1'
}