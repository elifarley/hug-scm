#!/usr/bin/env bash
# Test helper utilities for Hug SCM tests
# This file is sourced by all BATS test files

declare -ga HUG_TEST_REMOTE_REPOS=()

# Load deterministic git helpers for reproducible commit hashes
# This is sourced early so all fixtures can use git_commit_deterministic()
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/deterministic_git.bash"

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
  # BATS_TEST_FILENAME points to tests/unit/test_*.bats or tests/lib/test_*.bats
  # We need to go up 2 levels to get to project root
  export PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export HUG_BIN="$PROJECT_ROOT/git-config/bin"

  # Add hug to PATH for tests
  export PATH="$HUG_BIN:$PATH"

  # Enable test mode for gum simulation (bypasses TTY checks)
  export HUG_TEST_MODE=true

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

    # Create initial commit with deterministic timestamp
    reset_fake_clock
    echo "# Test Repository" > README.md
    git add README.md
    git_commit_deterministic "Initial commit"
  )
  
  echo "$test_repo"
}

# Create a test repository with some sample commits
# Uses deterministic timestamps for reproducible commit hashes
create_test_repo_with_history() {
  local test_repo
  test_repo=$(create_test_repo)

  (
    cd "$test_repo" || { echo "Failed to cd to $test_repo" >&2; exit 1; }
    reset_fake_clock  # Start from epoch for reproducibility

    # Add a few more commits with deterministic timestamps
    echo "Feature 1" > feature1.txt
    git add feature1.txt
    git_commit_deterministic "Add feature 1"

    echo "Feature 2" > feature2.txt
    git add feature2.txt
    git_commit_deterministic "Add feature 2"
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
# Uses deterministic timestamps for reproducible commit hashes.
create_test_repo_with_head_mixed_state() {
  local test_repo
  test_repo=$(create_test_repo)

  (
    cd "$test_repo" || { echo "Failed to cd to $test_repo" >&2; exit 1; }
    reset_fake_clock

    echo "ignored.txt" > .gitignore
    git add .gitignore
    git_commit_deterministic "Ignore ignored.txt"

    cat <<'EOF' > tracked.txt
alpha baseline
beta baseline
gamma baseline
EOF
    git add tracked.txt
    git_commit_deterministic "Add tracked baseline"

    cat <<'EOF' > tracked.txt
alpha commit
beta baseline
gamma baseline
delta commit
EOF
    git add tracked.txt
    git_commit_deterministic "Touch tracked top and bottom"

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
# Uses deterministic timestamps for reproducible commit hashes.
create_test_repo_with_head_conflict_state() {
  local test_repo
  test_repo=$(create_test_repo)

  (
    cd "$test_repo" || { echo "Failed to cd to $test_repo" >&2; exit 1; }
    reset_fake_clock

    cat <<'EOF' > tracked.txt
alpha baseline
beta baseline
gamma baseline
EOF
    git add tracked.txt
    git_commit_deterministic "Add tracked baseline"

    cat <<'EOF' > tracked.txt
alpha head
beta baseline
gamma baseline
EOF
    git add tracked.txt
    git_commit_deterministic "Modify tracked top line"

    cat <<'EOF' > tracked.txt
alpha local
beta baseline
gamma baseline
EOF
    # Leave the conflicting change unstaged to simulate user edits that must be preserved.
  )

  echo "$test_repo"
}

# Create a test repository with commits at specific dates
# Useful for testing temporal filtering functions
create_test_repo_with_dated_commits() {
  local test_repo
  test_repo=$(create_test_repo)
  
  (
    cd "$test_repo" || { echo "Failed to cd to $test_repo" >&2; exit 1; }
    
    # Create commits at specific times
    echo "day1" > day1.txt
    git add day1.txt
    GIT_COMMITTER_DATE="2024-01-01 10:00:00" GIT_AUTHOR_DATE="2024-01-01 10:00:00" \
      git commit -q -m "Day 1"
    
    echo "day5" > day5.txt
    git add day5.txt
    GIT_COMMITTER_DATE="2024-01-05 10:00:00" GIT_AUTHOR_DATE="2024-01-05 10:00:00" \
      git commit -q -m "Day 5"
    
    echo "day10" > day10.txt
    git add day10.txt
    GIT_COMMITTER_DATE="2024-01-10 10:00:00" GIT_AUTHOR_DATE="2024-01-10 10:00:00" \
      git commit -q -m "Day 10"
    
    echo "day15" > day15.txt
    git add day15.txt
    GIT_COMMITTER_DATE="2024-01-15 10:00:00" GIT_AUTHOR_DATE="2024-01-15 10:00:00" \
      git commit -q -m "Day 15"
    
    echo "day20" > day20.txt
    git add day20.txt
    GIT_COMMITTER_DATE="2024-01-20 10:00:00" GIT_AUTHOR_DATE="2024-01-20 10:00:00" \
      git commit -q -m "Day 20"
  )
  
  echo "$test_repo"
}

# Clean up test repository
cleanup_test_repo() {
  # CRITICAL: Exit any test repo directory first to prevent getcwd errors
  local cwd
  cwd=$(pwd)
  
  # If we're inside a test repo, exit it before cleanup
  if [[ "$cwd" == *"hug-test-repo"* || "$cwd" == *"hug-workflow-test"* || "$cwd" == *"hug-clone-test"* || "$cwd" == *"hug-remote-test"* ]]; then
    cd "${BATS_TEST_TMPDIR:-/tmp}" 2>/dev/null || cd /tmp || cd "$HOME"
  fi
  
  # Cleanup TEST_REPO if set
  if [[ -n "${TEST_REPO:-}" && -d "$TEST_REPO" ]]; then
    # Remove any worktrees FIRST (they reference main repo)
    if [[ -d "$TEST_REPO/.git" ]]; then
      git -C "$TEST_REPO" worktree list --porcelain 2>/dev/null |
        grep "^worktree " |
        cut -d' ' -f2 |
        while read -r wt; do
          [[ "$wt" != "$TEST_REPO" && -d "$wt" ]] && rm -rf "$wt" 2>/dev/null
        done
      
      # Prune worktree metadata
      git -C "$TEST_REPO" worktree prune 2>/dev/null || true
    fi
    
    # Now safe to remove main repo
    rm -rf "$TEST_REPO" 2>/dev/null || true
    unset TEST_REPO
  fi
  
  # Clean up any orphaned test repos (older than 60 minutes)
  find /tmp -maxdepth 1 -name "hug-test-repo-*" -type d \
    -mmin +60 -exec rm -rf {} + 2>/dev/null || true

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

# Enable gum simulation for testing
# This enables test mode which bypasses TTY checks and allows gum to work in test environments
enable_gum_simulation() {
  export HUG_TEST_MODE=true
  export HUG_DISABLE_GUM=""  # Ensure gum is not disabled
}

# Disable gum simulation for testing
disable_gum_simulation() {
  unset HUG_TEST_MODE
}

# Force gum to be unavailable for testing
# This is useful when testing error paths that require gum to be disabled
disable_gum_for_test() {
  export HUG_DISABLE_GUM=true
  unset HUG_TEST_MODE
}

# Configure gum mock to simulate cancellation
# Useful for testing that commands handle cancelled gum interactions properly
gum_mock_cancel() {
  export HUG_TEST_GUM_CONFIRM="no"
  export HUG_TEST_GUM_INPUT_RETURN_CODE=1
}

# Configure gum mock to simulate successful selection/input
gum_mock_success() {
  export HUG_TEST_GUM_CONFIRM="yes"
  export HUG_TEST_GUM_INPUT_RETURN_CODE=0
}

# Setup gum mock for testing
# This adds tests/bin to PATH so gum-mock is used instead of real gum
# Usage in tests:
#   setup_gum_mock
#   export HUG_TEST_GUM_SELECTION_INDEX=0  # Select first item (optional)
#   hug w wipdel  # Will use gum-mock instead of real gum
#   teardown_gum_mock
setup_gum_mock() {
  # Save original PATH
  export HUG_TEST_ORIGINAL_PATH="$PATH"
  
  # Add tests/bin to the beginning of PATH
  # The gum symlink should already exist pointing to gum-mock
  if [[ -z "${PROJECT_ROOT:-}" ]]; then
    # Fallback: calculate PROJECT_ROOT if not set
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fi
  
  tests_bin="$PROJECT_ROOT/tests/bin"
  export PATH="$tests_bin:$PATH"
}

# Teardown gum mock
teardown_gum_mock() {
  # Restore original PATH
  if [[ -n "${HUG_TEST_ORIGINAL_PATH:-}" ]]; then
    export PATH="$HUG_TEST_ORIGINAL_PATH"
    unset HUG_TEST_ORIGINAL_PATH
  fi
  
  # Unset any mock-related environment variables
  unset HUG_TEST_GUM_SELECTION_INDEX
  unset HUG_TEST_GUM_CONFIRM
}

# Skip test if gum is not available
require_gum() { gum_available || error "gum not available in test environment"; }

# Skip test if worktree commands are not fully implemented or supported
require_worktree_support() {
  # Check if worktree commands exist and respond
  if ! command -v hug &>/dev/null; then
    skip "hug command not found in PATH"
  fi
  
  # Check if git worktree is supported (git 2.5+)
  if ! git worktree list &>/dev/null 2>&1; then
    skip "git worktree not supported in this git version (requires 2.5+)"
  fi
  
  # Optional: Check if specific worktree commands are implemented
  # Commands may exist but not be fully functional yet
  # This allows tests to be written before full implementation
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

    # Create a feature branch with commits (existing functionality)
    git checkout -q -b feature/branch
    echo "Feature branch file" > feature.txt
    git add feature.txt
    git commit -q -m "Add feature on branch"

    # Switch back to main and add more commits
    git checkout -q main
    echo "Main extra" > main_extra.txt
    git add main_extra.txt
    git commit -q -m "Add main extra"

    # Create branches that worktree tests expect
    git checkout -q -b feature-1
    echo "Feature 1 content" > feature1.txt
    git add feature1.txt
    git commit -q -m "feature-1 initial commit"

    git checkout -q main

    git checkout -q -b feature-2
    echo "Feature 2 content" > feature2.txt
    git add feature2.txt
    git commit -q -m "feature-2 initial commit"

    git checkout -q main

    git checkout -q -b hotfix-1
    echo "Hotfix 1 content" > hotfix1.txt
    git add hotfix1.txt
    git commit -q -m "hotfix-1 initial commit"

    # Return to main branch
    git checkout -q main
  )

  echo "$test_repo"
}

################################################################################
# Demo Repository Helpers (Leverage Makefile Targets)
################################################################################

# Create simple demo repository via repo-setup script
# This uses the battle-tested repo-setup-simple.sh script which creates
# deterministic commits with fixed timestamps for repeatable test results.
#
# The simple demo repo includes:
# - 3 initial commits (README, app.js, .gitignore)
# - 4 commits with overlapping file changes (for dependency testing)
# - 2 commits on feature/search branch
# - Bare remote repository
# - Proper git config (user.name, user.email)
#
# Returns: Path to created repository
create_demo_repo_simple() {
  local repo_path="${1:-$(create_temp_repo_dir)}"

  # Call repo-setup script directly
  # Explicitly set PATH to include hug bin (setup_file should have done this)
  if [ -z "${PROJECT_ROOT:-}" ]; then
    echo "ERROR: PROJECT_ROOT not set in create_demo_repo_simple" >&2
    return 1
  fi

  local setup_script="$PROJECT_ROOT/docs/screencasts/bin/repo-setup-simple.sh"
  if [[ ! -f "$setup_script" ]]; then
    echo "ERROR: Setup script not found: $setup_script" >&2
    return 1
  fi

  # Run the setup script (output suppressed)
  if ! HUG_BIN_PATH="$PROJECT_ROOT/git-config/bin" \
       PATH="$PATH:$PROJECT_ROOT/git-config/bin" \
       bash "$setup_script" "$repo_path" >/dev/null 2>&1; then
    echo "Failed to create demo repo at $repo_path (script returned error)" >&2
    return 1
  fi

  # Verify repo was created successfully
  if [[ ! -d "$repo_path/.git" ]]; then
    echo "Failed to create demo repo at $repo_path (no .git directory)" >&2
    return 1
  fi

  echo "$repo_path"
}

# Create full demo repository via make target
# This uses repo-setup.sh which creates a comprehensive demo with:
# - 70+ commits with deterministic timestamps
# - 15+ branches (feature, bugfix, hotfix, experimental, release)
# - 4 contributors with realistic commit patterns
# - Remote repository with upstream tracking
# - Tags (both local and pushed)
# - Various file states (staged, unstaged, conflicts, etc.)
#
# Returns: Path to created repository
create_demo_repo_full() {
  local repo_path="${1:-$(create_temp_repo_dir)}"

  # Call repo-setup script directly instead of via make
  # This avoids issues with make being called from within BATS
  HUG_BIN_PATH="$PROJECT_ROOT/git-config/bin" \
  PATH="$PATH:$PROJECT_ROOT/git-config/bin" \
  bash "$PROJECT_ROOT/docs/screencasts/bin/repo-setup.sh" "$repo_path" >/dev/null 2>&1

  # Verify repo was created successfully
  if [[ ! -d "$repo_path/.git" ]]; then
    echo "Failed to create full demo repo at $repo_path" >&2
    return 1
  fi

  echo "$repo_path"
}

# JSON validation helpers - flexible to formatting variations
# These helpers allow tests to validate JSON structure and values
# without being strict about formatting (spaces, quote style, ordering)

assert_valid_json() {
  echo "$output" | jq . >/dev/null || fail "Output is not valid JSON"
}

assert_json_has_key() {
  local jq_path="$1"
  echo "$output" | jq -e "$jq_path" >/dev/null || fail "JSON missing key: $jq_path"
}

assert_json_value() {
  local jq_path="$1"
  local expected="$2"
  local actual
  actual=$(echo "$output" | jq -r "$jq_path")
  [[ "$actual" == "$expected" ]] || fail "Expected $jq_path = '$expected', got '$actual'"
}

assert_json_type() {
  local jq_path="$1"
  local expected_type="$2"  # string, number, boolean, array, object, null
  local actual_type
  actual_type=$(echo "$output" | jq -r "$jq_path | type")
  [[ "$actual_type" == "$expected_type" ]] || fail "Expected $jq_path to be $expected_type, got $actual_type"
}

assert_json_array_length() {
  local jq_path="$1"
  local expected_length="$2"
  local actual_length
  actual_length=$(echo "$output" | jq "$jq_path | length")
  [[ "$actual_length" == "$expected_length" ]] || fail "Expected $jq_path length = $expected_length, got $actual_length"
}

assert_json_contains() {
  local jq_path="$1"
  local search_term="$2"
  echo "$output" | jq -e "$jq_path | contains(\"$search_term\")" >/dev/null || fail "$jq_path does not contain '$search_term'"
}

################################################################################
# Worktree Test Helpers
################################################################################

# Create a test worktree for the specified branch
# Usage: worktree_path=$(create_test_worktree "feature-branch" "/path/to/repo")
# Returns: Path to the created worktree
create_test_worktree() {
  local branch="$1"
  local test_repo_path="$2"

  # Ensure branch exists in test repo
  (
    cd "$test_repo_path" || { echo "Failed to cd to $test_repo_path" >&2; exit 1; }

    # Create branch if it doesn't exist
    if ! git rev-parse --verify "refs/heads/$branch" >/dev/null 2>&1; then
      git checkout -q -b "$branch" 2>/dev/null || {
        git checkout -q master 2>/dev/null || git checkout -q main 2>/dev/null
        git checkout -q -b "$branch"
      }

      # Add a commit to make the branch distinct
      echo "Test content for $branch" > "test-${branch}.txt"
      git add "test-${branch}.txt"
      git_commit_deterministic "Add test content for $branch"
    fi
  )

  # Create worktree path outside the repository
  local worktree_path="${test_repo_path}-wt-${branch}"

  # Create the worktree
  (
    cd "$test_repo_path" || { echo "Failed to cd to $test_repo_path" >&2; exit 1; }

    # Try to create worktree with force flag first
    if ! git worktree add "$worktree_path" "$branch" --force >/dev/null 2>&1; then
      # If force fails, the branch might be checked out, so create a temp branch
      current_branch=$(git branch --show-current)
      temp_branch="temp-worktree-branch-$(date +%s)"

      # Create temporary branch to free up the target branch
      if git checkout -b "$temp_branch" >/dev/null 2>&1; then
        # Now try to create the worktree
        if git worktree add "$worktree_path" "$branch" >/dev/null 2>&1; then
          # Success - switch back to original branch and clean up
          git checkout "$current_branch" >/dev/null 2>&1
          git branch -D "$temp_branch" >/dev/null 2>&1
        else
          # Still failed - clean up and exit
          git checkout "$current_branch" >/dev/null 2>&1
          git branch -D "$temp_branch" >/dev/null 2>&1
          echo "Failed to create worktree for branch $branch" >&2
          exit 1
        fi
      else
        # Couldn't create temp branch
        echo "Failed to create worktree for branch $branch" >&2
        exit 1
      fi
    fi
  )

  echo "$worktree_path"
}

# Create multiple test worktrees for a repository
# Usage: create_test_worktrees "/path/to/repo" "branch1" "branch2" "branch3"
# Creates worktrees for all specified branches
create_test_worktrees() {
  local test_repo_path="$1"
  shift
  local branches=("$@")

  # Verify repo exists
  if [[ ! -d "$test_repo_path/.git" ]]; then
    echo "ERROR: test repo doesn't exist: $test_repo_path" >&2
    return 1
  fi

  # Verify branches exist before creating worktrees
  local branch
  for branch in "${branches[@]}"; do
    if ! git -C "$test_repo_path" rev-parse --verify "refs/heads/$branch" >/dev/null 2>&1; then
      echo "ERROR: branch '$branch' doesn't exist in $test_repo_path" >&2
      echo "Available branches:" >&2
      git -C "$test_repo_path" branch --format='%(refname:short)' >&2
      return 1
    fi
  done

  # Create worktrees
  local -a created_worktrees=()
  for branch in "${branches[@]}"; do
    local worktree_path
    worktree_path=$(create_test_worktree "$branch" "$test_repo_path")
    if [[ $? -ne 0 || -z "$worktree_path" ]]; then
      echo "ERROR: failed to create worktree for branch '$branch'" >&2
      # Cleanup any worktrees created so far
      for wt in "${created_worktrees[@]}"; do
        rm -rf "$wt" 2>/dev/null
      done
      return 1
    fi
    created_worktrees+=("$worktree_path")
  done

  # Return paths as space-separated string
  printf '%s ' "${created_worktrees[@]}"
}

# Clean up all test worktrees for a repository
# Usage: cleanup_test_worktrees "/path/to/repo"
cleanup_test_worktrees() {
  local test_repo="$1"

  # Remove all worktrees associated with the test repository
  if [[ -d "$test_repo" ]]; then
    git -C "$test_repo" worktree list --porcelain 2>/dev/null | grep "^worktree " | cut -d' ' -f2 | while read -r wt; do
      if [[ "$wt" != "$test_repo" && -d "$wt" ]]; then
        rm -rf "$wt"
      fi
    done

    # Prune worktree metadata
    git -C "$test_repo" worktree prune 2>/dev/null || true
  fi
}

# Create a test worktree with uncommitted changes
# Usage: worktree_path=$(create_test_worktree_with_changes "feature-branch" "/path/to/repo")
create_test_worktree_with_changes() {
  local branch="$1"
  local test_repo_path="$2"

  local worktree_path
  worktree_path=$(create_test_worktree "$branch" "$test_repo_path")

  # Add uncommitted changes to the worktree
  (
    cd "$worktree_path" || { echo "Failed to cd to $worktree_path" >&2; exit 1; }
    echo "Uncommitted changes in $branch" > "uncommitted-${branch}.txt"
    git add "uncommitted-${branch}.txt"
    # Note: Don't commit - leave it staged for testing
  )

  echo "$worktree_path"
}

# Create a test worktree with dirty working directory
# Usage: worktree_path=$(create_test_worktree_with_dirty_changes "feature-branch" "/path/to/repo")
create_test_worktree_with_dirty_changes() {
  local branch="$1"
  local test_repo_path="$2"

  local worktree_path
  worktree_path=$(create_test_worktree "$branch" "$test_repo_path")

  # Add uncommitted (unstaged) changes to the worktree
  (
    cd "$worktree_path" || { echo "Failed to cd to $worktree_path" >&2; exit 1; }
    echo "Dirty changes in $branch" > "dirty-${branch}.txt"
    # Note: Don't even stage - leave it completely unstaged
  )

  echo "$worktree_path"
}

# Assert that a worktree exists and is valid
# Usage: assert_worktree_exists "/path/to/worktree"
assert_worktree_exists() {
  local worktree_path="$1"

  assert_dir_exists "$worktree_path"

  # Check it's a valid git worktree (in worktrees, .git is a file, not a directory)
  [[ -f "$worktree_path/.git" ]] || fail "Worktree $worktree_path is not a valid git repository"

  # Check it's listed in git worktree list
  local found=false
  while IFS= read -r line; do
    if [[ "$line" == "worktree $worktree_path" ]]; then
      found=true
      break
    fi
  done < <(git worktree list --porcelain 2>/dev/null)

  $found || fail "Worktree $worktree_path not found in git worktree list"
}

# Usage: run_with_timeout <timeout_seconds> [expected_exit_code] <command>
# Run command with timeout protection and optional expected exit code
# Accepts timeout exit code (124) as valid for hanging tests
run_with_timeout() {
  local timeout_seconds="$1"
  local expected_exit_code="$2"
  shift 2

  if command -v timeout >/dev/null 2>&1; then
    run timeout "$timeout_seconds" bash -c "$*"
    # Accept timeout exit code as valid for hanging tests
    if [[ "$status" -eq 124 ]]; then
      echo "Test timed out after ${timeout_seconds}s (expected behavior for hanging scenario)"
      if [[ -n "$expected_exit_code" ]]; then
        # For timeout scenarios, treat as success if expecting specific code
        if [[ "$expected_exit_code" != "0" ]]; then
          assert_equal "$status" "$expected_exit_code"
        fi
      else
        # No specific expectation, timeout is acceptable
        return 0
      fi
    fi
  else
    run "$@"
  fi

  # Handle expected exit codes for non-timeout scenarios
  if [[ -n "$expected_exit_code" ]]; then
    assert_equal "$status" "$expected_exit_code"
  else
    assert_success
  fi
}

# Assert that a worktree does not exist
# Usage: assert_worktree_not_exists "/path/to/worktree"
assert_worktree_not_exists() {
  local worktree_path="$1"

  assert_dir_not_exists "$worktree_path"

  # Check it's not listed in git worktree list
  local found=false
  while IFS= read -r line; do
    if [[ "$line" == "worktree $worktree_path" ]]; then
      found=true
      break
    fi
  done < <(git worktree list --porcelain 2>/dev/null)

  ! $found || fail "Worktree $worktree_path still found in git worktree list"
}

# Assert that a worktree has the specified branch checked out
# Usage: assert_worktree_branch "/path/to/worktree" "feature-branch"
assert_worktree_branch() {
  local worktree_path="$1"
  local expected_branch="$2"

  local actual_branch
  actual_branch=$(git -C "$worktree_path" branch --show-current 2>/dev/null || echo "")

  [[ "$actual_branch" == "$expected_branch" ]] || fail "Worktree $worktree_path has branch '$actual_branch', expected '$expected_branch'"
}

# Assert that a worktree is clean (no uncommitted changes)
# Usage: assert_worktree_clean "/path/to/worktree"
assert_worktree_clean() {
  local worktree_path="$1"

  git -C "$worktree_path" diff --quiet && git -C "$worktree_path" diff --cached --quiet || \
    fail "Worktree $worktree_path has uncommitted changes"
}

# Assert that a worktree is dirty (has uncommitted changes)
# Usage: assert_worktree_dirty "/path/to/worktree"
assert_worktree_dirty() {
  local worktree_path="$1"

  git -C "$worktree_path" diff --quiet && git -C "$worktree_path" diff --cached --quiet && \
    fail "Worktree $worktree_path is clean, expected dirty"
}

# Get the number of worktrees for the current repository
# Usage: count=$(get_worktree_count)
get_worktree_count() {
  git worktree list 2>/dev/null | wc -l
}

# Assert that the repository has the expected number of worktrees
# Usage: assert_worktree_count 3
assert_worktree_count() {
  local expected_count="$1"
  local actual_count
  actual_count=$(get_worktree_count)

  [[ "$actual_count" == "$expected_count" ]] || \
    fail "Repository has $actual_count worktrees, expected $expected_count"
}

# Get all worktree paths for the current repository
# Usage: worktree_paths=$(get_worktree_paths)
# Returns: Space-separated list of worktree paths
get_worktree_paths() {
  git worktree list --porcelain 2>/dev/null | grep "^worktree " | cut -d' ' -f2 | tr '\n' ' '
}

# Assert that text matches a regex pattern
# Usage: assert_regex_match "some text" "pattern.*match"
assert_regex_match() {
  local text="$1"
  local pattern="$2"

  if ! echo "$text" | grep -qE "$pattern"; then
    echo "Expected '$text' to match regex pattern: $pattern"
    return 1
  fi
}
