#!/usr/bin/env bats

setup() {
  load '../test_helper'

  # Create a test repository with branches
  TEST_REPO=$(create_test_repo_with_branches)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_worktrees "$TEST_REPO"
  cleanup_test_repo "$TEST_REPO"
}

@test "hug wtc: shows help when --help flag is used" {
  run git-wtc --help
  assert_success
  assert_output --partial "hug wtc: Create worktree for existing or new branch"
}

@test "hug wtc: creates worktree for existing branch" {
  # Test creating worktree for feature-1 branch with force flag to skip confirmation
  run git-wtc feature-1 -f
  assert_success

  # Extract path from output and resolve it to remove ../
  local worktree_path
  worktree_path=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  worktree_path="$(cd "$(dirname "$worktree_path")" && pwd)/$(basename "$worktree_path")"

  # Verify worktree was created
  assert_worktree_exists "$worktree_path"

  # Verify worktree is on correct branch
  cd "$worktree_path"
  assert_git_clean
  assert_equal "$(git branch --show-current)" "feature-1"

  # Verify worktree contains expected file from feature-1 branch
  assert_file_exists "feature1.txt"
}

@test "hug wtc: creates worktree at custom path" {
  # Create a custom directory for worktree
  local custom_path="${TEST_REPO}-custom-feature2"
  mkdir -p "$(dirname "$custom_path")"

  # Test creating worktree with custom path
  run git-wtc feature-2 "$custom_path" -f
  assert_success
  assert_output --partial "$custom_path"

  # Verify worktree was created at custom path
  assert_worktree_exists "$custom_path"

  # Verify worktree is on correct branch
  cd "$custom_path"
  assert_git_clean
  assert_equal "$(git branch --show-current)" "feature-2"

  # Verify worktree contains expected file from feature-2 branch
  assert_file_exists "feature2.txt"
}

@test "hug wtc: dry run mode shows what would be done" {
  # Test dry run mode
  run git-wtc feature-1 --dry-run
  assert_success
  assert_output --partial "Worktree Creation Preview (DRY RUN)"
  assert_output --partial "No changes made (dry run)"

  # Verify no worktree was actually created
  local worktree_path
  worktree_path=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  worktree_path="$(cd "$(dirname "$worktree_path")" && pwd)/$(basename "$worktree_path")"

  # The worktree should NOT exist in dry run mode
  assert_dir_not_exists "$worktree_path"
}

@test "hug wtc: creates new branch with --new flag" {
  # Test creating new branch and worktree with --new flag
  run git-wtc brand-new-branch --new -f
  assert_success

  # Should show branch creation message
  assert_output --partial "Created branch 'brand-new-branch'"

  # Extract path from output and verify worktree exists
  local worktree_path
  worktree_path=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  worktree_path="$(cd "$(dirname "$worktree_path")" && pwd)/$(basename "$worktree_path")"

  # Verify worktree was created
  assert_worktree_exists "$worktree_path"

  # Verify worktree is on correct branch
  cd "$worktree_path"
  assert_equal "$(git branch --show-current)" "brand-new-branch"
}

@test "hug wtc: prompts to create branch without --new flag" {
  # Test with non-existent branch without --new flag
  run bash -c "export HUG_DISABLE_GUM=true HUG_TEST_MODE=true; echo 'n' | git-wtc another-missing-branch 2>&1"
  assert_failure

  # Should show prompt about branch creation
  assert_output --partial "does not exist locally"
  assert_output --partial "Create branch"
  assert_output --partial "and its worktree"
}

@test "hug wtc: auto-creates branch with --force flag" {
  # Test that --force also auto-creates branches (without --dry-run)
  run git-wtc force-created-branch -f
  assert_success

  # Should show branch creation and success messages
  assert_output --partial "Created branch 'force-created-branch'"
  assert_output --partial "Worktree created for 'force-created-branch'"
  assert_output --partial "To start working:"
}

@test "hug wtc: error when using --force and --dry-run together" {
  # Test that --force and --dry-run are mutually exclusive
  run git-wtc test-branch -f --dry-run
  assert_failure
  assert_output --partial "Cannot use --force and --dry-run together"
}

@test "hug wtc: interactive mode with no branch argument" {
  # Test interactive mode with EOF simulation to prevent hanging
  # This works in both gum and non-gum environments
  run bash -c "echo | git-wtc 2>&1"
  assert_failure  # Exits with code 1 due to cancellation

  # Should show cancellation message since no interactive selection possible
  assert_output --partial "cancelled"
}

@test "hug wtc: error when branch already has worktree" {
  # First, create a worktree for feature-1
  run git-wtc feature-1 -f
  assert_success

  # Try to create another worktree for the same branch - should fail
  run git-wtc feature-1 -f
  assert_failure

  # Should show appropriate error message
  assert_output --partial "already checked out in another worktree"
}

@test "hug wtc: dry-run with --new does NOT create branch (bug fix)" {
  # This was a bug: dry-run would actually create the branch
  run git-wtc brand-new-dry-run --new --dry-run
  assert_success
  assert_output --partial "Worktree Creation Preview (DRY RUN)"
  assert_output --partial "new, from HEAD"
  assert_output --partial "No changes made (dry run)"

  # CRITICAL: Verify the branch was NOT created
  run git rev-parse --verify "refs/heads/brand-new-dry-run"
  assert_failure
}

@test "hug wtc: shows post-creation tip with cd command" {
  run git-wtc feature-1 -f
  assert_success
  assert_output --partial "Worktree created for"
  assert_output --partial "To start working:"
  assert_output --partial "cd "
}

@test "hug wtc: rollback branch on worktree creation failure" {
  # Create a path inside the main repo to force worktree creation failure
  local bad_path="${TEST_REPO}/inside-repo-worktree"

  run git-wtc rollback-test-branch "$bad_path" --new -f
  assert_failure

  # Verify the branch was rolled back (cleaned up)
  run git rev-parse --verify "refs/heads/rollback-test-branch"
  assert_failure
}

@test "hug wtc: shows git error details on failure (not suppressed)" {
  # First create a worktree for feature-1
  run git-wtc feature-1 -f
  assert_success

  # Try to create another worktree for the same branch
  run git-wtc feature-1 -f
  assert_failure

  # Error should contain useful information (not just "Failed to create worktree")
  assert_output --partial "already checked out"
}

@test "hug wtc: single confirmation for new branch (not double prompt)" {
  # When declining, should only see ONE prompt, not two
  run bash -c "export HUG_DISABLE_GUM=true HUG_TEST_MODE=true; echo 'n' | git-wtc single-prompt-test 2>&1"
  assert_failure

  # Should show the branch doesn't exist info
  assert_output --partial "does not exist locally"

  # Should show combined prompt (branch + worktree in one)
  assert_output --partial "Create branch"
  assert_output --partial "and its worktree"

  # The branch should NOT have been created
  run git rev-parse --verify "refs/heads/single-prompt-test"
  assert_failure
}

@test "hug wtc: resolves path conflicts automatically" {
  # Create a directory at the default path location to force a conflict
  local default_path="${TEST_REPO}.WT.feature-2"
  mkdir -p "$default_path"
  echo "existing file" > "$default_path/existing.txt"

  # Create worktree for feature-2 - should handle the path conflict
  run git-wtc feature-2 -f
  assert_success

  # Extract the actual path used
  local worktree_path
  worktree_path=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  worktree_path="$(cd "$(dirname "$worktree_path")" && pwd)/$(basename "$worktree_path")"

  # Worktree should exist at the generated path
  assert_worktree_exists "$worktree_path"

  # The generated path should be different from the blocked default path
  local expected_default_path
  expected_default_path="$(cd "$(dirname "$default_path")" && pwd)/$(basename "$default_path")"
  assert_not_equal "$worktree_path" "$expected_default_path"

  # Original directory should remain unchanged
  assert_file_exists "$default_path/existing.txt"
  assert_dir_exists "$default_path"
}

@test "hug wtc: error with too many arguments" {
  # Test with too many arguments - should fail
  run git-wtc feature-1 extra-path another-arg
  assert_failure

  # Should show appropriate error message
  assert_output --partial "Too many arguments"
  assert_output --partial "Usage: hug wtc [branch] [path]"
}

@test "hug wtc: interactive mode with explicit -- flag" {
  # Test interactive mode with explicit -- flag using EOF simulation
  # This works in both gum and non-gum environments
  run bash -c "echo | git-wtc -- 2>&1"
  assert_failure  # Exits with code 1 due to cancellation

  # Should show cancellation message since no interactive selection possible
  assert_output --partial "cancelled"
}

@test "hug wtc: creates worktree for main branch" {
  # Switch off main so we can create a worktree for it
  git checkout -q feature-1

  # Test creating worktree for main branch with force flag to skip confirmation
  run git-wtc main -f
  assert_success

  # Extract path from output and resolve it to remove ../
  local worktree_path
  worktree_path=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  worktree_path="$(cd "$(dirname "$worktree_path")" && pwd)/$(basename "$worktree_path")"

  # Verify worktree was created
  assert_worktree_exists "$worktree_path"

  # Verify worktree is on correct branch
  cd "$worktree_path"
  assert_git_clean
  assert_equal "$(git branch --show-current)" "main"

  # Verify worktree contains expected files from main branch
  assert_file_exists "main_extra.txt"
}

@test "hug wtc: error with invalid option" {
  # Test with invalid option - should fail
  run git-wtc --invalid-option
  assert_failure

  # Should show appropriate error message from getopt
  assert_output --partial "unrecognized option"
}

@test "hug wtc: creates worktree for hotfix branch" {
  # Test creating worktree for hotfix-1 branch with force flag to skip confirmation
  run git-wtc hotfix-1 -f
  assert_success

  # Extract path from output and resolve it to remove ../
  local worktree_path
  worktree_path=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  worktree_path="$(cd "$(dirname "$worktree_path")" && pwd)/$(basename "$worktree_path")"

  # Verify worktree was created
  assert_worktree_exists "$worktree_path"

  # Verify worktree is on correct branch
  cd "$worktree_path"
  assert_git_clean
  assert_equal "$(git branch --show-current)" "hotfix-1"

  # Verify worktree contains expected file from hotfix-1 branch
  assert_file_exists "hotfix1.txt"
}

@test "hug wtc: combined flag usage" {
  # Test using --dry-run flag alone (no longer supports combining with -f)
  run git-wtc feature-1 --dry-run
  assert_success
  assert_output --partial "Worktree Creation Preview (DRY RUN)"
  assert_output --partial "No changes made (dry run)"

  # Extract path from output and verify no worktree was actually created
  local worktree_path
  worktree_path=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  worktree_path="$(cd "$(dirname "$worktree_path")" && pwd)/$(basename "$worktree_path")"

  # The worktree should NOT exist in dry run mode
  assert_dir_not_exists "$worktree_path"
}

@test "hug wtc: creates worktree with relative custom path" {
  # Create a worktree using a relative path (use feature-2, not main which is checked out)
  run git-wtc feature-2 ../relative-feature2-worktree -f
  assert_success

  # Extract path from output - it should be resolved to absolute path
  local worktree_path
  worktree_path=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')

  # Path should be absolute (no relative components)
  [[ "$worktree_path" = /* ]] || fail "Worktree path should be absolute: $worktree_path"

  # Resolve path for verification
  worktree_path="$(cd "$(dirname "$worktree_path")" && pwd)/$(basename "$worktree_path")"

  # Verify worktree was created at the correct location
  assert_worktree_exists "$worktree_path"

  # Verify worktree is on correct branch
  cd "$worktree_path"
  assert_git_clean
  assert_equal "$(git branch --show-current)" "feature-2"
}

@test "hug wtc: comprehensive workflow test" {
  # Create multiple worktrees for different branches and verify they coexist
  local worktree_paths=()

  # Create worktree for feature/branch with custom path outside repository
  run git-wtc feature/branch "${TEST_REPO}-custom-feature" -f
  assert_success
  local path1
  path1=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  worktree_paths+=("$path1")

  # Create worktree for hotfix-1 with auto-generated path
  run git-wtc hotfix-1 -f
  assert_success
  local path2
  path2=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  worktree_paths+=("$path2")

  # Verify all worktrees exist and are valid
  for wp in "${worktree_paths[@]}"; do
    local resolved_path
    resolved_path="$(cd "$(dirname "$wp")" && pwd)/$(basename "$wp")"
    assert_worktree_exists "$resolved_path"
  done

  # Test first worktree (feature/branch)
  cd "$(cd "$(dirname "${worktree_paths[0]}")" && pwd)/$(basename "${worktree_paths[0]}")"
  assert_equal "$(git branch --show-current)" "feature/branch"
  assert_file_exists "feature.txt"

  # Test second worktree (hotfix-1)
  cd "$(cd "$(dirname "${worktree_paths[1]}")" && pwd)/$(basename "${worktree_paths[1]}")"
  assert_equal "$(git branch --show-current)" "hotfix-1"
  assert_file_exists "hotfix1.txt"

  # Test error when trying to create worktree for branch that already has one
  run git-wtc feature/branch -f
  assert_failure
  assert_output --partial "already checked out in another worktree"
}

@test "hug wtc: error when branch is checked out in main worktree without -f" {
  # main is the currently checked out branch in the test repo
  run git-wtc main
  assert_failure
  assert_output --partial "currently checked out in the main worktree"
  assert_output --partial "--force"
}

@test "hug wtc: succeeds with -f for branch checked out in main worktree" {
  # main is checked out, but -f should override
  run git-wtc main -f
  assert_success
  assert_output --partial "Worktree created for"

  # Verify worktree was created
  local worktree_path
  worktree_path=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  worktree_path="$(cd "$(dirname "$worktree_path")" && pwd)/$(basename "$worktree_path")"
  assert_worktree_exists "$worktree_path"
}