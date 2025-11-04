#!/usr/bin/env bats
# Tests for git-llf (log file with renames)

# Load test helpers
load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

@test "hug llf: shows help with -h flag" {
  run hug llf -h
  assert_success
  assert_output --partial "hug llf: Log commits to a file (handles renames)"
}

@test "hug llf: shows help with --help flag" {
  run hug llf --help
  # --help triggers git's man page lookup which may fail if man pages aren't installed
  # We just verify it doesn't crash and exits with non-zero (help behavior)
  assert_failure
}

@test "hug llf: shows log for a file" {
  # Create a file with a commit
  echo "Content" > test.txt
  git add test.txt
  git commit -q -m "Add test.txt"
  
  run hug llf test.txt
  assert_success
  assert_output --partial "Add test.txt"
}

@test "hug llf: limits output with -N flag" {
  # Create multiple commits
  echo "v1" > test.txt
  git add test.txt
  git commit -q -m "Add test.txt"
  
  echo "v2" >> test.txt
  git add test.txt
  git commit -q -m "Update test.txt v2"
  
  echo "v3" >> test.txt
  git add test.txt
  git commit -q -m "Update test.txt v3"
  
  # Get only the last commit
  run hug llf test.txt -1
  assert_success
  assert_output --partial "Update test.txt v3"
  refute_output --partial "Add test.txt"
}

@test "hug llf: handles file that doesn't exist" {
  # Git log with --follow on nonexistent file returns empty (success)
  # This is expected behavior - no commits touched the file
  run hug llf nonexistent.txt
  assert_success
  # Output should be empty (no commits)
  assert_output ""
}

@test "hug llf: follows file renames" {
  # Create a file
  echo "Content" > original.txt
  git add original.txt
  git commit -q -m "Add original.txt"
  
  # Rename the file
  git mv original.txt renamed.txt
  git commit -q -m "Rename to renamed.txt"
  
  # Modify the renamed file
  echo "More content" >> renamed.txt
  git add renamed.txt
  git commit -q -m "Update renamed.txt"
  
  # llf should show all commits including the original
  run hug llf renamed.txt
  assert_success
  assert_output --partial "Add original.txt"
  assert_output --partial "Rename to renamed.txt"
  assert_output --partial "Update renamed.txt"
}

@test "hug llf: shows patches with -p flag" {
  echo "Line 1" > test.txt
  git add test.txt
  git commit -q -m "Add test.txt"
  
  echo "Line 2" >> test.txt
  git add test.txt
  git commit -q -m "Add line 2"
  
  run hug llf test.txt -1 -p
  assert_success
  assert_output --partial "Add line 2"
  assert_output --partial "+Line 2"
}

@test "hug llf: passes additional git log options" {
  echo "v1" > test.txt
  git add test.txt
  git commit -q -m "Add test.txt"
  
  echo "v2" >> test.txt
  git add test.txt
  git commit -q -m "Update test.txt"
  
  run hug llf test.txt --stat
  assert_success
  assert_output --partial "test.txt"
  assert_output --partial "1 file changed"
}

@test "hug llf: works with files in subdirectories" {
  mkdir -p src/components
  echo "Component code" > src/components/button.js
  git add src/components/button.js
  git commit -q -m "Add button component"
  
  run hug llf src/components/button.js
  assert_success
  assert_output --partial "Add button component"
}

@test "hug llf: handles files with spaces in name" {
  echo "Content" > "file with spaces.txt"
  git add "file with spaces.txt"
  git commit -q -m "Add file with spaces"
  
  run hug llf "file with spaces.txt"
  assert_success
  assert_output --partial "Add file with spaces"
}

@test "hug llf: shows only commits that touch the file" {
  # Create file A
  echo "A" > fileA.txt
  git add fileA.txt
  git commit -q -m "Add fileA"
  
  # Create file B
  echo "B" > fileB.txt
  git add fileB.txt
  git commit -q -m "Add fileB"
  
  # Modify file A
  echo "A2" >> fileA.txt
  git add fileA.txt
  git commit -q -m "Modify fileA"
  
  run hug llf fileA.txt
  assert_success
  assert_output --partial "Add fileA"
  assert_output --partial "Modify fileA"
  refute_output --partial "Add fileB"
}

@test "hug llf: works with -2 to show last 2 commits" {
  echo "v1" > test.txt
  git add test.txt
  git commit -q -m "Commit 1"
  
  echo "v2" >> test.txt
  git add test.txt
  git commit -q -m "Commit 2"
  
  echo "v3" >> test.txt
  git add test.txt
  git commit -q -m "Commit 3"
  
  run hug llf test.txt -2
  assert_success
  assert_output --partial "Commit 3"
  assert_output --partial "Commit 2"
  refute_output --partial "Commit 1"
}

@test "hug llf: handles newly added files" {
  # File only in most recent commit
  echo "New" > new.txt
  git add new.txt
  git commit -q -m "Add new file"
  
  run hug llf new.txt
  assert_success
  assert_output --partial "Add new file"
}

@test "hug llf: handles multiple renames" {
  # Create original file
  echo "Content" > file1.txt
  git add file1.txt
  git commit -q -m "Add file1"
  
  # First rename
  git mv file1.txt file2.txt
  git commit -q -m "Rename to file2"
  
  # Second rename
  git mv file2.txt file3.txt
  git commit -q -m "Rename to file3"
  
  # Should track through all renames
  run hug llf file3.txt
  assert_success
  assert_output --partial "Add file1"
  assert_output --partial "Rename to file2"
  assert_output --partial "Rename to file3"
}

@test "hug llf: combines -N and -p flags" {
  echo "v1" > test.txt
  git add test.txt
  git commit -q -m "Version 1"
  
  echo "v2" >> test.txt
  git add test.txt
  git commit -q -m "Version 2"
  
  run hug llf test.txt -1 -p
  assert_success
  assert_output --partial "Version 2"
  assert_output --partial "+v2"
  refute_output --partial "Version 1"
}

@test "hug llf: handles binary files" {
  # Create a simple binary-like file
  printf '\x00\x01\x02\x03' > binary.bin
  git add binary.bin
  git commit -q -m "Add binary file"
  
  run hug llf binary.bin
  assert_success
  assert_output --partial "Add binary file"
}

@test "hug llf: works from subdirectory" {
  mkdir -p src
  echo "Code" > src/main.js
  git add src/main.js
  git commit -q -m "Add main.js"
  
  cd src
  run hug llf main.js
  assert_success
  assert_output --partial "Add main.js"
}

@test "hug llf: handles deleted files in history" {
  # Create and delete a file
  echo "Temp" > temp.txt
  git add temp.txt
  git commit -q -m "Add temp"
  
  git rm temp.txt
  git commit -q -m "Remove temp"
  
  # Should still show history even though file is deleted
  run hug llf temp.txt
  assert_success
  assert_output --partial "Add temp"
}
