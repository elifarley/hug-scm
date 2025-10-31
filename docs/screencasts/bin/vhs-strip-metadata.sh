#!/usr/bin/env bash
#==============================================================================
# vhs-strip-metadata.sh - Strip metadata from PNG/GIF images for determinism
#
# Makes VHS-generated images deterministic by removing timestamp metadata.
# This ensures that regenerating images produces identical files if the
# content hasn't changed, avoiding unnecessary git commits.
#
# Usage:
#   vhs-strip-metadata.sh [OPTIONS]
#
# Options:
#   --dry-run, -n       Show what would be processed without processing
#   --help, -h          Show this help message
#
# Examples:
#   vhs-strip-metadata.sh              # Strip metadata from all images
#   vhs-strip-metadata.sh --dry-run    # Preview what would be processed
#
# Requirements:
#   - ImageMagick (convert command)
#==============================================================================

set -euo pipefail

#==============================================================================
# Configuration
#==============================================================================

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)/docs"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Options (defaults)
DRY_RUN=false

#==============================================================================
# Output Functions
#==============================================================================

msg() {
    local color=$1; shift
    echo -e "${color}$*${NC}"
}

info()    { msg "$BLUE"   "$*"; }
success() { msg "$GREEN"  "$*"; }
warn()    { msg "$YELLOW" "$*" >&2; }
error()   { msg "$RED"    "ERROR: $*" >&2; exit 1; }

#==============================================================================
# Core Functions
#==============================================================================

check_imagemagick() {
    if ! command -v convert &> /dev/null; then
        error "ImageMagick's 'convert' command not found.\nInstall it with: sudo apt-get install imagemagick"
    fi
}

strip_image_metadata() {
    local image_file=$1
    local rel_path="${image_file#$DOCS_DIR/}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY RUN] Would strip: $rel_path"
        return 0
    fi
    
    # Create temp file for the stripped version
    local temp_file="${image_file}.tmp"
    
    # Strip metadata using ImageMagick
    if convert "$image_file" -strip "$temp_file" 2>/dev/null; then
        # Replace original with stripped version
        mv "$temp_file" "$image_file"
        return 0
    else
        # Clean up temp file if conversion failed
        rm -f "$temp_file"
        warn "  ✗ Failed to strip: $rel_path"
        return 1
    fi
}

find_image_files() {
    # Find all PNG and GIF files in docs/**/img/ directories
    find "$DOCS_DIR" -type d -name "img" -exec find {} -type f \( -name "*.png" -o -name "*.gif" \) \; | sort
}

process_images() {
    local images=()
    
    # Collect all image files
    while IFS= read -r img; do
        images+=("$img")
    done < <(find_image_files)
    
    if [[ ${#images[@]} -eq 0 ]]; then
        warn "No PNG or GIF files found in $DOCS_DIR/**/img/"
        return 0
    fi
    
    info "Found ${#images[@]} image file(s) to process"
    [[ "$DRY_RUN" == "true" ]] && info "DRY RUN MODE - No files will be modified"
    
    local processed=0
    local failed=0
    
    for img in "${images[@]}"; do
        if strip_image_metadata "$img"; then
            ((processed++)) || true
        else
            ((failed++)) || true
        fi
    done
    
    echo ""
    if [[ $failed -eq 0 ]]; then
        success "✓ Successfully processed $processed image file(s)"
        return 0
    else
        warn "⚠ Processed $processed/$((processed + failed)) image file(s) ($failed failed)"
        return 1
    fi
}

#==============================================================================
# Argument Parsing
#==============================================================================

show_usage() {
    sed -n '2,/^#==/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run|-n)     DRY_RUN=true; shift ;;
            --help|-h)        show_usage ;;
            -*)               error "Unknown option: $1\nUse --help for usage" ;;
            *)                error "Unexpected argument: $1\nUse --help for usage" ;;
        esac
    done
}

#==============================================================================
# Main
#==============================================================================

main() {
    parse_args "$@"
    
    # Check dependencies
    check_imagemagick
    
    # Process images
    process_images
}

# Run main function
main "$@"
