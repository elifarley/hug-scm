#!/usr/bin/env bats
# Tests for hug c (git-c) command

load '../test_helper'

setup() {
  enable_gum_for_test
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

  # Verify commit exists
  run git log -1 --format=%s
  assert_output "Empty commit"
}

@test "hug c: commits staged changes with -m" {
  local original_head
  original_head=$(git rev-parse HEAD)

  run hug c -m "Staged commit"
  assert_success
  assert_output --partial "Committing staged file(s) (1):"

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
  refute_output --partial "Committing staged file(s)"
}
@test "hug c: propagates git commit errors" {
  # Attempt commit without message and fake editor failure
  # Save and unset fallback environment variables to ensure consistent behavior
  local saved_git_sequence_editor="${GIT_SEQUENCE_EDITOR:-}"
  local saved_visual="${VISUAL:-}"
  local saved_editor="${EDITOR:-}"
  local saved_git_editor="${GIT_EDITOR:-}"
  unset GIT_SEQUENCE_EDITOR
  unset VISUAL
  unset EDITOR
  
  # Debug: Show environment before test
  echo "# Debug: Environment before test:" >&3
  echo "# GIT_EDITOR=${GIT_EDITOR:-<not set>}" >&3
  echo "# VISUAL=${VISUAL:-<not set>}" >&3
  echo "# EDITOR=${EDITOR:-<not set>}" >&3
  
  # Export GIT_EDITOR before run command (not inline)
  export GIT_EDITOR="false"
  run hug c
  
  # Debug output
  echo "# Exit status: $status" >&3
  echo "# Output:" >&3
  echo "$output" | sed 's/^/# /' >&3
  
  assert_failure
  assert_output --regexp "[Tt]here was a problem with the editor"
  
  # Restore original values (BATS runs tests in subshells, so this is defensive)
  [[ -n "$saved_git_sequence_editor" ]] && export GIT_SEQUENCE_EDITOR="$saved_git_sequence_editor"
  [[ -n "$saved_visual" ]] && export VISUAL="$saved_visual"
  [[ -n "$saved_editor" ]] && export EDITOR="$saved_editor"
  [[ -n "$saved_git_editor" ]] && export GIT_EDITOR="$saved_git_editor"
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
  assert_output --partial "Committing staged file(s)"

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
  refute_output --partial "Committing staged file(s)"  # Quiet suppresses via HUG_QUIET call-site gate

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
  
  # Temporarily unset global git config to ensure test isolation
  # Track existence separately from value to handle empty strings correctly
  local saved_global_name
  local saved_global_email
  local had_global_name=false
  local had_global_email=false
  if git config --global user.name >/dev/null 2>&1; then
    saved_global_name="$(git config --global user.name)"
    had_global_name=true
  fi
  if git config --global user.email >/dev/null 2>&1; then
    saved_global_email="$(git config --global user.email)"
    had_global_email=true
  fi
  git config --global --unset user.name 2>/dev/null || true
  git config --global --unset user.email 2>/dev/null || true
  
  # Debug: Check git config
  echo "# Debug: Git config check:" >&3
  echo "# user.name in repo: $(git config --local user.name 2>&1 || echo '<not set>')" >&3
  echo "# user.email in repo: $(git config --local user.email 2>&1 || echo '<not set>')" >&3
  echo "# user.name global: $(git config --global user.name 2>&1 || echo '<not set>')" >&3
  echo "# user.email global: $(git config --global user.email 2>&1 || echo '<not set>')" >&3
  
  echo "content" > file.txt
  git add file.txt

  run hug c -m "Should fail"
  
  # Debug output
  echo "# Exit status: $status" >&3
  echo "# Output:" >&3
  echo "$output" | sed 's/^/# /' >&3
  
  # Restore global config before assertions (in case they fail)
  if [[ "$had_global_name" == true ]]; then
    git config --global user.name "$saved_global_name"
  fi
  if [[ "$had_global_email" == true ]]; then
    git config --global user.email "$saved_global_email"
  fi
  
  assert_failure
  assert_output --partial "Author identity unknown"

  # Restore original environment values (BATS runs tests in subshells, so this is defensive)
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
  assert_output --partial "Require clean tracked working tree"
  
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
  assert_output --partial "Require clean tracked working tree"
  
  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: tracked-dirty tree still refuses the clean-gate (unified predicate)" {
  local repo
  repo=$(create_test_repo_with_history)
  pushd "$repo" >/dev/null

  # Modify a tracked file to create unstaged tracked changes
  echo "dirty edit" >> feature1.txt

  run hug cmv 1 newbranch --new --force
  assert_failure
  assert_output --partial "Require clean tracked working tree"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: untracked-only tree passes the clean-gate (reset --hard ignores untracked)" {
  local repo
  repo=$(create_test_repo_with_history)
  pushd "$repo" >/dev/null

  # Add an untracked file only — no tracked changes at all
  echo "untracked" > scratch.txt

  run hug cmv 1 newbranch --new --force
  assert_success

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

  # Test declining confirmation
  run bash -c 'echo "n" | hug cmv 1 target-branch'
  assert_failure
  assert_output --partial "📤 moving to target-branch:"
  assert_output --partial "ℹ️ Info: Cancelled."

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

  # Test accepting confirmation (type the action word "move")
  export HUG_DISABLE_GUM=true  # Disable gum to use text-based prompts
  run bash -c 'echo "cmv" | hug cmv 1 existing-target'
  assert_success
  assert_output --partial "1 commit since"

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

  # Test accepting confirmation to create new branch (type action word "move")
  export HUG_DISABLE_GUM=true  # Disable gum to use text-based prompts
  run bash -c 'echo "cmv" | hug cmv 1 prompt-missing'
  assert_success
  assert_output --partial "📊 1 commit since"
  assert_output --partial "📤 moving to prompt-missing (new branch):"

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

  # Test declining confirmation (wrong word typed → cancelled)
  export HUG_DISABLE_GUM=true  # Disable gum to use text-based prompts
  run bash -c 'echo "n" | hug cmv 1 abort-missing'
  assert_failure
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
  assert_output --partial "Invalid commitish"

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

# cmv 0-commit guard: the `count == 0` no-op is CORRECT for cmv (its target must be an
# ancestor — "commit to move above" / "reset branch back" — so a descendant has nothing
# above it). These tests pin BOTH truthful sub-case messages AND the no-regression invariant
# that the current branch never moves: a forward (descendant) target must NOT fall through
# to the tail's `git reset --hard`, which would hard-reset the branch FORWARD + switch branch
# on a 'NOT RESTORABLE' command. The message must branch on is_aligned because a commit is its
# own ancestor (equality-as-ancestry): "already at" when aligned, "is a descendant" otherwise.
@test "hug cmv: aligned target (HEAD) -> 'already at' message, branch unmoved" {
  local repo
  repo=$(create_test_repo_with_history)
  pushd "$repo" >/dev/null

  git checkout -q -b feature
  local before
  before=$(git rev-parse HEAD)

  run env HUG_FORCE=true hug cmv HEAD main
  assert_success
  assert_output --partial "already at"
  refute_output --partial "is a descendant"
  # Current branch did NOT move (guard exits before any reset)
  [ "$(git rev-parse HEAD)" = "$before" ]

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: descendant target -> 'is a descendant of HEAD' message, branch unmoved" {
  local repo
  repo=$(create_test_repo_with_history)
  pushd "$repo" >/dev/null

  git checkout -q -b feature
  # Current HEAD becomes the FORWARD (descendant) target; then move feature back one commit so
  # the target is a descendant of the new HEAD — an incoherent cmv request that must no-op.
  local descendant
  descendant=$(git rev-parse HEAD)
  git reset -q --hard HEAD~1
  local before
  before=$(git rev-parse HEAD)

  run env HUG_FORCE=true hug cmv "$descendant" main
  assert_success
  assert_output --partial "is a descendant of HEAD"
  refute_output --partial "already at"
  # Current branch did NOT move forward (no forward-hard-reset regression)
  [ "$(git rev-parse HEAD)" = "$before" ]

  popd >/dev/null
  rm -rf "$repo"
}

# Additional cmv edge cases...

# -----------------------------------------------------------------------------
# cmv danger-tier migration: -y refusal, -f proceeds, no recovery hint, help
# -----------------------------------------------------------------------------

@test "hug cmv: -y is refused (danger tier, exit 3)" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main
  git checkout -q -b target-branch HEAD~1
  git checkout -q main

  run hug cmv 1 target-branch -y
  [ "$status" -eq 3 ]      # HUG_EX_BLOCKED — danger-tier ops refuse -y
  [ "$status" -ne 0 ]      # backstop: a sourcing-order regression fails noisily, not silently
  assert_output --partial "Dangerous operation requires --force (not -y)"

  # HEAD unchanged (operation didn't proceed)
  run git branch --show-current
  assert_output "main"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: -f proceeds (danger tier skips confirmation)" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main
  git checkout -q -b target-branch HEAD~1
  git checkout -q main

  run hug cmv 1 target-branch -f
  assert_success

  # Now on target-branch (operation completed)
  run git branch --show-current
  assert_output "target-branch"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: no recovery hint emitted on success" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main
  git checkout -q -b target-branch HEAD~1
  git checkout -q main

  run hug cmv 1 target-branch -f
  assert_success
  refute_output --partial "hug h restore"
  refute_output --partial "recover"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: current branch changes after success (reason recovery is incomplete)" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main

  run hug cmv 1 new-branch --new -f
  assert_success

  # Current branch changed from main to new-branch
  run git branch --show-current
  assert_output "new-branch"
  refute_output "main"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: help states not restorable" {
  run hug cmv -h
  assert_output --partial "NOT RESTORABLE"
  assert_output --partial "No single-command recovery exists"
}


# -----------------------------------------------------------------------------
# Post-Commit Push Suggestion Tests
# -----------------------------------------------------------------------------

@test "hug c: suggests bpush after commit on branch with upstream" {
  # Setup repo with upstream
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  pushd "$repo" >/dev/null

  # Make a change and commit
  echo "new content" > newfile.txt
  git add newfile.txt

  run hug c -m "New commit"
  assert_success
  assert_output --partial "Committing staged file(s)"
  # Should suggest bpush since we're on a branch with upstream
  assert_output --partial "Ready to push? Use \"hug bpush\""

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug c: no suggestion when no upstream exists" {
  create_test_repo_with_history

  # Make a change on a branch without upstream
  git checkout -q -b no-upstream-branch
  echo "content" > newfile.txt
  git add newfile.txt

  run hug c -m "Commit without upstream"
  assert_success
  # Should NOT suggest push since there's no upstream
  refute_output --partial "Ready to push? Use"
  refute_output --partial "bpush"

  git checkout -q main 2>/dev/null || git checkout -q master
}

@test "hug c: suggests bpushf after amending pushed commit" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  pushd "$repo" >/dev/null

  # Create and push a commit
  echo "original content" > file.txt
  git add file.txt
  git commit -q -m "Original commit"
  git push -q origin main 2>/dev/null || true

  # Amend the commit to make it diverge from upstream
  echo "amended content" >> file.txt
  git add file.txt

  run hug c --amend --no-edit
  assert_success
  # Should suggest bpushf since commit diverged from upstream
  assert_output --partial "Commit amended. Use \"hug bpushf\" to force-push safely."

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug c: respects HUG_QUIET for suggestions" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  pushd "$repo" >/dev/null

  # Make a change and commit with quiet mode
  echo "new content" > newfile.txt
  git add newfile.txt

  HUG_QUIET=T run hug c -m "New commit"
  assert_success
  # Should NOT suggest anything in quiet mode
  refute_output --partial "Ready to push? Use"
  refute_output --partial "bpush"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug ca: suggests bpush after commit all tracked" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  pushd "$repo" >/dev/null

  # Make unstaged changes
  echo "tracked changes" > tracked.txt
  git add tracked.txt

  run hug ca -m "Commit all tracked"
  assert_success
  # Should suggest bpush since we're on a branch with upstream
  assert_output --partial "Ready to push? Use \"hug bpush\""

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug caa: suggests bpush after commit all" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  pushd "$repo" >/dev/null

  # Make changes (tracked and untracked)
  echo "tracked changes" > tracked.txt
  echo "untracked content" > untracked.txt

  run hug caa -m "Commit everything" --force
  assert_success
  # Should suggest bpush since we're on a branch with upstream
  assert_output --partial "Ready to push? Use \"hug bpush\""

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmod: suggests bpushf after amending pushed commit" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  pushd "$repo" >/dev/null

  # Create and push initial commit
  echo "initial" > amend.txt
  git add amend.txt
  git commit -q -m "Initial"
  git push -q origin main 2>/dev/null || true

  # Stage changes for amend
  echo "amended" >> amend.txt
  git add amend.txt

  run hug cmod --no-edit
  assert_success
  # Should suggest bpushf since we amended a pushed commit
  assert_output --partial "Commit amended. Use \"hug bpushf\" to force-push safely."

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmod: suggests bpush after amending unpushed commit" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  pushd "$repo" >/dev/null

  # Create initial commit (not pushed)
  echo "initial" > amend.txt
  git add amend.txt
  git commit -q -m "Initial"

  # Stage changes for amend
  echo "amended" >> amend.txt
  git add amend.txt

  run hug cmod --no-edit
  assert_success
  # Should suggest bpush (not bpushf) since we haven't pushed yet
  assert_output --partial "Ready to push? Use \"hug bpush\""

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmoda: suggests bpushf after amending pushed commit with all tracked" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  pushd "$repo" >/dev/null

  # Create and push initial commit
  echo "initial" > cma.txt
  git add cma.txt
  git commit -q -m "Initial"
  git push -q origin main 2>/dev/null || true

  # Make unstaged changes
  echo "amended" >> cma.txt

  run hug cmoda --no-edit
  assert_success
  # Should suggest bpushf since we amended a pushed commit
  assert_output --partial "Commit amended. Use \"hug bpushf\" to force-push safely."

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmoda: suggests bpush after amending unpushed commit" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  pushd "$repo" >/dev/null

  # Create initial commit (not pushed)
  echo "initial" > cma.txt
  git add cma.txt
  git commit -q -m "Initial"

  # Make unstaged changes
  echo "amended" >> cma.txt

  run hug cmoda --no-edit
  assert_success
  # Should suggest bpush (not bpushf) since we haven't pushed yet
  assert_output --partial "Ready to push? Use \"hug bpush\""

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug c: no suggestion after commit on new branch without upstream" {
  create_test_repo_with_history

  # Create a new branch without setting upstream
  git checkout -q -b feature-branch

  echo "feature content" > feature.txt
  git add feature.txt

  run hug c -m "Feature commit"
  assert_success
  # Should NOT suggest push since there's no upstream
  refute_output --partial "Ready to push? Use"
  refute_output --partial "bpush"

  git checkout -q main 2>/dev/null || git checkout -q master
}

@test "hug c: neutral diverged message after regular commit on diverged HEAD" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  pushd "$repo" >/dev/null

  # Create and push a commit
  echo "original" > file.txt
  git add file.txt
  git commit -q -m "Original"
  git push -q origin main 2>/dev/null || true

  # Amend to diverge HEAD from upstream
  echo "amended" >> file.txt
  git add file.txt
  git commit -q --amend --no-edit

  # Now do a regular (non-amend) commit — should show neutral message
  echo "new content" > newfile.txt
  git add newfile.txt

  run hug c -m "Regular commit on diverged HEAD"
  assert_success
  assert_output --partial "Local and remote histories differ"
  refute_output --partial "Commit amended"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug caa: shows push suggestion only once" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  pushd "$repo" >/dev/null

  echo "tracked" > tracked.txt
  echo "untracked" > untracked.txt

  run hug caa -m "Commit all" --force
  assert_success
  # Count occurrences of push suggestion — should be exactly 1
  local count
  count=$(echo "$output" | grep -c "Ready to push")
  [[ "$count" -eq 1 ]]

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug c: shows amended message with explicit --amend on diverged HEAD" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  pushd "$repo" >/dev/null

  # Create and push a commit
  echo "original" > file.txt
  git add file.txt
  git commit -q -m "Original"
  git push -q origin main 2>/dev/null || true

  # Amend to diverge HEAD from upstream
  echo "amended" >> file.txt
  git add file.txt

  run hug c --amend --no-edit
  assert_success
  assert_output --partial "Commit amended. Use \"hug bpushf\" to force-push safely."

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug ca: detects --amend and shows amended message on diverged HEAD" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  pushd "$repo" >/dev/null

  # Create and push a commit
  echo "original" > file.txt
  git add file.txt
  git commit -q -m "Original"
  git push -q origin main 2>/dev/null || true

  # Amend via ca --amend
  echo "amended" >> file.txt

  run hug ca --amend --no-edit
  assert_success
  assert_output --partial "Commit amended. Use \"hug bpushf\" to force-push safely."

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug caa: detects --amend and shows amended message" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  pushd "$repo" >/dev/null

  # Create and push a commit
  echo "original" > file.txt
  git add file.txt
  git commit -q -m "Original"
  git push -q origin main 2>/dev/null || true

  # Amend via caa --amend --no-edit --force
  echo "amended" >> file.txt

  run hug caa --amend --no-edit --force
  assert_success
  # Should show amended message exactly once
  local count
  count=$(echo "$output" | grep -c "Commit amended")
  [[ "$count" -eq 1 ]]

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug c: respects HUG_QUIET=T via --quiet flag" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  pushd "$repo" >/dev/null

  echo "new content" > newfile.txt
  git add newfile.txt

  # --quiet sets HUG_QUIET=T via parse_common_flags
  run hug c --quiet -m "Quiet commit"
  assert_success
  refute_output --partial "Ready to push? Use"
  refute_output --partial "bpush"

  popd >/dev/null
  rm -rf "$repo"
}

# -----------------------------------------------------------------------------
# Pre-commit staged-file preview tests (#207)
# -----------------------------------------------------------------------------

@test "hug c: pre-commit preview shows staged file name on stderr" {
  # setup() stages staged.txt via create_test_repo_with_changes — unstage
  # it first so we control exactly what's in the index for this test.
  git restore --staged staged.txt
  echo "stage me" > preview_one.txt
  hug a preview_one.txt
  run hug c -m "preview test"
  assert_success
  assert_output --partial "Committing staged file(s) (1):"
  assert_output --partial "preview_one.txt"
}

@test "hug c: preview caps at 10 with overflow marker" {
  # setup() stages staged.txt — unstage it first.
  git restore --staged staged.txt
  # Stage 12 files. Use ZERO-PADDED names so lexical order matches numeric
  # order — `capfile_10.txt` lexically sorts BEFORE `capfile_2.txt` without
  # padding, which would make the cap-test assertions nondeterministic.
  for i in $(seq -w 1 12); do
    echo "content $i" > "capfile_${i}.txt"
  done
  hug a capfile_*.txt
  # Capture stderr separately to verify the cap without git's stdout noise.
  # BATS `run` merges streams, so we use file-redirection here.
  local _out _err
  _out=$(mktemp)
  _err=$(mktemp)
  hug c -m "cap test" >"$_out" 2>"$_err"
  local _exit=$?
  # stderr must show total count (12) and the overflow marker
  grep -q "Committing staged file(s) (12):" "$_err"
  grep -q "capfile_01.txt" "$_err"
  grep -q "capfile_10.txt" "$_err"
  grep -q "... (+2 more — run 'hug sls' for the full list)" "$_err"
  # The 11th and 12th files must NOT appear in the stderr preview
  # shellcheck disable=SC2314  # ! before grep is intentional negative assertion
  ! grep -q "capfile_11.txt" "$_err"
  # shellcheck disable=SC2314
  ! grep -q "capfile_12.txt" "$_err"
  # stdout (git's commit output) contains all 12 files — that's expected.
  grep -q "12 files changed" "$_out"
  [[ $_exit -eq 0 ]]
  rm -f "$_out" "$_err"
}

@test "hug c: --allow-empty with no staged files skips preview" {
  # setup() stages staged.txt — unstage it first.
  git restore --staged staged.txt
  run hug c --allow-empty -m "empty"
  assert_success
  refute_output --partial "Committing staged file(s)"
}

@test "hug c: --quiet suppresses the preview (HUG_QUIET contract)" {
  # setup() stages staged.txt — unstage it first.
  git restore --staged staged.txt
  echo "quiet test" > quiet_preview.txt
  hug a quiet_preview.txt
  run hug c -m "quiet preview" --quiet
  assert_success
  refute_output --partial "Committing staged file(s)"
}

@test "hug c: preview goes to stderr, git output to stdout" {
  # Use the file-redirection pattern — `run` merges streams.
  # Stage one file, then capture stdout and stderr separately.
  # setup() stages staged.txt — unstage it first.
  git restore --staged staged.txt
  echo "stream test" > stream_test.txt
  hug a stream_test.txt
  local _out _err
  _out=$(mktemp)
  _err=$(mktemp)
  hug c -m "stream test" >"$_out" 2>"$_err"
  # stdout must NOT contain the preview header or the staged filename
  # shellcheck disable=SC2314  # ! before grep is intentional negative assertion
  ! grep -q "Committing staged file(s)" "$_out"
  # shellcheck disable=SC2314
  ! grep -q "stream_test.txt" "$_out"
  # stderr MUST contain the preview header and the staged filename
  grep -q "Committing staged file(s)" "$_err"
  grep -q "stream_test.txt" "$_err"
  rm -f "$_out" "$_err"
}
