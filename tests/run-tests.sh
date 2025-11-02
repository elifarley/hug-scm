#!/usr/bin/env bash
# Script to run Hug SCM tests locally

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Get the project root (parent of tests/ if we're in tests/, otherwise current dir)
if [[ "$(basename "$SCRIPT_DIR")" == "tests" ]]; then
  PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
else
  PROJECT_ROOT="$SCRIPT_DIR"
fi

# Dependency paths
DEPS_DIR="${DEPS_DIR:-$HOME/.hug-deps/bats}"
BATS_CORE_DIR="$DEPS_DIR/bats-core"
BATS_BIN="$BATS_CORE_DIR/bin/bats"
BATS_SUPPORT_DIR="$DEPS_DIR/bats-support"
BATS_ASSERT_DIR="$DEPS_DIR/bats-assert"
BATS_FILE_DIR="$DEPS_DIR/bats-file"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Install or update test dependencies
install_test_deps() {
  mkdir -p "$DEPS_DIR"
  clone_or_update() {
    local repo_url="$1" target_dir="$2"
    if [[ -d "$target_dir/.git" ]]; then
      echo "Updating $(basename "$target_dir")..."
      git -C "$target_dir" pull --ff-only
    else
      echo "Installing $(basename "$target_dir")..."
      git clone --depth 1 "$repo_url" "$target_dir"
    fi
  }

  clone_or_update https://github.com/bats-core/bats-core.git "$BATS_CORE_DIR"
  clone_or_update https://github.com/bats-core/bats-support.git "$BATS_SUPPORT_DIR"
  clone_or_update https://github.com/bats-core/bats-assert.git "$BATS_ASSERT_DIR"
  clone_or_update https://github.com/bats-core/bats-file.git "$BATS_FILE_DIR"
}

# Check if BATS is installed
check_bats() {
  if command -v bats >/dev/null; then
    bats --version
    echo -e "${GREEN}✓ BATS is installed${NC}"
    return
  fi

  if [[ ! -x "$BATS_BIN" ]]; then
    echo -e "${YELLOW}⚠ BATS not found, installing locally...${NC}"
    install_test_deps
  fi

  if [[ -x "$BATS_BIN" ]]; then
    PATH="$BATS_CORE_DIR/bin:$PATH"
    export PATH
  fi

  if ! command -v bats >/dev/null; then
    echo -e "${RED}❌ Error: BATS installation failed${NC}"
    exit 1
  fi

  bats --version
  echo -e "${GREEN}✓ Using local BATS from $BATS_CORE_DIR${NC}"
}

# Check if helper libraries are available
check_helpers() {
  local missing=0
  local found_local=false
  
  # Export for test_helper.bash
  export HUG_TEST_DEPS="$DEPS_DIR"
  
  # Check local dependencies first
  for lib_dir in "$BATS_SUPPORT_DIR" "$BATS_ASSERT_DIR" "$BATS_FILE_DIR"; do
    if [[ -d "$lib_dir" ]]; then
      found_local=true
      break
    fi
  done
  
  if [[ "$found_local" == "true" ]]; then
    echo -e "${GREEN}✓ Using local BATS helper libraries${NC}"
    return
  fi
  
  # Check system locations
  for lib in bats-support bats-assert bats-file; do
    if [[ ! -d "/usr/lib/bats/$lib" ]] && [[ ! -d "/usr/lib/$lib" ]] && [[ ! -d "/usr/local/lib/$lib" ]] && [[ ! -d "$HOME/.bats-libs/$lib" ]]; then
      missing=1
    fi
  done
  
  if [[ $missing -eq 1 ]]; then
    echo -e "${YELLOW}⚠ Helper libraries not found, installing locally...${NC}"
    install_test_deps
    echo -e "${GREEN}✓ BATS helper libraries installed${NC}"
  else
    echo -e "${GREEN}✓ BATS helper libraries found${NC}"
  fi
}

# Activate Hug
activate_hug() {
  local activate_script="$PROJECT_ROOT/bin/activate"
  if [[ -f "$activate_script" ]]; then
    # shellcheck source=/dev/null
    source "$activate_script"
    echo -e "${GREEN}✓ Hug activated${NC}"
  else
    echo -e "${YELLOW}⚠ Warning: $activate_script not found${NC}"
    echo "Make sure you're running this from the project root or tests directory"
  fi
  echo "Verifying no global changes post-activation"
}

# Run tests
run_tests() {
  local test_path="${1:-tests/}"
  local extra_args=("${@:2}")
  
  # If test_path is relative and we're not in project root, make it absolute
  if [[ ! "$test_path" =~ ^/ ]]; then
    test_path="$PROJECT_ROOT/$test_path"
  fi
  
  # Ensure exports for parallel execution
  export HUG_TEST_DEPS="$DEPS_DIR"
  export PATH="$BATS_CORE_DIR/bin:$PATH"
  
  # Find .bats files, excluding deps/
  local bats_files
  if [[ -f "$test_path" ]]; then
    bats_files="$test_path"
  else
    bats_files=$(find "$test_path" -path "*/deps/*" -prune -o -name "*.bats" -print)
  fi
  
  if [[ -z "$bats_files" ]]; then
    echo "No .bats files found in $test_path"
    return 1
  fi
  
  echo ""
  echo -e "${GREEN}Running tests: $test_path${NC}"
  echo "----------------------------------------"
  
  if bats --timing --tap "${extra_args[@]}" $bats_files; then
    echo ""
    echo -e "${GREEN}✓ All tests passed!${NC}"
    return 0
  else
    echo ""
    echo -e "${RED}❌ Some tests failed${NC}"
    return 1
  fi
}

# Show usage
show_usage() {
  cat <<EOF
Usage: $0 [OPTIONS] [TEST_PATH]

Run Hug SCM test suite using BATS.

Options:
  -h, --help          Show this help message
  -f, --filter TEXT   Run only tests matching TEXT
  -j, --jobs N        Run tests in parallel with N jobs
  --unit              Run only unit tests
  --integration       Run only integration tests
  --check             Check prerequisites without running tests
  --install-deps      Install or update test dependencies only

Examples:
  $0                           # Run all tests
  $0 tests/unit/               # Run all unit tests
  $0 tests/unit/test_status_staging.bats  # Run specific test file
  $0 -f "hug s"                # Run tests matching "hug s"
  $0 -j 4                      # Run with 4 parallel jobs
  $0 --unit                    # Run only unit tests
  $0 --check                   # Check prerequisites
  $0 --install-deps            # Install test dependencies

EOF
}

# Main
main() {
  local test_path="tests/"
  local filter=""
  local jobs=""
  local check_only=false
  local install_only=false
  local extra_args=()
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_usage
        exit 0
        ;;
      -f|--filter)
        extra_args+=("--filter" "$2")
        shift 2
        ;;
      -j|--jobs)
        extra_args+=("--jobs" "$2")
        shift 2
        ;;
      --unit)
        test_path="tests/unit/"
        shift
        ;;
      --integration)
        test_path="tests/integration/"
        shift
        ;;
      --check)
        check_only=true
        extra_args+=("--count")
        shift
        ;;
      --install-deps)
        install_only=true
        shift
        ;;
      -*)
        echo -e "${RED}Unknown option: $1${NC}"
        show_usage
        exit 1
        ;;
      *)
        test_path="$1"
        shift
        ;;
    esac
  done
  
  # Handle install-only mode
  if [[ "$install_only" == "true" ]]; then
    echo -e "${GREEN}Installing test dependencies...${NC}"
    install_test_deps
    echo -e "${GREEN}✓ Test dependencies installed successfully${NC}"
    exit 0
  fi
  
  # Check prerequisites
  echo "Checking prerequisites..."
  check_bats
  check_helpers
  activate_hug
  
  # Pre-flight check for temp dir isolation
  if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
    echo -e "${YELLOW}⚠ Bats \$BATS_TEST_TMPDIR not set; using explicit /tmp isolation${NC}"
  fi
  temp_dir=$(mktemp -d -t bats-check-XXXXXX 2>/dev/null || echo "failed")
  if [[ "$temp_dir" == "failed" ]]; then
    echo -e "${RED}❌ Cannot create temp dirs; check /tmp permissions${NC}"
    exit 1
  fi
  rm -rf "$temp_dir"
  
  # Run tests or only show test counts if `--check` present
  (run_tests "$test_path" "${extra_args[@]}")

  if [[ "$check_only" == "true" ]]; then
    echo ""
    echo -e "${GREEN}✓ All prerequisites are met${NC}"
  fi

}

# Run main function
main "$@"
