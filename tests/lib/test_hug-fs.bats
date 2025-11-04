#!/usr/bin/env bats
# Tests for hug-fs library: filesystem utilities

load '../test_helper'
load '../../git-config/lib/hug-fs'

@test "hug-fs: is_symlink returns true for symbolic links" {
  # Arrange: Create a test directory and symlink
  TEST_DIR=$(mktemp -d)
  touch "$TEST_DIR/target_file"
  ln -s "$TEST_DIR/target_file" "$TEST_DIR/symlink"
  
  # Act
  run is_symlink "$TEST_DIR/symlink"
  
  # Assert
  assert_success
  
  # Cleanup
  rm -rf "$TEST_DIR"
}

@test "hug-fs: is_symlink returns false for regular files" {
  # Arrange: Create a regular file
  TEST_DIR=$(mktemp -d)
  touch "$TEST_DIR/regular_file"
  
  # Act
  run is_symlink "$TEST_DIR/regular_file"
  
  # Assert
  assert_failure  # is_symlink outputs nothing and returns 1 for non-symlinks
  refute_output
  
  # Cleanup
  rm -rf "$TEST_DIR"
}

@test "hug-fs: is_symlink returns false for non-existent paths" {
  # Arrange: Non-existent path
  
  # Act
  run is_symlink "/non/existent/path"
  
  # Assert
  assert_failure
  refute_output
  
}
