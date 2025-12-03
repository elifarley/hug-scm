#!/usr/bin/env bats
# Simple test suite for file input enhancements to hug commands

load '../test_helper'

setup() {
  create_test_repo_with_history
  cd "$TEST_REPO"
}

@test "hug a: supports --from-file flag" {
  # Create test files
  echo "content1" > file1.txt
  echo "content2" > file2.txt
  echo "content3" > file3.txt

  # Create a file list
  echo -e "file1.txt\nfile3.txt" > files.txt

  # Add files using --from-file
  run hug a --from-file files.txt

  assert_success
  # Check that only files from the list were staged
  run hug sl
  assert_output --partial "file1.txt"
  assert_output --partial "file3.txt"
  refute_output --partial "file2.txt"
}

@test "hug a: supports --from-commit flag" {
  # Create and commit initial files
  echo "content1" > file1.txt
  echo "content2" > file2.txt
  hug add file1.txt file2.txt
  hug c -m "Initial commit"

  # Modify the files
  echo "modified1" > file1.txt
  echo "modified2" > file2.txt

  # Add files from the initial commit
  run hug a --from-commit HEAD

  assert_success
  # Check that both files were staged
  run hug sl
  assert_output --partial "file1.txt"
  assert_output --partial "file2.txt"
}

@test "hug us: supports --from-file flag" {
  # Stage some files
  echo "content1" > file1.txt
  echo "content2" > file2.txt
  hug add file1.txt file2.txt

  # Create a file list to unstage
  echo -e "file1.txt" > files.txt

  # Unstage files using --from-file
  run hug us --from-file files.txt

  assert_success
  # Check that only file1.txt was unstaged
  run hug sl
  refute_output --partial "file1.txt"
  assert_output --partial "file2.txt"
}

@test "hug us: supports --from-commit flag" {
  # Create and commit initial files
  echo "content1" > file1.txt
  echo "content2" > file2.txt
  hug add file1.txt file2.txt
  hug c -m "Initial commit"

  # Stage all files again
  hug add file1.txt file2.txt

  # Unstage files from the initial commit
  run hug us --from-commit HEAD

  assert_success
  # Check that both files were unstaged
  run hug sl
  refute_output --partial "file1.txt"
  refute_output --partial "file2.txt"
}

@test "hug ccp: supports --husk flag" {
  # Create and commit files in a specific pattern
  echo "content1" > config.json
  echo "content2" > settings.ini
  hug add config.json settings.ini
  hug c -m "Add configuration files"

  # Create new branch
  hug bc feature

  # Modify the files with different content
  echo "new config" > config.json
  echo "new settings" > settings.ini

  # Use husk to stage same files with original message
  run hug ccp --husk main

  assert_success
  # Check that the message was reused
  run hug sh
  assert_output --partial "Add configuration files"

  # Check that files are staged
  run hug sl
  assert_output --partial "config.json"
  assert_output --partial "settings.ini"
}

@test "hug ccp: --husk fails without commit" {
  run hug ccp --husk
  assert_failure
  assert_output --partial "requires a source commit"
}