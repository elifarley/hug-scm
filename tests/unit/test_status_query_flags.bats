#!/usr/bin/env bats
# Tests for hug s query flag parsing and skeleton behavior.
# These tests verify that getopt-based flag parsing works correctly,
# that query flags are recognized, and that the query mode skeleton
# (Task 1) behaves as expected -- exiting early with no output when
# query flags are given.

load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_changes)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

# ---------------------------------------------------------------------------
# Regression tests: existing behavior must not change
# ---------------------------------------------------------------------------

@test "hug s: no flags produces summary line containing HEAD (regression)" {
  run hug s
  assert_success
  assert_output --partial "HEAD"
}

@test "hug s: --json still works without query flags (regression)" {
  run hug s --json
  assert_success
  assert_valid_json
  assert_json_has_key ".branch"
}

# ---------------------------------------------------------------------------
# New help behavior
# ---------------------------------------------------------------------------

@test "hug s: --help shows QUERY FLAGS section and exits 0" {
  # Git intercepts --help and tries man pages; the codebase convention
  # is to use `hug help s` which calls git-s --help directly.
  run hug help s
  assert_success
  assert_output --partial "QUERY FLAGS"
}

@test "hug s: -h (short) shows QUERY FLAGS and exits 0" {
  run hug s -h
  assert_success
  assert_output --partial "QUERY FLAGS"
}

# ---------------------------------------------------------------------------
# Flag conflict detection
# ---------------------------------------------------------------------------

@test "hug s: --json -b exits with error about incompatible flags" {
  run hug s --json -b
  assert_failure
  # The error message must mention that the flags are incompatible
  [[ "$output" =~ (cannot|incompatible|conflict) ]]
}

@test "hug s: --json --branch exits with error about incompatible flags" {
  run hug s --json --branch
  assert_failure
  [[ "$output" =~ (cannot|incompatible|conflict) ]]
}

# ---------------------------------------------------------------------------
# Query mode skeleton: flag is accepted, exits 0 with empty output
# ---------------------------------------------------------------------------

@test "hug s: -b exits 0 (query skeleton)" {
  run hug s -b
  assert_success
}

@test "hug s: --branch exits 0 (query skeleton)" {
  run hug s --branch
  assert_success
}

@test "hug s: --upstream exits 0 (query skeleton)" {
  run hug s --upstream
  assert_success
}

@test "hug s: --hash exits 0 (query skeleton)" {
  run hug s --hash
  assert_success
}

@test "hug s: --ball exits 0 (query skeleton)" {
  run hug s --ball
  assert_success
}

@test "hug s: multiple query flags exit 0 (query skeleton)" {
  run hug s -b --hash
  assert_success
}

# ---------------------------------------------------------------------------
# Error hint: suggests running --help
# ---------------------------------------------------------------------------

@test "hug s: unknown flag error mentions --help" {
  run hug s --nonexistent
  assert_failure
  assert_output --partial "hug s --help"
}

# ---------------------------------------------------------------------------
# getopt edge cases
# ---------------------------------------------------------------------------

@test "hug s: combined short flags are parsed correctly" {
  # -b (branch) and -B (behind) are separate flags; combined should work
  run hug s -bB
  assert_success
}

# ---------------------------------------------------------------------------
# Individual query flag output tests (Task 2: lazy computation)
# ---------------------------------------------------------------------------

@test "hug s -b: outputs current branch name only" {
  run hug s -b
  assert_success
  local expected
  expected=$(git branch --show-current)
  assert_output "$expected"
}

@test "hug s -u: outputs upstream tracking branch" {
  # Use the test repo which has origin set up via create_test_repo_with_remote_upstream
  # The default create_test_repo_with_changes has no upstream, so output may be empty
  run hug s -u
  assert_success
  # If upstream exists, it should match origin/*; if not, output should be empty
  local upstream
  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || echo "")
  assert_output "$upstream"
}

@test "hug s -H: outputs full 40-char SHA" {
  run hug s -H
  assert_success
  [[ ${#output} -eq 40 ]]
  [[ "$output" =~ ^[0-9a-f]{40}$ ]]
}

@test "hug s -s: outputs short hash" {
  run hug s -s
  assert_success
  [[ "$output" =~ ^[0-9a-f]{7,}$ ]]
  [[ ${#output} -lt 40 ]]
}

@test "hug s -A: outputs ahead count (integer)" {
  run hug s -A
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "hug s -B: outputs behind count (integer)" {
  run hug s -B
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "hug s -C: outputs ahead and behind space-separated" {
  local re='^[0-9]+ [0-9]+$'
  run hug s -C
  assert_success
  [[ "$output" =~ $re ]]
}

@test "hug s -S: outputs staged file count" {
  run hug s -S
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "hug s -U: outputs unstaged file count" {
  run hug s -U
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "hug s -K: outputs untracked file count" {
  run hug s -K
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "hug s -I: outputs ignored file count" {
  run hug s -I
  assert_success
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "hug s --ball: outputs a single emoji" {
  run hug s --ball
  assert_success
  # The ball emoji must be one of: red, green, yellow, magenta, black, white circle
  [[ "$output" =~ ^(🔴|🟢|🟡|🟣|⚫|⚪)$ ]]
}

# ---------------------------------------------------------------------------
# Multiple flags (Task 2)
# ---------------------------------------------------------------------------

@test "hug s -b -H: outputs branch and hash space-separated" {
  run hug s -b -H
  assert_success
  local branch hash
  branch=$(git branch --show-current)
  hash=$(git rev-parse HEAD)
  assert_output "$branch $hash"
}

@test "hug s -S -U: outputs staged and unstaged counts" {
  local re='^[0-9]+ [0-9]+$'
  run hug s -S -U
  assert_success
  [[ "$output" =~ $re ]]
}

@test "hug s -C -K: outputs ahead behind and untracked count" {
  local re='^[0-9]+ [0-9]+ [0-9]+$'
  run hug s -C -K
  assert_success
  # Canonical order: ahead behind untracked
  [[ "$output" =~ $re ]]
}

# ---------------------------------------------------------------------------
# Case sensitivity: -s (short hash) vs -S (staged count)
# ---------------------------------------------------------------------------

@test "hug s -s: short hash differs from -S staged count" {
  local short_hash staged_count
  short_hash=$(hug s -s)
  staged_count=$(hug s -S)
  [[ "$short_hash" != "$staged_count" ]]
}

# ---------------------------------------------------------------------------
# Clean stdout: no stderr chatter in query mode
# ---------------------------------------------------------------------------

@test "hug s -b: no output on stderr" {
  run bash -c 'hug s -b 2>&1 1>/dev/null'
  assert_success
  [[ -z "$output" ]]
}

# ---------------------------------------------------------------------------
# -z/--null: NUL-separated output
# ---------------------------------------------------------------------------

@test "hug s -z -b -H: NUL-separated output" {
  # BATS $output cannot hold NUL bytes (command substitution limitation),
  # so we verify by piping directly to a hex dump and checking for the
  # NUL byte (0x00) between the branch name and the hash.
  local branch hash
  branch=$(git branch --show-current)
  hash=$(git rev-parse HEAD)
  local nul_output
  nul_output=$(hug s -z -b -H | xxd -p | tr -d '\n')
  # Build expected hex: branch + 00 + hash + 0a (trailing newline)
  local expected_hex
  expected_hex=$(printf '%s\0%s\n' "$branch" "$hash" | xxd -p | tr -d '\n')
  [[ "$nul_output" == "$expected_hex" ]]
}

# ---------------------------------------------------------------------------
# -C -A no-duplicate: -C already covers ahead, adding -A must not duplicate
# ---------------------------------------------------------------------------

@test "hug s -C -A: no duplicate ahead count" {
  run hug s -C -A
  assert_success
  # -C implies ahead+behind, -A adds ahead. Should NOT output ahead twice.
  # Expected: ahead behind (just 2 numbers, same as -C alone)
  local just_c
  just_c=$(hug s -C)
  assert_output "$just_c"
}

# ---------------------------------------------------------------------------
# Edge cases: detached HEAD, no upstream, clean repo, ball states
# (Task 3: Decision #19 — detached/upstream tests create own repos because
#  create_test_repo_with_changes has no upstream. Decision #24 — not-a-git-repo
#  error test.)
# ---------------------------------------------------------------------------

@test "hug s -b: empty output in detached HEAD" {
  local detached_repo
  detached_repo=$(mktemp -d)
  git init -q "$detached_repo"
  git -C "$detached_repo" config user.name "Test"
  git -C "$detached_repo" config user.email "test@test.com"
  echo "x" > "$detached_repo/file"
  git -C "$detached_repo" add file
  git -C "$detached_repo" commit -q -m "init"
  local sha
  sha=$(git -C "$detached_repo" rev-parse HEAD)
  git -C "$detached_repo" checkout -q "$sha"
  cd "$detached_repo"

  run hug s -b
  assert_success
  [[ -z "$output" ]]

  cd "$TEST_REPO"
  rm -rf "$detached_repo"
}

@test "hug s -u: empty output with no upstream" {
  local no_upstream_repo
  no_upstream_repo=$(mktemp -d)
  git init -q "$no_upstream_repo"
  git -C "$no_upstream_repo" config user.name "Test"
  git -C "$no_upstream_repo" config user.email "test@test.com"
  echo "x" > "$no_upstream_repo/file"
  git -C "$no_upstream_repo" add file
  git -C "$no_upstream_repo" commit -q -m "init"
  cd "$no_upstream_repo"

  run hug s -u
  assert_success
  [[ -z "$output" ]]

  cd "$TEST_REPO"
  rm -rf "$no_upstream_repo"
}

@test "hug s -A: outputs 0 with no upstream" {
  local no_upstream_repo
  no_upstream_repo=$(mktemp -d)
  git init -q "$no_upstream_repo"
  git -C "$no_upstream_repo" config user.name "Test"
  git -C "$no_upstream_repo" config user.email "test@test.com"
  echo "x" > "$no_upstream_repo/file"
  git -C "$no_upstream_repo" add file
  git -C "$no_upstream_repo" commit -q -m "init"
  cd "$no_upstream_repo"

  run hug s -A
  assert_success
  assert_output "0"

  cd "$TEST_REPO"
  rm -rf "$no_upstream_repo"
}

# ── Ball emoji states ──

@test "hug s --ball: white circle on clean repo" {
  local clean_repo
  clean_repo=$(mktemp -d)
  git init -q "$clean_repo"
  git -C "$clean_repo" config user.name "Test"
  git -C "$clean_repo" config user.email "test@test.com"
  echo "x" > "$clean_repo/file"
  git -C "$clean_repo" add file
  git -C "$clean_repo" commit -q -m "init"
  cd "$clean_repo"

  run hug s --ball
  assert_success
  assert_output "⚪"

  cd "$TEST_REPO"
  rm -rf "$clean_repo"
}

@test "hug s --ball: green circle when only staged changes" {
  local repo
  repo=$(mktemp -d)
  git init -q "$repo"
  git -C "$repo" config user.name "Test"
  git -C "$repo" config user.email "test@test.com"
  echo "x" > "$repo/file"
  git -C "$repo" add file
  git -C "$repo" commit -q -m "init"
  echo "changed" > "$repo/file"
  git -C "$repo" add file
  cd "$repo"

  run hug s --ball
  assert_success
  assert_output "🟢"

  cd "$TEST_REPO"
  rm -rf "$repo"
}

@test "hug s --ball: red circle when only unstaged changes" {
  local repo
  repo=$(mktemp -d)
  git init -q "$repo"
  git -C "$repo" config user.name "Test"
  git -C "$repo" config user.email "test@test.com"
  echo "x" > "$repo/file"
  git -C "$repo" add file
  git -C "$repo" commit -q -m "init"
  echo "changed" > "$repo/file"
  cd "$repo"

  run hug s --ball
  assert_success
  assert_output "🔴"

  cd "$TEST_REPO"
  rm -rf "$repo"
}

@test "hug s --ball: yellow circle when both staged and unstaged" {
  local repo
  repo=$(mktemp -d)
  git init -q "$repo"
  git -C "$repo" config user.name "Test"
  git -C "$repo" config user.email "test@test.com"
  echo "x" > "$repo/file"
  git -C "$repo" add file
  git -C "$repo" commit -q -m "init"
  echo "staged" > "$repo/file"
  git -C "$repo" add file
  echo "unstaged" > "$repo/file"
  cd "$repo"

  run hug s --ball
  assert_success
  assert_output "🟡"

  cd "$TEST_REPO"
  rm -rf "$repo"
}

@test "hug s --ball: purple circle when only untracked files" {
  local repo
  repo=$(mktemp -d)
  git init -q "$repo"
  git -C "$repo" config user.name "Test"
  git -C "$repo" config user.email "test@test.com"
  echo "x" > "$repo/file"
  git -C "$repo" add file
  git -C "$repo" commit -q -m "init"
  echo "new" > "$repo/newfile"
  cd "$repo"

  run hug s --ball
  assert_success
  assert_output "🟣"

  cd "$TEST_REPO"
  rm -rf "$repo"
}

@test "hug s -S -U: outputs 0 0 on clean repo" {
  local clean_repo
  clean_repo=$(mktemp -d)
  git init -q "$clean_repo"
  git -C "$clean_repo" config user.name "Test"
  git -C "$clean_repo" config user.email "test@test.com"
  echo "x" > "$clean_repo/file"
  git -C "$clean_repo" add file
  git -C "$clean_repo" commit -q -m "init"
  cd "$clean_repo"

  run hug s -S -U
  assert_success
  assert_output "0 0"

  cd "$TEST_REPO"
  rm -rf "$clean_repo"
}

# ── Not a git repo ──

@test "hug s -b: error when not in a git repo" {
  local nongit_dir
  nongit_dir=$(mktemp -d)
  cd "$nongit_dir"

  run hug s -b
  assert_failure

  cd "$TEST_REPO"
  rm -rf "$nongit_dir"
}

# ---------------------------------------------------------------------------
# -r / --remote query flag tests
# Outputs the fetch URL of the tracking remote (empty if no upstream).
# Uses git for-each-ref --format='%(upstream:remotename)' + git remote get-url.
# ---------------------------------------------------------------------------

@test "hug s -r: outputs remote URL with upstream set" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  cd "$repo"

  run hug s -r
  assert_success
  # Should output the remote URL (a local path to the bare repo)
  [[ -n "$output" ]]
  [[ "$output" == *"/origin.git" ]]

  cd "$TEST_REPO"
}

@test "hug s -r: empty output with no remote" {
  # Fresh init, no remote at all
  local no_remote_repo
  no_remote_repo=$(mktemp -d)
  git init -q "$no_remote_repo"
  git -C "$no_remote_repo" config user.name "Test"
  git -C "$no_remote_repo" config user.email "test@test.com"
  echo "x" > "$no_remote_repo/file"
  git -C "$no_remote_repo" add file
  git -C "$no_remote_repo" commit -q -m "init"
  cd "$no_remote_repo"

  run hug s -r
  assert_success
  [[ -z "$output" ]]

  cd "$TEST_REPO"
  rm -rf "$no_remote_repo"
}

@test "hug s -r: empty output when origin exists but branch has no upstream" {
  local no_upstream_repo
  no_upstream_repo=$(mktemp -d)
  git init -q "$no_upstream_repo"
  git -C "$no_upstream_repo" config user.name "Test"
  git -C "$no_upstream_repo" config user.email "test@test.com"
  echo "x" > "$no_upstream_repo/file"
  git -C "$no_upstream_repo" add file
  git -C "$no_upstream_repo" commit -q -m "init"
  # Add a remote but do NOT set upstream tracking
  local remote_dir
  remote_dir=$(mktemp -d)
  git init --bare -q "$remote_dir"
  git -C "$no_upstream_repo" remote add origin "$remote_dir"
  cd "$no_upstream_repo"

  run hug s -r
  assert_success
  [[ -z "$output" ]]

  cd "$TEST_REPO"
  rm -rf "$no_upstream_repo" "$remote_dir"
}

@test "hug s -b -r: outputs branch and remote URL space-separated" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  cd "$repo"

  run hug s -b -r
  assert_success
  local branch url
  branch=$(hug s -b)
  url=$(hug s -r)
  assert_output "$branch $url"

  cd "$TEST_REPO"
}

@test "hug s -b -r -u: outputs in canonical order" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  cd "$repo"

  local branch remote_url upstream
  branch=$(hug s -b)
  remote_url=$(hug s -r)
  upstream=$(hug s -u)

  run hug s -b -r -u
  assert_success
  assert_output "$branch $remote_url $upstream"

  cd "$TEST_REPO"
}

@test "hug s -z -b -r -H: NUL-separated output" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  cd "$repo"

  local branch remote_url hash
  branch=$(hug s -b)
  remote_url=$(hug s -r)
  hash=$(hug s -H)

  local nul_output
  nul_output=$(hug s -z -b -r -H | xxd -p | tr -d '\n')
  local expected_hex
  expected_hex=$(printf '%s\0%s\0%s\n' "$branch" "$remote_url" "$hash" | xxd -p | tr -d '\n')
  [[ "$nul_output" == "$expected_hex" ]]

  cd "$TEST_REPO"
}

@test "hug s -r: no output on stderr" {
  local repo
  repo=$(create_test_repo_with_remote_upstream)
  cd "$repo"

  run bash -c 'hug s -r 2>&1 1>/dev/null'
  assert_success
  [[ -z "$output" ]]

  cd "$TEST_REPO"
}

@test "hug s --remote: exits 0 (long form)" {
  run hug s --remote
  assert_success
}

@test "hug s -r: empty output in detached HEAD" {
  local detached_repo
  detached_repo=$(mktemp -d)
  git init -q "$detached_repo"
  git -C "$detached_repo" config user.name "Test"
  git -C "$detached_repo" config user.email "test@test.com"
  echo "x" > "$detached_repo/file"
  git -C "$detached_repo" add file
  git -C "$detached_repo" commit -q -m "init"
  local sha
  sha=$(git -C "$detached_repo" rev-parse HEAD)
  git -C "$detached_repo" checkout -q "$sha"
  cd "$detached_repo"

  run hug s -r
  assert_success
  [[ -z "$output" ]]

  cd "$TEST_REPO"
  rm -rf "$detached_repo"
}

@test "hug s -r: outputs correct URL for non-origin remote" {
  local repo
  repo=$(mktemp -d)
  git init -q --initial-branch=main "$repo"
  git -C "$repo" config user.name "Test"
  git -C "$repo" config user.email "test@test.com"
  echo "x" > "$repo/file"
  git -C "$repo" add file
  git -C "$repo" commit -q -m "init"

  # Create two remotes: origin and upstream
  local origin_dir upstream_dir
  origin_dir=$(mktemp -d)
  upstream_dir=$(mktemp -d)
  git init --bare -q "$origin_dir"
  git init --bare -q "$upstream_dir"
  git -C "$repo" remote add origin "$origin_dir"
  git -C "$repo" remote add upstream "$upstream_dir"
  # Push to both remotes (creates refs in bare repos)
  git -C "$repo" push -q origin main
  git -C "$repo" push -q upstream main
  # Set upstream tracking to 'upstream/main' (not origin)
  git -C "$repo" branch --set-upstream-to=upstream/main
  cd "$repo"

  run hug s -r
  assert_success
  # Should output the upstream remote URL, not origin
  [[ "$output" == *"$upstream_dir"* ]]
  [[ "$output" != *"$origin_dir"* ]]

  cd "$TEST_REPO"
  rm -rf "$repo" "$origin_dir" "$upstream_dir"
}

@test "hug s --json -r: exits with error (mutual exclusion)" {
  run hug s --json -r
  assert_failure
  [[ "$output" =~ (cannot|incompatible|conflict) ]]
}

@test "hug s -r: exits 0 in default fixture" {
  # The default setup (create_test_repo_with_changes) has no upstream
  # so -r should output empty but exit 0
  run hug s -r
  assert_success
  [[ -z "$output" ]]
}
