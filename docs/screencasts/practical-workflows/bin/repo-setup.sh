#!/usr/bin/env bash
#==============================================================================
# Practical workflows repository setup
# Creates a repository with realistic development scenarios
#==============================================================================

set -euo pipefail

DEMO_REPO_BASE="${1:-/tmp/workflows-repo}"

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

echo -e "${BLUE}Creating practical workflows repository at ${DEMO_REPO_BASE}${NC}"

# Clean up any existing repo
rm -rf "$DEMO_REPO_BASE"

# Setup git user if not already configured
if [ -z "$(command git config --global user.name 2>/dev/null || true)" ]; then
    command git config --global user.name "Demo User"
    command git config --global user.email "demo@example.com"
fi

# Create local repo
echo "Initializing repository..."
mkdir -p "$DEMO_REPO_BASE"
git init -b main

# Create initial content with a realistic project structure
echo "Setting up project structure..."
cat > "$DEMO_REPO_BASE/README.md" << 'EOF'
# Web Application Project

A sample web application for demonstrating practical Git workflows.
EOF
git add README.md
git_commit_deterministic "Initial commit"

mkdir -p "$DEMO_REPO_BASE/src"
cat > "$DEMO_REPO_BASE/src/app.js" << 'EOF'
// Main application
console.log('App starting...');
EOF
git add src/app.js
git_commit_deterministic "feat: Add main application file" 86400

cat > "$DEMO_REPO_BASE/src/utils.js" << 'EOF'
// Utility functions
function formatDate(date) {
    return date.toISOString();
}
EOF
git add src/utils.js
git_commit_deterministic "feat: Add utility functions" 86400

cat > "$DEMO_REPO_BASE/.gitignore" << 'EOF'
node_modules/
dist/
.env
*.log
EOF
git add .gitignore
git_commit_deterministic "chore: Add gitignore" 86400

echo -e "${GREEN}Practical workflows repository created successfully!${NC}"
echo "  Location: ${DEMO_REPO_BASE}"
echo "  Commits: $(git rev-list --all --count)"
echo "  Status: Ready for workflow demonstrations"
