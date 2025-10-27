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
  # Save and unset fallback environment variables to ensure consistent behavior
  local saved_git_sequence_editor="${GIT_SEQUENCE_EDITOR:-}"
  local saved_visual="${VISUAL:-}"
  local saved_editor="${EDITOR:-}"
  unset GIT_SEQUENCE_EDITOR
  unset VISUAL
  unset EDITOR
  
  GIT_EDITOR="false" run hug c
  
  # Debug output
  echo "# Exit status: $status" >&3
  echo "# Output:" >&3
  echo "$output" | sed 's/^/# /' >&3
  
  assert_failure
  assert_output --partial "there was a problem with the editor"
  
  # Restore original values (BATS runs tests in subshells, so this is defensive)
  [[ -n "$saved_git_sequence_editor" ]] && export GIT_SEQUENCE_EDITOR="$saved_git_sequence_editor"
  [[ -n "$saved_visual" ]] && export VISUAL="$saved_visual"
  [[ -n "$saved_editor" ]] && export EDITOR="$saved_editor"
  : # the previous command may have returned false
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

@test "hug c: amends last commit with --amend" {
  local repo
  repo=$(create_test_repo_with_history)
  pushd "$repo" >/dev/null

  echo "amend content" > amend.txt
  git add amend.txt
  run hug c -m "Add amend file"
  assert_success

  echo "amend update" >> amend.txt
  git add amend.txt
  run hug c --amend -m "Add amend file (amended)"
  assert_success

  run git log -1 --format=%s
  assert_output "Add amend file (amended)"

  run git show --stat HEAD
  assert_output --partial "amend.txt"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug c: surfaces commit hook failures" {
  local repo
  repo=$(create_test_repo_with_history)
  pushd "$repo" >/dev/null

  cat > .git/hooks/commit-msg <<'HOOK'
#!/usr/bin/env bash
echo "rejecting commit from hook" >&2
exit 1
HOOK
  chmod +x .git/hooks/commit-msg

  echo "hook failure" > hook.txt
  git add hook.txt

  run hug c -m "Commit rejected by hook"
  assert_failure
  assert_output --partial "rejecting commit from hook"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug c: errors when author identity unknown" {
  local repo
  repo=$(create_temp_repo_dir)
  pushd "$repo" >/dev/null

  # Save and unset all possible sources of git identity to ensure test fails as expected
  local saved_git_author_name="${GIT_AUTHOR_NAME:-}"
  local saved_git_author_email="${GIT_AUTHOR_EMAIL:-}"
  local saved_git_committer_name="${GIT_COMMITTER_NAME:-}"
  local saved_git_committer_email="${GIT_COMMITTER_EMAIL:-}"
  unset GIT_AUTHOR_NAME
  unset GIT_AUTHOR_EMAIL
  unset GIT_COMMITTER_NAME
  unset GIT_COMMITTER_EMAIL
  
  git init -q
  echo "content" > file.txt
  git add file.txt

  run hug c -m "Should fail"
  
  # Debug output
  echo "# Exit status: $status" >&3
  echo "# Output:" >&3
  echo "$output" | sed 's/^/# /' >&3
  
  assert_failure
  assert_output --partial "Author identity unknown"

  # Restore original values (BATS runs tests in subshells, so this is defensive)
  [[ -n "$saved_git_author_name" ]] && export GIT_AUTHOR_NAME="$saved_git_author_name"
  [[ -n "$saved_git_author_email" ]] && export GIT_AUTHOR_EMAIL="$saved_git_author_email"
  [[ -n "$saved_git_committer_name" ]] && export GIT_COMMITTER_NAME="$saved_git_committer_name"
  [[ -n "$saved_git_committer_email" ]] && export GIT_COMMITTER_EMAIL="$saved_git_committer_email"
  : # To avoid affecting test result

  popd >/dev/null
  rm -rf "$repo"
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
@test "hug cmv: moves last commit to existing branch (cherry-pick) and stays on it" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null
  
  git checkout -q main
  local original_head
  original_head=$(git rev-parse HEAD)
  
  # Create target branch at HEAD~2 (not direct parent, to ensure cherry-pick creates new commit)
  git checkout -q -b target-branch HEAD~2
  
  git checkout -q main
  
  run hug cmv 1 target-branch --force
  assert_success
  refute_output --partial "Commits to be affected:"
  assert_output --partial "📊 1 commit since"
  assert_output --partial "📤 moving to target-branch:"
  
  # Original branch reset back
  assert_equal "$(git rev-parse main)" "$(git rev-parse "$original_head~1")"
  
  # Now on target-branch
  run git branch --show-current
  assert_output "target-branch"
  
  # Commit moved to target-branch (new commit via cherry-pick)
  run git log -2 --oneline
  assert_line --index 0 --partial "Add main extra"
  # New commit hash when parent is different
  assert_not_equal "$(git rev-parse HEAD)" "$original_head"
  
  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: single unified preview for existing branch (no duplication)" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null
  
  git checkout -q main
  local original_head
  original_head=$(git rev-parse HEAD)
  
  # Create existing target branch
  git checkout -q -b existing-target HEAD~1
  git checkout -q main
  
  run hug cmv 1 existing-target --force
  assert_success
  refute_output --partial "Commits to be affected:"
  refute_output --partial "Preview: changes in"
  assert_output --partial "📊 1 commit since"
  # Ensure the preview section (between 📊 and operational git output) shows commit hash only once
  # Extract just the preview section (everything before "HEAD is now" which is from git reset)
  local preview_section
  preview_section=$(echo "$output" | sed -n '/📊/,/HEAD is now/p' | head -n -1)
  local commit_hash
  commit_hash=$(git rev-parse --short "$original_head")
  # grep -c returns 0 if no matches are found, so no fallback is needed
  local count=$(echo "$preview_section" | grep -c "$commit_hash")
  assert_equal "$count" 1
  assert_output --partial "📤 moving to existing-target:"
  
  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: detaches exact history to new branch (--new) and stays on it" {
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
  refute_output --partial "Commits to be affected:"
  assert_output --partial "📊 1 commit since"
  assert_output --partial "📤 moving to new-detach (new branch):"

  # Original branch reset back
  assert_equal "$(git rev-parse main)" "$(git rev-parse "$original_head~1")"

  # Now on new-detach
  run git branch --show-current
  assert_output "new-detach"

  # New branch log matches exact range SHAs (no new commits)
  run git log --oneline HEAD~1..HEAD
  assert_output "$expected_log"  # Exact match - just the moved commit(s)
  assert_equal "$(git rev-parse HEAD)" "$original_head"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: moves multiple commits to new branch (detach) and stays on it" {
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
  
  # Now on new-branch
  run git branch --show-current
  assert_output "new-branch"

  # New branch log matches exact range SHAs
  run git log --oneline HEAD~2..HEAD
  assert_output "$expected_log"  # Exact match - just the moved commits
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

@test "hug cmv: skips confirmation with --force and stays on target (existing)" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null
  
  git checkout -q main
  
  # Create target branch
  git checkout -q -b target-branch HEAD~1
  git checkout -q main
  
  run hug cmv 1 target-branch --force
  assert_success
  
  # Now on target-branch
  run git branch --show-current
  assert_output "target-branch"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: moves to existing branch and stays on it (with confirmation)" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main
  local original_head
  original_head=$(git rev-parse HEAD)

  # Create existing target
  git checkout -q -b existing-target HEAD~1
  git checkout -q main

  run bash -c 'printf "y\n" | hug cmv 1 existing-target'
  assert_success
  assert_output --partial "Proceed with moving 1 commit to 'existing-target'?"

  # Original branch reset back
  assert_equal "$(git rev-parse main)" "$(git rev-parse "$original_head~1")"

  # Now on existing-target
  run git branch --show-current
  assert_output "existing-target"

  # Verify cherry-pick
  run git log -1 --oneline
  assert_line --index 0 --partial "Add main extra"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: handles upstream mode" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null
  
  # Create a mock remote
  git checkout -q main
  git remote add origin "$repo"
  git fetch -q origin
  git branch --set-upstream-to=origin/main
  
  # Create a local commit on top
  echo "Local only" > local.txt
  git add local.txt
  git commit -q -m "Add local commit"
  
  # Mock upstream commit (for test, move the local commit)
  run hug cmv -u new-upstream --new --force
  assert_success
  
  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: prompts to create missing branch without --new (combined prompt, detach on y) and stays on it" {
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
  assert_output --partial "📊 1 commit since"
  assert_output --partial "📤 moving to prompt-missing (new branch):"
  assert_output --partial "Branch 'prompt-missing' doesn't exist. Proceed with creating a new branch named 'prompt-missing' and moving 1 commit to it?"

  # Verify creation and reset to just before
  local target_before
  target_before=$(git rev-parse "${original_head}~1")
  assert_equal "$(git rev-parse main)" "$target_before"
  run bash -c "git branch -l | grep prompt-missing"
  assert_success

  # Now on prompt-missing
  run git branch --show-current
  assert_output "prompt-missing"

  # New branch log matches exact range SHAs
  run git log --oneline HEAD~1..HEAD
  assert_output "$expected_log"  # Exact match - just the moved commit(s)
  assert_equal "$(git rev-parse HEAD)" "$original_head"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: aborts on 'n' to creation prompt without --new (combined prompt)" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main
  local original_head
  original_head=$(git rev-parse HEAD)

  run bash -c 'printf "n\n" | hug cmv 1 abort-missing'
  assert_failure
  assert_output --partial "Branch 'abort-missing' doesn't exist. Proceed with creating a new branch named 'abort-missing' and moving 1 commit to it?"
  assert_output --partial "Cancelled."

  # No changes
  assert_equal "$(git rev-parse HEAD)" "$original_head"
  run bash -c "git branch -l | grep abort-missing"
  refute_output

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: auto-creates with --force on missing without --new (detach) and stays on it" {
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
  refute_output --partial "Commits to be affected:"
  assert_output --partial "📊 1 commit since"
  assert_output --partial "📤 moving to auto-force-missing (new branch):"
  assert_output --partial "Branch auto-force-missing missing; auto-creating with --force from target $target_short."

  # Verify creation, reset to just before
  assert_equal "$(git rev-parse main)" "$(git rev-parse "${original_head}~1")"
  run bash -c "git branch -l | grep auto-force-missing"
  assert_success

  # Now on auto-force-missing
  run git branch --show-current
  assert_output "auto-force-missing"

  # New branch log matches exact range SHAs
  run git log --oneline HEAD~1..HEAD
  assert_output "$expected_log"  # Exact match - just the moved commit(s)
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
  assert_output --partial "Created and moved 1 commit to new branch 'post-force'. Now on 'post-force'."

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
  assert_output --partial "Moved 1 commit to 'existing-target'. Now on 'existing-target'."

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: aborts with cherry-pick conflict on existing branch" {
  local repo
  repo=$(create_test_repo_with_cherry_pick_conflict)
  pushd "$repo" >/dev/null

  git checkout -q main
  run hug cmv 1 conflict-target --force
  assert_failure
  assert_output --partial "CONFLICT"

  run git status --porcelain
  assert_output --partial "UU feature1.txt"

  git cherry-pick --abort >/dev/null 2>&1 || true

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: errors on invalid branch name" {
  local repo
  repo=$(create_test_repo_with_history)
  pushd "$repo" >/dev/null

  run hug cmv 1 "invalid branch" --new --force
  assert_failure
  assert_output --partial "invalid branch"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: errors on invalid commit target" {
  local repo
  repo=$(create_test_repo_with_history)
  pushd "$repo" >/dev/null

  run hug cmv deadbeef target-branch --force
  assert_failure
  assert_output --partial "fatal"

  run git branch --list target-branch
  if [[ -n "$output" ]]; then
    fail "Expected target-branch to not exist, found: $output"
  fi

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: errors when run from detached HEAD" {
  local repo
  repo=$(create_test_repo_with_history)
  pushd "$repo" >/dev/null

  git checkout --detach HEAD >/dev/null 2>&1

  run hug cmv 1 target-branch --force
  assert_failure
  assert_output --partial "Detached HEAD"

  git checkout -q main

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: detaches local-only commits to new branch with -u" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  pushd "$repo" >/dev/null

  local upstream_sha
  upstream_sha=$(git rev-parse origin/main)

  echo "local detach" > local-detach.txt
  git add local-detach.txt
  git commit -q -m "Local detach commit"
  local local_sha
  local_sha=$(git rev-parse HEAD)

  run hug cmv -u upstream-detach --new --force
  assert_success
  assert_equal "$(git rev-parse main)" "$upstream_sha"

  git checkout -q upstream-detach
  assert_equal "$(git rev-parse HEAD)" "$local_sha"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: moves local-only commits to existing branch with -u" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  pushd "$repo" >/dev/null

  git checkout -q -b existing-target origin/main
  echo "target branch content" > target.txt
  git add target.txt
  git commit -q -m "Existing branch baseline"
  git checkout -q main

  local upstream_sha
  upstream_sha=$(git rev-parse origin/main)
  echo "local existing" > local-existing.txt
  git add local-existing.txt
  git commit -q -m "Local existing commit"
  local local_sha
  local_sha=$(git rev-parse HEAD)

  run hug cmv -u existing-target --force
  assert_success
  assert_equal "$(git rev-parse main)" "$upstream_sha"

  git checkout -q existing-target
  run git log -1 --format=%s
  assert_output "Local existing commit"
  assert_not_equal "$(git rev-parse HEAD)" "$local_sha"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: errors on -u without upstream" {
  local repo
  repo=$(create_test_repo_with_history)
  pushd "$repo" >/dev/null

  run hug cmv -u missing --new --force
  assert_failure
  assert_output --partial "upstream"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: supports --quiet with --force" {
  local repo
  repo=$(create_test_repo_with_history)
  pushd "$repo" >/dev/null

  run hug cmv 1 quiet-branch --new --force --quiet
  assert_success
  if [[ -n "$output" ]]; then
    fail "Expected no output in quiet mode, got: $output"
  fi

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: no branch created when moving 0 commits" {
  local repo
  repo=$(create_test_repo_with_history)
  pushd "$repo" >/dev/null

  run hug cmv 0 zero-branch --force
  assert_success
  assert_output --partial "No commits to move"

  run git branch --list zero-branch
  if [[ -n "$output" ]]; then
    fail "Expected zero-branch to not exist, found: $output"
  fi

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: aborts if target branch doesn't exist without --new or --force" {
  run hug cmv 1 nonexistent
  assert_failure
  # Now prompts, but if n, aborts as above
}

@test "hug cmv: handles no commits to move gracefully" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null
  
  git checkout -q main
  run hug cmv 0 new-branch --new --force
  assert_success
  assert_output --partial "No commits to move"
  
  popd >/dev/null
  rm -rf "$repo"
}

# Additional cmv edge cases...
