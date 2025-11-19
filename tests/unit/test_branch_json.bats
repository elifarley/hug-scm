#!/usr/bin/env bats

# Test JSON output for branch commands (hug bll)

setup() {
  create_test_repo_with_history
  load_test_helpers
}

teardown() {
  cleanup_test_repo
}

@test "hug bll --json: basic JSON structure" {
  # Arrange
  git checkout main

  # Act
  run hug bll --json

  # Assert
  assert_success
  assert_output --partial '"repository"'
  assert_output --partial '"timestamp"'
  assert_output --partial '"command":"hug bll --json"'
  assert_output --partial '"branches"'

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
}

@test "hug bll --json: includes current branch marker" {
  # Arrange
  git checkout main

  # Act
  run hug bll --json

  # Assert
  assert_success
  assert_output --partial '"current_branch":"main"'
  assert_output --partial '"current":true'
  assert_output --partial '"name":"main"'

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
}

@test "hug bll --json: branch with upstream tracking" {
  # Arrange - create a remote branch scenario
  git checkout -b feature/test
  git commit --allow-empty -m "Test commit"

  # Act
  run hug bll --json

  # Assert
  assert_success
  assert_output --partial '"name":"feature/test"'
  assert_output --partial '"current":true'

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
}

@test "hug bll --json: multiple branches" {
  # Arrange - ensure we have multiple branches
  git checkout main
  git checkout -b feature1
  git checkout main
  git checkout -b feature2

  # Act
  run hug bll --json

  # Assert
  assert_success
  # Should have at least 3 branches (main, feature1, feature2)
  local branch_count
  branch_count=$(echo "$output" | jq '.branches | length')
  [ "$branch_count" -ge 3 ]

  # Should include all branch names
  assert_output --partial '"name":"main"'
  assert_output --partial '"name":"feature1"'
  assert_output --partial '"name":"feature2"'

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
}

@test "hug bll --json: branch object structure" {
  # Arrange
  git checkout main

  # Act
  run hug bll --json

  # Assert
  assert_success
  # Check branch object fields
  assert_output --partial '"hash"'  # Should have short hash
  assert_output --partial '"subject"'  # Should have commit subject
  assert_output --partial '"name"'    # Should have branch name
  assert_output --partial '"current"'  # Should have current branch marker

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
}

@test "hug bll --json: no ANSI colors in JSON" {
  # Arrange
  git checkout main

  # Act
  run hug bll --json

  # Assert
  assert_success
  refute_output --partial $'\e['  # No ANSI escape codes

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "JSON should be clean without ANSI codes"
}

@test "hug bll --json: handles repository with single branch" {
  # Arrange - new repo with only main branch
  create_test_repo
  git commit --allow-empty -m "Initial commit"

  # Act
  run hug bll --json

  # Assert
  assert_success
  local branch_count
  branch_count=$(echo "$output" | jq '.branches | length')
  [ "$branch_count" -eq 1 ]

  assert_output --partial '"name":"main"'

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
}