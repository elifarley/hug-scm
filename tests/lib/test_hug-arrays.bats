#!/usr/bin/env bats
# Tests for hug-arrays library: array manipulation utilities

load '../test_helper'
load '../../git-config/lib/hug-arrays'

@test "hug-arrays: dedupe_array removes duplicates" {
  # Arrange
  local arr=("apple" "banana" "apple" "cherry" "banana")
  
  # Act
  dedupe_array arr
  
  # Assert
  assert_equal "${#arr[@]}" 3
  assert_equal "${arr[0]}" "apple"
  assert_equal "${arr[1]}" "banana"
  assert_equal "${arr[2]}" "cherry"
}

@test "hug-arrays: dedupe_array preserves order of first occurrence" {
  # Arrange
  local arr=("first" "second" "first" "third" "second")
  
  # Act
  dedupe_array arr
  
  # Assert
  assert_equal "${#arr[@]}" 3
  assert_equal "${arr[0]}" "first"
  assert_equal "${arr[1]}" "second"
  assert_equal "${arr[2]}" "third"
}

@test "hug-arrays: dedupe_array filters out empty strings" {
  # Arrange
  local arr=("a" "" "b" "" "c")
  
  # Act
  dedupe_array arr
  
  # Assert
  assert_equal "${#arr[@]}" 3
  assert_equal "${arr[0]}" "a"
  assert_equal "${arr[1]}" "b"
  assert_equal "${arr[2]}" "c"
}

@test "hug-arrays: dedupe_array handles array with no duplicates" {
  # Arrange
  local arr=("one" "two" "three")
  
  # Act
  dedupe_array arr
  
  # Assert
  assert_equal "${#arr[@]}" 3
  assert_equal "${arr[0]}" "one"
  assert_equal "${arr[1]}" "two"
  assert_equal "${arr[2]}" "three"
}

@test "hug-arrays: dedupe_array handles empty array" {
  # Arrange
  local arr=()
  
  # Act
  dedupe_array arr
  
  # Assert
  assert_equal "${#arr[@]}" 0
}

@test "hug-arrays: dedupe_array handles array with all duplicates" {
  # Arrange
  local arr=("same" "same" "same")
  
  # Act
  dedupe_array arr
  
  # Assert
  assert_equal "${#arr[@]}" 1
  assert_equal "${arr[0]}" "same"
}

@test "hug-arrays: print_list displays title and items" {
  # Act
  run print_list "Test Items" "item1" "item2" "item3"
  
  # Assert
  assert_success
  assert_output --partial "Test Items (3):"
  assert_output --partial "  item1"
  assert_output --partial "  item2"
  assert_output --partial "  item3"
}

@test "hug-arrays: print_list handles single item" {
  # Act
  run print_list "Single" "only"
  
  # Assert
  assert_success
  assert_output --partial "Single (1):"
  assert_output --partial "  only"
}

@test "hug-arrays: print_list handles no items" {
  # Act
  run print_list "Empty List"
  
  # Assert
  assert_success
  assert_output "Empty List (0):"
}

@test "hug-arrays: print_list handles items with spaces" {
  # Act
  run print_list "Files" "file with spaces.txt" "another file.txt"

  # Assert
  assert_success
  assert_output --partial "Files (2):"
  assert_output --partial "  file with spaces.txt"
  assert_output --partial "  another file.txt"
}

# --- print_list --cap / --more-hint tests ---

@test "print_list: --cap with overflow — shows first N + overflow line" {
  run print_list --cap 2 "T" a b c d
  assert_success
  assert_output --partial "T (4):"
  assert_output --partial "  a"
  assert_output --partial "  b"
  refute_output --partial "  c"
  assert_output --partial "... (+2 more)"
}

@test "print_list: --cap with non-empty --more-hint" {
  run print_list --cap 2 --more-hint "see more" "T" a b c d
  assert_success
  assert_output --partial "... (+2 more — see more)"
}

@test "print_list: --cap with empty --more-hint — no trailing em-dash" {
  run print_list --cap 2 --more-hint "" "T" a b c d
  assert_success
  assert_output --partial "... (+2 more)"
  refute_output --partial "—"
}

@test "print_list: count ≤ cap — no overflow line" {
  run print_list --cap 5 "T" a b
  assert_success
  assert_output --partial "T (2):"
  refute_output --partial "more"
}

@test "print_list: --cap 0 — treated as no-cap" {
  run print_list --cap 0 "T" a b c
  assert_success
  assert_output --partial "  c"
  refute_output --partial "more"
}

@test "print_list: --cap 08 — decimal 8, not octal error" {
  # 9 items, cap 8: should show 8 items + 1 overflow
  run print_list --cap 08 "T" a b c d e f g h i
  assert_success
  assert_output --partial "T (9):"
  assert_output --partial "  h"
  refute_output --partial "  i"
  assert_output --partial "... (+1 more)"
}

@test "print_list: --more-hint without --cap — hint ignored" {
  run print_list --more-hint "x" "T" a b c
  assert_success
  refute_output --partial "more"
}

@test "print_list: --cap with no value (end of args) — error, return 1" {
  # No title, no items — --cap is the LAST arg, value is missing.
  run print_list --cap
  assert_failure
  assert_output --partial "requires a value"
}

@test "print_list: --cap value not an integer — error, return 1" {
  # --cap has a value (T), but T is non-numeric — different error message.
  run print_list --cap T "Title" a b
  assert_failure
  assert_output --partial "non-negative integer"
}

@test "print_list: --cap value too large (overflow guard) — error, return 1" {
  # Bash arithmetic silently overflows huge numbers; bound the cap to
  # prevent silent corruption (cap=99999999999999999999999 wraps to garbage).
  run print_list --cap 99999999999999999999999 "T" a b
  assert_failure
  assert_output --partial "out of range"
}

@test "print_list: --cap with no title/items — error, return 1" {
  # Under set -u, `local title=$1` with no args fails. Guard against this.
  run print_list --cap 5
  assert_failure
  assert_output --partial "requires a title"
}

@test "print_list: -- delimiter — leading-dash title parsed" {
  run print_list --cap 2 -- "--my title--" a b c d
  assert_success
  assert_output --partial "--my title-- (4):"
  assert_output --partial "... (+2 more)"
}

@test "print_list: all output on stderr, stdout empty" {
  # Source the full library files (NOT line-range slices — fragile across edits).
  # Both files only define functions at top level; no execution side effects.
  run bash -c '. "'"$BATS_TEST_DIRNAME"'/../../git-config/lib/hug-common"; . "'"$BATS_TEST_DIRNAME"'/../../git-config/lib/hug-arrays"; print_list --cap 1 "T" a b 2>/dev/null'
  assert_success
  assert_output ""
}

@test "print_list: HUG_QUIET does NOT suppress output (print_list is data, not chatter)" {
  # Without HUG_QUIET, output appears
  run bash -c '. "'"$BATS_TEST_DIRNAME"'/../../git-config/lib/hug-common"; . "'"$BATS_TEST_DIRNAME"'/../../git-config/lib/hug-arrays"; print_list "T" a b 2>&1'
  assert_success
  assert_output --partial "T (2):"
  # With HUG_QUIET set, output STILL appears — print_list is used in dry-run paths
  # where the file list IS the data. Callers gate themselves if they want silence.
  run bash -c 'HUG_QUIET=T . "'"$BATS_TEST_DIRNAME"'/../../git-config/lib/hug-common"; HUG_QUIET=T . "'"$BATS_TEST_DIRNAME"'/../../git-config/lib/hug-arrays"; HUG_QUIET=T print_list "T" a b 2>&1'
  assert_success
  assert_output --partial "T (2):"
}
