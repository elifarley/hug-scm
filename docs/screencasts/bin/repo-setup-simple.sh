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

echo -e "${BLUE}Creating simple demo repository at ${DEMO_REPO_BASE}${NC}"

# Clean up any existing repos
rm -rf "$DEMO_REPO_BASE" "$REMOTE_BASE"

# Setup git user if not already configured
if [ -z "$(git config --global user.name 2>/dev/null || true)" ]; then
    git config --global user.name "Demo User"
    git config --global user.email "demo@example.com"
fi

# Create bare remote
echo "Creating bare remote at ${REMOTE_BASE}..."
mkdir -p "$REMOTE_BASE"
cd "$REMOTE_BASE"
git init --bare

# Create local repo
echo "Creating local repository at ${DEMO_REPO_BASE}..."
mkdir -p "$DEMO_REPO_BASE"
cd "$DEMO_REPO_BASE"
git init -b main
git remote add origin "$REMOTE_BASE"

# Create initial content
echo "Adding initial content..."
cat > README.md << 'EOF'
# Demo Repository

This is a demo repository for Hug SCM documentation and screencasts.
EOF
git add README.md
git commit -m "Initial commit"

cat > app.js << 'EOF'
console.log('hello');
EOF
git add app.js
git commit -m "feat: Add main app"

cat > .gitignore << 'EOF'
node_modules/
dist/
.env
EOF
git add .gitignore
git commit -m "chore: Add gitignore"

# Push to remote
echo "Pushing to remote..."
git push -u origin main

# Create a feature branch
echo "Creating feature branch..."
git checkout -b feature/search

cat > search.js << 'EOF'
// Search functionality
EOF
git add search.js
git commit -m "feat: Add search module"

cat >> search.js << 'EOF'
function search(query) { 
    // Implementation here
}
EOF
git add search.js
git commit -m "feat: Implement search function"

# Back to main
git checkout main

echo -e "${GREEN}Demo repository created successfully!${NC}"
echo "  Location: ${DEMO_REPO_BASE}"
echo "  Remote: ${REMOTE_BASE}"
echo "  Commits: $(git rev-list --all --count)"
echo "  Branches: $(git branch -a | wc -l)"
