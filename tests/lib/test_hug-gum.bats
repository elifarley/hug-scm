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
