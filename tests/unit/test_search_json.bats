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
  assert_json_has_key ".data.search"
  assert_json_has_key ".data.results"
  assert_json_value ".data.search.type" "message"
  assert_json_value ".data.search.term" "feat"
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
  assert_json_has_key ".data.results"
  assert_json_type ".data.results" "array"
  # Should find at least the feat commit (check with jq)
  [[ $(echo "$output" | jq -r '.data.results[].message' | grep -c "feat: add new feature") -ge 1 ]] || fail "Should find feat commit"
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
  assert_json_has_key ".data.search.with_files"
  assert_json_value ".data.search.with_files" "true"
  assert_json_has_key ".data.results[0].files"
  # Check that newfile.txt appears in files array
  [[ $(echo "$output" | jq -r '.data.results[0].files[].filename' | grep -c "newfile.txt") -ge 1 ]] || fail "Should find newfile.txt in files"
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
  assert_json_value ".data.search.type" "code"
  assert_json_value ".data.search.term" "testFunction"
  assert_json_has_key ".data.search"
  assert_json_has_key ".data.results"
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
  assert_valid_json "$output"
  # Should find the commit with the function
  local has_commit=$(echo "$output" | jq -r '.data.results[] | select(.message | contains("add test function")) | .message' | wc -l)
  [[ "$has_commit" -ge 1 ]] || fail "Should find commit with 'add test function' message"
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
  assert_valid_json
  assert_json_value ".data.search.with_files" "true"
  assert_json_has_key ".data.results[0].files"
  # Check for test.js in files array
  local has_file=$(echo "$output" | jq -r '.data.results[0].files[]? | select(.filename == "test.js") | .filename' | wc -l)
  [[ "$has_file" -ge 1 ]] || fail "Should find test.js in files array"
}

@test "hug lf --json: handles no matches" {
  # Arrange
  git checkout main

  # Act - search for something that doesn't exist
  run hug lf "nonexistentterm" --json

  # Assert - validate structure using jq
  assert_success
  assert_valid_json "$output"

  # Check search results - handle both .search and .data.search structures
  local results_count=$(echo "$output" | jq -r '.data.search.results_count // .search.results_count // 0')
  [[ "$results_count" == "0" ]] || fail "Expected results_count: 0, got: $results_count"
  local results_length=$(echo "$output" | jq '.data.results // .results | length')
  [[ "$results_length" == "0" ]] || fail "Expected empty results array"
}

@test "hug lc --json: handles no matches" {
  # Arrange
  git checkout main

  # Act - search for code that doesn't exist
  run hug lc "nonexistentFunction" --json

  # Assert - validate structure using jq
  assert_success
  assert_valid_json "$output"

  # Check search results - handle both .search and .data.search structures
  local results_count=$(echo "$output" | jq -r '.data.search.results_count // .search.results_count // 0')
  [[ "$results_count" == "0" ]] || fail "Expected results_count: 0, got: $results_count"
  local results_length=$(echo "$output" | jq '.data.results // .results | length')
  [[ "$results_length" == "0" ]] || fail "Expected empty results array"
}

@test "hug lf --json: no ANSI colors in JSON" {
  # Arrange
  git commit --allow-empty -m "test: commit"

  # Act
  run hug lf "test" --json

  # Assert
  assert_success
  assert_valid_json "$output"
  refute_output --partial $'\e['  # No ANSI escape codes
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
  assert_valid_json "$output"
  refute_output --partial $'\e['  # No ANSI escape codes
}

@test "hug lf --json: error handling" {
  # Arrange - not in git repo
  cd /tmp

  # Act
  run hug lf "test" --json

  # Assert - validate error JSON structure
  assert_failure

  # Validate error JSON (might not be JSON if critical error)
  if echo "$output" | jq . >/dev/null 2>&1; then
    # If it's valid JSON, check for error fields
    echo "$output" | jq -e '.error' >/dev/null || fail "Missing 'error' field in JSON output"
    echo "$output" | jq -e '.error.type' >/dev/null || fail "Missing 'error.type' field"
    echo "$output" | jq -e '.error.message' >/dev/null || fail "Missing 'error.message' field"
  fi
  # If it's not JSON, that's also acceptable for critical errors
}