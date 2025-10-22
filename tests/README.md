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
├── integration/              # Integration tests for workflows
│   └── test_workflows.bats         # End-to-end workflow tests
└── fixtures/                 # Test data and sample repositories
```

## Prerequisites

### Installing BATS

BATS and its helper libraries must be installed before running tests.

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

### Test Naming Conventions

- Test files: `test_<feature>.bats`
- Test descriptions: `"hug <command>: <behavior>"`
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

## Continuous Integration

Tests run automatically in GitHub Actions on every push and pull request.

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
- ✅ Common workflows (integration tests)

To add:
- [ ] Branch operations (b*)
- [ ] Commit commands (c*)
- [ ] Logging commands (l*)
- [ ] Tagging commands (t*)
- [ ] File inspection (f*)
- [ ] Rebase and merge (r*, m*)

## Contributing

When adding new commands or features:
1. Write tests first (TDD) or alongside the feature
2. Ensure tests pass: `bats tests/`
3. Add integration tests for complex workflows
4. Update this README if adding new test utilities

## Resources

- [BATS Documentation](https://bats-core.readthedocs.io/)
- [bats-assert GitHub](https://github.com/bats-core/bats-assert)
- [bats-support GitHub](https://github.com/bats-core/bats-support)
- [bats-file GitHub](https://github.com/bats-core/bats-file)
- [ADR-001: Testing Strategy](../docs/architecture/ADR-001-automated-testing-strategy.md)
