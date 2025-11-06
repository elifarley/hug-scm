#!/usr/bin/env bats
# Tests for hug-gum library: gum integration helpers

load '../test_helper'
load '../../git-config/lib/hug-gum'
load '../../git-config/lib/hug-output'

@test "hug-gum: gum_available returns success when gum is in PATH" {
  # Arrange - mock gum command
  command() {
    if [[ "$1" == "-v" && "$2" == "gum" ]]; then
      return 0
    fi
    builtin command "$@"
  }
  export -f command
  
  # Act
  run gum_available
  
  # Assert
  assert_success
}

@test "hug-gum: gum_available returns failure when gum is not in PATH" {
  # Arrange - mock gum command as not found
  command() {
    if [[ "$1" == "-v" && "$2" == "gum" ]]; then
      return 1
    fi
    builtin command "$@"
  }
  export -f command
  
  # Act
  run gum_available
  
  # Assert
  assert_failure
}

@test "hug-gum: gum_available returns failure when HUG_DISABLE_GUM is true" {
  # Arrange
  export HUG_DISABLE_GUM=true
  
  # Act
  run gum_available
  
  # Assert
  assert_failure
  
  # Cleanup
  unset HUG_DISABLE_GUM
}

@test "hug-gum: gum_available ignores gum in PATH when HUG_DISABLE_GUM is true" {
  # Arrange
  export HUG_DISABLE_GUM=true
  # Even if gum is available, it should return failure
  
  # Act
  run gum_available
  
  # Assert
  assert_failure
  
  # Cleanup
  unset HUG_DISABLE_GUM
}

@test "hug-gum: gum_available works when HUG_DISABLE_GUM is not set" {
  # Arrange - ensure variable is not set
  unset HUG_DISABLE_GUM
  
  # Mock command to simulate gum being available
  command() {
    if [[ "$1" == "-v" && "$2" == "gum" ]]; then
      return 0
    fi
    builtin command "$@"
  }
  export -f command
  
  # Act
  run gum_available
  
  # Assert
  assert_success
}

@test "hug-gum: gum_available works when HUG_DISABLE_GUM is false" {
  # Arrange
  export HUG_DISABLE_GUM=false
  
  # Mock command to simulate gum being available
  command() {
    if [[ "$1" == "-v" && "$2" == "gum" ]]; then
      return 0
    fi
    builtin command "$@"
  }
  export -f command
  
  # Act
  run gum_available
  
  # Assert
  assert_success
  
  # Cleanup
  unset HUG_DISABLE_GUM
}

@test "hug-gum: gum_filter_extract with first word extraction" {
  # Arrange - create extractor function
  extract_first_word() { echo "${1%% *}"; }
  
  # Mock gum filter to return selection
  gum() {
    if [[ "$1" == "filter" ]]; then
      cat  # Just pass through input as selection
      return 0
    fi
    return 1
  }
  
  # Act - provide formatted input like "file.txt status"
  run gum_filter_extract "Test" "Cancelled" "extract_first_word" --no-limit < <(printf "%s\n" "file1.txt modified" "file2.js new")
  
  # Assert
  assert_success
  assert_line --index 0 "file1.txt"
  assert_line --index 1 "file2.js"
}

@test "hug-gum: gum_filter_extract returns failure when cancelled" {
  # Arrange - create extractor function
  extract_first_word() { echo "${1%% *}"; }
  
  # Mock gum filter to return empty (cancelled)
  gum() {
    if [[ "$1" == "filter" ]]; then
      return 1  # Simulate cancellation
    fi
    return 1
  }
  
  # Act
  run gum_filter_extract "Test" "No items selected" "extract_first_word" < <(printf "%s\n" "file1.txt modified")
  
  # Assert
  assert_failure
  assert_output --partial "No items selected"
}

@test "hug-gum: gum_filter_extract returns failure when no input provided" {
  # Arrange - create extractor function
  extract_first_word() { echo "${1%% *}"; }
  
  # Act - provide empty input
  run gum_filter_extract "Test" "No items" "extract_first_word" < /dev/null
  
  # Assert
  assert_failure
}

@test "hug-gum: gum_filter_extract handles single selection" {
  # Arrange - create extractor function
  extract_first_word() { echo "${1%% *}"; }
  
  # Mock gum filter to return single selection
  gum() {
    if [[ "$1" == "filter" ]]; then
      echo "branch1 hash123 commit message"
      return 0
    fi
    return 1
  }
  
  # Act
  run gum_filter_extract "Test" "Cancelled" "extract_first_word" < <(printf "%s\n" "branch1 hash123" "branch2 hash456")
  
  # Assert
  assert_success
  assert_output "branch1"
}

@test "hug-gum: gum_filter_extract with custom extractor" {
  # Arrange - create custom extractor that extracts text before arrow
  extract_before_arrow() { 
    local line="$1"
    echo "${line%% → *}"
  }
  
  # Mock gum filter
  gum() {
    if [[ "$1" == "filter" ]]; then
      cat  # Pass through
      return 0
    fi
    return 1
  }
  
  # Act
  run gum_filter_extract "Test" "Cancelled" "extract_before_arrow" --no-limit < <(printf "%s\n" "2024-11/01 → original" "2024-11/02 → feature")
  
  # Assert
  assert_success
  assert_line --index 0 "2024-11/01"
  assert_line --index 1 "2024-11/02"
}

@test "hug-gum: gum_filter_extract skips empty lines" {
  # Arrange - create extractor function
  extract_first_word() { echo "${1%% *}"; }
  
  # Mock gum filter
  gum() {
    if [[ "$1" == "filter" ]]; then
      printf "%s\n" "file1.txt modified" "" "file2.js new"  # Include empty line
      return 0
    fi
    return 1
  }
  
  # Act
  run gum_filter_extract "Test" "Cancelled" "extract_first_word" --no-limit < <(printf "%s\n" "file1.txt modified" "file2.js new")
  
  # Assert
  assert_success
  assert_line --index 0 "file1.txt"
  assert_line --index 1 "file2.js"
  # Should only have 2 lines (empty line skipped)
  [ "${#lines[@]}" -eq 2 ]
}

# Tests for new helper functions

@test "hug-gum: normalize_selection strips leading asterisk and space" {
  run normalize_selection "* main"
  assert_success
  assert_output "main"
}

@test "hug-gum: normalize_selection strips trailing whitespace" {
  run normalize_selection "branch  "
  assert_success
  assert_output "branch"
}

@test "hug-gum: normalize_selection extracts before arrow" {
  run normalize_selection "2024-11/02 → feature"
  assert_success
  assert_output "2024-11/02"
}

@test "hug-gum: normalize_selection extracts before parenthesis" {
  run normalize_selection "branch (abc123)"
  assert_success
  assert_output "branch"
}

@test "hug-gum: normalize_selection extracts first word by default" {
  run normalize_selection "branch hash123 subject"
  assert_success
  assert_output "branch"
}

@test "hug-gum: normalize_selection handles complex format" {
  run normalize_selection "* feature (abc123) [origin/feature] message"
  assert_success
  assert_output "feature"
}

@test "hug-gum: gum_invoke_filter returns selection" {
  # Arrange
  local -a options=("option1" "option2" "option3")
  
  # Mock gum filter
  gum() {
    if [[ "$1" == "filter" ]]; then
      echo "option2"
      return 0
    fi
    return 1
  }
  
  # Act
  run gum_invoke_filter options "Select option"
  
  # Assert
  assert_success
  assert_output "option2"
}

@test "hug-gum: gum_invoke_filter returns failure on cancel" {
  # Arrange
  local -a options=("option1" "option2")
  
  # Mock gum filter to simulate cancel
  gum() {
    if [[ "$1" == "filter" ]]; then
      return 1
    fi
    return 1
  }
  
  # Act
  run gum_invoke_filter options "Select option"
  
  # Assert
  assert_failure
}

@test "hug-gum: gum_invoke_filter returns failure for empty array" {
  # Arrange
  local -a options=()
  
  # Act
  run gum_invoke_filter options "Select option"
  
  # Assert
  assert_failure
}

@test "hug-gum: gum_invoke_filter supports multi-select with --no-limit" {
  # Arrange
  local -a options=("item1" "item2" "item3")
  
  # Mock gum filter to return multiple selections
  gum() {
    if [[ "$1" == "filter" ]]; then
      printf "%s\n" "item1" "item3"
      return 0
    fi
    return 1
  }
  
  # Act
  run gum_invoke_filter options "Select items" --no-limit
  
  # Assert
  assert_success
  assert_line --index 0 "item1"
  assert_line --index 1 "item3"
}

@test "hug-gum: gum_filter_by_index returns index of selected item" {
  # Arrange
  local -a test_options=("branch1 hash1" "branch2 hash2" "branch3 hash3")
  
  # Mock gum filter to return second item
  gum() {
    if [[ "$1" == "filter" ]]; then
      echo "branch2 hash2"
      return 0
    fi
    return 1
  }
  
  # Act
  run gum_filter_by_index test_options "Select branch"
  
  # Assert
  assert_success
  assert_output "1"
}

@test "hug-gum: gum_filter_by_index with --match-keys uses normalized matching" {
  # Arrange
  local -a test_formatted=("* main abc123 subject" "feature def456 message")
  local -a test_keys=("main" "feature")
  
  # Mock gum filter to return first item (with asterisk)
  gum() {
    if [[ "$1" == "filter" ]]; then
      echo "* main abc123 subject"
      return 0
    fi
    return 1
  }
  
  # Act
  run gum_filter_by_index test_formatted "Select branch" --match-keys test_keys
  
  # Assert
  assert_success
  assert_output "0"
}

@test "hug-gum: gum_filter_by_index returns multiple indices with --no-limit" {
  # Arrange
  local -a test_options=("file1.txt" "file2.js" "file3.py")
  
  # Mock gum filter to return multiple selections
  gum() {
    if [[ "$1" == "filter" ]]; then
      printf "%s\n" "file1.txt" "file3.py"
      return 0
    fi
    return 1
  }
  
  # Act
  run gum_filter_by_index test_options "Select files" --no-limit
  
  # Assert
  assert_success
  assert_line --index 0 "0"
  assert_line --index 1 "2"
}

@test "hug-gum: gum_filter_by_index returns failure on cancel" {
  # Arrange
  local -a test_options=("item1" "item2")
  
  # Mock gum filter to simulate cancel
  gum() {
    if [[ "$1" == "filter" ]]; then
      return 1
    fi
    return 1
  }
  
  # Act
  run gum_filter_by_index test_options "Select item"
  
  # Assert
  assert_failure
}

@test "hug-gum: gum_filter_by_index with match-keys handles arrow format" {
  # Arrange
  local -a test_formatted=("2024-11/01 → feature" "2024-11/02 → bugfix")
  local -a test_keys=("2024-11/01" "2024-11/02")
  
  # Mock gum filter
  gum() {
    if [[ "$1" == "filter" ]]; then
      echo "2024-11/02 → bugfix"
      return 0
    fi
    return 1
  }
  
  # Act
  run gum_filter_by_index test_formatted "Select backup" --match-keys test_keys
  
  # Assert
  assert_success
  assert_output "1"
}
