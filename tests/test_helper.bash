#!/usr/bin/env bash
# Test helper utilities for Hug SCM tests
# This file is sourced by all BATS test files

# Load BATS support libraries
# Try multiple common locations
if [[ -f '/usr/lib/bats-support/load.bash' ]]; then
  load '/usr/lib/bats-support/load.bash'
  load '/usr/lib/bats-assert/load.bash'
  load '/usr/lib/bats-file/load.bash'
elif [[ -d '/usr/lib/bats-support' ]]; then
  # Load individual files if load.bash doesn't exist
  for lib in /usr/lib/bats-support/*.bash; do
    source "$lib"
  done
  for lib in /usr/lib/bats-assert/*.bash; do
    source "$lib"
  done
  for lib in /usr/lib/bats-file/*.bash; do
    source "$lib"
  done
elif [[ -d "$HOME/.bats-libs/bats-support" ]]; then
  load "$HOME/.bats-libs/bats-support/load.bash"
  load "$HOME/.bats-libs/bats-assert/load.bash"
  load "$HOME/.bats-libs/bats-file/load.bash"
fi

# Set up the test environment
setup_file() {
  # Export the project root for tests to use
  export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HUG_BIN="$PROJECT_ROOT/git-config/bin"
  
  # Add hug to PATH for tests
  export PATH="$HUG_BIN:$PATH"
}

# Helper to create a unique temp dir for test repos
create_temp_repo_dir() {
  local dir
  dir=$(mktemp -d -t "hug-test-repo-XXXXXX" 2>/dev/null || mktemp -d /tmp/hug-test-repo-XXXXXX)
  echo "$dir"
}

# Create a temporary git repository for testing
create_test_repo() {
  local test_repo
  test_repo=$(create_temp_repo_dir)
  
  # Clean up if it exists
  rm -rf "$test_repo"
  mkdir -p "$test_repo"
  
  # Initialize repo in subshell for isolation
  (
    cd "$test_repo" || { echo "Failed to cd to $test_repo" >&2; exit 1; }
    git init -q
    git config user.email "test@hug-scm.test"
    git config user.name "Hug Test"
    
    # Create initial commit
    echo "# Test Repository" > README.md
    git add README.md
    git commit -q -m "Initial commit"
  )
  
  echo "$test_repo"
}

# Create a test repository with some sample commits
create_test_repo_with_history() {
  local test_repo
  test_repo=$(create_test_repo)
  
  (
    cd "$test_repo" || { echo "Failed to cd to $test_repo" >&2; exit 1; }
    # Add a few more commits
    echo "Feature 1" > feature1.txt
    git add feature1.txt
    git commit -q -m "Add feature 1"
    
    echo "Feature 2" > feature2.txt
    git add feature2.txt
    git commit -q -m "Add feature 2"
  )
  
  echo "$test_repo"
}

# Create a test repository with uncommitted changes
create_test_repo_with_changes() {
  local test_repo
  test_repo=$(create_test_repo)
  
  (
    cd "$test_repo" || { echo "Failed to cd to $test_repo" >&2; exit 1; }
    # Staged changes
    echo "Staged content" > staged.txt
    git add staged.txt
    
    # Unstaged changes
    echo "Modified content" >> README.md
    
    # Untracked file
    echo "Untracked content" > untracked.txt
  )
  
  echo "$test_repo"
}

# Clean up test repository
cleanup_test_repo() {
  if [[ -n "${TEST_REPO:-}" && -d "$TEST_REPO" ]]; then
    rm -rf "$TEST_REPO"
    unset TEST_REPO
  fi
  # Clean up any hug-test-repo-* dirs
  find /tmp -maxdepth 1 -name "hug-test-repo-*" -type d -exec rm -rf {} + 2>/dev/null || true
}

# Assert that a command's output contains a string (case-insensitive)
assert_output_contains() {
  local expected="$1"
  if ! echo "$output" | grep -iq "$expected"; then
    echo "Expected output to contain: $expected"
    echo "Actual output: $output"
    return 1
  fi
}

# Assert that a file exists
assert_file_exists() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "Expected file to exist: $file"
    return 1
  fi
}

# Assert that a file does not exist
assert_file_not_exists() {
  local file="$1"
  if [[ -f "$file" ]]; then
    echo "Expected file to not exist: $file"
    return 1
  fi
}

# Assert that git status is clean
assert_git_clean() {
  local status
  status=$(git status --porcelain)
  if [[ -n "$status" ]]; then
    echo "Expected clean git status, but found:"
    echo "$status"
    return 1
  fi
}

# Skip test if hug is not installed
require_hug() {
  if ! command -v hug &> /dev/null; then
    skip "hug command not found in PATH"
  fi
}

# Skip test if git version is too old
require_git_version() {
  local required="$1"
  local current
  current=$(git --version | grep -oP '\d+\.\d+' | head -1)
  
  if ! awk -v curr="$current" -v req="$required" 'BEGIN { exit !(curr >= req) }'; then
    skip "Git version $required or higher required (found $current)"
  fi
}
