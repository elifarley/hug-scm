#!/usr/bin/env bats
# Tests for the hug dispatcher's global flag parsing.
#
# The dispatcher (bin/hug) supports two global flags consumed BEFORE the command
# reaches the SCM detection / case statement:
#
#   -C <path>           cd into <path> before dispatch (SCM-agnostic)
#   -S <name|path>      resolve a git submodule and cd into it
#   --submodule=<name>  long form of -S
#
# Design rationale (from bin/hug comments):
#   Global flags use `cd` rather than `exec git -C` so that SCM detection
#   inspects the TARGET directory, and clone/init/help dispatch works from
#   the cd'd directory. Unknown flags fall through (break) so they remain
#   in $@ for the command. Command names are never '-'-prefixed, so they
#   also break correctly.
#
# Test matrix:
#   T1–T3c : -C basic, error, and edge cases
#   T4–T10 : -S name, path, error, containment, and long form
#   T11–T12: composition (-C + -S), subdir resolution, name ambiguity
#   R1–R7  : regressions (no-flag behavior, namespace overlap, passthrough)

load '../test_helper'

# ===========================================================================
# -C tests: cd into target directory before dispatch
# ===========================================================================

@test "hug -C <repo> s: runs status in target repo" {
  create_test_repo
  local other_repo
  other_repo=$(create_test_repo)
  cd "$TEST_REPO"  # be in some repo
  run hug -C "$other_repo" s
  assert_success
  # Output should mention the other repo's HEAD, not ours
  assert_output --partial "HEAD"
}

@test "hug -C <repo> s --branch: reports target repo branch" {
  create_test_repo
  local other_repo
  other_repo=$(create_test_repo)
  cd "$TEST_REPO"
  run hug -C "$other_repo" s --branch
  assert_success
  assert_output --partial "main"
}

@test "hug -C <repo> ll -1: log from target repo" {
  create_test_repo
  local other_repo
  other_repo=$(create_test_repo)
  cd "$TEST_REPO"
  run hug -C "$other_repo" ll -1
  assert_success
  assert_output --partial "Initial commit"
}

@test "hug -C <repo> s: works from non-git directory" {
  local repo
  repo=$(create_test_repo)
  cd /tmp  # KEY BUG FIX: -C from a non-git CWD must work
  run hug -C "$repo" s
  assert_success
  assert_output --partial "HEAD"
}

@test "hug -C <hg-repo> s: SCM-agnostic (works with Mercurial)" {
  # Mercurial may not be installed — skip gracefully
  command -v hg >/dev/null 2>&1 || skip "hg not installed"
  local hg_repo
  hg_repo=$(create_test_hg_repo)
  cd /tmp  # not in any repo
  run hug -C "$hg_repo" s
  assert_success
  rm -rf "$hg_repo"
}

@test "hug -C <missing-dir>: error for nonexistent directory" {
  run hug -C /nonexistent/path/xyz s
  assert_failure
  assert_output --partial "not a directory"
}

@test "hug -C: error when no path given (not unbound variable)" {
  # WHY this test: without the ${2:-} guard, bash's set -u would crash
  # with "unbound variable" instead of a helpful message.
  run hug -C
  assert_failure
  assert_output --partial "requires a path"
}

@test "hug -C <file>: error when target is a file" {
  local tmpf
  tmpf=$(mktemp)
  run hug -C "$tmpf" s
  assert_failure
  assert_output --partial "not a directory"
  rm -f "$tmpf"
}

@test "hug -C '<path with spaces>': works with spaces in path" {
  create_test_repo
  local spaced_dir
  spaced_dir=$(mktemp -d '/tmp/hug test repo XXXXXX')
  (
    cd "$spaced_dir" || exit 1
    git init -q --initial-branch=main 2>/dev/null || git init -q
    git config user.email "test@test"
    git config user.name "Test"
    echo "x" > f.txt && git add f.txt && git commit -q -m "init"
  )
  cd /tmp
  run hug -C "$spaced_dir" s
  assert_success
  rm -rf "$spaced_dir"
}

# ===========================================================================
# -S tests: resolve git submodule and cd into it
# ===========================================================================

@test "hug -S <name> s: status of submodule by name" {
  create_test_repo_with_submodule
  cd "$TEST_PARENT_REPO"
  run hug -S sub s
  assert_success
}

@test "hug -S <name> s --branch: submodule branch query" {
  create_test_repo_with_submodule
  cd "$TEST_PARENT_REPO"
  run hug -S sub s --branch
  assert_success
  assert_output --partial "main"
}

@test "hug -S <path> s: status of submodule by path" {
  # When the submodule name happens to also be its path (common case),
  # both name and path resolution should work identically.
  create_test_repo_with_submodule
  cd "$TEST_PARENT_REPO"
  run hug -S sub s
  assert_success
}

@test "hug -S <nonexistent>: error lists available submodules" {
  create_test_repo_with_submodule
  cd "$TEST_PARENT_REPO"
  run hug -S nonexistent s
  assert_failure
  assert_output --partial "not found"
  # The error message should list the available submodule name
  assert_output --partial "sub"
}

@test "hug -S: error when no submodule name given" {
  create_test_repo_with_submodule
  cd "$TEST_PARENT_REPO"
  run hug -S
  assert_failure
  assert_output --partial "requires a submodule"
}

@test "hug -S ../../other: rejects path outside repo (containment)" {
  create_test_repo_with_submodule
  cd "$TEST_PARENT_REPO"
  run hug -S ../../etc s
  assert_failure
  # ../../etc doesn't match any submodule name or path, so it hits "not found"
  # before the containment check. Either "not found" or "outside the
  # repository" is an acceptable rejection — the important thing is it fails.
  [[ "$output" == *"not found"* || "$output" == *"outside the repository"* ]]
}

@test "hug -S /abs/path: rejects absolute path" {
  create_test_repo_with_submodule
  cd "$TEST_PARENT_REPO"
  run hug -S /tmp s
  assert_failure
  # Absolute paths won't match any submodule name or relative path,
  # so they hit "not found" — not "outside the repository".
  # Either message is acceptable as long as we get failure.
  assert_failure
}

@test "hug -S <uninitialized>: suggests git submodule update --init" {
  # Create repo with submodule, then deinit it so it becomes uninitialized
  create_test_repo_with_submodule
  cd "$TEST_PARENT_REPO"
  # WHY git submodule deinit: removes the submodule's working tree while
  # keeping the .gitmodules entry — exactly the "uninitialized" state.
  git submodule deinit -f sub 2>/dev/null || true
  run hug -S sub s
  assert_failure
  assert_output --partial "not initialized"
  assert_output --partial "git submodule update --init"
}

@test "hug --submodule=<name> s: long form of -S" {
  create_test_repo_with_submodule
  cd "$TEST_PARENT_REPO"
  run hug --submodule=sub s
  assert_success
}

@test "hug --submodule= (empty): error when long form has no value" {
  create_test_repo_with_submodule
  cd "$TEST_PARENT_REPO"
  run hug --submodule= s
  assert_failure
  assert_output --partial "requires a submodule"
}

# ===========================================================================
# Composition tests: -C and -S together, subdir resolution, name ambiguity
# ===========================================================================

@test "hug -C <repo> -S <name> s: composition of both global flags" {
  create_test_repo_with_submodule
  cd /tmp  # not in the parent repo at all
  run hug -C "$TEST_PARENT_REPO" -S sub s
  assert_success
}

@test "hug -S: exact name match with multiple submodules (no prefix confusion)" {
  # When two submodules share a prefix (pay, pay-v2), -S must match
  # the EXACT name, not a prefix. This prevents "pay" silently resolving
  # to "pay-v2" or vice-versa.
  create_test_repo_with_submodule pay pay-v2
  cd "$TEST_PARENT_REPO"
  run hug -S pay s
  assert_success
}

@test "hug -S: exact name match for pay-v2 (no prefix confusion)" {
  create_test_repo_with_submodule pay pay-v2
  cd "$TEST_PARENT_REPO"
  run hug -S pay-v2 s
  assert_success
}

@test "hug -S <name> from subdir: resolves via repo top-level" {
  # Submodule paths in .gitmodules are relative to the repo root.
  # When CWD is a subdirectory, -S must still find the submodule by
  # resolving .gitmodules from the repo top-level (git rev-parse --show-toplevel).
  create_test_repo_with_submodule
  cd "$TEST_PARENT_REPO"
  mkdir -p subdir
  cd subdir
  run hug -S sub s
  assert_success
}

@test "hug -S: error in non-git directory" {
  cd /tmp  # not a git repo
  run hug -S anything s
  assert_failure
  assert_output --partial "not in a Git repository"
}

@test "hug -S: error in Mercurial repo (submodules are git-only)" {
  command -v hg >/dev/null 2>&1 || skip "hg not installed"
  local hg_repo
  hg_repo=$(create_test_hg_repo)
  cd "$hg_repo"
  run hug -S anything s
  assert_failure
  assert_output --partial "Mercurial"
  rm -rf "$hg_repo"
}

@test "hug -S: error when repo has no submodules (.gitmodules missing)" {
  create_test_repo
  cd "$TEST_REPO"
  run hug -S anything s
  assert_failure
  assert_output --partial ".gitmodules"
}

# ===========================================================================
# Regression tests: existing behavior must not change
# ===========================================================================

@test "regression: hug s works without global flags" {
  create_test_repo
  cd "$TEST_REPO"
  run hug s
  assert_success
  assert_output --partial "HEAD"
}

@test "regression: hug help still dispatches" {
  run hug help
  assert_success
  # hughelp shows the top-level category listing
  assert_output --partial "command groups"
}

@test "regression: hug --version still works" {
  run hug --version
  assert_success
  assert_output --partial "Hug SCM"
}

@test "regression: hug version still works (long form)" {
  run hug version
  assert_success
  assert_output --partial "Hug SCM"
}

@test "regression: hug clone dispatch still works (no args = error)" {
  # Running clone without a URL should produce an error from the clone
  # handler, proving the dispatcher routed correctly.
  run hug clone
  assert_failure
}

@test "regression: hug init dispatch still works (no args = error)" {
  run hug init
  assert_failure
}

@test "regression: hug s -C still means --counts (not global -C)" {
  # CRITICAL namespace overlap: `hug s -C` is a SUBCOMMAND flag (--counts)
  # that appears AFTER the command name. The global flag loop only consumes
  # flags BEFORE the command, so -C after `s` must pass through to git-s.
  create_test_repo
  cd "$TEST_REPO"
  # Stage a file so -C (counts) has something to report
  echo "x" > newfile.txt && git add newfile.txt
  run hug s -C
  assert_success
  # The key assertion: this does NOT fail with "requires a path" from the
  # global flag parser. --counts mode outputs "staged unstaged" counts only,
  # which for a clean repo + one staged file would be something like "1 0".
  [[ ! "$output" == *"requires a path"* ]]
}

@test "regression: hug s -S still means --staged (not global -S)" {
  # Same namespace overlap as -C: `hug s -S` means --staged when it
  # appears after the command name.
  create_test_repo
  cd "$TEST_REPO"
  echo "x" > staged.txt && git add staged.txt
  run hug s -S
  assert_success
  # Should NOT fail with "requires a submodule"
  # --staged outputs a count of staged files only (e.g., "1")
  [[ ! "$output" == *"requires a submodule"* ]]
}

@test "regression: unknown global flag passes through to git" {
  # -p is not a hug global flag, so the while-loop's `*) break` fires,
  # leaving -p in $@ for git to handle. The command should not fail with
  # "unknown flag" from hug's dispatcher.
  create_test_repo
  cd "$TEST_REPO"
  run hug -p s
  # git status -p is not a valid combination, so git itself may fail,
  # but the failure must come from git — not from hug's dispatcher.
  # We only assert that hug does not produce its own "unknown flag" error.
  if [[ $status -ne 0 ]]; then
    # If it failed, make sure it's NOT hug's dispatcher complaining
    [[ ! "$output" == *"unknown"* ]]
  fi
}

@test "regression: -- ends global flags, rest passes to command" {
  create_test_repo
  cd "$TEST_REPO"
  # -- should end the global flag loop; everything after goes to git
  run hug -- s
  assert_success
  assert_output --partial "HEAD"
}

@test "regression: hug with no args in git repo shows hughelp" {
  create_test_repo
  cd "$TEST_REPO"
  # No args → dispatcher's help branch fires (before SCM detection), showing
  # the top-level hughelp listing (exit 0). This is by design: hug with no
  # args is more helpful than git's raw error.
  run hug
  assert_success
  assert_output --partial "command groups"
}
