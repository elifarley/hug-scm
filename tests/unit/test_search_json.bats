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

  # Assert - use flexible JSON validation
  assert_success
  assert_valid_json
  assert_json_has_key ".repository"
  assert_json_has_key ".timestamp"
  assert_json_has_key ".command"
  assert_json_has_key ".search"
  assert_json_has_key ".commits"
  assert_json_value ".search.type" "message"
  assert_json_value ".search.term" "feat"
}

@test "hug lf --json: finds commits with matching messages" {
  # Arrange
  git checkout main
  git commit --allow-empty -m "feat: add new feature"
  git commit --allow-empty -m "fix: resolve bug"
  git commit --allow-empty -m "docs: update README"

  # Act
  run hug lf "feat" --json

  # Assert - flexible validation
  assert_success
  assert_valid_json
  assert_json_has_key ".commits"
  assert_json_type ".commits" "array"
  # Should find at least the feat commit (check with jq)
  [[ $(echo "$output" | jq -r '.commits[].message' | grep -c "feat: add new feature") -ge 1 ]] || fail "Should find feat commit"
}

@test "hug lf --json: with --with-files flag" {
  # Arrange
  echo "test content" > newfile.txt
  git add newfile.txt
  git commit -m "feat: add new file"

  # Act
  run hug lf "feat" --json --with-files

  # Assert - flexible validation
  assert_success
  assert_valid_json
  assert_json_has_key ".search.with_files"
  assert_json_value ".search.with_files" "true"
  assert_json_has_key ".commits[0].files"
  # Check that newfile.txt appears in files array
  [[ $(echo "$output" | jq -r '.commits[0].files[].filename' | grep -c "newfile.txt") -ge 1 ]] || fail "Should find newfile.txt in files"
}

@test "hug lc --json: basic code search structure" {
  # Arrange
  echo "function testFunction() {}" > test.js
  git add test.js
  git commit -m "add test function"

  # Act
  run hug lc "testFunction" --json

  # Assert - flexible validation
  assert_success
  assert_valid_json
  assert_json_value ".search.type" "code"
  assert_json_value ".search.term" "testFunction"
  assert_json_has_key ".search"
  assert_json_has_key ".commits"
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
  assert_output --partial '"filename": "test.js"'
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

  # Assert - validate structure using jq
  assert_success

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"

  # Check search results using jq
  [[ "$(echo "$output" | jq -r '.search.results_count')" == "0" ]] || fail "Expected results_count: 0"
  [[ "$(echo "$output" | jq '.results | length')" == "0" ]] || fail "Expected empty results array"
}

@test "hug lc --json: handles no matches" {
  # Arrange
  git checkout main

  # Act - search for code that doesn't exist
  run hug lc "nonexistentFunction" --json

  # Assert - validate structure using jq
  assert_success

  # Validate JSON
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"

  # Check search results using jq
  [[ "$(echo "$output" | jq -r '.search.results_count')" == "0" ]] || fail "Expected results_count: 0"
  [[ "$(echo "$output" | jq '.commits | length')" == "0" ]] || fail "Expected empty commits array"
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

  # Assert - validate error JSON structure
  assert_failure

  # Validate error JSON
  echo "$output" | jq . >/dev/null
  assert_success "Error output should be valid JSON"

  # Check error field exists using jq
  echo "$output" | jq -e '.error' >/dev/null || fail "Missing 'error' field in JSON output"
  echo "$output" | jq -e '.error.type' >/dev/null || fail "Missing 'error.type' field"
  echo "$output" | jq -e '.error.message' >/dev/null || fail "Missing 'error.message' field"
}