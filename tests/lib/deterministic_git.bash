#!/usr/bin/env bash
#==============================================================================
# Deterministic Git Operations for Test Reproducibility
#
# This library provides the FAKE_CLOCK system used by repo-setup scripts,
# extracted for reuse in test_helper.bash fixtures. All commits created with
# git_commit_deterministic() will have fixed timestamps, ensuring reproducible
# commit hashes across test runs.
#
# Usage in test fixtures:
#   source tests/lib/deterministic_git.bash
#   git_commit_deterministic "commit message"  # Uses 1 hour increment
#   git_commit_deterministic "commit message" 86400  # Use 1 day increment
#
# The clock starts at 2000-01-01 00:00:00 UTC and increments with each commit.
#==============================================================================

# --- Deterministic Timestamps for Repeatable Commit Hashes ---
# Initialize to a fixed starting date (2000-01-01 00:00:00 UTC)
FAKE_CLOCK_EPOCH=946684800
FAKE_CLOCK_CURRENT=$FAKE_CLOCK_EPOCH

# Helper function to create commits with deterministic timestamps
# Args:
#   $1 - Commit message (required)
#   $2 - Seconds to add to clock (optional, default: 3600 = 1 hour)
git_commit_deterministic() {
    local message="$1"
    local seconds_offset="${2:-3600}"  # Default: 1 hour increment

    FAKE_CLOCK_CURRENT=$((FAKE_CLOCK_CURRENT + seconds_offset))
    local commit_date="${FAKE_CLOCK_CURRENT} +0000"

    GIT_AUTHOR_DATE="$commit_date" \
    GIT_COMMITTER_DATE="$commit_date" \
    git commit -q -m "$message"
}

# Reset the clock to the epoch (useful between test fixtures)
reset_fake_clock() {
    FAKE_CLOCK_CURRENT=$FAKE_CLOCK_EPOCH
}
