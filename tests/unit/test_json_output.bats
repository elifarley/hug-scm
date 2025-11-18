#!/usr/bin/env bats
# Tests for JSON output functionality across analysis/stats commands

load ../test_helper

setup() {
  require_hug
  TEST_REPO=$(create_demo_repo_simple)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

# Helper function to validate JSON structure
validate_json() {
  python3 -m json.tool <<< "$1" > /dev/null
}

# =============================================================================
# hug analyze co-changes --json
# =============================================================================

@test "hug analyze co-changes --json: produces valid JSON" {
  run hug analyze co-changes 10 --json

  assert_success
  validate_json "$output"
}

@test "hug analyze co-changes --json: contains expected fields" {
  run hug analyze co-changes 10 --json

  assert_success
  assert_output --partial '"commits_analyzed"'
  assert_output --partial '"threshold"'
  assert_output --partial '"total_pairs"'
  assert_output --partial '"correlations"'
}

@test "hug analyze co-changes --json: correlations have required fields" {
  run hug analyze co-changes 10 --json

  assert_success
  assert_output --partial '"file_a"'
  assert_output --partial '"file_b"'
  assert_output --partial '"correlation"'
  assert_output --partial '"co_changes"'
  assert_output --partial '"changes_a"'
  assert_output --partial '"changes_b"'
}

@test "hug analyze co-changes --json: can be piped to jq" {
  command -v jq >/dev/null || skip "jq not installed"

  run bash -c "hug analyze co-changes 10 --json | jq -r '.commits_analyzed'"

  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]  # Should be a number
}

# =============================================================================
# hug analyze expert --json
# =============================================================================

@test "hug analyze expert --json: produces valid JSON" {
  run hug analyze expert README.md --json

  assert_success
  validate_json "$output"
}

@test "hug analyze expert --json: contains expected fields" {
  run hug analyze expert README.md --json

  assert_success
  assert_output --partial '"file"'
  assert_output --partial '"total_commits"'
  assert_output --partial '"ownership"'
  assert_output --partial '"decay_days"'
}

@test "hug analyze expert --json: ownership entries have required fields" {
  run hug analyze expert README.md --json

  assert_success
  assert_output --partial '"author"'
  assert_output --partial '"raw_commits"'
  assert_output --partial '"weighted_score"'
  assert_output --partial '"ownership_pct"'
  assert_output --partial '"classification"'
}

@test "hug analyze expert --json: can be piped to jq" {
  command -v jq >/dev/null || skip "jq not installed"

  run bash -c "hug analyze expert README.md --json | jq -r '.file'"

  assert_success
  assert_output "README.md"
}

# =============================================================================
# hug stats file --json
# =============================================================================

@test "hug stats file --json: produces valid JSON" {
  run hug stats file README.md --json

  assert_success
  validate_json "$output"
}

@test "hug stats file --json: contains expected top-level fields" {
  run hug stats file README.md --json

  assert_success
  assert_output --partial '"file"'
  assert_output --partial '"file_churn"'
  assert_output --partial '"line_churn"'
  assert_output --partial '"summary"'
}

@test "hug stats file --json: file_churn has required fields" {
  run hug stats file README.md --json

  assert_success
  assert_output --partial '"total_commits"'
  assert_output --partial '"unique_authors"'
  assert_output --partial '"authors"'
  assert_output --partial '"first_commit"'
  assert_output --partial '"last_commit"'
}

@test "hug stats file --json: can be piped to jq" {
  command -v jq >/dev/null || skip "jq not installed"

  run bash -c "hug stats file README.md --json | jq -r '.file'"

  assert_success
  assert_output "README.md"
}

# =============================================================================
# hug analyze activity --json
# =============================================================================

@test "hug analyze activity --json: produces valid JSON" {
  run hug analyze activity --by-hour --json

  assert_success
  validate_json "$output"
}

@test "hug analyze activity --json: contains expected fields" {
  run hug analyze activity --by-hour --json

  assert_success
  assert_output --partial '"commits_analyzed"'
  assert_output --partial '"analysis"'
  assert_output --partial '"type"'
  assert_output --partial '"data"'
}

@test "hug analyze activity --by-hour --json: type is by_hour" {
  run hug analyze activity --by-hour --json

  assert_success
  assert_output --partial '"type": "by_hour"'
}

@test "hug analyze activity --by-day --json: type is by_day" {
  run hug analyze activity --by-day --json

  assert_success
  assert_output --partial '"type": "by_day"'
}

@test "hug analyze activity --json: can be piped to jq" {
  command -v jq >/dev/null || skip "jq not installed"

  run bash -c "hug analyze activity --by-hour --json | jq -r '.analysis.type'"

  assert_success
  assert_output "by_hour"
}

# =============================================================================
# Cross-command validation
# =============================================================================

@test "All JSON outputs are valid and parseable by python json.tool" {
  # Test co-changes
  run hug analyze co-changes 10 --json
  assert_success
  validate_json "$output"

  # Test expert
  run hug analyze expert README.md --json
  assert_success
  validate_json "$output"

  # Test stats file
  run hug stats file README.md --json
  assert_success
  validate_json "$output"

  # Test activity
  run hug analyze activity --by-hour --json
  assert_success
  validate_json "$output"
}
