#!/usr/bin/env bats
# Tests for --cwd scoping in newly updated commands
# These tests verify that commands work correctly when run from subdirectories

# Load test helpers
load '../test_helper'

# Helper function to create a test repo with subdirectory structure
create_test_repo_with_subdirs() {
  local test_repo
  test_repo=$(create_test_repo)
  
  (
    cd "$test_repo" || exit 1
    
    # Create directory structure
    mkdir -p src/components
    mkdir -p src/utils
    mkdir -p docs
    
    # Create files in root
    echo "root file 1" > root1.txt
    echo "root file 2" > root2.txt
    
    # Create files in src/components
    echo "component A" > src/components/ComponentA.js
    echo "component B" > src/components/ComponentB.js
    
    # Create files in src/utils
    echo "util 1" > src/utils/helper.js
    echo "util 2" > src/utils/validator.js
    
    # Create files in docs
    echo "readme" > docs/README.md
    echo "guide" > docs/guide.md
    
    # Commit all
    git add -A
    git commit -q -m "Initial structure"
    
    # Make some changes in different locations
    # Root changes
    echo "modified root 1" >> root1.txt
    echo "staged root" > staged-root.txt
    git add staged-root.txt
    
    # src/components changes
    echo "modified component A" >> src/components/ComponentA.js
    echo "staged component" > src/components/staged-comp.js
    git add src/components/staged-comp.js
    echo "untracked component" > src/components/untracked.js
    
    # src/utils changes
    echo "modified helper" >> src/utils/helper.js
    
    # docs changes
    echo "modified readme" >> docs/README.md
  )
  
  echo "$test_repo"
}

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_subdirs)
  cd "$TEST_REPO" || exit 1
}

teardown() {
  cleanup_test_repo
}

################################################################################
# hug a COMMAND TESTS - staging files
################################################################################

@test "hug a works from subdirectory with explicit file" {
  cd src/components
  
  # Stage a file from the current subdirectory
  run hug a ComponentA.js
  assert_success
  
  # Verify file is staged
  run git diff --cached --name-only
  assert_output --partial "ComponentA.js"
}

@test "hug a works from subdirectory with parent directory file" {
  cd src/components
  
  # Stage a file from parent directory using relative path
  run hug a ../../root1.txt
  assert_success
  
  # Verify file is staged
  run git diff --cached --name-only
  assert_output --partial "root1.txt"
}

################################################################################
# hug ss, hug su, hug sw COMMAND TESTS - viewing changes
################################################################################

@test "hug ss shows staged changes from subdirectory" {
  cd src/components
  
  # View staged changes
  run hug ss
  assert_success
  assert_output --partial "staged-comp.js"
}

@test "hug su shows unstaged changes from subdirectory" {
  cd src/components
  
  # View unstaged changes  
  run hug su
  assert_success
  assert_output --partial "ComponentA.js"
}

@test "hug sw shows working directory changes from subdirectory" {
  cd src/components
  
  # View all working directory changes
  run hug sw
  assert_success
  # Should show both staged and unstaged changes
  assert_output --partial "ComponentA.js"
}

################################################################################
# FILE COMMAND TESTS - file analysis commands work from subdirectories
################################################################################

@test "hug llf works from subdirectory with explicit file" {
  cd src/components
  
  # View log for file in current directory
  run hug llf ComponentA.js
  assert_success
  assert_output --partial "Initial structure"
}

@test "hug llf works from subdirectory with parent directory file" {
  cd src/components
  
  # View log for file in parent directory
  run hug llf ../../root1.txt
  assert_success
  assert_output --partial "Initial structure"
}

@test "hug fblame works from subdirectory with explicit file" {
  cd src/components
  
  # Blame file in current directory
  run hug fblame ComponentA.js
  assert_success
}

@test "hug fcon works from subdirectory with explicit file" {
  cd src/components
  
  # List contributors for file
  run hug fcon ComponentA.js
  assert_success
}

@test "hug fa works from subdirectory with explicit file" {
  cd src/components
  
  # Count commits per author
  run hug fa ComponentA.js
  assert_success
}

################################################################################
# HELP TEXT TESTS - verify --browse-root is documented
################################################################################

@test "hug a -h shows browse-root option" {
  run hug a -h
  assert_success
  assert_output --partial "--browse-root"
  assert_output --partial "current directory"
}

@test "hug ss -h shows browse-root option" {
  run hug ss -h
  assert_success
  assert_output --partial "--browse-root"
  assert_output --partial "current directory"
}

@test "hug llf -h shows browse-root option" {
  run hug llf -h
  assert_success
  assert_output --partial "--browse-root"
  assert_output --partial "current directory"
}

@test "hug fblame -h shows browse-root option" {
  run hug fblame -h
  assert_success
  assert_output --partial "--browse-root"
  assert_output --partial "current directory"
}

@test "hug lc -h shows browse-root option" {
  run hug lc -h
  assert_success
  assert_output --partial "--browse-root"
  assert_output --partial "current directory"
}
