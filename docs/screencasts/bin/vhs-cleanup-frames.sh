#!/usr/bin/env bash
#==============================================================================
# Cleanup VHS frame directories that may be created during image generation
# Extracts the last frame as the final image if needed
#
# VHS may create frame directories with the same name as the output file
# (e.g., a directory named "output.png/" containing frame files).
# This script extracts the last frame and replaces the directory with the file.
#
# Usage: 
#   vhs-cleanup-frames.sh [OPTIONS] [IMG_DIR]
#
# Options:
#   --verify        Verify that no frame directories remain (no cleanup)
#   --verify-strict Exit with error if frame directories are found
#
# Arguments:
#   IMG_DIR         Directory containing VHS output (default: docs/commands/img)
#==============================================================================

set -euo pipefail

# Parse options
VERIFY_MODE=false
VERIFY_STRICT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --verify)
            VERIFY_MODE=true
            shift
            ;;
        --verify-strict)
            VERIFY_MODE=true
            VERIFY_STRICT=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

IMG_DIR="${1:-docs/commands/img}"

# Color codes
RED='\033[0;31m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Verify mode: check for frame directories without cleaning
if [ "$VERIFY_MODE" = true ]; then
    echo -e "${BLUE}Verifying no frame directories remain in ${IMG_DIR}...${NC}"
    
    if [ ! -d "$IMG_DIR" ]; then
        echo -e "${RED}ERROR: Directory ${IMG_DIR} does not exist${NC}" >&2
        exit 1
    fi
    
    cd "$IMG_DIR" || exit 1
    
    # Find frame directories (directories with .png or .gif extensions)
    frame_dirs=$(find . -maxdepth 1 -type d \( -name "*.png" -o -name "*.gif" \) 2>/dev/null || true)
    
    if [ -n "$frame_dirs" ]; then
        frame_count=$(echo "$frame_dirs" | wc -l)
        if [ "$VERIFY_STRICT" = true ]; then
            echo -e "${RED}✗ Verification failed: Found $frame_count frame director(y|ies):${NC}" >&2
            echo "$frame_dirs" | sed 's|^\./||' >&2
            exit 1
        else
            echo -e "${YELLOW}⚠ Warning: Found $frame_count frame director(y|ies):${NC}"
            echo "$frame_dirs" | sed 's|^\./||'
            exit 0
        fi
    else
        echo -e "${GREEN}✓ Verification passed: No frame directories found${NC}"
        exit 0
    fi
fi

# Normal cleanup mode
echo -e "${BLUE}Cleaning up VHS frame directories in ${IMG_DIR}...${NC}"

cd "$IMG_DIR" || exit 1

cleaned=0
skipped=0
errors=0

for dir in */; do
    # Skip if not a directory (can happen with glob expansion)
    [ -d "$dir" ] || continue
    
    dir_name=$(basename "$dir")
    
    # Only process directories that look like VHS frame directories
    # (contain frame-text-*.png files)
    if ! ls "${dir}"frame-text-*.png > /dev/null 2>&1; then
        echo -e "${YELLOW}Skipping non-frame directory: ${dir_name}${NC}"
        skipped=$((skipped + 1))
        continue
    fi
    
    echo -e "${YELLOW}Found frame directory: ${dir_name}${NC}"
    
    # Extract the last frame as the final image
    last_frame=$(ls "${dir}"frame-text-*.png 2>/dev/null | sort | tail -1)
    
    if [ -z "$last_frame" ]; then
        echo -e "  ${YELLOW}No frames found, removing directory${NC}"
        rm -rf "$dir"
        skipped=$((skipped + 1))
        continue
    fi
    
    echo "  Extracting last frame to ${dir_name}"
    
    # Use a temporary file to avoid conflicts when dir_name equals an existing directory
    temp_file=".temp-${dir_name}.$$"
    
    # Copy the last frame to temp file
    if ! cp "$last_frame" "$temp_file" 2>/dev/null; then
        echo -e "  ${RED}ERROR: Failed to copy frame${NC}" >&2
        errors=$((errors + 1))
        continue
    fi
    
    # Remove the frame directory
    echo "  Removing frame directory"
    if ! rm -rf "$dir" 2>/dev/null; then
        echo -e "  ${RED}ERROR: Failed to remove directory${NC}" >&2
        rm -f "$temp_file"
        errors=$((errors + 1))
        continue
    fi
    
    # Move temp file to final location
    if ! mv "$temp_file" "$dir_name" 2>/dev/null; then
        echo -e "  ${RED}ERROR: Failed to create final file${NC}" >&2
        rm -f "$temp_file"
        errors=$((errors + 1))
        continue
    fi
    
    cleaned=$((cleaned + 1))
    echo -e "  ${GREEN}✓ Successfully extracted to ${dir_name}${NC}"
done

# Summary
echo ""
if [ $cleaned -gt 0 ]; then
    echo -e "${GREEN}✓ Successfully cleaned up $cleaned frame director(y|ies)${NC}"
fi
if [ $skipped -gt 0 ]; then
    echo -e "${YELLOW}⊘ Skipped $skipped director(y|ies)${NC}"
fi
if [ $errors -gt 0 ]; then
    echo -e "${RED}✗ Encountered $errors error(s)${NC}" >&2
    exit 1
fi
if [ $cleaned -eq 0 ] && [ $skipped -eq 0 ]; then
    echo -e "${GREEN}No frame directories found${NC}"
fi
