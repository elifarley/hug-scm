#!/usr/bin/env bash
#==============================================================================
# vhs-commit-push.sh - Commit and push VHS image changes
#
# This script handles git operations for VHS-generated images.
# It's CI-aware and will only push when running in GitHub Actions.
#
# Usage:
#   vhs-commit-push.sh
#
# Environment Variables:
#   GITHUB_ACTIONS      - Set by GitHub Actions, triggers push
#   GITHUB_REF_NAME     - Branch name to push to (default: main)
#
# Exit Codes:
#   0 - Success (changes committed or no changes)
#   1 - Error during git operations
#==============================================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored message
msg() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

info() { msg "$BLUE" "$*"; }
success() { msg "$GREEN" "$*"; }
warn() { msg "$YELLOW" "$*"; }
error() { msg "$RED" "ERROR: $*" >&2; exit 1; }

#==============================================================================
# Main
#==============================================================================

info "Committing VHS image changes..."

# Stage image files
git add docs/commands/img/

# Check if there are changes
if git diff --staged --quiet; then
    warn "No changes to commit"
    exit 0
fi

# Show what will be committed
info "Changes to commit:"
git diff --staged --stat

# Commit changes
if ! git commit -m "chore: regenerate VHS documentation images [skip ci]"; then
    error "Failed to commit changes"
fi

success "Changes committed"

# Push if in CI environment
if [ -n "${GITHUB_ACTIONS:-}" ]; then
    BRANCH="${GITHUB_REF_NAME:-main}"
    info "Running in GitHub Actions, pushing to ${BRANCH}..."
    
    if git push origin "$BRANCH"; then
        success "Changes pushed to remote"
    else
        error "Failed to push changes"
    fi
else
    warn "Not in GitHub Actions - skipping push"
    info "To push manually, run: git push"
fi
