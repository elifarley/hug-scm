#!/usr/bin/env bash
#==============================================================================
# vhs-build.sh - Build animated GIFs/PNGs from VHS tape files
#
# A streamlined tool for generating documentation images from VHS tape files.
# Supports parallel builds, dry-run mode, and automatic VHS installation.
#
# Usage:
#   vhs-build.sh [OPTIONS] [TAPE_FILE...]
#
# Options:
#   --all, -a           Build all .tape files in the screencasts directory
#   --dry-run, -n       Show what would be built without building
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

#==============================================================================
# Configuration
#==============================================================================

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCREENCASTS_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${SCREENCASTS_DIR}/../commands/img"
USER_DEPS_DIR="${VHS_DEPS_DIR:-$HOME/.hug-deps/bin}"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Options (defaults)
DRY_RUN=false
BUILD_ALL=false
PARALLEL=false
CHECK_ONLY=false
INSTALL_DEPS=false

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
# VHS Management
#==============================================================================

check_vhs() {
    # Check user deps and PATH
    export PATH="$USER_DEPS_DIR:$PATH"
    if command -v vhs &> /dev/null; then
        info "✓ VHS is installed: $(command -v vhs)"
        vhs --version
        return 0
    fi
    
    warn "✗ VHS is not installed"
    return 1
}

install_vhs() {
    local user_bin="$USER_DEPS_DIR/vhs"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    # Check if already installed in user dir
    if [[ -x "$user_bin" ]]; then
        info "✓ VHS already available at $user_bin"
        export PATH="$USER_DEPS_DIR:$PATH"
        return 0
    fi
    
    # Detect OS and architecture
    local os arch os_name
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    arch=$(uname -m)
    
    case "$os" in
        darwin) os_name="Darwin" ;;
        linux)  os_name="Linux" ;;
        *)
            warn "Unsupported OS: $os"
            info "Install VHS manually:"
            info "  • go install github.com/charmbracelet/vhs@latest"
            info "  • https://github.com/charmbracelet/vhs/releases"
            return 1
            ;;
    esac
    
    case "$arch" in
        x86_64|amd64) arch="x86_64" ;;
        arm64)        arch="arm64" ;;
        *)
            warn "Unsupported architecture: $arch"
            info "Install VHS manually:"
            info "  • go install github.com/charmbracelet/vhs@latest"
            info "  • https://github.com/charmbracelet/vhs/releases"
            return 1
            ;;
    esac
    
    info "Installing VHS for $os_name $arch..."
    
    # Try to get latest version, fall back to known stable version
    local version
    version=$(curl -sSL https://api.github.com/repos/charmbracelet/vhs/releases/latest \
        | grep '"tag_name":' \
        | sed -E 's/.*"v([^"]+)".*/\1/' 2>/dev/null) || true
    
    if [[ -z "$version" ]]; then
        warn "Could not fetch latest version from GitHub API, using fallback version"
        version="0.10.0"
        info "Using VHS v${version}"
    fi
    
    # Download and install
    local url="https://github.com/charmbracelet/vhs/releases/download/v${version}/vhs_${version}_${os_name}_${arch}.tar.gz"
    local tarball="$tmp_dir/vhs.tar.gz"
    
    info "Downloading VHS v${version}..."
    if ! curl -sSL -o "$tarball" "$url"; then
        warn "Download failed from: $url"
        info "Install VHS manually from: https://github.com/charmbracelet/vhs/releases"
        rm -rf "$tmp_dir"
        return 1
    fi
    
    info "Extracting..."
    # Extract all contents first, then find the vhs binary
    if tar -xzf "$tarball" -C "$tmp_dir" 2>/dev/null; then
        # Find the vhs binary (may be in root or subdirectory)
        local vhs_binary
        vhs_binary=$(find "$tmp_dir" -type f -name "vhs" -executable 2>/dev/null | head -1)
        
        if [[ -n "$vhs_binary" && -x "$vhs_binary" ]]; then
            mkdir -p "$USER_DEPS_DIR"
            mv "$vhs_binary" "$user_bin"
            chmod +x "$user_bin"
            export PATH="$USER_DEPS_DIR:$PATH"
            success "✓ VHS installed at $user_bin"
            rm -rf "$tmp_dir"
            return 0
        else
            warn "VHS binary not found in tarball"
            info "Contents of tarball:"
            tar -tzf "$tarball" | head -10
            rm -rf "$tmp_dir"
            return 1
        fi
    else
        warn "Failed to extract tarball"
        rm -rf "$tmp_dir"
        return 1
    fi
}

#==============================================================================
# Build Functions
#==============================================================================

find_tape_files() {
    # Find all .tape files in screencasts directory and subdirectories
    # Exclude setup.tape files at any level
    find "$SCREENCASTS_DIR" -name "*.tape" -type f ! -name "setup.tape"  ! -name "template.tape" | sort
}

build_single_tape() {
    local tape_file=$1
    local tape_name tape_dir tape_basename rel_path
    
    tape_basename=$(basename "$tape_file")
    tape_dir=$(dirname "$tape_file")
    
    # Calculate relative path from screencasts dir for display
    rel_path="${tape_file#$SCREENCASTS_DIR/}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY RUN] Would build: $rel_path"
        return 0
    fi
    
    info "Building: $rel_path"
    
    # Run VHS in the directory containing the tape file
    # This ensures relative paths in Source and Screenshot work correctly
    if (cd "$tape_dir" && vhs "$tape_basename" 2>&1); then
        success "  ✓ $rel_path"
        return 0
    else
        warn "  ✗ Failed: $rel_path"
        return 1
    fi
}

build_sequential() {
    local tapes=("$@")
    local failed=0
    local total=${#tapes[@]}
    
    info "Building $total tape file(s)..."
    echo ""
    
    for tape in "${tapes[@]}"; do
        build_single_tape "$tape" || ((failed++))
    done
    
    echo ""
    if [[ $failed -eq 0 ]]; then
        success "✓ Successfully built all $total tape file(s)"
        return 0
    else
        warn "⚠ Built $((total - failed))/$total tape file(s) ($failed failed)"
        return 1
    fi
}

build_parallel() {
    local tapes=("$@")
    
    if ! command -v parallel &> /dev/null; then
        warn "GNU parallel not found, using sequential build"
        build_sequential "${tapes[@]}"
        return
    fi
    
    info "Building ${#tapes[@]} tape(s) in parallel..."
    
    # Export functions for parallel
    export -f build_single_tape msg info success warn
    export SCREENCASTS_DIR DRY_RUN BLUE GREEN YELLOW NC
    
    printf '%s\n' "${tapes[@]}" | parallel -j 4 --line-buffer build_single_tape {}
    
    success "✓ Parallel build complete"
}

#==============================================================================
# Argument Parsing
#==============================================================================

show_help() {
    sed -n '2,/^#==/p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all|-a)         BUILD_ALL=true; shift ;;
            --dry-run|-n)     DRY_RUN=true; shift ;;
            --parallel|-p)    PARALLEL=true; shift ;;
            --check|-c)       CHECK_ONLY=true; shift ;;
            --install-deps|-i) INSTALL_DEPS=true; shift ;;
            --help|-h)        show_help ;;
            -*)               error "Unknown option: $1\nUse --help for usage" ;;
            *)                break ;;
        esac
    done
}

#==============================================================================
# Main
#==============================================================================

main() {
    # Parse arguments
    parse_args "$@"
    
    # Handle special modes
    if [[ "$INSTALL_DEPS" == "true" ]]; then
        check_vhs || install_vhs || exit 1
        check_vhs
        exit 0
    fi
    
    if [[ "$CHECK_ONLY" == "true" ]]; then
        check_vhs
        exit $?
    fi
    
    # Ensure VHS is available
    check_vhs || error "VHS not found. Run with --install-deps to install"
    
    # Collect tape files
    local tape_files=()
    
    if [[ "$BUILD_ALL" == "true" ]]; then
        while IFS= read -r tape; do
            tape_files+=("$tape")
        done < <(find_tape_files)
        
        [[ ${#tape_files[@]} -gt 0 ]] || error "No .tape files found in $SCREENCASTS_DIR"
        info "Found ${#tape_files[@]} tape file(s)"
        
    elif [[ $# -gt 0 ]]; then
        # Build specific files
        for arg in "$@"; do
            if [[ -f "$SCREENCASTS_DIR/$arg" ]]; then
                tape_files+=("$SCREENCASTS_DIR/$arg")
            elif [[ -f "$arg" ]]; then
                tape_files+=("$arg")
            else
                error "Tape file not found: $arg"
            fi
        done
    else
        # Default: build all
        while IFS= read -r tape; do
            tape_files+=("$tape")
        done < <(find_tape_files)
        
        if [[ ${#tape_files[@]} -eq 0 ]]; then
            warn "No .tape files found"
            exit 0
        fi
        
        info "No files specified, building all ${#tape_files[@]} tape file(s)"
    fi
    
    # Show mode
    [[ "$DRY_RUN" == "true" ]] && info "DRY RUN MODE - No files will be built"
    
    # Build
    if [[ "$PARALLEL" == "true" ]]; then
        build_parallel "${tape_files[@]}"
    else
        build_sequential "${tape_files[@]}"
    fi
}

# Run main function
main "$@"
