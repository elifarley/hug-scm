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
  assert_output --partial "hug wtc: Create worktree for existing branch"
}

@test "hug wtc: creates worktree for existing branch" {
  # Test creating worktree for feature-1 branch with force flag to skip confirmation
  run git-wtc feature-1 -f
  assert_success

  # Extract path from output and resolve it to remove ../
  local worktree_path
  worktree_path=$(echo "$output" | grep "Path:" | sed 's/.*Path: //' | sed 's/\s*$//')
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
  assert_output --partial "Path: $custom_path"

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
  assert_output --partial "Mode: DRY RUN"
  assert_output --partial "Would create worktree for branch 'feature-1'"

  # Verify no worktree was actually created
  local worktree_path
  worktree_path=$(echo "$output" | grep "Path:" | sed 's/.*Path: //' | sed 's/\s*$//')
  worktree_path="$(cd "$(dirname "$worktree_path")" && pwd)/$(basename "$worktree_path")"

  # The worktree should NOT exist in dry run mode
  assert_dir_not_exists "$worktree_path"
}

@test "hug wtc: error when branch does not exist" {
  # Test with non-existent branch
  run git-wtc non-existent-branch -f
  assert_failure

  # Should show appropriate error message
  assert_output --partial "does not exist locally"
  assert_output --partial "Create it first with"
}

@test "hug wtc: interactive mode with no branch argument" {
  # Disable gum to avoid hanging in interactive branch selection
  disable_gum_for_test

  # Test interactive mode (no arguments)
  run git-wtc
  assert_failure  # Exits with code 1 due to cancellation

  # Should show cancellation message since no interactive selection possible
  assert_output --partial "Cancelled"
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

@test "hug wtc: resolves path conflicts automatically" {
  # Create a directory at the default path location to force a conflict
  local default_path="${TEST_REPO}-worktrees/feature-2"
  mkdir -p "$default_path"
  echo "existing file" > "$default_path/existing.txt"

  # Create worktree for feature-2 - should handle the path conflict
  run git-wtc feature-2 -f
  assert_success

  # Extract the actual path used
  local worktree_path
  worktree_path=$(echo "$output" | grep "Path:" | sed 's/.*Path: //' | sed 's/\s*$//')
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
  # Disable gum to avoid hanging in interactive branch selection
  disable_gum_for_test

  # Test interactive mode with explicit -- flag
  run git-wtc --
  assert_failure  # Exits with code 1 due to cancellation

  # Should show cancellation message since no interactive selection possible
  assert_output --partial "Cancelled"
}

@test "hug wtc: creates worktree for main branch" {
  # Test creating worktree for main branch with force flag to skip confirmation
  run git-wtc main -f
  assert_success

  # Extract path from output and resolve it to remove ../
  local worktree_path
  worktree_path=$(echo "$output" | grep "Path:" | sed 's/.*Path: //' | sed 's/\s*$//')
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
  worktree_path=$(echo "$output" | grep "Path:" | sed 's/.*Path: //' | sed 's/\s*$//')
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
  # Test using both --dry-run and -f flags together
  run git-wtc feature-1 --dry-run -f
  assert_success
  assert_output --partial "Mode: DRY RUN"
  assert_output --partial "Would create worktree for branch 'feature-1'"

  # Extract path from output and verify no worktree was actually created
  local worktree_path
  worktree_path=$(echo "$output" | grep "Path:" | sed 's/.*Path: //' | sed 's/\s*$//')
  worktree_path="$(cd "$(dirname "$worktree_path")" && pwd)/$(basename "$worktree_path")"

  # The worktree should NOT exist in dry run mode
  assert_dir_not_exists "$worktree_path"
}

@test "hug wtc: creates worktree with relative custom path" {
  # Create a worktree using a relative path
  run git-wtc main ../relative-main-worktree -f
  assert_success

  # Extract path from output - it should be resolved to absolute path
  local worktree_path
  worktree_path=$(echo "$output" | grep "Path:" | sed 's/.*Path: //' | sed 's/\s*$//')

  # Path should be absolute (no relative components)
  [[ "$worktree_path" = /* ]] || fail "Worktree path should be absolute: $worktree_path"

  # Resolve path for verification
  worktree_path="$(cd "$(dirname "$worktree_path")" && pwd)/$(basename "$worktree_path")"

  # Verify worktree was created at the correct location
  assert_worktree_exists "$worktree_path"

  # Verify worktree is on correct branch
  cd "$worktree_path"
  assert_git_clean
  assert_equal "$(git branch --show-current)" "main"
}

@test "hug wtc: comprehensive workflow test" {
  # Create multiple worktrees for different branches and verify they coexist
  local worktree_paths=()

  # Create worktree for feature/branch with custom path outside repository
  run git-wtc feature/branch "${TEST_REPO}-custom-feature" -f
  assert_success
  local path1
  path1=$(echo "$output" | grep "Path:" | sed 's/.*Path: //' | sed 's/\s*$//')
  worktree_paths+=("$path1")

  # Create worktree for hotfix-1 with auto-generated path
  run git-wtc hotfix-1 -f
  assert_success
  local path2
  path2=$(echo "$output" | grep "Path:" | sed 's/.*Path: //' | sed 's/\s*$//')
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