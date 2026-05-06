#!/usr/bin/env bats
# Integration tests for hug help topic search (/keyword, @category, !intent)

load ../test_helper

setup() {
    require_hug
    # Clear search cache to ensure fresh results
    rm -f /tmp/cache/hug/search-meta.cache
    TEST_TEMP_DIR=$(create_temp_repo_dir)
    mkdir -p "$TEST_TEMP_DIR"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

# --- Keyword search (/) ---

@test "hug help /undo - finds undo-related commands" {
    cd "$TEST_TEMP_DIR"
    run hug help /undo
    assert_success
    assert_output --partial "hug h undo"
}

@test "hug help /push - finds push commands" {
    cd "$TEST_TEMP_DIR"
    run hug help /push
    assert_success
    assert_output --partial "hug bpush"
}

@test "hug help / - shows usage hint" {
    cd "$TEST_TEMP_DIR"
    run hug help /
    assert_success
    assert_output --partial "Usage: hug help /<keyword>"
}

@test "hug help /xyzzy12345 - returns no results" {
    cd "$TEST_TEMP_DIR"
    run hug help /xyzzy12345
    assert_success
    assert_output --partial "(none)"
}

# --- Category search (@) ---

@test "hug help @ - lists all categories" {
    cd "$TEST_TEMP_DIR"
    run hug help @
    assert_success
    assert_output --partial "Available categories:"
}

@test "hug help @branching - finds branching commands" {
    cd "$TEST_TEMP_DIR"
    run hug help @branching
    assert_success
    assert_output --partial "hug bpush"
}

@test "hug help @staging - finds staging commands" {
    cd "$TEST_TEMP_DIR"
    run hug help @staging
    assert_success
    assert_output --partial "hug a"
}

@test "hug help @worktrees - finds worktree commands" {
    cd "$TEST_TEMP_DIR"
    run hug help @worktrees
    assert_success
    assert_output --partial "hug wtc"
}

# --- Intent search (!) ---

@test "hug help !push - finds push commands" {
    cd "$TEST_TEMP_DIR"
    run hug help '!push'
    assert_success
    assert_output --partial "hug bpush"
}

@test "hug help ! - shows usage hint" {
    cd "$TEST_TEMP_DIR"
    run hug help '!'
    assert_success
    assert_output --partial "Usage: hug help !<intent>"
}

# --- Regression: existing help still works ---

@test "hug help - still shows command groups (regression)" {
    cd "$TEST_TEMP_DIR"
    run hug help
    assert_success
    assert_output --partial "Available command groups:"
    assert_output --partial "Topic search:"
}

@test "hug help s - still shows prefix commands (regression)" {
    cd "$TEST_TEMP_DIR"
    run hug help s
    assert_success
    assert_output --partial "Commands starting with 's':"
}

@test "hug help a - still shows prefix commands (regression)" {
    cd "$TEST_TEMP_DIR"
    run hug help a
    assert_success
    assert_output --partial "Commands starting with 'a':"
}
