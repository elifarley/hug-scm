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

# Tests for ANSI color handling
@test "hug-gum: normalize_selection strips ANSI color codes" {
  # Test with ANSI color codes (yellow and reset)
  run normalize_selection $'\x1b[33mbranch\x1b[0m'
  assert_success
  assert_output "branch"
}

@test "hug-gum: normalize_selection strips ANSI codes with asterisk" {
  run normalize_selection $'* \x1b[33mmain\x1b[0m abc123'
  assert_success
  assert_output "main"
}

@test "hug-gum: normalize_selection handles upstream status with colon" {
  run normalize_selection "origin/feat: ahead 2"
  assert_success
  assert_output "origin/feat"
}

@test "hug-gum: normalize_selection handles complex git status with ANSI" {
  # Simulates: colored branch name with upstream tracking
  run normalize_selection $'\x1b[32mfeature\x1b[0m [origin/feature: ahead 1]'
  assert_success
  assert_output "feature"
}

@test "hug-gum: normalize_selection handles branch with spaces and ANSI" {
  # Branch name followed by colored hash
  run normalize_selection $'feature \x1b[33mabc123\x1b[0m subject text'
  assert_success
  assert_output "feature"
}

# Test for HUG_QUIET support
@test "hug-gum: gum_log respects HUG_QUIET" {
  # Mock gum to not be available
  gum_available() { return 1; }
  
  # Act with HUG_QUIET set
  export HUG_QUIET=T
  run gum_log "INFO" "test message"
  
  # Assert - should produce no output when quiet
  assert_success
  assert_output ""
  
  unset HUG_QUIET
}

@test "hug-gum: gum_log produces output when HUG_QUIET not set" {
  # Mock gum to not be available
  gum_available() { return 1; }
  
  # Act without HUG_QUIET
  unset HUG_QUIET
  run gum_log "INFO" "test message"
  
  # Assert - should produce output
  assert_success
  assert_output --partial "INFO: test message"
}

# Test edge cases in gum_filter_by_index
@test "hug-gum: gum_filter_by_index with ANSI colors in formatted options" {
  # Arrange - formatted options with ANSI codes
  local -a test_formatted=($'\x1b[33mbranch1\x1b[0m abc123' $'\x1b[33mbranch2\x1b[0m def456')
  local -a test_keys=("branch1" "branch2")
  
  # Mock gum filter to return colored selection
  gum() {
    if [[ "$1" == "filter" ]]; then
      echo $'\x1b[33mbranch2\x1b[0m def456'
      return 0
    fi
    return 1
  }
  
  # Act
  run gum_filter_by_index test_formatted "Select branch" --match-keys test_keys
  
  # Assert
  assert_success
  assert_output "1"
}
