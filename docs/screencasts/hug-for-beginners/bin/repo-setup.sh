#!/usr/bin/env bash
#==============================================================================
# Beginner tutorial repository setup
# Creates a minimal, clean repository perfect for learning the basics
#==============================================================================

set -euo pipefail

DEMO_REPO_BASE="${1:-/tmp/beginner-repo}"

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Wrapper function to ensure all git operations happen in DEMO_REPO_BASE
# This prevents accidental operations in the wrong directory
git() { (cd "$DEMO_REPO_BASE" && command git "$@") ;}

# --- Deterministic Timestamps for Repeatable Commit Hashes ---
# Initialize to a fixed starting date (2000-01-01 00:00:00 UTC)
FAKE_CLOCK_EPOCH=946684800
FAKE_CLOCK_CURRENT=$FAKE_CLOCK_EPOCH

# Helper function to create commits with deterministic timestamps
git_commit_deterministic() {
    local message="$1"
    local seconds_offset="${2:-3600}"  # Default: 1 hour increment
    
    FAKE_CLOCK_CURRENT=$((FAKE_CLOCK_CURRENT + seconds_offset))
    local commit_date="${FAKE_CLOCK_CURRENT} +0000"
    
    GIT_AUTHOR_DATE="$commit_date" \
    GIT_COMMITTER_DATE="$commit_date" \
    git commit -m "$message"
}

echo -e "${BLUE}Creating beginner tutorial repository at ${DEMO_REPO_BASE}${NC}"

# Clean up any existing repo
rm -rf "$DEMO_REPO_BASE"

# Create local repo
echo "Initializing empty repository..."
mkdir -p "$DEMO_REPO_BASE"
git init -b main

# Setup git user locally (not globally) for reliable VHS execution
git config user.name "Demo User"
git config user.email "demo@example.com"

# Create minimal initial content - just enough for a complete tutorial
echo "Adding minimal initial content..."
cat > "$DEMO_REPO_BASE/README.md" << 'EOF'
# My First Project

A simple project to learn version control.
EOF
git add README.md
git_commit_deterministic "Initial commit"

echo -e "${GREEN}Beginner repository created successfully!${NC}"
echo "  Location: ${DEMO_REPO_BASE}"
echo "  Commits: $(git rev-list --all --count)"
echo "  Status: Clean working directory, ready for tutorial"
