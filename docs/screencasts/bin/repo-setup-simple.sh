#!/usr/bin/env bash
#==============================================================================
# Simple demo repository setup for CI/CD and quick testing
# Creates a minimal repository with just enough structure for VHS demos
#==============================================================================

set -euo pipefail

DEMO_REPO_BASE="${1:-/tmp/demo-repo}"
REMOTE_BASE="${DEMO_REPO_BASE}.git"

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Wrapper function to ensure all git operations happen in DEMO_REPO_BASE
# This prevents accidental operations in the wrong directory
git() { (cd "$DEMO_REPO_BASE" && command git "$@") ;}

# Function for git operations in the remote (bare) repo
git_remote() { (cd "$REMOTE_BASE" && command git "$@") ;}

# Source consolidated deterministic git functions (DRY compliance)
source "$(dirname "${BASH_SOURCE[0]}")/../../../tests/lib/deterministic_git.bash"

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

# Create commits with overlapping file changes for dependency testing
echo "Creating commits with file dependencies..."

# Commit 1: Touch file1.txt and file2.txt
cat > "$DEMO_REPO_BASE/file1.txt" << 'EOF'
content1
EOF
cat > "$DEMO_REPO_BASE/file2.txt" << 'EOF'
content2
EOF
git add file1.txt file2.txt
git_commit_deterministic "feat: add feature A" 86400

# Commit 2: Touch file2.txt and file3.txt (related via file2.txt)
cat > "$DEMO_REPO_BASE/file2.txt" << 'EOF'
content2 updated
EOF
cat > "$DEMO_REPO_BASE/file3.txt" << 'EOF'
content3
EOF
git add file2.txt file3.txt
git_commit_deterministic "feat: extend feature A" 86400

# Commit 3: Touch file1.txt and file2.txt again (related to commit 1)
cat > "$DEMO_REPO_BASE/file1.txt" << 'EOF'
content1 updated
EOF
cat > "$DEMO_REPO_BASE/file2.txt" << 'EOF'
content2 updated again
EOF
git add file1.txt file2.txt
git_commit_deterministic "fix: bug in feature A" 86400

# Commit 4: Touch only file4.txt (unrelated to others)
cat > "$DEMO_REPO_BASE/file4.txt" << 'EOF'
content4
EOF
git add file4.txt
git_commit_deterministic "feat: add feature B" 86400

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
