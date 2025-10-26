#!/usr/bin/env bats
# Tests for hug c (git-c) command

load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_changes)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

@test "hug c: shows help with -h" {
  run hug c -h
  assert_success
  assert_output --partial "hug c: Commit staged changes."
  assert_output --partial "USAGE:"
  assert_output --partial "OPTIONS:"
  assert_output --partial "--quiet       Suppress non-essential output."
}

@test "hug c: shows help with --help" {
  # Note: git intercepts --help and tries to show man page before our script runs
  # This is built into git and cannot be overridden for custom commands
  skip "git intercepts --help for man pages (use -h instead)"
}

@test "hug c: fails gracefully outside git repo" {
  cd /tmp
  run hug c
  assert_failure
  assert_output --partial "Not in a Git or Mercurial repository"
}

@test "hug c: informs when no staged changes without --allow-empty" {
  # Unstage everything
  git restore --staged .

  run hug c -m "test"
  assert_failure
  assert_output --partial "No staged changes found."
  assert_output --partial "Suggestions:"
  assert_output --partial "hug a <files>"
}

@test "hug c: allows empty commit with --allow-empty" {
  run hug c --allow-empty -m "Empty commit"
  assert_success
  assert_output --partial "Committing staged changes..."

  # Verify commit exists
  run git log -1 --format=%s
  assert_output "Empty commit"
}

@test "hug c: commits staged changes with -m" {
  local original_head
  original_head=$(git rev-parse HEAD)

  run hug c -m "Staged commit"
  assert_success
  assert_output --partial "Committing staged changes..."

  local new_head
  new_head=$(git rev-parse HEAD)
  assert_not_equal "$original_head" "$new_head"

  run git log -1 --format=%s
  assert_output "Staged commit"

  # Unstaged changes should remain
  run git diff --name-only
  assert_output --partial "README.md"
}

@test "hug c: preserves unstaged and untracked files" {
  run hug c -m "Test commit"
  assert_success

  # Unstaged should still be modified
  run git diff --name-only
  assert_output --partial "README.md"

  # Untracked should remain
  assert_file_exists "untracked.txt"
}


@test "hug c: works with --quiet (minimal output)" {
  run hug c -m "Quiet commit" --quiet
  assert_success
  refute_output --partial "Committing staged changes..."
}

@test "hug c: propagates git commit errors" {
  # Attempt commit without message and fake editor failure
  GIT_EDITOR="false" run hug c
  assert_failure
  assert_output --partial "there was a problem with the editor"
}

@test "hug c: commits in repo with no prior commits" {
  # Create fresh repo without initial commit
  local fresh_repo
  fresh_repo=$(create_temp_repo_dir)
  cd "$fresh_repo"
  git init -q
  git config user.name "Test"
  git config user.email "test@example.com"

  echo "first" > first.txt
  git add first.txt

  run hug c -m "Initial commit"
  assert_success
  assert_output --partial "Committing staged changes..."

  run git log -1 --format=%s
  assert_output "Initial commit"
}

@test "hug c: handles no arguments correctly (no pathspec error)" {
  # Setup with staged changes
  echo "staged content" > staged_no_msg.txt
  git add staged_no_msg.txt

  # Create a fake editor that writes a message
  local fake_editor=$(mktemp)
  cat > "$fake_editor" << 'EDITORSCRIPT'
#!/bin/bash
echo "Test commit message" > "$1"
EDITORSCRIPT
  chmod +x "$fake_editor"

  # Should succeed without pathspec error
  GIT_EDITOR="$fake_editor" run hug c
  assert_success
  refute_output --partial "pathspec"
  refute_output --partial "empty string"

  # Verify commit was created
  run git log -1 --format=%s
  assert_output "Test commit message"

  rm -f "$fake_editor"

  # Clean case: no staged, no args
  git reset --hard HEAD  # Clean staging
  run hug c
  assert_failure
  assert_output --partial "No staged changes found."
  refute_output --partial "pathspec"
  refute_output --partial "empty string"
}

@test "hug c: handles flags only (no args, no pathspec error)" {
  # Staged changes + quiet flag only
  echo "quiet staged" > quiet_staged.txt
  git add quiet_staged.txt

  # Create a fake editor that writes a message
  local fake_editor=$(mktemp)
  cat > "$fake_editor" << 'EDITORSCRIPT'
#!/bin/bash
echo "Quiet commit message" > "$1"
EDITORSCRIPT
  chmod +x "$fake_editor"

  GIT_EDITOR="$fake_editor" run hug c --quiet
  assert_success
  refute_output --partial "pathspec"
  refute_output --partial "empty string"
  refute_output --partial "Committing staged changes..."  # Quiet suppresses

  # Verify commit
  run git log -1 --format=%s
  assert_output "Quiet commit message"

  rm -f "$fake_editor"
}

# -----------------------------------------------------------------------------
# hug cmv expectations
#   - Copies specified commits to target branch (new or existing) via cherry-pick.
#   - Resets original branch back to target commit (discards from original history).
#   - Requires clean working tree and index (no staged/unstaged; untracked ok).
#   - With -u, moves local-only commits above upstream.
#   - Aborts on conflicts, invalid branches, or without --new if branch doesn't exist.
#   - Requires confirmation (skipped with --force).
# -----------------------------------------------------------------------------
@test "hug cmv: moves last commit to existing branch (cherry-pick)" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null
  
  git checkout -q main
  local original_head
  original_head=$(git rev-parse HEAD)
  
  # Create target branch
  git checkout -q -b target-branch HEAD~1
  
  git checkout -q main
  
  run hug cmv 1 target-branch --force
  assert_success
  
  # Original branch reset back
  assert_equal "$(git rev-parse main)" "$(git rev-parse "$original_head~1")"
  
  # Commit moved to target-branch (new commit via cherry-pick)
  git checkout -q target-branch
  run git log -2 --oneline
  assert_line --index 0 --partial "Add main extra"
  # New commit hash, but message matches
  refute_equal "$(git rev-parse HEAD)" "$original_head"
  
  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: detaches exact history to new branch (--new)" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null
  
  git checkout -q main
  local original_head
  original_head=$(git rev-parse HEAD)
  local expected_log
  expected_log=$(git log --oneline HEAD~1..HEAD)  # Range to move (1 commit)

  run hug cmv 1 new-detach --new --force
  assert_success

  # Original branch reset back
  assert_equal "$(git rev-parse main)" "$(git rev-parse "$original_head~1")"

  # New branch log matches exact range SHAs (no new commits)
  git checkout -q new-detach
  run git log --oneline
  assert_output "$expected_log"  # Exact match
  assert_equal "$(git rev-parse HEAD)" "$original_head"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: moves multiple commits to new branch (detach)" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null
  
  git checkout -q main
  local original_head
  original_head=$(git rev-parse HEAD)
  local expected_log
  expected_log=$(git log --oneline HEAD~2..HEAD)  # Range to move (2 commits)

  run hug cmv 2 new-branch --new --force
  assert_success
  
  # Original branch reset back
  assert_equal "$(git rev-parse main)" "$(git rev-parse "$original_head~2")"
  
  # New branch log matches exact range SHAs
  git checkout -q new-branch
  run git log --oneline
  assert_output "$expected_log"  # Exact match
  assert_equal "$(git rev-parse HEAD)" "$original_head"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: aborts if staged changes present" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null
  
  git checkout -q main
  echo "staged" > staged.txt
  git add staged.txt
  
  run hug cmv 1 target-branch --force
  assert_failure
  assert_output --partial "Require clean working tree and index to proceed"
  
  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: aborts if unstaged changes present" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null
  
  git checkout -q main
  echo "unstaged" >> README.md
  
  run hug cmv 1 target-branch --force
  assert_failure
  assert_output --partial "Require clean working tree and index to proceed"
  
  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: requires confirmation without --force" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null
  
  git checkout -q main
  
  # Create target branch
  git checkout -q -b target-branch HEAD~1
  git checkout -q main
  
  run bash -c 'printf "n\n" | hug cmv 1 target-branch'
  assert_failure
  assert_output --partial "Proceed with moving"
  assert_output --partial "Cancelled."
  
  # HEAD unchanged
  run git rev-parse HEAD
  assert_output "$(git rev-parse main)"
  
  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: skips confirmation with --force" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null
  
  git checkout -q main
  
  # Create target branch
  git checkout -q -b target-branch HEAD~1
  git checkout -q main
  
  run hug cmv 1 target-branch --force
  assert_success
  
  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: handles upstream mode" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null
  
  # Simulate upstream (assuming main has upstream)
  git checkout -q main
  git branch --set-upstream-to=origin/main >/dev/null 2>&1
  
  # Mock upstream commit (for test, assume HEAD~1 is "upstream")
  run hug cmv -u new-upstream --new --force
  # Note: Full upstream simulation may need mock remote; test basic flow
  assert_success
  
  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: prompts to create missing branch without --new (detach on y)" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main
  local original_head
  original_head=$(git rev-parse HEAD)
  local expected_log
  expected_log=$(git log --oneline HEAD~1..HEAD)  # Range to move

  run bash -c 'printf "y\n" | hug cmv 1 prompt-missing'
  assert_success
  assert_output --partial "Target branch 'prompt-missing' doesn't exist. Create it?"
  assert_output --partial "Proceed with moving 1 commit to 'prompt-missing' (detaching to new branch 'prompt-missing')?"

  # Verify creation and reset to just before
  local target_before
  target_before=$(git rev-parse "${original_head}~1")
  assert_equal "$(git rev-parse main)" "$target_before"
  run git branch -l | grep prompt-missing
  assert_success

  # New branch log matches exact range SHAs
  git checkout -q prompt-missing
  run git log --oneline
  assert_output "$expected_log"  # Exact match
  assert_equal "$(git rev-parse HEAD)" "$original_head"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: aborts on 'n' to creation prompt without --new" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main
  local original_head
  original_head=$(git rev-parse HEAD)

  run bash -c 'printf "n\n" | hug cmv 1 abort-missing'
  assert_failure
  assert_output --partial "Cancelled."

  # No changes
  assert_equal "$(git rev-parse HEAD)" "$original_head"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: auto-creates with --force on missing without --new (detach)" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main
  local original_head
  original_head=$(git rev-parse HEAD)
  local expected_log
  expected_log=$(git log --oneline HEAD~1..HEAD)  # Range to move
  local target_short
  target_short=$(git rev-parse --short "${original_head}~1")

  run hug cmv 1 auto-force-missing --force
  assert_success
  assert_output --partial "Branch auto-force-missing missing; auto-creating with --force from target $target_short."

  # Verify creation, reset to just before
  assert_equal "$(git rev-parse main)" "$(git rev-parse "${original_head}~1")"
  run git branch -l | grep auto-force-missing
  assert_success

  # New branch log matches exact range SHAs
  git checkout -q auto-force-missing
  run git log --oneline
  assert_output "$expected_log"  # Exact match
  assert_equal "$(git rev-parse HEAD)" "$original_head"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: post-op message for auto-creation with --force (detach)" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main
  local target_short
  target_short=$(git rev-parse --short HEAD~1)

  run hug cmv 1 post-force --force
  assert_success
  assert_output --partial "Detached commits to new branch 'post-force' (from original HEAD). Original branch reset to $target_short (just before the moved commits)."

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: post-op message for existing branch (cherry-pick)" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main
  local target_short
  target_short=$(git rev-parse --short HEAD~1)
  # Create existing target
  git checkout -q -b existing-target HEAD~1
  git checkout -q main

  run hug cmv 1 existing-target --force
  assert_success
  assert_output --partial "Moved 1 commit to 'existing-target'. Original branch reset to $target_short (just before the moved commits)."

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: aborts if target branch doesn't exist without --new or --force" {
  run hug cmv 1 nonexistent
  assert_failure
  # Now prompts, but if n, aborts as above
}

@test "hug cmv: handles no commits to move gracefully" {
  run hug cmv 0 new-branch --new --force
  assert_success
  assert_output --partial "No commits to move"
}

# Additional cmv edge cases...
