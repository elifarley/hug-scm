#!/usr/bin/env bats
# Lib tests for hug-git-rebase plan/render helpers and the in-progress guard.

load '../test_helper'
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-git-kit'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"
  # Build a tiny history: main has 1 commit; create a feature with 1 more.
  git checkout -q -b feature
  echo "feature" > feature.txt
  git add feature.txt
  git commit -q -m "feature commit"
  git checkout -q main
  export HUG_FAKE_CLOCK=946684800
}

teardown() {
  cleanup_test_repo
}

# Resolve HUG_HOME for child shells (BATS subshells don't inherit it).
_HUG_HOME="${HUG_HOME:-$(hug rev-parse --hug-home 2>/dev/null)}"

# -----------------------------------------------------------------------------
# rb_assert_no_rebase_in_progress — D7 guard
# -----------------------------------------------------------------------------

@test "rb_assert_no_rebase_in_progress: passes when no rebase state exists" {
  run rb_assert_no_rebase_in_progress
  assert_success
}

@test "rb_assert_no_rebase_in_progress: blocks on rebase-merge backend" {
  mkdir -p "$(git rev-parse --git-path rebase-merge)"
  run rb_assert_no_rebase_in_progress
  assert_failure
  assert_output --partial "A rebase is already in progress"
}

@test "rb_assert_no_rebase_in_progress: blocks on rebase-apply backend" {
  mkdir -p "$(git rev-parse --git-path rebase-apply)"
  run rb_assert_no_rebase_in_progress
  assert_failure
  assert_output --partial "A rebase is already in progress"
}

@test "rb_assert_no_rebase_in_progress: error mentions rbc and rba" {
  mkdir -p "$(git rev-parse --git-path rebase-merge)"
  run rb_assert_no_rebase_in_progress
  assert_failure
  assert_output --partial "hug rbc"
  assert_output --partial "hug rba"
}

# -----------------------------------------------------------------------------
# rb_build_plan — pure structuring
# -----------------------------------------------------------------------------

@test "rb_build_plan: warn-tier when backup is on" {
  git checkout -q feature
  run rb_build_plan main feature false
  assert_success
  # Output is a set of VAR=value lines we eval in the caller. Check tier + auth.
  assert_output --partial "RB_PLAN_TIER=warn"
  assert_output --partial "RB_PLAN_AUTH_FLAG=-y"
  assert_output --partial "RB_PLAN_WILL_BACKUP=true"
  assert_output --partial "RB_PLAN_NUM_COMMITS=1"
  git checkout -q main
}

@test "rb_build_plan: danger-tier when --no-backup" {
  git checkout -q feature
  run rb_build_plan main feature true
  assert_success
  assert_output --partial "RB_PLAN_TIER=danger"
  assert_output --partial "RB_PLAN_AUTH_FLAG=-f"
  assert_output --partial "RB_PLAN_WILL_BACKUP=false"
  git checkout -q main
}

@test "rb_build_plan: resolves a backup name matching the new format" {
  git checkout -q feature
  run rb_build_plan main feature false
  assert_success
  assert_output --partial "RB_PLAN_BACKUP_NAME=hug-backups/2000-01/01-0000.feature"
  git checkout -q main
}

# -----------------------------------------------------------------------------
# rb_render_plan — stderr discipline + quiet
#
# ENG-REVIEW CODEX #6: every subshell MUST source hug-common + hug-git-kit
# before calling rb_build_plan / rb_render_plan. A bare `bash -c "source
# <(rb_build_plan …)"` won't have the functions.
# -----------------------------------------------------------------------------

@test "rb_render_plan: writes nothing to stdout" {
  # Source helpers, build+eval the plan, render with stderr suppressed.
  # stdout must be empty (stdout discipline).
  run bash -c "
    . '$_HUG_HOME/git-config/lib/hug-common'
    . '$_HUG_HOME/git-config/lib/hug-git-kit'
    cd '$TEST_REPO'
    eval \"\$(rb_build_plan main feature false)\"
    rb_render_plan 2>/dev/null
  "
  assert_success
  assert_output ""
}

@test "rb_render_plan: includes backup disposition and auth hint" {
  run bash -c "
    . '$_HUG_HOME/git-config/lib/hug-common'
    . '$_HUG_HOME/git-config/lib/hug-git-kit'
    cd '$TEST_REPO'
    eval \"\$(rb_build_plan main feature false)\"
    rb_render_plan 2>&1
  "
  assert_success
  assert_output --partial "backup"
  assert_output --partial "-y"
}

@test "rb_render_plan: silent when HUG_QUIET=T" {
  # HUG_QUIET must be exported BEFORE the subshell so rb_render_plan sees it.
  HUG_QUIET=T run bash -c "
    . '$_HUG_HOME/git-config/lib/hug-common'
    . '$_HUG_HOME/git-config/lib/hug-git-kit'
    cd '$TEST_REPO'
    eval \"\$(rb_build_plan main feature false)\"
    rb_render_plan 2>&1
  "
  assert_success
  assert_output ""
}
