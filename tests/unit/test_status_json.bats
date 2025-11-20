#!/usr/bin/env bats

# Test JSON output for status commands (hug s, hug sl, hug sla)

load ../test_helper

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

@test "hug s --json: basic JSON structure" {
  # Arrange
  echo "test content" > file.txt
  git add file.txt

  # Act
  run hug s --json

  # Assert - flexible validation using helpers
  assert_success
  assert_valid_json
  assert_json_has_key ".repository"
  assert_json_has_key ".timestamp"
  assert_json_has_key ".command"
  assert_json_has_key ".status"
  assert_json_has_key ".branch"
}

@test "hug s --json: clean repository" {
  # Arrange - repository is already clean with just committed files
  # No changes to add, just test clean status
  
  # Act
  run hug s --json

  # Assert - flexible validation
  assert_success
  assert_valid_json
  assert_json_value ".status.clean" "true"
  assert_json_value ".status.staged_files" "0"
  assert_json_value ".status.unstaged_files" "0"
}

@test "hug s --json: dirty repository" {
  # Arrange
  echo "modified" > feature1.txt  # Modify existing file
  echo "staged" > staged.txt
  git add staged.txt

  # Act
  run hug s --json

  # Assert - flexible validation
  assert_success
  assert_valid_json
  assert_json_value ".status.clean" "false"
  assert_json_value ".status.staged_files" "1"
  assert_json_value ".status.unstaged_files" "1"
}

@test "hug sl --json: file status structure" {
  # Arrange
  echo "staged" > staged.txt
  echo "modified" > modified.txt
  echo "untracked" > untracked.txt
  git add staged.txt

  # Act
  run hug sl --json

  # Assert - validate structure using jq
  assert_success
  assert_valid_json

  # Check summary exists and has required fields
  assert_json_has_key ".summary"
  assert_json_has_key ".summary.staged"
  assert_json_has_key ".summary.unstaged"
  assert_json_has_key ".summary.untracked"
  assert_json_has_key ".summary.total"
  
  # Check that we have at least the files we created
  local staged_count=$(echo "$output" | jq -r '.summary.staged')
  [[ "$staged_count" -ge 1 ]] || fail "Expected at least 1 staged file"
  
  # Check specific files exist
  echo "$output" | jq -e '.staged[] | select(.path=="staged.txt")' >/dev/null || fail "Missing staged.txt"
  echo "$output" | jq -e '.untracked[] | select(.path=="untracked.txt")' >/dev/null || fail "Missing untracked.txt"
}

@test "hug sla --json: includes untracked files" {
  # Arrange
  echo "test" > file.txt
  echo "untracked" > untracked.txt
  git add file.txt

  # Act
  run hug sla --json

  # Assert - validate structure using jq
  assert_success
  assert_valid_json

  # Check summary exists with untracked files
  assert_json_has_key ".summary.untracked"
  local untracked_count=$(echo "$output" | jq -r '.summary.untracked')
  [[ "$untracked_count" -ge 1 ]] || fail "Expected at least 1 untracked file"
  
  # Check that untracked.txt exists in untracked array
  echo "$output" | jq -e '.untracked[] | select(.path=="untracked.txt")' >/dev/null || fail "Missing untracked.txt"
}

@test "hug sl --json: empty repository" {
  # Arrange - clean repo with no changes (repository already has committed files, so it has status)
  # Just test the existing clean state

  # Act
  run hug sl --json

  # Assert - validate structure using jq
  assert_success

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"

  # Check required fields exist
  echo "$output" | jq -e '.summary.staged' >/dev/null || fail "Missing 'staged' field"
  echo "$output" | jq -e '.summary.unstaged' >/dev/null || fail "Missing 'unstaged' field"
  echo "$output" | jq -e '.summary.untracked' >/dev/null || fail "Missing 'untracked' field"
  assert_output --partial '"total"'

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
}

@test "hug s --json: error handling" {
  # Arrange - not in git repo
  cd /tmp

  # Act
  run hug s --json

  # Assert
  assert_failure
  assert_output --partial 'Error'
  # Note: Error output is currently plain text, not JSON
  # TODO: Consider implementing JSON error format in future
}

@test "hug s --json: no ANSI colors in JSON" {
  # Arrange
  echo "test" > file.txt
  git add file.txt

  # Act
  run hug s --json

  # Assert
  assert_success
  refute_output --partial $'\e['  # No ANSI escape codes

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "JSON should be clean without ANSI codes"
}