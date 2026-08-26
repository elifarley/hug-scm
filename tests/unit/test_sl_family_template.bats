#!/usr/bin/env bats
# =============================================================================
# Drift guard: the sl* listing scripts must stay ON the family template (#303).
# =============================================================================
# WHY: Tasks 6 + 7 collapse five near-identical ~180-line scripts onto a
# shared `sl_family_main` body (hug-status-listing). The shape is the
# contract; hand-copies reintroduce drift. This suite pins the contract.
#
# SCOPE (controller ruling, plan-text conflict resolved): the brief's
# sketch loops over all FIVE scripts (sl{c,i,k,s,u}), but Task 6 only
# migrates s/u — Task 7 widens the loop. Per the ruling, this test scopes
# its loop to `git-sl{s,u}` NOW and a follow-up widens it. The file header
# documents the widening; do NOT widen the loop until Task 7 lands.
#
# Members by task:
#   Task 6 (this task):  git-sls, git-slu
#   Task 7 (next task):  git-slk, git-sli, git-slc
# =============================================================================

load ../test_helper

@test "every migrated sl* script delegates to sl_family_main" {
  local script
  # SCOPED to Task 6's migrated members — see file header.
  for script in "$HUG_HOME/git-config/bin/"git-sl{s,u}; do
    grep -q 'sl_family_main' "$script" || {
      fail "$(basename "$script") missing sl_family_main (hand-copy reintroduced?)"
    }
  done
}

@test "no migrated sl* script carries its own parse own-loop" {
  local script
  # SCOPED to Task 6's migrated members — see file header.
  for script in "$HUG_HOME/git-config/bin/"git-sl{s,u}; do
    if grep -qE '^for arg in "\$@"; do$' "$script"; then
      fail "$(basename "$script") has an own-loop (should live in hug-status-listing)"
    fi
  done
}
