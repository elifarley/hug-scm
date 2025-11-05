#!/usr/bin/env bats
# Tests for hug-git-kit library: main entry point that sources all modules

load '../test_helper'
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-git-kit'

setup() {
  require_hug
}

@test "hug-git-kit: loads without errors" {
  # The load above should succeed if sourcing works correctly
  [[ -n "$_HUG_GIT_KIT_LOADED" ]]
}

@test "hug-git-kit: sets _HUG_GIT_KIT_LOADED guard" {
  [[ "$_HUG_GIT_KIT_LOADED" == "1" ]]
}

@test "hug-git-kit: prevents double loading" {
  # Try loading again - should not fail
  . "$HUG_LIB_DIR/hug-git-kit"
  [[ "$_HUG_GIT_KIT_LOADED" == "1" ]]
}

@test "hug-git-kit: sources hug-git-repo functions" {
  declare -F check_git_repo >/dev/null
}

@test "hug-git-kit: sources hug-git-state functions" {
  declare -F has_pending_changes >/dev/null
}

@test "hug-git-kit: sources hug-git-files functions" {
  declare -F list_staged_files >/dev/null
}

@test "hug-git-kit: sources hug-git-discard functions" {
  declare -F discard_all_unstaged >/dev/null
}

@test "hug-git-kit: sources hug-git-branch functions" {
  declare -F compute_local_branch_details >/dev/null
}

@test "hug-git-kit: sources hug-git-commit functions" {
  declare -F count_commits_in_range >/dev/null
}

@test "hug-git-kit: sources hug-git-upstream functions" {
  declare -F handle_upstream_operation >/dev/null
}

@test "hug-git-kit: sources hug-git-backup functions" {
  declare -F create_backup_branch >/dev/null
}

@test "hug-git-kit: sources hug-git-rebase functions" {
  declare -F rebase_pick >/dev/null
}
