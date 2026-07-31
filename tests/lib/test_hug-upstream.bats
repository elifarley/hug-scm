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

################################################################################
# handle_standard_operation: Defect-1 regression (forward target must NOT no-op)
################################################################################

@test "handle_standard_operation: forward (descendant) target does NOT no-op (Defect 1)" {
  # HEAD at an ancestor; target is a descendant. Pre-fix this printed 'Already at target'.
  # The old guard was `count target..HEAD == 0`, which is ALSO true when HEAD is BEHIND the
  # target (a forward target), so the mover silently no-op'ed. is_same_commit (exact SHA equality)
  # is the correct guard: a forward target is NOT aligned and must proceed.
  local descendant; descendant=$(git rev-parse HEAD)
  git update-ref HEAD HEAD~1                  # move HEAD back one (plumbing; avoids git reset/checkout)
  run handle_standard_operation "move back" "$descendant"
  assert_success                              # returns past the guard (does not exit 0 early)
  refute_output --partial "Already at target" # the guard was NOT taken
}

################################################################################
# Defect-2 strict propagation: a bad ref / missing upstream must return non-zero
################################################################################
# WHY these exist: pre-#229, count_commits_in_range swallowed a failed rev-list into
# `echo 0`, so an invalid ref or a missing upstream surfaced as a *plausible-looking*
# zero count ("0 commits" / "Already synced") and the helper returned SUCCESS. The fix
# removed the swallow; every strict call site now propagates non-zero. These two tests
# pin that guarantee at the LIBRARY level (the command-level pins live in test_head.bats).
#
# They pin the USER-VISIBLE guarantee (non-zero return, never a silent no-op), NOT the exact strict
# site. That mechanism is isolated one layer down by the primitive canary at
# tests/lib/test_hug-git-commit.bats (count_commits_in_range strictness) — mutation-testing shows
# re-adding the swallow merely RELOCATES the failure downstream (the helper-tail `git diff --stat`
# still fails on the bad range), so these stay green by design. Read them as "the helper fails
# loudly," not "this specific guard propagates."

@test "handle_standard_operation: invalid target -> non-zero (strict, not a silent no-op)" {
  # A non-resolving target is NOT aligned: is_same_commit is a false-NEGATIVE-only predicate
  # (rev-parse --verify fails -> non-zero -> the SHA-equality test is false), so the helper
  # proceeds past the aligned-guard and fails loudly on the bad ref. The FIRST strict site it hits is
  # count_commits_in_range (`git rev-list --count NO_SUCH_REF..HEAD`), but that is NOT the only possible
  # failure point — re-adding the swallow there just relocates the failure to the helper-tail
  # `git diff --stat NO_SUCH_REF..HEAD` (see the section header). The pinned guarantee is the non-zero
  # return + no misleading "Already at target"; pre-fix the swallow rendered a '0 commits' no-op (return 0).
  run handle_standard_operation "move back" "NO_SUCH_REF_XYZ"
  assert_failure
  refute_output --partial "Already at target" # the misleading pre-fix no-op message must NOT appear
}

@test "handle_upstream_operation: no upstream -> non-zero (strict guarantee)" {
  # create_test_repo_with_history configures NO upstream, so get_upstream_commit exits non-zero
  # inside the $(…) substitution; `target=$(get_upstream_commit) || return 1` propagates it
  # (hug-git-upstream:41). Pre-fix the missing upstream could be masked downstream; now the helper
  # returns non-zero instead of echoing an empty target that word-splits into a bogus default.
  run handle_upstream_operation "moving" warn "move" "reason"
  assert_failure
}
