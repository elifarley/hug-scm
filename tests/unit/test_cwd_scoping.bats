#!/usr/bin/env bats
# Tests for --cwd scoping in file listing and git-w-discard command
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
# GIT COMMAND BEHAVIOR WITH -- . (validates our --cwd implementation)
################################################################################

@test "git diff --cached -- . scopes to current directory from root" {
  # From root, should see only root staged files
  mapfile -t files < <(git diff --cached --name-only -- .)
  
  # Should include all staged files when at root
  [[ " ${files[*]} " =~ " staged-root.txt " ]]
  [[ " ${files[*]} " =~ " src/components/staged-comp.js " ]]
}

@test "git diff --cached -- . scopes to subdirectory" {
  cd src/components
  mapfile -t files < <(git diff --cached --name-only -- .)
  
  # Should see only staged-comp.js, not root staged files (paths relative to .)
  assert_equal "${#files[@]}" 1
  [[ " ${files[*]} " =~ "staged-comp.js" ]]
  [[ ! " ${files[*]} " =~ "staged-root.txt" ]]
}

@test "git diff -- . scopes unstaged files to subdirectory" {
  cd src/components
  mapfile -t files < <(git diff --name-only -- .)
  
  # Should see only ComponentA.js (path relative to .)
  assert_equal "${#files[@]}" 1
  [[ " ${files[*]} " =~ "ComponentA.js" ]]
  [[ ! " ${files[*]} " =~ "root1.txt" ]]
}

@test "git status --porcelain -z -- . scopes to subdirectory" {
  cd src/components
  local count
  count=$(git status --porcelain=v1 -z -- . | tr '\0' '\n' | grep -c "^??")
  
  # Should see only untracked.js in this directory
  assert_equal "$count" 1
}

################################################################################
# hug w discard --cwd BEHAVIOR (default in interactive mode)
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

################################################################################
# SCOPING VERIFICATION TESTS
################################################################################

@test "git ls-files -- . scopes tracked files to subdirectory" {
  cd src/components
  mapfile -t files < <(git ls-files -- .)
  
  # Should see only files in this directory and subdirs (at least ComponentA and ComponentB)
  [[ ${#files[@]} -ge 2 ]]
  [[ " ${files[*]} " =~ " ComponentA.js " ]]
  [[ " ${files[*]} " =~ " ComponentB.js " ]]
  [[ ! " ${files[*]} " =~ " helper.js " ]]
  [[ ! " ${files[*]} " =~ " root1.txt " ]]
}

@test "git diff without -- . shows all unstaged files" {
  cd src/components
  mapfile -t files < <(git diff --name-only)
  
  # Should see files from entire repo (paths relative to repo root)
  [[ ${#files[@]} -gt 1 ]]
  # Files will be repo-root relative
  [[ " ${files[*]} " =~ " src/components/ComponentA.js " ]]
  [[ " ${files[*]} " =~ " root1.txt " ]] # root file visible
}

@test "scoped commands include child directories" {
  # Create nested structure
  mkdir -p src/components/buttons
  echo "button" > src/components/buttons/Button.js
  git add src/components/buttons/Button.js
  git commit -q -m "Add button"
  echo "modified" >> src/components/buttons/Button.js
  
  cd src/components
  mapfile -t files < <(git diff --name-only -- .)
  
  # Should include buttons/Button.js and ComponentA.js (paths relative to .)
  [[ " ${files[*]} " =~ "buttons/Button.js" ]]
  [[ " ${files[*]} " =~ "ComponentA.js" ]]
}

@test "scoped commands from src include multiple child dirs" {
  cd src
  mapfile -t files < <(git ls-files -- .)
  
  # Should include files from both components and utils
  [[ " ${files[*]} " =~ " components/ComponentA.js " ]]
  [[ " ${files[*]} " =~ " components/ComponentB.js " ]]
  [[ " ${files[*]} " =~ " utils/helper.js " ]]
  [[ " ${files[*]} " =~ " utils/validator.js " ]]
  
  # But not files from docs or root
  [[ ! " ${files[*]} " =~ " README.md " ]]
  [[ ! " ${files[*]} " =~ " root1.txt " ]]
}

################################################################################
# EDGE CASE TESTS
################################################################################

@test "git commands handle files with spaces in names" {
  cd src/components
  echo "content" > "file with spaces.js"
  git add "file with spaces.js"
  
  # Use null-delimited output to handle spaces correctly
  local output
  output=$(git diff --cached --name-only -z -- . | tr '\0' '\n')
  
  # Should include the file with spaces
  [[ "$output" =~ "file with spaces.js" ]]
}

@test "empty directory with scoped commands returns no results" {
  cd docs
  mapfile -t files < <(git diff --cached --name-only -- .)
  
  # docs has no staged files
  assert_equal "${#files[@]}" 0
}

@test "scoped commands work from deeply nested directory" {
  mkdir -p src/components/nested/deep
  echo "deep file" > src/components/nested/deep/file.js
  git add src/components/nested/deep/file.js
  git commit -q -m "Add deep file"
  echo "modified" >> src/components/nested/deep/file.js
  
  cd src/components/nested/deep
  mapfile -t files < <(git diff --name-only -- .)
  
  # Should see only file.js (no ComponentA.js from parent)
  assert_equal "${#files[@]}" 1
  [[ " ${files[*]} " =~ "file.js" ]]
  [[ ! " ${files[*]} " =~ "ComponentA.js" ]]
}
