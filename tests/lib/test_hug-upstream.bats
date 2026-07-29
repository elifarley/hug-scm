#!/usr/bin/env bats
# Tests for hug-git-upstream library: handle_standard_operation aligned-target behavior
# and handle_upstream_operation tier-gated confirmation (Task 5).

load '../test_helper'
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-git-repo'
load '../../git-config/lib/hug-git-state'
load '../../git-config/lib/hug-git-commit'
load '../../git-config/lib/hug-confirm'
load '../../git-config/lib/hug-git-upstream'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

################################################################################
# handle_standard_operation: aligned-target cases
################################################################################

@test "handle_standard_operation: aligned + untracked-only -> 'Already at target' (no tracked-reset message)" {
  git checkout -q -b feature 2>/dev/null || true
  echo "note" > untracked.txt     # untracked only, no tracked changes
  target=$(git rev-parse HEAD)
  run handle_standard_operation "moving" "$target" false
  assert_output --partial "Already at target"
  refute_output --partial "tracked changes will be reset"
}

@test "handle_standard_operation: aligned + tracked-dirty + skip=false -> tracked-reset message" {
  echo "edit" >> feature1.txt     # tracked, unstaged
  target=$(git rev-parse HEAD)
  run handle_standard_operation "moving" "$target" false
  assert_output --partial "local tracked changes will be reset"
}

################################################################################
# handle_upstream_operation: tier-gated confirmation (Task 5)
################################################################################

@test "handle_upstream_operation: missing tier arg is a hard error" {
  create_test_repo_with_history
  git checkout -q -b feature 2>/dev/null || true
  echo x >> feature1.txt && git commit -qam "ahead"
  run handle_upstream_operation "moving"     # only the verb, no tier -> ${2:?} fires
  assert_failure
}

@test "handle_upstream_operation: tier=warn auto-confirms under HUG_YES" {
  create_test_repo_with_history
  local branch; branch=$(git branch --show-current)
  local remote_repo
  remote_repo=$(mktemp -d -p "${BATS_TEST_TMPDIR}" -t "up-warn-XXXXXX")/origin.git
  git init --bare -q "$remote_repo"
  git remote add origin "$remote_repo"
  git push -q origin "$branch"
  git branch --set-upstream-to="origin/$branch" >&2
  echo x >> feature1.txt && git commit -qam "ahead"
  HUG_YES=true run handle_upstream_operation "moving" warn "move" "reason text"
  assert_success
}

@test "handle_upstream_operation: tier=danger refuses HUG_YES (exit 3)" {
  create_test_repo_with_history
  local branch; branch=$(git branch --show-current)
  local remote_repo
  remote_repo=$(mktemp -d -p "${BATS_TEST_TMPDIR}" -t "up-danger-XXXXXX")/origin.git
  git init --bare -q "$remote_repo"
  git remote add origin "$remote_repo"
  git push -q origin "$branch"
  git branch --set-upstream-to="origin/$branch" >&2
  echo x >> feature1.txt && git commit -qam "ahead"
  HUG_YES=true run handle_upstream_operation "moving" danger "move" "irreversible"
  assert_failure
  [ "$status" -eq 3 ]
}

################################################################################
# emit_head_recovery_hint: quiet-aware recovery hint helper (Task 6)
################################################################################

@test "emit_head_recovery_hint: prints the restore command to stderr" {
  run emit_head_recovery_hint "abc1234def5678" "back"
  assert_success
  [[ "$output" == *"hug h restore abc1234def5678 --back -y"* ]]
}

@test "emit_head_recovery_hint: suppressed under HUG_QUIET=T" {
  HUG_QUIET=T run emit_head_recovery_hint "abc1234def5678" "back"
  assert_success
  [ -z "$output" ]
}
