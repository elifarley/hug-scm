#!/usr/bin/env bats

load '../test_helper'
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-output'
load '../../git-config/lib/hug-git-worktree'

setup() {
  require_worktree_support
  
  # Create a test repository with branches
  TEST_REPO=$(create_test_repo_with_branches)
  
  # Use pushd for automatic directory management
  pushd "$TEST_REPO" > /dev/null
}

teardown() {
  # CRITICAL: Exit directory BEFORE cleanup to prevent getcwd errors
  popd > /dev/null 2>&1 || cd /tmp
  
  # Cleanup worktrees first, then repo
  cleanup_test_worktrees "$TEST_REPO"
  cleanup_test_repo
}

@test "hug-git-worktree: get_worktrees returns empty when no worktrees exist" {
  declare -a worktree_paths=() branches=() commits=() status_dirty=() locked_status=()

  # get_worktrees returns 1 when no additional worktrees exist (only main repo)
  # This is expected behavior - function returns failure with empty arrays
  run get_worktrees worktree_paths branches commits status_dirty locked_status
  
  # Should return failure (exit 1) when no additional worktrees
  assert_failure
  
  # Arrays should still be empty
  assert_equal "${#worktree_paths[@]}" 0
  assert_equal "${#branches[@]}" 0
  assert_equal "${#commits[@]}" 0
  assert_equal "${#status_dirty[@]}" 0
  assert_equal "${#locked_status[@]}" 0
}

@test "hug-git-worktree: get_worktrees returns all worktrees when they exist" {
  # Create worktrees
  local feature_wt
  feature_wt=$(create_test_worktree "feature-1" "$TEST_REPO")

  declare -a worktree_paths=() branches=() commits=() status_dirty=() locked_status=()

  get_worktrees worktree_paths branches commits status_dirty locked_status

  assert_equal "${#worktree_paths[@]}" 1  # Feature worktree only (main repo excluded)
  assert_equal "${#branches[@]}" 1
  assert_equal "${#commits[@]}" 1
  assert_equal "${#status_dirty[@]}" 1
  assert_equal "${#locked_status[@]}" 1

  # Check that feature worktree is included
  local found_feature=false
  for path in "${worktree_paths[@]}"; do
    if [[ "$path" == "$feature_wt" ]]; then
      found_feature=true
      break
    fi
  done
  $found_feature || fail "Feature worktree path not found in worktree list"
}

@test "hug-git-worktree: get_current_worktree_path returns current directory" {
  cd "$TEST_REPO"
  local current_path
  current_path=$(get_current_worktree_path)

  assert_equal "$current_path" "$TEST_REPO"
}

@test "hug-git-worktree: worktree_exists correctly identifies existing worktree" {
  local feature_wt
  feature_wt=$(create_test_worktree "feature-1" "$TEST_REPO")

  worktree_exists "$feature_wt"
}

@test "hug-git-worktree: worktree_exists returns false for non-existent worktree" {
  # shellcheck disable=SC2314
  ! worktree_exists "/nonexistent/path"
}

@test "hug-git-worktree: worktree_exists returns false for empty path" {
  # shellcheck disable=SC2314
  ! worktree_exists ""
}

@test "hug-git-worktree: worktree_gitdir resolves shared gitdir for linked worktree" {
  local feature_wt gitdir
  feature_wt=$(create_test_worktree "feature-1" "$TEST_REPO")

  gitdir=$(worktree_gitdir "$feature_wt")
  # Linked worktrees share the main repo's .git as their common dir.
  [[ "$gitdir" = "$TEST_REPO/.git" ]] || { echo "got: $gitdir" >&2; false; }
}

@test "hug-git-worktree: worktree_gitdir absolutizes relative .git for main worktree" {
  local gitdir
  # In the main worktree, --git-common-dir returns the literal ".git" —
  # the helper must absolutize it so callers can pass it to --git-dir
  # safely regardless of CWD.
  gitdir=$(worktree_gitdir "$TEST_REPO")
  [[ "$gitdir" = /* ]] || { echo "expected absolute gitdir, got: $gitdir" >&2; false; }
  [[ "$gitdir" = "$TEST_REPO/.git" ]] || { echo "expected $TEST_REPO/.git, got: $gitdir" >&2; false; }
}

@test "hug-git-worktree: worktree_gitdir returns failure for non-existent path" {
  # shellcheck disable=SC2314
  ! worktree_gitdir "/nonexistent/path-that-does-not-exist"
}

@test "hug-git-worktree: worktree_gitdir returns failure for empty path" {
  # shellcheck disable=SC2314
  ! worktree_gitdir ""
}

@test "hug-git-worktree: worktree_exists finds submodule worktree when CWD is meta-repo" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  [[ -n "$meta_repo" && -n "$wt_path" ]] || skip "submodule fixture setup failed (likely modern git restricting local submodules)"

  cd "$meta_repo"
  worktree_exists "$wt_path"

  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}

@test "hug-git-worktree: worktree_exists finds submodule worktree when CWD is submodule checkout" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  [[ -n "$meta_repo" && -n "$wt_path" ]] || skip "submodule fixture setup failed"

  cd "$meta_repo/sub"
  worktree_exists "$wt_path"

  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}

@test "hug-git-worktree: worktree_exists finds submodule worktree when CWD is the worktree itself" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  [[ -n "$meta_repo" && -n "$wt_path" ]] || skip "submodule fixture setup failed"

  cd "$wt_path"
  worktree_exists "$wt_path"

  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}

@test "hug-git-worktree: worktree_exists does NOT match substring paths" {
  # Regression test: previously used grep -qF (substring), now uses grep -qxF (exact line).
  # If we register /tmp/foo and ask about /tmp/fo, the answer must be NO.
  local feature_wt feature_wt_prefix
  feature_wt=$(create_test_worktree "feature-1" "$TEST_REPO")
  # Truncate one char — this prefix must NOT be reported as existing
  feature_wt_prefix="${feature_wt%?}"

  worktree_exists "$feature_wt"
  # shellcheck disable=SC2314
  ! worktree_exists "$feature_wt_prefix"
}

@test "hug-git-worktree: get_worktree_count returns correct count" {
  # Should start with 0 (main repository only)
  assert_equal "$(get_worktree_count)" 0

  # Create worktree
  create_test_worktree "feature-1" "$TEST_REPO"

  # Should now have 1
  assert_equal "$(get_worktree_count)" 1
}

@test "hug-git-worktree: validate_worktree_path accepts valid worktree" {
  local feature_wt
  feature_wt=$(create_test_worktree "feature-1" "$TEST_REPO")

  validate_worktree_path "$feature_wt"  # Should not fail
}

@test "hug-git-worktree: validate_worktree_path rejects empty path" {
  run validate_worktree_path ""

  assert_failure
  assert_output --partial "Worktree path cannot be empty"
}

@test "hug-git-worktree: validate_worktree_path rejects non-existent path" {
  run validate_worktree_path "/nonexistent/path"

  assert_failure
  assert_output --partial "Worktree path does not exist"
}

@test "hug-git-worktree: validate_worktree_path rejects non-directory" {
  local file_path="${TEST_REPO}/test-file"
  touch "$file_path"

  run validate_worktree_path "$file_path"

  assert_failure
  assert_output --partial "Worktree path is not a directory"

  rm "$file_path"
}

@test "hug-git-worktree: validate_worktree_path rejects non-worktree directory" {
  local not_worktree="/tmp/hug-test-not-worktree"
  mkdir -p "$not_worktree"

  run validate_worktree_path "$not_worktree"

  assert_failure
  assert_output --partial "Path is not a Git worktree"

  rmdir "$not_worktree"
}

@test "hug-git-worktree: branch_available_for_worktree accepts available branch" {
  branch_available_for_worktree "main"  # main should be available
}

@test "hug-git-worktree: branch_available_for_worktree rejects checked out branch" {
  # Create worktree for feature-1
  create_test_worktree "feature-1" "$TEST_REPO"

  # shellcheck disable=SC2314
  ! branch_available_for_worktree "feature-1"
}

@test "hug-git-worktree: branch_available_for_worktree rejects non-existent branch" {
  # shellcheck disable=SC2314
  ! branch_available_for_worktree "nonexistent-branch"
}

@test "hug-git-worktree: branch_available_for_worktree rejects empty branch name" {
  # shellcheck disable=SC2314
  ! branch_available_for_worktree ""
}

@test "hug-git-worktree: validate_worktree_creation_path accepts valid path" {
  local parent_dir="/tmp/hug-test-validate"
  mkdir -p "$parent_dir"
  local valid_path="${parent_dir}/new-worktree"

  validate_worktree_creation_path "$valid_path"

  rmdir "$parent_dir"
}

@test "hug-git-worktree: validate_worktree_creation_path rejects empty path" {
  run validate_worktree_creation_path ""

  assert_failure
  assert_output --partial "Worktree path cannot be empty"
}

@test "hug-git-worktree: validate_worktree_creation_path rejects existing path" {
  local existing_path="${TEST_REPO}/existing"
  mkdir -p "$existing_path"

  run validate_worktree_creation_path "$existing_path"

  assert_failure
  assert_output --partial "Target path already exists"

  rmdir "$existing_path"
}

@test "hug-git-worktree: validate_worktree_creation_path rejects non-existent parent" {
  local path_with_nonexistent_parent="/tmp/nonexistent/parent/path"

  # Pass false to disable auto-creation of parent directory
  run validate_worktree_creation_path "$path_with_nonexistent_parent" "false"

  assert_failure
  assert_output --partial "Parent directory does not exist"
}

@test "hug-git-worktree: generate_worktree_path creates sensible default" {
  local generated_path
  generated_path=$(generate_worktree_path "feature-1")

  local parent_dir
  parent_dir=$(dirname "$TEST_REPO")
  assert_equal "$generated_path" "${parent_dir}/$(basename "$TEST_REPO").WT.feature-1"
}

@test "hug-git-worktree: generate_worktree_path sanitizes branch name" {
  local generated_path
  generated_path=$(generate_worktree_path "feature/auth.v2")

  local parent_dir
  parent_dir=$(dirname "$TEST_REPO")
  assert_equal "$generated_path" "${parent_dir}/$(basename "$TEST_REPO").WT.feature-auth-v2"
}

@test "hug-git-worktree: generate_unique_worktree_path returns unique path" {
  # Create a directory at the default location
  local default_path
  default_path=$(generate_worktree_path "feature-1")
  mkdir -p "$default_path"

  local unique_path
  unique_path=$(generate_unique_worktree_path "feature-1")

  # Should be different from default path
  assert_not_equal "$unique_path" "$default_path"
  assert_regex_match "$unique_path" ".*-1$"

  # Clean up
  rm -rf "$default_path"
}

@test "hug-git-worktree: generate_unique_worktree_path returns default if available" {
  local default_path
  default_path=$(generate_worktree_path "feature-unique")

  # Should return default path since it doesn't exist
  local unique_path
  unique_path=$(generate_unique_worktree_path "feature-unique")

  assert_equal "$unique_path" "$default_path"
}

@test "hug-git-worktree: create_worktree succeeds with valid inputs" {
  local new_path="${TEST_REPO}-wt-test-create"
  run create_worktree "main" "$new_path" true false

  assert_success
  assert_worktree_exists "$new_path"
  assert_worktree_branch "$new_path" "main"
}

# NOTE: create_worktree no longer supports dry-run directly.
# Dry-run is handled at the command level (git-wtc) and tested in test_worktree_create.bats.

@test "hug-git-worktree: create_worktree fails with non-existent branch" {
  local new_path="${TEST_REPO}-wt-test-fail"
  run create_worktree "nonexistent-branch" "$new_path" true

  assert_failure
  assert_output --partial "Branch 'nonexistent-branch' does not exist locally"
  assert_worktree_not_exists "$new_path"
}

@test "hug-git-worktree: create_worktree fails with checked out branch" {
  # Create worktree for feature-1
  create_test_worktree "feature-1" "$TEST_REPO"

  local new_path="${TEST_REPO}-wt-test-checked-out"
  run create_worktree "feature-1" "$new_path" true

  assert_failure
  assert_output --partial "Branch 'feature-1' is already checked out"
  assert_worktree_not_exists "$new_path"
}

@test "hug-git-worktree: remove_worktree succeeds with valid inputs" {
  local feature_wt
  feature_wt=$(create_test_worktree "feature-1" "$TEST_REPO")

  run remove_worktree "$feature_wt" true

  assert_success
  assert_worktree_not_exists "$feature_wt"
}

@test "hug-git-worktree: remove_worktree fails with current worktree" {
  cd "$TEST_REPO"
  run remove_worktree "$TEST_REPO" true

  assert_failure
  assert_output --partial "Cannot remove current worktree"
}

@test "hug-git-worktree: remove_worktree fails with dirty worktree without force" {
  local feature_wt
  feature_wt=$(create_test_worktree_with_dirty_changes "feature-1" "$TEST_REPO")

  run remove_worktree "$feature_wt" false

  assert_failure
  assert_output --partial "Worktree has uncommitted changes"
  assert_worktree_exists "$feature_wt"
}

@test "hug-git-worktree: remove_worktree removes dirty worktree with force" {
  local feature_wt
  feature_wt=$(create_test_worktree_with_dirty_changes "feature-1" "$TEST_REPO")

  run remove_worktree "$feature_wt" true

  assert_success
  assert_worktree_not_exists "$feature_wt"
}

@test "hug-git-worktree: switch_to_worktree succeeds with valid path" {
  local feature_wt
  feature_wt=$(create_test_worktree "feature-1" "$TEST_REPO")

  # Note: We can't test actual directory change in bats, but we can test validation
  run switch_to_worktree "$feature_wt"

  assert_success
  assert_output --partial "Switched to worktree"
}

@test "hug-git-worktree: switch_to_worktree fails with invalid path" {
  run switch_to_worktree "/nonexistent/path"

  assert_failure
  assert_output --partial "Cannot switch to worktree"
}

@test "hug-git-worktree: prune_worktrees handles no orphaned worktrees" {
  # Source the library to access the function
  source "$HUG_HOME/git-config/lib/hug-git-worktree"

  run prune_worktrees false false

  assert_success
  assert_output --partial "No orphaned worktrees found"
}

@test "hug-git-worktree: is_worktree_not_main returns false for main repository" {
  cd "$TEST_REPO"
  # shellcheck disable=SC2314
  ! is_worktree_not_main
}

@test "hug-git-worktree: is_worktree_not_main returns true for worktree" {
  local feature_wt
  feature_wt=$(create_test_worktree "feature-1" "$TEST_REPO")

  cd "$feature_wt"
  is_worktree_not_main
}

@test "hug-git-worktree: is_worktree_not_main returns false when not in git repo" {
  cd /tmp
  # shellcheck disable=SC2314
  ! is_worktree_not_main
}

# Tests for branch_matches_any function

@test "hug-git-worktree: branch_matches_any exact match returns success" {
  run branch_matches_any "feature-1" "feat-1" "feature-1" "main"
  assert_success
}

@test "hug-git-worktree: branch_matches_any no match returns failure" {
  run branch_matches_any "feature-1" "feat-1" "main"
  assert_failure
}

@test "hug-git-worktree: branch_matches_any empty filters matches everything" {
  run branch_matches_any "feature-1"
  assert_success
}

@test "hug-git-worktree: branch_matches_any case-sensitive matching" {
  run branch_matches_any "feature-1" "Feature-1" "MAIN"
  assert_failure
}

@test "hug-git-worktree: branch_matches_any single filter match" {
  run branch_matches_any "main" "main"
  assert_success
}

@test "hug-git-worktree: branch_matches_any single filter no match" {
  run branch_matches_any "main" "develop"
  assert_failure
}

# Tests for get_worktree_dirty_details function

@test "hug-git-worktree: get_worktree_dirty_details returns clean for clean worktree" {
  local feature_wt
  feature_wt=$(create_test_worktree "feature-1" "$TEST_REPO")
  
  local is_dirty=""
  local details=""
  get_worktree_dirty_details "$feature_wt" is_dirty details
  
  [[ "$is_dirty" == "false" ]] || fail "Expected is_dirty=false, got '$is_dirty'"
  [[ "$details" == "" ]] || fail "Expected empty details, got '$details'"
}

@test "hug-git-worktree: get_worktree_dirty_details detects unstaged changes" {
  local feature_wt
  feature_wt=$(create_test_worktree "feature-1" "$TEST_REPO")
  
  # Modify existing file (unstaged)
  echo "dirty changes" >> "$feature_wt/README.md"
  git -C "$feature_wt" add "README.md"
  git -C "$feature_wt" reset HEAD "README.md" >/dev/null 2>&1
  
  local is_dirty=""
  local details=""
  get_worktree_dirty_details "$feature_wt" is_dirty details
  
  [[ "$is_dirty" == "true" ]] || fail "Expected is_dirty=true, got '$is_dirty'"
  [[ "$details" == *"unstaged changes"* ]] || fail "Expected 'unstaged changes' in details, got '$details'"
}

@test "hug-git-worktree: get_worktree_dirty_details detects staged changes" {
  local feature_wt
  feature_wt=$(create_test_worktree "feature-1" "$TEST_REPO")
  
  # Stage a new file
  echo "new file" > "$feature_wt/staged.txt"
  git -C "$feature_wt" add "staged.txt"
  
  local is_dirty=""
  local details=""
  get_worktree_dirty_details "$feature_wt" is_dirty details
  
  [[ "$is_dirty" == "true" ]] || fail "Expected is_dirty=true, got '$is_dirty'"
  [[ "$details" == *"staged changes"* ]] || fail "Expected 'staged changes' in details, got '$details'"
}

@test "hug-git-worktree: get_worktree_dirty_details detects untracked files" {
  local feature_wt
  feature_wt=$(create_test_worktree "feature-1" "$TEST_REPO")
  
  # Create untracked file
  echo "untracked" > "$feature_wt/untracked.txt"
  
  local is_dirty=""
  local details=""
  get_worktree_dirty_details "$feature_wt" is_dirty details
  
  [[ "$is_dirty" == "true" ]] || fail "Expected is_dirty=true, got '$is_dirty'"
  [[ "$details" == *"untracked files"* ]] || fail "Expected 'untracked files' in details, got '$details'"
}

@test "hug-git-worktree: get_worktree_dirty_details combines multiple change types" {
  local feature_wt
  feature_wt=$(create_test_worktree "feature-1" "$TEST_REPO")
  
  # Create untracked file
  echo "untracked" > "$feature_wt/untracked.txt"
  
  # Modify and stage a file
  echo "modified" >> "$feature_wt/README.md"
  git -C "$feature_wt" add "README.md"
  
  local is_dirty=""
  local details=""
  get_worktree_dirty_details "$feature_wt" is_dirty details
  
  [[ "$is_dirty" == "true" ]] || fail "Expected is_dirty=true, got '$is_dirty'"
  # Should contain at least two types (comma-separated)
  local comma_count
  comma_count=$(echo "$details" | tr -cd ',' | wc -c)
  [[ $comma_count -ge 1 ]] || fail "Expected at least 2 change types in details, got '$details'"
}

@test "resolve_main_worktree_path: returns repo path for plain clone" {
  # Reassign TEST_REPO so teardown() handles cleanup automatically.
  # cleanup_test_repo() ignores its argument — it only cleans up $TEST_REPO —
  # so we must not use a separate local $repo variable here. Any plain git repo
  # (including the branches-flavoured one) works because we only verify that
  # resolve_main_worktree_path returns the main worktree root, not branch state.
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
  # No re-source needed: hug-git-worktree is already loaded via
  # `load '../../git-config/lib/hug-git-worktree'` at the top of this file.
  run resolve_main_worktree_path
  assert_success
  # Use realpath because macOS /tmp resolves to /private/tmp
  [[ "$(realpath "$output")" == "$(realpath "$TEST_REPO")" ]]
}
