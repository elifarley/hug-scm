#!/usr/bin/env bash
# test-repo-builder.sh - Library for creating isolated test repositories
# Extracted from docs/screencasts/bin/repo-setup.sh patterns

# Prevent multiple sourcing
if [[ "${TEST_REPO_BUILDER_LOADED:-}" == "true" ]]; then
  return 0
fi
TEST_REPO_BUILDER_LOADED=true

# Default author information for test commits
readonly TEST_AUTHOR_NAME="Hug Test"
readonly TEST_AUTHOR_EMAIL="test@hug-scm.test"

# Global variable to track current test repo
TEST_REPO_BASE=""

# --- Fake Clock System for Deterministic Commit Hashes ---
# Initialize fake clock to a fixed starting date
# This ensures all commits have deterministic dates and thus deterministic hashes
FAKE_CLOCK_EPOCH=946684800 # 2000-01-01 00:00:00 UTC

# Current fake timestamp (will be advanced with each commit)
FAKE_CLOCK_CURRENT=$FAKE_CLOCK_EPOCH

# Advances the fake clock by a specified delta
# Usage: advance_clock <amount> <unit>
advance_clock() {
  local amount=$1
  local unit=$2
  local seconds=0

  case "$unit" in
  minute | minutes)
    seconds=$((amount * 60))
    ;;
  hour | hours)
    seconds=$((amount * 3600))
    ;;
  day | days)
    seconds=$((amount * 86400))
    ;;
  week | weeks)
    seconds=$((amount * 604800))
    ;;
  month | months)
    # Approximate: 30.44 days per month
    seconds=$((amount * 2629800))
    ;;
  year | years)
    # Approximate: 365.25 days per year
    seconds=$((amount * 31557600))
    ;;
  *)
    echo "Error: Unknown time unit: $unit" >&2
    return 1
    ;;
  esac

  FAKE_CLOCK_CURRENT=$((FAKE_CLOCK_CURRENT + seconds))
}

# Executes a hug command as a specific author with deterministic dates.
# Usage: commit_with_date <time_delta> <time_unit> "Author Name" "author@email.com" <hug command and args>
# Example: commit_with_date 2 days "Alice Smith" "alice@example.com" c -m "Add feature"
commit_with_date() {
  local time_amount="$1"
  shift
  local time_unit="$1"
  shift
  local author_name="$1"
  shift
  local author_email="$1"
  shift

  # Advance the fake clock
  advance_clock "$time_amount" "$time_unit"

  # Format the timestamp for git (ISO 8601 format with timezone)
  local commit_date="${FAKE_CLOCK_CURRENT} +0000"

  # Execute the command with all environment variables set for deterministic commits
  GIT_AUTHOR_NAME="$author_name" \
    GIT_AUTHOR_EMAIL="$author_email" \
    GIT_AUTHOR_DATE="$commit_date" \
    GIT_COMMITTER_NAME="$author_name" \
    GIT_COMMITTER_EMAIL="$author_email" \
    GIT_COMMITTER_DATE="$commit_date" \
    repo_hug "$@"
}

# Executes a hug command as a specific author.
# Usage: as_author "Author Name" "author@email.com" hug c -m 'message'
as_author() (
  local author_name="$1"
  shift
  local author_email="$1"
  shift

  GIT_AUTHOR_NAME="$author_name" GIT_AUTHOR_EMAIL="$author_email" \
    GIT_COMMITTER_NAME="$author_name" GIT_COMMITTER_EMAIL="$author_email" \
    repo_hug "$@"
)

# Creates a completely isolated test repository
# Usage: create_isolated_repo [repo_name]
# Returns the path to the created repository
create_isolated_repo() {
  local repo_name="${1:-test-repo-$(date +%s)}"
  TEST_REPO_BASE="$(mktemp -d -t "${repo_name}-XXXXXX" 2> /dev/null || mktemp -d "/tmp/${repo_name}-XXXXXX")"

  # Create the directory and initialize the git repository
  mkdir -p "$TEST_REPO_BASE"
  cd "$TEST_REPO_BASE"
  repo_git init -b main

  # Configure git aliases needed by hug commands
  # These are from git-config/.gitconfig
  repo_git config --local alias.ll "log --graph --pretty=log1 --date=short"
  repo_git config --local pretty.log1 "%C(bold blue)%h%C(reset) %C(white)%ad%C(reset) %C(dim white)%an%C(reset)%C(auto)%d%C(reset) %s"

  # Create initial commit with deterministic timestamp
  reset_fake_clock
  echo "# Test Repository" > README.md
  repo_git add README.md
  commit_with_date 0 minutes "$TEST_AUTHOR_NAME" "$TEST_AUTHOR_EMAIL" c -m "Initial commit"

  echo "$TEST_REPO_BASE"
}

# Wrapper function that runs hug commands in the test repo
# Usage: repo_hug <command> [args...]
repo_hug() {
  if [[ -z "$TEST_REPO_BASE" ]]; then
    echo "Error: TEST_REPO_BASE not set. Call create_isolated_repo() first." >&2
    return 1
  fi

  # Find hug binary relative to this script
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local hug_bin="$script_dir/bin/hug"

  cd "$TEST_REPO_BASE" && "$hug_bin" "$@"
}

# Wrapper function that runs git commands in the test repo
# Usage: repo_git <command> [args...]
repo_git() {
  if [[ -z "$TEST_REPO_BASE" ]]; then
    echo "Error: TEST_REPO_BASE not set. Call create_isolated_repo() first." >&2
    return 1
  fi

  cd "$TEST_REPO_BASE" && command git "$@"
}

# Reset the fake clock to the epoch
reset_fake_clock() {
  FAKE_CLOCK_CURRENT=$FAKE_CLOCK_EPOCH
}

# Get the current test repo path
# Usage: get_test_repo_path
get_test_repo_path() {
  echo "$TEST_REPO_BASE"
}

# Clean up the test repository
# Usage: cleanup_test_repo
cleanup_test_repo() {
  if [[ -n "$TEST_REPO_BASE" && -d "$TEST_REPO_BASE" ]]; then
    rm -rf "$TEST_REPO_BASE"
    TEST_REPO_BASE=""
  fi
}

# Create a test repository with some history
# Usage: create_test_repo_with_history [repo_name]
create_test_repo_with_history() {
  local repo_path
  repo_path=$(create_isolated_repo "${1:-test-repo-history-$(date +%s)}")

  # Add a few more commits with deterministic timestamps
  cd "$TEST_REPO_BASE"
  echo "Feature 1" > feature1.txt
  repo_git add feature1.txt
  commit_with_date 1 day "$TEST_AUTHOR_NAME" "$TEST_AUTHOR_EMAIL" c -m "Add feature 1"

  echo "Feature 2" > feature2.txt
  repo_git add feature2.txt
  commit_with_date 1 day "$TEST_AUTHOR_NAME" "$TEST_AUTHOR_EMAIL" c -m "Add feature 2"

  echo "$repo_path"
}

# Create a test repository with staged and unstaged changes
# Usage: create_test_repo_with_changes [repo_name]
create_test_repo_with_changes() {
  local repo_path
  repo_path=$(create_isolated_repo "${1:-test-repo-changes-$(date +%s)}")

  cd "$TEST_REPO_BASE"

  # Staged changes
  echo "Staged content" > staged.txt
  repo_hug a staged.txt

  # Unstaged changes
  echo "Modified content" >> README.md

  # Untracked file
  echo "Untracked content" > untracked.txt

  echo "$repo_path"
}

# Export functions if sourced from a shell
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  export -f create_isolated_repo
  export -f repo_hug
  export -f repo_git
  export -f commit_with_date
  export -f as_author
  export -f reset_fake_clock
  export -f get_test_repo_path
  export -f cleanup_test_repo
  export -f create_test_repo_with_history
  export -f create_test_repo_with_changes
fi
