# Testing Guide for Hug SCM

This document provides comprehensive guidance on testing strategies, practices, and tools for Hug SCM.

## Table of Contents

- [Overview](#overview)
- [Testing Philosophy](#testing-philosophy)
- [Quick Start](#quick-start)
- [Test Structure](#test-structure)
- [Writing Tests](#writing-tests)
- [Running Tests](#running-tests)
- [ShellCheck Integration](#shellcheck-integration)
- [CI/CD Integration](#cicd-integration)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [Library Testing](#library-testing)

## Overview

Hug SCM uses **BATS (Bash Automated Testing System)** for automated testing. BATS is a TAP-compliant testing framework designed specifically for Bash scripts, making it the perfect fit for our codebase.

### Why BATS?

- **Native Bash**: Written for Bash, perfect for testing Bash scripts
- **Simple Syntax**: Easy to read and write tests
- **Rich Ecosystem**: Helper libraries for assertions and file operations
- **CI/CD Ready**: Easy GitHub Actions integration
- **Industry Standard**: Used by Docker, Homebrew, and many other projects

For the full rationale, see [ADR-001: Automated Testing Strategy](docs/architecture/ADR-001-automated-testing-strategy.md).

## Testing Philosophy

### Goals

1. **Prevent Regressions**: Catch bugs before they reach users
2. **Enable Refactoring**: Change code confidently
3. **Document Behavior**: Tests serve as living documentation
4. **Support Development**: Fast feedback during development

### Coverage Strategy

- **Unit Tests**: Test individual commands in isolation
- **Integration Tests**: Test complete workflows and command interactions
- **Edge Cases**: Test error conditions and boundary cases
- **Safety Tests**: Verify destructive operations require confirmation

### Test Pyramid

```
    Integration Tests (20%)
         /\
        /  \
       /    \
      /------\
     Unit Tests (80%)
```

Focus on unit tests for speed and precision, with targeted integration tests for critical workflows.

### Test Infrastructure Architecture (Phase 1-3 Complete)

Hug SCM uses a **hybrid architecture** for test repository creation, optimized for both performance and reproducibility:

**Demo Repositories** (Externally-Built, Comprehensive)
- Full-featured repos with 9+ commits, branches, remotes, tags
- Built via `docs/screencasts/bin/repo-setup-simple.sh` and `repo-setup.sh`
- Use when: Integration tests need realistic repo structure
- Performance: ~200ms setup cost per test
- Example: `test_analyze_deps.bats` (needs overlapping file changes)

**Test Fixtures** (In-Process, Lightweight)
- Purpose-built minimal repos (1-4 commits)
- Built via `tests/test_helper.bash` functions
- Use when: Unit tests need fast, focused setup
- Performance: ~20ms setup cost per test (10x faster)
- Example: `test_llf.bats`, `test_bc.bats`, `test_head.bats`

**Shared Foundation: Deterministic Timestamps**
- All repos use `tests/lib/deterministic_git.bash`
- Fixed epoch: 2000-01-01 00:00:00 UTC
- Reproducible commit hashes across all test runs
- Zero non-deterministic commit creation in entire suite

**Key Insight:** Both patterns are optimal for their use cases. Demo repos provide realism for integration tests; fixtures provide speed for unit tests. Attempting to use only one pattern would sacrifice either performance (10x slower) or realism. The hybrid approach leverages the strengths of both.

## Quick Start

### Install Test Dependencies

Run once (or whenever you need an update):

```bash
make test-deps-install
```

This installs **both BATS and Python test dependencies**:
- BATS and helper libraries for Bash testing (installed to `$HOME/.hug-deps`)
- pytest, coverage, and Python dev dependencies for Python library tests

The installation handles both dependency types automatically with graceful fallbacks if installation fails.

To install dependencies in a different location, you can set the `DEPS_DIR` environment variable. Similarly, the `vhs` dependency location can be overridden with the `VHS_DEPS_DIR` environment variable, and optional dependencies with `OPTIONAL_DEPS_DIR`.

```bash
DEPS_DIR=/path/to/your/deps VHS_DEPS_DIR=/path/to/your/vhs-deps OPTIONAL_DEPS_DIR=/path/to/your/optional-deps make test-deps-install vhs-deps-install optional-deps-install
```

The test runner (`./tests/run-tests.sh`) will automatically install or update dependencies if they're missing, so you can also just run `make test` and let it bootstrap everything.

### Install Optional Dependencies

Optional dependencies enhance Hug's functionality but are not required for basic operation. To install them:

```bash
make optional-deps-install
```

This installs tools like `gum` (interactive filter) that improve the user experience for certain commands. By default, they are installed to `$HOME/.hug-deps/bin`.

To check if optional dependencies are installed:

```bash
make optional-deps-check
```

Optional dependencies currently include:
- **gum**: Interactive filter/prompt tool used by commands like `hug brestore` for better UX when selecting from many backup branches

#### Manual Installation (Optional)

If you prefer to install BATS system-wide:

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y bats

# Install helper libraries
sudo mkdir -p /usr/lib/bats-{support,assert,file}
git clone https://github.com/bats-core/bats-support.git /tmp/bats-support
git clone https://github.com/bats-core/bats-assert.git /tmp/bats-assert
git clone https://github.com/bats-core/bats-file.git /tmp/bats-file
sudo cp -r /tmp/bats-support/src/* /usr/lib/bats-support/
sudo cp -r /tmp/bats-assert/src/* /usr/lib/bats-assert/
sudo cp -r /tmp/bats-file/src/* /usr/lib/bats-file/
```

**macOS:**
```bash
brew install bats-core
brew tap kaos/shell
brew install bats-assert bats-file bats-support
```

### Running Tests

Using Make (recommended):
```bash
# Check prerequisites (checks both BATS and Python dependencies)
make test-check

# Run all tests (BATS + Python library tests)
make test

# Run only unit tests
make test-unit

# Run only integration tests
make test-integration

# Run only library tests
make test-lib

# Run only Python library tests
make test-lib-py

# Run Python library tests with coverage report
make test-lib-py-coverage

# BATS tests show only failing tests by default
make test                    # Shows only failing BATS tests
make test-unit              # Shows only failing unit tests
make test-lib-py             # Python tests (pytest, shows all by default)

# Show all test results (including passing)
make test TEST_SHOW_ALL_RESULTS=1
make test-unit TEST_SHOW_ALL_RESULTS=1
```

#### Running Specific Tests via Makefile
The Makefile now supports optional variables for granular execution within categories. This overrides defaults without breaking broad runs. For category-specific targets, if `TEST_FILE` lacks a full path (doesn't start with `tests/`), it automatically prepends the category directory (e.g., `tests/unit/` for `test-unit`).

```bash
# Run a specific unit test file (short name auto-prepended with tests/unit/)
make test-unit TEST_FILE=test_head.bats

# Run unit tests matching a filter (searches @test names across all unit files)
make test-unit TEST_FILTER="hug h back"

# Combine: Specific file with filter (filters within that file)
make test-unit TEST_FILE=test_head.bats TEST_FILTER="edge case"

# Full paths also work
make test-unit TEST_FILE=tests/unit/test_head.bats

# BATS tests show only failing tests by default
make test-unit                           # Shows only failing unit tests
make test-unit TEST_FILE=test_head.bats  # Shows only failing tests in this file

# Show all test results (including passing)
make test-unit TEST_SHOW_ALL_RESULTS=1
make test-unit TEST_FILE=test_head.bats TEST_SHOW_ALL_RESULTS=1

# Same pattern for other categories
make test-integration TEST_FILE=test_workflows.bats  # Auto-prepends tests/integration/
make test-lib TEST_FILTER="hug-fs is_symlink"
make test-lib TEST_FILE=test_hug-fs.bats  # Auto-prepends tests/lib/
make test TEST_FILE=test_head.bats  # Auto-prepends tests/ for general tests

# Notes:
# - TEST_FILE overrides the category path; short names (filenames only) are auto-completed with category dir.
# - Full relative paths (e.g., tests/unit/test_head.bats) are used as-is.
# - TEST_FILTER uses run-tests.sh's -f (partial match on test names); combine with TEST_FILE for precision.
# - BATS tests show only failing tests by default; use TEST_SHOW_ALL_RESULTS=1 to see all test output.
# - For advanced args (e.g., -j 4, -v), invoke run-tests.sh directly.
# - Invalid paths/files will error via run-tests.sh.
```

Or use the test script directly:
```bash
# Check prerequisites
./tests/run-tests.sh --check

# Run all tests
./tests/run-tests.sh

# Run specific test suite
./tests/run-tests.sh tests/unit/test_status_staging.bats
./tests/run-tests.sh tests/lib/test_hug-fs.bats

# Run with verbose output
./tests/run-tests.sh -v

# Run tests matching a pattern
./tests/run-tests.sh -f "hug s"

# Run tests in parallel
./tests/run-tests.sh -j 4

# Show only failing tests
./tests/run-tests.sh -F
./tests/run-tests.sh --show-failing-only
```

## Test Structure

```
tests/
├── test_helper.bash              # Common utilities and setup
├── unit/                         # Unit tests
│   ├── test_status_staging.bats  # Status and staging (s*, a*, us*)
│   ├── test_working_dir.bats     # Working directory (w*)
│   └── test_head.bats            # HEAD operations (h*)
├── lib/                          # Library unit tests
│   └── test_hug-fs.bats          # Filesystem utilities (hug-fs)
├── integration/                  # Integration tests
│   └── test_workflows.bats       # End-to-end workflows
└── fixtures/                     # Test data
```

### Test Helper Functions

`test_helper.bash` provides utilities for all tests:

**Repository Setup:**
```bash
create_test_repo()                # Fresh git repo
create_test_repo_with_history()   # Repo with commits
create_test_repo_with_changes()   # Repo with uncommitted changes
cleanup_test_repo()               # Clean up after test
```

**Assertions:**
```bash
assert_success                    # Command succeeded
assert_failure                    # Command failed
assert_output "text"              # Output matches
assert_output --partial "text"    # Output contains
assert_file_exists "path"         # File exists
assert_git_clean()                # No uncommitted changes
```

**Environment:**
```bash
require_hug()                     # Skip if hug not installed
require_git_version "2.23"        # Skip if git too old
```

## Writing Tests

### Basic Test Template

For command tests (unit/integration):

```bash
#!/usr/bin/env bats
# Tests for [feature description]

load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

@test "command: does something specific" {
  # Arrange: Set up test conditions
  echo "content" > file.txt
  
  # Act: Run the command
  run hug command args
  
  # Assert: Verify results
  assert_success
  assert_output --partial "expected"
}
```

For library tests:

```bash
#!/usr/bin/env bats
# Tests for [library feature]

load '../../test_helper'

# Load the library (BATS 'load' ensures reliable sourcing)
load '../../../git-config/lib/hug-fs'  # Relative from tests/lib/

@test "library function: does something specific" {
  # Act: Call the function
  run is_symlink "arg"
  
  # Assert: Verify outcome
  assert_success
}
```

### Test Naming

- **File Names**: `test_<feature>.bats`
- **Test Names**: `"hug <command>: <specific behavior>"`
- Be descriptive and specific
- One behavior per test

**Good Examples:**
- `"hug s: shows status summary"`
- `"hug w discard -f: discards changes without confirmation"`
- `"hug h back N: moves HEAD back N commits"`
- `"hug-fs: is_symlink: detects symbolic links"`

**Bad Examples:**
- `"test status"` (too vague)
- `"it works"` (doesn't describe behavior)

### Arrange-Act-Assert Pattern

Structure tests clearly:

```bash
@test "hug a: stages modified tracked files" {
  # Arrange: Set up initial state
  echo "change" >> README.md
  
  # Act: Execute command
  run hug a
  
  # Assert: Verify outcome
  assert_success
  run git diff --cached --name-only
  assert_output --partial "README.md"
}
```

### Testing Different Scenarios

**Success Cases:**
```bash
@test "hug command: succeeds with valid input" {
  run hug command valid-arg
  assert_success
  assert_output --partial "success message"
}
```

**Error Cases:**
```bash
@test "hug command: fails with invalid input" {
  run hug command invalid-arg
  assert_failure
  assert_output --partial "error message"
}
```

**Edge Cases:**
```bash
@test "hug command: handles empty repository" {
  local empty_repo
  empty_repo=$(create_test_repo)
  cd "$empty_repo"
  
  run hug command
  # Verify appropriate behavior
}
```

**With Flags:**
```bash
@test "hug command --dry-run: previews without applying" {
  run hug command --dry-run
  assert_success
  assert_output --partial "would"
  # Verify no actual changes
}
```

### Testing Interactive Commands

**CRITICAL LESSON**: Testing interactive gum commands requires the gum mock infrastructure. The naive approach of piping empty input (`echo '' | hug command`) fails in TTY environments.

#### The Problem with Input Piping

```bash
# WRONG - Causes TTY errors or hangs in different environments
run bash -c "echo '' | hug bdel 2>&1"
# In CI: "unable to run filter: could not open a new TTY: open /dev/tty: no such device"
# In TTY: Hangs indefinitely waiting for input
```

**Why it fails**: `gum filter` tries to open `/dev/tty` directly (not stdin), which:
- In non-TTY CI: fails immediately with "no such device or address"
- In TTY environments: causes the test to hang waiting for real user input

#### The Solution: Gum Mock Infrastructure

```bash
@test "hug bdel (no args): enters interactive mode when no branches specified" {
  # Create test branches...
  git checkout -q -b test-feature-1
  echo "f1" > f1.txt
  git add f1.txt
  git commit -q -m "feat 1"
  git checkout -q main

  # RIGHT - Use setup_gum_mock for all interactive tests
  setup_gum_mock
  export HUG_TEST_GUM_INPUT_RETURN_CODE=1  # Simulate user cancellation

  run hug bdel
  assert_success  # git-bdel exits 0 when user cancels gracefully
  assert_output --partial "No branches selected."
  refute_output --partial "unbound variable"

  teardown_gum_mock
}
```

#### How Gum Mock Works

1. `setup_gum_mock()` adds `tests/bin` to the beginning of PATH
2. A symlink `tests/bin/gum` points to `tests/bin/gum-mock`
3. When hug commands call `gum`, they get the mock instead of real gum
4. The mock reads environment variables to determine behavior:
   - `HUG_TEST_GUM_INPUT_RETURN_CODE=1`: Simulate cancellation (exit code 1)
   - `HUG_TEST_GUM_SELECTION_INDEX=0`: Select first item (0-based index)
   - `HUG_TEST_GUM_CONFIRM=yes`: Confirm prompts with "yes"
5. `teardown_gum_mock()` restores the original PATH

#### Common Gum Mock Patterns

**Simulate cancellation (Ctrl+C/ESC):**
```bash
setup_gum_mock
export HUG_TEST_GUM_INPUT_RETURN_CODE=1

run hug interactive-command
assert_failure  # Command should fail when cancelled
assert_output --partial "Cancelled"

teardown_gum_mock
```

**Select specific item from menu:**
```bash
setup_gum_mock
export HUG_TEST_GUM_SELECTION_INDEX=2  # Select third item (0-indexed)

run hug interactive-command
assert_success
# Verify the third item was selected/processed

teardown_gum_mock
```

**Auto-confirm all prompts:**
```bash
setup_gum_mock
export HUG_TEST_GUM_CONFIRM="yes"

run hug dangerous-command --force
assert_success

teardown_gum_mock
```

#### When Input Piping IS Acceptable

For simple yes/no prompts (not gum filter menus), input piping works fine:

```bash
# OK for simple confirm prompts
run bash -c 'echo "y" | hug cmv 1 feature'  # Confirm commit move
run bash -c 'echo "n" | hug h back HEAD~1'  # Decline dangerous operation
```

**Decision tree:**
- `gum filter`/`gum choose` menus → **Always use gum mock**
- Simple yes/no prompts → **Input piping is OK**
- `gum input` text entry → **Use gum mock or input piping**

#### Additional Resources

- `tests/bin/README.md` - Complete gum mock documentation
- `tests/bin/gum-mock` - Mock implementation with all supported commands
- `tests/test_helper.bash` - `setup_gum_mock()` and `teardown_gum_mock()` helpers

### Testing Destructive Operations

Verify safety mechanisms:

```bash
@test "hug w discard: requires confirmation without -f" {
  echo "change" >> file.txt

  # Should timeout waiting for input
  run timeout 2 bash -c "echo '' | hug w discard file.txt 2>&1 || true"

  # Change should remain
  run git diff file.txt
  assert_output --partial "change"
}

@test "hug w discard -f: bypasses confirmation" {
  echo "change" >> file.txt
  
  run hug w discard -f file.txt
  assert_success
  
  # Change should be gone
  assert_git_clean
}
```

### Testing File Operations

```bash
@test "command: creates expected files" {
  run hug command
  assert_success
  assert_file_exists "expected.txt"
}

@test "command: removes files" {
  echo "temp" > temp.txt
  
  run hug command temp.txt
  assert_success
  assert_file_not_exists "temp.txt"
}
```

### Testing Multiple Commands (Integration)

```bash
@test "workflow: stage, commit, verify" {
  # Create change
  echo "new feature" > feature.txt
  
  # Stage
  run hug aa
  assert_success
  
  # Commit
  run hug c -m "Add feature"
  assert_success
  
  # Verify
  run git log --oneline
  assert_output --partial "Add feature"
  assert_git_clean
}
```

## Running Tests

### Local Execution

**All tests:**
```bash
make test
# or
./tests/run-tests.sh
```

**Specific suite:**
```bash
make test-unit
make test-integration
# or
./tests/run-tests.sh tests/unit/
./tests/run-tests.sh tests/integration/
```

**Specific file:**
```bash
./tests/run-tests.sh tests/unit/test_status_staging.bats
./tests/run-tests.sh tests/lib/test_hug-fs.bats
```

**Single test:**
```bash
./tests/run-tests.sh -f "hug s shows status"
./tests/run-tests.sh -f "hug-fs: is_symlink"
```

**Verbose output:**
```bash
make test-verbose
# or
./tests/run-tests.sh -v
```

**Parallel execution:**
```bash
./tests/run-tests.sh -j 4
```

### Direct BATS Commands

```bash
# Activate Hug first
source bin/activate

# Run tests
bats tests/
bats --tap tests/unit/
bats tests/unit/test_status_staging.bats
```

## ShellCheck Integration

Hug SCM uses ShellCheck for static analysis of Bash scripts, including BATS test files. The CI pipeline runs `make sanitize-check` which includes ShellCheck linting.

### BATS-Specific Warnings

ShellCheck has special rules for BATS tests that may trigger warnings for intentional patterns.

#### SC2314: Function Negation in BATS

When testing that a function returns false, use this pattern:

```bash
@test "function: returns false for invalid input" {
  # shellcheck disable=SC2314
  ! worktree_exists "/nonexistent/path"
}
```

**Why**: The `! function_name` pattern is a clear BATS idiom for testing false returns. ShellCheck's suggestion to use `run ! function` requires BATS 1.5.0+ and changes test semantics. The directive preserves the idiomatic pattern while documenting the intentional exception.

**Key Points**:
- Directive must be on the line **immediately before** the negated call
- Not on the same line, not after the command
- Document why the pattern is intentional

#### SC2315: Conditional Negation in BATS

For negated conditionals, prefer folding the `!` into the condition:

```bash
# Before (triggers SC2315):
! [[ " ${files[*]} " =~ " pattern " ]]

# After (preferred):
[[ ! " ${files[*]} " =~ " pattern " ]]
```

**Why**: Folding `!` into `[[ ! ... ]]` is standard bash syntax that:
- Eliminates the need for suppression directives
- Is more idiomatic and readable
- Works consistently across all bash versions

**Example in tests**:
```bash
@test "list_tracked_files: excludes parent files with --cwd" {
  cd src/components
  mapfile -t files < <(list_tracked_files --cwd)

  # Should NOT include files from parent directories
  [[ ! " ${files[*]} " =~ " root1.txt " ]]
  [[ ! " ${files[*]} " =~ " helper.js " ]]
}
```

### Project-Wide Suppressions

See `.shellcheckrc` for documented suppressions covering:
- BATS test framework patterns (SC2030, SC2031)
- Nameref false positives (SC2178, SC2154)
- Git-specific syntax (SC1083)
- Intentional word splitting (SC2046, SC2206, SC2207)
- And many more project-specific patterns

Each suppression in `.shellcheckrc` includes a comment explaining **why** it's disabled.

### Inline vs. Project-Wide Suppressions

**Use inline directives (`# shellcheck disable=SCXXXX`) when**:
- The warning is for a specific, intentional pattern in one test
- The pattern is a BATS idiom that shouldn't be changed
- The pattern is rare (only a few instances)

**Add to `.shellcheckrc` when**:
- The pattern is project-wide and appears in many files
- The pattern is a fundamental design decision
- The suppression applies to all Bash files, not just tests

### Running ShellCheck

```bash
# Check all Bash scripts
make lint

# Check specific files
shellcheck tests/lib/test_hug-git-worktree.bats

# Full sanitize check (includes formatting + linting + type checking)
make sanitize-check
```

### CI/CD Pipeline

The `sanitize-check` job runs on every commit:
1. Bash formatting (shfmt)
2. Python formatting (black/ruff)
3. Bash linting (ShellCheck)
4. Python linting (ruff)
5. Python type checking (mypy)

Any ShellCheck warnings will cause CI to fail.

## CI/CD Integration

Tests run automatically in GitHub Actions on:
- Push to `main` or `develop`
- Pull requests to `main` or `develop`

### Workflow Configuration

See `.github/workflows/test.yml` for the complete CI setup.

Key steps:
1. Install BATS and helpers
2. Install Hug SCM
3. Run unit tests
4. Run integration tests
5. Show verbose output on failure

### Adding CI Checks

To add test coverage reporting or other checks:

1. Add steps to `.github/workflows/test.yml`
2. Use existing BATS plugins or tools
3. Update this document with new checks

## Best Practices

### Do's ✅

- **Write tests first** (TDD) or alongside features
- **One behavior per test** - tests should be focused
- **Use descriptive names** - tests are documentation
- **Test edge cases** - empty inputs, invalid args, etc.
- **Clean up in teardown** - keep tests isolated
- **Use test helpers** - leverage provided utilities
- **Test error messages** - verify user feedback
- **Keep tests fast** - avoid unnecessary delays

### Don'ts ❌

- **Don't depend on test order** - tests should be independent
- **Don't use real repositories** - always use test repos
- **Don't skip cleanup** - prevent pollution between tests
- **Don't test implementation** - test behavior
- **Don't make tests fragile** - avoid brittle assertions
- **Don't ignore failing tests** - fix or skip with reason

### Performance Tips

- Use `setup_file()` for expensive one-time setup
- Create minimal test repositories
- Run tests in parallel: `./tests/run-tests.sh -j 4`
- Focus tests on specific behaviors (faster than broad tests)

### Code Review Checklist

When reviewing PRs with tests:

- [ ] Tests cover new functionality
- [ ] Tests cover edge cases
- [ ] Test names are clear and descriptive
- [ ] Tests are independent and isolated
- [ ] Setup and teardown are correct
- [ ] Tests pass locally and in CI
- [ ] No tests are skipped without good reason

## Troubleshooting

### Tests Won't Run

**Problem**: `bats: command not found`
```bash
# Solution: Install BATS
sudo apt-get install bats  # Ubuntu/Debian
brew install bats-core      # macOS
```

**Problem**: Helper libraries not found
```bash
# Solution: Install helpers (see Prerequisites section)
# Or update test_helper.bash with correct paths
```

**Problem**: `hug: command not found`
```bash
# Solution: Activate Hug
source bin/activate
```

### Tests Fail Unexpectedly

**Problem**: Test passes locally but fails in CI
- Check Git version differences
- Verify BATS helper library versions
- Check for environment-specific assumptions

**Problem**: Intermittent failures
- Look for race conditions
- Check for incomplete cleanup
- Verify test isolation

**Problem**: "Cannot create temp directory"
- Check disk space
- Verify permissions on `/tmp`

### Debugging Tests

**Enable verbose output:**
```bash
./tests/run-tests.sh -v tests/unit/test_status_staging.bats
```

**Add debugging to tests:**
```bash
@test "my test" {
  echo "Debug info: $variable" >&3
  run hug command
  echo "Output: $output" >&3
  echo "Status: $status" >&3
  assert_success
}
```

**Use Bash tracing:**
```bash
@test "my test" {
  set -x  # Enable tracing
  run hug command
  assert_success
}
```

**Inspect test repository:**
```bash
teardown() {
  echo "Test repo: $TEST_REPO" >&3
  # Comment out cleanup to inspect after test
  # cleanup_test_repo
}
```

**Run single test:**
```bash
./tests/run-tests.sh -f "exact test name"
```

**Library loading fails (e.g., function not found):**
- Use `load` instead of `source`—it's BATS-optimized. Ensure relative path is correct (e.g., `../../../` from tests/lib/).
- Debug: Add `@test "debug" { echo "Loaded from: $(pwd)"; }` after load.
- Verify: Run `make test-lib` and check for status 127 (partial BATS lib load).

### Common Issues

**Tests hang waiting for input:**
- Destructive commands need `-f` flag in tests
- Use `timeout` wrapper for confirmation tests

**Git operations fail:**
- Ensure `git config user.{name,email}` set in test repo
- Use `create_test_repo()` which sets these

**File not found errors:**
- Verify `cd "$TEST_REPO"` in setup
- Check file paths are relative to test repo

## Contributing

### Adding New Tests

1. Determine test type (unit vs integration)
2. Add to appropriate directory
3. Follow naming conventions
4. Use test helpers
5. Run tests locally
6. Verify tests pass in CI
7. Update coverage tracking

### Coverage Goals

Target: **>80% overall coverage** (commands + libraries)

Current coverage:
- ✅ Status and staging (s*, a*, us*)
- ✅ Working directory (w*)
- ✅ HEAD operations (h*)
- ✅ Library: filesystem (hug-fs)
- ✅ Common workflows
- ⏳ Branch operations (b*)
- ⏳ Commit commands (c*)
- ⏳ Logging (l*)
- ⏳ Tagging (t*)
- ⏳ File inspection (f*)
- ⏳ Rebase/merge (r*, m*)
- ⏳ Additional libraries (hug-confirm, etc.)

### Test Requirements for PRs

All PRs must:
- Include tests for new features
- Update tests for changed behavior
- Pass all existing tests
- Maintain or improve coverage

## Library Testing

### Bash Library Tests

Library tests in `tests/lib/` focus on reusable code from `git-config/lib/` (e.g., `hug-fs`, `hug-confirm`). These are pure unit tests without Git dependencies:

### Python Library Tests

Python library tests in `git-config/lib/python/tests/` use pytest to test the Python analysis modules (activity, churn, co_changes, ownership, etc.):

```bash
# Run Python library tests
make test-lib-py

# Run with coverage report
make test-lib-py-coverage

# Filter tests by name
make test-lib-py TEST_FILTER="test_analyze"
```

**Automatic Dependency Installation**: Python tests automatically install pytest and dev dependencies if missing, but it's recommended to run `make test-deps-install` beforehand for consistency.

**Key Features**:
- Uses standard pytest with fixtures and mocks
- Tests analyze activity, ownership, dependencies, and JSON transformations
- Integrated with the main test suite via `make test`

### Guidelines
- **Sourcing**: Use `load` for libraries: `load '../../../git-config/lib/hug-fs'` (relative path from .bats file). This is preferred over `source` in BATS for path handling and consistency with helpers.
- **Isolation**: No repo setup; use `mktemp` for files/dirs
- **Assertions**: Focus on function return codes and output (e.g., `assert_success`, `assert_output`)
- **Naming**: `"hug-<lib>: <function>: <behavior>"` (e.g., `"hug-fs: is_symlink: handles broken links"`)
- **Edge Cases**: Test valid/invalid inputs, empty args, non-existent paths
- **No Teardown**: Individual tests clean up temps; no global `setup()`/`teardown()`

### Example Workflow
1. Add new lib function to `git-config/lib/`
2. Create `tests/lib/test_<lib>.bats`
3. Test in isolation: `make test-lib`
4. Integrate with commands if applicable (via unit/integration tests)

## Resources

- [BATS Documentation](https://bats-core.readthedocs.io/)
- [bats-assert](https://github.com/bats-core/bats-assert)
- [bats-support](https://github.com/bats-core/bats-support)
- [bats-file](https://github.com/bats-core/bats-file)
- [ADR-001: Testing Strategy](docs/architecture/ADR-001-automated-testing-strategy.md)
- [Test Suite README](tests/README.md)

## Config Isolation Guidelines

To ensure tests do not affect global Git configurations:
- Always use `--local` with `git config` in test helpers.
- Use subshells for environment isolation in scripts.
- Capture and restore global configs in setup/teardown if needed.
- Verify locally by checking `git config --global user.name` before/after tests.
- Run tests outside Git repositories or back up global configs manually.

## Questions?

For questions or issues with testing:
1. Check this guide and the test README
2. Look at existing tests for examples
3. Ask in GitHub Issues or Discussions
4. Consult BATS documentation

---

**Remember**: Good tests are an investment. They save time, prevent bugs, and enable confident development. Happy testing! 🧪

