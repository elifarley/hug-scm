#!/usr/bin/env bats
# Tests for fast-forward merge (hug mff / git mff)
#
# TDD baseline: these tests capture the existing one-arg behavior of mff,
# which is currently a gitconfig alias (merge --ff-only). They will fail
# until mff is promoted to a full script with --help and arg validation.

load '../test_helper'

setup() {
  enable_gum_for_test
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

# Helper: create a linear branch structure
# main: A -- B -- C
#                \-- feature: D -- E
setup_linear_branches() {
  # main already has initial commit (A)

  echo "main1" > main1.txt
  git add main1.txt
  git commit -m "Main commit B"

  echo "main2" > main2.txt
  git add main2.txt
  git commit -m "Main commit C"

  # Create feature branch ahead of main
  git checkout -q -b feature
  echo "feat1" > feat1.txt
  git add feat1.txt
  git commit -m "Feature commit D"

  echo "feat2" > feat2.txt
  git add feat2.txt
  git commit -m "Feature commit E"

  # Go back to main
  git checkout -q main
}

# -----------------------------------------------------------------------------
# One-arg form (existing behavior)
# -----------------------------------------------------------------------------

@test "hug mff -h: shows help with cross-references" {
  run hug mff -h
  assert_success
  assert_output --partial "hug mff:"
  assert_output --partial "USAGE:"
  assert_output --partial "SEE ALSO"
  assert_output --partial "hug bmv"
}

@test "hug mff <target>: fast-forwards current branch" {
  setup_linear_branches

  run hug mff feature
  assert_success
  assert_output --partial "Fast-forward"
}

@test "hug mff <target>: current branch now at feature's commit" {
  setup_linear_branches

  hug mff feature
  current_commit=$(git rev-parse HEAD)
  feature_commit=$(git rev-parse feature)
  [ "$current_commit" = "$feature_commit" ]
}

@test "hug mff <target>: fails when not a fast-forward" {
  setup_linear_branches

  # Add a commit to main so it diverges
  echo "diverge" > diverge.txt
  git add diverge.txt
  git commit -m "Diverge from feature"

  run hug mff feature
  assert_failure
}

@test "hug mff: requires at least one argument" {
  run hug mff
  assert_failure
  assert_output --partial "USAGE"
}

# Helper: create diverged branches
# main: A -- B -- C -- D
# feature:    B' -- E  (diverges from B)
setup_diverged_branches() {
  # main has initial commit (A)

  echo "base" > base.txt
  git add base.txt
  git commit -m "Shared base B"

  git checkout -q -b feature

  echo "feat-only" > feat.txt
  git add feat.txt
  git commit -m "Feature commit E"

  git checkout -q main

  echo "main-only" > main.txt
  git add main.txt
  git commit -m "Main commit C"

  echo "main-more" > main2.txt
  git add main2.txt
  git commit -m "Main commit D"
}

# -----------------------------------------------------------------------------
# Two-arg form (new behavior)
# -----------------------------------------------------------------------------

@test "hug mff A B: fast-forwards non-checked-out branch" {
  setup_linear_branches

  # main is behind feature, feature is checked out
  git checkout -q feature

  run hug mff main feature
  assert_success
  assert_output --partial "Fast-forwarded"
}

@test "hug mff A B: moves branch pointer without switching" {
  setup_linear_branches
  git checkout -q feature

  hug mff main feature

  # main should now point to feature's commit
  main_sha=$(git rev-parse main)
  feature_sha=$(git rev-parse feature)
  [ "$main_sha" = "$feature_sha" ]

  # current branch should still be feature
  current=$(git branch --show-current)
  [ "$current" = "feature" ]
}

@test "hug mff A B: reports already-at-target" {
  setup_linear_branches

  # feature is ahead, fast-forward main to feature
  hug mff main feature

  # Now try again — should say already at target
  run hug mff main feature
  assert_success
  assert_output --partial "already points at"
}

@test "hug mff A B: fails on diverged branches" {
  setup_diverged_branches

  run hug mff main feature
  assert_failure
  assert_output --partial "diverged"
  assert_output --partial "--force"
}

@test "hug mff A B: divergence error shows commit counts and subjects" {
  setup_diverged_branches

  run hug mff main feature
  assert_failure
  assert_output --partial "'main' has"
  assert_output --partial "commit(s) not in 'feature'"
  assert_output --partial "Main commit C"
  assert_output --partial "Main commit D"
  assert_output --partial "'feature' has"
  assert_output --partial "commit(s) not in 'main'"
}

@test "hug mff A B: divergence error shows hug ll inspect command" {
  setup_diverged_branches

  run hug mff main feature
  assert_failure
  assert_output --partial "Inspect: hug ll main...feature"
}

@test "hug mff A B -f: force-moves diverged non-checked-out branch" {
  setup_diverged_branches
  # Switch away from main so force-move is allowed (DX-1: checked-out branch rejected)
  git checkout -q feature

  run hug mff main feature --force
  assert_success
  assert_output --partial "Moved"
  assert_output --partial "--force"

  main_sha=$(git rev-parse main)
  feature_sha=$(git rev-parse feature)
  [ "$main_sha" = "$feature_sha" ]
}

@test "hug mff A B: target can be a tag" {
  setup_linear_branches
  git tag release-point feature
  git checkout -q feature

  run hug mff main release-point
  assert_success
  assert_output --partial "Fast-forwarded"
}

@test "hug mff A B: target can be a raw SHA" {
  setup_linear_branches
  target_sha=$(git rev-parse feature)
  git checkout -q feature

  run hug mff main "$target_sha"
  assert_success
  assert_output --partial "Fast-forwarded"
}

@test "hug mff A B: branch is current branch — delegates to merge" {
  setup_linear_branches
  # main is checked out, feature is ahead

  run hug mff main feature
  assert_success
}

@test "hug mff A B: error on non-existent branch" {
  setup_linear_branches

  run hug mff nonexistent feature
  assert_failure
  assert_output --partial "not found"
}

@test "hug mff A B: error on non-existent target" {
  setup_linear_branches

  run hug mff main nonexistent-target-xyz
  assert_failure
  assert_output --partial "Cannot resolve"
}

@test "hug mff A B --dry-run: shows preview without moving" {
  setup_linear_branches
  git checkout -q feature

  main_before=$(git rev-parse main)

  run hug mff main feature --dry-run
  assert_success
  assert_output --partial "Would fast-forward"

  # Verify main was NOT moved
  main_after=$(git rev-parse main)
  [ "$main_before" = "$main_after" ]
}

@test "hug mff A B -f: errors when branch is current and diverged" {
  setup_diverged_branches

  run hug mff main feature --force
  assert_failure
  assert_output --partial "Cannot force-move checked-out branch"
  assert_output --partial "Switch away first"
}

# -----------------------------------------------------------------------------
# Worktree safety check (porcelain format fix)
# -----------------------------------------------------------------------------

@test "mff: rejects fast-forward of branch checked out in worktree" {
  # WHY: Before the porcelain format fix, `git worktree list --porcelain` emits
  # `branch refs/heads/X` (space, no colon) but the grep pattern used
  # `branch: refs/heads/X` (with colon). The safety check NEVER matched, so
  # `hug mff` on a branch checked out in another worktree gave a cryptic
  # `git branch -f` error instead of the clear actionable message.
  #
  # Setup: main at C, feature at C-D-E, with feature checked out in a worktree.
  # We switch to a temporary branch so `feature` is NOT the current branch,
  # then try to move `feature` forward — the worktree check should block it.
  setup_linear_branches

  # Create a temporary branch to switch away from main
  git checkout -q -b temp-branch

  # Create a worktree for the feature branch so it's "checked out" there
  local wt_path
  wt_path=$(mktemp -d -p "$BATS_TEST_TMPDIR" -t "hug-mff-wt-XXXXXX")
  git worktree add "$wt_path" feature 2>/dev/null || true

  # Advance main beyond feature so we can try to fast-forward feature to main
  git checkout -q main
  echo "extra" > extra.txt
  git add extra.txt
  git commit -q -m "Extra commit on main"
  git checkout -q temp-branch

  # mff should detect that feature is checked out in worktree and refuse
  run hug mff feature main
  local mff_exit=$status

  # Cleanup worktree before assertions to avoid side effects
  git worktree remove "$wt_path" --force 2>/dev/null || rm -rf "$wt_path"

  # The worktree safety check should have fired (error or early exit)
  [ "$mff_exit" -ne 0 ] || fail "Expected mff to reject moving branch checked out in worktree"
}
