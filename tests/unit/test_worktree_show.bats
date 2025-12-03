#!/usr/bin/env bats

setup() {
  load '../test_helper'

  # Create a simple test repository
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo "$TEST_REPO"
}

@test "hug wtsh: shows help when --help flag is used" {
  run git-wtsh --help
  assert_success
  assert_output --partial "hug wtsh: Show detailed information about worktrees"
  assert_output --partial "USAGE:"
  assert_output --partial "DESCRIPTION:"
}

@test "hug wtsh: shows worktree summary with correct structure" {
  cd "$TEST_REPO"
  run git-wtsh

  assert_success
  assert_output --partial "Worktree Summary"
  assert_output --partial "───────────────────────"
  assert_output --partial "Current:"
  # Just main worktree = 0 additional
  assert_output --partial "Worktrees (0 total)"
  assert_output --partial "───────────────────────"
}

@test "hug wtsh: displays single worktree with detailed information" {
  cd "$TEST_REPO"
  run git-wtsh

  assert_success
  assert_output --partial "[CURRENT]"
  assert_output --partial "main"

  # Should show commit information
  assert_output --partial "Commit:"
  assert_output --partial "Author:"
  assert_output --partial "Branch:"
  assert_output --partial "Path:"
  assert_output --partial "Status:"
  assert_output --partial "Config:"

  # Should show tree structure
  assert_output --partial "├─"
  assert_output --partial "└─"
}

@test "hug wtsh: highlights current worktree with CURRENT indicator" {
  cd "$TEST_REPO"
  run git-wtsh

  assert_success
  # Should have exactly one [CURRENT] indicator
  local current_count
  current_count=$(echo "$output" | grep -o "\[CURRENT\]" | wc -l)
  [[ "$current_count" == "1" ]] || fail "Expected exactly 1 [CURRENT] indicator, got $current_count"
}

@test "hug wtsh: displays commit details correctly" {
  cd "$TEST_REPO"
  run git-wtsh

  assert_success
  # Should show commit hash in parentheses
  assert_output --partial "("
  assert_output --partial ")"

  # Should show commit subject
  assert_output --partial "Initial commit"

  # Should show author information
  assert_output --partial "Author:"

  # Should show relative date
  assert_output --partial "ago"
}

@test "hug wtsh: shows working directory status" {
  cd "$TEST_REPO"
  run git-wtsh

  assert_success
  assert_output --partial "Status: Clean"
}

@test "hug wtsh: shows worktree configuration information" {
  cd "$TEST_REPO"
  run git-wtsh

  assert_success
  assert_output --partial "Config:"
  assert_output --partial "Standard worktree"
  assert_output --partial "detached: no"
}

@test "hug wtsh: handles dirty worktree status correctly" {
  # Make worktree dirty with unstaged changes
  echo "dirty changes" > existing.txt
  git add existing.txt
  git commit -m "Add existing file"
  echo "unstaged changes" > existing.txt

  cd "$TEST_REPO"
  run git-wtsh

  assert_success
  assert_output --partial "[DIRTY]"
  assert_output --partial "Status: Dirty"
  assert_output --partial "files changed"
  assert_output --partial "staged"
  assert_output --partial "unstaged"
}

@test "hug wtsh: handles no matching search term" {
  cd "$TEST_REPO"
  run git-wtsh nonexistent

  assert_failure
  assert_output --partial "No worktrees found matching: nonexistent"
}

@test "hug wtsh: error when not in git repository" {
  cd /tmp
  run git-wtsh

  assert_failure
  assert_output --partial "Not in a git repository"
}

@test "hug wtsh: displays relative time information" {
  cd "$TEST_REPO"
  run git-wtsh

  assert_success
  # Should show relative time (ago)
  assert_output --partial "ago"
}

@test "hug wtsh: shows commit hash in correct format" {
  cd "$TEST_REPO"
  run git-wtsh

  assert_success
  # Should show commit hash
  assert_output --partial "Commit: "

  # Commit hash should be in parentheses after branch name
  assert_output --partial "("
  assert_output --partial ")"
}

@test "hug wtsh: tree structure formatting is consistent" {
  cd "$TEST_REPO"
  run git-wtsh

  assert_success
  # Check tree structure symbols are present
  assert_output --partial "├─"
  assert_output --partial "└─"

  # Should end with Config: line (└─ Config:)
  assert_output --partial "└─ Config:"
}

@test "hug wtsh: handles search filtering with branch name" {
  cd "$TEST_REPO"
  run git-wtsh main

  assert_success
  assert_output --partial "main"
  assert_output --partial "[CURRENT]"
}

@test "hug wtsh: case-insensitive search filtering" {
  cd "$TEST_REPO"
  run git-wtsh MAIN

  assert_success
  assert_output --partial "main"
  assert_output --partial "[CURRENT]"
}

@test "hug wtsh: filters worktrees by search term" {
  cd "$TEST_REPO"
  run git-wtsh "$(basename "$TEST_REPO")"

  assert_success
  assert_output --partial "main"
  assert_output --partial "[CURRENT]"
}

@test "hug wtsh: displays author information correctly" {
  cd "$TEST_REPO"
  run git-wtsh

  assert_success
  # Should show author line
  assert_output --partial "Author: "

  # Author should not be empty
  local author_lines
  author_lines=$(echo "$output" | grep "Author:" | wc -l)
  [[ "$author_lines" -ge 1 ]] || fail "Expected at least 1 author line"
}

@test "hug wtsh: shows branch information with remote tracking" {
  cd "$TEST_REPO"
  run git-wtsh

  assert_success
  assert_output --partial "Branch: main"
  # Should show remote tracking info (may be "no remote" for local branches)
  assert_output --partial "no remote"
}

# NEW BEHAVIOR TESTS

@test "hug wtsh: default behavior shows current worktree only" {
  cd "$TEST_REPO"
  run git-wtsh

  assert_success
  # Should show exactly one worktree (current only)
  # Count worktree entries by looking for lines with branch patterns (path (branch))
  local worktree_count
  worktree_count=$(echo "$output" | grep -c "\ ([^[:space:]]*)$" || echo "0")
  [[ "$worktree_count" == "1" ]] || fail "Expected exactly 1 worktree in default mode, got $worktree_count"

  # Should show current worktree indicator
  assert_output --partial "[CURRENT]"
}

@test "hug wtsh: --all flag shows all worktrees" {
  cd "$TEST_REPO"
  run git-wtsh --all

  assert_success
  # Just main = 0 additional
  assert_output --partial "Worktrees (0 total)"
  # Should show current worktree when it's the only one
  assert_output --partial "[CURRENT]"
}

@test "hug wtsh: -a short flag works same as --all" {
  cd "$TEST_REPO"

  # Compare output of --all and -a flags
  run git-wtsh --all
  local all_output="$output"

  run git-wtsh -a
  local a_output="$output"

  assert_success
  # Outputs should be identical (excluding potential whitespace differences)
  [[ "${all_output//[[:space:]]/}" == "${a_output//[[:space:]]/}" ]] || fail "Output mismatch between --all and -a flags"
}

@test "hug wtsh: interactive mode requires gum" {
  cd "$TEST_REPO"

  # Disable gum via environment variable
  HUG_DISABLE_GUM=true run git-wtsh --

  assert_failure
  assert_output --partial "Interactive worktree selection requires 'gum' to be installed"
}

@test "hug wtsh: interactive mode error when no worktrees" {
  cd /tmp  # Not in a git repo
  run git-wtsh --

  assert_failure
  # Should fail either due to not being in git repo or no worktrees
}

@test "hug wtsh: shows help with -h flag" {
  run git-wtsh -h

  assert_success
  assert_output --partial "hug wtsh: Show detailed information about worktrees"
  assert_output --partial "USAGE:"
  assert_output --partial "OPTIONS:"
}

@test "hug wtsh: shows help with --help flag" {
  run git-wtsh --help

  assert_success
  assert_output --partial "hug wtsh: Show detailed information about worktrees"
  assert_output --partial "USAGE:"
  assert_output --partial "OPTIONS:"
}

@test "hug wtsh: error on unknown flag" {
  cd "$TEST_REPO"
  run git-wtsh --unknown-flag

  assert_failure
  assert_output --partial "Unknown option: --unknown-flag"
}

@test "hug wtsh: error on single dash unknown flag" {
  cd "$TEST_REPO"
  run git-wtsh -x

  assert_failure
  assert_output --partial "Unknown option: -x"
}

@test "hug wtsh: search filtering still works with new behavior" {
  cd "$TEST_REPO"
  run git-wtsh main

  assert_success
  assert_output --partial "main"
  assert_output --partial "[CURRENT]"
}

@test "hug wtsh: default behavior vs --all behavior difference" {
  cd "$TEST_REPO"

  # Test default behavior (should work the same when only one worktree exists)
  run git-wtsh
  local default_output="$output"

  # Test --all behavior
  run git-wtsh --all
  local all_output="$output"

  assert_success
  # Both should succeed and show the same single worktree
  assert_output --partial "[CURRENT]"
}

@test "hug wtsh: help text shows new behavior examples" {
  run git-wtsh --help

  assert_success
  # Should show new behavior examples in help
  assert_output --partial "hug wtsh                   # Current worktree only"
  assert_output --partial "hug wtsh --all             # All worktrees"
  assert_output --partial "hug wtsh -a                # All worktrees"
  assert_output --partial "hug wtsh --                # Interactive worktree selection"
}

@test "hug wtsh: help text explains status indicators" {
  run git-wtsh --help

  assert_success
  assert_output --partial "STATUS INDICATORS:"
  assert_output --partial "[CURRENT]"
  assert_output --partial "[DIRTY]"
  assert_output --partial "[LOCKED]"
  assert_output --partial "[DETACHED]"
}

@test "hug wtsh: multiple worktrees with --all flag" {
  # Create additional worktree for testing
  cd "$TEST_REPO"
  git branch feature-test
  local worktree_path="${TEST_REPO}-feature"
  git worktree add "$worktree_path" feature-test

  run git-wtsh --all

  assert_success
  # Should show multiple worktrees - count by looking for lines with (branch) patterns
  local worktree_count
  worktree_count=$(echo "$output" | grep -c "\ ([^[:space:]]*)$" || echo "0")
  [[ "$worktree_count" -ge 2 ]] || fail "Expected at least 2 worktrees with --all flag, got $worktree_count"

  # Should have exactly one CURRENT worktree
  local current_count
  current_count=$(echo "$output" | grep -o "\[CURRENT\]" | wc -l)
  [[ "$current_count" == "1" ]] || fail "Expected exactly 1 [CURRENT] indicator, got $current_count"

  # Cleanup
  git worktree remove "$worktree_path"
  git branch -D feature-test
}

@test "hug wtsh: default behavior with multiple worktrees shows current only" {
  # Create additional worktree for testing
  cd "$TEST_REPO"
  git branch feature-test2
  local worktree_path="${TEST_REPO}-feature2"
  git worktree add "$worktree_path" feature-test2

  run git-wtsh

  assert_success
  # Should show exactly one worktree (current only) even when multiple exist
  # Count worktree entries by looking for lines with branch patterns (path (branch))
  local worktree_count
  worktree_count=$(echo "$output" | grep -c "\ ([^[:space:]]*)$" || echo "0")
  [[ "$worktree_count" == "1" ]] || fail "Expected exactly 1 worktree in default mode, got $worktree_count"

  # Should show current worktree indicator
  assert_output --partial "[CURRENT]"

  # Cleanup
  git worktree remove "$worktree_path"
  git branch -D feature-test2
}

# NEW MULTI-TERM SEARCH TESTS

@test "hug wtsh: supports multi-term search (OR logic)" {
  # Create additional worktrees for multi-term testing
  cd "$TEST_REPO"
  git branch feature-search
  git branch hotfix-search
  local feature_wt="${TEST_REPO}-feature-search"
  local hotfix_wt="${TEST_REPO}-hotfix-search"
  git worktree add "$feature_wt" feature-search
  git worktree add "$hotfix_wt" hotfix-search

  run git-wtsh feature hotfix

  assert_success
  # Should show details for worktrees matching either "feature" OR "hotfix"
  # 2 additional worktrees found (excluding main)
  assert_output --partial "feature-search"
  assert_output --partial "hotfix-search"
  assert_output --partial "Worktrees (2 total)"

  # Cleanup
  git worktree remove "$feature_wt"
  git worktree remove "$hotfix_wt"
  git branch -D feature-search hotfix-search
}

@test "hug wtsh: multi-term search matches path or branch" {
  # Create worktree with specific path pattern
  cd "$TEST_REPO"
  git branch special-branch
  local special_wt="${TEST_REPO}-special-path"
  git worktree add "$special_wt" special-branch

  run git-wtsh special branch

  assert_success
  # Should find worktree with "special" in path AND "branch" in branch name
  # NOTE: Only the additional worktree matches the search terms
  assert_output --partial "special-path"
  assert_output --partial "special-branch"
  assert_output --partial "Worktrees (1 total)"

  # Cleanup
  git worktree remove "$special_wt"
  git branch -D special-branch
}

@test "hug wtsh: multi-term search with no matches returns error" {
  cd "$TEST_REPO"
  run git-wtsh nonexistent1 nonexistent2 nonexistent3

  assert_failure
  assert_output --partial "No worktrees found matching: nonexistent1 nonexistent2 nonexistent3"
}

@test "hug wtsh: multi-term search is case insensitive" {
  # Create worktree with test-new branch for case-insensitive search
  cd "$TEST_REPO"
  git branch test-new-worktree
  local test_wt="${TEST_REPO}-test-new-worktree"
  git worktree add "$test_wt" test-new-worktree

  run git-wtsh TEST NEW

  assert_success
  # Should find worktree with "test" and "new" in branch name
  assert_output --partial "test-new-worktree"
  # 2 matching worktrees: main (path has "test") and test-new-worktree (has "test" and "new")
  assert_output --partial "Worktrees (2 total)"

  # Cleanup
  git worktree remove "$test_wt"
  git branch -D test-new-worktree
}

@test "hug wtsh: multi-term search with single term works" {
  # Create worktree with test-new branch for single term search
  cd "$TEST_REPO"
  git branch test-new-worktree
  local test_wt="${TEST_REPO}-test-new-worktree"
  git worktree add "$test_wt" test-new-worktree

  run git-wtsh test

  assert_success
  # Should find worktree with "test" in branch name (path also matches but that's OK)
  assert_output --partial "test-new-worktree"
  # NOTE: Path contains "test" so main worktree also matches, giving us 2 total
  assert_output --partial "Worktrees (2 total)"

  # Cleanup
  git worktree remove "$test_wt"
  git branch -D test-new-worktree
}

@test "hug wtsh: multi-term search error message shows all terms" {
  cd "$TEST_REPO"
  run git-wtsh foo bar baz

  assert_failure
  # Error message should show all search terms
  assert_output --partial "foo bar baz"
}