#!/usr/bin/env bats
# Tests for remote branch functions in hug-git-branch library

# Load test helpers
load '../test_helper.bash'

setup() {
  require_hug
  
  # Create a test repo with remote
  TEST_REPO=$(create_test_repo_with_remote_upstream)
  cd "$TEST_REPO"
  
  # Create some remote branches for testing
  git checkout -q -b feature
  echo "feature work" > feature.txt
  git add feature.txt
  git commit -q -m "Add feature"
  git push -q origin feature
  
  git checkout -q main
  git checkout -q -b bugfix
  echo "bugfix work" > bugfix.txt
  git add bugfix.txt
  git commit -q -m "Add bugfix"
  git push -q origin bugfix
  
  git checkout -q main
  git branch -D feature bugfix >/dev/null 2>&1
  git fetch -q
  
  # Source the library to test functions directly
  source "$HUG_HOME/git-config/lib/hug-git-branch"
}

teardown() {
  cleanup_test_repo
}

# -----------------------------------------------------------------------------
# compute_remote_branch_details tests
# -----------------------------------------------------------------------------

@test "compute_remote_branch_details: populates arrays with remote branch info" {
  # Verify remote branches exist first
  run git branch -r
  assert_success
  
  declare -a branches=() hashes=() remote_refs=() subjects=()
  local max_len=0
  
  compute_remote_branch_details max_len hashes branches remote_refs subjects "true"
  
  # Should find at least some remote branches (we know we created feature and bugfix)
  [ ${#branches[@]} -ge 1 ]
  [ ${#hashes[@]} -eq ${#branches[@]} ]
  [ ${#remote_refs[@]} -eq ${#branches[@]} ]
  [ ${#subjects[@]} -eq ${#branches[@]} ]
  
  # Max length should be computed
  [ "$max_len" -gt 0 ]
}

@test "compute_remote_branch_details: strips remote prefix from branch names" {
  declare -a branches=() hashes=() remote_refs=() subjects=()
  local max_len=0
  
  compute_remote_branch_details max_len hashes branches remote_refs subjects "true"
  
  # Branch names should not have "origin/" prefix
  local found_feature=false
  for branch in "${branches[@]}"; do
    [[ "$branch" != origin/* ]]
    if [[ "$branch" == "feature" ]]; then
      found_feature=true
    fi
  done
  
  [ "$found_feature" = true ]
}

@test "compute_remote_branch_details: remote_refs contain full remote paths" {
  declare -a branches=() hashes=() remote_refs=() subjects=()
  local max_len=0
  
  compute_remote_branch_details max_len hashes branches remote_refs subjects "true"
  
  # At least one remote ref should have "origin/" prefix
  local found_origin=false
  for ref in "${remote_refs[@]}"; do
    if [[ "$ref" == origin/* ]]; then
      found_origin=true
      break
    fi
  done
  
  [ "$found_origin" = true ]
}

@test "compute_remote_branch_details: excludes HEAD references" {
  declare -a branches=() hashes=() remote_refs=() subjects=()
  local max_len=0
  
  compute_remote_branch_details max_len hashes branches remote_refs subjects "true"
  
  # No branch or ref should be named "HEAD"
  for branch in "${branches[@]}"; do
    [[ "$branch" != "HEAD" ]]
  done
  
  for ref in "${remote_refs[@]}"; do
    [[ "$ref" != */HEAD ]]
  done
}

@test "compute_remote_branch_details: includes subjects when requested" {
  declare -a branches=() hashes=() remote_refs=() subjects=()
  local max_len=0
  
  compute_remote_branch_details max_len hashes branches remote_refs subjects "true"
  
  # Subjects array should be populated
  [ ${#subjects[@]} -gt 0 ]
  [ ${#subjects[@]} -eq ${#branches[@]} ]
}

@test "compute_remote_branch_details: omits subjects when not requested" {
  declare -a branches=() hashes=() remote_refs=() subjects=()
  local max_len=0
  
  compute_remote_branch_details max_len hashes branches remote_refs subjects "false"
  
  # Subjects array should be empty
  [ ${#subjects[@]} -eq 0 ]
  # But other arrays should still be populated
  [ ${#branches[@]} -gt 0 ]
}

@test "compute_remote_branch_details: returns error when no remote branches exist" {
  # Remove all remote branches (keep only local)
  git branch -r | grep -v '/HEAD' | xargs -I {} git branch -rd {} || true
  
  declare -a branches=() hashes=() remote_refs=() subjects=()
  local max_len=0
  
  run compute_remote_branch_details max_len hashes branches remote_refs subjects "true"
  assert_failure
}

# -----------------------------------------------------------------------------
# find_remote_branch tests
# -----------------------------------------------------------------------------

@test "find_remote_branch: finds remote branch by short name" {
  run find_remote_branch "feature"
  assert_success
  assert_output "origin/feature"
}

@test "find_remote_branch: finds remote branch by full remote ref" {
  run find_remote_branch "origin/bugfix"
  assert_success
  assert_output "origin/bugfix"
}

@test "find_remote_branch: returns error when branch not found" {
  run find_remote_branch "nonexistent"
  assert_failure
}

@test "find_remote_branch: prefers origin when multiple remotes have same branch" {
  # Add a second remote
  local remote2_root
  remote2_root=$(mktemp -d -t "hug-remote2-XXXXXX")
  local remote2_repo="$remote2_root/upstream.git"
  git init --bare -q "$remote2_repo"
  HUG_TEST_REMOTE_REPOS+=("$remote2_root")
  
  git remote add upstream "$remote2_repo"
  
  # Create and push to both remotes
  git checkout -q -b test-branch
  echo "test" > test.txt
  git add test.txt
  git commit -q -m "Test"
  git push -q origin test-branch
  git push -q upstream test-branch
  git checkout -q main
  git branch -D test-branch >/dev/null 2>&1
  git fetch -q --all
  
  # Should prefer origin
  run find_remote_branch "test-branch"
  assert_success
  assert_output "origin/test-branch"
}

@test "find_remote_branch: returns first alphabetically when origin not available" {
  # Add remotes that don't include "origin" in name
  local remote1_root remote2_root
  remote1_root=$(mktemp -d -t "hug-remote-zebra-XXXXXX")
  remote2_root=$(mktemp -d -t "hug-remote-alpha-XXXXXX")
  
  local remote1_repo="$remote1_root/zebra.git"
  local remote2_repo="$remote2_root/alpha.git"
  
  git init --bare -q "$remote1_repo"
  git init --bare -q "$remote2_repo"
  
  HUG_TEST_REMOTE_REPOS+=("$remote1_root" "$remote2_root")
  
  # Remove origin and add new remotes
  git remote remove origin
  git remote add zebra "$remote1_repo"
  git remote add alpha "$remote2_repo"
  
  # Create and push branch to both
  git checkout -q -b special-branch
  echo "special" > special.txt
  git add special.txt
  git commit -q -m "Special"
  git push -q zebra special-branch
  git push -q alpha special-branch
  git checkout -q main
  git branch -D special-branch >/dev/null 2>&1
  git fetch -q --all
  
  # Should return first alphabetically (alpha)
  run find_remote_branch "special-branch"
  assert_success
  assert_output "alpha/special-branch"
}

@test "find_remote_branch: handles branch names with slashes" {
  git checkout -q -b release/v1.0
  echo "sub" > sub.txt
  git add sub.txt
  git commit -q -m "Sub feature"
  git push -q origin release/v1.0
  git checkout -q main
  git branch -D release/v1.0 >/dev/null 2>&1
  git fetch -q
  
  run find_remote_branch "release/v1.0"
  assert_success
  assert_output "origin/release/v1.0"
}
