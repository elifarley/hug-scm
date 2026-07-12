#!/usr/bin/env bats
# Net-new coverage for hug rb. Closes elifarley/hug-scm#205:
#   #3b — exit code lies on --no-backup success
#   #2  — backup collision / orphan on cancel+retry
#   #1  — non-interactive cancel with no opt-in
#   #3a — ad-hoc --no-backup guard
# Plus the two latent defects (dead conflict branch; --quiet authorizes).

load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
  # Base history: main + a feature branch one commit ahead of main.
  git commit -q --allow-empty -m "main 1"
  git checkout -q -b feature
  echo "x" > x.txt
  git add x.txt
  git commit -q -m "feature 1"
  git checkout -q main
  export HUG_FAKE_CLOCK=946684800
}

teardown() {
  cleanup_test_repo
}

# Helper: count hug-backups/* branches.
count_backups() {
  git for-each-ref --format='%(refname:short)' 'refs/heads/hug-backups/**' 2>/dev/null | wc -l
}

# -----------------------------------------------------------------------------
# #3b — exit code lies
# -----------------------------------------------------------------------------

@test "rb: --no-backup -f on clean linear-ahead exits 0" {
  git checkout -q feature
  run hug rb main -f --no-backup
  assert_success
  assert_output --partial "successful"
  [[ "$(count_backups)" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Conflict guidance resurrected (bonus defect found tracing #3b)
# -----------------------------------------------------------------------------

@test "rb: on conflict, exit non-zero AND conflict guidance printed" {
  # Make main diverge so the rebase conflicts.
  git checkout -q main
  echo "conflict" > x.txt
  git add x.txt
  git commit -q -m "main conflicting"
  git checkout -q feature

  run hug rb main -y
  assert_failure
  assert_output --partial "hug rbc"
  assert_output --partial "hug rba"
  # Abort the paused rebase so teardown can clean up.
  git rebase --abort 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# #1 — non-interactive tier routing
# -----------------------------------------------------------------------------

@test "rb: -y proceeds in non-TTY (warn-tier honors -y)" {
  git checkout -q feature
  # </dev/null forces non-interactive stdin.
  run bash -c "hug rb main -y </dev/null"
  assert_success
  [[ "$(count_backups)" -eq 1 ]]
}

@test "rb: bare non-interactive cancels (exit 1)" {
  git checkout -q feature
  run bash -c "hug rb main </dev/null"
  assert_failure
  # The cancel message (either gum's TTY error or our Cancelled message).
  assert_output --partial "unable to confirm"
  assert_output --partial "Cancelled"
}

@test "rb: --no-backup -y rejects with exit 3 (danger refuses -y)" {
  git checkout -q feature
  run bash -c "hug rb main --no-backup -y </dev/null"
  [[ "$status" -eq 3 ]]
  assert_output --partial "requires --force"
}

@test "rb: --no-backup -f proceeds with no backup" {
  git checkout -q feature
  run bash -c "hug rb main --no-backup -f </dev/null"
  assert_success
  [[ "$(count_backups)" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# #2 — no orphan on cancel; no collision on retry
# -----------------------------------------------------------------------------

@test "rb: cancelled run creates ZERO backup branches" {
  git checkout -q feature
  # Bare non-interactive cancels before authorization — backup must not exist.
  run bash -c "hug rb main </dev/null"
  assert_failure
  [[ "$(count_backups)" -eq 0 ]]
}

@test "rb: two runs under the same HUG_FAKE_CLOCK produce distinct backups" {
  git checkout -q feature
  hug rb main -y >/dev/null 2>&1
  # Rewind feature to its pre-rebase state and re-run in the same clock minute.
  git reset --hard HEAD@{1} >/dev/null 2>&1 || git reset --hard feature >/dev/null 2>&1 || true
  # Re-create the feature commit so there's something to rebase again.
  git checkout -q -B feature main
  echo "y" > y.txt
  git add y.txt
  git commit -q -m "feature 2"

  run hug rb main -y
  assert_success
  # Two backups total, both distinct.
  [[ "$(count_backups)" -ge 2 ]]
}

# -----------------------------------------------------------------------------
# D6 — --quiet never authorizes
# -----------------------------------------------------------------------------

@test "rb: --quiet alone does not authorize in non-TTY" {
  git checkout -q feature
  run bash -c "hug rb main --quiet </dev/null"
  assert_failure
  # With --quiet, only the gum TTY error appears (info messages suppressed).
  assert_output --partial "unable to confirm"
  [[ "$(count_backups)" -eq 0 ]]
}

# -----------------------------------------------------------------------------
# D7 — refuse to start when a rebase is already in progress
# -----------------------------------------------------------------------------

@test "rb: refuses on rebase-merge backend, creates no backup" {
  git checkout -q feature
  mkdir -p .git/rebase-merge
  run hug rb main -y
  assert_failure
  assert_output --partial "A rebase is already in progress"
  [[ "$(count_backups)" -eq 0 ]]
  rmdir .git/rebase-merge 2>/dev/null || true
}

@test "rb: refuses on rebase-apply backend, creates no backup" {
  git checkout -q feature
  mkdir -p .git/rebase-apply
  run hug rb main -y
  assert_failure
  assert_output --partial "A rebase is already in progress"
  [[ "$(count_backups)" -eq 0 ]]
  rmdir .git/rebase-apply 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# --dry-run — faithful preview, zero side effects
# -----------------------------------------------------------------------------

@test "rb: --dry-run changes nothing and shows backup disposition + auth hint" {
  git checkout -q feature
  local head_before
  head_before=$(git rev-parse HEAD)
  local branches_before
  branches_before=$(git for-each-ref --format='%(refname)' refs/heads/ | wc -l)

  run hug rb main --dry-run
  assert_success
  assert_output --partial "would create backup"
  assert_output --partial "-y"

  # No side effects.
  [[ "$(git rev-parse HEAD)" == "$head_before" ]]
  [[ "$(git for-each-ref --format='%(refname)' refs/heads/ | wc -l)" -eq "$branches_before" ]]
}

@test "rb: --dry-run --no-backup shows skip + needs -f" {
  git checkout -q feature
  run hug rb main --dry-run --no-backup
  assert_success
  assert_output --partial "SKIP backup"
  assert_output --partial "-f"
}

# -----------------------------------------------------------------------------
# #3a — ad-hoc guard removed
# -----------------------------------------------------------------------------

@test "rb: --no-backup without -f/-y no longer hard-errors; routes to danger-tier" {
  # The old behavior: `--no-backup requires --force` hard error. New behavior:
  # in an interactive context it would prompt for the typed word. In a
  # non-TTY, danger-tier cancels with the standard "Non-interactive" message
  # (NOT the ad-hoc guard message).
  git checkout -q feature
  run bash -c "hug rb main --no-backup </dev/null"
  assert_failure
  # The ad-hoc message must be gone.
  ! assert_output --partial "--no-backup requires --force"
}
