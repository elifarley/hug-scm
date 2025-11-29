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
  assert_output --partial "Worktrees (1 total)"
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