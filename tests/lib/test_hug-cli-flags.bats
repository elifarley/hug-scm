#!/usr/bin/env bats
# Tests for hug-cli-flags library: CLI flag parsing utilities

load '../test_helper'
load '../../git-config/lib/hug-output'
load '../../git-config/lib/hug-cli-flags'

setup() {
  export HUG_DISABLE_GUM=true
}

teardown() {
  unset HUG_DISABLE_GUM
  unset HUG_FORCE
  unset HUG_QUIET
  unset HUG_INTERACTIVE_FILE_SELECTION
}

@test "hug-cli-flags: parse_common_flags sets dry_run=true for --dry-run" {
  # Act
  eval "$(parse_common_flags --dry-run arg1 arg2)"
  
  # Assert
  assert_equal "$dry_run" "true"
  assert_equal "$1" "arg1"
  assert_equal "$2" "arg2"
}

@test "hug-cli-flags: parse_common_flags sets force=true for -f" {
  # Act
  eval "$(parse_common_flags -f arg1)"
  
  # Assert
  assert_equal "$force" "true"
  assert_equal "${HUG_FORCE:-}" "true"
  assert_equal "$1" "arg1"
}

@test "hug-cli-flags: parse_common_flags sets force=true for --force" {
  # Act
  eval "$(parse_common_flags --force arg1)"
  
  # Assert
  assert_equal "$force" "true"
  assert_equal "${HUG_FORCE:-}" "true"
  assert_equal "$1" "arg1"
}

@test "hug-cli-flags: parse_common_flags exports HUG_QUIET for --quiet" {
  # Act
  eval "$(parse_common_flags --quiet arg1)"
  
  # Assert
  assert_equal "${HUG_QUIET:-}" "T"
  assert_equal "$1" "arg1"
}

@test "hug-cli-flags: parse_common_flags handles multiple flags" {
  # Act
  eval "$(parse_common_flags --dry-run -f --quiet arg1 arg2)"
  
  # Assert
  assert_equal "$dry_run" "true"
  assert_equal "$force" "true"
  assert_equal "${HUG_FORCE:-}" "true"
  assert_equal "${HUG_QUIET:-}" "T"
  assert_equal "$1" "arg1"
  assert_equal "$2" "arg2"
}

@test "hug-cli-flags: parse_common_flags handles -- as separator" {
  # Act
  eval "$(parse_common_flags arg1 -- arg2 arg3)"
  
  # Assert
  assert_equal "$1" "arg1"
  assert_equal "$2" "arg2"
  assert_equal "$3" "arg3"
}

@test "hug-cli-flags: parse_common_flags sets HUG_INTERACTIVE_FILE_SELECTION when -- is last arg" {
  # Act
  eval "$(parse_common_flags arg1 arg2 --)"
  
  # Assert
  assert_equal "${HUG_INTERACTIVE_FILE_SELECTION:-}" "true"
  assert_equal "$1" "arg1"
  assert_equal "$2" "arg2"
  assert_equal "$#" "2"
}

@test "hug-cli-flags: parse_common_flags handles no arguments" {
  # Act
  eval "$(parse_common_flags)"
  
  # Assert
  assert_equal "$#" "0"
}

@test "hug-cli-flags: parse_common_flags preserves non-flag arguments" {
  # Act
  eval "$(parse_common_flags --dry-run file1.txt file2.txt)"
  
  # Assert
  assert_equal "$dry_run" "true"
  assert_equal "$1" "file1.txt"
  assert_equal "$2" "file2.txt"
}

@test "hug-cli-flags: parse_common_flags handles flags interspersed with args" {
  # Act
  eval "$(parse_common_flags arg1 --dry-run arg2 -f arg3)"
  
  # Assert
  assert_equal "$dry_run" "true"
  assert_equal "$force" "true"
  assert_equal "$1" "arg1"
  assert_equal "$2" "arg2"
  assert_equal "$3" "arg3"
}

@test "hug-cli-flags: parse_common_flags handles only -- as last argument" {
  # Act
  eval "$(parse_common_flags --)"
  
  # Assert
  assert_equal "${HUG_INTERACTIVE_FILE_SELECTION:-}" "true"
  assert_equal "$#" "0"
}

@test "hug-cli-flags: require_args passes with enough arguments" {
  # Arrange
  export HUG_DISABLE_GUM=true
  
  # Act
  run require_args 2 3 "custom message"
  
  # Assert
  assert_success
}

@test "hug-cli-flags: require_args fails with too few arguments" {
  # Arrange
  export HUG_DISABLE_GUM=true
  
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-cli-flags'
    require_args 3 1
  "
  
  # Assert
  assert_failure
  assert_output --partial "requires at least 3 argument(s)"
}

@test "hug-cli-flags: require_args uses custom error message" {
  # Arrange
  export HUG_DISABLE_GUM=true
  
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-cli-flags'
    require_args 2 1 'custom error message'
  "
  
  # Assert
  assert_failure
  assert_output --partial "custom error message"
}

@test "hug-cli-flags: require_args passes when actual equals required" {
  # Arrange
  export HUG_DISABLE_GUM=true
  
  # Act
  run require_args 2 2
  
  # Assert
  assert_success
}

@test "hug-cli-flags: parse_common_flags sets browse_root=true for --browse-root" {
  # Act
  eval "$(parse_common_flags --browse-root)"
  
  # Assert
  assert_equal "$browse_root" "true"
  assert_equal "${HUG_INTERACTIVE_FILE_SELECTION:-}" "true"
  assert_equal "$#" "0"
}

@test "hug-cli-flags: parse_common_flags handles --browse-root with other flags" {
  # Act
  eval "$(parse_common_flags --dry-run --browse-root -f)"
  
  # Assert
  assert_equal "$dry_run" "true"
  assert_equal "$browse_root" "true"
  assert_equal "$force" "true"
  assert_equal "${HUG_INTERACTIVE_FILE_SELECTION:-}" "true"
  assert_equal "$#" "0"
}

@test "hug-cli-flags: parse_common_flags errors when --browse-root used with args even with --" {
  # Act - Using a subshell to capture the error
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-cli-flags'
    eval \"\$(parse_common_flags --browse-root arg1 --)\"
  "
  
  # Assert
  assert_failure
  assert_output --partial "cannot be used with explicit paths"
}

@test "hug-cli-flags: parse_common_flags handles --browse-root alone" {
  # Act
  eval "$(parse_common_flags --browse-root)"
  
  # Assert
  assert_equal "$browse_root" "true"
  assert_equal "$#" "0"
  assert_equal "${HUG_INTERACTIVE_FILE_SELECTION:-}" "true"
}

@test "hug-cli-flags: parse_common_flags errors when --browse-root used with paths" {
  # Act - Using a subshell to capture the error
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-cli-flags'
    eval \"\$(parse_common_flags --browse-root file.txt)\"
  "
  
  # Assert
  assert_failure
  assert_output --partial "cannot be used with explicit paths"
}

@test "hug-cli-flags: check_browse_root_no_paths passes when browse_root is false" {
  # Act
  run check_browse_root_no_paths false true
  
  # Assert
  assert_success
}

@test "hug-cli-flags: check_browse_root_no_paths passes when no paths provided" {
  # Act
  run check_browse_root_no_paths true false
  
  # Assert
  assert_success
}

@test "hug-cli-flags: check_browse_root_no_paths fails when browse_root=true and has_paths=true" {
  # Act - Using a subshell to capture the error
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-cli-flags'
    check_browse_root_no_paths true true
  "
  
  # Assert
  assert_failure
  assert_output --partial "cannot be used with explicit paths"
}

@test "hug-cli-flags: check_browse_root_no_paths passes when both flags are false" {
  # Act
  run check_browse_root_no_paths false false
  
  # Assert
  assert_success
}

# Tests for GNU getopt enhancements

@test "hug-cli-flags: parse_common_flags handles combined short options -fq" {
  # Act
  eval "$(parse_common_flags -fq arg1)"
  
  # Assert
  assert_equal "$force" "true"
  assert_equal "${HUG_FORCE:-}" "true"
  assert_equal "${HUG_QUIET:-}" "T"
  assert_equal "$1" "arg1"
}

@test "hug-cli-flags: parse_common_flags handles combined short options -qf" {
  # Act
  eval "$(parse_common_flags -qf arg1 arg2)"
  
  # Assert
  assert_equal "$force" "true"
  assert_equal "${HUG_FORCE:-}" "true"
  assert_equal "${HUG_QUIET:-}" "T"
  assert_equal "$1" "arg1"
  assert_equal "$2" "arg2"
}

@test "hug-cli-flags: parse_common_flags handles -q short option for quiet" {
  # Act
  eval "$(parse_common_flags -q arg1)"
  
  # Assert
  assert_equal "${HUG_QUIET:-}" "T"
  assert_equal "$1" "arg1"
}

@test "hug-cli-flags: parse_common_flags handles combined -fqh (exits via help)" {
  # Act - Using a subshell to capture the help exit
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-cli-flags'
    show_help() { echo 'Help text'; }
    eval \"\$(parse_common_flags -fqh arg1)\"
  "
  
  # Assert
  assert_success
  assert_output "Help text"
}

@test "hug-cli-flags: parse_common_flags properly reorders options before args" {
  # With GNU getopt, options can come after args and will be reordered
  # Act
  eval "$(parse_common_flags arg1 --dry-run arg2 -f arg3 --quiet)"
  
  # Assert
  assert_equal "$dry_run" "true"
  assert_equal "$force" "true"
  assert_equal "${HUG_QUIET:-}" "T"
  assert_equal "$1" "arg1"
  assert_equal "$2" "arg2"
  assert_equal "$3" "arg3"
}
