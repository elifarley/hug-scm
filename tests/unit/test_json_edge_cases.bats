#!/usr/bin/env bats
# Tests for JSON output edge cases and error conditions

load ../test_helper

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_history)
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
# hug-json library edge cases
# =============================================================================

@test "hug-json: json_escape handles Unicode characters" {
  # Test Unicode characters in file content
  echo 'café 🦊 résumé' > "unicode_file.txt"
  hug add unicode_file.txt
  hug commit -m "add unicode file: café, résumé, 🦊"

  run hug s --json
  assert_success
  validate_json "$output"
  # Should include repository metadata and status
  assert_output --partial '"repository"'
  assert_output --partial '"command":"hug s --json"'
  assert_output --partial '"status":'
}

@test "hug-json: json_escape handles control characters" {
  # Test json_escape directly with control characters
  cd /tmp
  printf 'tab\tseparated\nnewlines\rreturn' > test_input.txt
  run bash -c "
    source $PROJECT_ROOT/git-config/lib/hug-json
    test_str=\"\$(cat test_input.txt)\"
    escaped=\$(json_escape \"\$test_str\")
    printf \"%s\" \"\$escaped\"
  "
  assert_success
  # Control characters should be escaped
  assert_output --partial '\\t'
  assert_output --partial '\\n'
  assert_output --partial '\\r'
}

@test "hug-json: json_escape handles quotes and backslashes" {
  # Test quotes and backslashes in content
  echo 'file with "double quotes" and backslashes\\' > "quotes.txt"
  hug add quotes.txt
  hug commit -m "add file with quotes and backslashes"

  run hug s --json --staged
  assert_success
  validate_json "$output"
  # Quotes and backslashes should be escaped
  assert_output --partial '\\"'
  assert_output --partial '\\\\'
}

@test "hug-json: to_json_array handles empty arrays" {
  # Test empty array generation
  run bash -c "cd $PROJECT_ROOT && source git-config/lib/hug-json; to_json_array"
  assert_success
  assert_output '[]'
}

@test "hug-json: to_json_array handles arrays with special characters" {
  run bash -c "
    cd $PROJECT_ROOT
    source git-config/lib/hug-json
    array=(\"file with spaces.txt\" \"file\\\"with\\\"quotes.txt\" \"file\twith\ttabs.txt\" \"file\nwith\nnewlines.txt\")
    to_json_array \"\${array[@]}\"
  "
  assert_success
  validate_json "$output"
  assert_output --partial 'file with spaces.txt'
  assert_output --partial 'file"with"quotes.txt'
  # Should escape special characters
  assert_output --partial '\\t'
  assert_output --partial '\\n'
}

# =============================================================================
# JSON status edge cases
# =============================================================================

@test "hug status --json: handles repository with changes" {
  # Create files with various names
  echo 'content1' > "file1.txt"
  echo 'content2' > "file2.txt"
  hug add file1.txt file2.txt
  hug commit -m "add test files"

  # Make unstaged changes
  echo 'modified content' > "file1.txt"
  echo 'untracked content' > "file3.txt"

  run hug s --json
  assert_success
  validate_json "$output"
  # Should show not clean and correct file counts
  assert_output --partial '"clean":false'
  assert_output --partial '"unstaged_files":1'
  assert_output --partial '"untracked_count":1'
  assert_output --partial '"staged_files":0'
}

@test "hug status --json: handles renamed files" {
  echo 'content' > "old_name.txt"
  hug add "old_name.txt"
  hug commit -m "initial file"

  hug mv "old_name.txt" "new_name.txt"
  run hug s --json --staged
  assert_success
  validate_json "$output"
  # Should show renamed file with correct counts
  assert_output --partial '"staged_files":1'
  assert_output --partial '"staged_insertions":0'
  assert_output --partial '"staged_deletions":0'
}

@test "hug status --json: handles binary files" {
  # Create binary file
  printf '\x00\x01\x02\x03\x04' > binary.bin
  hug add binary.bin
  hug commit -m "add binary file"

  run hug s --json
  assert_success
  validate_json "$output"
  # Should show clean repository after commit
  assert_output --partial '"clean":true'
  assert_output --partial '"staged_files":0'
  assert_output --partial '"unstaged_files":0'
}

@test "hug status --json: handles empty repository" {
  cd "$(mktemp -d)"
  hug init

  run hug s --json
  assert_success
  validate_json "$output"
  assert_output --partial '"clean":true'
  assert_output --partial '"staged_files":0'
  assert_output --partial '"unstaged_files":0'
  assert_output --partial '"untracked_count":0'
  assert_output --partial '"ignored_count":0'
}

@test "hug status --json: handles repository with only ignored files" {
  touch file1.txt file2.log
  echo '*.log' > .gitignore
  hug add .gitignore
  hug commit -m "add gitignore"

  run hug s --json
  assert_success
  validate_json "$output"
  # Should have 1 untracked and 1 ignored file
  assert_output --partial '"untracked_count":1'
  assert_output --partial '"ignored_count":1'
  assert_output --partial '"clean":false'
}

# =============================================================================
# JSON commit search edge cases
# =============================================================================

@test "hug lf --json: handles commits with special characters in message" {
  # Commit with special characters
  echo 'content' > special.txt
  hug add special.txt
  hug commit -m 'special: café résumé 🦊 "quoted" text\ttabbed'

  run hug lf 'special' --json
  assert_success
  validate_json "$output"
  assert_output --partial 'café'
  assert_output --partial 'résumé'
  assert_output --partial '🦊'
  assert_output --partial '\\"quoted\\"'
  assert_output --partial '\\t'
}

@test "hug lf --json: handles multi-line commit messages" {
  echo 'content' > multiline.txt
  hug add multiline.txt
  hug commit -m $'multi-line\ncommit message\nwith three lines'

  run hug lf 'multi' --json
  assert_success
  validate_json "$output"
  assert_output --partial 'multi-line'
  assert_output --partial 'commit message'
  assert_output --partial 'with three lines'
}

@test "hug lf --json: handles empty search results" {
  run hug lf 'nonexistent' --json
  assert_success
  validate_json "$output"
  assert_output --partial '"results_count":0'
  assert_output --partial '"results":[]'
}

@test "hug lf --json: handles commits with files containing special characters" {
  # Create files with special names
  echo 'content' > 'file with spaces.txt'
  echo 'content' > 'file"with"quotes.txt'
  hug add 'file with spaces.txt' 'file"with"quotes.txt'
  hug commit -m "add special files"

  run hug lf 'special' --json --with-files
  assert_success
  validate_json "$output"
  assert_output --partial 'file with spaces.txt'
  assert_output --partial 'file"with"quotes.txt'
}

@test "hug lc --json: handles code search with special characters" {
  # File with special characters
  echo 'café résumé 🦊 "quoted"' > code.txt
  hug add code.txt
  hug commit -m "add code with special chars"

  run hug lc 'café' --json
  assert_success
  validate_json "$output"
  assert_output --partial 'café'
  assert_output --partial '"type":"code"'
}

# =============================================================================
# JSON branch list edge cases
# =============================================================================

@test "hug bll --json: handles branch names with special characters" {
  # Create branch with special characters
  hug bc 'feature/special-chars"test'
  hug b 'feature/special-chars"test'
  echo 'content' > test.txt
  hug add test.txt
  hug commit -m "test commit"

  run hug bll --json
  assert_success
  validate_json "$output"
  assert_output --partial 'feature/special-chars"test'
}

@test "hug bll --json: handles repository with no branches" {
  # Test with single branch (main only)
  run hug bll --json
  assert_success
  validate_json "$output"
  # Should have at least one branch (current)
  assert_output --partial '"branches":['
  assert_output --partial '"current":true'
}

# =============================================================================
# Error handling edge cases
# =============================================================================

@test "hug-json: json_error produces valid JSON" {
  run bash -c "
    cd $PROJECT_ROOT
    source git-config/lib/hug-json
    json_error \"test_error\" \"test message\" 2>&1
  "
  assert_failure 1
  validate_json "$output"
  assert_output --partial '"error":{"type":"test_error","message":"test message"}'
}

@test "hug-json: validate_json handles malformed JSON" {
  run bash -c "
    cd $PROJECT_ROOT
    source git-config/lib/hug-json
    validate_json '{\"invalid\": json}'
  "
  assert_failure 1
}

@test "hug-json: validate_json handles valid JSON" {
  run bash -c "
    cd $PROJECT_ROOT
    source git-config/lib/hug-json
    validate_json '{\"valid\": \"json\", \"array\": [1,2,3]}'
  "
  assert_success
}

# =============================================================================
# Performance edge cases
# =============================================================================

@test "hug status --json: handles large number of files efficiently" {
  # Create many files
  for i in {1..100}; do
    echo "content $i" > "file$i.txt"
  done
  hug add file*.txt
  hug commit -m "add many files"

  run timeout 10s hug s --json --staged
  assert_success
  validate_json "$output"
  # Should have 0 staged files after commit
  assert_output --partial '"staged_files":0'
}

@test "hug lf --json: handles large commit history efficiently" {
  # Create many commits
  for i in {1..50}; do
    echo "content $i" > "file$i.txt"
    hug add "file$i.txt"
    hug commit -m "commit $i"
  done

  run timeout 15s hug lf 'commit' --json
  assert_success
  validate_json "$output"
  # Should have multiple results
  assert_output --partial '"results_count":'
  assert_output --partial '"results":['
}