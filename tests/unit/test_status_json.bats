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

  # Assert
  assert_success
  assert_output --partial '"repository"'
  assert_output --partial '"timestamp"'
  assert_output --partial '"command": "hug s --json"'
  assert_output --partial '"status"'
  assert_output --partial '"branch"'

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
}

@test "hug s --json: clean repository" {
  # Arrange
  git add file.txt
  git commit -m "Add test file"

  # Act
  run hug s --json

  # Assert
  assert_success
  assert_output --partial '"clean":true'
  assert_output --partial '"staged_files":0'
  assert_output --partial '"unstaged_files":0'

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
}

@test "hug s --json: dirty repository" {
  # Arrange
  echo "modified" > file.txt
  echo "staged" > staged.txt
  git add staged.txt

  # Act
  run hug s --json

  # Assert
  assert_success
  assert_output --partial '"clean":false'
  assert_output --partial '"staged_files":1'
  assert_output --partial '"unstaged_files":1'
  assert_output --partial '"staged_insertions":7'
  assert_output --partial '"unstaged_insertions":9'

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

  # Assert
  assert_success
  assert_output --partial '"summary"'
  assert_output --partial '"staged":1'
  assert_output --partial '"unstaged":1'
  assert_output --partial '"untracked":1'
  assert_output --partial '"total":3'

  # Check file objects
  assert_output --partial '"path" : "staged.txt"'
  assert_output --partial '"status" : "added"'
  assert_output --partial '"path" : "modified.txt"'
  assert_output --partial '"status" : "modified"'
  assert_output --partial '"path" : "untracked.txt"'
  assert_output --partial '"status" : "untracked"'

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
}

@test "hug sla --json: includes untracked files" {
  # Arrange
  echo "test" > file.txt
  echo "untracked" > untracked.txt

  # Act
  run hug sla --json

  # Assert
  assert_success
  assert_output --partial '"staged":1'
  assert_output --partial '"untracked":1'
  assert_output --partial '"path" : "untracked.txt"'
  assert_output --partial '"status" : "untracked"'

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
}

@test "hug sl --json: empty repository" {
  # Arrange - clean repo with no changes
  git add file.txt
  git commit -m "Add test file"

  # Act
  run hug sl --json

  # Assert
  assert_success
  assert_output --partial '"staged":0'
  assert_output --partial '"unstaged":0'
  assert_output --partial '"untracked":0'
  assert_output --partial '"total":0'

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
  assert_output --partial '"error"'

  # Validate error JSON
  echo "$output" | jq . >/dev/null
  assert_success "Error output should be valid JSON"
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