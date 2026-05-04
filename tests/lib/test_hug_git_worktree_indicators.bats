#!/usr/bin/env bats
# Tests for format_worktree_indicators() in hug-git-worktree library
#
# WHY this test file exists:
#   format_worktree_indicators() is used by most Bash output paths (wtl, wt, wtsh,
#   wtll, show_worktree_summary) but had no direct unit tests. The Python counterpart
#   has 8 tests. This file provides parity for the Bash implementation.
#
# TESTING NOTE — ANSI codes:
#   hug-terminal defines color variables (GREEN, YELLOW, RED, CYAN, GREY, NC) that
#   are empty when stdout is not a TTY (which is the case in BATS). Therefore, in
#   BATS tests the function outputs plain characters without ANSI escape sequences.
#   However, we defensively strip ANSI codes anyway so the tests remain correct if
#   someone runs them in a TTY-equipped environment.

load '../test_helper'

# Strip ANSI escape sequences for reliable assertions.
strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g; s/\x1b//g'
}

@test "format_worktree_indicators: all inactive produces two dots" {
  run bash -c 'source git-config/lib/hug-terminal; source git-config/lib/hug-git-worktree; format_worktree_indicators false false'
  assert_success
  local stripped
  stripped=$(echo "$output" | strip_ansi)
  assert_equal "$stripped" ".."
}

@test "format_worktree_indicators: dirty only shows plus in column 1" {
  run bash -c 'source git-config/lib/hug-terminal; source git-config/lib/hug-git-worktree; format_worktree_indicators true false'
  assert_success
  local stripped
  stripped=$(echo "$output" | strip_ansi)
  assert_equal "$stripped" "+."
}

@test "format_worktree_indicators: locked only shows hash in column 2" {
  run bash -c 'source git-config/lib/hug-terminal; source git-config/lib/hug-git-worktree; format_worktree_indicators false true'
  assert_success
  local stripped
  stripped=$(echo "$output" | strip_ansi)
  assert_equal "$stripped" ".#"
}

@test "format_worktree_indicators: both active shows +#" {
  run bash -c 'source git-config/lib/hug-terminal; source git-config/lib/hug-git-worktree; format_worktree_indicators true true'
  assert_success
  local stripped
  stripped=$(echo "$output" | strip_ansi)
  assert_equal "$stripped" "+#"
}

@test "format_worktree_indicators: default args produces two dots" {
  run bash -c 'source git-config/lib/hug-terminal; source git-config/lib/hug-git-worktree; format_worktree_indicators'
  assert_success
  local stripped
  stripped=$(echo "$output" | strip_ansi)
  assert_equal "$stripped" ".."
}

@test "format_worktree_branch_display: current on branch shows green star prefix" {
  run bash -c 'source git-config/lib/hug-terminal; source git-config/lib/hug-git-worktree; format_worktree_branch_display true false main'
  assert_success
  local stripped
  stripped=$(echo "$output" | strip_ansi)
  assert_equal "$stripped" "*main"
}

@test "format_worktree_branch_display: not current on branch shows plain name" {
  run bash -c 'source git-config/lib/hug-terminal; source git-config/lib/hug-git-worktree; format_worktree_branch_display false false feature-1'
  assert_success
  local stripped
  stripped=$(echo "$output" | strip_ansi)
  assert_equal "$stripped" "feature-1"
}

@test "format_worktree_branch_display: not current detached shows @ detached" {
  run bash -c 'source git-config/lib/hug-terminal; source git-config/lib/hug-git-worktree; format_worktree_branch_display false true'
  assert_success
  local stripped
  stripped=$(echo "$output" | strip_ansi)
  assert_equal "$stripped" "@ detached"
}

@test "format_worktree_branch_display: current detached shows *@ detached" {
  run bash -c 'source git-config/lib/hug-terminal; source git-config/lib/hug-git-worktree; format_worktree_branch_display true true'
  assert_success
  local stripped
  stripped=$(echo "$output" | strip_ansi)
  assert_equal "$stripped" "*@ detached"
}

@test "print_worktree_legend: outputs nothing to stdout (legend on stderr)" {
  # BATS runs non-TTY, so the legend is suppressed entirely (non-TTY guard).
  # Verify that stdout is empty regardless.
  run bash -c 'source git-config/lib/hug-terminal; source git-config/lib/hug-git-worktree; print_worktree_legend 2>/dev/null'
  assert_success
  # stdout should be empty — legend goes to stderr (or suppressed entirely in non-TTY)
  assert_output ""
}

@test "print_worktree_legend: includes Legend prefix on stderr under TTY" {
  # Force TTY-like conditions using script(1) to provide a pty
  if ! command -v script >/dev/null 2>&1; then
    skip "script command not available"
  fi
  run bash -c 'script -qc "source git-config/lib/hug-terminal; source git-config/lib/hug-git-worktree; print_worktree_legend" /dev/null 2>&1'
  assert_success
  assert_output --partial "Legend:"
}
