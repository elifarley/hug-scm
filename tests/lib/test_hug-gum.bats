#!/usr/bin/env bats
# Tests for hug-gum library: gum integration helpers

load '../test_helper'
load '../../git-config/lib/hug-gum'

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
