#!/usr/bin/env bats
# Tests for `hug shv` — visual show (a commit's patch / a range's cumulative diff).
#
# shv is a thin wrapper over the SAME dd_commit_diff engine as `hug dd`, so most
# endpoint correctness is already covered in test_dd.bats. These tests focus on
# what is SPECIFIC to shv: the default (HEAD), the s/u/w redirect, flag rejection,
# the guard chain (TTY + difftool preflight inherited via the engine), shcp-style
# multi-path handling, and — crucially — that `shv X` is byte-identical to `dd X`.
#
# The difftool shim + assert helpers live in tests/test_helper.bash (shared with
# test_dd.bats).

load '../test_helper'

setup() {
  require_hug
}

teardown() {
  teardown_git_shim 2>/dev/null || true
  cleanup_test_repo
}

# --------------------------------------------------------------------------- #
# Defaulting + endpoints
# --------------------------------------------------------------------------- #

@test "hug shv (bare): defaults to HEAD's own patch (HEAD^1 HEAD)" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"; setup_git_shim
  run git-shv
  assert_success
  assert_shim_logged_exact "HEAD^1"
  assert_shim_logged_exact "HEAD"
}

@test "hug shv HEAD: HEAD's introduced patch (HEAD^1 HEAD)" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"; setup_git_shim
  run git-shv HEAD
  assert_success
  assert_shim_logged_exact "HEAD^1"
  assert_shim_logged_exact "HEAD"
}

@test "hug shv N: N=1 → HEAD~1^1 HEAD~1" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"; setup_git_shim
  run git-shv 1
  assert_success
  assert_shim_logged_exact "HEAD~1^1"
  assert_shim_logged_exact "HEAD~1"
}

@test "hug shv -N: -2 → cumulative range HEAD~2..HEAD" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"; setup_git_shim
  run git-shv -2
  assert_success
  assert_shim_logged_exact "HEAD~2..HEAD"
  refute_shim_logged_exact "HEAD~2..HEAD^1"
}

@test "hug shv <range>: A..B passed through verbatim" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"; setup_git_shim
  run git-shv HEAD~2..HEAD
  assert_success
  assert_shim_logged_exact "HEAD~2..HEAD"
}

# --------------------------------------------------------------------------- #
# Equivalence with dd — the DRY contract (one shared engine)
# --------------------------------------------------------------------------- #

@test "hug shv X == hug dd X: identical difftool argv (same engine)" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"; setup_git_shim

  run git-dd HEAD~1
  assert_success
  local dd_log; dd_log=$(cat "$GIT_SHIM_LOG")

  : > "$GIT_SHIM_LOG"   # clear the shim log between runs

  run git-shv HEAD~1
  assert_success
  local shv_log; shv_log=$(cat "$GIT_SHIM_LOG")

  [[ "$dd_log" == "$shv_log" ]] \
    || fail "shv and dd produced different difftool argv:\n--- dd ---\n${dd_log}\n--- shv ---\n${shv_log}"
}

# --------------------------------------------------------------------------- #
# Commit-only surface: reject working-tree subcommands, redirect helpfully
# --------------------------------------------------------------------------- #

@test "hug shv s|u|w: rejected with a redirect to dd / ss|su|sw" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  for sub in s u w; do
    run git-shv "$sub"
    assert_failure
    assert_output --partial "hug dd ${sub}"
  done
}

@test "hug shv --stat: a flag is rejected, not treated as a ref" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  run git-shv --stat
  assert_failure
  assert_output --partial "Unknown flag"
}

# --------------------------------------------------------------------------- #
# No-changes guard + exit-code discipline (inherited from the engine)
# --------------------------------------------------------------------------- #

@test "hug shv <empty-commit>: no introduced changes → message, no launch" {
  TEST_REPO=$(create_test_repo_with_empty_commit); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  run git-shv HEAD
  assert_success
  assert_output --partial "No changes introduced"
  assert_fake_tool_not_invoked
}

@test "hug shv <invalid-ref>: errors (does NOT report 'no changes')" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  run git-shv no-such-ref-xyz
  assert_failure
  refute_output --partial "No changes"
  assert_fake_tool_not_invoked
}

# --------------------------------------------------------------------------- #
# Guard chain: shv inherits TTY + difftool preflight via the engine
# (it bypasses dd_dispatch, so these prove it still gets guarded)
# --------------------------------------------------------------------------- #

@test "hug shv: refuses when stdout is not a TTY" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  HUG_TEST_MODE="" HUG_DISABLE_GUM=true run git-shv HEAD
  assert_failure
  assert_output --partial "TTY"
  assert_fake_tool_not_invoked
}

@test "hug shv: errors when no difftool is configured" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  # No configure_fake_difftool; isolate from any global diff.tool.
  GIT_CONFIG_GLOBAL=/dev/null HUG_TEST_MODE=true HUG_DISABLE_GUM=true run git-shv HEAD
  assert_failure
  [[ "$output" =~ [Dd]ifftool || "$output" =~ [Dd]iff[[:space:]]tool ]] \
    || fail "Expected an error about difftool configuration. Got: $output"
}

# --------------------------------------------------------------------------- #
# Pathspecs: multi-path like shcp (NOT shp's single-path-with-warning)
# --------------------------------------------------------------------------- #

@test "hug shv <commit> -- <multiple paths>: forwards all paths, no warning" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"; setup_git_shim
  # HEAD~1 introduced feature1.txt; scope to two paths — both must be forwarded.
  run git-shv HEAD~1 -- feature1.txt README.md
  assert_success
  refute_output --partial "Warning"
  assert_shim_logged_exact "feature1.txt"
  assert_shim_logged_exact "README.md"
}

# --------------------------------------------------------------------------- #
# Help works without a TTY or a configured difftool
# --------------------------------------------------------------------------- #

@test "hug shv --help: shows usage and SEE ALSO without TTY or difftool" {
  TEST_REPO=$(create_test_repo); cd "$TEST_REPO"
  HUG_TEST_MODE="" GIT_CONFIG_GLOBAL=/dev/null run git-shv --help
  assert_success
  assert_output --partial "hug shv"
  assert_output --partial "SEE ALSO"
  [[ "$output" =~ shp|shcp ]] || fail "SEE ALSO should reference shp/shcp"
}
