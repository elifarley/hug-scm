#!/usr/bin/env bats
# Tests for hug-output library: output and messaging functions

load '../test_helper'
load '../../git-config/lib/hug-terminal'
load '../../git-config/lib/hug-gum'
load '../../git-config/lib/hug-output'

# Mock gum to not be available for most tests
setup() {
  export HUG_DISABLE_GUM=true
}

teardown() {
  unset HUG_DISABLE_GUM
  unset HUG_QUIET
}

@test "hug-output: error displays error message and exits" {
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    export HUG_DISABLE_GUM=true
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    error 'test error message'
  "
  
  # Assert
  assert_failure
  assert_output --partial "Error:"
  assert_output --partial "test error message"
}

@test "hug-output: error exits with custom exit code" {
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    export HUG_DISABLE_GUM=true
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    error 'test error' 42
  "
  
  # Assert
  assert_equal "$status" 42
}

@test "hug-output: warning displays warning message" {
  # Act
  run warning "test warning"
  
  # Assert
  assert_success
  assert_output --partial "Warning:"
  assert_output --partial "test warning"
}

@test "hug-output: warning respects HUG_QUIET" {
  # Arrange
  export HUG_QUIET=T
  
  # Act
  run warning "should not appear"
  
  # Assert
  assert_success
  refute_output
}

@test "hug-output: warn is alias for warning" {
  # Act
  run warn "test warning"
  
  # Assert
  assert_success
  assert_output --partial "Warning:"
  assert_output --partial "test warning"
}

@test "hug-output: info displays info message" {
  # Act
  run info "test info"
  
  # Assert
  assert_success
  assert_output --partial "Info:"
  assert_output --partial "test info"
}

@test "hug-output: info respects HUG_QUIET" {
  # Arrange
  export HUG_QUIET=T
  
  # Act
  run info "should not appear"
  
  # Assert
  assert_success
  refute_output
}

@test "hug-output: tip displays tip message" {
  # Act
  run tip "test tip"
  
  # Assert
  assert_success
  assert_output --partial "Tip:"
  assert_output --partial "test tip"
}

@test "hug-output: tip respects HUG_QUIET" {
  # Arrange
  export HUG_QUIET=T
  
  # Act
  run tip "should not appear"
  
  # Assert
  assert_success
  refute_output
}

@test "hug-output: success displays success message" {
  # Act
  run success "test success"
  
  # Assert
  assert_success
  assert_output --partial "Success:"
  assert_output --partial "test success"
}

@test "hug-output: success respects HUG_QUIET" {
  # Arrange
  export HUG_QUIET=T
  
  # Act
  run success "should not appear"
  
  # Assert
  assert_success
  refute_output
}

@test "hug-output: print_nothing_to_do uses default scope" {
  # Act
  run print_nothing_to_do "discard"
  
  # Assert
  assert_success
  assert_output --partial "Nothing to discard"
  assert_output --partial "for the selected scope"
}

@test "hug-output: print_nothing_to_do accepts custom scope" {
  # Act
  run print_nothing_to_do "zap" "in the repository."
  
  # Assert
  assert_success
  assert_output --partial "Nothing to zap"
  assert_output --partial "in the repository."
}

@test "hug-output: print_dry_run_preview uses default scope" {
  # Act
  run print_dry_run_preview "be discarded"
  
  # Assert
  assert_success
  assert_output --partial "Dry run"
  assert_output --partial "be discarded"
  assert_output --partial "for the selected scope"
}

@test "hug-output: print_dry_run_preview accepts custom scope" {
  # Act
  run print_dry_run_preview "be removed" "from working directory."
  
  # Assert
  assert_success
  assert_output --partial "Dry run"
  assert_output --partial "be removed"
  assert_output --partial "from working directory."
}

@test "hug-output: print_action_preview uses default scope" {
  # Act
  run print_action_preview "discard the changes"
  
  # Assert
  assert_success
  assert_output --partial "About to discard the changes"
  assert_output --partial "for the selected scope"
}

@test "hug-output: print_action_preview accepts custom scope" {
  # Act
  run print_action_preview "remove files" "from staging area."
  
  # Assert
  assert_success
  assert_output --partial "About to remove files"
  assert_output --partial "from staging area."
}

@test "hug-output: print_staged_unstaged_paths displays both arrays" {
  # Arrange
  source 'git-config/lib/hug-arrays'
  staged=("file1.txt" "file2.txt")
  unstaged=("file3.txt" "file4.txt")
  
  # Act
  run print_staged_unstaged_paths staged unstaged true true
  
  # Assert
  assert_success
  assert_output --partial "Staged paths:"
  assert_output --partial "file1.txt"
  assert_output --partial "file2.txt"
  assert_output --partial "Unstaged paths:"
  assert_output --partial "file3.txt"
  assert_output --partial "file4.txt"
  assert_output --partial "Both staged and unstaged would be fully discarded"
}

@test "hug-output: print_staged_unstaged_paths shows preserve note for staged-only" {
  # Arrange
  source 'git-config/lib/hug-arrays'
  staged=("file1.txt")
  unstaged=()
  
  # Act
  run print_staged_unstaged_paths staged unstaged true false
  
  # Assert
  assert_success
  assert_output --partial "unstaged changes in these files would be preserved"
  assert_output --partial "file1.txt"
}

@test "hug-output: print_staged_unstaged_paths handles empty arrays" {
  # Arrange
  source 'git-config/lib/hug-arrays'
  staged=()
  unstaged=()
  
  # Act
  run print_staged_unstaged_paths staged unstaged true true
  
  # Assert
  assert_success
  refute_output --partial "Staged paths:"
  refute_output --partial "Unstaged paths:"
}

@test "hug-output: print_untracked_ignored_paths displays both arrays" {
  # Arrange
  source 'git-config/lib/hug-arrays'
  untracked=("new1.txt" "new2.txt")
  ignored=(".DS_Store" "node_modules/")
  
  # Act
  run print_untracked_ignored_paths untracked ignored true true
  
  # Assert
  assert_success
  assert_output --partial "Untracked"
  assert_output --partial "new1.txt"
  assert_output --partial "new2.txt"
  assert_output --partial "Ignored"
  assert_output --partial ".DS_Store"
}

@test "hug-output: print_untracked_ignored_paths respects target flags" {
  # Arrange
  source 'git-config/lib/hug-arrays'
  untracked=("new1.txt")
  ignored=(".DS_Store")
  
  # Act - only target untracked
  run print_untracked_ignored_paths untracked ignored true false
  
  # Assert
  assert_success
  assert_output --partial "Untracked"
  assert_output --partial "new1.txt"
  refute_output --partial "Ignored"
  refute_output --partial ".DS_Store"
}
