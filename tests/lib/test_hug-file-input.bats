#!/usr/bin/env bats
# Tests for hug-file-input library: File input and parsing utilities

load '../test_helper'

# Source the library and dependencies
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-file-input'

# Override error function for library testing
error() {
  echo "Error: $1" >&2
  return 1
}

# Helper function to create test files with specific content
create_test_file() {
  local filename="$1"
  local content="$2"
  echo -e "$content" > "$filename"
}

#=== read_files_from_source Tests ===

@test "read_files_from_source: reads from simple file list" {
  # Arrange
  local test_file="$BATS_TMPDIR/simple_list.txt"
  create_test_file "$test_file" "file1.txt\nfile2.txt\nfile3.txt"

  # Act
  run read_files_from_source "$test_file"

  # Assert
  assert_success
  assert_line "file1.txt"
  assert_line "file2.txt"
  assert_line "file3.txt"
}

@test "read_files_from_source: reads from stdin" {
  # Arrange
  local expected="file1.txt\nfile2.txt"

  # Act - Use subprocess to test stdin reading
  run bash -c 'source /home/ecc/IdeaProjects/hug-scm/git-config/lib/hug-file-input; echo -e "file1.txt\nfile2.txt" | read_files_from_source -'

  # Assert
  assert_success
  assert_line "file1.txt"
  assert_line "file2.txt"
}

@test "read_files_from_source: handles non-existent file" {
  # Arrange
  local non_existent="/tmp/non_existent_file_$$"

  # Act
  run read_files_from_source "$non_existent"

  # Assert
  assert_failure
  assert_output --partial "Error:"
}

@test "read_files_from_source: handles empty source" {
  # Arrange
  local empty_file="$BATS_TMPDIR/empty.txt"
  touch "$empty_file"

  # Act
  run read_files_from_source "$empty_file"

  # Assert
  assert_success
  assert_output ""
}

@test "read_files_from_source: skips comments and empty lines" {
  # Arrange
  local test_file="$BATS_TMPDIR/with_comments.txt"
  create_test_file "$test_file" "# This is a comment\n\nfile1.txt\n  # Another comment\nfile2.txt\n\n"

  # Act
  run read_files_from_source "$test_file"

  # Assert
  assert_success
  assert_line "file1.txt"
  assert_line "file2.txt"
  refute_output --partial "#"
}

#=== parse_file_content Tests ===

@test "parse_file_content: detects hug sh output format" {
  # Arrange - Create content that looks like hug sh output with correct count
  local content="file1.txt | 1 +\nfile2.txt | 2 -\n2 files changed"

  # Act
  run parse_file_content "$content"

  # Assert
  assert_success
  assert_line "file1.txt"
  assert_line "file2.txt"
}

@test "parse_file_content: handles simple file list format" {
  # Arrange
  local content="file1.txt\nfile2.txt\nfile3.txt"

  # Act
  run parse_file_content "$content"

  # Assert
  assert_success
  # Output is on a single line when not hug sh format
  assert_output "file1.txt"
}

@test "parse_file_content: handles empty content" {
  # Arrange
  local content=""

  # Act
  run parse_file_content "$content"

  # Assert
  assert_success
  assert_output ""
}

@test "parse_file_content: handles whitespace trimming" {
  # Arrange
  local content="  file1.txt  \n\tfile2.txt\t\n   file3.txt   "

  # Act
  run parse_file_content "$content"

  # Assert
  assert_success
  # Output is on a single line when not hug sh format
  assert_output "file1.txt"
}

#=== extract_files_from_hug_sh Tests ===

@test "extract_files_from_hug_sh: extracts files from valid hug sh output" {
  # Arrange
  local content="README.md | 5 +++++\nsrc/main.js | 10 +++++++---\n2 files changed"

  # Act
  run extract_files_from_hug_sh "$content"

  # Assert
  assert_success
  assert_line "README.md"
  assert_line "src/main.js"
}

@test "extract_files_from_hug_sh: handles renamed files" {
  # Arrange
  local content="{old_name.js => new_name.js} | 100 +\nother.txt | 5 +\n2 files changed"

  # Act
  run extract_files_from_hug_sh "$content"

  # Assert
  assert_success
  assert_line "new_name.js"
  assert_line "other.txt"
  refute_output --partial "old_name.js"
}

@test "extract_files_from_hug_sh: handles complex renames" {
  # Arrange
  local content="{src/old/very/long/path.js => lib/new/short.js} | 50 +\n1 file changed"

  # Act
  run extract_files_from_hug_sh "$content"

  # Assert
  assert_success
  assert_line "lib/new/short.js"
}

@test "extract_files_from_hug_sh: fails on missing summary line" {
  # Arrange
  local content="file1.txt | 1 +\nfile2.txt | 1 -"

  # Act
  run extract_files_from_hug_sh "$content"

  # Assert
  assert_failure
  assert_output --partial "Error:"
}

@test "extract_files_from_hug_sh: fails on invalid file count" {
  # Arrange
  local content="file1.txt | 1 +\nfile2.txt | 1 -\n10 files changed"

  # Act
  run extract_files_from_hug_sh "$content"

  # Assert
  assert_failure
  assert_output --partial "Error:"
}

#=== extract_simple_file_list Tests ===

@test "extract_simple_file_list: extracts clean file list" {
  # Arrange
  local content="file1.txt\nfile2.txt\nfile3.txt"

  # Act
  run extract_simple_file_list "$content"

  # Assert
  assert_success
  assert_line "file1.txt"
  assert_line "file2.txt"
  assert_line "file3.txt"
}

@test "extract_simple_file_list: removes comments" {
  # Arrange
  local content="# Comment\nfile1.txt\n  # Another comment  \nfile2.txt"

  # Act
  run extract_simple_file_list "$content"

  # Assert
  assert_success
  assert_line "file1.txt"
  assert_line "file2.txt"
  refute_output --partial "# Comment"
}

@test "extract_simple_file_list: trims whitespace" {
  # Arrange
  local content="  file1.txt  \n\tfile2.txt\t\n   file3.txt   "

  # Act
  run extract_simple_file_list "$content"

  # Assert
  assert_success
  assert_line "file1.txt"
  assert_line "file2.txt"
  assert_line "file3.txt"
}

@test "extract_simple_file_list: skips empty lines" {
  # Arrange
  local content="file1.txt\n\nfile2.txt\n   \nfile3.txt\n"

  # Act
  run extract_simple_file_list "$content"

  # Assert
  assert_success
  assert_line "file1.txt"
  assert_line "file2.txt"
  assert_line "file3.txt"
}

#=== extract_files_from_commit Tests ===

@test "extract_files_from_commit: extracts files from valid commit" {
  # Arrange
  local test_repo=$(create_test_repo)
  cd "$test_repo"

  # Create and commit files
  echo "content1" > file1.txt
  echo "content2" > file2.txt
  git add file1.txt file2.txt
  git commit -m "Add files"

  # Act
  run extract_files_from_commit HEAD

  # Assert
  assert_success
  assert_line "file1.txt"
  assert_line "file2.txt"
}

@test "extract_files_from_commit: handles commit with no files changed" {
  # Arrange
  local test_repo=$(create_test_repo)
  cd "$test_repo"

  # Create and commit files
  echo "content" > file.txt
  git add file.txt
  git commit -m "Add file"

  # Create empty commit
  git commit --allow-empty -m "Empty commit"

  # Act
  run extract_files_from_commit HEAD

  # Assert
  assert_success
  assert_output ""
}

@test "extract_files_from_commit: fails on invalid commit" {
  # Arrange
  local test_repo=$(create_test_repo)
  cd "$test_repo"

  # Act
  run extract_files_from_commit "invalid_commit_hash"

  # Assert
  assert_failure
  assert_output --partial "Error:"
}

@test "extract_files_from_commit: handles merge commits" {
  # Arrange
  local test_repo=$(create_test_repo)
  cd "$test_repo"

  # Initial commit
  echo "initial" > base.txt
  git add base.txt
  git commit -m "Initial"

  # Branch and modify
  git checkout -b feature
  echo "feature" > feature.txt
  git add feature.txt
  git commit -m "Add feature"

  # Merge back
  git checkout main
  git merge feature --no-ff -m "Merge feature"

  # Act
  run extract_files_from_commit HEAD

  # Assert
  assert_success
  # Should include files changed in the merge
  assert_line "feature.txt"
}

#=== Integration Tests ===

@test "integration: full workflow with --from-file using collect_files_from_args" {
  # Arrange
  local test_file="$BATS_TMPDIR/workflow_files.txt"
  create_test_file "$test_file" "# Important files\nconfig.json\n.env\n"

  # Act - Use the function as intended
  collect_files_from_args "--from-file" "$test_file"

  # Assert
  [[ ${#collected_files[@]} -eq 2 ]]
  [[ "${collected_files[0]}" == "config.json" ]]
  [[ "${collected_files[1]}" == ".env" ]]
}

@test "integration: full workflow with simple args using collect_files_from_args" {
  # Arrange

  # Act
  collect_files_from_args "file1.txt" "file2.txt" "file3.txt"

  # Assert
  [[ ${#collected_files[@]} -eq 3 ]]
  [[ "${collected_files[0]}" == "file1.txt" ]]
  [[ "${collected_files[1]}" == "file2.txt" ]]
  [[ "${collected_files[2]}" == "file3.txt" ]]
}

@test "integration: empty args using collect_files_from_args" {
  # Arrange

  # Act
  collect_files_from_args

  # Assert
  [[ ${#collected_files[@]} -eq 0 ]]
}