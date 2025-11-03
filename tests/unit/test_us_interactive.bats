#!/usr/bin/env bats
# Test for hug us interactive mode

load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
  
  # Create initial commit
  echo "initial" > README.md
  git add README.md
  git commit -q -m "Initial commit"
  
  # Stage a file for testing
  echo "new content" > newfile.txt
  git add newfile.txt
}

teardown() {
  cleanup_test_repo
}

@test "hug us: mapfile correctly captures staged files" {
  # This test verifies that mapfile correctly captures staged files
  
  # First verify the file is actually staged
  run git diff --cached --name-only
  assert_success
  assert_output "newfile.txt"
  
  # Now test the exact pattern used in git-us
  run bash -c '
    staged_files=()
    mapfile -t staged_files < <(
      git diff --cached --name-only 2>/dev/null || true
    )
    
    echo "Count: ${#staged_files[@]}"
    for file in "${staged_files[@]}"; do
      echo "File: [$file]"
    done
  '
  
  assert_success
  assert_output --partial "Count: 1"
  assert_output --partial "File: [newfile.txt]"
}

@test "hug us: formatted options array is built correctly" {
  # Test that the formatted_options array is built correctly
  
  run bash -c '
    source "$HUG_HOME/git-config/lib/hug-common"
    source "$HUG_HOME/git-config/lib/hug-git-kit"
    
    staged_files=()
    mapfile -t staged_files < <(
      git diff --cached --name-only 2>/dev/null || true
    )
    
    formatted_options=()
    for file in "${staged_files[@]}"; do
      status=$(git diff --cached --name-status "$file" 2>/dev/null | cut -f1 || echo "M")
      
      case "$status" in
        A) status_text="${GREEN}new${NC}" ;;
        M) status_text="${YELLOW}modified${NC}" ;;
        D) status_text="${RED}deleted${NC}" ;;
        R*) status_text="${BLUE}renamed${NC}" ;;
        C*) status_text="${BLUE}copied${NC}" ;;
        *) status_text="${GREY}changed${NC}" ;;
      esac
      
      formatted="${file} ${status_text}"
      formatted_options+=("$formatted")
    done
    
    echo "Formatted count: ${#formatted_options[@]}"
    for opt in "${formatted_options[@]}"; do
      echo "Option: [$opt]"
    done
  '
  
  assert_success
  assert_output --partial "Formatted count: 1"
  assert_output --partial "Option: [newfile.txt"
}


@test "hug us: handles edge case with empty array elements" {
  # Test defensive handling of potential empty elements
  
  run bash -c '
    source "$HUG_HOME/git-config/lib/hug-common"
    source "$HUG_HOME/git-config/lib/hug-git-kit"
    
    # Simulate a scenario with an empty element
    staged_files=("newfile.txt" "" "another.txt")
    
    formatted_options=()
    for file in "${staged_files[@]}"; do
      [[ -z "$file" ]] && continue
      
      status=$(git diff --cached --name-status "$file" 2>/dev/null | cut -f1 || echo "M")
      
      case "$status" in
        A) status_text="${GREEN}new${NC}" ;;
        M) status_text="${YELLOW}modified${NC}" ;;
        *) status_text="${GREY}changed${NC}" ;;
      esac
      
      formatted="${file} ${status_text}"
      [[ -n "$formatted" ]] && formatted_options+=("$formatted")
    done
    
    echo "Formatted count: ${#formatted_options[@]}"
    # Should only have 2 elements (skipped the empty one)
    [[ ${#formatted_options[@]} -eq 2 ]] && echo "PASS" || echo "FAIL"
  '
  
  assert_success
  assert_output --partial "Formatted count: 2"
  assert_output --partial "PASS"
}
