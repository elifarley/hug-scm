#!/usr/bin/env bats
# Tests for hug-pathspec: pathspec scope-set construction + relpath conversion
load '../test_helper'
load '../../git-config/lib/hug-common'

setup() {
  require_hug
  export HUG_HOME="$BATS_TEST_DIRNAME/../.."
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "hug-pathspec: sources via hug-git-kit after registration" {
  . "$REPO_ROOT/git-config/lib/hug-git-kit"
  declare -F root_to_cwd_relpath >/dev/null
}

# Helper: run root_to_cwd_relpath INSIDE a subdir of a scratch repo so
# `git rev-parse --show-prefix` reflects the sub/ context.
relpath_from_sub() {
  local sub="$1"; shift
  local repo; repo=$(mktemp -d)
  git -C "$repo" init -q
  mkdir -p "$repo/$sub"
  (cd "$repo/$sub" && {
    . "$REPO_ROOT/git-config/lib/hug-common" >/dev/null 2>&1 || true
    . "$REPO_ROOT/git-config/lib/hug-pathspec"
    root_to_cwd_relpath "$@"
  })
  rm -rf "$repo"
}

@test "relpath: strips cwd prefix when target lives under cwd" {
  run relpath_from_sub docs docs/a.md
  assert_success
  assert_output "a.md"
}

@test "relpath: climbs when target lives outside cwd (:(top) spelling)" {
  run relpath_from_sub docs ../root.txt
  assert_output "../root.txt"
  # NOTE: input is ROOT-relative per contract; from docs/, root.txt climbs
  run relpath_from_sub docs root.txt
  assert_output "../root.txt"
}

@test "relpath: identity when cwd is repo root (empty show-prefix)" {
  run relpath_from_sub . top.txt
  assert_output "top.txt"
}

@test "relpath: multi-level climb from nested subdir" {
  run relpath_from_sub a/b/c top.txt
  assert_output "../../../top.txt"
}

@test "relpath: strips multi-component shared prefix" {
  run relpath_from_sub a/b a/b/deep/f.txt
  assert_output "deep/f.txt"
}
