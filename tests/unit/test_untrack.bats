#!/usr/bin/env bats

# Test for hug untrack --from-file and --from-commit functionality

load '../test_helper'

setup() {
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"
}

@test "hug untrack: supports --from-file flag" {
  # Create and commit files
  echo "secret" > .env
  echo "config" > config.local.json
  echo "public" > public.txt
  hug add .env config.local.json public.txt
  hug c -m "Add files"

  # Create a file list with some files to untrack
  echo -e ".env\nconfig.local.json" > files.txt

  # Test dry-run first
  run hug untrack --dry-run --from-file files.txt
  assert_success
  assert_output --partial "Would untrack 2 file(s)"
  assert_output --partial ".env"
  assert_output --partial "config.local.json"

  # Actually untrack the files
  run hug untrack --force --from-file files.txt
  assert_success
  assert_output --partial "Untracked 2 files"

  # Check that files are no longer tracked
  run hug ls-files
  assert_success
  refute_output --partial ".env"
  refute_output --partial "config.local.json"
  assert_output --partial "public.txt"  # Should still be tracked
}

@test "hug untrack: supports --from-commit flag" {
  # Create initial commit
  echo "v1" > file1.txt
  echo "v1" > file2.txt
  hug add file1.txt file2.txt
  hug c -m "Initial commit"

  # Modify and commit file1 only
  echo "v2" > file1.txt
  hug add file1.txt
  hug c -m "Update file1"

  # Add another file that won't be in the last commit
  echo "new" > file3.txt
  hug add file3.txt
  hug c -m "Add file3"

  # Test dry-run with --from-commit for the last commit
  run hug untrack --dry-run --from-commit HEAD
  assert_success
  assert_output --partial "Would untrack 1 file(s)"
  assert_output --partial "file3.txt"

  # Test dry-run with --from-commit HEAD~1 (the commit that changed file1)
  run hug untrack --dry-run --from-commit HEAD~1
  assert_success
  assert_output --partial "Would untrack 1 file(s)"
  assert_output --partial "file1.txt"
}

@test "hug untrack: --from-file and --from-commit are mutually exclusive" {
  echo "file.txt" > files.txt

  run hug untrack --from-file files.txt --from-commit HEAD
  assert_failure
  assert_output --partial "Cannot use --from-file and --from-commit" || assert_output --partial "Cannot use --from-commit and --from-file"
}