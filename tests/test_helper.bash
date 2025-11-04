#!/usr/bin/env bash
# Test helper utilities for Hug SCM tests
# This file is sourced by all BATS test files

declare -ga HUG_TEST_REMOTE_REPOS=()

# Load BATS support libraries
# Try local dependencies first
local_loaded=false
if [[ -n "${HUG_TEST_DEPS:-}" ]]; then
  if [[ -f "$HUG_TEST_DEPS/bats-support/load.bash" ]]; then
    load "$HUG_TEST_DEPS/bats-support/load.bash"
    load "$HUG_TEST_DEPS/bats-assert/load.bash"
    load "$HUG_TEST_DEPS/bats-file/load.bash"
    local_loaded=true
  fi
fi

# Fall back to system locations if local not loaded
if [[ "$local_loaded" == "false" ]]; then
  if [[ -f '/usr/lib/bats/bats-support/load.bash' ]]; then
    load '/usr/lib/bats/bats-support/load.bash'
    load '/usr/lib/bats/bats-assert/load.bash'
    load '/usr/lib/bats/bats-file/load.bash'
  elif [[ -f '/usr/lib/bats-support/load.bash' ]]; then
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
fi

# Set up the test environment
setup_file() {
  # Export the project root for tests to use
  export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HUG_BIN="$PROJECT_ROOT/git-config/bin"
  
  # Add hug to PATH for tests
  export PATH="$HUG_BIN:$PATH"
  
  # Set up isolated temp dir for the test suite
  export BATS_TEST_TMPDIR="$(mktemp -d -t hug-test-suite-XXXXXX)"

  # Capture original global configs
  export ORIGINAL_GIT_USER_NAME="$(git config --global user.name || echo "")"
  export ORIGINAL_GIT_USER_EMAIL="$(git config --global user.email || echo "")"
  HUG_TEST_REMOTE_REPOS=()
}

teardown_file() {
  # Clean up suite-level temp dir
  if [[ -n "${BATS_TEST_TMPDIR:-}" && -d "$BATS_TEST_TMPDIR" ]]; then
    rm -rf "$BATS_TEST_TMPDIR"
    unset BATS_TEST_TMPDIR
  fi

  # Restore original global configs if changed
  current_name="$(git config --global user.name || echo "")"
  if [ "$current_name" != "$ORIGINAL_GIT_USER_NAME" ]; then
    if [ -n "$ORIGINAL_GIT_USER_NAME" ]; then
      git config --global user.name "$ORIGINAL_GIT_USER_NAME"
    else
      git config --global --unset user.name || true
    fi
  fi
  current_email="$(git config --global user.email || echo "")"
  if [ "$current_email" != "$ORIGINAL_GIT_USER_EMAIL" ]; then
    if [ -n "$ORIGINAL_GIT_USER_EMAIL" ]; then
      git config --global user.email "$ORIGINAL_GIT_USER_EMAIL"
    else
      git config --global --unset user.email || true
    fi
  fi
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
    git init -q --initial-branch=main
    git config --local user.email "test@hug-scm.test"
    git config --local user.name "Hug Test"
    
    # Configure git aliases needed by hug commands
    # These are from git-config/.gitconfig
    git config --local alias.ll "log --graph --pretty=log1 --date=short"
    git config --local pretty.log1 "%C(bold blue)%h%C(reset) %C(white)%ad%C(reset) %C(dim white)%an%C(reset)%C(auto)%d%C(reset) %s"
    
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

# Create a repository where HEAD commits touch the same file as local staged,
# unstaged, untracked, and ignored changes. Useful for exercising hug h*
# interactions with mixed working-tree states.
# The tracked.txt storyline deliberately overlaps:
#   1. Baseline commit seeds three lines.
#   2. Next commit rewrites the TOP line and appends a BOTTOM line.
#   3. Local staged edit rewrites the TOP line again.
#   4. Local unstaged edit appends a new BOTTOM line.
# This lets tests confirm how commands reconcile commit deltas with staged and
# unstaged hunks that touch different sections of the same file.
create_test_repo_with_head_mixed_state() {
  local test_repo
  test_repo=$(create_test_repo)
  
  (
    cd "$test_repo" || { echo "Failed to cd to $test_repo" >&2; exit 1; }
    
    echo "ignored.txt" > .gitignore
    git add .gitignore
    git commit -q -m "Ignore ignored.txt"
    
    cat <<'EOF' > tracked.txt
alpha baseline
beta baseline
gamma baseline
EOF
    git add tracked.txt
    git commit -q -m "Add tracked baseline"
    
    cat <<'EOF' > tracked.txt
alpha commit
beta baseline
gamma baseline
delta commit
EOF
    git add tracked.txt
    git commit -q -m "Touch tracked top and bottom"
    
    cat <<'EOF' > tracked.txt
alpha staged
beta baseline
gamma baseline
delta commit
EOF
    git add tracked.txt
    
    echo "epsilon unstaged" >> tracked.txt
    
    echo "scratch content" > scratch.txt
    
    echo "ignored content" > ignored.txt
  )
  
  echo "$test_repo"
}

# Create a repository where rolling back commits would overwrite local changes,
# allowing tests to assert that git reset --keep aborts safely.
create_test_repo_with_head_conflict_state() {
  local test_repo
  test_repo=$(create_test_repo)
  
  (
    cd "$test_repo" || { echo "Failed to cd to $test_repo" >&2; exit 1; }
    
    cat <<'EOF' > tracked.txt
alpha baseline
beta baseline
gamma baseline
EOF
    git add tracked.txt
    git commit -q -m "Add tracked baseline"
    
    cat <<'EOF' > tracked.txt
alpha head
beta baseline
gamma baseline
EOF
    git add tracked.txt
    git commit -q -m "Modify tracked top line"
    
    cat <<'EOF' > tracked.txt
alpha local
beta baseline
gamma baseline
EOF
    # Leave the conflicting change unstaged to simulate user edits that must be preserved.
  )
  
  echo "$test_repo"
}

# Clean up test repository
cleanup_test_repo() {
  if [[ -n "${TEST_REPO:-}" && -d "$TEST_REPO" ]]; then
    rm -rf "$TEST_REPO" 2>/dev/null || true
    unset TEST_REPO
  fi
  # Clean up any hug-test-repo-* dirs
  find /tmp -maxdepth 1 -name "hug-test-repo-*" -type d -exec rm -rf {} + 2>/dev/null || true

  if [[ ${#HUG_TEST_REMOTE_REPOS[@]} -gt 0 ]]; then
    for remote_dir in "${HUG_TEST_REMOTE_REPOS[@]}"; do
      if [[ -d "$remote_dir" ]]; then
        rm -rf "$remote_dir" 2>/dev/null || true
      fi
    done
    HUG_TEST_REMOTE_REPOS=()
  fi
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

# Assert that a file contains the given string.
assert_file_contains() {
  local file="$1"
  local expected="$2"
  if [[ ! -f "$file" ]]; then
    echo "Expected file to exist for content assertion: $file"
    return 1
  fi
  if ! grep -F -- "$expected" "$file" >/dev/null; then
    echo "Expected $file to contain: $expected"
    echo "Actual contents:"
    cat "$file"
    return 1
  fi
}

# Assert that a file does not contain the given string.
assert_file_not_contains() {
  local file="$1"
  local unexpected="$2"
  if [[ ! -f "$file" ]]; then
    echo "Expected file to exist for content assertion: $file"
    return 1
  fi
  if grep -F -- "$unexpected" "$file" >/dev/null; then
    echo "Did not expect $file to contain: $unexpected"
    echo "Actual contents:"
    cat "$file"
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

# Obtain git status output with porcelain=2 for detailed assertions.
git_status_porcelain() {
  git status --porcelain=2 --untracked-files=normal
}

# Assert that git status porcelain output contains a specific fragment.
assert_git_status_contains() {
  local expected="$1"
  local status
  status=$(git_status_porcelain)
  if ! printf '%s\n' "$status" | grep -F -- "$expected" >/dev/null; then
    echo "Expected git status --porcelain=2 to contain: $expected"
    echo "Actual status:"
    printf '%s\n' "$status"
    return 1
  fi
}

# Assert that git status porcelain output omits a specific fragment.
assert_git_status_not_contains() {
  local unexpected="$1"
  local status
  status=$(git_status_porcelain)
  if printf '%s\n' "$status" | grep -F -- "$unexpected" >/dev/null; then
    echo "Did not expect git status --porcelain=2 to contain: $unexpected"
    echo "Actual status:"
    printf '%s\n' "$status"
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

################################################################################
# Gum Test Helpers
################################################################################

# Disable gum for tests that need non-interactive behavior
# This allows tests to use stdin for confirmation prompts
disable_gum_for_test() {
  export HUG_DISABLE_GUM=true
}

enable_gum_for_test() {
  unset HUG_DISABLE_GUM
}

# Check if gum is available in test environment (respects HUG_DISABLE_GUM)
gum_available_in_test() {
  if [[ "${HUG_DISABLE_GUM:-}" == "true" ]]; then
    return 1
  fi
  command -v gum >/dev/null 2>&1
}

# Skip test if gum is not available
require_gum() {
  if ! gum_available_in_test; then
    skip "gum not available in test environment"
  fi
}

################################################################################
# Mercurial Test Helpers
################################################################################

# Skip test if hg is not installed
require_hg() {
  if ! command -v hg &> /dev/null; then
    skip "hg (Mercurial) command not found in PATH"
  fi
}

# Skip test if hg extension is not available
require_hg_extension() {
  local ext="$1"
  if ! hg help "$ext" >/dev/null 2>&1; then
    skip "Mercurial extension '$ext' is not enabled"
  fi
}

# Create a temporary Mercurial repository for testing
create_test_hg_repo() {
  local test_repo
  test_repo=$(create_temp_repo_dir)
  
  # Clean up if it exists
  rm -rf "$test_repo"
  mkdir -p "$test_repo"
  
  # Initialize repo in subshell for isolation
  (
    cd "$test_repo" || { echo "Failed to cd to $test_repo" >&2; exit 1; }
    hg init
    
    # Configure test user
    cat > .hg/hgrc <<EOF
[ui]
username = Hug Test <test@hug-scm.test>

[extensions]
purge =
EOF
    
    # Create initial commit
    echo "# Test Repository" > README.md
    hg add README.md
    hg commit -m "Initial commit" -q
  )
  
  echo "$test_repo"
}

# Create a test Mercurial repository with some sample commits
create_test_hg_repo_with_history() {
  local test_repo
  test_repo=$(create_test_hg_repo)
  
  (
    cd "$test_repo" || { echo "Failed to cd to $test_repo" >&2; exit 1; }
    # Add a few more commits
    echo "Feature 1" > feature1.txt
    hg add feature1.txt
    hg commit -m "Add feature 1" -q
    
    echo "Feature 2" > feature2.txt
    hg add feature2.txt
    hg commit -m "Add feature 2" -q
  )
  
  echo "$test_repo"
}

# Create a test Mercurial repository with uncommitted changes
create_test_hg_repo_with_changes() {
  local test_repo
  test_repo=$(create_test_hg_repo)
  
  (
    cd "$test_repo" || { echo "Failed to cd to $test_repo" >&2; exit 1; }
    # Added file
    echo "Added content" > added.txt
    hg add added.txt
    
    # Modified file
    echo "Modified content" >> README.md
    
    # Untracked file
    echo "Untracked content" > untracked.txt
  )
  
  echo "$test_repo"
}

# Assert that hg status is clean
assert_hg_clean() {
  local status
  status=$(hg status)
  if [[ -n "$status" ]]; then
    echo "Expected clean hg status, but found:"
    echo "$status"
    return 1
  fi
}

create_test_repo_with_cherry_pick_conflict() {
  local test_repo
  test_repo=$(create_test_repo_with_history)

  (
    cd "$test_repo" || { echo "Failed to cd to $test_repo" >&2; exit 1; }

    git checkout -q -b conflict-target HEAD~1
    echo "Feature 1 change on target branch" > feature1.txt
    git add feature1.txt
    git commit -q -m "Conflict change on target"

    git checkout -q main
    echo "Feature 1 change on main branch" > feature1.txt
    git add feature1.txt
    git commit -q -m "Conflict change on main"
  )

  echo "$test_repo"
}

create_test_repo_with_remote_upstream() {
  local test_repo
  test_repo=$(create_test_repo_with_history)

  local remote_root
  remote_root=$(mktemp -d -t "hug-remote-XXXXXX" 2>/dev/null || mktemp -d /tmp/hug-remote-XXXXXX)
  local remote_repo="$remote_root/origin.git"
  git init --bare -q "$remote_repo"
  HUG_TEST_REMOTE_REPOS+=("$remote_root")

  (
    cd "$test_repo" || { echo "Failed to cd to $test_repo" >&2; exit 1; }

    git remote add origin "$remote_repo"
    git push -q origin main
    git branch --set-upstream-to=origin/main >&2
  )

  echo "$test_repo"
}

# Create a test repository with multiple branches for relocate tests
create_test_repo_with_branches() {
  local test_repo
  test_repo=$(create_test_repo_with_history)
  
  (
    cd "$test_repo" || { echo "Failed to cd to $test_repo" >&2; exit 1; }
    
    # Create a feature branch with commits
    git checkout -q -b feature/branch
    echo "Feature branch file" > feature.txt
    git add feature.txt
    git commit -q -m "Add feature on branch"
    
    # Switch back to main and add more commits
    git checkout -q main
    echo "Main extra" > main_extra.txt
    git add main_extra.txt
    git commit -q -m "Add main extra"
  )
  
  echo "$test_repo"
}
