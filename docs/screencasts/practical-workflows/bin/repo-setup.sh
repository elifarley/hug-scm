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

echo -e "${BLUE}Creating practical workflows repository at ${DEMO_REPO_BASE}${NC}"

# Clean up any existing repo
rm -rf "$DEMO_REPO_BASE"

# Setup git user if not already configured
if [ -z "$(git config --global user.name 2>/dev/null || true)" ]; then
    git config --global user.name "Demo User"
    git config --global user.email "demo@example.com"
fi

# Create local repo
echo "Initializing repository..."
mkdir -p "$DEMO_REPO_BASE"
cd "$DEMO_REPO_BASE"
git init -b main

# Create initial content with a realistic project structure
echo "Setting up project structure..."
cat > README.md << 'EOF'
# Web Application Project

A sample web application for demonstrating practical Git workflows.
EOF
git add README.md
git commit -m "Initial commit"

mkdir -p src
cat > src/app.js << 'EOF'
// Main application
console.log('App starting...');
EOF
git add src/app.js
git commit -m "feat: Add main application file"

cat > src/utils.js << 'EOF'
// Utility functions
function formatDate(date) {
    return date.toISOString();
}
EOF
git add src/utils.js
git commit -m "feat: Add utility functions"

cat > .gitignore << 'EOF'
node_modules/
dist/
.env
*.log
EOF
git add .gitignore
git commit -m "chore: Add gitignore"

echo -e "${GREEN}Practical workflows repository created successfully!${NC}"
echo "  Location: ${DEMO_REPO_BASE}"
echo "  Commits: $(git rev-list --all --count)"
echo "  Status: Ready for workflow demonstrations"
