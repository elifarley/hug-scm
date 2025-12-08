#!/usr/bin/env bats
# Tests for hug-confirm library: confirmation prompts

load '../test_helper'
load '../../git-config/lib/hug-terminal'
load '../../git-config/lib/hug-gum'
load '../../git-config/lib/hug-output'
load '../../git-config/lib/hug-strings'
load '../../git-config/lib/hug-confirm'

# Mock gum to not be available for most tests
setup() {
  export HUG_DISABLE_GUM=true
}

teardown() {
  unset HUG_DISABLE_GUM
  unset HUG_FORCE
}

@test "hug-confirm: prompt_confirm_warn succeeds with HUG_FORCE" {
  # Arrange
  export HUG_FORCE=true
  
  # Act
  run prompt_confirm_warn
  
  # Assert
  assert_success
}

@test "hug-confirm: prompt_confirm_warn succeeds when user enters y" {
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    export HUG_DISABLE_GUM=true
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-strings'
    source 'git-config/lib/hug-confirm'
     echo 'y' | prompt_confirm_warn
  "
  
  # Assert
  assert_success
}

@test "hug-confirm: prompt_confirm_warn succeeds when user enters Y" {
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    export HUG_DISABLE_GUM=true
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-strings'
    source 'git-config/lib/hug-confirm'
     echo 'Y' | prompt_confirm_warn
  "
  
  # Assert
  assert_success
}

@test "hug-confirm: prompt_confirm_warn exits when user enters n" {
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    export HUG_DISABLE_GUM=true
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-strings'
    source 'git-config/lib/hug-confirm'
     echo 'n' | prompt_confirm_warn
  "
  
  # Assert
  assert_failure
  assert_output --partial "Cancelled"
}

@test "hug-confirm: prompt_confirm_warn exits when user enters N" {
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    export HUG_DISABLE_GUM=true
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-strings'
    source 'git-config/lib/hug-confirm'
     echo 'N' | prompt_confirm_warn
  "
  
  # Assert
  assert_failure
  assert_output --partial "Cancelled"
}

@test "hug-confirm: prompt_confirm_warn exits when user presses Ctrl-D" {
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    export HUG_DISABLE_GUM=true
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-strings'
    source 'git-config/lib/hug-confirm'
    prompt_confirm_warn < /dev/null
  "
  
  # Assert
  assert_failure
  assert_output --partial "Cancelled"
}

@test "hug-confirm: prompt_confirm_warn accepts custom prompt" {
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    export HUG_DISABLE_GUM=true
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-strings'
    source 'git-config/lib/hug-confirm'
     echo 'y' | prompt_confirm_warn 'Continue? [y/N]: '
  "
  
  # Assert
  assert_success
}

@test "hug-confirm: prompt_confirm_danger succeeds with HUG_FORCE" {
  # Arrange
  export HUG_FORCE=true
  
  # Act
  run prompt_confirm_danger "delete"
  
  # Assert
  assert_success
}

@test "hug-confirm: prompt_confirm_danger succeeds when user types exact word" {
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    export HUG_DISABLE_GUM=true
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-strings'
    source 'git-config/lib/hug-confirm'
     echo 'delete' | prompt_confirm_danger 'delete'
  "
  
  # Assert
  assert_success
}

@test "hug-confirm: prompt_confirm_danger exits when user types wrong word" {
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    export HUG_DISABLE_GUM=true
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-strings'
    source 'git-config/lib/hug-confirm'
     echo 'wrong' | prompt_confirm_danger 'delete'
  "
  
  # Assert
  assert_failure
  assert_output --partial "Cancelled"
}

@test "hug-confirm: prompt_confirm_danger exits when user types nothing" {
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    export HUG_DISABLE_GUM=true
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-strings'
    source 'git-config/lib/hug-confirm'
     echo '' | prompt_confirm_danger 'delete'
  "
  
  # Assert
  assert_failure
  assert_output --partial "Cancelled"
}

@test "hug-confirm: prompt_confirm_danger exits on Ctrl-D" {
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    export HUG_DISABLE_GUM=true
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-strings'
    source 'git-config/lib/hug-confirm'
    prompt_confirm_danger 'delete' < /dev/null
  "

  # Assert
  assert_failure
  assert_output --partial "Cancelled"
}

@test "hug-confirm: prompt_input returns user input without gum" {
  # Arrange
  export HUG_DISABLE_GUM=true

  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    export HUG_DISABLE_GUM=true
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-strings'
    source 'git-config/lib/hug-confirm'
    echo 'my-input' | prompt_input 'Enter value: ' 2>/dev/null
  "

  # Assert
  assert_success
  assert_output 'my-input'
}

@test "hug-confirm: prompt_input returns default when input is empty" {
  # Arrange
  export HUG_DISABLE_GUM=true

  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    export HUG_DISABLE_GUM=true
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-strings'
    source 'git-config/lib/hug-confirm'
    echo '' | prompt_input 'Enter value: ' 'default-value' 2>/dev/null
  "

  # Assert
  assert_success
  assert_output 'default-value'
}

@test "hug-confirm: prompt_input returns default when no default provided" {
  # Arrange
  export HUG_DISABLE_GUM=true

  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    export HUG_DISABLE_GUM=true
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-strings'
    source 'git-config/lib/hug-confirm'
    echo '' | prompt_input 'Enter value: ' 2>/dev/null
  "

  # Assert
  assert_success
  assert_output ''
}

# Note: gum mock tests for prompt_input are complex due to the mock behavior.
# The function is already tested with the non-gum fallback, which exercises the same code path.
