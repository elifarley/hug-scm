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

# --- New: rich `hug help @` listing with summary column (T7) ---

@test "hug help @ - shows summary column with em-dash separator" {
    cd "$TEST_TEMP_DIR"
    run hug help @
    assert_success
    assert_output --partial "@branching"
    assert_output --partial "Create, list, switch, and delete branches"
    assert_output --partial "—"
}

@test "hug help @ - tip line mentions 'learn about a category'" {
    cd "$TEST_TEMP_DIR"
    run hug help @
    assert_success
    assert_output --partial "learn about a category and list its commands"
}

@test "hug help @ - advertises /<keyword> and !<intent> sigils" {
    cd "$TEST_TEMP_DIR"
    run hug help @
    assert_success
    assert_output --partial "/<keyword>"
    assert_output --partial "!<intent>"
}

# --- New: boxed `hug help @<category>` page (T8) ---

@test "hug help @branching - shows boxed header with category label" {
    cd "$TEST_TEMP_DIR"
    run hug help @branching
    assert_success
    assert_output --partial "@branching"
    assert_output --partial "Branch operations"
}

@test "hug help @branching - command list reaches stdout (pipe-safe)" {
    cd "$TEST_TEMP_DIR"
    # 2>/dev/null filters stderr; only data survives on stdout.
    run bash -c "hug help @branching 2>/dev/null"
    assert_success
    assert_output --partial "hug bc"
    refute_output --partial "──"
    refute_output --partial "Tip:"
}

@test "hug help @branching | grep - data is greppable" {
    cd "$TEST_TEMP_DIR"
    run bash -c "hug help @branching 2>/dev/null | grep 'hug bpush'"
    assert_success
    assert_output --partial "hug bpush"
}

# --- New: token-aware !intent (T4) finds via per-command keyword ---

@test "hug help !save my work - finds wip via per-command keyword" {
    cd "$TEST_TEMP_DIR"
    run bash -c "hug help '!save my work'"
    assert_success
    assert_output --partial "hug w wip"
}

@test "hug help !save - destructive sibling NOT in results (F3 regression)" {
    cd "$TEST_TEMP_DIR"
    run bash -c "hug help '!save'"
    assert_success
    refute_output --partial "hug w wipdel"
}

# --- New: --explain flag annotates results (T6) ---

@test "hug help /branch --explain - annotates with match-source" {
    cd "$TEST_TEMP_DIR"
    run hug help /branch --explain
    assert_success
    assert_output --partial "["
    assert_output --partial "]"
}

@test "hug help /branch (no --explain) - no annotations by default" {
    cd "$TEST_TEMP_DIR"
    run hug help /branch
    assert_success
    refute_output --partial "[desc,"
    refute_output --partial "[name=,"
    refute_output --partial "[name~,"
    refute_output --partial "[keywords,"
}

# --- New: --all disables cap (T5) ---

@test "hug help /branch --all - returns matches without cap" {
    cd "$TEST_TEMP_DIR"
    run hug help /branch --all
    assert_success
    assert_output --partial "Keyword search for 'branch'"
}

# --- New: validation gate (T10) — healthy repo passes ---

@test "hug help @ - exits 0 in healthy repo (T10 validation)" {
    cd "$TEST_TEMP_DIR"
    run hug help @
    assert_success
}

# --- New: T9 tip-line update ---

@test "hug help (no args) - new tip lines distinguish @ from @<category>" {
    cd "$TEST_TEMP_DIR"
    run hug help
    assert_success
    assert_output --partial "List all categories"
    assert_output --partial "Learn about a category and list its commands"
}

# --- F3 destructive isolation: /keyword path ---

@test "hug help /save - returns wip but NOT wipdel (F3 lock)" {
    cd "$TEST_TEMP_DIR"
    run hug help /save
    assert_success
    assert_output --partial "hug w wip"
    refute_output --partial "hug w wipdel"
}
