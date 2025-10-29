#!/usr/bin/env bash
#==============================================================================
# Cleanup VHS frame directories that may be created during image generation
# Extracts the last frame as the final image if needed
#==============================================================================

set -euo pipefail

IMG_DIR="${1:-docs/commands/img}"

# Color codes
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}Cleaning up VHS frame directories in ${IMG_DIR}...${NC}"

cd "$IMG_DIR" || exit 1

cleaned=0

for dir in */; do
    if [ -d "$dir" ]; then
        dir_name=$(basename "$dir")
        echo -e "${YELLOW}Found frame directory: ${dir_name}${NC}"
        
        # Check if there are frame files
        if ls "${dir}"frame-text-*.png > /dev/null 2>&1; then
            # Extract the last frame as the final image
            last_frame=$(ls "${dir}"frame-text-*.png 2>/dev/null | tail -1)
            if [ -n "$last_frame" ]; then
                echo "  Extracting last frame to ${dir_name}"
                cp "$last_frame" "${dir_name}"
            fi
        fi
        
        # Remove the frame directory
        echo "  Removing frame directory"
        rm -rf "$dir"
        ((cleaned++))
    fi
done

if [ $cleaned -gt 0 ]; then
    echo -e "${GREEN}Cleaned up $cleaned frame director(y|ies)${NC}"
else
    echo -e "${GREEN}No frame directories found${NC}"
fi
