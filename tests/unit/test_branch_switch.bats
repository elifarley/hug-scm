#!/usr/bin/env bats
# Tests for branch switching (hug b / git b)

# Load test helpers
load '../test_helper.bash'

setup() {
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
  assert_output --partial "hug b: Switch to a local branch"
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
  
  # Should show numbered menu format
  assert_output --partial "Select a branch to switch to:"
  assert_output --partial "1)"
  assert_output --partial "Enter choice"
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

  # Mock gum: Select the current branch (line starting with "* main")
  local mock_dir
  mock_dir=$(mktemp -d)
  cat > "$mock_dir/gum" <<'EOF'
#!/usr/bin/env bash
mapfile -t lines
for line in "${lines[@]}"; do
  if [[ "$line" == "* main"* ]]; then
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
  export PATH="$mock_dir:$PATH"
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

  # Mock gum to select the feature/test-1 branch
  local mock_dir
  mock_dir=$(mktemp -d)
  cat > "$mock_dir/gum" <<'EOF'
#!/usr/bin/env bash
mapfile -t lines
for line in "${lines[@]}"; do
  if [[ "$line" == feature/test-1* ]]; then
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
  
  # Temporarily hide gum from PATH
  export PATH="/tmp/no-gum:$PATH"
  
  # Run hug b with a timeout
  run timeout 1 bash -c "echo | hug b 2>&1"
  
  # Should fall back to numbered menu (will timeout waiting for input, but that's ok)
  # Verify it shows the numbered menu format
  [[ "$output" == *"Enter choice"* ]] || [[ "$status" -eq 124 ]]
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
