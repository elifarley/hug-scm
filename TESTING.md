# Testing Guide for Hug SCM

This document provides comprehensive guidance on testing strategies, practices, and tools for Hug SCM.

## Table of Contents

- [Overview](#overview)
- [Testing Philosophy](#testing-philosophy)
- [Quick Start](#quick-start)
- [Test Structure](#test-structure)
- [Writing Tests](#writing-tests)
- [Running Tests](#running-tests)
- [CI/CD Integration](#cicd-integration)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

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

## Quick Start

### Prerequisites

Install BATS and helper libraries:

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
# Check prerequisites
make test-check

# Run all tests
make test

# Run only unit tests
make test-unit

# Run only integration tests
make test-integration

# Run with verbose output
make test-verbose
```

Or use the test script directly:
```bash
# Check prerequisites
./tests/run-tests.sh --check

# Run all tests
./tests/run-tests.sh

# Run specific test suite
./tests/run-tests.sh tests/unit/test_status_staging.bats

# Run with verbose output
./tests/run-tests.sh -v

# Run tests matching a pattern
./tests/run-tests.sh -f "hug s"

# Run tests in parallel
./tests/run-tests.sh -j 4
```

## Test Structure

```
tests/
├── test_helper.bash              # Common utilities and setup
├── unit/                         # Unit tests
│   ├── test_status_staging.bats  # Status and staging (s*, a*, us*)
│   ├── test_working_dir.bats     # Working directory (w*)
│   └── test_head.bats            # HEAD operations (h*)
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

### Test Naming

- **File Names**: `test_<feature>.bats`
- **Test Names**: `"hug <command>: <specific behavior>"`
- Be descriptive and specific
- One behavior per test

**Good Examples:**
- `"hug s: shows status summary"`
- `"hug w discard -f: discards changes without confirmation"`
- `"hug h back N: moves HEAD back N commits"`

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
```

**Single test:**
```bash
./tests/run-tests.sh -f "hug s shows status"
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
source git-config/activate

# Run tests
bats tests/
bats --tap tests/unit/
bats --verbose-run tests/unit/test_status_staging.bats
```

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
source git-config/activate
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

Target: **>80% command coverage**

Current coverage:
- ✅ Status and staging (s*, a*, us*)
- ✅ Working directory (w*)
- ✅ HEAD operations (h*)
- ✅ Common workflows
- ⏳ Branch operations (b*)
- ⏳ Commit commands (c*)
- ⏳ Logging (l*)
- ⏳ Tagging (t*)
- ⏳ File inspection (f*)
- ⏳ Rebase/merge (r*, m*)

### Test Requirements for PRs

All PRs must:
- Include tests for new features
- Update tests for changed behavior
- Pass all existing tests
- Maintain or improve coverage

## Resources

- [BATS Documentation](https://bats-core.readthedocs.io/)
- [bats-assert](https://github.com/bats-core/bats-assert)
- [bats-support](https://github.com/bats-core/bats-support)
- [bats-file](https://github.com/bats-core/bats-file)
- [ADR-001: Testing Strategy](docs/architecture/ADR-001-automated-testing-strategy.md)
- [Test Suite README](tests/README.md)

## Questions?

For questions or issues with testing:
1. Check this guide and the test README
2. Look at existing tests for examples
3. Ask in GitHub Issues or Discussions
4. Consult BATS documentation

---

**Remember**: Good tests are an investment. They save time, prevent bugs, and enable confident development. Happy testing! 🧪
