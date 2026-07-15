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
