# CLAUDE.md - Testing Guidelines and Best Practices

This document provides guidance to Claude Code when working with tests in the Hug SCM repository.

## Testing Philosophy

Hug SCM uses the BATS (Bash Automated Testing System) framework to test its Bash-based CLI commands. Testing is structured into three main categories:

- **Library tests** (`tests/lib/`)
- **Unit tests** (`tests/unit/`): Individual command testing
- **Integration tests** (`tests/integration/`): End-to-end workflows

## Critical Issue: TTY Environment and Hanging Tests

### Root Cause Analysis

**Problem**: Tests that read from STDIN can hang indefinitely in TTY (terminal) environments.

**Why it happens**:
- **Non-TTY environment (CI, automation)**: reading from STDIN immediately fails with exit code 1
- **TTY environment (direct terminal)**: waits indefinitely (test hangs)

**Example problematic code**:
```bash
# In hug-git-branch:556 (get_numbered_selection_index function)
if ! read -r choice; then  # L Hangs in TTY environments
    info "Cancelled."
    exit 1
fi
```

### Environment Detection

To diagnose TTY vs non-TTY behavior, use these commands:

```bash
# Check if stdin is a TTY
[[ -t 0 ]] && echo "STDIN is TTY" || echo "STDIN is NOT TTY"

# Check if stdout is a TTY
[[ -t 1 ]] && echo "STDOUT is TTY" || echo "STDOUT is NOT TTY"
```

## Best Practices for Interactive Tests

### 1. Always Disable Gum for Interactive Tests

When testing interactive functionality, disable gum to avoid complex UI interactions:

```bash
@test "hug b: interactive branch selection" {
  # Disable gum to avoid hanging in interactive branch selection
  disable_gum_for_test

  # Test the interactive functionality
  run hug b
  assert_success
  assert_output --partial "interactive behavior expected"
}
```

### 2. Use EOF Simulation for Tests That Expect Cancellation

For tests that need to verify cancellation behavior in interactive modes, use EOF simulation:

```bash
@test "hug wtc: interactive mode with no branch argument" {
  # Disable gum to avoid hanging in interactive branch selection
  disable_gum_for_test

  # Test interactive mode with EOF input (provides cancellation)
  run bash -c "echo | git-wtc 2>&1"
  assert_failure  # Exits with code 1 due to cancellation

  # Should show cancellation message
  assert_output --partial "Cancelled"
}

@test "hug wtc: interactive mode with explicit -- flag" {
  # Disable gum to avoid hanging in interactive branch selection
  disable_gum_for_test

  # Test interactive mode with explicit -- flag and EOF
  run bash -c "echo | git-wtc -- 2>&1"
  assert_failure  # Exits with code 1 due to cancellation

  # Should show cancellation message
  assert_output --partial "Cancelled"
}
```

### 3. Test Environment Isolation

Always use test helper functions to create isolated environments:

```bash
@test "hug wtc: creates worktree for existing branch" {
  # Create clean test environment
  create_test_repo

  # Make some commits and create a branch
  echo "test content" > file.txt
  hug add file.txt
  hug c -m "initial commit"
  hug bc feature-branch

  # Test the functionality
  run git-wtc feature-branch
  assert_success
  assert_file_exists "hug-feature-branch"
}
```

### 4. Follow Established Patterns

Look at existing test files for patterns:

- **Reference pattern**: `test_branch_switch.bats:199` shows EOF simulation
- **Interactive tests**: `test_worktree_create.bats` demonstrates gum disabling + EOF simulation
- **Confirmation tests**: Use `confirm_action` library function with `HUG_FORCE` environment variable

### 5. Test Both Success and Error Cases

```bash
@test "hug wtc: error when branch does not exist" {
  create_test_repo

  # Test error case - should fail with specific error
  run git-wtc non-existent-branch
  assert_failure 2  # Use specific exit code if possible
  assert_output --partial "branch does not exist"
}

@test "hug wtc: creates worktree for existing branch" {
  create_test_repo_with_branches

  # Test success case
  run git-wtc existing-branch -f  # Use -f to skip confirmation
  assert_success
  assert_file_exists "hug-existing-branch"
}
```

## Troubleshooting Hanging Tests

### Step 1: Check Test Environment

Run these commands to determine if TTY issues are likely:

```bash
# Check current test environment
echo "Environment check:"
[[ -t 0 ]] && echo "STDIN: TTY - potential hanging risk" || echo "STDIN: Non-TTY - safe"
[[ -t 1 ]] && echo "STDOUT: TTY - potential output differences" || echo "STDOUT: Non-TTY - safe"
```

### Step 2: Identify Hanging Points

If a test hangs, check these common locations:

1. **Interactive selection code** in `hug-git-branch:556`:
   ```bash
   if ! read -r choice; then
       info "Cancelled."
       exit 1
   fi
   ```

2. **Confirmation prompts** in command scripts:
   ```bash
   if ! confirm_action "$operation"; then
       info "Cancelled."
       return 1
   fi
   ```

3. **Gum interactive commands** that expect user input

### Step 3: Apply EOF Simulation Fix

For hanging tests, wrap the command with EOF simulation:

```bash
# Before (hangs):
run hug-command

# After (no hanging):
run bash -c "echo | hug-command 2>&1"
```

### Step 4: Verify Fix

After applying fixes, test both individually and in bulk:

```bash
# Test individual fixed test
make test-unit TEST_FILE=test_file.bats TEST_FILTER="test description" TEST_SHOW_ALL_RESULTS=1

# Test entire file
make test-unit TEST_FILE=test_file.bats TEST_SHOW_ALL_RESULTS=1

# Test broader suite
make test-unit TEST_SHOW_ALL_RESULTS=1
```

## Testing Commands

### Makefile Targets (Recommended)

Use the provided Makefile targets for consistent testing:

```bash
# All tests (recommended for final validation)
make test                                    # Shows only failing tests
make test TEST_SHOW_ALL_RESULTS=1             # Shows all test results

# BATS-only testing
make test-bash                               # All BATS tests
make test-bash TEST_SHOW_ALL_RESULTS=1       # All BATS with verbose output

# Test categories
make test-unit                               # Unit tests only
make test-integration                        # Integration tests only
make test-lib                                # Library tests only

#  TEST_FILE to run specific test files
make test-unit TEST_FILE=test_worktree_create.bats
make test-lib TEST_FILE=test_hug_common.bats

# TEST_FILTER to filter by test name
make test-unit TEST_FILTER="hug wtc"
make test-bash TEST_FILTER="interactive mode"
```

## Test Helper Functions

### Repository Setup

```bash
create_test_repo               # Fresh git repo
create_test_repo_with_history  # Repo with commits
create_test_repo_with_changes # Repo with uncommitted changes
cleanup_test_repo             # Cleanup
```

### Assertions

```bash
assert_success / assert_failure
assert_output "text" / assert_output --partial "text"
assert_output --partial "partial text"
assert_file_exists / assert_file_not_exists
assert_git_clean()
```

### Environment Control

```bash
require_hug                    # Skip if hug not installed
require_git_version "2.23"     # Skip if git too old
disable_gum_for_test           # Disable gum for interactive tests
```

## Testing Environment Variables

### Hug-specific variables
- `HUG_FORCE`: Skip confirmation prompts
- `HUG_QUIET`: Suppress output functions
- `HUG_DISABLE_GUM`: Disable gum (set by `disable_gum_for_test`)

### Testing variables
- `TEST_SHOW_ALL_RESULTS=1`: Show all test results (not just failures)
- `TEST_FILTER="<pattern>"`: Filter tests by name pattern
- `TEST_FILE="<filename>"`: Run specific test file

## Common Pitfalls to Avoid

1. **Using direct `run hug-command`** for tests expecting cancellation (hangs in TTY)
2. **Not using test helper functions** for environment setup
3. **Ignoring error exit codes** - test both success and failure cases
4. **Hardcoding file paths** - use relative paths and test repos
5. **Testing production code without isolation** - use create_test_repo()

## Continuous Integration

### CI Pipeline
- **BATS tests**: Run on push/PR via `.github/workflows/test.yml`
- **Python tests**: Run for analysis modules via `make test-lib-py`
- **Coverage reporting**: Generated for Python tests, planned for BATS

### CI Best Practices
- Always run `make test` before committing
- Use `TEST_SHOW_ALL_RESULTS=1` to catch hanging issues
- Monitor test execution time for performance regressions

## Related Documentation

- **GitHub test workflow**: `.github/workflows/test.yml`
