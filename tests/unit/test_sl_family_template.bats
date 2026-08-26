#!/usr/bin/env bats
# =============================================================================
# Drift guard: the sl* listing scripts must stay ON the family template (#303).
# =============================================================================
# WHY: Tasks 6 + 7 collapse five near-identical ~180-line scripts onto a
# shared `sl_family_main` body (hug-status-listing). The shape is the
# contract; hand-copies reintroduce drift. This suite pins the contract.
#
# Task 7 widened the loop to all FIVE family members; the five scripts
# (sl{c,i,k,s,u}) share the same template shape. Any new family member
# must be born on the template or fail this suite.
#
# Members by task:
#   Task 6:  git-sls, git-slu
#   Task 7:  git-slk, git-sli, git-slc
# =============================================================================

load ../test_helper

@test "every migrated sl* script delegates to sl_family_main" {
  local script
  # WIDENED in Task 7 to all five family members.
  for script in "$HUG_HOME/git-config/bin/"git-sl{c,i,k,s,u}; do
    grep -q 'sl_family_main' "$script" || {
      fail "$(basename "$script") missing sl_family_main (hand-copy reintroduced?)"
    }
  done
}

@test "no migrated sl* script carries its own parse own-loop" {
  local script
  # WIDENED in Task 7 to all five family members.
  for script in "$HUG_HOME/git-config/bin/"git-sl{c,i,k,s,u}; do
    if grep -qE '^for arg in "\$@"; do$' "$script"; then
      fail "$(basename "$script") has an own-loop (should live in hug-status-listing)"
    fi
  done
}
