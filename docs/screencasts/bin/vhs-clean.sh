#!/usr/bin/env bash
#==============================================================================
# vhs-clean.sh - Clean generated VHS images
#
# Removes all generated GIF and PNG files from VHS tape builds
#==============================================================================

set -euo pipefail

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCREENCASTS_DIR="$(dirname "$SCRIPT_DIR")"
DOCS_DIR="$(dirname "$SCREENCASTS_DIR")"

# Color codes
readonly GREEN='\033[0;32m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

msg() {
    local color=$1; shift
    echo -e "${color}$*${NC}"
}

info() { msg "$BLUE" "$*"; }
success() { msg "$GREEN" "$*"; }

main() {
    local count=0
    
    info "Cleaning VHS generated images..."
    
    # Clean command reference images (in docs/commands/img/)
    if [[ -d "$DOCS_DIR/commands/img" ]]; then
        count=$(find "$DOCS_DIR/commands/img" -name "hug-*.gif" -o -name "hug-*.png" | wc -l)
        find "$DOCS_DIR/commands/img" -name "hug-*.gif" -delete
        find "$DOCS_DIR/commands/img" -name "hug-*.png" -delete
    fi
    
    # Clean tutorial/workflow images (in docs/img/ subdirectories)
    if [[ -d "$DOCS_DIR/img" ]]; then
        local tutorial_count
        tutorial_count=$(find "$DOCS_DIR/img" -type f \( -name "*.gif" -o -name "*.png" \) | wc -l)
        find "$DOCS_DIR/img" -type f \( -name "*.gif" -o -name "*.png" \) -delete
        count=$((count + tutorial_count))
    fi
    
    if [[ $count -gt 0 ]]; then
        success "✓ Cleaned $count VHS-generated image(s)"
    else
        info "No VHS images found to clean"
    fi
}

main "$@"
