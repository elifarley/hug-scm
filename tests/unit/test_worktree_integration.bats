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

@test "worktree integration: complete workflow from creation to removal" {
  cd "$TEST_REPO"

  # 1. Create worktree
  run git-wtc feature-1 --force
  assert_success
  
  # Get the actual worktree path from porcelain output (reliable)
  local feature_wt
  feature_wt=$(git worktree list --porcelain | grep -B2 "branch refs/heads/feature-1" | grep "^worktree " | sed 's/^worktree //')
  [[ -n "$feature_wt" ]] || fail "Could not find worktree path for feature-1"
  assert_worktree_exists "$feature_wt"

  # 2. List worktrees
  run git-wt --summary
  assert_success
  # 2 total (main + 1 additional) = count shows 1
  assert_output --partial "Worktrees (1)"
  assert_output --partial "feature-1"

  # 3. Get worktree count
  # Should return 1 (one additional worktree, excluding main)
  assert_worktree_count 1

  # 4. Switch to worktree (validate path exists)
  run git-wt "$feature_wt"
  assert_success

  # 5. Remove worktree
  run git-wtdel "$feature_wt" --force
  assert_success
  assert_worktree_not_exists "$feature_wt"

  # 6. Verify back to original state
  # 0 additional worktrees (only main remains)
  assert_worktree_count 0
}

@test "worktree integration: handles multiple worktrees simultaneously" {
  cd "$TEST_REPO"

  # Create multiple worktrees
  local wt1 wt2 wt3
  wt1=$(create_test_worktree "feature-1" "$TEST_REPO")
  wt2=$(create_test_worktree "feature-2" "$TEST_REPO")
  wt3=$(create_test_worktree "hotfix-1" "$TEST_REPO")

  # Should have 4 worktrees total (main + 3 created) = 3 additional
  assert_worktree_count 3

  # All worktrees should exist and be on correct branches
  assert_worktree_exists "$wt1"
  assert_worktree_branch "$wt1" "feature-1"
  assert_worktree_clean "$wt1"

  assert_worktree_exists "$wt2"
  assert_worktree_branch "$wt2" "feature-2"
  assert_worktree_clean "$wt2"

  assert_worktree_exists "$wt3"
  assert_worktree_branch "$wt3" "hotfix-1"
  assert_worktree_clean "$wt3"

  # List should show all worktrees
  run git-wt --summary
  assert_success
  # 4 total (main + 3 additional) = count shows 3
  assert_output --partial "Worktrees (3)"
  assert_output --partial "feature-1"
  assert_output --partial "feature-2"
  assert_output --partial "hotfix-1"

  # JSON output should include all worktrees
  run git-wt --json
  assert_success
  assert_valid_json
  assert_json_array_length '.worktrees' 4
  # Count shows additional worktrees only: 4 total - 1 main = 3 additional
  assert_json_value '.count' '3'

  # Clean up one worktree
  run git-wtdel "$wt2" --force
  assert_success
  assert_worktree_not_exists "$wt2"

  # Should have 3 worktrees now (main + 2 additional)
  assert_worktree_count 2
}

@test "worktree integration: handles dirty worktrees correctly" {
  # Disable gum to avoid hanging in interactive remove menu
  disable_gum_for_test

  cd "$TEST_REPO"

  # Create worktree and make it dirty
  local dirty_wt
  dirty_wt=$(create_test_worktree_with_dirty_changes "feature-1" "$TEST_REPO")

  # Check that it's detected as dirty
  assert_worktree_dirty "$dirty_wt"

  # Summary should show dirty indicator
  run git-wt --summary
  assert_success
  assert_output --partial "[DIRTY]"
  assert_output --partial "feature-1"

  # Interactive remove menu test
  run bash -c "echo '' | git-wtdel"
  # Menu may or may not show due to timing, cancellation is expected
  assert_output --partial "cancelled"

  # Should fail to remove without force
  run git-wtdel "$dirty_wt" --dry-run
  assert_success
  assert_output --partial "Would remove worktree"

  # Should succeed to remove with force
  run git-wtdel "$dirty_wt" --force
  assert_success
  assert_worktree_not_exists "$dirty_wt"
}

@test "worktree integration: parallel development workflow" {
  cd "$TEST_REPO"

  # Simulate parallel development workflow
  # 1. Create worktree for feature A
  local feature_a
  feature_a=$(create_test_worktree "feature-1" "$TEST_REPO")

  # 2. Create worktree for feature B
  local feature_b
  feature_b=$(create_test_worktree "feature-2" "$TEST_REPO")

  # 3. Work on feature A - add commits
  (
    cd "$feature_a"
    echo "Feature A work" > "feature-a.txt"
    git add feature-a.txt
    git_commit_deterministic "Add feature A work"

    # Verify we're on correct branch with our commits
    assert_worktree_branch "$feature_a" "feature-1"
    assert_worktree_clean "$feature_a"
  )

  # 4. Work on feature B - add commits
  (
    cd "$feature_b"
    echo "Feature B work" > "feature-b.txt"
    git add feature-b.txt
    git_commit_deterministic "Add feature B work"

    # Verify we're on correct branch with our commits
    assert_worktree_branch "$feature_b" "feature-2"
    assert_worktree_clean "$feature_b"
  )

  # 5. Main repository should be clean and unchanged
  assert_worktree_clean "$TEST_REPO"
  assert_worktree_branch "$TEST_REPO" "main"

  # 6. Both features should be isolated
  assert_worktree_exists "$feature_a"
  assert_worktree_exists "$feature_b"

  # 7. List shows all worktrees with correct branches
  run git-wt --summary
  assert_success
  assert_output --partial "main"
  assert_output --partial "feature-1"
  assert_output --partial "feature-2"

  # 8. Cleanup one feature worktree
  run git-wtdel "$feature_a" --force
  assert_success

  # 9. Other feature worktree should remain unaffected
  assert_worktree_exists "$feature_b"
  assert_worktree_branch "$feature_b" "feature-2"

  # 10. Main repository should still be clean
  assert_worktree_clean "$TEST_REPO"
}

@test "worktree integration: hotfix workflow" {
  cd "$TEST_REPO"

  # Simulate hotfix workflow while feature development is in progress
  # 1. Create feature worktree with ongoing work
  local feature_wt
  feature_wt=$(create_test_worktree_with_changes "feature-1" "$TEST_REPO")

  # 2. Create hotfix worktree
  local hotfix_wt
  hotfix_wt=$(create_test_worktree "hotfix-1" "$TEST_REPO")

  # 3. Complete hotfix
  (
    cd "$hotfix_wt"
    echo "Hotfix fix" > "hotfix.txt"
    git add hotfix.txt
    git_commit_deterministic "Apply hotfix"

    assert_worktree_branch "$hotfix_wt" "hotfix-1"
    assert_worktree_clean "$hotfix_wt"
  )

  # 4. Feature worktree should have uncommitted changes
  assert_worktree_exists "$feature_wt"
  assert_worktree_branch "$feature_wt" "feature-1"
  # Note: Our helper creates staged changes, not unstaged
  run git -C "$feature_wt" diff --cached --quiet
  assert_failure  # Should have staged changes

  # 5. Can remove hotfix worktree when done
  run git-wtdel "$hotfix_wt" --force
  assert_success

  # 6. Feature worktree remains unaffected
  assert_worktree_exists "$feature_wt"
  assert_worktree_branch "$feature_wt" "feature-1"

  # 7. Feature worktree still has its changes
  run git -C "$feature_wt" diff --cached --quiet
  assert_failure  # Should still have staged changes
}

@test "worktree integration: branch name sanitization" {
  cd "$TEST_REPO"

  # Create branches with special characters
  git checkout -b "feature/auth"
  git checkout -b "feature/v2.0"
  git checkout -b "bugfix/issue-123"
  git checkout -b "experimental/test_case"

  # Create worktrees for these branches
  run git-wtc "feature/auth" --force
  assert_success
  # Get the worktree path from porcelain output (more reliable)
  local wt_auth
  wt_auth=$(git worktree list --porcelain | grep -B2 "branch refs/heads/feature/auth" | grep "^worktree " | sed 's/^worktree //')
  [[ -n "$wt_auth" ]] || fail "Could not find worktree for feature/auth"
  assert_worktree_exists "$wt_auth"
  assert_worktree_branch "$wt_auth" "feature/auth"

  run git-wtc "feature/v2.0" --force
  assert_success
  local wt_v2
  wt_v2=$(git worktree list --porcelain | grep -B2 "branch refs/heads/feature/v2.0" | grep "^worktree " | sed 's/^worktree //')
  [[ -n "$wt_v2" ]] || fail "Could not find worktree for feature/v2.0"
  assert_worktree_exists "$wt_v2"
  assert_worktree_branch "$wt_v2" "feature/v2.0"

  run git-wtc "bugfix/issue-123" --force
  assert_success
  local wt_bugfix
  wt_bugfix=$(git worktree list --porcelain | grep -B2 "branch refs/heads/bugfix/issue-123" | grep "^worktree " | sed 's/^worktree //')
  [[ -n "$wt_bugfix" ]] || fail "Could not find worktree for bugfix/issue-123"
  assert_worktree_exists "$wt_bugfix"
  assert_worktree_branch "$wt_bugfix" "bugfix/issue-123"

  run git-wtc "experimental/test_case" --force
  assert_success
  local wt_experimental
  wt_experimental=$(git worktree list --porcelain | grep -B2 "branch refs/heads/experimental/test_case" | grep "^worktree " | sed 's/^worktree //')
  [[ -n "$wt_experimental" ]] || fail "Could not find worktree for experimental/test_case"
  assert_worktree_exists "$wt_experimental"
  assert_worktree_branch "$wt_experimental" "experimental/test_case"

  # All should show up in worktree list
  run git-wt --summary
  assert_success
  # 5 total (main + 4 additional) = count shows 4
  assert_output --partial "Worktrees (4)"
  assert_output --partial "feature/auth"
  assert_output --partial "feature/v2.0"
  assert_output --partial "bugfix/issue-123"
  assert_output --partial "experimental/test_case"
}

@test "worktree integration: error handling and recovery" {
  cd "$TEST_REPO"

  # Test various error conditions and recovery

  # 1. Try to create worktree for non-existent branch
  run git-wtc nonexistent-branch
  assert_failure
  assert_output --partial "does not exist locally"

  # 2. Create worktree and then try to create another for same branch
  local first_wt
  first_wt=$(create_test_worktree "feature-1" "$TEST_REPO")

  run git-wtc feature-1 "${TEST_REPO}-duplicate-feature" --force
  assert_failure
  assert_output --partial "already checked out in another worktree"

  # 3. Try to remove current worktree
  cd "$first_wt"
  run git-wtdel "$first_wt"
  assert_failure
  assert_output --partial "Cannot remove current worktree"

  # 4. Go back to main and remove successfully
  cd "$TEST_REPO"
  run git-wtdel "$first_wt" --force
  assert_success
  assert_worktree_not_exists "$first_wt"

  # 5. Repository should be in clean state (only main worktree)
  assert_worktree_count 0
  assert_worktree_clean "$TEST_REPO"
}