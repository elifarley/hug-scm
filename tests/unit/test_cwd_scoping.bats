#!/usr/bin/env bats
# Tests for --cwd scoping in hug commands
# These tests verify that --cwd limits file listings to current directory and subdirectories

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
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

################################################################################
# hug w discard COMMAND TESTS WITH --cwd SCOPING
################################################################################

@test "hug w discard from subdirectory scopes to CWD by default" {
  cd src/components
  
  # Verify we have changes here
  run git diff --name-only -- .
  assert_output --partial "ComponentA.js"
  
  # Run discard with force flag to avoid interactive prompt
  # This should default to --cwd (local scope)
  run hug w discard -f ComponentA.js
  assert_success
  
  # ComponentA.js should be reset
  run git diff -- ComponentA.js
  assert_output ""
  
  # But root1.txt should still have changes (not affected)
  # Note: git diff outputs repo-relative paths when no -- . is used
  run git diff --name-only ../../root1.txt
  assert_output "root1.txt"
}

@test "hug w discard with explicit path works from subdirectory" {
  cd src/components
  
  # Discard specific file using relative path
  run hug w discard -f ComponentA.js
  assert_success
  
  # File should be clean
  run git diff ComponentA.js
  assert_output ""
}

@test "hug w discard with explicit parent path works from subdirectory" {
  cd src/components
  
  # Discard file in parent using relative path
  run hug w discard -f ../../root1.txt
  assert_success
  
  # root1.txt should be clean
  run git diff ../../root1.txt
  assert_output ""
}

@test "hug w discard --browse-root with explicit paths shows error" {
  # --browse-root should not be combinable with explicit paths
  run hug w discard --browse-root root1.txt
  assert_failure
  assert_output --partial "browse-root cannot be used with explicit paths"
}

@test "hug w discard --help shows browse-root option" {
  run hug w discard -h
  assert_success
  assert_output --partial "--browse-root"
  assert_output --partial "current directory"
}
