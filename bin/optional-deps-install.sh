#!/usr/bin/env bash
#==============================================================================
# optional-deps-install.sh - Install optional dependencies for Hug SCM
#
# This script installs optional tools that enhance Hug's functionality.
# Currently supports:
#   - gum: Interactive filter/prompt tool from Charm Bracelet
#          Used by commands like 'hug brestore' for better UX
#
# Usage:
#   optional-deps-install.sh [OPTIONS]
#
# Options:
#   --check, -c         Check if optional tools are installed
#   --help, -h          Show this help message
#
# Environment:
#   OPTIONAL_DEPS_DIR   Installation directory (default: $HOME/.hug-deps/bin)
#
# Examples:
#   optional-deps-install.sh          # Install all optional tools
#   optional-deps-install.sh --check  # Check installation status
#==============================================================================

set -euo pipefail

#==============================================================================
# Configuration
#==============================================================================

OPTIONAL_DEPS_DIR="${OPTIONAL_DEPS_DIR:-$HOME/.hug-deps/bin}"

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Options
CHECK_ONLY=false

#==============================================================================
# Output Functions
#==============================================================================

msg() {
  local color=$1
  shift
  echo -e "${color}$*${NC}"
}

info() { msg "$BLUE" "$*"; }
success() { msg "$GREEN" "$*"; }
warn() { msg "$YELLOW" "$*" >&2; }
error() {
  msg "$RED" "ERROR: $*" >&2
  exit 1
}

#==============================================================================
# Gum Installation
#==============================================================================

check_gum() {
  # Check user deps and PATH
  export PATH="$OPTIONAL_DEPS_DIR:$PATH"
  if command -v gum &> /dev/null; then
    info "✓ gum is installed: $(command -v gum)"
    gum --version
    return
  fi

  warn "✗ gum is not installed"
  return 1
}

install_gum() {
  local user_bin="$OPTIONAL_DEPS_DIR/gum"
  local tmp_dir
  tmp_dir=$(mktemp -d)

  # Check if already installed in user dir
  if [[ -x "$user_bin" ]]; then
    info "✓ gum already available at $user_bin"
    export PATH="$OPTIONAL_DEPS_DIR:$PATH"
    return 0
  fi

  # Detect OS and architecture
  local os arch os_name
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  arch=$(uname -m)

  case "$os" in
  darwin) os_name="Darwin" ;;
  linux) os_name="Linux" ;;
  *)
    warn "Unsupported OS: $os"
    info "Install gum manually:"
    info "  • go install github.com/charmbracelet/gum@latest"
    info "  • https://github.com/charmbracelet/gum/releases"
    return 1
    ;;
  esac

  case "$arch" in
  x86_64 | amd64) arch="x86_64" ;;
  arm64) arch="arm64" ;;
  aarch64) arch="arm64" ;;
  *)
    warn "Unsupported architecture: $arch"
    info "Install gum manually:"
    info "  • go install github.com/charmbracelet/gum@latest"
    info "  • https://github.com/charmbracelet/gum/releases"
    return 1
    ;;
  esac

  info "Installing gum for $os_name $arch..."

  # Try to get latest version, fall back to known stable version
  local version
  version=$(curl -sSL https://api.github.com/repos/charmbracelet/gum/releases/latest |
    grep '"tag_name":' |
    sed -E 's/.*"v([^"]+)".*/\1/' 2> /dev/null) || true

  if [[ -z "$version" ]]; then
    warn "Could not fetch latest version from GitHub API, using fallback version"
    version="0.17.0"
    info "Using gum v${version}"
  fi

  # Download and install
  local url="https://github.com/charmbracelet/gum/releases/download/v${version}/gum_${version}_${os_name}_${arch}.tar.gz"
  local tarball="$tmp_dir/gum.tar.gz"

  info "Downloading gum v${version}..."
  if ! curl -sSL -o "$tarball" "$url"; then
    warn "Download failed from: $url"
    info "Install gum manually from: https://github.com/charmbracelet/gum/releases"
    rm -rf "$tmp_dir"
    return 1
  fi

  info "Extracting..."
  # Extract all contents first, then find the gum binary
  if tar -xzf "$tarball" -C "$tmp_dir" 2> /dev/null; then
    # Find the gum binary (may be in root or subdirectory)
    local gum_binary
    gum_binary=$(find "$tmp_dir" -type f -name "gum" -executable 2> /dev/null | head -1)

    if [[ -n "$gum_binary" && -x "$gum_binary" ]]; then
      mkdir -p "$OPTIONAL_DEPS_DIR"
      mv "$gum_binary" "$user_bin"
      chmod +x "$user_bin"
      export PATH="$OPTIONAL_DEPS_DIR:$PATH"
      success "✓ gum installed at $user_bin"
      rm -rf "$tmp_dir"
      return 0
    else
      warn "gum binary not found in tarball"
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
# Main Functions
#==============================================================================

show_help() {
  cat << 'EOF'
optional-deps-install.sh - Install optional dependencies for Hug SCM

USAGE:
    optional-deps-install.sh [OPTIONS]

OPTIONS:
    --check, -c         Check if optional tools are installed
    --help, -h          Show this help message

ENVIRONMENT:
    OPTIONAL_DEPS_DIR   Installation directory (default: $HOME/.hug-deps/bin)

DESCRIPTION:
    Installs optional tools that enhance Hug's functionality:
    
    • gum: Interactive filter/prompt tool from Charm Bracelet
           Used by commands like 'hug brestore' for better UX
           https://github.com/charmbracelet/gum

EXAMPLES:
    optional-deps-install.sh          # Install all optional tools
    optional-deps-install.sh --check  # Check installation status

SEE ALSO:
    make optional-deps-install        # Install via Makefile
    make test-deps-install            # Install test dependencies
    make vhs-deps-install             # Install VHS for screencasts
EOF
}

check_all() {
  info "Checking optional dependencies..."
  echo ""

  local all_installed=true

  if ! check_gum; then
    all_installed=false
  fi

  echo ""
  if [[ "$all_installed" == "true" ]]; then
    success "✓ All optional dependencies are installed"
    return 0
  else
    info "Some optional dependencies are not installed"
    info "Run 'make optional-deps-install' to install them"
    return 1
  fi
}

install_all() {
  info "Installing optional dependencies to: $OPTIONAL_DEPS_DIR"
  echo ""

  local install_failed=false

  if ! install_gum; then
    install_failed=true
    warn "Failed to install gum"
  fi

  echo ""
  if [[ "$install_failed" == "true" ]]; then
    warn "Some installations failed - see messages above"
    info "You can still use Hug, but some features may not be available"
    return 1
  else
    success "✓ All optional dependencies installed successfully"
    info ""
    info "Add to your PATH: export PATH=\"$OPTIONAL_DEPS_DIR:\$PATH\""
    info "Or activate Hug with: source bin/activate"
    return 0
  fi
}

#==============================================================================
# Argument Parsing
#==============================================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
  -c | --check)
    CHECK_ONLY=true
    shift
    ;;
  -h | --help)
    show_help
    exit 0
    ;;
  *)
    error "Unknown option: $1\nUse --help for usage"
    ;;
  esac
done

#==============================================================================
# Main Execution
#==============================================================================

if [[ "$CHECK_ONLY" == "true" ]]; then
  check_all
else
  install_all
fi
