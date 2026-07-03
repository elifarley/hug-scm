#!/usr/bin/env bats
# Tests for hug clone command

load ../test_helper

setup() {
    require_hug
    TEST_CLONE_DIR=$(create_temp_repo_dir)
    mkdir -p "$TEST_CLONE_DIR"
}

teardown() {
    rm -rf "$TEST_CLONE_DIR"
}

# Helper function to create a bare repo for testing
create_test_remote() {
    local remote_path="$1"
    mkdir -p "$remote_path"
    cd "$remote_path"
    git init --bare
}

# Helper function to create a repo with content
create_test_repo_with_content() {
    local repo_path="$1"
    mkdir -p "$repo_path"
    cd "$repo_path"
    git init -q --initial-branch=main
    git config --local user.email "test@hug-scm.test"
    git config --local user.name "Hug Test"
    echo "test content" > test.txt
    git add test.txt
    git commit -q -m "Initial commit"
}

@test "hug clone - shows usage with no arguments" {
    run hug clone
    assert_failure
    assert_output --partial "Usage: hug clone"
}

@test "hug clone - shows help with --help" {
    run hug clone --help
    assert_success
    assert_output --partial "Usage: hug clone"
    assert_output --partial "Examples:"
}

@test "hug clone - auto-detects Git from .git URL" {
    local remote_repo="$TEST_CLONE_DIR/remote.git"
    create_test_repo_with_content "$TEST_CLONE_DIR/source"
    cd "$TEST_CLONE_DIR/source"
    git clone --bare . "$remote_repo"
    
    cd "$TEST_CLONE_DIR"
    run hug clone --no-status "file://$remote_repo" cloned
    assert_success
    assert_output --partial "Detected: Git"
    assert_output --partial "Cloning with git"
    assert_output --partial "Cloned successfully"
    assert_dir_exists "$TEST_CLONE_DIR/cloned"
}

@test "hug clone - auto-detects Git from github.com URL pattern" {
    # This test verifies URL detection without actually cloning
    # We'll use --git flag to force Git and verify the detection message isn't shown
    cd "$TEST_CLONE_DIR"
    
    # Note: We can't actually clone from GitHub without network, but we can test
    # that the URL pattern is recognized. The clone will fail due to network,
    # but we should see the "Detected: Git" message before it fails.
    # For this test, we'll create a local repo with a github-like name
    local fake_github="$TEST_CLONE_DIR/github.com-user-repo"
    create_test_repo_with_content "$fake_github"
    
    cd "$TEST_CLONE_DIR"
    run hug clone --no-status "file://$fake_github" cloned-gh
    assert_success
    # Should auto-detect Git from the pattern
    assert_output --partial "Cloning with git"
}

@test "hug clone - forces Git with --git flag" {
    local remote_repo="$TEST_CLONE_DIR/remote"
    create_test_repo_with_content "$remote_repo"
    
    cd "$TEST_CLONE_DIR"
    run hug clone --git --no-status "file://$remote_repo" cloned
    assert_success
    assert_output --partial "Cloning with git"
    refute_output --partial "Detected:"
    assert_dir_exists "$TEST_CLONE_DIR/cloned"
}

@test "hug clone - clones to default directory name" {
    local remote_repo="$TEST_CLONE_DIR/myrepo.git"
    create_test_repo_with_content "$TEST_CLONE_DIR/source"
    cd "$TEST_CLONE_DIR/source"
    git clone --bare . "$remote_repo"
    
    cd "$TEST_CLONE_DIR"
    run hug clone --git --no-status "file://$remote_repo"
    assert_success
    assert_dir_exists "$TEST_CLONE_DIR/myrepo"
}

@test "hug clone - clones to specified directory" {
    local remote_repo="$TEST_CLONE_DIR/remote.git"
    create_test_repo_with_content "$TEST_CLONE_DIR/source"
    cd "$TEST_CLONE_DIR/source"
    git clone --bare . "$remote_repo"
    
    cd "$TEST_CLONE_DIR"
    run hug clone --git --no-status "file://$remote_repo" custom-name
    assert_success
    assert_dir_exists "$TEST_CLONE_DIR/custom-name"
}

@test "hug clone - passes through git options" {
    local remote_repo="$TEST_CLONE_DIR/remote.git"
    create_test_repo_with_content "$TEST_CLONE_DIR/source"
    cd "$TEST_CLONE_DIR/source"
    # Create multiple commits for depth testing
    echo "content2" > test2.txt
    git add test2.txt
    git commit -m "Second commit"
    echo "content3" > test3.txt
    git add test3.txt
    git commit -m "Third commit"
    git clone --bare . "$remote_repo"
    
    cd "$TEST_CLONE_DIR"
    run hug clone --git --no-status "file://$remote_repo" shallow --depth 1
    assert_success
    assert_dir_exists "$TEST_CLONE_DIR/shallow"
    
    # Verify shallow clone (should have only 1 commit)
    cd "$TEST_CLONE_DIR/shallow"
    commit_count=$(git rev-list --count HEAD)
    [[ "$commit_count" -eq 1 ]]
}

@test "hug clone - runs status by default after clone" {
    local remote_repo="$TEST_CLONE_DIR/remote.git"
    create_test_repo_with_content "$TEST_CLONE_DIR/source"
    cd "$TEST_CLONE_DIR/source"
    git clone --bare . "$remote_repo"
    
    cd "$TEST_CLONE_DIR"
    run hug clone --git "file://$remote_repo" with-status
    assert_success
    assert_output --partial "Cloned successfully"
    # Status output should be present (branch name or HEAD info)
    assert_output --partial "HEAD:"
}

@test "hug clone - skips status with --no-status flag" {
    local remote_repo="$TEST_CLONE_DIR/remote.git"
    create_test_repo_with_content "$TEST_CLONE_DIR/source"
    cd "$TEST_CLONE_DIR/source"
    git clone --bare . "$remote_repo"
    
    cd "$TEST_CLONE_DIR"
    run hug clone --git --no-status "file://$remote_repo" no-status
    assert_success
    assert_output --partial "Cloned successfully"
    # Should not have excessive output from status
    refute_output --partial "Changes"
}

@test "hug clone - fails gracefully when VCS not found" {
    # Try to clone with hg when it's not installed (likely scenario)
    cd "$TEST_CLONE_DIR"
    
    # Skip test if hg is actually installed
    if command -v hg >/dev/null 2>&1; then
        skip "Mercurial is installed"
    fi
    
    run hug clone --hg "http://example.com/repo" test
    assert_failure
    assert_output --partial "not found in PATH"
}

@test "hug clone - prompts when directory exists (simulated)" {
    local remote_repo="$TEST_CLONE_DIR/remote.git"
    create_test_repo_with_content "$TEST_CLONE_DIR/source"
    cd "$TEST_CLONE_DIR/source"
    git clone --bare . "$remote_repo"
    
    # Create existing directory
    mkdir -p "$TEST_CLONE_DIR/existing"
    echo "existing content" > "$TEST_CLONE_DIR/existing/file.txt"
    
    cd "$TEST_CLONE_DIR"
    # We can't easily test interactive prompts in BATS, but we can verify
    # that with an existing directory, the command would handle it
    # For now, we'll just verify the directory check doesn't crash
    # In a real scenario, user would be prompted
    
    # This test documents expected behavior but can't fully test interactive prompts
    skip "Interactive prompt testing requires expect or similar tool"
}

@test "hug clone - library function detect_vcs_from_url works" {
    # Source the detect function from hug-clone
    source "$HUG_HOME/git-config/lib/hug-common"
    source <(sed -n '/^detect_vcs_from_url/,/^}/p' "$HUG_HOME/bin/hug-clone")
    
    # Test Git patterns
    result=$(detect_vcs_from_url "https://github.com/user/repo.git")
    [[ "$result" == "git" ]]
    
    result=$(detect_vcs_from_url "https://gitlab.com/user/repo")
    [[ "$result" == "git" ]]
    
    result=$(detect_vcs_from_url "https://example.com/repo.git")
    [[ "$result" == "git" ]]
    
    # Test Mercurial patterns
    result=$(detect_vcs_from_url "https://example.com/repo.hg")
    [[ "$result" == "hg" ]]
    
    result=$(detect_vcs_from_url "https://hg.example.com/repo")
    [[ "$result" == "hg" ]]
    
    # Test unknown
    result=$(detect_vcs_from_url "https://example.com/repo")
    [[ "$result" == "unknown" ]]
}

@test "hug clone - derive_clone_dir derives target dir like git and hg" {
    source "$HUG_HOME/git-config/lib/hug-common"
    source <(sed -n '/^derive_clone_dir/,/^}/p' "$HUG_HOME/bin/hug-clone")

    # --- git (mirrors guess_dir_name) ---
    assert_equal "$(derive_clone_dir 'https://github.com/user/repo.git' git)" "repo"
    assert_equal "$(derive_clone_dir 'https://github.com/nexu-io/open-design' git)" "open-design"
    assert_equal "$(derive_clone_dir 'https://github.com/user/repo/' git)" "repo"
    assert_equal "$(derive_clone_dir 'https://github.com/user/repo.git/' git)" "repo"
    assert_equal "$(derive_clone_dir 'git@github.com:user/repo.git' git)" "repo"
    assert_equal "$(derive_clone_dir 'git@github.com:user/repo' git)" "repo"
    assert_equal "$(derive_clone_dir 'git@host:repo' git)" "repo"
    assert_equal "$(derive_clone_dir 'https://github.com/user/my.repo' git)" "my.repo"
    assert_equal "$(derive_clone_dir 'https://github.com/user/REPO.GIT' git)" "REPO.GIT"
    assert_equal "$(derive_clone_dir 'ssh://git@github.com:22/user/repo.git' git)" "repo"
    assert_equal "$(derive_clone_dir 'file:///abs/path/myrepo' git)" "myrepo"

    # --- hg (mirrors defaultdest: NO .hg strip) ---
    assert_equal "$(derive_clone_dir 'https://hg.example.com/repo.hg' hg)" "repo.hg"
    assert_equal "$(derive_clone_dir 'https://hg.example.com/proj/myhg' hg)" "myhg"
}

@test "hug clone - cleans up on failure" {
    cd "$TEST_CLONE_DIR"
    
    # Try to clone from non-existent repo
    run hug clone --git --no-status "file:///nonexistent/repo.git" failed-clone
    assert_failure
    
    # Directory should not exist after failed clone
    assert_dir_not_exists "$TEST_CLONE_DIR/failed-clone"
}

@test "hug clone - reports correct dir and runs status for suffixless URL (#193)" {
    # dotted.dir is intentional: it reproduces the old ${url%.*} bug, where the
    # shortest ".*" match stripped ".dir/open-design" and basename gave "dotted".
    local parent="$TEST_CLONE_DIR/dotted.dir"
    mkdir -p "$parent"
    create_test_repo_with_content "$TEST_CLONE_DIR/source"
    cd "$TEST_CLONE_DIR/source"
    git clone --bare . "$parent/open-design"

    cd "$TEST_CLONE_DIR"
    run hug clone --git "file://$parent/open-design"
    assert_success
    assert_output --partial "Cloned successfully to 'open-design'"
    assert_output --partial "HEAD:"
    refute_output --partial "No such file"
    assert_dir_exists "$TEST_CLONE_DIR/open-design"
}

@test "hug clone - bare clone keeps .git suffix and skips status" {
    local remote_repo="$TEST_CLONE_DIR/plain"
    create_test_repo_with_content "$TEST_CLONE_DIR/source"
    cd "$TEST_CLONE_DIR/source"
    git clone --bare . "$remote_repo"

    cd "$TEST_CLONE_DIR"
    run hug clone --git "file://$remote_repo" --bare
    assert_success
    assert_output --partial "Cloned successfully to 'plain.git'"
    refute_output --partial "HEAD:"
    assert_dir_exists "$TEST_CLONE_DIR/plain.git"
}

@test "hug clone - hg keeps .hg suffix (oracle: matches real hg clone)" {
    command -v hg >/dev/null 2>&1 || skip "Mercurial not installed"
    # Source must NOT be a sibling of the clone destination — if both resolve to
    # the same name under $TEST_CLONE_DIR, check_directory_exists fires an
    # interactive TTY prompt that BATS cannot answer. Put the remote in a
    # sub-directory so the destination path is clear.
    local src_dir="$TEST_CLONE_DIR/sources"
    mkdir -p "$src_dir"
    local src="$src_dir/myproj.hg"
    hg init "$src"
    cd "$TEST_CLONE_DIR"
    run hug clone --hg --no-status "file://$src"
    assert_success
    assert_output --partial "Cloned successfully to 'myproj.hg'"
    assert_dir_exists "$TEST_CLONE_DIR/myproj.hg"
}

@test "hug clone - preserves a pre-existing directory when overwrite is declined" {
    # Safety invariant behind the whole #193 fix: never destroy a directory the
    # user did not confirm overwriting. disable_gum_for_test forces the `read`
    # path so the piped "n" is deterministic (HUG_TEST_MODE would otherwise make
    # gum_available true and the pipe would not answer the gum prompt).
    disable_gum_for_test
    local remote_repo="$TEST_CLONE_DIR/remote.git"
    create_test_repo_with_content "$TEST_CLONE_DIR/source"
    cd "$TEST_CLONE_DIR/source"
    git clone --bare . "$remote_repo"

    mkdir -p "$TEST_CLONE_DIR/precious"
    echo "keep me" > "$TEST_CLONE_DIR/precious/data.txt"

    cd "$TEST_CLONE_DIR"
    run bash -c 'echo "n" | hug clone --git --no-status "file://'"$remote_repo"'" precious'
    assert_failure
    assert_output --partial "Cancelled"
    assert_file_exists "$TEST_CLONE_DIR/precious/data.txt"
}
