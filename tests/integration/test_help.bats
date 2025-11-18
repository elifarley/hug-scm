#!/usr/bin/env bats
# Tests for hug help command outside repository

load ../test_helper

setup() {
    require_hug
    TEST_TEMP_DIR=$(create_temp_repo_dir)
    mkdir -p "$TEST_TEMP_DIR"
}

teardown() {
    rm -rf "$TEST_TEMP_DIR"
}

@test "hug help - works outside repository without arguments" {
    cd "$TEST_TEMP_DIR"
    run hug help
    assert_success
    assert_output --partial "Available command groups:"
    assert_output --partial "a*  - Add to staging area"
    assert_output --partial "h*  - HEAD operations"
    assert_output --partial "w*  - Working dir operations"
}

@test "hug help - works outside repository with prefix argument" {
    cd "$TEST_TEMP_DIR"
    run hug help a
    assert_success
    assert_output --partial "Commands starting with 'a':"
}

@test "hug help h - shows HEAD operations outside repository" {
    cd "$TEST_TEMP_DIR"
    run hug help h
    assert_success
    assert_output --partial "Commands starting with 'h':"
    assert_output --partial "h* subcommands (HEAD operations):"
    assert_output --partial "back     - Move HEAD back, keep staged"
    assert_output --partial "rollback - Rollback commit, preserve local work"
}

@test "hug help w - shows working directory operations outside repository" {
    cd "$TEST_TEMP_DIR"
    run hug help w
    assert_success
    assert_output --partial "Commands starting with 'w':"
}

@test "hug help s - shows status operations outside repository" {
    cd "$TEST_TEMP_DIR"
    run hug help s
    assert_success
    assert_output --partial "Commands starting with 's':"
}

@test "hug help l - shows log operations outside repository" {
    cd "$TEST_TEMP_DIR"
    run hug help l
    assert_success
    assert_output --partial "Commands starting with 'l':"
    assert_output --partial "Tips for file history"
}

@test "hug help b - shows branch operations outside repository" {
    cd "$TEST_TEMP_DIR"
    run hug help b
    assert_success
    assert_output --partial "Commands starting with 'b':"
}

@test "hug help c - shows commit operations outside repository" {
    cd "$TEST_TEMP_DIR"
    run hug help c
    assert_success
    assert_output --partial "Commands starting with 'c':"
}

@test "hug help - works in repository too (regression check)" {
    cd "$TEST_TEMP_DIR"
    git init -q
    run hug help
    assert_success
    assert_output --partial "Available command groups:"
}

@test "hug help a - works in repository too (regression check)" {
    cd "$TEST_TEMP_DIR"
    git init -q
    run hug help a
    assert_success
    assert_output --partial "Commands starting with 'a':"
}

@test "hug version - works outside repository" {
    cd "$TEST_TEMP_DIR"
    run hug version
    assert_success
    assert_output --partial "Hug SCM"
}

@test "hug --version - works outside repository" {
    cd "$TEST_TEMP_DIR"
    run hug --version
    assert_success
    assert_output --partial "Hug SCM"
}
