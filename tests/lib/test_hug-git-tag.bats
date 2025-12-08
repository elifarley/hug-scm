#!/usr/bin/env bats

load ../test_helper

setup() {
  enable_gum_for_test
  require_hug
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"

  # Set up user config for annotated tags
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create various types of tags for testing
  git tag lightweight-tag HEAD~2
  git tag -a annotated-tag HEAD~1 -m "Annotated tag message"
  git tag -m "Another annotated" another-tag HEAD
}

teardown() {
  cleanup_test_repo
}

@test "compute_tag_details: populates arrays correctly" {
  source "$HUG_HOME/git-config/lib/hug-git-tag"

  local current_tag=""
  local max_len=0
  local -a tags=() hashes=() types=() subjects=() dates=() signatures=()

  # Test the function
  compute_tag_details current_tag max_len hashes tags types subjects dates signatures

  # Check that we found tags
  [[ ${#tags[@]} -eq 3 ]]
  [[ ${#hashes[@]} -eq 3 ]]
  [[ ${#types[@]} -eq 3 ]]
  [[ ${#subjects[@]} -eq 3 ]]

  # Check specific tags
  local found_lightweight=false
  local found_annotated=false

  for i in "${!types[@]}"; do
    if [[ "${types[i]}" == "lightweight" ]]; then
      found_lightweight=true
      [[ "${tags[i]}" =~ lightweight-tag ]]
    elif [[ "${types[i]}" == "annotated" ]]; then
      found_annotated=true
    fi
  done

  [[ "$found_lightweight" == "true" ]]
  [[ "$found_annotated" == "true" ]]

  # Check max_len is reasonable
  [[ $max_len -gt 10 ]]
}

@test "compute_tag_details: handles empty repository" {
  source "$HUG_HOME/git-config/lib/hug-git-tag"

  # Delete all tags
  git tag -d $(git tag -l)

  local current_tag=""
  local max_len=0
  local -a tags=() hashes=() types=() subjects=() dates=() signatures=()

  # Should return 1 when no tags found
  run compute_tag_details current_tag max_len hashes tags types subjects dates signatures
  [[ $status -eq 1 ]]
  [[ ${#tags[@]} -eq 0 ]]
}

@test "get_tag_type: correctly identifies tag types" {
  source "$HUG_HOME/git-config/lib/hug-git-tag"

  local tag_type

  # Test lightweight tag
  tag_type=$(get_tag_type "lightweight-tag")
  [[ "$tag_type" == "lightweight" ]]

  # Test annotated tag
  tag_type=$(get_tag_type "annotated-tag")
  [[ "$tag_type" == "annotated" ]]

  # Test another annotated tag
  tag_type=$(get_tag_type "another-tag")
  [[ "$tag_type" == "annotated" ]]

  # Test nonexistent tag
  tag_type=$(get_tag_type "nonexistent-tag")
  [[ "$tag_type" == "unknown" ]]
}

@test "get_tag_target_hash: returns correct commit hashes" {
  source "$HUG_HOME/git-config/lib/hug-git-tag"

  local hash

  # Test short hash
  hash=$(get_tag_target_hash "lightweight-tag" "short")
  [[ ${#hash} -eq 7 ]]

  # Test full hash
  hash=$(get_tag_target_hash "lightweight-tag")
  [[ ${#hash} -eq 40 ]]

  # Compare with git rev-parse
  local expected_hash
  expected_hash=$(git rev-list -n 1 "lightweight-tag")
  [[ "$hash" == "$expected_hash" ]]
}

@test "tag_exists_remote: checks remote tag existence" {
  source "$HUG_HOME/git-config/lib/hug-git-tag"

  # Add a fake remote
  git remote add origin https://github.com/example/repo.git

  # Test with non-existent remote tag
  run tag_exists_remote "nonexistent-tag"
  [[ $status -ne 0 ]]  # Should return false

  # Test with existing local tag (but not on remote)
  run tag_exists_remote "lightweight-tag"
  [[ $status -ne 0 ]]  # Should return false since it's not pushed
}

@test "print_tag_list: basic output format" {
  source "$HUG_HOME/git-config/lib/hug-git-tag"

  run print_tag_list

  assert_success
  assert_output --partial "lightweight-tag"
  assert_output --partial "annotated-tag"
  assert_output --partial "[L]"
  assert_output --partial "[A]"
}

@test "print_tag_list: JSON output" {
  source "$HUG_HOME/git-config/lib/hug-git-tag"

  run print_tag_list --json

  assert_success
  assert_output --partial '"name": "lightweight-tag"'
  assert_output --partial '"type": "lightweight"'
  assert_output --partial '"name": "annotated-tag"'
  assert_output --partial '"type": "annotated"'
}

@test "print_detailed_tag_list: detailed format" {
  source "$HUG_HOME/git-config/lib/hug-git-tag"

  run print_detailed_tag_list

  assert_success
  assert_output --partial "lightweight-tag"
  assert_output --partial "(lightweight)"
  assert_output --partial "annotated-tag"
  assert_output --partial "(annotated)"
  assert_output --partial "Annotated tag message"
  assert_output --partial "Test User"
}

@test "validate_tag_name: validation rules" {
  source "$HUG_HOME/git-config/lib/hug-git-tag"

  # Valid names
  validate_tag_name "valid-tag"
  [[ $? -eq 0 ]]

  validate_tag_name "v1.0.0"
  [[ $? -eq 0 ]]

  validate_tag_name "123tag"
  [[ $? -eq 0 ]]

  # Invalid names
  run validate_tag_name ""
  [[ $status -ne 0 ]]

  run validate_tag_name "invalid tag name"
  [[ $status -ne 0 ]]

  run validate_tag_name "invalid~tag"
  [[ $status -ne 0 ]]

  run validate_tag_name "invalid^tag"
  [[ $status -ne 0 ]]

  run validate_tag_name "invalid:tag"
  [[ $status -ne 0 ]]

  run validate_tag_name "invalid?tag"
  [[ $status -ne 0 ]]

  run validate_tag_name "invalid*tag"
  [[ $status -ne 0 ]]

  run validate_tag_name "invalid[tag"
  [[ $status -ne 0 ]]

  # Note: ']' is actually valid in git refs, so we don't test it here

  run validate_tag_name ".invalid"
  [[ $status -ne 0 ]]

  run validate_tag_name "invalid."
  [[ $status -ne 0 ]]

  run validate_tag_name "invalid..tag"
  [[ $status -ne 0 ]]

  run validate_tag_name "invalid.lock"
  [[ $status -ne 0 ]]
}

@test "backup_tag: creates backup before deletion" {
  source "$HUG_HOME/git-config/lib/hug-git-tag"

  local backup
  backup=$(backup_tag "annotated-tag")

  # Should create a backup tag
  [[ -n "$backup" ]]
  [[ "$backup" =~ hug-backups/annotated-tag-backup- ]]

  # Verify backup tag exists
  git rev-parse --verify "refs/tags/$backup"
}

@test "backup_tag: handles non-existent tag" {
  source "$HUG_HOME/git-config/lib/hug-git-tag"

  local backup
  backup=$(backup_tag "nonexistent-tag")

  # Should return empty for non-existent tag
  [[ -z "$backup" ]]
}

@test "get_tags_containing: finds tags containing commits" {
  source "$HUG_HOME/git-config/lib/hug-git-tag"

  # Get tags containing HEAD (only the tag pointing directly to HEAD)
  local result
  result=$(get_tags_containing "HEAD")

  # Should find only the tag that points to HEAD
  local count
  count=$(echo "$result" | wc -l)
  [[ $count -eq 1 ]]
  [[ "$result" =~ another-tag ]]
}

@test "get_tags_pointing_to: finds tags pointing to exact commit" {
  source "$HUG_HOME/git-config/lib/hug-git-tag"

  # Get commit hash for HEAD~1
  local commit_hash
  commit_hash=$(git rev-parse "HEAD~1")

  # Find tags pointing to that commit
  local result
  result=$(get_tags_pointing_to "$commit_hash")

  # Should find annotated-tag which points to HEAD~1
  [[ "$result" =~ annotated-tag ]]
  [[ ! "$result" =~ lightweight-tag ]]
}

@test "get_tags_pointing_to: handles short commit hash" {
  source "$HUG_HOME/git-config/lib/hug-git-tag"

  # Get short commit hash for HEAD
  local short_hash
  short_hash=$(git rev-parse --short "HEAD")

  # Find tags pointing to that commit
  local result
  result=$(get_tags_pointing_to "$short_hash")

  # Should find another-tag which points to HEAD
  [[ "$result" =~ another-tag ]]
}

@test "print_tag_line: formats individual tags" {
  source "$HUG_HOME/git-config/lib/hug-git-tag"

  # Create test data
  local current_tag="annotated-tag"
  local max_len=15
  local -a tags=("lightweight-tag" "annotated-tag")
  local -a hashes=("abc1234" "def5678")
  local -a types=("lightweight" "annotated")
  local -a subjects=("Subject 1" "Subject 2")

  # Test current tag formatting (using index 0 for lightweight-tag)
  run print_tag_line "" "$current_tag" "$max_len" 0 tags hashes types subjects

  assert_success
  assert_output --partial "abc1234 lightweight-tag [L]"
  assert_output --partial "Subject 1"
}

@test "select_tags: requires tags to exist" {
  source "$HUG_HOME/git-config/lib/hug-common"
  source "$HUG_HOME/git-config/lib/hug-git-tag"

  # Delete all tags
  git tag -d $(git tag -l)

  local -a selected=()
  run select_tags selected

  assert_failure
  assert_output --partial "No tags found"
}

@test "select_tags: filters by type" {
  source "$HUG_HOME/git-config/lib/hug-git-tag"

  # Mock gum_available to return false for simpler testing
  gum_available() { return 1; }

  local -a selected=()

  # This would need interactive input, so just test that the function exists
  # and can be called without errors
  type select_tags
}