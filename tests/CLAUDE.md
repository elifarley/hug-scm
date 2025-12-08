# CLAUDE.md - Testing Guidelines and Best Practices

This document provides guidance to Claude Code when working with tests in the Hug SCM repository.

## Testing Philosophy

Hug SCM uses the BATS (Bash Automated Testing System) framework to test its Bash-based CLI commands; Python tests use pytest. Testing is structured into 4 main categories (fastest groups first):

1. **Python Library tests** (`git-config/lib/python/tests/`)
   - `make test-lib-py`
2. **Library tests** (`tests/lib/`)
    - `make test-lib`
3. **Unit tests** (`tests/unit/`): Individual command testing
   - `make test-unit`
4. **Integration tests** (`tests/integration/`): End-to-end workflows
    - `make test-integration`

## Critical Issue: TTY Environment and Hanging Tests

### Root Cause Analysis

**Problem**: Tests that read from STDIN (calls to `gum`, `read`, etc) can hang indefinitely in TTY (terminal) environments.

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

### How to identify hanging tests

Instead of running all tests at once (`make test`), run tests by category (see `## Testing Philosophy` above).
You MUST include `TEST_SHOW_ALL_RESULTS=1` argument after the target name so that you can see the name of each test that finished (without that, only failed tests are shown).

### Environment Detection

To diagnose TTY vs non-TTY behavior, use these commands:

```bash
# Check if stdin is a TTY
[[ -t 0 ]] && echo "STDIN is TTY" || echo "STDIN is NOT TTY"

# Check if stdout is a TTY
[[ -t 1 ]] && echo "STDOUT is TTY" || echo "STDOUT is NOT TTY"
```

## Best Practices for Interactive Tests

### 1. Preferred: Use Gum Mock Infrastructure for Interactive Testing

Hug SCM has a sophisticated gum mock system that allows comprehensive testing of interactive functionality without hanging or requiring actual user input. This is the recommended approach for testing gum interactions.

#### Gum Mock Overview

The gum mock system (`tests/bin/gum-mock`) provides realistic simulation of gum commands while allowing tests to control behavior:

```bash
setup_gum_mock                    # Enable gum mock system
export HUG_TEST_GUM_SELECTION_INDEX=1  # Select second item
export HUG_TEST_GUM_CONFIRM=yes      # Simulate "yes" confirmation
export HUG_TEST_GUM_INPUT_RETURN_CODE=1  # Simulate cancellation
export HUG_TEST_GUM_INPUT="1,3"    # Multi-select input
teardown_gum_mock                 # Clean up environment
```

#### Example: Gum Mock Testing

```bash
@test "select_branches: interactive selection with gum mock" {
  setup_gum_mock
  export HUG_TEST_GUM_SELECTION_INDEX=1  # Select second branch

  declare -a selected_branches=()

  # Mock compute_local_branch_details to return test data
  compute_local_branch_details() {
    local -n _current_branch_ref=$1 _max_len_ref=$2 _hashes_ref=$3 _branches_ref=$4 _tracks_ref=$5 _subjects_ref=$6
    _current_branch_ref="main"
    _max_len_ref="20"
    _hashes_ref=("abc123" "def456" "ghi789")
    _branches_ref=("main" "feature-1" "feature-2")
    _tracks_ref=("[origin/main]" "" "")
    _subjects_ref=("Initial" "Feature" "More work")
    return 0
  }

  # Test actual gum interaction - no hanging!
  select_branches selected_branches --exclude-current --exclude-backup

  # Verify the selection worked correctly
  [[ ${#selected_branches[@]} -eq 1 ]]
  [[ "${selected_branches[0]}" == "feature-1" ]]  # Index 1 = feature-1

  teardown_gum_mock
}

@test "hug confirm: uses gum mock for confirmation testing" {
  setup_gum_mock
  export HUG_TEST_GUM_CONFIRM=yes  # Simulate "yes" response

  run hug some-command-that-confirms
  assert_success
  # Command should proceed because user said "yes"

  teardown_gum_mock
}

@test "select_branches: handles gum cancellation" {
  setup_gum_mock
  export HUG_TEST_GUM_INPUT_RETURN_CODE=1  # Simulate cancellation

  declare -a selected_branches=()

  # Should fail gracefully due to cancellation
  run select_branches selected_branches
  assert_failure 1
  assert_output --partial "Cancelled"

  teardown_gum_mock
}
```

### 2. Alternative: Disable Gum for Simple Tests

For tests that don't need to verify gum interaction specifically, disable gum entirely:

```bash
@test "hug b: basic branch selection (no gum interaction needed)" {
  # Disable gum entirely for simpler testing
  disable_gum_for_test

  # Test functionality without gum
  run hug b some-branch
  assert_success
}
```

### 3. Use Input Piping for Simple Prompt Responses

For tests that need to handle simple yes/no prompts without complex interaction, use input piping:

```bash
@test "git-wtc: handles non-existent branch with user input" {
  # When command prompts for branch creation, automatically answer "n"
  run bash -c 'echo "n" | git-wtc nonexistent-branch'
  assert_failure
  assert_output --partial "does not exist locally"
}

@test "git-wtdel: handles deletion prompts with confirmation" {
  create_test_worktree "feature-1" "$TEST_REPO"

  # Automatically confirm deletion when prompted
  run bash -c 'echo "y" | git-wtdel "${TEST_REPO}-wt-feature-1"'
  assert_success
  assert_worktree_not_exists "${TEST_REPO}-wt-feature-1"
}
```

#### Input Piping Patterns

**Common prompt responses**:
- `echo "n"` - Decline/No response (most common for error testing)
- `echo "y"` - Accept/Yes response (for confirmation testing)
- `echo ""` - Empty input/Cancel (for cancellation testing)

**When to use input piping**:
- ✅ Commands that prompt for branch creation (git-wtc with non-existent branches)
- ✅ Commands that require deletion confirmation (git-wtdel without --force)
- ✅ Simple yes/no prompts without complex menu navigation
- ✅ When you want to test the actual command behavior, not just the UI

**When NOT to use input piping**:
- ❌ Complex gum filter/select menus (use gum mock instead)
- ❌ Multi-step interactive workflows (use gum mock)
- ❌ When you need to test UI behavior specifically (use gum mock)

### 4. Use EOF Simulation for Tests That Expect Cancellation

For tests that need to verify cancellation behavior in interactive modes, use EOF simulation:

```bash
@test "hug wtc: interactive mode with no branch argument" {

  # Test interactive mode with EOF input (provides cancellation)
  run bash -c "echo | git-wtc 2>&1"
  assert_failure  # Exits with code 1 due to cancellation

  # Should show cancellation message
  assert_output --partial "Cancelled"
}

@test "hug wtc: interactive mode with explicit -- flag" {

  # Test interactive mode with explicit -- flag and EOF
  run bash -c "echo | git-wtc -- 2>&1"
  assert_failure  # Exits with code 1 due to cancellation

  # Should show cancellation message
  assert_output --partial "Cancelled"
}
```

### 5. Test Environment Isolation

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

### 6. Follow Established Patterns

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
   if ! prompt_confirm_danger "$operation"; then
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
run bash -c "echo 'what the user should type' | hug-command 2>&1"
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

# Runs all bash-related tests
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

## Gum Mock Reference

### Setup and Teardown

```bash
setup_gum_mock                    # Enable gum mock system
teardown_gum_mock                 # Restore original PATH and cleanup
```

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `HUG_TEST_GUM_SELECTION_INDEX` | Which item to select in filter/choose commands | `export HUG_TEST_GUM_SELECTION_INDEX=1` |
| `HUG_TEST_GUM_CONFIRM` | Confirm response (yes/no) | `export HUG_TEST_GUM_CONFIRM=yes` |
| `HUG_TEST_GUM_INPUT` | Input response for input commands | `export HUG_TEST_GUM_INPUT="1,3"` |
| `HUG_TEST_GUM_INPUT_RETURN_CODE` | Return code for input commands | `export HUG_TEST_GUM_INPUT_RETURN_CODE=1` |

### Gum Commands Supported

- **filter**: Simulates interactive selection with `HUG_TEST_GUM_SELECTION_INDEX`
- **confirm**: Simulates yes/no responses with `HUG_TEST_GUM_CONFIRM`
- **input**: Simulates text input with `HUG_TEST_GUM_INPUT` and `HUG_TEST_GUM_INPUT_RETURN_CODE`
- **log**: Passes through to real gum if available
- **Other commands**: Returns success without affecting behavior

### Gum Mock Scenarios

```bash
# Single selection - choose first item
setup_gum_mock
export HUG_TEST_GUM_SELECTION_INDEX=0
# Run test that uses gum filter
teardown_gum_mock

# Multi-selection - choose items 1 and 3
setup_gum_mock
export HUG_TEST_GUM_INPUT="1,3"
# Run test that uses multi-select
teardown_gum_mock

# Confirm "yes"
setup_gum_mock
export HUG_TEST_GUM_CONFIRM=yes
# Run test that requires confirmation
teardown_gum_mock

# Cancel input
setup_gum_mock
export HUG_TEST_GUM_INPUT_RETURN_CODE=1
# Run test that expects cancellation
teardown_gum_mock
```

## Common Pitfalls to Avoid

1. **Using direct `run hug-command`** for tests expecting cancellation (hangs in TTY)
2. **Not using test helper functions** for environment setup
3. **Ignoring error exit codes** - test both success and failure cases
4. **Hardcoding file paths** - use relative paths and test repos
5. **Testing production code without isolation** - use create_test_repo()

## Gum Mock Migration Guide

### From `disable_gum_for_test` to Gum Mock

#### Before (Simple, Limited Testing)
```bash
@test "interactive test - simple fix" {
  disable_gum_for_test
  run hug interactive-command
  # Only tests that it doesn't hang
}
```

#### After (Comprehensive Testing)
```bash
@test "interactive test - comprehensive gum mock" {
  setup_gum_mock
  export HUG_TEST_GUM_SELECTION_INDEX=1  # Control behavior

  run hug interactive-command
  assert_success

  # Can now verify actual gum interaction behavior
  [[ ${#selected_items[@]} -eq 1 ]]
  [[ "${selected_items[0]}" == "expected_item" ]]

  teardown_gum_mock
}
```

### Enhanced Test Examples

#### Example 1: Branch Selection with Specific Branch Chosen
```bash
@test "select_branches: chooses feature-1 branch" {
  setup_gum_mock
  export HUG_TEST_GUM_SELECTION_INDEX=1  # Choose second branch (feature-1)

  declare -a selected_branches=()
  # ... setup test data ...

  select_branches selected_branches

  # Verify the correct branch was selected
  [[ ${#selected_branches[@]} -eq 1 ]]
  [[ "${selected_branches[0]}" == "feature-1" ]]

  teardown_gum_mock
}
```

#### Example 2: Multi-Branch Selection
```bash
@test "multi_select_branches: chooses multiple branches" {
  setup_gum_mock
  export HUG_TEST_GUM_INPUT="1,3"  # Choose first and third items

  declare -a selected_branches=()
  # ... setup test data ...

  multi_select_branches selected_branches

  # Verify multiple branches were selected
  [[ ${#selected_branches[@]} -eq 2 ]]
  [[ "${selected_branches[@]}" == "main feature-2" ]]  # Example expected result

  teardown_gum_mock
}
```

## Continuous Integration

### CI Pipeline
- Run on push/PR via `.github/workflows/test.yml`
- **Coverage reporting**: Generated for Python tests, planned for BATS

### CI Best Practices
- Always run `make test` before committing
- Use `TEST_SHOW_ALL_RESULTS=1` to catch hanging issues. Last line that shows before hanging identifies the last test that didn't hang.

## Related Documentation

- **GitHub test workflow**: `.github/workflows/test.yml`
