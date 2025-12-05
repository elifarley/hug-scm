#!/usr/bin/env bats
# Tests for hug-common library: common bootstrap and library loading

load '../test_helper'

@test "hug-common: loads without errors" {
  # Act
  export HUG_HOME="$BATS_TEST_DIRNAME/../.."
  run bash -c "cd '$BATS_TEST_DIRNAME/../..'; source 'git-config/lib/hug-common'; echo 'loaded'"
  
  # Assert
  assert_success
  assert_output --partial "loaded"
}

@test "hug-common: sets _HUG_COMMON_LOADED guard" {
  # Act
  export HUG_HOME="$BATS_TEST_DIRNAME/../.."
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-common'
    if [[ -n \"\${_HUG_COMMON_LOADED:-}\" ]]; then
      echo 'guard set'
    fi
  "
  
  # Assert
  assert_success
  assert_output "guard set"
}

@test "hug-common: prevents double loading" {
  # Act
  export HUG_HOME="$BATS_TEST_DIRNAME/../.."
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-common'
    echo 'first load'
    source 'git-config/lib/hug-common'
    echo 'second load'
  "
  
  # Assert
  assert_success
  assert_output --partial "first load"
  assert_output --partial "second load"
}

@test "hug-common: sets HUG_LIB_DIR environment variable" {
  # Act
  export HUG_HOME="$BATS_TEST_DIRNAME/../.."
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-common'
    if [[ -n \"\${HUG_LIB_DIR:-}\" ]]; then
      echo 'HUG_LIB_DIR set'
    fi
  "
  
  # Assert
  assert_success
  assert_output "HUG_LIB_DIR set"
}

@test "hug-common: exports HUG_LIB_DIR" {
  # Act
  export HUG_HOME="$BATS_TEST_DIRNAME/../.."
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-common'
    bash -c 'if [[ -n \"\${HUG_LIB_DIR:-}\" ]]; then echo \"exported\"; fi'
  "
  
  # Assert
  assert_success
  assert_output "exported"
}

@test "hug-common: HUG_LIB_DIR points to lib directory" {
  # Act
  export HUG_HOME="$BATS_TEST_DIRNAME/../.."
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-common'
    basename \"\$HUG_LIB_DIR\"
  "
  
  # Assert
  assert_success
  assert_output "lib"
}

@test "hug-common: sources hug-terminal library" {
  # Act
  export HUG_HOME="$BATS_TEST_DIRNAME/../.."
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-common'
    if declare -p RED &>/dev/null; then
      echo 'hug-terminal sourced'
    fi
  "
  
  # Assert
  assert_success
  assert_output "hug-terminal sourced"
}

@test "hug-common: sources hug-gum library" {
  # Act
  export HUG_HOME="$BATS_TEST_DIRNAME/../.."
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-common'
    # Test that gum_available function is available (doesn't require direct gum checks)
    if type gum_available &>/dev/null; then
      echo 'hug-gum sourced'
    fi
  "

  # Assert
  assert_success
  assert_output "hug-gum sourced"
}

@test "hug-common: sources hug-output library" {
  # Act
  export HUG_HOME="$BATS_TEST_DIRNAME/../.."
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-common'
    if declare -f error &>/dev/null; then
      echo 'hug-output sourced'
    fi
  "
  
  # Assert
  assert_success
  assert_output "hug-output sourced"
}

@test "hug-common: sources hug-strings library" {
  # Act
  export HUG_HOME="$BATS_TEST_DIRNAME/../.."
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-common'
    if declare -f trim_message &>/dev/null; then
      echo 'hug-strings sourced'
    fi
  "
  
  # Assert
  assert_success
  assert_output "hug-strings sourced"
}

@test "hug-common: sources hug-arrays library" {
  # Act
  export HUG_HOME="$BATS_TEST_DIRNAME/../.."
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-common'
    if declare -f dedupe_array &>/dev/null; then
      echo 'hug-arrays sourced'
    fi
  "
  
  # Assert
  assert_success
  assert_output "hug-arrays sourced"
}

@test "hug-common: sources hug-fs library" {
  # Act
  export HUG_HOME="$BATS_TEST_DIRNAME/../.."
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-common'
    if declare -f is_symlink &>/dev/null; then
      echo 'hug-fs sourced'
    fi
  "
  
  # Assert
  assert_success
  assert_output "hug-fs sourced"
}

@test "hug-common: sources hug-cli-flags library" {
  # Act
  export HUG_HOME="$BATS_TEST_DIRNAME/../.."
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-common'
    if declare -f parse_common_flags &>/dev/null; then
      echo 'hug-cli-flags sourced'
    fi
  "
  
  # Assert
  assert_success
  assert_output "hug-cli-flags sourced"
}

@test "hug-common: sources hug-confirm library" {
  # Act
  export HUG_HOME="$BATS_TEST_DIRNAME/../.."
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-common'
    if declare -f prompt_confirm_warn &>/dev/null; then
      echo 'hug-confirm sourced'
    fi
  "
  
  # Assert
  assert_success
  assert_output "hug-confirm sourced"
}

@test "hug-common: sources hug-select-files library" {
  # Act
  export HUG_HOME="$BATS_TEST_DIRNAME/../.."
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-common'
    if declare -f select_files_with_status &>/dev/null; then
      echo 'hug-select-files sourced'
    fi
  "
  
  # Assert
  assert_success
  assert_output "hug-select-files sourced"
}

@test "hug-common: does not source hug-git-kit by default" {
  # Act
  export HUG_HOME="$BATS_TEST_DIRNAME/../.."
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-common'
    # Check for a function from hug-git-kit
    if declare -f git_current_branch &>/dev/null; then
      echo 'hug-git-kit sourced'
    else
      echo 'hug-git-kit not sourced'
    fi
  "
  
  # Assert
  assert_success
  assert_output "hug-git-kit not sourced"
}

@test "hug-common: handles missing library gracefully" {
  # Act - use a temporary directory without all libraries
  run bash -c "
    # Create a temp directory and copy hug-common there (but no other libs)
    TEMP_DIR=\$(mktemp -d)
    mkdir -p \"\$TEMP_DIR/git-config/lib\"
    cp '$BATS_TEST_DIRNAME/../../git-config/lib/hug-common' \"\$TEMP_DIR/git-config/lib/hug-common\"
    
    # Set HUG_HOME to temp for test
    export HUG_HOME=\"\$TEMP_DIR\"
    
    # Try to source it (will warn about missing libraries but shouldn't fail)
    cd \"\$TEMP_DIR/git-config/lib\"
    source hug-common 2>&1 | grep -q 'warning.*could not source' && echo 'warning shown'
    
    # Cleanup
    rm -rf \"\$TEMP_DIR\"
  "
  
  # Assert
  assert_success
  assert_output "warning shown"
}
