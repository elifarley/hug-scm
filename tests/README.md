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

### Run All Tests
```bash
# From the project root
bats tests/

# Or from the tests directory
cd tests
bats .
```

### Run Specific Test File
```bash
bats tests/unit/test_status_staging.bats
bats tests/unit/test_working_dir.bats
bats tests/unit/test_head.bats
bats tests/lib/test_hug-fs.bats
bats tests/integration/test_workflows.bats
```

### Run Specific Test
```bash
bats tests/unit/test_status_staging.bats --filter "hug s shows status"
```

### Run Tests in Parallel
```bash
bats --jobs 4 tests/
```

### Verbose Output
```bash
bats --tap tests/              # TAP format output
bats --verbose-run tests/      # Show test commands as they run
bats --print-output-on-failure tests/  # Show output only on failures
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

load '../../test_helper'

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
- `create_test_repo()` - Creates a fresh git repository
- `create_test_repo_with_history()` - Creates a repo with sample commits
- `create_test_repo_with_changes()` - Creates a repo with uncommitted changes
- `cleanup_test_repo()` - Cleans up test repository

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
