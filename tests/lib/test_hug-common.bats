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

################################################################################
# HUG_HOME self-resolution tests
#
# hug-common auto-derives HUG_HOME from BASH_SOURCE[1] (the sourcing script's
# path) when HUG_HOME is unset.  The logic: resolve the caller's realpath,
# go up two dirs (bin/ -> git-config/ -> repo-root), then verify
# repo-root/git-config/lib/hug-common exists.  This mirrors the CMD_BASE
# pattern in bin scripts: all bin scripts live in git-config/bin/.
################################################################################

@test "hug-common self-resolves HUG_HOME from BASH_SOURCE" {
  # WHY: In production, bin scripts source hug-common without setting HUG_HOME
  # first (HUG_HOME is only guaranteed in the outer `hug` dispatcher or via
  # `bin/activate`).  The self-resolution lets individual bin scripts work
  # standalone — e.g. when invoked directly as git-config/bin/git-s.
  #
  # Approach: Create a thin wrapper script in git-config/bin/ that sources
  # hug-common and prints HUG_HOME.  This exactly mirrors how real bin
  # scripts source it — BASH_SOURCE[1] will be the wrapper's path.

  local wrapper="$PROJECT_ROOT/git-config/bin/_test_self_resolve"
  cat > "$wrapper" << 'WRAPPER'
#!/usr/bin/env bash
# shellcheck source=../lib/hug-common
. "$(dirname "$0")/../lib/hug-common"
echo "$HUG_HOME"
WRAPPER
  chmod +x "$wrapper"

  # Unset HUG_HOME so self-resolution kicks in.  _HUG_COMMON_LOADED must also
  # be cleared since the test process inherited it from test_helper setup.
  run bash -c "unset HUG_HOME _HUG_COMMON_LOADED; '$wrapper'"

  # Cleanup
  rm -f "$wrapper"

  # Assert — HUG_HOME should resolve to the repo root
  assert_success
  assert_output "$PROJECT_ROOT"
}

@test "hug-common preserves existing HUG_HOME when already set" {
  # WHY: External callers (the `hug` dispatcher, CI, user shell) set HUG_HOME
  # before sourcing.  Self-resolution must NOT clobber an explicit value,
  # especially when the user has pointed HUG_HOME at a worktree or custom
  # install location.

  local wrapper="$PROJECT_ROOT/git-config/bin/_test_preserve_home"
  cat > "$wrapper" << 'WRAPPER'
#!/usr/bin/env bash
# shellcheck source=../lib/hug-common
. "$(dirname "$0")/../lib/hug-common"
echo "$HUG_HOME"
WRAPPER
  chmod +x "$wrapper"

  # Set HUG_HOME to a distinct value and clear the idempotency guard.
  # Suppress stderr — the fake path causes "could not source" warnings for
  # every library, which is expected and irrelevant to this test.
  local fake_home="/nonexistent/fake-hug-home"
  run bash -c "export HUG_HOME='$fake_home'; unset _HUG_COMMON_LOADED; '$wrapper' 2>/dev/null"

  # Cleanup
  rm -f "$wrapper"

  # Assert — the explicit HUG_HOME must survive sourcing untouched
  assert_success
  assert_output "$fake_home"
}

@test "hug-common returns 1 when derivation fails (non-bin path)" {
  # WHY: Self-resolution depends on the caller being in git-config/bin/ so
  # that dirname/../.. lands on the repo root.  If sourced from an arbitrary
  # location (e.g. a user's ~/bin or /tmp), the derivation should fail
  # gracefully with a non-zero return code and a diagnostic message.

  # Source hug-common from /tmp — dirname/../.. will be /, which won't contain
  # git-config/lib/hug-common, so derivation must fail.
  run bash -c "
    unset HUG_HOME _HUG_COMMON_LOADED
    cd /tmp
    source '$PROJECT_ROOT/git-config/lib/hug-common' 2>&1
  "

  assert_failure 1
  # The error message should mention the source path and the derivation failure
  assert_output --partial "HUG_HOME not set"
}

@test "hug-common does not call exit (uses return 1)" {
  # WHY: In a sourced file, `exit 1` would kill the calling script
  # immediately — no cleanup, no fallback, no chance for hug-git-kit to
  # handle the missing HUG_LIB_DIR.  The code intentionally uses `return 1`
  # so the sourcing script retains control.  This test verifies the outer
  # shell survives the failed source.

  # The outer bash -c continues executing after the failed source; if
  # hug-common used `exit` instead of `return`, the echo would never run.
  run bash -c "
    unset HUG_HOME _HUG_COMMON_LOADED
    cd /tmp
    source '$PROJECT_ROOT/git-config/lib/hug-common' 2>/dev/null || true
    echo 'survived'
  "

  # Assert — the outer script is still alive
  assert_success
  assert_output "survived"
}
