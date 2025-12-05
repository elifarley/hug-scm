#!/usr/bin/env bats
# Tests for hug init command

load ../test_helper

setup() {
    require_hug
    TEST_INIT_DIR=$(create_temp_repo_dir)
    mkdir -p "$TEST_INIT_DIR"
}

teardown() {
    rm -rf "$TEST_INIT_DIR"
}

@test "hug init - shows usage with --help" {
    run hug init --help
    assert_success
    assert_output --partial "Usage: hug init"
    assert_output --partial "Examples:"
}

@test "hug init - initializes Git repo in current directory with --no-status" {
    cd "$TEST_INIT_DIR"
    run hug init --no-status
    assert_success
    assert_output --partial "Initializing Git repository"
    assert_output --partial "Initialized Git repository in '.'"
    assert_dir_exists "$TEST_INIT_DIR/.git"

    # Check that default branch is 'main'
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
    [[ "$branch" == "main" ]]
}

@test "hug init - initializes Git repo in new directory" {
    cd "$TEST_INIT_DIR"
    run hug init --no-status my-repo
    assert_success
    assert_output --partial "Initializing Git repository"
    assert_output --partial "Initialized Git repository in 'my-repo'"
    assert_dir_exists "$TEST_INIT_DIR/my-repo/.git"

    # Check that default branch is 'main'
    cd "$TEST_INIT_DIR/my-repo"
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
    [[ "$branch" == "main" ]]
}

@test "hug init - shows status message on empty repo when status enabled" {
    cd "$TEST_INIT_DIR"
    run hug init test-status
    assert_success
    assert_output --partial "Initialized Git repository"
    assert_output --partial "Empty repository. Create your first commit to see status."
}

@test "hug init - defaults to Git" {
    cd "$TEST_INIT_DIR"
    run hug init --no-status
    assert_success
    assert_output --partial "Initializing Git repository"
    assert_dir_exists "$TEST_INIT_DIR/.git"
}

@test "hug init - forces Git with --git flag" {
    cd "$TEST_INIT_DIR"
    run hug init --git --no-status my-git-repo
    assert_success
    assert_output --partial "Initializing Git repository"
    assert_dir_exists "$TEST_INIT_DIR/my-git-repo/.git"
}

@test "hug init - passes through git options" {
    cd "$TEST_INIT_DIR"
    run hug init --git --no-status bare-repo --bare
    assert_success
    assert_output --partial "Initialized Git repository"
    assert_dir_exists "$TEST_INIT_DIR/bare-repo"
    # Check for bare repo markers (objects, refs, HEAD in root)
    assert_file_exists "$TEST_INIT_DIR/bare-repo/HEAD"
    assert_dir_exists "$TEST_INIT_DIR/bare-repo/objects"
    assert_dir_exists "$TEST_INIT_DIR/bare-repo/refs"
}

@test "hug init - errors when already initialized" {
    cd "$TEST_INIT_DIR"
    run hug init --no-status
    assert_success
    
    # Try to init again
    run hug init --no-status
    assert_failure
    assert_output --partial "Already a Git repository"
}

@test "hug init - errors when directory already initialized" {
    cd "$TEST_INIT_DIR"
    run hug init --no-status my-repo
    assert_success
    
    # Try to init the same directory again
    run hug init --no-status my-repo
    assert_failure
    assert_output --partial "Already a Git repository"
}

@test "hug init - passes through initial-branch option" {
    cd "$TEST_INIT_DIR"
    run hug init --no-status --initial-branch=develop test-develop
    assert_success

    # Check the branch name
    cd "$TEST_INIT_DIR/test-develop"
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
    [[ "$branch" == "develop" ]]
}

@test "hug init - default is main branch but can be overridden" {
    cd "$TEST_INIT_DIR"

    # First verify default is main
    run hug init --no-status default-main-repo
    assert_success
    cd "$TEST_INIT_DIR/default-main-repo"
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
    [[ "$branch" == "main" ]]
    cd ..

    # Then verify override works
    run hug init --no-status --initial-branch=feature custom-branch-repo
    assert_success
    cd "$TEST_INIT_DIR/custom-branch-repo"
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
    [[ "$branch" == "feature" ]]
}

@test "hug init - supports Mercurial with --hg flag" {
    # Skip test if hg is not installed
    if ! command -v hg >/dev/null 2>&1; then
        skip "Mercurial is not installed"
    fi
    
    cd "$TEST_INIT_DIR"
    run hug init --hg --no-status hg-repo
    assert_success
    assert_output --partial "Initializing Mercurial repository"
    assert_output --partial "Initialized Mercurial repository"
    assert_dir_exists "$TEST_INIT_DIR/hg-repo/.hg"
}

@test "hug init - errors when hg not installed but --hg specified" {
    # Skip test if hg is actually installed
    if command -v hg >/dev/null 2>&1; then
        skip "Mercurial is installed"
    fi
    
    cd "$TEST_INIT_DIR"
    run hug init --hg --no-status
    assert_failure
    assert_output --partial "not found in PATH"
}

@test "hug init - creates directory if it doesn't exist" {
    cd "$TEST_INIT_DIR"
    [[ ! -d "$TEST_INIT_DIR/new-dir" ]]
    
    run hug init --no-status new-dir
    assert_success
    assert_dir_exists "$TEST_INIT_DIR/new-dir"
    assert_dir_exists "$TEST_INIT_DIR/new-dir/.git"
}

@test "hug init - can init in subdirectory" {
    cd "$TEST_INIT_DIR"
    mkdir -p subdir
    cd subdir
    
    run hug init --no-status
    assert_success
    assert_dir_exists "$TEST_INIT_DIR/subdir/.git"
}

@test "hug init - handles path with spaces" {
    cd "$TEST_INIT_DIR"
    run hug init --no-status "my repo with spaces"
    assert_success
    assert_dir_exists "$TEST_INIT_DIR/my repo with spaces/.git"
}

@test "hug init - status works after first commit" {
    cd "$TEST_INIT_DIR"
    hug init --no-status test-repo
    cd test-repo
    
    # Create a commit
    git config --local user.email "test@hug-scm.test"
    git config --local user.name "Hug Test"
    echo "test" > test.txt
    git add test.txt
    git commit -m "Initial commit"
    
    # Now status should work
    run hug s
    assert_success
    assert_output --partial "HEAD:"
}

@test "hug init - combined flags order doesn't matter" {
    cd "$TEST_INIT_DIR"
    run hug init --no-status --git test1
    assert_success
    
    run hug init --git --no-status test2
    assert_success
}

@test "hug init - multiple options passed through correctly" {
    cd "$TEST_INIT_DIR"
    # Test that we can pass multiple git options
    run hug init --no-status test-repo --bare --shared
    assert_success
    assert_dir_exists "$TEST_INIT_DIR/test-repo"
}
