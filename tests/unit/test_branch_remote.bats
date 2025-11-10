#!/usr/bin/env bats
# Tests for remote branch handling in hug b

# Load test helpers
load '../test_helper.bash'

setup() {
  enable_gum_for_test
  require_hug
  
  # Create a test repo with remote
  TEST_REPO=$(create_test_repo_with_remote_upstream)
  cd "$TEST_REPO"
  
  # Create some remote branches for testing
  # Create feature branch
  git checkout -q -b feature
  echo "feature work" > feature.txt
  git add feature.txt
  git commit -q -m "Add feature"
  git push -q origin feature
  
  # Create bugfix branch
  git checkout -q main
  git checkout -q -b bugfix
  echo "bugfix work" > bugfix.txt
  git add bugfix.txt
  git commit -q -m "Add bugfix"
  git push -q origin bugfix
  
  # Go back to main and delete local branches to simulate remote-only branches
  git checkout -q main
  git branch -D feature bugfix >/dev/null 2>&1
  
  # Fetch to update remote tracking
  git fetch -q
}

teardown() {
  cleanup_test_repo
}

# -----------------------------------------------------------------------------
# Auto-create from remote branch tests
# -----------------------------------------------------------------------------

@test "hug b <remote-branch>: creates local tracking branch when branch exists on remote only" {
  # Verify feature branch doesn't exist locally
  run git show-ref --verify --quiet refs/heads/feature
  assert_failure
  
  # Verify it exists on remote
  run git show-ref --verify --quiet refs/remotes/origin/feature
  assert_success
  
  # Switch using hug b
  run hug b feature
  assert_success
  assert_output --partial "Creating local branch 'feature' tracking 'origin/feature'"
  assert_output --partial "Switched to new branch 'feature'"
  
  # Verify we're on the new branch
  current=$(git branch --show-current)
  [ "$current" = "feature" ]
  
  # Verify it's tracking the remote
  upstream=$(git rev-parse --abbrev-ref feature@{upstream})
  [ "$upstream" = "origin/feature" ]
}

@test "hug b <remote-branch>: with full remote ref creates local tracking branch" {
  # Verify bugfix branch doesn't exist locally
  run git show-ref --verify --quiet refs/heads/bugfix
  assert_failure
  
  # Switch using full remote ref
  run hug b origin/bugfix
  assert_success
  assert_output --partial "Creating local branch 'bugfix' tracking 'origin/bugfix'"
  
  # Verify we're on the new branch
  current=$(git branch --show-current)
  [ "$current" = "bugfix" ]
  
  # Verify tracking
  upstream=$(git rev-parse --abbrev-ref bugfix@{upstream})
  [ "$upstream" = "origin/bugfix" ]
}

@test "hug b <local-branch>: switches to existing local branch normally" {
  # Create a local branch
  git checkout -q -b local-only
  git checkout -q main
  
  # Verify behavior doesn't change for existing local branches
  run hug b local-only
  assert_success
  
  # Should not show "Creating" message
  refute_output --partial "Creating local branch"
  
  current=$(git branch --show-current)
  [ "$current" = "local-only" ]
}

@test "hug b <nonexistent-branch>: shows error when branch not found locally or remotely" {
  run hug b nonexistent-branch
  assert_failure
  # Git's own error message should appear (can vary by git version)
  assert_output --regexp "(did not match|invalid reference)"
}

@test "hug b <remote-branch>: handles branch with same name as local but different content" {
  # Create local feature branch with different content
  git checkout -q -b feature
  echo "different content" > feature.txt
  git add feature.txt
  git commit -q -m "Different feature"
  git checkout -q main
  
  # Now try to switch to feature (should use local, not create from remote)
  run hug b feature
  assert_success
  
  # Should not show "Creating" message since local exists
  refute_output --partial "Creating local branch"
  
  current=$(git branch --show-current)
  [ "$current" = "feature" ]
  
  # Verify it's the local branch (has our different content)
  [ -f feature.txt ]
  grep -q "different content" feature.txt
}

# -----------------------------------------------------------------------------
# --remote flag tests
# -----------------------------------------------------------------------------

@test "hug b -r <branch>: shows error when branch argument provided with -r flag" {
  run hug b -r main
  assert_failure
  assert_output --partial "The -r/--remote flag cannot be used with a branch argument"
}

@test "hug b --remote <branch>: shows error when branch argument provided with --remote flag" {
  run hug b --remote main
  assert_failure
  assert_output --partial "The -r/--remote flag cannot be used with a branch argument"
}

# Note: Interactive menu tests for -r flag would require mocking gum or user input
# We test the error case above, and the library functions separately

# -----------------------------------------------------------------------------
# Help text tests
# -----------------------------------------------------------------------------

@test "hug b -h: shows updated help with -r flag documentation" {
  run hug b -h
  assert_success
  assert_output --partial "-r, --remote"
  assert_output --partial "remote branches"
  assert_output --partial "creates a local tracking branch"
}

@test "hug b --help: documents automatic remote branch tracking" {
  run hug b -h
  assert_success
  assert_output --partial "automatically"
  assert_output --partial "tracking branch"
}

# -----------------------------------------------------------------------------
# Edge cases
# -----------------------------------------------------------------------------

@test "hug b <remote-branch>: handles branch names with slashes" {
  # Create a branch name with slashes (use "hotfix" to avoid conflict with "feature" branch)
  git checkout -q -b hotfix/slash-test
  echo "test" > slashtest.txt
  git add slashtest.txt
  git commit -q -m "Add slash test"
  git push -q origin hotfix/slash-test
  git checkout -q main
  git branch -D hotfix/slash-test >/dev/null 2>&1
  git fetch -q
  
  # Switch to it
  run hug b hotfix/slash-test
  assert_success
  assert_output --partial "Creating local branch 'hotfix/slash-test'"
  
  current=$(git branch --show-current)
  [ "$current" = "hotfix/slash-test" ]
}

@test "hug b: prefers origin when multiple remotes have same branch" {
  # Add a second remote
  local remote2_root
  remote2_root=$(mktemp -d -t "hug-remote2-XXXXXX")
  local remote2_repo="$remote2_root/upstream.git"
  git init --bare -q "$remote2_repo"
  HUG_TEST_REMOTE_REPOS+=("$remote2_root")
  
  git remote add upstream "$remote2_repo"
  
  # Create a unique branch for this test
  git checkout -q -b multiremote
  echo "multiremote" > multiremote.txt
  git add multiremote.txt
  git commit -q -m "Multiremote feature"
  git push -q origin multiremote
  git push -q upstream multiremote
  git checkout -q main
  git branch -D multiremote >/dev/null 2>&1
  git fetch -q --all
  
  # Verify both remotes have the branch
  run git branch -r
  assert_output --partial "origin/multiremote"
  assert_output --partial "upstream/multiremote"
  
  # hug b should prefer origin
  run hug b multiremote
  assert_success
  assert_output --partial "origin/multiremote"
  
  upstream=$(git rev-parse --abbrev-ref multiremote@{upstream})
  [ "$upstream" = "origin/multiremote" ]
}
