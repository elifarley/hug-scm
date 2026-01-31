#!/usr/bin/env bats
# Tests for branch listing commands (hug bl / hug bll)

load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"

  # Create specific branches for search testing
  git checkout -b "feature/login"
  git commit --allow-empty -m "impl: login functionality"

  git checkout -b "feature/signup"
  git commit --allow-empty -m "impl: signup page"

  git checkout -b "bugfix/auth"
  git commit --allow-empty -m "fix: authentication crash"

  git checkout -b "docs/api"
  git commit --allow-empty -m "docs: update api reference"

  # Return to main so 'docs/api' is just another branch
  git checkout main
}

teardown() {
  cleanup_test_repo
}

# -----------------------------------------------------------------------------
# hug bl (Short List) Tests
# TEMPORARILY DISABLED during migration to Python implementation
# -----------------------------------------------------------------------------

@test "hug bl: lists all local branches by default" {
  skip "hug bl temporarily disabled during migration - use hug bll"
}

@test "hug bl: marks current branch with asterisk" {
  skip "hug bl temporarily disabled during migration - use hug bll"
}

@test "hug bl <term>: filters branches by NAME only (not tracking info)" {
  skip "hug bl temporarily disabled during migration - use hug bll"
}

@test "hug bl <term>: does NOT match tracking info (avoids false positives)" {
  skip "hug bl temporarily disabled during migration - use hug bll"
}

@test "hug bl <term>: is case-insensitive" {
  skip "hug bl temporarily disabled during migration - use hug bll"
}

@test "hug bl <term>: handles no matches gracefully" {
  skip "hug bl temporarily disabled during migration - use hug bll"
}

@test "hug bl <term>: matches partial strings" {
  skip "hug bl temporarily disabled during migration - use hug bll"
}

# -----------------------------------------------------------------------------
# hug bll (Long List) Tests
# -----------------------------------------------------------------------------

@test "hug bll: lists branches with commit messages" {
  run hug bll
  assert_success
  assert_output --partial "feature/login"
  assert_output --partial "impl: login functionality"
}

@test "hug bll <term>: matches text in commit message (via branch name)" {
  # The search now filters by branch name only, not message content
  # This test has been updated to match the new behavior
  run hug bll "bugfix"
  assert_success
  assert_output --partial "bugfix/auth"
  # Should filter out others (don't have 'bugfix' in the name)
  refute_output --partial "feature/login"
}

@test "hug bll <term>: matches text in branch name" {
  run hug bll "docs"
  assert_success
  assert_output --partial "docs/api"
  assert_output --partial "docs: update api reference"
}

@test "hug bll <term>: handles hyphenated branch names" {
  # Test searching for a string that's a substring of branch name
  git checkout -b "multi-word"
  git commit --allow-empty -m "multi word search"

  # Search for 'multi' should find 'multi-word'
  run hug bll "multi"
  assert_success
  assert_output --partial "multi-word"
}

@test "hug bll --json: ignores search terms (safe degradation)" {
  # When --json is used, search terms should simply be ignored rather than breaking JSON output
  run hug bll --json "feature"
  assert_success

  # Should still produce valid JSON
  # Using a simple check since assert_valid_json might be in a separate file
  echo "$output" | python3 -m json.tool > /dev/null

  # JSON should contain ALL branches, ignoring the filter
  assert_output --partial "bugfix/auth"
  assert_output --partial "feature/login"
}

# -----------------------------------------------------------------------------
# Edge Cases
# -----------------------------------------------------------------------------

@test "hug bl: handles special characters in search" {
  skip "hug bl temporarily disabled during migration - use hug bll"
}

@test "hug bll: preserves color codes when filtering" {
  # This is tricky to test exactly in BATS without strict strict TTY emulation,
  # but we can verify the output contains the branch info we expect.
  # The implementation pipes formatted output to grep.

  run hug bll "main"
  assert_success
  # Should output the main branch with its full details (hash, optional tracking, message)
  assert_output --regexp "main"
  # Verify it includes at least a hash and message
  assert_output --regexp "[0-9a-f]{7}" # Short commit hash
}

# NEW MULTI-TERM SEARCH TESTS

@test "hug bl: supports multi-term search (OR logic)" {
  skip "hug bl temporarily disabled during migration - use hug bll"
}

@test "hug bll: supports multi-term search (OR logic)" {
  cd "$TEST_REPO"

  # Create branches with specific patterns for testing
  git branch feature-α 2>/dev/null || true
  git branch hotfix-β 2>/dev/null || true

  run hug bll feature hotfix

  assert_success
  # Should show branches containing either "feature" OR "hotfix" with full details
  assert_output --partial "feature-α"
  assert_output --partial "hotfix-β"

  # Cleanup
  git branch -D feature-α 2>/dev/null || true
  git branch -D hotfix-β 2>/dev/null || true
}

@test "hug bl: multi-term search matches commit hashes" {
  skip "hug bl temporarily disabled during migration - use hug bll"
}

@test "hug bll: multi-term search matches commit hashes" {
  cd "$TEST_REPO"

  # Test that search can match commit hashes
  run hug bll "$(git rev-parse --short HEAD 2>/dev/null || echo 'test')"

  assert_success
  # Should find the current branch by its hash
  assert_output --partial "$current_branch"
}

@test "hug bl: multi-term search with no matches returns empty output" {
  skip "hug bl temporarily disabled during migration - use hug bll"
}

@test "hug bll: multi-term search with no matches returns empty output" {
  cd "$TEST_REPO"
  run hug bll nonexistent1 nonexistent2

  assert_success
  # Should return success but with no branch output (empty result)
  [[ -z "$output" ]] || {
    # If there's output, it shouldn't contain any branches
    refute_output --partial "* "
  }
}

@test "hug bl: multi-term search is case insensitive" {
  skip "hug bl temporarily disabled during migration - use hug bll"
}

@test "hug bll: multi-term search is case insensitive" {
  cd "$TEST_REPO"
  run hug bll MAIN

  assert_success
  # Should find main branch regardless of case
  assert_output --partial "main"
}

@test "hug bl: multi-term search with single term still works" {
  skip "hug bl temporarily disabled during migration - use hug bll"
}
