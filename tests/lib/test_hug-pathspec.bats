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

# Helper: fresh scratch repo with one committed file
new_scratch_repo() {
  local repo; repo=$(mktemp -d)
  git -C "$repo" init -q
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  mkdir -p "$repo/docs"
  echo a > "$repo/docs/a.md"
  echo r > "$repo/root.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m base
  printf '%s' "$repo"
}

call_build_scope_set() {           # <repo-cd-dir> <out-var> <pathspecs...>
  local dir="$1"; local outvar="$2"; shift 2
  (
    cd "$dir"
    unset _HUG_PATHSPEC_LOADED
    . "$REPO_ROOT/git-config/lib/hug-common" >/dev/null 2>&1 || true
    . "$REPO_ROOT/git-config/lib/hug-git-kit"
    build_scope_set "$outvar" "$@"
    eval "printf '%s\n' \${$outvar[@]+\"\${$outvar[@]}\"}"
  )
}

@test "build_scope_set: tracked files in scope" {
  local repo; repo=$(new_scratch_repo)
  run call_build_scope_set "$repo" out
  assert_success
  assert_line "docs/a.md"
  assert_line "root.txt"
  rm -rf "$repo"
}

@test "build_scope_set: union includes STAGED DELETIONS (index entry gone)" {
  local repo; repo=$(new_scratch_repo)
  git -C "$repo" rm -q --cached docs/a.md   # staged deletion
  run call_build_scope_set "$repo" out
  assert_success
  assert_line "docs/a.md"             # present VIA the D-filter half
  rm -rf "$repo"
}

@test "build_scope_set: --no-renames splits a staged rename's D side" {
  local repo; repo=$(new_scratch_repo)
  git -C "$repo" mv docs/a.md docs/b.md      # staged rename
  run call_build_scope_set "$repo" out
  assert_success
  assert_line "docs/a.md"             # old path joins via --no-renames
  assert_line "docs/b.md"
  rm -rf "$repo"
}

@test "build_scope_set: unborn HEAD does not fatal" {
  local repo; repo=$(mktemp -d)
  git -C "$repo" init -q
  echo x > "$repo/x.txt"; git -C "$repo" add x.txt
  run call_build_scope_set "$repo" out
  assert_success
  assert_line "x.txt"
  rm -rf "$repo"
}

@test "build_scope_set: invalid pathspec dies with usage error (exit 2)" {
  local repo; repo=$(new_scratch_repo)
  run call_build_scope_set "$repo" out ':('
  [[ "$status" -eq 2 ]]
  rm -rf "$repo"
}
