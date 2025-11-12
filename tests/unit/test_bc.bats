#!/usr/bin/env bats
# Tests for branch creation (hug bc / git bc)

# Load test helpers
load '../test_helper.bash'

setup() {
  enable_gum_for_test
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
  
  # Create some commits for testing
  echo "file1" > file1.txt
  git add file1.txt
  git commit -m "First commit"
  
  echo "file2" > file2.txt
  git add file2.txt
  git commit -m "Second commit"
  
  # Create a tag for testing
  git tag v1.0.0
  
  echo "file3" > file3.txt
  git add file3.txt
  git commit -m "Third commit"
}

teardown() {
  cleanup_test_repo
}

# -----------------------------------------------------------------------------
# Basic functionality tests
# -----------------------------------------------------------------------------

@test "hug bc --help: shows help message" {
  run hug bc -h
  assert_success
  assert_output --partial "hug bc: Create a new branch and switch to it"
  assert_output --partial "USAGE:"
  assert_output --partial "--point-to"
}

@test "hug bc <branch>: creates and switches to new branch from HEAD" {
  # Get current branch before creating new one
  original_branch=$(git branch --show-current)
  original_commit=$(git rev-parse HEAD)
  
  run hug bc new-feature
  assert_success
  
  # Verify we're on the new branch
  current=$(git branch --show-current)
  [ "$current" = "new-feature" ]
  
  # Verify it points to the original HEAD
  feature_commit=$(git rev-parse HEAD)
  [ "$feature_commit" = "$original_commit" ]
}

@test "hug bc: requires branch name without --point-to" {
  run hug bc
  assert_failure
  assert_output --partial "Branch name is required"
}

@test "hug bc --no-switch <branch>: creates without switching" {
  original_branch=$(git branch --show-current)
  original_commit=$(git rev-parse HEAD)
  
  run hug bc --no-switch new-feature-no-switch
  assert_success
  assert_output --partial "Created branch 'new-feature-no-switch' from HEAD"
  
  # Verify still on original branch
  current=$(git branch --show-current)
  [ "$current" = "$original_branch" ]
  
  # Verify branch exists and points to original HEAD
  git show-ref --verify "refs/heads/new-feature-no-switch" >/dev/null
  branch_commit=$(git rev-parse new-feature-no-switch)
  [ "$branch_commit" = "$original_commit" ]
}

@test "hug bc --no-switch --point-to <commit> <branch>: creates from commit without switching" {
  first_commit=$(git rev-list --max-parents=0 HEAD)
  
  original_branch=$(git branch --show-current)
  run hug bc --no-switch --point-to "$first_commit" feature-from-first-no-switch
  assert_success
  assert_output --partial "Created branch 'feature-from-first-no-switch' pointing to"
  
  # Verify still on original branch
  current=$(git branch --show-current)
  [ "$current" = "$original_branch" ]
  
  # Verify branch exists and points to first commit
  git show-ref --verify "refs/heads/feature-from-first-no-switch" >/dev/null
  branch_commit=$(git rev-parse feature-from-first-no-switch)
  [ "$branch_commit" = "$first_commit" ]
}

@test "hug bc --no-switch --point-to <tag>: auto-generates name without switching" {
  original_branch=$(git branch --show-current)
  
  run hug bc --no-switch --point-to v1.0.0
  assert_success
  assert_output --partial "Auto-generated branch name:"
  assert_output --partial ".branch."
  assert_output --partial "Created branch"
  
  # Verify still on original branch
  current=$(git branch --show-current)
  [ "$current" = "$original_branch" ]
  
  # Verify generated branch exists and points to tag
  new_branch=$(git branch | grep ".branch\." | head -1 | xargs)
  [ -n "$new_branch" ]
  git show-ref --verify "refs/heads/$new_branch" >/dev/null
  tag_commit=$(git rev-parse v1.0.0)
  branch_commit=$(git rev-parse "$new_branch")
  [ "$branch_commit" = "$tag_commit" ]
}

@test "hug bc --no-switch: fails if branch exists" {
  git checkout -b existing-no-switch
  git switch -
  
  run hug bc --no-switch existing-no-switch
  assert_failure
  assert_output --partial "already exists"
}

@test "hug bc --no-switch --point-to: auto-generates unique name if conflict" {
  original_branch=$(git branch --show-current)
  
  # First create to cause potential conflict (but with seconds uniqueness)
  run hug bc --no-switch --point-to v1.0.0
  first_branch=$(git branch | grep ".branch\." | head -1 | xargs)
  
  # Second should generate unique (with seconds)
  run hug bc --no-switch --point-to v1.0.0
  assert_success
  assert_output --partial "Generated name existed; using"
  
  second_branch=$(git branch | grep ".branch\." | tail -1 | xargs)
  [ "$second_branch" != "$first_branch" ]
  [ -n "$second_branch" ]
}

# -----------------------------------------------------------------------------
# --point-to with explicit branch name tests
# -----------------------------------------------------------------------------

@test "hug bc --point-to <commit> <branch>: creates branch from specific commit" {
  # Get the first commit hash
  first_commit=$(git rev-list --max-parents=0 HEAD)
  
  run hug bc --point-to "$first_commit" feature-from-first
  assert_success
  
  # Verify we're on the new branch
  current=$(git branch --show-current)
  [ "$current" = "feature-from-first" ]
  
  # Verify it points to the first commit
  branch_commit=$(git rev-parse HEAD)
  [ "$branch_commit" = "$first_commit" ]
}

@test "hug bc --point-to <tag> <branch>: creates branch from tag" {
  run hug bc --point-to v1.0.0 feature-from-tag
  assert_success
  
  # Verify we're on the new branch
  current=$(git branch --show-current)
  [ "$current" = "feature-from-tag" ]
  
  # Verify it points to the tagged commit
  tag_commit=$(git rev-parse v1.0.0)
  branch_commit=$(git rev-parse HEAD)
  [ "$branch_commit" = "$tag_commit" ]
}

@test "hug bc --point-to <branch> <new-branch>: creates branch from another branch" {
  # Get current branch
  original_branch=$(git branch --show-current)
  
  # Create a test branch
  git checkout -b source-branch
  echo "source" > source.txt
  git add source.txt
  git commit -m "Source commit"
  source_commit=$(git rev-parse HEAD)
  
  # Switch back to original
  git switch "$original_branch"
  
  # Create new branch from source-branch
  run hug bc --point-to source-branch target-branch
  assert_success
  
  current=$(git branch --show-current)
  [ "$current" = "target-branch" ]
  
  # Verify it points to source-branch
  target_commit=$(git rev-parse HEAD)
  [ "$target_commit" = "$source_commit" ]
}

@test "hug bc <branch> --point-to <commit>: flag can come after branch name" {
  first_commit=$(git rev-list --max-parents=0 HEAD)
  
  run hug bc my-feature --point-to "$first_commit"
  assert_success
  
  current=$(git branch --show-current)
  [ "$current" = "my-feature" ]
  
  branch_commit=$(git rev-parse HEAD)
  [ "$branch_commit" = "$first_commit" ]
}

@test "hug bc --point-to: requires a commitish argument" {
  run hug bc --point-to
  assert_failure
  assert_output --partial "requires an argument"
}

@test "hug bc --point-to <invalid>: fails with invalid commitish" {
  run hug bc --point-to nonexistent-commit my-branch
  assert_failure
  assert_output --partial "Invalid commitish"
}

# -----------------------------------------------------------------------------
# Auto-generated branch name tests
# -----------------------------------------------------------------------------

@test "hug bc --point-to <branch>: generates branch name with .copy suffix" {
  # Get current branch
  current_branch=$(git branch --show-current)
  
  run hug bc --point-to "$current_branch"
  assert_success
  assert_output --partial "Auto-generated branch name:"
  assert_output --partial ".copy."
  
  # Verify the pattern: <branch>.copy.YYYYMMDD-HHMM
  new_branch=$(git branch --show-current)
  [[ "$new_branch" =~ ^${current_branch}\.copy\.[0-9]{8}-[0-9]{4}$ ]]
}

@test "hug bc --point-to <tag>: generates branch name with .branch suffix" {
  run hug bc --point-to v1.0.0
  assert_success
  assert_output --partial "Auto-generated branch name:"
  assert_output --partial ".branch."
  
  # Verify the pattern: <tag>.branch.YYYYMMDD-HHMM
  current=$(git branch --show-current)
  [[ "$current" =~ ^v1\.0\.0\.branch\.[0-9]{8}-[0-9]{4}$ ]]
}

@test "hug bc --point-to <commit-hash>: generates branch name with short hash" {
  first_commit=$(git rev-list --max-parents=0 HEAD)
  short_hash=$(git rev-parse --short=7 "$first_commit")
  
  run hug bc --point-to "$first_commit"
  assert_success
  assert_output --partial "Auto-generated branch name:"
  assert_output --partial "$short_hash"
  assert_output --partial ".branch."
  
  # Verify the pattern: <short-hash>.branch.YYYYMMDD-HHMM
  current=$(git branch --show-current)
  [[ "$current" =~ ^${short_hash}\.branch\.[0-9]{8}-[0-9]{4}$ ]]
}

@test "hug bc --point-to <commit-hash>: works with short hash input" {
  first_commit=$(git rev-list --max-parents=0 HEAD)
  short_hash=$(git rev-parse --short=7 "$first_commit")
  
  run hug bc --point-to "$short_hash"
  assert_success
  assert_output --partial "Auto-generated branch name:"
  
  # Should still generate a valid branch name
  current=$(git branch --show-current)
  [[ "$current" =~ \.branch\.[0-9]{8}-[0-9]{4}$ ]]
  
  # Verify it points to the correct commit
  branch_commit=$(git rev-parse HEAD)
  [ "$branch_commit" = "$first_commit" ]
}

@test "hug bc --point-to with auto-name: points to correct commit" {
  tag_commit=$(git rev-parse v1.0.0)
  
  run hug bc --point-to v1.0.0
  assert_success
  
  # Verify the branch points to the tag commit
  branch_commit=$(git rev-parse HEAD)
  [ "$branch_commit" = "$tag_commit" ]
}

# -----------------------------------------------------------------------------
# Edge cases and error handling
# -----------------------------------------------------------------------------

@test "hug bc: too many arguments fails" {
  run hug bc branch1 branch2
  assert_failure
  assert_output --partial "Too many arguments"
}

@test "hug bc: unknown option fails" {
  run hug bc --unknown-flag my-branch
  assert_failure
  assert_output --partial "unrecognized option"
}

@test "hug bc: works with branch names containing special characters" {
  run hug bc feature/my-new-feature
  assert_success
  
  current=$(git branch --show-current)
  [ "$current" = "feature/my-new-feature" ]
}

@test "hug bc --point-to: auto-generated name is unique per minute" {
  # Get current branch
  original_branch=$(git branch --show-current)
  
  # Create first branch
  run hug bc --point-to v1.0.0
  assert_success
  first_branch=$(git branch --show-current)
  
  # Switch back to original
  git switch "$original_branch"
  
  # Try to create another branch from same tag in same minute
  # This should succeed with a unique name (adds seconds)
  run hug bc --point-to v1.0.0
  assert_success
  assert_output --partial "Generated name existed; using"
  second_branch=$(git branch --show-current)
  
  # Verify branches are different but both exist
  [ "$first_branch" != "$second_branch" ]
  git show-ref --verify "refs/heads/$first_branch" >/dev/null
  git show-ref --verify "refs/heads/$second_branch" >/dev/null
}

@test "hug bc: validates repo is a git repository" {
  cd /tmp
  mkdir -p /tmp/not-a-repo-$$
  cd /tmp/not-a-repo-$$
  
  run hug bc test-branch
  assert_failure
  assert_output --partial "Not in a Git or Mercurial repository"
  
  cd /tmp
  rm -rf /tmp/not-a-repo-$$
}

# -----------------------------------------------------------------------------
# Integration with existing branches
# -----------------------------------------------------------------------------

@test "hug bc: cannot create branch with existing name" {
  # Create a branch
  git checkout -b existing-branch
  git switch -
  
  # Try to create the same branch again
  run hug bc existing-branch
  assert_failure
  assert_output --partial "already exists"
}

@test "hug bc --point-to: creates branch at different point than HEAD" {
  # Get commits
  head_commit=$(git rev-parse HEAD)
  first_commit=$(git rev-list --max-parents=0 HEAD)
  
  # Verify they're different
  [ "$head_commit" != "$first_commit" ]
  
  # Create branch from first commit
  run hug bc --point-to "$first_commit" from-first
  assert_success
  
  branch_commit=$(git rev-parse HEAD)
  [ "$branch_commit" = "$first_commit" ]
  [ "$branch_commit" != "$head_commit" ]
}
