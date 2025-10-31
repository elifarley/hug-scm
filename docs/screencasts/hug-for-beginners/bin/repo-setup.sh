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

echo -e "${BLUE}Creating beginner tutorial repository at ${DEMO_REPO_BASE}${NC}"

# Clean up any existing repo
rm -rf "$DEMO_REPO_BASE"

# Setup git user if not already configured
if [ -z "$(git config --global user.name 2>/dev/null || true)" ]; then
    git config --global user.name "Demo User"
    git config --global user.email "demo@example.com"
fi

# Create local repo
echo "Initializing empty repository..."
mkdir -p "$DEMO_REPO_BASE"
cd "$DEMO_REPO_BASE"
git init -b main

# Create minimal initial content - just enough for a complete tutorial
echo "Adding minimal initial content..."
cat > README.md << 'EOF'
# My First Project

A simple project to learn version control.
EOF
git add README.md
git commit -m "Initial commit"

echo -e "${GREEN}Beginner repository created successfully!${NC}"
echo "  Location: ${DEMO_REPO_BASE}"
echo "  Commits: $(git rev-list --all --count)"
echo "  Status: Clean working directory, ready for tutorial"
