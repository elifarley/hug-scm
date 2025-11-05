#!/usr/bin/env bats
# Tests for hug-terminal library: color definitions

load '../test_helper'

@test "hug-terminal: loads without errors" {
  # Act
  run bash -c "cd '$BATS_TEST_DIRNAME/../..'; source 'git-config/lib/hug-terminal'; echo 'loaded'"
  
  # Assert
  assert_success
  assert_output --partial "loaded"
}

@test "hug-terminal: defines color variables" {
  # Act & Assert - source the library and check variables exist
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-terminal'
    [[ -n \"\${RED+x}\" ]] && echo 'RED defined'
    [[ -n \"\${GREEN+x}\" ]] && echo 'GREEN defined'
    [[ -n \"\${YELLOW+x}\" ]] && echo 'YELLOW defined'
    [[ -n \"\${BLUE+x}\" ]] && echo 'BLUE defined'
    [[ -n \"\${MAGENTA+x}\" ]] && echo 'MAGENTA defined'
    [[ -n \"\${CYAN+x}\" ]] && echo 'CYAN defined'
    [[ -n \"\${GREY+x}\" ]] && echo 'GREY defined'
    [[ -n \"\${NC+x}\" ]] && echo 'NC defined'
  "
  
  assert_success
  assert_output --partial "RED defined"
  assert_output --partial "GREEN defined"
  assert_output --partial "YELLOW defined"
  assert_output --partial "BLUE defined"
  assert_output --partial "MAGENTA defined"
  assert_output --partial "CYAN defined"
  assert_output --partial "GREY defined"
  assert_output --partial "NC defined"
}

@test "hug-terminal: color variables are readonly" {
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-terminal'
    RED='modified' 2>&1 || echo 'readonly'
  "
  
  # Assert
  assert_output --partial "readonly"
}

@test "hug-terminal: color variables are exported" {
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-terminal'
    bash -c 'if [[ -n \"\${RED+x}\" ]]; then echo \"exported\"; fi'
  "
  
  # Assert
  assert_output "exported"
}

@test "hug-terminal: colors are empty when not a tty" {
  # Act - run in non-interactive mode (no tty)
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-terminal'
    if [[ -z \"\$RED\" ]]; then echo 'empty'; fi
  "
  
  # Assert - colors should be empty when not a tty
  assert_output "empty"
}
