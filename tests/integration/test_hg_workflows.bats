#!/usr/bin/env bats
# Integration tests for Mercurial workflows

# Load test helpers
load '../test_helper'

setup() {
  require_hg
  require_hug
  TEST_REPO=$(create_test_hg_repo)
  cd "$TEST_REPO"
  # Update PATH to include hg-config bin
  export PATH="$PROJECT_ROOT/hg-config/bin:$PATH"
}

teardown() {
  cleanup_test_repo
}

@test "Complete workflow: create, modify, commit, view history" {
  # Create a new file
  echo "Feature A" > feature_a.txt
  
  # Add and commit
  run hug a feature_a.txt
  assert_success
  
  run hug c -m "Add feature A"
  assert_success
  
  # Modify existing file
  echo "Updated" >> README.md
  
  # Commit again
  run hug c -m "Update README"
  assert_success
  
  # View history
  run hug l
  assert_success
  assert_output --partial "Add feature A"
  assert_output --partial "Update README"
}

@test "Bookmark workflow: create, switch, list" {
  # Create a new bookmark
  run hug bc feature-branch
  assert_success
  
  # Make a commit
  echo "New feature" > new_feature.txt
  hug a new_feature.txt
  run hug c -m "Add new feature"
  assert_success
  
  # Create another bookmark from initial commit
  hug b default
  run hug bc another-feature
  assert_success
  
  # List bookmarks
  run hug bl
  assert_success
  assert_output --partial "feature-branch"
  assert_output --partial "another-feature"
  
  # Switch back
  run hug b feature-branch
  assert_success
  
  # Verify file exists
  assert_file_exists new_feature.txt
}

@test "Working directory cleanup workflow" {
  # Create some changes
  echo "Modified" >> README.md
  echo "New file" > temp.txt
  hug a temp.txt
  echo "Untracked" > untracked.txt
  
  # Verify we have changes
  run hg status
  assert_success
  [[ -n "$output" ]]
  
  # Discard only modified files
  run hug w discard -f README.md
  assert_success
  
  # Verify discard worked
  run cat README.md
  assert_output "# Test Repository"
  
  # Purge untracked
  run hug w purge -f
  assert_success
  
  # Verify untracked file removed
  assert_file_not_exists untracked.txt
  
  # temp.txt should still exist (it was added)
  assert_file_exists temp.txt
}

@test "Complete cleanup with zap" {
  # Create various changes
  echo "Modified" >> README.md
  echo "New file" > new.txt
  hug a new.txt
  echo "Untracked" > untracked.txt
  
  # Zap all
  run hug w zap-all -f
  assert_success
  
  # Verify everything is clean
  run hg status
  [[ -z "$output" ]]
  
  # Verify untracked removed
  assert_file_not_exists untracked.txt
  
  # Verify modifications reverted
  run cat README.md
  assert_output "# Test Repository"
}

@test "Add all and commit workflow" {
  # Create multiple new files
  echo "File 1" > file1.txt
  echo "File 2" > file2.txt
  echo "File 3" > file3.txt
  
  # Add all and commit
  run hug caa -m "Add all files"
  assert_success
  
  # Verify all files committed
  run hg log -r . --template '{files}\n'
  assert_output --partial "file1.txt"
  assert_output --partial "file2.txt"
  assert_output --partial "file3.txt"
}

@test "Status variants: s, sl, sla" {
  # Create different types of files
  echo "Modified" >> README.md
  echo "New" > new.txt
  hug a new.txt
  echo "Untracked" > untracked.txt
  
  # Basic status
  run hug s
  assert_success
  
  # Status without untracked (should not show untracked.txt)
  run hug sl
  assert_success
  refute_output --partial "untracked.txt"
  
  # Full status (should show everything)
  run hug sla
  assert_success
  assert_output --partial "untracked.txt"
}

@test "Log variants: l, ll, la" {
  # Create some history
  echo "Commit 1" > file1.txt
  hug a file1.txt
  hug c -m "First commit"
  
  echo "Commit 2" > file2.txt
  hug a file2.txt
  hug c -m "Second commit"
  
  # Basic log
  run hug l
  assert_success
  assert_output --partial "First commit"
  assert_output --partial "Second commit"
  
  # Detailed log
  run hug ll
  assert_success
  assert_output --partial "First commit"
  
  # All branches log
  run hug la
  assert_success
  assert_output --partial "First commit"
}

@test "Multi-SCM detection: hug works in correct repo type" {
  # We're in a Mercurial repo
  run hug s
  assert_success
  
  # Create a temp git repo to test detection
  local git_repo
  git_repo=$(mktemp -d)
  (
    cd "$git_repo"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    echo "test" > test.txt
    git add test.txt
    git commit -q -m "test"
    
    # Update PATH to include both git and hg config
    export PATH="$PROJECT_ROOT/git-config/bin:$PROJECT_ROOT/hg-config/bin:$PATH"
    
    # Hug should work here too (using git backend)
    run hug s
    [[ $status -eq 0 ]]
  )
  rm -rf "$git_repo"
}

@test "Error handling: not in a repository" {
  # Go to temp directory without any repo
  local temp_dir
  temp_dir=$(mktemp -d)
  cd "$temp_dir"
  
  # Should get an error
  run hug s
  assert_failure
  assert_output --partial "Not in a"
  
  rm -rf "$temp_dir"
}
