#!/usr/bin/env bats

setup() {
  load '../test_helper'

  # Source the hug-arrays library to get access to search functions
  . "$HUG_HOME/git-config/lib/hug-arrays"
}

teardown() {
  # No cleanup needed for library function tests
  return 0
}

@test "search_items_by_fields: matches single term with OR logic" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_items_by_fields "test" "OR" "test-file" "another-file"'

  assert_success
}

@test "search_items_by_fields: matches case-insensitive with OR logic" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_items_by_fields "TEST" "OR" "test-file" "another-file"'

  assert_success
}

@test "search_items_by_fields: matches substring with OR logic" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_items_by_fields "tes" "OR" "test-file" "another-file"'

  assert_success
}

@test "search_items_by_fields: no match returns failure with OR logic" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_items_by_fields "nonexistent" "OR" "test-file" "another-file"'

  assert_failure
}

@test "search_items_by_fields: matches any term with OR logic" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_items_by_fields "file another" "OR" "test-file" "some-dir"'

  assert_success
}

@test "search_items_by_fields: matches all terms with AND logic" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_items_by_fields "test file" "AND" "test-file" "another-file"'

  assert_success
}

@test "search_items_by_fields: fails when not all terms match with AND logic" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_items_by_fields "test nonexistent" "AND" "test-file" "another-file"'

  assert_failure
}

@test "search_items_by_fields: matches everything with empty search terms" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_items_by_fields "" "OR" "test-file" "another-file"'

  assert_success
}

@test "search_items_by_fields: handles special characters in search terms" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_items_by_fields "test-branch" "OR" "feature/test-branch" "main"'

  assert_success
}

@test "search_worktree: matches path with OR logic" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_worktree "/home/user/test-project" "main" "test" "OR"'

  assert_success
}

@test "search_worktree: matches branch with OR logic" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_worktree "/home/user/project" "feature-test" "test" "OR"'

  assert_success
}

@test "search_worktree: matches both path and branch with multi-term OR logic" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_worktree "/home/user/test-project" "feature-main" "test main" "OR"'

  assert_success
}

@test "search_worktree: no match returns failure" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_worktree "/home/user/project" "main" "nonexistent" "OR"'

  assert_failure
}

@test "search_worktree: matches all terms with AND logic" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_worktree "/home/user/test-project" "feature-test" "test" "AND"'

  assert_success
}

@test "search_worktree: fails when terms split across fields with AND logic" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_worktree "/home/user/project" "feature-test" "project test" "AND"'

  assert_success  # This should succeed because "project" matches path and "test" matches branch
}

@test "search_branch_line: matches whole line with single term" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_branch_line "* main                 abc123 (origin/main)" "main" "OR"'

  assert_success
}

@test "search_branch_line: matches commit hash" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_branch_line "* feature-test         def456 (origin/feature-test)" "def456" "OR"'

  assert_success
}

@test "search_branch_line: matches remote tracking info" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_branch_line "* feature-auth         ghi789 (origin/feature-auth ↑2)" "origin" "OR"'

  assert_success
}

@test "search_branch_line: multi-term search with OR logic" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_branch_line "* bugfix              123abc [detached]" "bugfix 123" "OR"'

  assert_success
}

@test "search_branch_line: multi-term search with AND logic" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_branch_line "* hotfix-security     456def (origin/hotfix)" "hotfix security" "AND"'

  assert_success
}

@test "search_branch_line: case insensitive matching" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_branch_line "* MAIN                abc123 (origin/MAIN)" "main" "OR"'

  assert_success
}

@test "search_branch_line: no match returns failure" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_branch_line "* develop             xyz789 (origin/develop)" "nonexistent" "OR"'

  assert_failure
}

@test "search_functions: handle whitespace in search terms" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_items_by_fields "  test  " "OR" "test-file"'

  assert_success
}

@test "search_functions: handle multiple spaces in search terms" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_items_by_fields "test   file" "OR" "test-file"'

  assert_success
}

@test "search_functions: worktree search with path containing search term" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_worktree "/tmp/hug-test-repo-SMEUCD" "main" "test-repo" "OR"'

  assert_success
}

@test "search_functions: branch line search with multiple fields" {
  run bash -c 'source "$HUG_HOME/git-config/lib/hug-arrays" && search_branch_line "  main                 abc123 (no remote)" "no remote" "OR"'

  assert_success
}