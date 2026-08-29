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

################################################################################
# validate_backward_target: #234 — explicit targets must be valid BACKWARD moves
################################################################################
# NOTE on test layers: bats `run` DISABLES errexit, so these helper-layer tests would
# pass green even on a capture idiom broken under set -e. The mover-layer e2e tests in
# tests/unit/test_head.bats (real scripts under set -euo pipefail) are the layer that
# catches that — do not delete them in favor of these.

@test "validate_backward_target: garbage target -> 'not a valid commit', non-zero" {
  run validate_backward_target "definitely-not-a-ref" "back"
  assert_failure
  assert_output --partial "'definitely-not-a-ref' is not a valid commit"
}

@test "validate_backward_target: valid target + UNBORN HEAD -> 'cannot resolve HEAD' (not a target error) + restore hint" {
  # When HEAD is unborn (the post-root-undo recovery state), commit_offset(target, HEAD)
  # returns 3 because its SECOND arg fails — NOT because the target is invalid. The exit-3
  # arm must disambiguate: a valid target means HEAD is the problem, and the natural recovery
  # is `hug h restore <target> --<op>`. Pre-fix this mislabeled a valid SHA as "not a valid commit".
  local saved; saved=$(git rev-parse HEAD)
  git update-ref -d HEAD                           # -> unborn HEAD
  run validate_backward_target "$saved" "back"
  assert_failure
  assert_output --partial "cannot resolve HEAD"
  assert_output --partial "hug h restore $saved --back"
  refute_output --partial "'$saved' is not a valid commit"
}

@test "validate_backward_target: forward (descendant) target -> 'ahead of HEAD' + pasteable restore hint" {
  local descendant; descendant=$(git rev-parse HEAD)
  git update-ref HEAD HEAD~1                  # plumbing: HEAD back one, descendant now ahead
  run validate_backward_target "$descendant" "back"
  assert_failure
  assert_output --partial "is ahead of HEAD by 1 commit(s)"
  assert_output --partial "hug h restore $descendant --back"
}

@test "validate_backward_target: diverged target -> silent pass (sideways move preserved)" {
  git checkout -q -b diverger                 # branch at HEAD
  echo "d" > diverger.txt; git add diverger.txt; git commit -q -m "branch diverges"
  git checkout -q -                           # back to the original branch
  echo "l" > local-only.txt; git add local-only.txt; git commit -q -m "HEAD diverges"
  run validate_backward_target "diverger" "undo"
  assert_success
  [ -z "$output" ]                            # contract: diverged is silent — no info/warning either
}

@test "validate_backward_target: ancestor and self -> silent pass" {
  run validate_backward_target "HEAD~1" "back"
  assert_success
  [ -z "$output" ]
  local self; self=$(git rev-parse HEAD)
  run validate_backward_target "$self" "back"
  assert_success
  [ -z "$output" ]
}

################################################################################
# handle_upstream_operation: truthful aligned-vs-behind messaging (#237)
################################################################################
# count(target..HEAD) == 0 means "not AHEAD" — also true when HEAD is BEHIND upstream.
# Diverged cannot reach the branch (diverged ⇒ ahead > 0), so it is a clean 2-state split.

# Shared fixture: repo + bare origin + push + attached upstream (HEAD synced with origin).
setup_synced_upstream() {
  local branch; branch=$(git branch --show-current)
  REMOTE_REPO=$(mktemp -d -p "${BATS_TEST_TMPDIR}" -t "up-synced-origin-XXXXXX")/origin.git
  git init --bare -q "$REMOTE_REPO"
  git remote add origin "$REMOTE_REPO"
  git push -q origin "$branch"
  git branch --set-upstream-to="origin/$branch" >&2
}

# Advances origin by N empty commits (via a clone), leaving HEAD BEHIND upstream.
# Fetches afterward so the LOCAL refs/remotes/origin/<branch> tracking ref updates —
# @{u} resolves against the local ref, not the remote, so without the fetch the upstream
# would still appear "aligned" with a stale SHA.
# Pushes explicitly to refs/heads/<branch> — a fresh clone of a bare repo with mismatched
# default branches (origin's HEAD vs. the test branch) lands on the WRONG branch otherwise,
# advancing a sibling ref and leaving the tracked one untouched.
advance_remote() {
  local n="$1" clone_dir branch
  branch=$(git branch --show-current)
  clone_dir=$(mktemp -d -p "${BATS_TEST_TMPDIR}" -t "up-advance-clone-XXXXXX")/clone
  git clone -q -b "$branch" "$REMOTE_REPO" "$clone_dir"
  local i=1
  while [ "$i" -le "$n" ]; do
    git -C "$clone_dir" -c user.email=test@test -c user.name=test \
        commit -q --allow-empty -m "remote advance $i"
    i=$((i + 1))
  done
  git -C "$clone_dir" push -q origin "HEAD:refs/heads/$branch"
  git fetch -q origin
}

@test "handle_upstream_operation: aligned -> 'Already synced' (unchanged), exit 0 (#237)" {
  create_test_repo_with_history
  setup_synced_upstream
  run handle_upstream_operation "moving back" "warn" "back" "discards local-only commits"
  assert_success
  assert_output --partial "Already synced to upstream"
}

@test "handle_upstream_operation: HEAD BEHIND upstream -> truthful behind message, exit 0 (#237)" {
  create_test_repo_with_history
  setup_synced_upstream
  advance_remote 2
  run handle_upstream_operation "moving back" "warn" "back" "discards local-only commits"
  assert_success
  assert_output --partial "Nothing to move: HEAD is 2 commit(s) behind upstream"
  assert_output --partial "Pull or rebase to catch up"
  refute_output --partial "Already synced"
}

################################################################################
# #235: pin the load-bearing `|| return 1` guards with function-shadowing stubs
################################################################################
# WHY stubs: the guards cannot fail naturally (a resolved upstream always counts), which is
# exactly why they were untested — deleting them keeps every natural-path test green. Bash
# redefinition shadows the library function for `run`'s subshell. If a guard is removed,
# the stub's failure falls through into the preview/message blocks and these tests go red.

@test "#235: count guard pinned — failing count_commits_in_range -> non-zero, no preview" {
  # Pins the guard at hug-git-upstream:49 (NOT the get_upstream_commit guard at :41).
  create_test_repo_with_history
  setup_synced_upstream
  advance_remote 1
  count_commits_in_range() { return 1; }
  run handle_upstream_operation "moving back" "warn" "back" "discards local-only commits"
  assert_failure
  refute_output --partial "Commits to be affected"
}

@test "#235 symmetry: commit_offset guard pinned — failing offset in the ==0 branch -> non-zero" {
  create_test_repo_with_history
  setup_synced_upstream                    # count is 0 -> the ==0 branch executes
  commit_offset() { return 1; }
  run handle_upstream_operation "moving back" "warn" "back" "discards local-only commits"
  assert_failure
  refute_output --partial "Already synced"
  refute_output --partial "behind upstream"
}

################################################################################
# sync_state_of / report_empty_outgoing: truthful empty-outgoing reporting
################################################################################

@test "sync_state_of: synced repo -> in_sync" {
  create_test_repo_with_history
  setup_synced_upstream
  run sync_state_of "$(git rev-parse '@{u}')"
  assert_success
  assert_output "in_sync"
}

@test "sync_state_of: behind-by-2 -> 'behind 2'" {
  create_test_repo_with_history
  setup_synced_upstream
  advance_remote 2
  run sync_state_of "$(git rev-parse '@{u}')"
  assert_success
  assert_output "behind 2"
}

@test "sync_state_of: failing target ref -> unknown (never in_sync)" {
  create_test_repo_with_history
  run sync_state_of "definitely-not-a-ref"
  assert_success
  assert_output "unknown"
}

@test "report_empty_outgoing: synced -> '(already synced to …)'" {
  create_test_repo_with_history
  setup_synced_upstream
  run report_empty_outgoing "📭 No outgoing commits" "origin/main" "$(git rev-parse '@{u}')"
  assert_success
  assert_output --partial "📭 No outgoing commits (already synced to origin/main)"
}

@test "report_empty_outgoing: behind-by-2 -> truthful count + catch-up hint" {
  create_test_repo_with_history
  setup_synced_upstream
  advance_remote 2
  run report_empty_outgoing "📭 No outgoing commits" "origin/main" "$(git rev-parse '@{u}')"
  assert_success
  assert_output --partial "📭 No outgoing commits (branch is behind origin/main by 2 commits — pull or rebase to catch up)"
  refute_output --partial "already synced"
}

@test "report_empty_outgoing: behind-by-1 -> singular 'commit'" {
  create_test_repo_with_history
  setup_synced_upstream
  advance_remote 1
  run report_empty_outgoing "No outgoing changes" "a1b2c3d" "$(git rev-parse '@{u}')"
  assert_success
  assert_output --partial "behind a1b2c3d by 1 commit —"
  refute_output --partial "1 commits"
}

@test "report_empty_outgoing: failure -> self-contained fallback (no noun repeat)" {
  create_test_repo_with_history
  run report_empty_outgoing "No outgoing changes" "definitely-not-a-ref" "definitely-not-a-ref"
  assert_success
  assert_output --partial "No outgoing changes (sync state with definitely-not-a-ref could not be determined)"
  refute_output --partial "No outgoing changes (No outgoing changes"
}

@test "report_empty_outgoing: message routes to stderr (stdout stays empty)" {
  create_test_repo_with_history
  setup_synced_upstream
  run --separate-stderr report_empty_outgoing "No outgoing changes" "origin/main" "$(git rev-parse '@{u}')"
  assert_success
  assert_output ""
  [[ -n "$stderr" ]]
}

@test "report_empty_outgoing: suppressed under HUG_QUIET=T" {
  create_test_repo_with_history
  setup_synced_upstream
  HUG_QUIET=T run --separate-stderr report_empty_outgoing "No outgoing changes" "origin/main" "$(git rev-parse '@{u}')"
  assert_success
  assert_output ""
  [[ -z "$stderr" ]]
}

@test "sync_state_of: missing target ref -> hard guard abort (never a state value)" {
  # The ${1:?} guard is a shell EXIT (rc=1, message on stderr): the function's
  # contract is "returns 0 always, the state is the VALUE" — so a stateless call
  # must abort, never default. A defaulted ref (e.g. a future ${1:-HEAD}) would
  # INVENT sync truth by silently measuring against an arbitrary target.
  run sync_state_of
  assert_failure
  assert_output --partial "sync_state_of: target ref required"
  refute_output --partial "in_sync"
  refute_output --partial "unknown"
}

@test "report_empty_outgoing: missing args -> hard guard abort on each position" {
  # All three ${N:?} guards, one invocation per position (each `run` resets
  # $output/$status, so assert immediately after each). Guards fire before any
  # git call — pure argument-contract enforcement, no repo state involved.
  run report_empty_outgoing
  assert_failure
  assert_output --partial "report_empty_outgoing: noun required"

  run report_empty_outgoing "No outgoing changes"
  assert_failure
  assert_output --partial "report_empty_outgoing: upstream display required"

  run report_empty_outgoing "No outgoing changes" "origin/main"
  assert_failure
  assert_output --partial "report_empty_outgoing: target ref required"
}

@test "report_empty_outgoing: empty 4th arg omits the catch-up hint (custom targets)" {
  create_test_repo_with_history
  setup_synced_upstream
  advance_remote 1
  run report_empty_outgoing "No outgoing changes" "origin/dev" "$(git rev-parse '@{u}')" ""
  assert_success
  assert_output --partial "behind origin/dev by 1 commit)"
  refute_output --partial "pull or rebase"
}

@test "report_unknown_sync: self-contained fallback, composes with any noun" {
  create_test_repo_with_history
  run report_unknown_sync "📭 No outgoing commits" "origin/main"
  assert_success
  assert_output --partial "📭 No outgoing commits (sync state with origin/main could not be determined)"
  refute_output --partial "📭 No outgoing commits (📭"
}
