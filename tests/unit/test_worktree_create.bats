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

@test "hug wtc: -f composes with --dry-run (previews, no error)" {
  # After family parity: -f and --dry-run compose (no longer mutually exclusive)
  run git-wtc some-new-branch --dry-run -f
  assert_success
  assert_output --partial "DRY RUN"
  refute_output --partial "mutually exclusive"
}

@test "hug wtc: interactive mode with no branch argument" {
  # Test interactive mode with EOF simulation to prevent hanging
  # This works in both gum and non-gum environments
  run bash -c "echo | git-wtc 2>&1"
  assert_failure  # Exits with code 1 due to cancellation

  # Should show cancellation message since no interactive selection possible
  assert_output --partial "cancelled"
}

@test "hug wtc: error when branch already has worktree (exit 3)" {
  # First, create a worktree for feature-1
  run git-wtc feature-1 -f
  assert_success

  # Try to create another worktree for the same branch - should fail with exit 3
  run git-wtc feature-1 -f
  assert_failure 3

  # Should show appropriate error message naming the holding worktree
  assert_output --partial "checked out in worktree"
  assert_output --partial "hug wtdel feature-1"
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
  assert_failure 3

  # Error should contain useful information (names holding worktree + removal hint)
  assert_output --partial "checked out in worktree"
  assert_output --partial "hug wtdel feature-1"
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

@test "hug wtc: error with too many arguments (exit 2)" {
  # Test with too many arguments - should fail with usage error
  run git-wtc feature-1 extra-path another-arg
  assert_failure 2

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
  # Test using --dry-run flag alone
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
  assert_failure 3
  assert_output --partial "checked out in worktree"
}

@test "hug wtc: error when branch is checked out in main worktree without -f (exit 3)" {
  # main is the currently checked out branch in the test repo
  run git-wtc main
  assert_failure 3
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

# --- --base flag tests ---

@test "hug wtc: --base creates branch from specified branch" {
  # Create a new branch from feature-1 via --base, then worktree
  run git-wtc from-feature1 --base feature-1 -f
  assert_success
  assert_output --partial "Created branch 'from-feature1' from feature-1"

  # Verify worktree was created
  local worktree_path
  worktree_path=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  worktree_path="$(cd "$(dirname "$worktree_path")" && pwd)/$(basename "$worktree_path")"
  assert_worktree_exists "$worktree_path"

  # Verify the worktree has feature-1's file (not main's)
  cd "$worktree_path"
  assert_file_exists "feature1.txt"
}

@test "hug wtc: --base with tag creates branch from tag" {
  # Create a tag on the current HEAD
  git tag v1.0

  # Add a commit on main so HEAD is past the tag
  echo "post-tag" > post-tag.txt
  git add post-tag.txt
  git commit -q -m "post-tag commit"

  run git-wtc from-tag --base v1.0 -f
  assert_success
  assert_output --partial "Created branch 'from-tag' from v1.0"

  # Verify worktree exists and does NOT have the post-tag file
  local worktree_path
  worktree_path=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  worktree_path="$(cd "$(dirname "$worktree_path")" && pwd)/$(basename "$worktree_path")"
  assert_worktree_exists "$worktree_path"
  cd "$worktree_path"
  assert_file_not_exists "post-tag.txt"
}

@test "hug wtc: --base HEAD~2 creates branch from relative ref" {
  run git-wtc from-relative --base HEAD~2 -f
  assert_success
  assert_output --partial "Created branch 'from-relative' from HEAD~2"
}

@test "hug wtc: --base errors when branch already exists" {
  # feature-1 already exists in the test repo
  run git-wtc feature-1 --base main
  assert_failure
  assert_output --partial "already exists"
  assert_output --partial "--base only applies when creating new branches"
}

@test "hug wtc: --base errors with invalid commitish" {
  run git-wtc new-branch --base nonexistent-ref-xyz
  assert_failure
  assert_output --partial "Cannot resolve --base"
  assert_output --partial "nonexistent-ref-xyz"
  assert_output --partial "HEAD~N"
}

@test "hug wtc: --base implies --new without explicit flag" {
  # Create a branch without --new -- should work because --base implies it
  run git-wtc implied-new-branch --base main -f
  assert_success
  assert_output --partial "Created branch 'implied-new-branch'"
  assert_output --partial "Worktree created for 'implied-new-branch'"
}

@test "hug wtc: --base with --dry-run shows start-point" {
  run git-wtc dry-run-base --base main --dry-run
  assert_success
  assert_output --partial "Worktree Creation Preview (DRY RUN)"
  assert_output --partial "new, from main"
  assert_output --partial "No changes made (dry run)"

  # Verify the branch was NOT created
  run git rev-parse --verify "refs/heads/dry-run-base"
  assert_failure
}

@test "hug wtc: --base with --force skips confirmation" {
  run git-wtc force-base-branch --base feature-1 -f
  assert_success
  assert_output --partial "Created branch 'force-base-branch' from feature-1"
  assert_output --partial "Worktree created for 'force-base-branch'"
}

@test "hug wtc: generates path outside .git/ when invoked from submodule CWD" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  cd "$meta_repo/sub"
  hug b main 2>/dev/null || hug b master 2>/dev/null || true
  run git-wtc new-branch --new -y
  assert_success
  local generated_path
  generated_path=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  [[ "$generated_path" != *"/.git/"* ]]
  [[ "$(dirname "$(realpath "$generated_path")")" == "$(realpath "$meta_repo")" ]]
  # Eng E9: also assert Git's registered worktree state via owning gitdir
  local sub_gitdir="$meta_repo/.git/modules/sub"
  git --git-dir="$sub_gitdir" worktree list --porcelain | grep -qxF "worktree $generated_path"
  git --git-dir="$sub_gitdir" worktree remove --force "$generated_path" 2>/dev/null || rm -rf "$generated_path"
  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}

# Eng E7: --base flag + submodule CWD
@test "hug wtc: --base flag works from submodule CWD without .git/ path leakage" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  cd "$meta_repo/sub"
  hug b main 2>/dev/null || hug b master 2>/dev/null || true
  run git-wtc base-new-branch --base HEAD -y
  assert_success
  local generated_path
  generated_path=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  [[ "$generated_path" != *"/.git/"* ]]
  local sub_gitdir="$meta_repo/.git/modules/sub"
  git --git-dir="$sub_gitdir" worktree remove --force "$generated_path" 2>/dev/null || rm -rf "$generated_path"
  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}

# Eng E10: linked WT of submodule as CWD
@test "hug wtc: works from a linked submodule worktree CWD" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  cd "$wt_path"
  run git-wtc another-branch --new -y
  assert_success
  local generated_path
  generated_path=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  [[ "$generated_path" != *"/.git/"* ]]
  local sub_gitdir="$meta_repo/.git/modules/sub"
  git --git-dir="$sub_gitdir" worktree remove --force "$generated_path" 2>/dev/null || rm -rf "$generated_path"
  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}

@test "hug wtc: rejects user-supplied path under .git/" {
  TEST_REPO=$(create_test_repo_with_branches)
  cd "$TEST_REPO"
  run git-wtc feature-1 "$TEST_REPO/.git/should-not-go-here" -f
  assert_failure
  assert_output --partial "Cannot create worktree under a .git/ directory"
}

@test "hug wtc: rejects .git/<missing>/wt without creating partial dir" {
  TEST_REPO=$(create_test_repo_with_branches)
  cd "$TEST_REPO"
  run git-wtc feature-1 "$TEST_REPO/.git/never-existed/wt" -f
  assert_failure
  # Mkdir must NOT have created the intermediate directory (guard runs before mkdir)
  [[ ! -d "$TEST_REPO/.git/never-existed" ]]
}

@test "hug wtc: emits superproject .gitignore tip from submodule CWD" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  cd "$meta_repo/sub"
  hug b main 2>/dev/null || hug b master 2>/dev/null || true
  run git-wtc new-branch --new -y
  assert_success
  assert_output --partial "Worktree is inside superproject"
  assert_output --partial "*.WT.*/"
  local generated
  generated=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  rm -rf "$generated" 2>/dev/null || true
  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}

@test "hug wtc: suppresses tip when *.WT.*/ already in superproject .gitignore" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  printf '*.WT.*/\n' >> "$meta_repo/.gitignore"
  cd "$meta_repo/sub"
  hug b main 2>/dev/null || hug b master 2>/dev/null || true
  run git-wtc new-branch --new -y
  assert_success
  [[ "$output" != *"Worktree is inside superproject"* ]]
  local generated
  generated=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  rm -rf "$generated" 2>/dev/null || true
  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}

# Eng phase finding #E3
@test "hug wtc: does NOT emit superproject tip when custom path is outside meta-repo" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  cd "$meta_repo/sub"
  hug b main 2>/dev/null || hug b master 2>/dev/null || true
  local custom_path
  custom_path=$(mktemp -d)/external-wt
  run git-wtc external-branch --new "$custom_path" -y
  assert_success
  [[ "$output" != *"Worktree is inside superproject"* ]]
  local sub_gitdir="$meta_repo/.git/modules/sub"
  git --git-dir="$sub_gitdir" worktree remove --force "$custom_path" 2>/dev/null || rm -rf "$custom_path"
  rm -rf "$(dirname "$custom_path")"
  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}

@test "hug wtc: does NOT emit superproject tip for plain clone" {
  TEST_REPO=$(create_test_repo_with_branches)
  cd "$TEST_REPO"
  run git-wtc feature-1 -f
  assert_success
  [[ "$output" != *"Worktree is inside superproject"* ]]
  local generated
  generated=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  hug wtdel feature-1 -f -B 2>/dev/null || rm -rf "$generated"
}

# --- Family parity tests (env force, dry-run composition, -p/-B, --json, -q, exit codes) ---

@test "hug wtc: HUG_FORCE env enables force semantics (main checkout)" {
  cd "$TEST_REPO"
  HUG_FORCE=true run git-wtc main
  assert_success
  assert_output --partial "Worktree created for 'main'"
}

@test "hug wtc: -p/--path places the worktree at the flag path" {
  cd "$TEST_REPO"
  target="$BATS_TEST_TMPDIR/custom-wt"
  run git-wtc flagged --new -y -p "$target"
  assert_success
  assert [ -f "$target/.git" ]
}

@test "hug wtc: positional path plus -p is a usage error (exit 2)" {
  cd "$TEST_REPO"
  run git-wtc b1 /tmp/pos-path -p /tmp/flag-path
  assert_failure 2
  assert_output --partial "not both"
}

@test "hug wtc: -B is an alias of --new" {
  cd "$TEST_REPO"
  run git-wtc aliased-branch -B -y
  assert_success
  assert_output --partial "Created branch 'aliased-branch'"
}

@test "hug wtc: branch-in-use error names holding worktree, exit 3" {
  wt=$(create_test_worktree "feature-1" "$TEST_REPO")
  cd "$TEST_REPO"
  run git-wtc feature-1 -y
  assert_failure 3
  assert_output --partial "checked out in worktree"
  assert_output --partial "hug wtdel feature-1"
}

@test "hug wtc: --base HEAD~1 resolves (relative refs accepted)" {
  cd "$TEST_REPO"
  run git-wtc from-past --base HEAD~1 -y
  assert_success
  assert_output --partial "Created branch 'from-past'"
}

@test "hug wtc: --base unresolvable ref explains accepted forms" {
  cd "$TEST_REPO"
  run git-wtc oops --base HEAD~99 -y
  assert_failure 1
  assert_output --partial "Cannot resolve --base"
  assert_output --partial "HEAD~N"
}

@test "hug wtc: --json emits parseable result object" {
  cd "$TEST_REPO"
  run bash -c "git-wtc jsonbranch --new -y --json 2>/dev/null | python3 -m json.tool"
  assert_success
  assert_output --partial '"created_branch": true'
  assert_output --partial '"branch": "jsonbranch"'
}

@test "hug wtc: -q suppresses summary chatter" {
  cd "$TEST_REPO"
  run git-wtc quietbranch --new -y -q
  assert_success
  refute_output --partial "Worktree Creation Summary"
}
