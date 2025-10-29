#!/usr/bin/env bash
#==============================================================================
# vhs-build.sh - Build animated GIFs/PNGs from VHS tape files
#
# Usage:
#   vhs-build.sh [OPTIONS] [TAPE_FILE...]
#
# Options:
#   --all, -a           Build all .tape files in the screencasts directory
#   --dry-run, -n       Show what would be built without actually building
#   --parallel, -p      Build tapes in parallel (requires GNU parallel)
#   --check, -c         Check if VHS is installed and exit
#   --install-deps, -i  Install VHS if not present (exit after)
#   --help, -h          Show this help message
#
# Arguments:
#   TAPE_FILE...        Specific tape file(s) to build (optional)
#                       If no files specified and --all not used, builds all
#
# Examples:
#   vhs-build.sh --all                    # Build all tape files
#   vhs-build.sh hug-lol.tape             # Build specific tape
#   vhs-build.sh --dry-run hug-*.tape     # Preview what would be built
#   vhs-build.sh --parallel --all         # Build all in parallel
#   vhs-build.sh --install-deps           # Install VHS tool
#==============================================================================

set -euo pipefail

# Script directory (where this script is located)
CMD_BASE="$(readlink -f "$0" 2>/dev/null || greadlink -f "$0")" || CMD_BASE="$0"
CMD_BASE="$(dirname "$CMD_BASE")"

# Screencasts directory (parent of bin/)
SCREENCASTS_DIR="$(dirname "$CMD_BASE")"

# Output directory for images
OUTPUT_DIR="${SCREENCASTS_DIR}/../commands/img"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Command-line options
DRY_RUN=false
BUILD_ALL=false
PARALLEL=false
CHECK_ONLY=false
INSTALL_DEPS=false

#==============================================================================
# Helper Functions
#==============================================================================

# Print colored message
msg() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Print error message and exit
error() {
    msg "$RED" "ERROR: $*" >&2
    exit 1
}

# Print warning message
warn() {
    msg "$YELLOW" "WARNING: $*" >&2
}

# Print info message
info() {
    msg "$BLUE" "$*"
}

# Print success message
success() {
    msg "$GREEN" "$*"
}

# Check if VHS is installed
check_vhs() {
    if command -v vhs &> /dev/null; then
        info "VHS is installed: $(command -v vhs)"
        vhs --version
        return 0
    else
        warn "VHS is not installed."
        return 1
    fi
}

# Install VHS locally if not present
install_vhs() {
    local local_bin="$SCREENCASTS_DIR/bin/vhs"
    local tmp_dir=$(mktemp -d)

    # Check if already installed locally
    if [[ -x "$local_bin" ]] && command -v vhs &> /dev/null; then
        info "VHS already available locally at $local_bin"
        export PATH="$SCREENCASTS_DIR/bin:$PATH"
        return 0
    fi

    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)
    local os_name="$os"
    if [[ "$os" == "darwin" ]]; then
        os_name="Darwin"
    elif [[ "$os" != "linux" ]]; then
        warn "Unsupported OS: $os. Manual installation required."
        echo "Install VHS via: go install github.com/charmbracelet/vhs@latest"
        echo "or download from https://github.com/charmbracelet/vhs/releases"
        return 1
    fi

    if [[ "$arch" != "x86_64" && "$arch" != "amd64" && "$arch" != "arm64" ]]; then
        warn "Unsupported architecture: $arch. Manual installation required."
        echo "Install VHS via: go install github.com/charmbracelet/vhs@latest"
        echo "or download from https://github.com/charmbracelet/vhs/releases"
        return 1
    fi

    if [[ "$arch" == "x86_64" ]]; then
        arch="x86_64"
    elif [[ "$arch" == "amd64" ]]; then
        arch="x86_64"
    fi

    info "Installing VHS for $os_name $arch..."

    # Get latest release tag
    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/charmbracelet/vhs/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/v//')

    if [[ -z "$latest_version" ]]; then
        error "Failed to fetch latest VHS version from GitHub API"
    fi

    local download_url="https://github.com/charmbracelet/vhs/releases/download/v${latest_version}/vhs_${latest_version}_${os_name}_${arch}.tar.gz"
    local tmp_tar="${tmp_dir}/vhs.tar.gz"

    if ! curl -L -o "$tmp_tar" "$download_url" 2>/dev/null; then
        warn "Failed to download VHS from $download_url"
        echo "Manual installation required:"
        echo "go install github.com/charmbracelet/vhs@latest"
        echo "or visit https://github.com/charmbracelet/vhs/releases"
        rm -rf "$tmp_dir"
        return 1
    fi

    mkdir -p "$(dirname "$local_bin")"
    if tar -xzf "$tmp_tar" -C "$tmp_dir" vhs; then
        cp "$tmp_dir/vhs" "$local_bin"
        chmod +x "$local_bin"
        export PATH="$SCREENCASTS_DIR/bin:$PATH"
        success "VHS installed locally at $local_bin (version: $(vhs --version 2>/dev/null || echo 'unknown'))"
        rm -rf "$tmp_dir"
        return 0
    else
        warn "Failed to extract VHS binary"
        rm -rf "$tmp_dir"
        return 1
    fi
}

# Show usage information
usage() {
    sed -n '2,/^#==/p' "$0" | sed 's/^# \?//'
    exit 0
}

# Find all tape files in the screencasts directory
find_all_tapes() {
    find "$SCREENCASTS_DIR" -maxdepth 1 -name "*.tape" -type f | sort
}

# Build a single tape file
build_tape() {
    local tape_file=$1
    local tape_name=$(basename "$tape_file")
    
    info "Building: $tape_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY RUN] Would execute: vhs $tape_file"
        return 0
    fi
    
    # Change to screencasts directory before running vhs
    (
        cd "$SCREENCASTS_DIR" || exit 1
        if vhs "$tape_name"; then
            success "  ✓ Built: $tape_name"
            return 0
        else
            warn "  ✗ Failed to build: $tape_name"
            return 1
        fi
    )
}

# Build tapes in parallel
build_parallel() {
    local tapes=("$@")
    
    if ! command -v parallel &> /dev/null; then
        warn "GNU parallel not found, falling back to sequential build"
        for tape in "${tapes[@]}"; do
            build_tape "$tape" || true
        done
        return
    fi
    
    info "Building ${#tapes[@]} tape(s) in parallel..."
    printf '%s\n' "${tapes[@]}" | parallel -j 4 --line-buffer "$(declare -f build_tape msg info success warn); build_tape {}"
}

# Build tapes sequentially
build_sequential() {
    local tapes=("$@")
    local failed=0
    local total=${#tapes[@]}
    
    info "Building $total tape file(s) sequentially..."
    
    for tape in "${tapes[@]}"; do
        if ! build_tape "$tape"; then
            ((failed++)) || true
        fi
    done
    
    echo ""
    if [[ $failed -eq 0 ]]; then
        success "Successfully built all $total tape file(s)"
    else
        warn "Built $((total - failed))/$total tape file(s) ($failed failed)"
        return 1
    fi
}

#==============================================================================
# Main Script
#==============================================================================

# Parse command-line options
while [[ $# -gt 0 ]]; do
    case $1 in
        --all|-a)
            BUILD_ALL=true
            shift
            ;;
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --parallel|-p)
            PARALLEL=true
            shift
            ;;
        --check|-c)
            CHECK_ONLY=true
            shift
            ;;
        --install-deps|-i)
            INSTALL_DEPS=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        -*)
            error "Unknown option: $1\nUse --help for usage information"
            ;;
        *)
            break
            ;;
    esac
done

# Handle install-deps mode
if [[ "$INSTALL_DEPS" == "true" ]]; then
    if ! check_vhs; then
        install_vhs || {
            warn "VHS installation failed or manual installation required"
            exit 1
        }
    fi
    check_vhs
    exit 0
fi

# Check VHS installation
if [[ "$CHECK_ONLY" == "true" ]]; then
    check_vhs
    exit 0
fi

check_vhs || exit 1

# Collect tape files to build
TAPE_FILES=()

if [[ "$BUILD_ALL" == "true" ]]; then
    # Build all tapes in the screencasts directory
    while IFS= read -r tape; do
        TAPE_FILES+=("$tape")
    done < <(find_all_tapes)
    
    if [[ ${#TAPE_FILES[@]} -eq 0 ]]; then
        error "No .tape files found in $SCREENCASTS_DIR"
    fi
    
    info "Found ${#TAPE_FILES[@]} tape file(s) to build"
elif [[ $# -gt 0 ]]; then
    # Build specific tapes passed as arguments
    for arg in "$@"; do
        if [[ -f "$SCREENCASTS_DIR/$arg" ]]; then
            TAPE_FILES+=("$SCREENCASTS_DIR/$arg")
        elif [[ -f "$arg" ]]; then
            TAPE_FILES+=("$arg")
        else
            error "Tape file not found: $arg"
        fi
    done
else
    # Default: build all tapes
    while IFS= read -r tape; do
        TAPE_FILES+=("$tape")
    done < <(find_all_tapes)
    
    if [[ ${#TAPE_FILES[@]} -eq 0 ]]; then
        warn "No .tape files found in $SCREENCASTS_DIR"
        exit 0
    fi
    
    info "No specific files provided, building all ${#TAPE_FILES[@]} tape file(s)"
fi

# Show dry run info
if [[ "$DRY_RUN" == "true" ]]; then
    info "DRY RUN MODE - No files will be built"
fi

# Build the tapes
if [[ "$PARALLEL" == "true" ]]; then
    build_parallel "${TAPE_FILES[@]}"
else
    build_sequential "${TAPE_FILES[@]}"
fi

success "Build complete!"
