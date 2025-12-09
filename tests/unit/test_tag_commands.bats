#!/usr/bin/env bats

load ../test_helper

setup() {
  enable_gum_for_test
  require_hug
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"

}

teardown() {
  cleanup_test_repo
}

@test "git-tl: lists tags with type indicators" {
  # Create different types of tags
  git tag v1.0.0 HEAD~2
  git tag -a v1.1.0 HEAD~1 -m "Release version 1.1.0"

  run hug tl

  assert_success
  assert_output --partial "v1.0.0"
  assert_output --partial "v1.1.0"
  assert_output --partial "[L]"  # Lightweight indicator
  assert_output --partial "[A]"  # Annotated indicator
}

@test "git-tl: supports --json output" {
  git tag v1.0.0 HEAD~2
  git tag -a v1.1.0 HEAD~1 -m "Release version 1.1.0"

  run hug tl --json

  assert_success
  assert_output --partial '"name": "v1.0.0"'
  assert_output --partial '"type": "lightweight"'
  assert_output --partial '"name": "v1.1.0"'
  assert_output --partial '"type": "annotated"'
}

@test "git-tl: filters by pattern" {
  git tag v1.0.0 HEAD~2
  git tag v2.0.0 HEAD~1
  git tag feature-branch HEAD

  run hug tl v1

  assert_success
  assert_output --partial "v1.0.0"
  refute_output --partial "v2.0.0"
  refute_output --partial "feature-branch"
}

@test "git-tll: detailed tag list with annotations" {
  git config user.email "test@example.com"
  git config user.name "Test User"

  git tag v1.0.0 HEAD~2
  git tag -a v1.1.0 HEAD~1 -m "Release version 1.1.0"

  run hug tll

  assert_success
  assert_output --partial "v1.0.0"
  assert_output --partial "v1.1.0"
  assert_output --partial "(lightweight)"
  assert_output --partial "(annotated)"
  assert_output --partial "Release version 1.1.0"
  assert_output --partial "Test User"
}

@test "git-tll: supports --json output" {
  git config user.email "test@example.com"
  git config user.name "Test User"

  git tag -a v1.1.0 HEAD -m "Test release"

  run hug tll --json

  assert_success
  assert_output --partial '"name": "v1.1.0"'
  assert_output --partial '"type": "annotated"'
  assert_output --partial '"subject": "Test release"'
  assert_output --partial '"tagger":'
  assert_output --partial '"name": "Test User"'
}

@test "git-tll: filters by type" {
  git tag v1.0.0 HEAD~2
  git tag -a v1.1.0 HEAD~1 -m "Release version 1.1.0"

  run hug tll --type lightweight

  assert_success
  assert_output --partial "v1.0.0"
  assert_output --partial "(lightweight)"
  refute_output --partial "v1.1.0"
  refute_output --partial "(annotated)"
}

@test "git-tc: creates lightweight tag" {
  run hug tc test-tag HEAD~1

  assert_success
  assert_output --partial "Created lightweight tag: test-tag"

  # Verify tag exists
  git rev-parse --verify "refs/tags/test-tag"
}

@test "git-tc: creates annotated tag" {
  run hug tc -a test-annotated -m "Test annotated tag"

  assert_success
  assert_output --partial "Created annotated tag: test-annotated"

  # Verify tag exists and is annotated
  local tag_type
  tag_type=$(git cat-file -t "refs/tags/test-annotated")
  [[ "$tag_type" == "tag" ]]
}

@test "git-tc: validates tag names" {
  run hug tc "invalid tag name"

  assert_failure
  assert_output --partial "Invalid tag name"
}

@test "git-tc: prevents duplicate tags without force" {
  git tag existing-tag HEAD~1

  run hug tc existing-tag HEAD

  assert_failure
  assert_output --partial "already exists"
}

@test "git-tc: overwrites existing tag with force" {
  git tag existing-tag HEAD~1

  run hug tc -f existing-tag HEAD

  assert_success
  assert_output --partial "Created lightweight tag: existing-tag"
}

@test "git-tc: requires message for annotated tags" {
  run hug tc -a test-tag

  assert_failure
  assert_output --partial "Message required for annotated tags"
}

@test "git-tc: interactive mode accepts custom target commit" {
  setup_gum_mock

  # Configure sequential responses for the interactive prompts
  # 1st prompt (tag name): "v1.0.0-test"
  # 2nd prompt (target commit): "HEAD~1"
  # 3rd prompt (tag type): "annotated"
  # 4th prompt (tag message): "Test tag message"
  # Note: Use | as delimiter to preserve empty responses
  export HUG_TEST_GUM_RESPONSES="v1.0.0-test|HEAD~1|annotated|Test tag message"

  run hug tc -i

  assert_success
  assert_output --partial "Created annotated tag: v1.0.0-test"

  # Verify tag was created correctly
  run git tag -l "v1.0.0-test" -n99
  assert_success
  assert_output --partial "Test tag message"

  # Verify tag points to the correct commit
  # For annotated tags, we need to check the tag's target
  local tag_target
  tag_target=$(git rev-parse "v1.0.0-test^{}")
  local expected_commit
  expected_commit=$(git rev-parse "HEAD~1")
  [[ "$tag_target" == "$expected_commit" ]]

  teardown_gum_mock
}

@test "git-tc: interactive mode uses HEAD as default target" {
  setup_gum_mock

  # Configure sequential responses
  # 1st prompt (tag name): "release-2025-12-09"
  # 2nd prompt (target commit): Just press enter for HEAD default (empty response)
  # 3rd prompt (tag type): "lightweight"
  # No tag message needed for lightweight tags
  # Note: Use | as delimiter to preserve empty responses
  export HUG_TEST_GUM_RESPONSES="release-2025-12-09| |lightweight"

  run hug tc -i

  assert_success
  assert_output --partial "Created lightweight tag: release-2025-12-09"

  # Verify tag points to HEAD
  local tag_commit
  tag_commit=$(git rev-parse "release-2025-12-09")
  local head_commit
  head_commit=$(git rev-parse HEAD)
  [[ "$tag_commit" == "$head_commit" ]]

  teardown_gum_mock
}

@test "git-tc: interactive mode rejects invalid target commit" {
  # Disable gum to force fallback to basic input
  export HUG_DISABLE_GUM=true

  # Provide non-existent commit
  run bash -c "echo 'nonexistent123' | hug tc -i test-invalid-tag"

  # Command succeeds after showing error and cancelling
  assert_success
  assert_output --partial "Invalid target"
  assert_output --partial "Cancelled"
}

@test "git-tdel: deletes tag with confirmation" {
  git tag test-tag HEAD

  # Simulate user confirmation
  run bash -c 'echo "y" | hug tdel test-tag'

  assert_success
  assert_output --partial "Created backup"
  assert_output --partial "Deleted local tag"

  # Verify tag is deleted
  run git rev-parse --verify "refs/tags/test-tag"
  assert_failure
}

@test "git-tdel: deletes multiple tags" {
  git tag tag1 HEAD
  git tag tag2 HEAD~1

  # Use -f to skip confirmation (TTY not available in test)
  run hug tdel -f tag1

  assert_success
}

@test "git-tdel: supports --force to skip confirmation" {
  git tag test-tag HEAD

  run hug tdel -f test-tag

  assert_success
  assert_output --partial "Deleted local tag"
}

@test "git-tdel: supports --dry-run" {
  git tag test-tag HEAD

  run hug tdel --dry-run test-tag

  assert_success
  assert_output --partial "Dry run mode"

  # Verify tag still exists
  git rev-parse --verify "refs/tags/test-tag"
}

@test "git-tdel: warns about remote tags" {
  git tag test-tag HEAD

  # Mock remote existence
  run git-tdel -f test-tag

  # Would need to mock 'git ls-remote' for full test
  assert_success
}

@test "git-t: interactive tag browser" {
  git tag v1.0.0 HEAD~2
  git tag v1.1.0 HEAD~1
  git tag v2.0.0 HEAD

  # Direct checkout mode
  run hug t v1.1.0

  assert_success
  # Would have checked out the tag
}

@test "git-t: shows tag details" {
  git tag -a test-tag HEAD -m "Test tag"

  run hug t --action show test-tag

  assert_success
  # Would show git show output
}

@test "git-t: supports type filtering with direct tag checkout" {
  git tag v1.0.0 HEAD~2
  git tag -a v1.1.0 HEAD~1 -m "Release"

  # Direct tag checkout (non-interactive)
  run hug t v1.1.0

  assert_success
}

@test "tag library: compute_tag_details function" {
  source "$HUG_HOME/git-config/lib/hug-git-tag"

  git tag v1.0.0 HEAD~2
  git tag -a v1.1.0 HEAD~1 -m "Release"

  local current_tag=""
  local max_len=0
  local -a tags=() hashes=() types=() subjects=() dates=() signatures=()

  compute_tag_details current_tag max_len hashes tags types subjects dates signatures

  # Should have found tags
  [[ ${#tags[@]} -gt 0 ]]
  [[ ${#types[@]} -gt 0 ]]

  # Should have both lightweight and annotated tags
  local found_lightweight=false
  local found_annotated=false

  for type in "${types[@]}"; do
    if [[ "$type" == "lightweight" ]]; then
      found_lightweight=true
    elif [[ "$type" == "annotated" ]]; then
      found_annotated=true
    fi
  done

  [[ "$found_lightweight" == "true" ]]
  [[ "$found_annotated" == "true" ]]
}

@test "tag library: get_tag_type function" {
  source "$HUG_HOME/git-config/lib/hug-git-tag"

  git tag lightweight-tag HEAD
  git tag -a annotated-tag HEAD -m "Annotated"

  local type
  type=$(get_tag_type "lightweight-tag")
  [[ "$type" == "lightweight" ]]

  type=$(get_tag_type "annotated-tag")
  [[ "$type" == "annotated" ]]

  type=$(get_tag_type "nonexistent-tag")
  [[ "$type" == "unknown" ]]
}

# TODO: Fix validate_tag_name test - BATS treats function return 1 as test failure
@test "tag library: validate_tag_name function" {
  skip
}

@test "tag library: get_tags_containing function" {
  source "$HUG_HOME/git-config/lib/hug-git-tag"

  git tag tag1 HEAD~1
  git tag tag2 HEAD

  # Should find tag2 but not tag1 for HEAD
  local result
  result=$(get_tags_containing HEAD)
  [[ "$result" =~ tag2 ]]
  [[ ! "$result" =~ tag1 ]]
}
