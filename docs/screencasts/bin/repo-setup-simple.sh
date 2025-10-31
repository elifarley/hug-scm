#!/usr/bin/env bash
#==============================================================================
# Simple demo repository setup for CI/CD and quick testing
# Creates a minimal repository with just enough structure for VHS demos
#==============================================================================

set -euo pipefail

DEMO_REPO_BASE="${1:-/tmp/demo-repo}"
REMOTE_BASE="/tmp/demo-repo.git"

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Wrapper function to ensure all git operations happen in DEMO_REPO_BASE
# This prevents accidental operations in the wrong directory
git() { (cd "$DEMO_REPO_BASE" && command git "$@") ;}

# Function for git operations in the remote (bare) repo
git_remote() { (cd "$REMOTE_BASE" && command git "$@") ;}

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

echo -e "${BLUE}Creating simple demo repository at ${DEMO_REPO_BASE}${NC}"

# Clean up any existing repos
rm -rf "$DEMO_REPO_BASE" "$REMOTE_BASE"

# Create bare remote
echo "Creating bare remote at ${REMOTE_BASE}..."
mkdir -p "$REMOTE_BASE"
git_remote init --bare

# Create local repo
echo "Creating local repository at ${DEMO_REPO_BASE}..."
mkdir -p "$DEMO_REPO_BASE"
git init -b main
git remote add origin "$REMOTE_BASE"

# Setup git user locally (not globally) for reliable VHS execution
git config user.name "Demo User"
git config user.email "demo@example.com"

# Create initial content
echo "Adding initial content..."
cat > "$DEMO_REPO_BASE/README.md" << 'EOF'
# Demo Repository

This is a demo repository for Hug SCM documentation and screencasts.
EOF
git add README.md
git_commit_deterministic "Initial commit"

cat > "$DEMO_REPO_BASE/app.js" << 'EOF'
console.log('hello');
EOF
git add app.js
git_commit_deterministic "feat: Add main app" 86400

cat > "$DEMO_REPO_BASE/.gitignore" << 'EOF'
node_modules/
dist/
.env
EOF
git add .gitignore
git_commit_deterministic "chore: Add gitignore" 86400

# Push to remote
echo "Pushing to remote..."
git push -u origin main

# Create a feature branch
echo "Creating feature branch..."
git checkout -b feature/search

cat > "$DEMO_REPO_BASE/search.js" << 'EOF'
// Search functionality
EOF
git add search.js
git_commit_deterministic "feat: Add search module" 86400

cat >> "$DEMO_REPO_BASE/search.js" << 'EOF'
function search(query) { 
    // Implementation here
}
EOF
git add search.js
git_commit_deterministic "feat: Implement search function" 3600

# Back to main
git checkout main

echo -e "${GREEN}Demo repository created successfully!${NC}"
echo "  Location: ${DEMO_REPO_BASE}"
echo "  Remote: ${REMOTE_BASE}"
echo "  Commits: $(git rev-list --all --count)"
echo "  Branches: $(git branch -a | wc -l)"
