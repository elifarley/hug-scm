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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if BATS is installed
check_bats() {
  if ! command -v bats &> /dev/null; then
    echo -e "${RED}❌ Error: BATS is not installed${NC}"
    echo ""
    echo "Please install BATS and its helper libraries:"
    echo ""
    echo "On Ubuntu/Debian:"
    echo "  sudo apt-get install -y bats"
    echo ""
    echo "On macOS:"
    echo "  brew install bats-core"
    echo ""
    echo "See tests/README.md for detailed installation instructions."
    exit 1
  fi
  echo -e "${GREEN}✓ BATS is installed${NC}"
}

# Check if helper libraries are available
check_helpers() {
  local missing=0
  
  for lib in bats-support bats-assert bats-file; do
    if [[ ! -d "/usr/lib/$lib" ]] && [[ ! -d "/usr/local/lib/$lib" ]] && [[ ! -d "$HOME/.bats-libs/$lib" ]]; then
      echo -e "${YELLOW}⚠ Warning: $lib not found in standard locations${NC}"
      missing=1
    fi
  done
  
  if [[ $missing -eq 1 ]]; then
    echo ""
    echo "Helper libraries may be missing. Tests might fail."
    echo "See tests/README.md for installation instructions."
    echo ""
  else
    echo -e "${GREEN}✓ BATS helper libraries found${NC}"
  fi
}

# Activate Hug
activate_hug() {
  local activate_script="$PROJECT_ROOT/git-config/activate"
  if [[ -f "$activate_script" ]]; then
    # shellcheck source=/dev/null
    source "$activate_script"
    echo -e "${GREEN}✓ Hug activated${NC}"
  else
    echo -e "${YELLOW}⚠ Warning: $activate_script not found${NC}"
    echo "Make sure you're running this from the project root or tests directory"
  fi
}

# Run tests
run_tests() {
  local test_path="${1:-tests/}"
  local extra_args=("${@:2}")
  
  # If test_path is relative and we're not in project root, make it absolute
  if [[ ! "$test_path" =~ ^/ ]]; then
    test_path="$PROJECT_ROOT/$test_path"
  fi
  
  echo ""
  echo -e "${GREEN}Running tests: $test_path${NC}"
  echo "----------------------------------------"
  
  if bats --tap "${extra_args[@]}" "$test_path"; then
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
  -v, --verbose       Run tests with verbose output
  -f, --filter TEXT   Run only tests matching TEXT
  -j, --jobs N        Run tests in parallel with N jobs
  --unit              Run only unit tests
  --integration       Run only integration tests
  --check             Check prerequisites without running tests

Examples:
  $0                           # Run all tests
  $0 tests/unit/               # Run all unit tests
  $0 tests/unit/test_status_staging.bats  # Run specific test file
  $0 -v                        # Run with verbose output
  $0 -f "hug s"                # Run tests matching "hug s"
  $0 -j 4                      # Run with 4 parallel jobs
  $0 --unit                    # Run only unit tests
  $0 --check                   # Check prerequisites

EOF
}

# Main
main() {
  local test_path="tests/"
  local verbose=false
  local filter=""
  local jobs=""
  local check_only=false
  local extra_args=()
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        show_usage
        exit 0
        ;;
      -v|--verbose)
        extra_args+=("--verbose-run" "--print-output-on-failure")
        shift
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
  
  if [[ "$check_only" == "true" ]]; then
    echo ""
    echo -e "${GREEN}✓ All prerequisites are met${NC}"
    exit 0
  fi
  
  # Run tests
  run_tests "$test_path" "${extra_args[@]}"
}

# Run main function
main "$@"
