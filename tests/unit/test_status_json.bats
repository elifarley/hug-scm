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

  # Assert - validate JSON structure, not exact formatting
  assert_success

  # Validate JSON is parseable
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"

  # Check key fields exist (flexible format)
  echo "$output" | jq -e '.repository' >/dev/null || fail "Missing 'repository' field"
  echo "$output" | jq -e '.timestamp' >/dev/null || fail "Missing 'timestamp' field"
  echo "$output" | jq -e '.command' >/dev/null || fail "Missing 'command' field"
  echo "$output" | jq -e '.status' >/dev/null || fail "Missing 'status' field"
  echo "$output" | jq -e '.branch' >/dev/null || fail "Missing 'branch' field"
}

@test "hug s --json: clean repository" {
  # Arrange - repository is already clean with just committed files
  # No changes to add, just test clean status
  
  # Act
  run hug s --json

  # Assert - validate structure, not formatting
  assert_success

  # Validate JSON and check values
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"

  # Check status values using jq
  [[ "$(echo "$output" | jq -r '.status.clean')" == "true" ]] || fail "Expected clean: true"
  [[ "$(echo "$output" | jq -r '.status.staged_files')" == "0" ]] || fail "Expected staged_files: 0"
  [[ "$(echo "$output" | jq -r '.status.unstaged_files')" == "0" ]] || fail "Expected unstaged_files: 0"
}

@test "hug s --json: dirty repository" {
  # Arrange
  echo "modified" > feature1.txt  # Modify existing file
  echo "staged" > staged.txt
  git add staged.txt

  # Act
  run hug s --json

  # Assert - validate structure using jq
  assert_success

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"

  # Check status values
  [[ "$(echo "$output" | jq -r '.status.clean')" == "false" ]] || fail "Expected clean: false"
  [[ "$(echo "$output" | jq -r '.status.staged_files')" == "1" ]] || fail "Expected staged_files: 1"
  [[ "$(echo "$output" | jq -r '.status.unstaged_files')" == "1" ]] || fail "Expected unstaged_files: 1"

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
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

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"

  # Check summary values
  echo "$output" | jq -e '.summary' >/dev/null || fail "Missing 'summary' field"
  [[ "$(echo "$output" | jq -r '.summary.staged')" == "1" ]] || fail "Expected staged: 1"
  [[ "$(echo "$output" | jq -r '.summary.unstaged')" == "1" ]] || fail "Expected unstaged: 1"
  [[ "$(echo "$output" | jq -r '.summary.untracked')" == "1" ]] || fail "Expected untracked: 1"
  [[ "$(echo "$output" | jq -r '.summary.total')" == "3" ]] || fail "Expected total: 3"

  # Check file objects exist (validate structure, flexible format)
  echo "$output" | jq -e '.staged[] | select(.path=="staged.txt")' >/dev/null || fail "Missing staged.txt"
  echo "$output" | jq -e '.unstaged[] | select(.path=="modified.txt")' >/dev/null || fail "Missing modified.txt"
  echo "$output" | jq -e '.untracked[] | select(.path=="untracked.txt")' >/dev/null || fail "Missing untracked.txt"
}

@test "hug sla --json: includes untracked files" {
  # Arrange
  echo "test" > file.txt
  echo "untracked" > untracked.txt

  # Act
  run hug sla --json

  # Assert - validate structure using jq
  assert_success

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"

  # Check summary and file objects
  [[ "$(echo "$output" | jq -r '.summary.staged')" == "1" ]] || fail "Expected staged: 1"
  [[ "$(echo "$output" | jq -r '.summary.untracked')" == "1" ]] || fail "Expected untracked: 1"
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