#!/usr/bin/env bats
# Tests for hug ll (commit log) command

load '../test_helper'

setup() {
  # Create simple test repo with known commits
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO" || return 1

  echo "first" > file1.txt
  git add file1.txt
  git_commit_deterministic "First commit"

  echo "second" > file2.txt
  git add file2.txt
  git_commit_deterministic "Second commit"

  echo "third" > file3.txt
  git add file3.txt
  git_commit_deterministic "Third commit"
}

teardown() {
  cleanup_test_repo
}

# =============================================================================
# BASIC FUNCTIONALITY
# =============================================================================

@test "hug ll: shows commit log with default format" {
  run hug ll -1
  assert_success
  assert_output --partial "Third commit"
}

@test "hug ll: limits output with -n flag" {
  run hug ll -2
  assert_success
  # Should show exactly 2 commits (fixture has 3)
  assert_line --index 0 --partial "Third commit"
  assert_line --index 1 --partial "Second commit"
}

@test "hug ll: shows all branches with --all" {
  # Create a branch
  git checkout -b feature HEAD~1 >/dev/null 2>&1
  git checkout main >/dev/null 2>&1

  run hug ll --all -1
  assert_success
  # Should show commits from all branches
}

@test "hug ll: accepts revision range" {
  run hug ll HEAD~2..HEAD
  assert_success
  # Should show last 2 commits
}

@test "hug ll: N=0 shows HEAD commit" {
  run hug ll 0
  assert_success
  assert_output --partial "Third commit"
}

@test "hug ll: N=1 shows HEAD~1 commit" {
  run hug ll 1
  assert_success
  assert_output --partial "Second commit"
}

@test "hug ll: N=2 shows HEAD~2 commit" {
  run hug ll 2
  assert_success
  assert_output --partial "First commit"
}

@test "hug ll: N with JSON output" {
  run hug ll 0 --json
  assert_success

  # Validate JSON structure
  run python3 -m json.tool <<< "$output"
  assert_success

  # Should have exactly 1 commit
  run bash -c "echo '$output' | python3 -c 'import sys, json; print(len(json.load(sys.stdin)[\"commits\"]))'"
  assert_output "1"
}

@test "hug ll: N=-n have different behavior" {
  # N=1 shows single commit (HEAD~1)
  run hug ll 1
  assert_success
  assert_output --partial "Second commit"
  refute_output --partial "Third commit"

  # -1 shows last commit (HEAD)
  run hug ll -1
  assert_success
  assert_output --partial "Third commit"
}

@test "hug ll: N >= 1000 passes through as ref" {
  # Create a numeric tag for testing
  git tag 1234 HEAD

  # N=1234 should pass through as a ref (the tag)
  run hug ll 1234
  assert_success
  # Should show the commit that the tag points to
  assert_output --partial "Third commit"
}

# =============================================================================
# JSON OUTPUT
# =============================================================================

@test "hug ll --json: produces valid JSON" {
  run hug ll -1 --json
  assert_success

  # Validate JSON structure with python
  run python3 -m json.tool <<< "$output"
  assert_success
}

@test "hug ll --json: includes required fields" {
  run hug ll -1 --json
  assert_success
  local json_output="$output"

  # Check for required top-level fields
  run bash -c "echo '$json_output' | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d.get(\"command\"))'"
  assert_output "hug ll"

  run bash -c "echo '$json_output' | python3 -c 'import sys, json; d=json.load(sys.stdin); print(len(d.get(\"commits\", [])))'"
  assert_output "1"

  run bash -c "echo '$json_output' | python3 -c 'import sys, json; d=json.load(sys.stdin); print(d.get(\"summary\", {}).get(\"total_commits\"))'"
  assert_output "1"
}

@test "hug ll --json: commit object has correct structure" {
  run hug ll -1 --json
  assert_success
  local json_output="$output"

  # Check commit fields using jq if available, otherwise python
  if command -v jq >/dev/null 2>&1; then
    run bash -c "echo '$json_output' | jq -r '.commits[0].sha'"
    assert_success
    # SHA should be 40 characters
    [ ${#output} -eq 40 ]

    run bash -c "echo '$json_output' | jq -r '.commits[0].sha_short'"
    assert_success
    # Short SHA should be 7 characters
    [ ${#output} -eq 7 ]

    run bash -c "echo '$json_output' | jq -r '.commits[0].author.name'"
    assert_success
    [[ -n "$output" ]]

    run bash -c "echo '$json_output' | jq -r '.commits[0].subject'"
    assert_success
    [[ -n "$output" ]]
  else
    # Fallback to python
    run bash -c "echo '$json_output' | python3 -c 'import sys, json; c=json.load(sys.stdin)[\"commits\"][0]; print(len(c[\"sha\"]))'"
    assert_output "40"
  fi
}

@test "hug ll --json: includes date in ISO 8601 format" {
  run hug ll -1 --json
  assert_success

  # Extract author date and check format (YYYY-MM-DDTHH:MM:SS...)
  run bash -c "echo '$output' | python3 -c 'import sys, json; print(json.load(sys.stdin)[\"commits\"][0][\"author\"][\"date\"])'"
  assert_success
  assert_output --regexp '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}'
}

@test "hug ll --json: includes relative date" {
  run hug ll -1 --json
  assert_success

  # Check for author.date_relative field
  run bash -c "echo '$output' | python3 -c 'import sys, json; print(json.load(sys.stdin)[\"commits\"][0][\"author\"].get(\"date_relative\"))'"
  assert_success
  [[ -n "$output" ]]
}

@test "hug ll --json: handles multiple commits" {
  run hug ll -3 --json
  assert_success
  local json_output="$output"

  # Should have 3 commits
  run bash -c "echo '$json_output' | python3 -c 'import sys, json; print(len(json.load(sys.stdin)[\"commits\"]))'"
  assert_output "3"

  # Summary should match
  run bash -c "echo '$json_output' | python3 -c 'import sys, json; print(json.load(sys.stdin)[\"summary\"][\"total_commits\"])'"
  assert_output "3"
}

@test "hug ll --json: includes summary with date range" {
  run hug ll -2 --json
  assert_success

  # Check for date_range in summary
  run bash -c "echo '$output' | python3 -c 'import sys, json; d=json.load(sys.stdin); print(\"earliest\" in d[\"summary\"][\"date_range\"] and \"latest\" in d[\"summary\"][\"date_range\"])'"
  assert_output "True"
}

@test "hug ll --json: works with jq for filtering" {
  if ! command -v jq >/dev/null 2>&1; then
    skip "jq not installed"
  fi

  run hug ll -2 --json
  assert_success

  # Extract just commit subjects
  run bash -c "echo '$output' | jq -r '.commits[].subject'"
  assert_success
  [[ -n "$output" ]]
}

@test "hug ll --json: handles commit with refs" {
  # HEAD commit should have refs
  run hug ll -1 --json
  assert_success

  # Check if refs field exists and contains data
  run bash -c "echo '$output' | python3 -c 'import sys, json; refs=json.load(sys.stdin)[\"commits\"][0].get(\"refs\"); print(refs is not None and len(refs) > 0)'"
  assert_success
  assert_output "True"
}

@test "hug ll --json: includes parents array" {
  # Create a merge commit
  git checkout -b feature HEAD~1 >/dev/null 2>&1
  echo "feature" > feature.txt
  git add feature.txt
  git commit -m "Feature commit" >/dev/null 2>&1
  git checkout main >/dev/null 2>&1
  git merge --no-ff feature -m "Merge feature" >/dev/null 2>&1

  run hug ll -1 --json
  assert_success

  # Check that parents array exists
  run bash -c "echo '$output' | python3 -c 'import sys, json; print(\"parents\" in json.load(sys.stdin)[\"commits\"][0])'"
  assert_output "True"
}

# =============================================================================
# JSON WITH STATS
# =============================================================================

@test "hug ll --json: stats field ABSENT by default" {
  run hug ll -1 --json
  assert_success

  # Stats field should NOT exist when --with-stats is absent
  run bash -c "echo '$output' | python3 -c 'import sys, json; print(\"stats\" in json.load(sys.stdin)[\"commits\"][0])'"
  assert_success
  assert_output "False"
}

@test "hug ll --json --with-stats: includes file change statistics" {
  # Create a commit with known changes
  echo "new content" >> test.txt
  git add test.txt
  git commit -m "Update test.txt" >/dev/null 2>&1

  run hug ll -1 --json --with-stats
  assert_success

  # Check for stats field
  run bash -c "echo '$output' | python3 -c 'import sys, json; stats=json.load(sys.stdin)[\"commits\"][0].get(\"stats\"); print(stats is not None)'"
  assert_success
  assert_output "True"
}

@test "hug ll --json --with-stats: stats have correct structure" {
  # Create a commit with multiple file changes
  echo "line1" >> file1.txt
  echo "line2" >> file2.txt
  git add file1.txt file2.txt
  git commit -m "Add two files" >/dev/null 2>&1

  run hug ll -1 --json --with-stats
  assert_success

  # Check stats fields
  run bash -c "echo '$output' | python3 -c '
import sys, json
stats = json.load(sys.stdin)[\"commits\"][0][\"stats\"]
print(\"files_changed\" in stats and \"insertions\" in stats and \"deletions\" in stats)
'"
  assert_success
  assert_output "True"
}

# =============================================================================
# JSON WITH --no-body FLAG
# =============================================================================

@test "hug ll --json --no-body: body field is null" {
  # Create commit with body
  git commit --allow-empty -m "Subject line" -m "Body paragraph 1" -m "Body paragraph 2" >/dev/null 2>&1

  run hug ll -1 --json --no-body
  assert_success

  # Body should be null
  run bash -c "echo '$output' | python3 -c 'import sys, json; print(json.load(sys.stdin)[\"commits\"][0][\"body\"])'"
  assert_output "None"
}

@test "hug ll --json --no-body: message equals subject only" {
  # Create commit with body
  git commit --allow-empty -m "Test subject" -m "Test body content" >/dev/null 2>&1

  run hug ll -1 --json --no-body
  assert_success

  # Message should equal subject (no body)
  run bash -c "echo '$output' | python3 -c '
import sys, json
commit = json.load(sys.stdin)[\"commits\"][0]
print(commit[\"message\"] == commit[\"subject\"])
'"
  assert_success
  assert_output "True"
}

@test "hug ll --json: body INCLUDED by default" {
  # Create commit with body
  git commit --allow-empty -m "Subject" -m "Body text here" >/dev/null 2>&1

  run hug ll -1 --json
  assert_success

  # Body should be present
  run bash -c "echo '$output' | python3 -c 'import sys, json; body=json.load(sys.stdin)[\"commits\"][0][\"body\"]; print(body is not None and len(body) > 0)'"
  assert_success
  assert_output "True"
}

@test "hug ll --json --with-stats --no-body: both flags work together" {
  # Create commit with body and file changes
  echo "content" > newfile.txt
  git add newfile.txt
  git commit -m "Add file" -m "Detailed description here" >/dev/null 2>&1

  run hug ll -1 --json --with-stats --no-body
  assert_success
  local json_output="$output"

  # Check stats present
  run bash -c "echo '$json_output' | python3 -c 'import sys, json; print(\"stats\" in json.load(sys.stdin)[\"commits\"][0])'"
  assert_success
  assert_output "True"

  # Check body absent
  run bash -c "echo '$json_output' | python3 -c 'import sys, json; print(json.load(sys.stdin)[\"commits\"][0][\"body\"])'"
  assert_output "None"
}

# =============================================================================
# EDGE CASES
# =============================================================================

@test "hug ll --json: handles commit with multi-line message" {
  # Create commit with body
  git commit --allow-empty -m "Subject line" -m "Body paragraph 1" -m "Body paragraph 2" >/dev/null 2>&1

  run hug ll -1 --json
  assert_success

  # Check that body is captured
  run bash -c "echo '$output' | python3 -c 'import sys, json; body=json.load(sys.stdin)[\"commits\"][0].get(\"body\"); print(body is not None and len(body) > 0)'"
  assert_success
  assert_output "True"
}

@test "hug ll --json: handles commit with no body" {
  git commit --allow-empty -m "Just subject" >/dev/null 2>&1

  run hug ll -1 --json
  assert_success

  # Body should be null
  run bash -c "echo '$output' | python3 -c 'import sys, json; print(json.load(sys.stdin)[\"commits\"][0][\"body\"])'"
  assert_output "None"
}

@test "hug ll --json: handles commit with special characters in message" {
  git commit --allow-empty -m 'Fix "bug" in <module>' >/dev/null 2>&1

  run hug ll -1 --json
  assert_success

  # Special characters should be properly escaped in JSON
  run python3 -m json.tool <<< "$output"
  assert_success
}

@test "hug ll --json: empty result when no commits in range" {
  # Request impossible range
  run hug ll HEAD..HEAD --json
  assert_success

  # Should return empty commits array
  run bash -c "echo '$output' | python3 -c 'import sys, json; print(len(json.load(sys.stdin)[\"commits\"]))'"
  assert_output "0"
}

# =============================================================================
# HELP AND ERROR HANDLING
# =============================================================================

@test "hug ll --help: shows help message" {
  run hug ll -h
  assert_success
  assert_output --partial "USAGE"
  assert_output --partial "--json"
}

@test "hug ll -h: shows help message" {
  run hug ll -h
  assert_success
  assert_output --partial "USAGE"
}

@test "hug ll: works outside git repo with proper error" {
  cd /tmp
  run hug ll --json 2>&1
  assert_failure
  # Should fail gracefully
}
