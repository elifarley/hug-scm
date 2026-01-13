#!/usr/bin/env bash
#==============================================================================
# Consolidated Deterministic Git Operations with Author Identity Support
#
# This library provides the FAKE_CLOCK system used by repo-setup scripts and
# test_helper.bash fixtures. All commits created with the enhanced functions will
# have fixed timestamps and configurable author identity, ensuring reproducible
# commit hashes across test runs while supporting per-commit author customization.
#
# Usage in test fixtures:
#   source tests/lib/deterministic_git.bash
#   git_commit_deterministic "commit message"  # Uses default author
#   git_commit_deterministic "commit message" 86400  # Use 1 day increment
#   git_commit_deterministic "commit message" 3600 "Custom Author" "custom@test.com"
#
# The clock starts at 2000-01-01 00:00:00 UTC and increments with each commit.
#==============================================================================

# --- Deterministic Timestamps for Repeatable Commit Hashes ---
# Initialize to a fixed starting date (2000-01-01 00:00:00 UTC)
FAKE_CLOCK_EPOCH=946684800
FAKE_CLOCK_CURRENT=$FAKE_CLOCK_EPOCH

# Consolidated function with enhanced author support
# Args:
#   $1 - Commit message (required)
#   $2 - Seconds to add to clock (optional, default: 3600 = 1 hour)
#   $3 - Author name (optional, default: "Hug Test")
#   $4 - Author email (optional, default: "test@hug-scm.test")
commit_with_date() {
  local message="$1"
  local seconds_offset="${2:-3600}"  # Default: 1 hour increment
  local author_name="${3:-Hug Test}" # Flexible author identity
  local author_email="${4:-test@hug-scm.test}"

  FAKE_CLOCK_CURRENT=$((FAKE_CLOCK_CURRENT + seconds_offset))
  local commit_date="${FAKE_CLOCK_CURRENT} +0000"

  GIT_AUTHOR_NAME="$author_name" \
    GIT_AUTHOR_EMAIL="$author_email" \
    GIT_COMMITTER_NAME="$author_name" \
    GIT_COMMITTER_EMAIL="$author_email" \
    GIT_AUTHOR_DATE="$commit_date" \
    GIT_COMMITTER_DATE="$commit_date" \
    git commit -q -m "$message"
}

# Enhanced backward-compatible function
# Args:
#   $1 - Commit message (required)
#   $2 - Seconds to add to clock (optional, default: 3600 = 1 hour)
#   $3 - Author name (optional, default: "Hug Test")
#   $4 - Author email (optional, default: "test@hug-scm.test")
git_commit_deterministic() {
  local message="$1"
  local seconds_offset="${2:-3600}"
  local author_name="${3:-Hug Test}"           # NEW: Optional author parameter
  local author_email="${4:-test@hug-scm.test}" # NEW: Optional email parameter

  # Delegate to consolidated function for DRY compliance
  commit_with_date "$message" "$seconds_offset" "$author_name" "$author_email"
}

# Convenience functions for common test scenarios
git_commit_deterministic_user1() {
  git_commit_deterministic "$1" "${2:-3600}" "Test User 1" "user1@test.hug-scm"
}

git_commit_deterministic_user2() {
  git_commit_deterministic "$1" "${2:-3600}" "Test User 2" "user2@test.hug-scm"
}

# Reset the clock to the epoch (useful between test fixtures)
reset_fake_clock() {
  FAKE_CLOCK_CURRENT=$FAKE_CLOCK_EPOCH
}
