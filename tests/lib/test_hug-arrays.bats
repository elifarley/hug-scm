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
