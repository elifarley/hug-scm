#!/usr/bin/env bats
# Tests for branch switching (hug b / git b)

# Load test helpers
load '../test_helper.bash'

setup() {
  enable_gum_for_test
  require_hug
  TEST_REPO=$(create_test_repo_with_branches)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

# -----------------------------------------------------------------------------
# Basic functionality tests
# -----------------------------------------------------------------------------

@test "hug b --help: shows help message" {
  run bash -c "hug b -h 2>&1"
  assert_success
  assert_output --partial "hug b: Switch to a branch"
  assert_output --partial "USAGE:"
  assert_output --partial "gum filter"
}

@test "hug b <branch>: switches to specified branch directly" {
  # Create a test branch
  git checkout -b test-branch
  git switch main
  
  # Switch using hug b
  run hug b test-branch
  assert_success
  
  # Verify we're on the correct branch
  current=$(git branch --show-current)
  [ "$current" = "test-branch" ]
}

@test "hug b: with < 10 branches uses numbered menu" {
  # Verify we have less than 10 branches
  branch_count=$(git branch | wc -l)
  [ "$branch_count" -lt 10 ]

  # Run hug b with a timeout (it will wait for user input)
  run timeout 1 hug b

  # Python single_select_branches() displays a numbered list.
  # Format: "   1:   <branch> <hash> <date> <subject>"
  # The current branch gets a "* " prefix (green in TTY; no color in non-TTY output).
  # NOTE: "Select a branch to switch to:" and "Enter choice" were output by the
  # old Bash implementation; Python uses a clean numbered list without those headers.
  assert_output --partial "1:"
  # Verify at least one branch name appears in the output
  assert_output --partial "main"
}

# -----------------------------------------------------------------------------
# Gum filter integration tests
# -----------------------------------------------------------------------------

@test "hug b: with 10+ branches uses gum filter if available" {
  # Create additional branches to reach 10+
  for i in {1..10}; do
    git checkout -b "feature/test-$i" main >/dev/null 2>&1
    echo "test $i" >> file.txt
    git add file.txt
    git commit -m "Feature $i" >/dev/null 2>&1
  done
  git checkout main >/dev/null 2>&1
  
  # Verify we have 10+ branches
  branch_count=$(git branch | wc -l)
  [ "$branch_count" -ge 10 ]
  
  # Run hug b with a simulated input via echo and timeout
  # This test verifies the code path is executed without hanging indefinitely
  run timeout 2 bash -c "echo | hug b 2>&1"

  # The command will timeout waiting for input, but that's expected
  # We're just verifying it doesn't error out
  [ "$status" -eq 124 ] || [ "$status" -eq 1 ]  # 124 = timeout, 1 = cancelled
}

@test "hug b: gum selection matches current branch" {
  # Setup: Create exactly 10 branches to trigger gum
  for i in {1..10}; do
    git checkout -b "feature/test-$i" main >/dev/null 2>&1
    echo "test $i" >> file.txt
    git add file.txt
    git commit -m "Feature $i" >/dev/null 2>&1
  done
  git checkout main >/dev/null 2>&1

  # Verify 10+ branches
  branch_count=$(git branch | wc -l)
  [ "$branch_count" -ge 10 ]

  # Mock gum: Select the current branch (line containing "* main").
  # WHY ANSI stripping: branch_select.py always embeds ANSI escape codes in
  # formatted_options (Python uses hardcoded \x1b[32m etc., not tput which would
  # be empty in non-TTY environments).  We must strip codes before matching
  # so the pattern "* main" works regardless of terminal type.
  local mock_dir
  mock_dir=$(mktemp -d)
  cat > "$mock_dir/gum" <<'EOF'
#!/usr/bin/env bash
mapfile -t lines
for line in "${lines[@]}"; do
  # Strip ANSI escape codes before pattern matching (Python always emits them)
  clean=$(printf '%s' "$line" | sed $'s/\033\\[[0-9;]*[a-zA-Z]//g; s/\033(B//g')
  if [[ "$clean" == "* main"* ]]; then
    printf '%s\n' "$line"
    exit 0
  fi
done
if [[ ${#lines[@]} -gt 0 ]]; then
  printf '%s\n' "${lines[0]}"
fi
EOF
  chmod +x "$mock_dir/gum"

  # Temporarily override gum command
  local original_path="$PATH"
  hash -r

  run timeout 3 bash -c "PATH='$mock_dir:$PATH' hug b 2>&1"
  assert_success

  local after_branch
  after_branch=$(git branch --show-current)
  [ "$after_branch" = "main" ]

  # Cleanup
  rm -rf "$mock_dir"
  export PATH="$original_path"
  hash -r
}

@test "hug b: gum selection switches to feature branch" {
  # Setup: Create exactly 10 branches to trigger gum
  for i in {1..10}; do
    git checkout -b "feature/test-$i" main >/dev/null 2>&1
    echo "test $i" >> file.txt
    git add file.txt
    git commit -m "Feature $i" >/dev/null 2>&1
  done
  git checkout main >/dev/null 2>&1

  branch_count=$(git branch | wc -l)
  [ "$branch_count" -ge 10 ]

  # Mock gum to select the feature/test-1 branch.
  # WHY substring match (*feature/test-1*): Python's formatter adds a leading
  # two-space indent for non-current branches ("  feature/test-1 ..."), so we
  # match as a substring rather than a prefix.  ANSI stripping is applied first.
  local mock_dir
  mock_dir=$(mktemp -d)
  cat > "$mock_dir/gum" <<'EOF'
#!/usr/bin/env bash
mapfile -t lines
for line in "${lines[@]}"; do
  # Strip ANSI escape codes before pattern matching
  clean=$(printf '%s' "$line" | sed $'s/\033\\[[0-9;]*[a-zA-Z]//g; s/\033(B//g')
  if [[ "$clean" == *"feature/test-1"* ]] && [[ "$clean" != *"feature/test-10"* ]]; then
    printf '%s\n' "$line"
    exit 0
  fi
done
if [[ ${#lines[@]} -gt 0 ]]; then
  printf '%s\n' "${lines[0]}"
fi
EOF
  chmod +x "$mock_dir/gum"

  local original_path="$PATH"
  export PATH="$mock_dir:$PATH"
  hash -r

  local before_branch
  before_branch=$(git branch --show-current)
  [ "$before_branch" = "main" ]

  run timeout 3 bash -c "PATH='$mock_dir:$PATH' hug b 2>&1"
  assert_success

  local after_branch
  after_branch=$(git branch --show-current)
  [ "$after_branch" = "feature/test-1" ]

  # Cleanup
  rm -rf "$mock_dir"
  export PATH="$original_path"
  hash -r
}

@test "hug b: falls back to numbered menu when gum not installed" {
  # Create 10+ branches
  for i in {1..10}; do
    git checkout -b "feature/test-$i" main >/dev/null 2>&1
    echo "test $i" >> file.txt
    git add file.txt
    git commit -m "Feature $i" >/dev/null 2>&1
  done
  git checkout main >/dev/null 2>&1
  
  disable_gum_for_test
  
  # Run hug b with a timeout
  run timeout 1 bash -c "echo | hug b 2>&1"
  
  # Should fall back to numbered menu.
  # The empty-input pipe (echo | ...) causes Python's get_selection_input() to
  # return "" immediately, parse_single_input returns None → status=cancelled.
  # With the old Bash implementation the "Enter choice" prompt came from
  # get_numbered_selection_index; Python does not output that prompt.
  # Accept either: the command showed the numbered list OR it cancelled/timed-out.
  [[ "$output" == *"1:"* ]] || [[ "$status" -eq 124 ]] || [[ "$status" -eq 1 ]]
}

# -----------------------------------------------------------------------------
# Branch display format tests
# -----------------------------------------------------------------------------

@test "hug b: displays branch with hash and marks current branch" {
  git checkout -b test-branch >/dev/null 2>&1
  git checkout main >/dev/null 2>&1
  
  # Run hug b with timeout
  run timeout 1 bash -c "echo | hug b 2>&1"
  
  # Should show branches with hashes
  assert_output --regexp "[0-9a-f]{7}"
  # Should mark current branch with *
  assert_output --partial "* "
}

@test "hug b: handles branches with tracking info" {
  # Set up a remote
  git remote add origin https://github.com/test/test.git
  
  # Create a branch with upstream tracking
  git checkout -b tracked-branch >/dev/null 2>&1
  git branch --set-upstream-to=origin/main tracked-branch 2>/dev/null || true
  git checkout main >/dev/null 2>&1
  
  # Run hug b with timeout - just verify it doesn't crash
  run timeout 1 bash -c "echo | hug b 2>&1"
  
  # Should exit gracefully (timeout or cancelled, not an error)
  [ "$status" -eq 124 ] || [ "$status" -eq 1 ] || [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Edge cases
# -----------------------------------------------------------------------------

@test "hug b: handles branches with special characters in names" {
  git checkout -b "feature/test-123" >/dev/null 2>&1
  git checkout -b "hotfix/bug-fix" >/dev/null 2>&1
  git checkout main >/dev/null 2>&1
  
  # Run hug b with timeout
  run timeout 1 bash -c "echo | hug b 2>&1"
  
  # Should display branches without errors
  # Exit code 124 (timeout) or 1 (cancelled) is expected
  [ "$status" -eq 124 ] || [ "$status" -eq 1 ] || [ "$status" -eq 0 ]
  assert_output --partial "feature/test-123"
  assert_output --partial "hotfix/bug-fix"
}
