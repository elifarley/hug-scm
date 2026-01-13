#!/usr/bin/env bats
# Tests for hug log-outgoing (hug lol) - preview outgoing changes

# Load test helpers
load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_remote_upstream)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

@test "hug lol: shows help with -h flag" {
  run hug lol -h
  assert_success
  assert_output --partial "hug log-outgoing: Preview outgoing changes to upstream or custom target."
  assert_output --partial "USAGE:"
  assert_output --partial "<remote-branch>"
}

@test "hug lol: shows help with --help flag" {
  # Note: git intercepts --help and tries to show man page before our script runs
  # This is built into git and cannot be overridden for custom commands
  skip "git intercepts --help for man pages (use -h instead)"
}

@test "hug lol: errors without upstream when no remote-branch provided" {
  # Create a repo without upstream
  local repo
  repo=$(create_test_repo)
  cd "$repo"
  
  run hug lol
  assert_failure
  assert_output --partial "No upstream branch configured for the current branch."
}

@test "hug lol: previews outgoing to upstream with no args" {
  # Add local commits ahead of upstream
  echo "Local change" > local.txt
  git add local.txt
  git commit -q -m "Local commit 1"
  
  echo "More local" >> local.txt
  git add local.txt
  git commit -q -m "Local commit 2"
  
  run hug lol
  assert_success
  assert_output --partial "📊 2 commits since"
  assert_output --partial "Local commit 1"
  assert_output --partial "Local commit 2"
  assert_output --partial "Ready to push? Use \"hug bpush\"."
  refute_output --partial "Using custom target"
}

@test "hug lol: handles no outgoing commits to upstream" {
  # No local commits beyond upstream
  run hug lol
  assert_success
  assert_output --partial "No outgoing changes (already synced to"
  refute_output --partial "commits since"
}

@test "hug lol: uses custom remote-branch when provided" {
  # Use a different remote branch (assuming origin/main exists as upstream, test origin/feature if needed, but use main)
  # First, create a feature commit on main for outgoing
  echo "Feature change" > feature.txt
  git add feature.txt
  git commit -q -m "Feature commit"
  
  run hug lol origin/main
  assert_success
  assert_output --partial "Using custom target: origin/main"
  assert_output --partial "📊 1 commits since"
  assert_output --partial "Feature commit"
  assert_output --partial "Ready to push to origin/main? Set upstream with"
  refute_output --partial "Ready to push? Use \"hug bpush\"."
}

@test "hug lol: errors on invalid remote-branch" {
  run hug lol invalid/nonexistent
  assert_failure
  assert_output --partial "Invalid remote branch 'invalid/nonexistent': ref does not exist."
}

@test "hug lol: works without upstream using custom remote-branch" {
  # Create repo without upstream, but with remote
  local repo
  repo=$(create_test_repo)
  cd "$repo"
  local remote_root
  remote_root=$(mktemp -d -t "hug-remote-no-upstream-XXXXXX")
  local remote_repo="$remote_root/origin.git"
  git init --bare -q "$remote_repo"
  git remote add origin "$remote_repo"
  git push -q origin main
  
  # Add local commit
  echo "Local only" > local.txt
  git add local.txt
  git commit -q -m "Local commit"
  
  run hug lol origin/main
  assert_success
  assert_output --partial "Using custom target: origin/main"
  assert_output --partial "📊 1 commits since"
  assert_output --partial "Local commit"
}

@test "hug lol: handles no outgoing commits with custom remote-branch" {
  run hug lol origin/main
  assert_success
  assert_output --partial "No outgoing changes (already synced to"
  refute_output --partial "commits since"
}

@test "hug lol: --quiet mode suppresses verbose output but keeps core previews" {
  echo "Quiet change" > quiet.txt
  git add quiet.txt
  git commit -q -m "Quiet commit"
  
  run hug lol --quiet
  assert_success
  assert_output --partial "📊 1 commits since"
  # Core: diff stat, cherry, status (but status may be minimal)
  assert_output --partial "1 file changed"
  # Suppresses: log, ready message
  refute_output --partial "Outgoing commits to upstream"
  refute_output --partial "Ready to push"
}

@test "hug lol: --quiet with custom remote-branch" {
  echo "Custom quiet" > custom.txt
  git add custom.txt
  git commit -q -m "Custom commit"
  
  run hug lol --quiet origin/main
  assert_success
  assert_output --partial "Using custom target"
  assert_output --partial "📊 1 commits since"
  refute_output --partial "Outgoing commits to"
  refute_output --partial "Ready to push to"
}

@test "hug lol: --fetch updates remotes before preview" {
  # Simulate stale remote by adding remote commit (but since bare, assume fetch updates)
  # For test, fetch should run without error
  run hug lol --fetch
  assert_success
  assert_output --partial "Fetching remotes..."
  # If no outgoing, but test assumes setup has outgoing; adjust if needed
  # This mainly checks no crash on fetch
}

@test "hug lol: --fetch with custom remote-branch" {
  run hug lol --fetch origin/main
  assert_success
  assert_output --partial "Fetching remotes..."
  assert_output --partial "Using custom target"
}

@test "hug lol: shows cherry output for exact missing commits" {
  echo "Cherry commit" > cherry.txt
  git add cherry.txt
  git commit -q -m "Cherry commit"
  
  run hug lol
  assert_success
  # Cherry shows + for local uniques
  assert_output --partial "+ $(git rev-parse --short HEAD)"
}

@test "hug lol: includes status in output" {
  # Create outgoing commit first
  echo "Outgoing" > outgoing.txt
  git add outgoing.txt
  git commit -q -m "Outgoing commit"
  
  # Create unstaged change
  echo "Unstaged" > unstaged.txt
  
  run hug lol
  assert_success
  # Check that status summary line is included (shows untracked count)
  assert_output --partial "K:1"
  assert_output --partial "Outgoing commit"
}

@test "hug lol: handles custom remote-branch that matches local name but uses remote ref" {
  # Test resolves refs/remotes/origin/main even if local main exists
  run hug lol origin/main
  assert_success
  assert_output --partial "Using custom target: origin/main"
  # Confirms it uses remote ref
}
