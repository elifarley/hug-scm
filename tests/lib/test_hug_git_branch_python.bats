#!/usr/bin/env bats
# Tests for hug-git-branch-python library: Python branch data processing
#
# These tests verify the Python implementation of branch functionality
# provides feature parity with the v1 bash library via bash eval.

load '../test_helper'
load '../../git-config/lib/hug-common'

# Ensure Python 3.10+ is available
setup() {
  require_hug
  export HUG_HOME="$BATS_TEST_DIRNAME/../.."

  # Create test repository with branches
  TEST_REPO=$(create_test_repo_with_branches)
  cd "$TEST_REPO"
}

teardown() {
  cd /
  cleanup_test_repo "$TEST_REPO"
}

################################################################################
# Local Branch Details Tests
################################################################################

@test "python branch module: outputs valid bash declarations" {
  # Run Python module
  run python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" local

  # Should succeed
  assert_success

  # Output should be valid bash declarations
  assert_output --partial "declare current_branch="
  assert_output --partial "declare max_len="
  assert_output --partial "declare -a branches="
  assert_output --partial "declare -a hashes="
  assert_output --partial "declare -a tracks="
  assert_output --partial "declare -a subjects="
}

@test "python branch module: eval produces correct variables" {
  # Source Python output and verify variables
  eval "$(python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" local)"

  # Variables should be set
  [[ -n "$current_branch" ]]
  [[ "$max_len" -gt 0 ]]
  [[ ${#branches[@]} -gt 0 ]]

  # Arrays should have consistent lengths
  [[ ${#branches[@]} -eq ${#hashes[@]} ]]
  [[ ${#branches[@]} -eq ${#tracks[@]} ]]
  [[ ${#branches[@]} -eq ${#subjects[@]} ]]
}

@test "python branch module: excludes backup branches by default" {
  # Create a backup branch
  git branch hug-backups/test-backup

  eval "$(python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" local)"

  # Backup branch should not be in results
  local found=0
  for branch in "${branches[@]}"; do
    if [[ "$branch" == "hug-backups/"* ]]; then
      found=1
      break
    fi
  done
  [[ $found -eq 0 ]]
}

@test "python branch module: includes subjects" {
  eval "$(python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" local)"

  # Subjects array should be populated
  [[ ${#subjects[@]} -gt 0 ]]

  # Each subject should be non-empty or have default text
  for subject in "${subjects[@]}"; do
    # Subject may be "(no commit message)" or have actual content
    [[ -n "$subject" ]]
  done
}

@test "python branch module: handles empty branches" {
  cd /tmp
  local empty_repo
  empty_repo=$(mktemp -d)
  cd "$empty_repo"
  git init -q

  # Detach HEAD so there are no branches
  git checkout --detach -q 2>/dev/null || true

  # Delete any branches that might exist
  git branch -D $(git branch) 2>/dev/null || true

  # Should return exit code 1 for no branches
  run python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" local

  cd /
  rm -rf "$empty_repo"

  # Should return failure code (BATS sets $status from 'run')
  [ "$status" -eq 1 ]
}

@test "python branch module: max_len is calculated correctly" {
  # Create branches with specific lengths
  git branch short
  git branch medium-length-branch
  git branch very-long-branch-name-here

  eval "$(python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" local)"

  # Max length should be at least the length of our longest branch name
  [[ $max_len -ge 26 ]]  # Length of "very-long-branch-name-here"
}

@test "python branch module: array consistency is maintained" {
  eval "$(python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" local)"

  # All arrays should have the same length
  local count=${#branches[@]}
  [[ ${#hashes[@]} -eq $count ]]
  [[ ${#tracks[@]} -eq $count ]]
  [[ ${#subjects[@]} -eq $count ]]

  # Each index should have consistent data
  for ((i=0; i<count; i++)); do
    # Verify hash is non-empty (short hash should be 4-40 chars)
    [[ ${#hashes[$i]} -ge 4 ]]
    [[ ${#hashes[$i]} -le 40 ]]

    # Branch name should be non-empty
    [[ -n "${branches[$i]}" ]]
  done
}

@test "python branch module: branch names are sanitized" {
  # Create a test branch
  git branch "test-branch-$$"

  eval "$(python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" local)"

  # No branch name should have trailing newlines or carriage returns
  for branch in "${branches[@]}"; do
    [[ ! "$branch" == *$'\n'* ]]
    [[ ! "$branch" == *$'\r'* ]]
  done
}

@test "python branch module: handles special characters in subjects" {
  # Create a branch with a commit message containing special characters
  git branch "special-branch-$$"
  git checkout "special-branch-$$" 2>/dev/null || true
  echo "test" > test-file.txt
  git add test-file.txt 2>/dev/null || true
  git commit -m "Commit with (parentheses) and [brackets]" 2>/dev/null || true
  git checkout - 2>/dev/null || true

  eval "$(python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" local)"

  # Should not error when evaluating
  [[ ${#branches[@]} -gt 0 ]]
}

################################################################################
# JSON Output Tests
################################################################################

@test "python branch module: json mode outputs valid JSON" {
  run python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" local --json

  # Should succeed
  assert_success

  # Should be valid JSON
  # Use python to validate JSON
  python3 -c "import sys, json; json.loads(sys.stdin.read())" <<< "$output"
}

@test "python branch module: json mode contains expected fields" {
  run python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" local --json

  assert_success

  # Use python to check JSON structure
  local json_check
  json_check=$(python3 -c "
import sys, json
data = json.loads(sys.stdin.read())
# Check required fields
assert 'current_branch' in data
assert 'max_len' in data
assert 'branches' in data
assert isinstance(data['branches'], list)
# Check each branch has required fields
for b in data['branches']:
    assert 'name' in b
    assert 'hash' in b
    assert 'subject' in b
    assert 'track' in b
print('OK')
" <<< "$output")

  [[ "$json_check" == "OK" ]]
}

################################################################################
# Remote Branch Tests
################################################################################

# Helper function to create a local bare remote for testing
setup_local_remote() {
  local remote_name="${1:-origin}"
  local remote_branch="${2:-main}"

  # Create a local bare repository as remote
  local remote_root
  remote_root=$(mktemp -d -p "$BATS_TEST_TMPDIR" -t "hug-remote-${remote_name}-XXXXXX")
  local remote_repo="$remote_root/${remote_name}.git"
  git init --bare -q "$remote_repo"
  HUG_TEST_REMOTE_REPOS+=("$remote_root")

  # Add as remote and push current branches
  git remote add "$remote_name" "$remote_repo"
  git push -q "$remote_name" "$remote_branch" 2>/dev/null || true

  # Fetch to create remote tracking branches
  git fetch -q "$remote_name" 2>/dev/null || true
}

@test "python branch module: remote mode outputs remote_refs array" {
  # Add a local remote (no GitHub prompts)
  setup_local_remote origin main

  # Check if we have remote branches
  local has_remotes
  has_remotes=$(git for-each-ref --format='%(refname:short)' refs/remotes/ 2>/dev/null | grep -v '/HEAD$' | head -1 || true)

  if [[ -z "$has_remotes" ]]; then
    skip "No remote branches available for testing"
  fi

  run python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" remote

  # Should succeed
  assert_success

  # Should include remote_refs array
  assert_output --partial "declare -a remote_refs="
}

@test "python branch module: remote mode eval works" {
  # Add a local remote (no GitHub prompts)
  setup_local_remote origin main

  # Check if we have remote branches
  local has_remotes
  has_remotes=$(git for-each-ref --format='%(refname:short)' refs/remotes/ 2>/dev/null | grep -v '/HEAD$' | head -1 || true)

  if [[ -z "$has_remotes" ]]; then
    skip "No remote branches available for testing"
  fi

  eval "$(python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" remote)"

  # remote_refs array should exist
  [[ ${#remote_refs[@]} -gt 0 ]]

  # Arrays should have consistent lengths
  [[ ${#branches[@]} -eq ${#remote_refs[@]} ]]
}

@test "python branch module: remote excludes HEAD references" {
  # Add a local remote (no GitHub prompts)
  setup_local_remote origin main

  # Check if we have remote branches
  local has_remotes
  has_remotes=$(git for-each-ref --format='%(refname:short)' refs/remotes/ 2>/dev/null | grep -v '/HEAD$' | head -1 || true)

  if [[ -z "$has_remotes" ]]; then
    skip "No remote branches available for testing"
  fi

  eval "$(python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" remote)"

  # No branch should be named "HEAD" or end with "/HEAD"
  for branch in "${branches[@]}"; do
    [[ "$branch" != "HEAD" ]]
    [[ ! "$branch" == */HEAD ]]
  done
}

################################################################################
# WIP Branch Tests
################################################################################

@test "python branch module: wip mode finds WIP branches" {
  # Create WIP branches
  git branch WIP/test-feature
  git branch WIP/bug-fix
  git branch WIP/experiment

  run python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" wip

  # Should succeed
  assert_success

  # Output should be valid bash
  assert_output --partial "declare -a branches="
}

@test "python branch module: wip mode eval works" {
  # Create WIP branches
  git branch WIP/test-feature
  git branch WIP/bug-fix

  eval "$(python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" wip)"

  # Should find WIP branches
  [[ ${#branches[@]} -ge 2 ]]

  # All branches should start with WIP/
  for branch in "${branches[@]}"; do
    [[ "$branch" == WIP/* ]]
  done
}

@test "python branch module: wip mode returns 1 when no WIP branches" {
  # Force no WIP branches by using non-existent pattern
  run python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" wip --pattern 'refs/heads/NONEXISTENT/'

  # Should return failure code
  [ "$status" -eq 1 ]
}

@test "python branch module: wip mode works with custom pattern" {
  # Create custom temp branches
  git branch temp/feature-1
  git branch temp/feature-2

  eval "$(python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" wip --pattern 'refs/heads/temp/')"

  # Should find temp branches
  [[ ${#branches[@]} -ge 2 ]]

  # All branches should start with temp/
  for branch in "${branches[@]}"; do
    [[ "$branch" == temp/* ]]
  done
}

################################################################################
# Error Handling Tests
################################################################################

@test "python branch module: handles non-git repo gracefully" {
  cd /tmp
  local non_repo_dir
  non_repo_dir=$(mktemp -d)
  cd "$non_repo_dir"

  # Should fail gracefully
  run python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" local

  cd /
  rm -rf "$non_repo_dir"

  # Should fail
  [ "$status" -eq 1 ]
}

@test "python branch module: unknown command fails" {
  run python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" unknown_command

  # Should fail
  [ "$status" -eq 2 ]
}

################################################################################
# Sort Order Tests
################################################################################

@test "python branch module: sorts by committerdate descending (newest first) by default" {
  # Create branches with known commit order
  git checkout -b branch_early
  git commit --allow-empty -m "Early commit" --no-gpg-sign --quiet

  sleep 1  # Ensure different timestamp

  git checkout main
  git checkout -b branch_late
  git commit --allow-empty -m "Late commit" --no-gpg-sign --quiet

  eval "$(python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" local)"

  # Verify branches exist
  [[ ${#branches[@]} -ge 2 ]]

  # Find positions of our test branches
  local early_pos=-1 late_pos=-1
  local i
  for ((i = 0; i < ${#branches[@]}; i++)); do
    if [[ "${branches[$i]}" == "branch_early" ]]; then
      early_pos=$i
    fi
    if [[ "${branches[$i]}" == "branch_late" ]]; then
      late_pos=$i
    fi
  done

  # branch_late should appear before branch_early (newest first)
  [[ $late_pos -lt $early_pos ]]

  # Cleanup
  git checkout main -q
  git branch -D branch_early branch_late -q
}

@test "python branch module: --ascending sorts by committerdate ascending (oldest first)" {
  # Create branches with known commit order
  git checkout -b branch_early
  git commit --allow-empty -m "Early commit" --no-gpg-sign --quiet

  sleep 1  # Ensure different timestamp

  git checkout main
  git checkout -b branch_late
  git commit --allow-empty -m "Late commit" --no-gpg-sign --quiet

  eval "$(python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" local --ascending)"

  # Verify branches exist
  [[ ${#branches[@]} -ge 2 ]]

  # Find positions of our test branches
  local early_pos=-1 late_pos=-1
  local i
  for ((i = 0; i < ${#branches[@]}; i++)); do
    if [[ "${branches[$i]}" == "branch_early" ]]; then
      early_pos=$i
    fi
    if [[ "${branches[$i]}" == "branch_late" ]]; then
      late_pos=$i
    fi
  done

  # branch_early should appear before branch_late (oldest first)
  [[ $early_pos -lt $late_pos ]]

  # Cleanup
  git checkout main -q
  git branch -D branch_early branch_late -q
}

@test "python branch module: wip mode respects sort order" {
  # Create WIP branches with known commit order
  git branch WIP/early-feature
  git checkout WIP/early-feature -q
  git commit --allow-empty -m "Early WIP commit" --no-gpg-sign --quiet

  sleep 1

  git checkout main -q
  git branch WIP/late-feature
  git checkout WIP/late-feature -q
  git commit --allow-empty -m "Late WIP commit" --no-gpg-sign --quiet

  # Test descending (newest first, default)
  eval "$(python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" wip)"
  [[ ${#branches[@]} -ge 2 ]]
  [[ "${branches[0]}" == "WIP/late-feature" ]]

  # Test ascending (oldest first)
  eval "$(python3 "$HUG_HOME/git-config/lib/python/hug_git_branch.py" wip --ascending)"
  [[ ${#branches[@]} -ge 2 ]]
  [[ "${branches[0]}" == "WIP/early-feature" ]]

  # Cleanup
  git checkout main -q
  git branch -D WIP/early-feature WIP/late-feature -q
}
