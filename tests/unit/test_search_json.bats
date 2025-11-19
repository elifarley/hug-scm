#!/usr/bin/env bats

# Test JSON output for search commands (hug lf, hug lc)

load ../test_helper

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

@test "hug lf --json: basic message search structure" {
  # Arrange
  git checkout main
  git commit --allow-empty -m "feat: add new feature"

  # Act
  run hug lf "feat" --json

  # Assert
  assert_success
  assert_output --partial '"repository"'
  assert_output --partial '"timestamp"'
  assert_output --partial '"command": "hug lf --json"'
  assert_output --partial '"search"'
  assert_output --partial '"commits"'
  assert_output --partial '"type": "message"'
  assert_output --partial '"term": "feat"'

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
}

@test "hug lf --json: finds commits with matching messages" {
  # Arrange
  git checkout main
  git commit --allow-empty -m "feat: add new feature"
  git commit --allow-empty -m "fix: resolve bug"
  git commit --allow-empty -m "docs: update README"

  # Act
  run hug lf "feat" --json

  # Assert
  assert_success
  # Should find at least the feat commit
  assert_output --partial '"message": "feat: add new feature"'

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
}

@test "hug lf --json: with --with-files flag" {
  # Arrange
  echo "test content" > newfile.txt
  git add newfile.txt
  git commit -m "feat: add new file"

  # Act
  run hug lf "feat" --json --with-files

  # Assert
  assert_success
  assert_output --partial '"files"'
  assert_output --partial '"path": "newfile.txt"'
  assert_output --partial '"status": "added"'
  assert_output --partial '"with_files":true'

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
}

@test "hug lc --json: basic code search structure" {
  # Arrange
  echo "function testFunction() {}" > test.js
  git add test.js
  git commit -m "add test function"

  # Act
  run hug lc "testFunction" --json

  # Assert
  assert_success
  assert_output --partial '"type": "code"'
  assert_output --partial '"term": "testFunction"'
  assert_output --partial '"search"'
  assert_output --partial '"commits"'

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
}

@test "hug lc --json: finds commits with code changes" {
  # Arrange
  echo "function testFunction() {}" > test.js
  git add test.js
  git commit -m "add test function"

  # Act
  run hug lc "testFunction" --json

  # Assert
  assert_success
  # Should find the commit with the function
  assert_output --partial '"message": "add test function"'

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
}

@test "hug lc --json: with --with-files flag" {
  # Arrange
  echo "function testFunction() {}" > test.js
  git add test.js
  git commit -m "add test function"

  # Act
  run hug lc "testFunction" --json --with-files

  # Assert
  assert_success
  assert_output --partial '"files"'
  assert_output --partial '"path": "test.js"'
  assert_output --partial '"status": "modified"'
  assert_output --partial '"with_files":true'

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
}

@test "hug lf --json: handles no matches" {
  # Arrange
  git checkout main

  # Act - search for something that doesn't exist
  run hug lf "nonexistentterm" --json

  # Assert
  assert_success
  assert_output --partial '"commits":[]'
  assert_output --partial '"results_count":0'

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
}

@test "hug lc --json: handles no matches" {
  # Arrange
  git checkout main

  # Act - search for code that doesn't exist
  run hug lc "nonexistentFunction" --json

  # Assert
  assert_success
  assert_output --partial '"commits":[]'
  assert_output --partial '"results_count":0'

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"
}

@test "hug lf --json: no ANSI colors in JSON" {
  # Arrange
  git commit --allow-empty -m "test: commit"

  # Act
  run hug lf "test" --json

  # Assert
  assert_success
  refute_output --partial $'\e['  # No ANSI escape codes

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "JSON should be clean without ANSI codes"
}

@test "hug lc --json: no ANSI colors in JSON" {
  # Arrange
  echo "function test() {}" > test.js
  git add test.js
  git commit -m "add test function"

  # Act
  run hug lc "test" --json

  # Assert
  assert_success
  refute_output --partial $'\e['  # No ANSI escape codes

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "JSON should be clean without ANSI codes"
}

@test "hug lf --json: error handling" {
  # Arrange - not in git repo
  cd /tmp

  # Act
  run hug lf "test" --json

  # Assert
  assert_failure
  assert_output --partial '"error"'

  # Validate error JSON
  echo "$output" | jq . >/dev/null
  assert_success "Error output should be valid JSON"
}