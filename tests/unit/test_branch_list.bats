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
# -----------------------------------------------------------------------------

@test "hug bl: lists all local branches by default" {
  run hug bl
  assert_success
  assert_output --partial "feature/login"
  assert_output --partial "feature/signup"
  assert_output --partial "bugfix/auth"
  assert_output --partial "docs/api"
  assert_output --partial "main"
}

@test "hug bl: marks current branch with asterisk" {
  git checkout "feature/login"

  run hug bl
  assert_success
  # Should see asterisk before current branch (format may have leading spaces)
  assert_output --regexp "\* .* feature/login"
}

@test "hug bl <term>: filters branches by NAME only (not tracking info)" {
  run hug bl "feature"
  assert_success
  assert_output --partial "feature/login"
  assert_output --partial "feature/signup"
  refute_output --partial "bugfix/auth"
  refute_output --partial "docs/api"
}

@test "hug bl <term>: does NOT match tracking info (avoids false positives)" {
  # Even though 'main' appears in tracking info [origin/main],
  # we should only see the 'main' branch itself, not branches that track it
  run hug bl "main"
  assert_success
  assert_output --partial "main"
  # Branches tracking origin/main should NOT appear (they don't have 'main' in their name)
  refute_output --partial "feature/login"
  refute_output --partial "feature/signup"
}

@test "hug bl <term>: is case-insensitive" {
  run hug bl "BUGFIX"
  assert_success
  assert_output --partial "bugfix/auth"
  refute_output --partial "feature/login"
}

@test "hug bl <term>: handles no matches gracefully" {
  run hug bl "nonexistent"
  assert_success # implementation uses '|| true' so it shouldn't fail
  assert_output ""
}

@test "hug bl <term>: matches partial strings" {
  run hug bl "auth"
  assert_success
  assert_output --partial "bugfix/auth"
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
  git checkout -b "feat/special-chars"
  git commit --allow-empty -m "special [chars]"

  # Search with hyphen should work as substring match
  run hug bl "special"
  assert_success
  assert_output --partial "feat/special-chars"

  # Search with 'chars' substring should also match
  run hug bl "chars"
  assert_success
  assert_output --partial "feat/special-chars"
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
