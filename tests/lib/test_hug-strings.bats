#!/usr/bin/env bats
# Tests for hug-strings library: string manipulation utilities

load '../test_helper'
load '../../git-config/lib/hug-strings'

@test "hug-strings: trim_message removes leading whitespace" {
  # Act
  result=$(trim_message "   text")
  
  # Assert
  assert_equal "$result" "text"
}

@test "hug-strings: trim_message removes trailing whitespace" {
  # Act
  result=$(trim_message "text   ")
  
  # Assert
  assert_equal "$result" "text"
}

@test "hug-strings: trim_message removes leading and trailing whitespace" {
  # Act
  result=$(trim_message "   text   ")
  
  # Assert
  assert_equal "$result" "text"
}

@test "hug-strings: trim_message handles tabs" {
  # Act
  result=$(trim_message $'\t\ttext\t\t')
  
  # Assert
  assert_equal "$result" "text"
}

@test "hug-strings: trim_message handles mixed whitespace" {
  # Act
  result=$(trim_message $' \t text \t ')
  
  # Assert
  assert_equal "$result" "text"
}

@test "hug-strings: trim_message preserves internal whitespace" {
  # Act
  result=$(trim_message "  hello world  ")
  
  # Assert
  assert_equal "$result" "hello world"
}

@test "hug-strings: trim_message handles empty string" {
  # Act
  result=$(trim_message "")
  
  # Assert
  assert_equal "$result" ""
}

@test "hug-strings: trim_message handles string with only whitespace" {
  # Act
  result=$(trim_message "   ")
  
  # Assert
  assert_equal "$result" ""
}

@test "hug-strings: trim_message handles string with no whitespace" {
  # Act
  result=$(trim_message "text")
  
  # Assert
  assert_equal "$result" "text"
}
