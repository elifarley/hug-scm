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
