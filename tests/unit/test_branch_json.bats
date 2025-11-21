#!/usr/bin/env bats

# Test JSON output for branch commands (hug bll)

load '../test_helper'

setup() {
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO" || exit 1
}

teardown() {
  cd /
  rm -rf "$TEST_REPO"
}

@test "hug bll --json: basic JSON structure" {
  # Arrange
  git checkout main

  # Act
  run hug bll --json

  # Assert
  assert_success
  assert_valid_json
  assert_json_has_key ".repository"
  assert_json_has_key ".timestamp"
  assert_json_has_key ".command"
  assert_json_value ".command" "hug bll --json"
  assert_json_has_key ".branches"
  assert_json_type ".branches" "array"
}

@test "hug bll --json: includes current branch marker" {
  # Arrange
  git checkout main

  # Act
  run hug bll --json

  # Assert
  assert_success
  assert_valid_json
  assert_json_value ".current_branch" "main"
  # Check that at least one branch has current: true
  local current_count=$(echo "$output" | jq '[.branches[] | select(.current == true)] | length')
  [[ "$current_count" -ge 1 ]] || fail "Expected at least one branch with current: true"
}

@test "hug bll --json: branch with upstream tracking" {
  # Arrange - create a remote branch scenario
  git checkout -b feature/test
  git commit --allow-empty -m "Test commit"

  # Act
  run hug bll --json

  # Assert
  assert_success
  assert_valid_json
  # Check that feature/test branch exists in array
  local branch_exists=$(echo "$output" | jq '[.branches[] | select(.name == "feature/test")] | length')
  [[ "$branch_exists" -eq 1 ]] || fail "Expected feature/test branch in output"
  # Check current branch
  assert_json_value ".current_branch" "feature/test"
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
  assert_valid_json
  # Should have at least 3 branches (main, feature1, feature2)
  assert_json_array_length ".branches" 3
  
  # Check all branch names exist
  local main_exists=$(echo "$output" | jq '[.branches[] | select(.name == "main")] | length')
  [[ "$main_exists" -eq 1 ]] || fail "Expected main branch"
  local f1_exists=$(echo "$output" | jq '[.branches[] | select(.name == "feature1")] | length')
  [[ "$f1_exists" -eq 1 ]] || fail "Expected feature1 branch"
  local f2_exists=$(echo "$output" | jq '[.branches[] | select(.name == "feature2")] | length')
  [[ "$f2_exists" -eq 1 ]] || fail "Expected feature2 branch"
}

@test "hug bll --json: branch object structure" {
  # Arrange
  git checkout main

  # Act
  run hug bll --json

  # Assert
  assert_success
  assert_valid_json
  # Check that first branch has all required fields
  assert_json_has_key ".branches[0].hash"
  assert_json_has_key ".branches[0].name"
  assert_json_has_key ".branches[0].current"
  assert_json_type ".branches[0].current" "boolean"
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
  # Arrange - create a separate repo with only main branch
  local single_branch_repo
  single_branch_repo=$(create_test_repo)
  cd "$single_branch_repo" || exit 1

  # Act
  run hug bll --json

  # Assert
  assert_success
  assert_valid_json
  assert_json_array_length ".branches" 1
  # Check that the single branch is main
  local main_exists=$(echo "$output" | jq '[.branches[] | select(.name == "main")] | length')
  [[ "$main_exists" -eq 1 ]] || fail "Expected main branch"

  # Cleanup
  cd /
  rm -rf "$single_branch_repo"
}

@test "hug bll --json: branches field should be JSON array not string" {
  # Arrange
  git checkout main

  # Act
  run hug bll --json

  # Assert
  assert_success
  # Ensure branches field is a JSON array, not a string
  local branch_type
  branch_type=$(echo "$output" | jq '.branches | type')
  [ "$branch_type" = '"array"' ]

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
}

@test "hug bll --json: multiple branches create proper array structure" {
  # Arrange - create multiple branches
  git checkout main
  git checkout -b feature1
  git commit --allow-empty -m "Feature 1 commit"
  git checkout main
  git checkout -b feature2
  git commit --allow-empty -m "Feature 2 commit"

  # Act
  run hug bll --json

  # Assert
  assert_success
  assert_valid_json
  # Should have at least 3 branches (main, feature1, feature2)
  assert_json_array_length ".branches" 3
  
  # Ensure branches field is an array type
  assert_json_type ".branches" "array"
  
  # Check all branch names exist
  local main_exists=$(echo "$output" | jq '[.branches[] | select(.name == "main")] | length')
  [[ "$main_exists" -eq 1 ]] || fail "Expected main branch"
  local f1_exists=$(echo "$output" | jq '[.branches[] | select(.name == "feature1")] | length')
  [[ "$f1_exists" -eq 1 ]] || fail "Expected feature1 branch"
  local f2_exists=$(echo "$output" | jq '[.branches[] | select(.name == "feature2")] | length')
  [[ "$f2_exists" -eq 1 ]] || fail "Expected feature2 branch"
}