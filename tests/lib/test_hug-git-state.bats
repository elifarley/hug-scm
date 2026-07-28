#!/usr/bin/env bats
# Tests for hug-git-state library: working tree state checking functions

load '../test_helper'
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-git-repo'
load '../../git-config/lib/hug-git-state'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

################################################################################
# has_pending_changes TESTS
################################################################################

@test "has_pending_changes: returns false for clean repo" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  
  run has_pending_changes
  assert_failure
}

@test "has_pending_changes: returns true for unstaged changes" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  echo "modified" >> file.txt
  
  run has_pending_changes
  assert_success
}

@test "has_pending_changes: returns true for staged changes" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  echo "modified" >> file.txt
  git add file.txt
  
  run has_pending_changes
  assert_success
}

@test "has_pending_changes: returns true for untracked files" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  echo "untracked" > untracked.txt
  
  run has_pending_changes
  assert_success
}

################################################################################
# has_staged_changes TESTS
################################################################################

@test "has_staged_changes: returns false for no staged changes" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  
  run has_staged_changes
  assert_failure
}

@test "has_staged_changes: returns true for staged changes" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  echo "modified" >> file.txt
  git add file.txt
  
  run has_staged_changes
  assert_success
}

################################################################################
# has_unstaged_changes TESTS
################################################################################

@test "has_unstaged_changes: returns false for no unstaged changes" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  
  run has_unstaged_changes
  assert_failure
}

@test "has_unstaged_changes: returns true for unstaged changes" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  echo "modified" >> file.txt
  
  run has_unstaged_changes
  assert_success
}

################################################################################
# is_binary_staged TESTS
################################################################################

@test "is_binary_staged: returns false for text file" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  echo "modified" >> file.txt
  git add file.txt
  
  run is_binary_staged file.txt
  assert_failure
}

@test "is_binary_staged: returns false for no staged changes" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"

  run is_binary_staged file.txt
  assert_failure
}

################################################################################
# check_working_tree_clean — dirty-tree remediation text (elifarley/hug-scm#208)
################################################################################

@test "check_working_tree_clean: dirty tree error offers wipe (not discard)" {
  # create_test_repo already creates an initial commit (README.md) so HEAD is stable.
  cd "$(create_test_repo)" || exit 1
  # Stage one new file (staged changes present)
  echo "staged content" > staged_file.txt
  git add staged_file.txt
  # Modify the existing README.md (unstaged changes present) — README.md is
  # guaranteed to exist because create_test_repo creates it.
  echo "modification" >> README.md

  run check_working_tree_clean
  assert_failure
  assert_output --partial "hug w wip"
  assert_output --partial "hug w wipe-all"
  assert_output --partial "hug w wipe <file>"
  assert_output --partial "hug sl"
  refute_output --partial "git w-"
  refute_output --partial "hug w discard-all"
}

@test "check_file_unstaged: error says hug w discard (not git w-discard)" {
  # create_test_repo creates README.md in the initial commit. Modify it to
  # create unstaged changes on a known-existing tracked file.
  cd "$(create_test_repo)" || exit 1
  echo "modification" >> README.md
  run check_file_unstaged "README.md"
  assert_failure
  assert_output --partial "hug w discard"
  refute_output --partial "git w-discard"
}

@test "has_pending_changes: returns true under pipefail with many untracked files (SIGPIPE regression)" {
  # Create 1000+ untracked files to ensure git status output exceeds pipe buffer
  # (64KB on Linux). Under the old pipe-based implementation, this would trigger
  # SIGPIPE -> grep exits after first match -> git SIGPIPE -> false negative.
  local i
  for i in $(seq 1 1000); do
    echo "content_$i" > "untracked_file_$i"
  done

  # Must detect changes even under pipefail (which hug scripts set)
  run bash -c 'set -o pipefail; source "$HUG_HOME/git-config/lib/hug-common"; source "$HUG_HOME/git-config/lib/hug-git-repo"; source "$HUG_HOME/git-config/lib/hug-git-state"; has_pending_changes'
  assert_success
}

################################################################################
# get_dirty_files TESTS
################################################################################

@test "get_dirty_files: clean repo returns 0 and prints nothing" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"

  run get_dirty_files
  assert_success                 # MUST be 0 even when empty
  assert_output ""
}

@test "get_dirty_files: clean repo yields ZERO mapfile entries (joiner-bug regression)" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"

  local -a dirty=()
  mapfile -t dirty < <(get_dirty_files)
  [ "${#dirty[@]}" -eq 0 ]       # not 1
}

@test "get_dirty_files: lists unstaged-dirty file" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  echo "modified" >> file.txt

  run get_dirty_files
  assert_success
  assert_output "file.txt"
}

@test "get_dirty_files: lists staged-dirty file" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  echo "modified" >> file.txt
  git add file.txt

  run get_dirty_files
  assert_success
  assert_output "file.txt"
}

@test "get_dirty_files: dedupes a file that is both staged and unstaged dirty" {
  echo "test" > file.txt
  git add file.txt
  git commit -q -m "test commit"
  echo "staged" >> file.txt
  git add file.txt
  echo "unstaged" >> file.txt    # now dirty in BOTH index and worktree

  run get_dirty_files
  assert_success
  assert_output "file.txt"       # one line, not two
}

@test "get_dirty_files: scoped form reports only the named dirty file" {
  echo "a" > a.txt; echo "b" > b.txt
  git add a.txt b.txt
  git commit -q -m "init"
  echo "x" >> a.txt              # only a.txt dirty

  run get_dirty_files a.txt b.txt
  assert_success
  assert_output "a.txt"
}

@test "get_dirty_files: no-arg whole-tree matches porcelain dirty set" {
  echo "a" > a.txt; echo "b" > b.txt
  git add a.txt b.txt
  git commit -q -m "init"
  echo "x" >> a.txt              # unstaged
  echo "y" >> b.txt; git add b.txt   # staged

  run get_dirty_files
  assert_success
  assert_output "a.txt
b.txt"
}

################################################################################
# get_untracked_files TESTS
################################################################################

@test "get_untracked_files: clean repo (no untracked) returns 0 and prints nothing" {
  echo "test" > file.txt; git add file.txt; git commit -q -m "c"
  run get_untracked_files
  assert_success
  assert_output ""
}

@test "get_untracked_files: lists an untracked file" {
  echo "test" > file.txt; git add file.txt; git commit -q -m "c"
  echo "u" > untracked.txt
  run get_untracked_files
  assert_success
  assert_output "untracked.txt"
}

@test "get_untracked_files: scoped form lists only the named untracked file" {
  echo "a" > a.txt; echo "b" > b.txt; git add a.txt b.txt; git commit -q -m "c"
  echo "u" > u1.txt; echo "v" > u2.txt
  run get_untracked_files u1.txt a.txt   # a.txt is tracked, u1.txt untracked
  assert_success
  assert_output "u1.txt"
}

@test "check_files_clean: still refuses dirty files with byte-locked wipe text (unchanged)" {
  echo "a" > a.txt
  git add a.txt
  git commit -q -m "init"
  echo "x" >> a.txt

  run check_files_clean a.txt
  assert_failure
  assert_output --partial "Cannot proceed because some affected files have uncommitted changes."
  assert_output --partial "a.txt"
  assert_output --partial "hug w wipe-all"   # #208 byte-lock: wipe, not discard
}

@test "check_files_clean: passes when the named files are clean" {
  echo "a" > a.txt
  git add a.txt
  git commit -q -m "init"

  run check_files_clean a.txt
  assert_success
}

@test "check_file_unstaged: review-first, no-TTY-runnable remediation text" {
  echo "a" > a.txt
  git add a.txt
  git commit -q -m "init"
  echo "x" >> a.txt              # unstaged only

  run check_file_unstaged a.txt
  assert_failure
  assert_output --partial "has unstaged changes"
  assert_output --partial "Review with 'hug sw a.txt'"
  assert_output --partial "hug w discard -f a.txt"
}

@test "check_file_unstaged: passes when the file has no unstaged changes" {
  echo "a" > a.txt
  git add a.txt
  git commit -q -m "init"

  run check_file_unstaged a.txt
  assert_success
}

# Guards the unstaged-only invariant: a file with staged changes but NO working-tree
# delta must pass. If someone swapped the `git diff --quiet` (unstaged-only) probe for
# a broader status check, this test would catch the semantic drift — and that drift is
# exactly what would justify changing the remediation from 'discard' to 'wipe'.
@test "check_file_unstaged: passes when the file is staged-only (no unstaged delta)" {
  echo "a" > a.txt; git add a.txt; git commit -q -m "init"
  echo "x" >> a.txt; git add a.txt          # fully staged, no working-tree delta

  run check_file_unstaged a.txt
  assert_success
}
