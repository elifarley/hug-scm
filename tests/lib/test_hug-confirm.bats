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

@test "hug-confirm: confirm_action_danger succeeds with HUG_FORCE" {
  # Arrange
  export HUG_FORCE=true
  
  # Act
  run confirm_action_danger "delete"
  
  # Assert
  assert_success
}

@test "hug-confirm: confirm_action_danger succeeds when user types exact word" {
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    export HUG_DISABLE_GUM=true
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-strings'
    source 'git-config/lib/hug-confirm'
     echo 'delete' | confirm_action_danger 'delete'
  "
  
  # Assert
  assert_success
}

@test "hug-confirm: confirm_action_danger exits when user types wrong word" {
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    export HUG_DISABLE_GUM=true
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-strings'
    source 'git-config/lib/hug-confirm'
     echo 'wrong' | confirm_action_danger 'delete'
  "
  
  # Assert
  assert_failure
  assert_output --partial "Cancelled"
}

@test "hug-confirm: confirm_action_danger exits when user types nothing" {
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    export HUG_DISABLE_GUM=true
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-strings'
    source 'git-config/lib/hug-confirm'
     echo '' | confirm_action_danger 'delete'
  "
  
  # Assert
  assert_failure
  assert_output --partial "Cancelled"
}

@test "hug-confirm: confirm_action_danger exits on Ctrl-D" {
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    export HUG_DISABLE_GUM=true
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-strings'
    source 'git-config/lib/hug-confirm'
    confirm_action_danger 'delete' < /dev/null
  "
  
  # Assert
  assert_failure
  assert_output --partial "Cancelled"
}
