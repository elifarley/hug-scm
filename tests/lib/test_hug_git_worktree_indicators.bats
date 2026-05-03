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
# Pattern matches ESC [ <digits> m sequences (SGR — Select Graphic Rendition).
# Also handles bare ESC (e.g. tput sgr0 may emit ESC without trailing m).
strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g; s/\x1b//g'
}

@test "format_worktree_indicators: all inactive produces four dots" {
  # Act
  run bash -c 'source git-config/lib/hug-terminal; source git-config/lib/hug-git-worktree; format_worktree_indicators false false false false'

  # Assert
  assert_success
  local stripped
  stripped=$(echo "$output" | strip_ansi)
  assert_equal "$stripped" "...."
}

@test "format_worktree_indicators: current only shows asterisk in column 1" {
  # Act
  run bash -c 'source git-config/lib/hug-terminal; source git-config/lib/hug-git-worktree; format_worktree_indicators true false false false'

  # Assert
  assert_success
  local stripped
  stripped=$(echo "$output" | strip_ansi)
  assert_equal "$stripped" "*..."
}

@test "format_worktree_indicators: dirty only shows plus in column 2" {
  # Act
  run bash -c 'source git-config/lib/hug-terminal; source git-config/lib/hug-git-worktree; format_worktree_indicators false true false false'

  # Assert
  assert_success
  local stripped
  stripped=$(echo "$output" | strip_ansi)
  assert_equal "$stripped" ".+.."
}

@test "format_worktree_indicators: locked only shows hash in column 3" {
  # Act
  run bash -c 'source git-config/lib/hug-terminal; source git-config/lib/hug-git-worktree; format_worktree_indicators false false true false'

  # Assert
  assert_success
  local stripped
  stripped=$(echo "$output" | strip_ansi)
  assert_equal "$stripped" "..#."
}

@test "format_worktree_indicators: detached only shows at-sign in column 4" {
  # Act
  run bash -c 'source git-config/lib/hug-terminal; source git-config/lib/hug-git-worktree; format_worktree_indicators false false false true'

  # Assert
  assert_success
  local stripped
  stripped=$(echo "$output" | strip_ansi)
  assert_equal "$stripped" "...@"
}

@test "format_worktree_indicators: all active shows all four indicator chars" {
  # Act
  run bash -c 'source git-config/lib/hug-terminal; source git-config/lib/hug-git-worktree; format_worktree_indicators true true true true'

  # Assert
  assert_success
  local stripped
  stripped=$(echo "$output" | strip_ansi)
  assert_equal "$stripped" "*+#@"
}

@test "format_worktree_indicators: default args produces four dots" {
  # Act — no arguments; all should default to "false"
  run bash -c 'source git-config/lib/hug-terminal; source git-config/lib/hug-git-worktree; format_worktree_indicators'

  # Assert
  assert_success
  local stripped
  stripped=$(echo "$output" | strip_ansi)
  assert_equal "$stripped" "...."
}
