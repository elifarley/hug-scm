#!/usr/bin/env bats
# Tests for hug-file-input library: File input and parsing utilities

load '../test_helper'

# Source the library and dependencies
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-git-repo' # is_range for pinned_diff — hug-common does NOT load it
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

# Read NUL-separated records from <file> into the array named <out_arr>
# (house NUL-transport read, mirroring build_scope_set in hug-pathspec).
# WHY a helper: extract_files_from_commit emits RAW NUL-terminated records
# (-z semantics, elifarley/hug-scm#285), and `run`/`$output` strip NUL
# bytes — bash strings cannot hold them — so the stream's byte-level truth
# is invisible to assert_line. The NUL itself is the delimiter (filenames
# can never contain NUL), so records arrive NUL-free and array-safe.
read_nul_records() {
  local -n _rnr_out=$1
  local _rnr_file="$2"
  _rnr_out=()
  local _rnr_rec
  while IFS= read -r -d '' _rnr_rec; do
    _rnr_out+=("$_rnr_rec")
  done < "$_rnr_file"
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
  run bash -c 'source git-config/lib/hug-file-input; echo -e "file1.txt\nfile2.txt" | read_files_from_source -'

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
  local content="file1.txt | 1 +
file2.txt | 2 -
2 files changed"

  # Act
  run parse_file_content "$content"

  # Assert
  assert_success
  # Should output both files on separate lines
  assert_line "file1.txt"
  assert_line "file2.txt"
}

@test "parse_file_content: handles simple file list format" {
  # Arrange
  local content="file1.txt
file2.txt
file3.txt"

  # Act
  run parse_file_content "$content"

  # Assert
  assert_success
  # Should output all files when not hug sh format
  assert_line "file1.txt"
  assert_line "file2.txt"
  assert_line "file3.txt"
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
  local content="  file1.txt
	file2.txt
   file3.txt   "

  # Act
  run parse_file_content "$content"

  # Assert
  assert_success
  # Should output all files with whitespace trimmed
  assert_line "file1.txt"
  assert_line "file2.txt"
  assert_line "file3.txt"
}

#=== extract_files_from_hug_sh Tests ===

@test "extract_files_from_hug_sh: extracts files from valid hug sh output" {
  # Arrange
  local content="README.md | 5 +++++
src/main.js | 10 +++++++---
2 files changed"

  # Act
  run extract_files_from_hug_sh "$content"

  # Assert
  assert_success
  assert_line "README.md"
  assert_line "src/main.js"
}

@test "extract_files_from_hug_sh: handles renamed files (git show format)" {
  # Arrange - Use the format from hug sh (not git show)
  # Note: hug sh may not show renames in the same format as git show
  # This tests the basic functionality without relying on rename parsing
  local content="old_name.js | 100 ++++++
new_name.js | 50 ++++++----
other.txt | 5 ++
3 files changed"

  # Act
  run extract_files_from_hug_sh "$content"

  # Assert
  assert_success
  assert_line "old_name.js"
  assert_line "new_name.js"
  assert_line "other.txt"
}

@test "extract_files_from_hug_sh: handles simple changes" {
  # Arrange
  local content="file1.js | 10 +++++++
file2.js | 5 ---
2 files changed"

  # Act
  run extract_files_from_hug_sh "$content"

  # Assert
  assert_success
  assert_line "file1.js"
  assert_line "file2.js"
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
  local content="file1.txt
file2.txt
file3.txt"

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
  local content="# Comment
file1.txt
  # Another comment
file2.txt"

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
  local content="  file1.txt
	file2.txt
   file3.txt   "

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
  local content="file1.txt

file2.txt

file3.txt"

  # Act
  run extract_simple_file_list "$content"

  # Assert
  assert_success
  assert_line "file1.txt"
  assert_line "file2.txt"
  assert_line "file3.txt"
}

#=== extract_files_from_commit Tests ===
#
# NUL-STREAM CONTRACT (elifarley/hug-scm#285): extract_files_from_commit
# emits RAW NUL-terminated records (-z semantics, never C-quoted). `run`
# strips NUL bytes from $output, so NO test below may assert this function's
# stdout through $output/assert_line — every data assertion captures stdout
# to a temp file, then either cmp -s's the whole stream or reads records
# with read_nul_records.

@test "extract_files_from_commit: ASCII records byte-identical with old line-mode output (regression pin)" {
  # Arrange
  local test_repo=$(create_test_repo)
  cd "$test_repo"

  # Create and commit files
  echo "content1" > file1.txt
  echo "content2" > file2.txt
  git add file1.txt file2.txt
  git commit -m "Add files"

  # Act — capture the NUL stream to a file ($output would strip NULs)
  local out_file="$BATS_TMPDIR/efci_ascii.$$"
  extract_files_from_commit HEAD > "$out_file"

  # Assert — full stream byte-equal to the pre-change line-mode records,
  # NUL-terminated (tree order: file1.txt before file2.txt). Embeds the old
  # happy-path bytes so the -z switch provably changes nothing for plain
  # ASCII: same records, only the terminator/newline differs.
  printf 'file1.txt\0file2.txt\0' > "$BATS_TMPDIR/efci_ascii_expected.$$"
  run cmp -s "$out_file" "$BATS_TMPDIR/efci_ascii_expected.$$"
  assert_success
  local records=()
  read_nul_records records "$out_file"
  assert_equal ${#records[@]} 2
  assert_equal "${records[0]}" "file1.txt"
  assert_equal "${records[1]}" "file2.txt"
  rm -f "$out_file" "$BATS_TMPDIR/efci_ascii_expected.$$"
}

@test "extract_files_from_commit: structural-char filenames arrive RAW via NUL (core of #285)" {
  # Arrange — a literal backslash (C-quoted as "back\slash.txt" in line
  # mode) and a literal newline (C-quoted as "we\nird"). Line-mode output
  # made mapfile collect the QUOTED tokens, which are not paths — the
  # action list silently named files that do not exist.
  local test_repo=$(create_test_repo)
  cd "$test_repo"
  echo a > 'back\slash.txt'
  echo b > $'we\nird'
  git add -A && git commit -qm weird

  # Act
  local out_file="$BATS_TMPDIR/efci_weird.$$"
  extract_files_from_commit HEAD > "$out_file"

  # Assert — BYTE-EXACT oracle: raw backslash, raw newline byte, NUL
  # terminators, tree order (back\slash.txt before we\nird). Any C-quoting
  # anywhere in the stream fails this cmp.
  printf 'back\\slash.txt\0we\nird\0' > "$BATS_TMPDIR/efci_weird_expected.$$"
  run cmp -s "$out_file" "$BATS_TMPDIR/efci_weird_expected.$$"
  assert_success

  # Record count + exact per-record bytes through the NUL-safe reader.
  local records=()
  read_nul_records records "$out_file"
  assert_equal ${#records[@]} 2
  assert_equal "${records[0]}" 'back\slash.txt'
  assert_equal "${records[1]}" $'we\nird'
  rm -f "$out_file" "$BATS_TMPDIR/efci_weird_expected.$$"
}

@test "extract_files_from_commit: empty commit yields an empty stream (zero records)" {
  # Arrange
  local test_repo=$(create_test_repo)
  cd "$test_repo"

  echo "content" > file.txt
  git add file.txt
  git commit -m "Add file"

  # Create empty commit
  git commit --allow-empty -m "Empty commit"

  # Act
  local out_file="$BATS_TMPDIR/efci_empty.$$"
  local status=0
  extract_files_from_commit HEAD > "$out_file" || status=$?

  # Assert — zero records, and the file holds ZERO bytes (not even a
  # newline): the NUL contract emits no separator for an empty set.
  assert_equal "$status" 0
  assert_equal "$(wc -c < "$out_file")" 0
  local records=()
  read_nul_records records "$out_file"
  assert_equal ${#records[@]} 0
  rm -f "$out_file"
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

  # Create an additional file on the main branch before merging
  git checkout main
  echo "main-only" > main-only.txt
  git add main-only.txt
  git commit -m "Add main-only file"

  # Merge back with changes on both sides
  git merge feature --no-ff -m "Merge feature with additional changes"

  # Act
  run extract_files_from_commit HEAD

  # Assert
  assert_success
  # The merge commit should show files that were different between branches
  # We added main-only.txt on main before merging, so it might appear
  # Or it might be empty for pure merge commits, which is also valid
  # Both are acceptable behaviors
}

@test "extract_files_from_commit: rename lists BOTH sides as NUL records (action contract)" {
  local test_repo=$(create_test_repo)
  cd "$test_repo"
  echo a > old.txt
  git add -A && git commit -qm init
  git mv old.txt new.txt
  git commit -qm rename

  local out_file="$BATS_TMPDIR/efci_rename.$$"
  extract_files_from_commit HEAD > "$out_file"

  # Both sides: staging/untrack lists need the deleted side (--no-renames).
  # A display pin here would silently drop old.txt — rejected in review:
  # hug a --from-commit was working; a consolidation must not shrink action lists.
  # Tree order: new.txt before old.txt.
  printf 'new.txt\0old.txt\0' > "$BATS_TMPDIR/efci_rename_expected.$$"
  run cmp -s "$out_file" "$BATS_TMPDIR/efci_rename_expected.$$"
  assert_success
  local records=()
  read_nul_records records "$out_file"
  assert_equal ${#records[@]} 2
  assert_equal "${records[0]}" "new.txt"
  assert_equal "${records[1]}" "old.txt"
  rm -f "$out_file" "$BATS_TMPDIR/efci_rename_expected.$$"
}

@test "extract_files_from_commit: non-ASCII path stays raw bytes in the NUL stream under hostile quotePath" {
  local test_repo=$(create_test_repo)
  cd "$test_repo"
  git config core.quotePath true
  echo a > 'café.txt'
  git add -A && git commit -qm add

  local out_file="$BATS_TMPDIR/efci_cafe.$$"
  extract_files_from_commit HEAD > "$out_file"

  # Raw UTF-8 bytes, NUL-terminated — quotePath C-quoting ("caf\303\251.txt")
  # would fail this cmp even though pinned_diff defeats the config in line
  # mode too; -z is the only mode where structural chars are raw as well.
  printf 'café.txt\0' > "$BATS_TMPDIR/efci_cafe_expected.$$"
  run cmp -s "$out_file" "$BATS_TMPDIR/efci_cafe_expected.$$"
  assert_success
  local records=()
  read_nul_records records "$out_file"
  assert_equal ${#records[@]} 1
  assert_equal "${records[0]}" "café.txt"
  rm -f "$out_file" "$BATS_TMPDIR/efci_cafe_expected.$$"
}

#=== extract_files_from_commit_into Tests ===

@test "extract_files_from_commit_into: fills the array with raw structural-char records" {
  # Arrange
  local test_repo=$(create_test_repo)
  cd "$test_repo"
  echo a > 'back\slash.txt'
  echo b > $'we\nird'
  git add -A && git commit -qm weird

  # Act — the NUL-safe reader: no shell-variable capture, no process
  # substitution (both would mangle NULs or lose the guard's exit).
  local files=()
  extract_files_from_commit_into files HEAD

  # Assert
  assert_equal ${#files[@]} 2
  assert_equal "${files[0]}" 'back\slash.txt'
  assert_equal "${files[1]}" $'we\nird'
}

@test "extract_files_from_commit_into: invalid commit returns 1 and empties the array (guard exit survives)" {
  # Arrange
  local test_repo=$(create_test_repo)
  cd "$test_repo"
  echo a > a.txt
  git add -A && git commit -qm init

  # Act — the guard contract is FATAL in every consumer (a/us/untrack/ccp
  # spell `|| exit $?`; the lib helper composes `|| return $?`), so the
  # guard's exit must REACH the caller: the function may not detach it in a
  # process substitution, leak its temp file on this path, or let set -e
  # abort first.
  local files=("pre-existing")
  local status=0
  extract_files_from_commit_into files DOES_NOT_EXIST || status=$?

  # Assert
  assert_equal "$status" 1
  assert_equal ${#files[@]} 0
}

@test "extract_files_from_commit_into: empty commit leaves an empty array" {
  # Arrange
  local test_repo=$(create_test_repo)
  cd "$test_repo"
  echo a > a.txt
  git add -A && git commit -qm init
  git commit --allow-empty -qm empty

  # Act
  local files=("sentinel")
  extract_files_from_commit_into files HEAD

  # Assert — zero records; empty array flows on (set -u safe).
  assert_equal ${#files[@]} 0
}

#=== Integration Tests ===

@test "integration: workflow with --from-commit using extract_files_from_commit" {
  # Arrange
  local test_repo=$(create_test_repo)
  cd "$test_repo"

  # Create and commit files
  echo "config1" > config.json
  echo "env1" > .env
  git add config.json .env
  git commit -m "Add config files"

  # Act - extract through the NUL-safe reader (the path consumers use)
  local files=()
  extract_files_from_commit_into files HEAD

  # Assert — exact records in tree order (.env before config.json)
  assert_equal ${#files[@]} 2
  assert_equal "${files[0]}" ".env"
  assert_equal "${files[1]}" "config.json"
}

@test "integration: end-to-end workflow" {
  # Arrange
  local test_file="$BATS_TMPDIR/test_files.txt"
  create_test_file "$test_file" "config.json\n.env"

  # Act - Read files from source
  run read_files_from_source "$test_file"

  # Assert
  assert_success
  assert_line "config.json"
  assert_line ".env"
}
