# Hug SCM Test Suite

This directory contains automated tests for Hug SCM using the BATS (Bash Automated Testing System) framework.

## Directory Structure

```
tests/
├── test_helper.bash          # Common test utilities and setup functions
├── unit/                     # Unit tests for individual commands
│   ├── test_status_staging.bats    # Tests for s*, a*, us* commands
│   ├── test_working_dir.bats       # Tests for w* commands
│   └── test_head.bats              # Tests for h* commands
├── lib/                      # Unit tests for library code (git-config/lib/)
│   └── test_hug-fs.bats      # Tests for filesystem utilities
├── integration/              # Integration tests for workflows
│   └── test_workflows.bats         # End-to-end workflow tests
└── fixtures/                 # Test data and sample repositories
```

## Prerequisites

### Installing Test Dependencies

The project uses a self-contained test dependency system. Run once (or whenever you need an update):

```bash
make test-deps-install
```

By default, this installs BATS and its helper libraries into `$HOME/.hug-deps`.

To install dependencies in a different location, you can set the `DEPS_DIR` environment variable. Similarly, the `vhs` dependency location can be overridden with the `VHS_DEPS_DIR` environment variable.

```bash
DEPS_DIR=/path/to/your/deps VHS_DEPS_DIR=/path/to/your/vhs-deps make test-deps-install vhs-deps-install
```

The test runner (`./tests/run-tests.sh`) will automatically install or update dependencies if they're missing, so you can also just run `make test` and let it bootstrap everything.

#### Manual Installation (Optional)

If you prefer to install BATS system-wide:

#### On Ubuntu/Debian:
```bash
# Install BATS core
sudo apt-get update
sudo apt-get install -y bats

# Install helper libraries
sudo apt-get install -y bats-assert bats-support bats-file

# Alternative: manual installation
sudo mkdir -p /usr/lib/bats-support /usr/lib/bats-assert /usr/lib/bats-file
git clone https://github.com/bats-core/bats-support.git /tmp/bats-support
git clone https://github.com/bats-core/bats-assert.git /tmp/bats-assert
git clone https://github.com/bats-core/bats-file.git /tmp/bats-file
sudo cp -r /tmp/bats-support/src/* /usr/lib/bats-support/
sudo cp -r /tmp/bats-assert/src/* /usr/lib/bats-assert/
sudo cp -r /tmp/bats-file/src/* /usr/lib/bats-file/
```

#### On macOS:
```bash
brew install bats-core
brew tap kaos/shell
brew install bats-assert bats-file bats-support
```

#### Manual Installation (All Platforms):
```bash
# Create BATS library directory
mkdir -p ~/.bats-libs

# Clone helper libraries
git clone https://github.com/bats-core/bats-core.git ~/.bats-libs/bats-core
git clone https://github.com/bats-core/bats-support.git ~/.bats-libs/bats-support
git clone https://github.com/bats-core/bats-assert.git ~/.bats-libs/bats-assert
git clone https://github.com/bats-core/bats-file.git ~/.bats-libs/bats-file

# Add BATS to PATH
export PATH="$HOME/.bats-libs/bats-core/bin:$PATH"

# Update test_helper.bash to use custom paths
# Change load paths to use $HOME/.bats-libs/...
```

## Running Tests

**IMPORTANT: Always use `make` targets from the project root, NOT direct `bats` or `./tests/run-tests.sh` invocation.**

The Makefile provides the recommended interface for running all tests:

### Test Hierarchy

```
make test (ALL TESTS)
├── make test-bash (ALL BATS TESTS)
│   ├── make test-unit (tests/unit/*.bats)
│   ├── make test-integration (tests/integration/*.bats)
│   └── make test-lib (tests/lib/*.bats)
└── make test-lib-py (git-config/lib/python/tests/)
```

### Run All Tests
```bash
make test                                   # ALL tests (BATS + pytest)
make test-bash                              # All BATS tests (unit + integration + lib)
make test-lib-py                            # Python library tests only (pytest)
make test-lib-py-coverage                   # Python tests with coverage report
```

### Run BATS Test Categories
```bash
make test-unit                              # BATS unit tests (tests/unit/)
make test-integration                       # BATS integration tests (tests/integration/)
make test-lib                               # BATS library tests (tests/lib/)
```

### Run Specific BATS Test File
```bash
# Supports basename or full path
make test-unit TEST_FILE=test_status_staging.bats
make test-unit TEST_FILE=test_working_dir.bats
make test-unit TEST_FILE=test_head.bats
make test-lib TEST_FILE=test_hug-fs.bats
make test-integration TEST_FILE=test_workflows.bats
make test-bash TEST_FILE=test_head.bats     # Also works with test-bash
```

### Filter Tests by Name Pattern
```bash
# BATS tests
make test-unit TEST_FILTER="hug s shows status"
make test-lib TEST_FILTER="is_symlink"
make test-bash TEST_FILTER="hug w"

# Python tests (pytest -k)
make test-lib-py TEST_FILTER="test_analyze"
```

### BATS Tests Output

**Default behavior**: BATS tests show only failing tests by default
```bash
make test-unit                           # Shows only failing unit tests
make test-bash                           # Shows only failing BATS tests
make test-unit TEST_FILE=test_head.bats  # Shows only failing tests in this file
```

**Show all test results** (including passing)
```bash
make test-unit TEST_SHOW_ALL_RESULTS=1
make test-bash TEST_SHOW_ALL_RESULTS=1
make test-unit TEST_FILE=test_head.bats TEST_SHOW_ALL_RESULTS=1
```

### Combine BATS Options
```bash
make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="hug s"
make test-bash TEST_FILTER="working directory"

# Show all results with filters
make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="hug s" TEST_SHOW_ALL_RESULTS=1
make test-bash TEST_FILTER="working directory" TEST_SHOW_ALL_RESULTS=1
```

### Check Prerequisites
```bash
make test-check                             # Verify BATS setup without running tests
```

### ShellCheck Linting

Before committing, ensure tests pass ShellCheck:

```bash
make sanitize-check  # Includes ShellCheck + formatting + type checking
```

See [TESTING.md](../TESTING.md#shellcheck-integration) for BATS-specific ShellCheck patterns (SC2314, SC2315).

### Advanced: Direct Invocation
Only use direct commands for features not exposed by the Makefile:

```bash
# From project root (after running `make test-check` once)
./tests/run-tests.sh -j 4                   # Parallel BATS execution
./tests/run-tests.sh --install-deps         # Install BATS dependencies

# Direct bats (if you have system-wide BATS)
bats --tap tests/                           # TAP format output
bats --verbose-run tests/                   # Show commands as they run
```

## Writing Tests

### Test File Template

For command tests (unit/integration):

```bash
#!/usr/bin/env bats
# Tests for [feature description]

# Load test helpers
load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_changes)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

@test "descriptive test name" {
  # Arrange: Set up test conditions
  echo "test content" > test.txt
  
  # Act: Run the command
  run hug command args
  
  # Assert: Verify results
  assert_success
  assert_output --partial "expected output"
  assert_file_exists "test.txt"
}
```

For library tests (lib/):

```bash
#!/usr/bin/env bats
# Tests for [library description]

load '../test_helper'

# Load the library (use 'load' for BATS compatibility and path reliability)
load '../../../git-config/lib/hug-fs'  # Adjust path for your lib

@test "descriptive test name" {
  # Act: Call library function
  run is_symlink "path/to/symlink"
  
  # Assert: Verify results
  assert_success
}
```

### Available Test Helpers

From `test_helper.bash`:

**Repository Creation:**

*Phase 2: All fixtures now use deterministic commits for reproducibility*

**Demo Repositories (Externally-Built, Comprehensive)**
- `create_demo_repo_simple()` - Full-featured demo repo with 9 commits, 2 branches, remote
  - 3 initial commits (README, app.js, .gitignore)
  - 4 commits with overlapping files (for dependency testing: file1.txt, file2.txt, file3.txt, file4.txt)
  - 2 commits on feature/search branch
  - All commits have fixed timestamps (year 2000) for reproducible commit hashes
  - Includes bare remote repository
  - Perfect for testing commands that analyze commit history, dependencies, or branches
  - **Use when:** You need a realistic repo structure with remote and branches
- `create_demo_repo_full()` - Comprehensive demo repo with 70+ commits, 15+ branches, 4 contributors
  - Use when you need complex scenarios (tags, upstream tracking, WIP states, etc.)
  - Much slower than simple demo repo (use sparingly)

**Test Fixtures (Built In-Process, Lightweight)**
- `create_test_repo()` - Minimal git repository with 1 deterministic commit
  - Uses `git_commit_deterministic()` for reproducible hashes
  - Perfect for tests that only need a clean git repo as a starting point
- `create_test_repo_with_history()` - Repo with 3 deterministic commits
  - Commits: "Initial commit", "Add feature 1", "Add feature 2"
  - All use fixed timestamps starting from year 2000
  - **Use when:** Testing HEAD manipulation, history traversal
- `create_test_repo_with_changes()` - Repo with 1 commit + uncommitted changes
  - Staged file (staged.txt), unstaged changes (README.md), untracked file (untracked.txt)
  - **Use when:** Testing staging/unstaging commands (hug a, hug us, hug sl)
- `create_test_repo_with_head_mixed_state()` - Complex fixture for HEAD operation testing
  - 4 commits with overlapping edits to tracked.txt
  - Staged changes, unstaged changes, untracked file, ignored file
  - **Use when:** Testing hug h* commands with complex working tree states
- `create_test_repo_with_head_conflict_state()` - Fixture for conflict testing
  - Local changes conflict with HEAD commits
  - **Use when:** Testing git reset --keep behavior (hug h rollback)
- `create_test_repo_with_dated_commits()` - Commits at specific dates
  - 5 commits at specific 2024 dates (Day 1, Day 5, Day 10, Day 15, Day 20)
  - **Use when:** Testing temporal filtering (--since, --until)

**Deterministic Timestamp System:**
All fixtures now use `git_commit_deterministic()` from `tests/lib/deterministic_git.bash`:
- Fixed starting epoch: 2000-01-01 00:00:00 UTC
- Default increment: 1 hour between commits
- Ensures reproducible commit hashes across test runs
- Call `reset_fake_clock()` at start of fixture for consistency

*Cleanup:*
- `cleanup_test_repo()` - Cleans up test repository (works with all repo types)

**Assertions (from bats-assert):**
- `assert_success` - Command exit code is 0
- `assert_failure` - Command exit code is non-zero
- `assert_output "text"` - Output matches exactly
- `assert_output --partial "text"` - Output contains text
- `assert_output --regexp "pattern"` - Output matches regex
- `refute_output "text"` - Output does not contain text

**File Assertions (from bats-file):**
- `assert_file_exists "path"` - File exists
- `assert_file_not_exists "path"` - File does not exist
- `assert_dir_exists "path"` - Directory exists

**Custom Helpers:**
- `assert_git_clean()` - Git status is clean (no changes)
- `require_hug()` - Skip test if hug not installed
- `require_git_version "X.Y"` - Skip test if git too old

**Library Testing Notes:**
- Load library files with `load "$RELATIVE_PATH"` (e.g., `load '../../../git-config/lib/hug-fs'` from tests/lib/). Use `load` (not `source`) for BATS best practices—it handles paths relative to the .bats file and integrates with test isolation.
- Place after loading test_helper, once per file (not inside @test blocks).
- If path issues arise, verify with `echo "$(pwd)"` in a test; PROJECT_ROOT is for absolute paths if needed.
- Use temporary directories for file/symlink tests: `mktemp -d`
- Clean up temps in each test (no global setup/teardown needed for pure lib tests)

### Test Naming Conventions

- Test files: `test_<feature>.bats`
- Test descriptions: `"hug <command>: <behavior>"` (commands) or `"hug-fs: <function>: <behavior>"` (libraries)
- Be specific and descriptive
- Each test should verify one behavior

### Best Practices

1. **Isolation**: Each test should be independent
2. **Cleanup**: Use `setup()` and `teardown()` appropriately
3. **Clear Intent**: Test names should describe what they verify
4. **Fast Tests**: Keep tests fast; avoid unnecessary operations
5. **Comprehensive**: Test happy path, edge cases, and error conditions
6. **Mock When Needed**: Use test repositories, not real repos
7. **Deterministic**: Tests should always produce same results
8. **Prefer Demo Repos**: Use `create_demo_repo_simple()` instead of `create_test_repo*()` for tests that rely on commit history or analyze dependencies
   - Demo repos have fixed timestamps → reproducible commit hashes
   - Demo repos have realistic commit patterns → more thorough testing
   - Demo repos are battle-tested → fewer surprises
9. **ALWAYS Use Gum Mock for Interactive Tests**: Never pipe empty input to gum filter commands
   - **WRONG**: `run bash -c "echo '' | hug bdel 2>&1"`
   - **RIGHT**: Use `setup_gum_mock` + `export HUG_TEST_GUM_INPUT_RETURN_CODE=1` + `teardown_gum_mock`

### Testing Interactive Commands (Gum Integration)

**CRITICAL**: Interactive commands that use `gum filter` or `gum choose` must use the gum mock infrastructure.

#### Why Input Piping Fails

```bash
# WRONG - This fails in TTY environments
run bash -c "echo '' | hug bdel 2>&1"
# Error: "unable to run filter: could not open a new TTY: open /dev/tty: no such device"
```

Gum filter opens `/dev/tty` directly (not stdin), causing:
- **Non-TTY (CI)**: "no such device or address" error
- **TTY environments**: Test hangs waiting for input

#### Correct Pattern: Gum Mock

```bash
@test "hug bdel: interactive mode cancellation" {
  # Create test branches...
  git checkout -q -b feature-1
  git commit --allow-empty -m "Feature 1"
  git checkout -q main

  # Use gum mock for all interactive tests
  setup_gum_mock
  export HUG_TEST_GUM_INPUT_RETURN_CODE=1  # Simulate Ctrl+C/ESC

  run hug bdel
  assert_success  # Graceful cancellation
  assert_output --partial "No branches selected."

  teardown_gum_mock
}
```

#### Environment Variables

| Variable | Purpose | Example |
|----------|---------|---------|
| `HUG_TEST_GUM_INPUT_RETURN_CODE` | Simulate cancellation (1) or success (0) | `export HUG_TEST_GUM_INPUT_RETURN_CODE=1` |
| `HUG_TEST_GUM_SELECTION_INDEX` | Select Nth item from gum filter (0-indexed) | `export HUG_TEST_GUM_SELECTION_INDEX=2` |
| `HUG_TEST_GUM_CONFIRM` | Auto-answer confirm prompts | `export HUG_TEST_GUM_CONFIRM=yes` |

#### When to Use Each Approach

| Scenario | Approach |
|----------|----------|
| `gum filter` / `gum choose` menus | **ALWAYS use setup_gum_mock** |
| Simple yes/no confirmations | Input piping OK: `echo "y" \| hug command` |
| `gum input` text prompts | Use gum mock OR input piping |

See `tests/bin/README.md` for complete gum mock documentation.

## Advanced Usage

You can override the dependencies directory by setting the `DEPS_DIR` environment variable before running tests:

```bash
DEPS_DIR=/custom/path ./tests/run-tests.sh
```

This is useful for custom installations or CI environments with restricted paths.

## Continuous Integration

Tests run automatically in GitHub Actions on every push and pull request. The workflow caches test dependencies to speed up runs.

See `.github/workflows/test.yml` for the CI configuration.

## Debugging Failed Tests

### Run Test with Verbose Output
```bash
bats --verbose-run --print-output-on-failure tests/unit/test_status_staging.bats
```

### Debug a Specific Test
```bash
# Add debugging to your test
@test "my test" {
  echo "Debug: variable=$variable" >&3  # stderr visible in verbose mode
  run hug command
  echo "Output: $output" >&3
  echo "Status: $status" >&3
  assert_success
}
```

### Interactive Debugging
```bash
# Run test in debug mode
bats --verbose-run tests/unit/test_status_staging.bats

# Or add `set -x` to the test
@test "my test" {
  set -x  # Enable bash tracing
  run hug command
  assert_success
}
```

### Check Test Repository State
```bash
# In teardown, don't cleanup for debugging
teardown() {
  echo "Test repo at: $TEST_REPO" >&3
  # Comment out: cleanup_test_repo
}
```

## Coverage

Currently, we have tests for:
- ✅ Status and staging commands (s*, a*, us*)
- ✅ Working directory commands (w*)
- ✅ HEAD operations (h*)
- ✅ Library: filesystem utilities (hug-fs)
- ✅ Common workflows (integration tests)

To add:
- [ ] Branch operations (b*)
- [ ] Commit commands (c*)
- [ ] Logging commands (l*)
- [ ] Tagging commands (t*)
- [ ] File inspection (f*)
- [ ] Rebase and merge (r*, m*)
- [ ] Additional libraries (hug-confirm, hug-output, etc.)

## Contributing

When adding new commands or features:
1. Write tests first (TDD) or alongside the feature
2. For library code in git-config/lib/, add tests to tests/lib/
3. Ensure tests pass: `bats tests/`
4. Add integration tests for complex workflows
5. Update this README if adding new test utilities

## Resources

- [BATS Documentation](https://bats-core.readthedocs.io/)
- [bats-assert GitHub](https://github.com/bats-core/bats-assert)
- [bats-support GitHub](https://github.com/bats-core/bats-support)
- [bats-file GitHub](https://github.com/bats-core/bats-file)
- [ADR-001: Testing Strategy](../docs/architecture/ADR-001-automated-testing-strategy.md)
