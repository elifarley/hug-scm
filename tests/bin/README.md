# Gum Mock for Testing

This directory contains `gum-mock`, a comprehensive test double for the `gum` command used in Hug's interactive tests. The mock provides full simulation capabilities for all gum commands used in Hug.

## Why Gum Mock is Necessary

**CRITICAL LESSON**: Testing interactive gum commands with input piping fails in TTY environments.

### The Problem

```bash
# WRONG - Causes TTY errors or hangs
run bash -c "echo '' | hug bdel 2>&1"
# In CI: "unable to run filter: could not open a new TTY: open /dev/tty: no such device"
# In TTY: Hangs indefinitely waiting for input
```

**Root cause**: `gum filter` tries to open `/dev/tty` directly (not stdin), which:
- In non-TTY CI: fails with "no such device or address"
- In TTY environments: causes tests to hang waiting for real user input

### The Solution

Always use `setup_gum_mock()` for interactive tests:

```bash
setup_gum_mock
export HUG_TEST_GUM_INPUT_RETURN_CODE=1  # Simulate cancellation

run hug bdel
assert_success  # Exits 0 on graceful cancellation
assert_output --partial "No branches selected."

teardown_gum_mock
```

### How It Works

1. `setup_gum_mock()` adds `tests/bin` to the beginning of PATH
2. A symlink `tests/bin/gum` points to `tests/bin/gum-mock`
3. When hug commands call `gum`, they get the mock instead of real gum
4. The mock reads environment variables to determine behavior
5. `teardown_gum_mock()` restores the original PATH

This approach works reliably in **all environments** (TTY, non-TTY, CI, local).

## Usage

## Usage

The mock is automatically used when tests call `setup_gum_mock()` from `test_helper.bash`.

### Basic Example

```bash
@test "some interactive test" {
  # Setup the mock
  setup_gum_mock
  export HUG_TEST_GUM_SELECTION_INDEX=0  # Select first item

  # Run command that uses gum
  run hug w wipdel

  # Assertions
  assert_success

  # Cleanup
  teardown_gum_mock
}
```

### Advanced Control Examples

```bash
@test "test with confirmation" {
  setup_gum_mock
  gum_mock_success  # Set all gum interactions to succeed

  run hug w wipdel  # Will get "yes" for any confirmations
  assert_success

  teardown_gum_mock
}

@test "test with cancellation" {
  setup_gum_mock
  gum_mock_cancel  # Set all gum interactions to be cancelled

  run hug w wipdel  # Will be cancelled
  assert_failure
  assert_output --partial "Cancelled."

  teardown_gum_mock
}

@test "test with custom input" {
  setup_gum_mock
  export HUG_TEST_GUM_INPUT="delete"  # Custom input for gum input

  run hug some-command
  assert_success

  teardown_gum_mock
}
```

## Environment Variables

### Selection Control
- `HUG_TEST_GUM_SELECTION_INDEX`: Which item to select in `gum filter` (0-based index, default: 0)

### Confirmation Control
- `HUG_TEST_GUM_CONFIRM`: Set to "yes" or "no" to control `gum confirm` behavior
- `HUG_TEST_GUM_INPUT_RETURN_CODE`: Controls return code for gum input (0=success, 1=cancelled)

### Input Simulation
- `HUG_TEST_GUM_INPUT`: Pre-defined input for `gum input` command
- `HUG_TEST_GUM_INPUT_RETURN_CODE`: Force specific return code for input commands

## Commands Supported

### Fully Mocked Commands
- `gum filter`: Returns the item at `HUG_TEST_GUM_SELECTION_INDEX` (default: 0)
- `gum confirm`: Returns based on `HUG_TEST_GUM_CONFIRM` or passes through to real gum
- `gum input`: Uses `HUG_TEST_GUM_INPUT` or simulates interactive input with return code control

### Partially Supported Commands
- `gum log`: Passes through to real gum or echoes the message
- Other commands: Passes through to real gum if available

## Test Helper Functions

The following helper functions are available in `test_helper.bash` for fine-grained control:

```bash
# Enable/disable gum simulation
enable_gum_simulation()    # Set HUG_TEST_MODE=true
disable_gum_simulation()   # Unset HUG_TEST_MODE
disable_gum_for_test()     # Set HUG_DISABLE_GUM=true

# Control mock behavior
gum_mock_success()          # Set gum to always succeed
gum_mock_cancel()           # Set gum to always be cancelled
```

## Test Mode Integration

The mock integrates with Hug's test mode system:

- **HUG_TEST_MODE=true**: Bypasses TTY checks and enables gum in test environments
- **HUG_DISABLE_GUM=true**: Forces gum to be unavailable for testing error paths
- **Automatic**: Test mode is enabled globally in test_helper.bash

## Architecture

### Standalone Implementation
The mock is completely standalone - it does not source any Hug libraries to avoid circular dependencies:

```bash
# Standalone gum_available function
gum_available() {
  [[ "${HUG_DISABLE_GUM:-}" == "true" ]] && return 1
  [[ "${HUG_TEST_MODE:-}" == "true" ]] && return 0
  command -v gum >/dev/null 2>&1
}
```

### How It Works

1. `setup_gum_mock()` adds `tests/bin` to the beginning of PATH
2. A symlink `tests/bin/gum` points to `tests/bin/gum-mock`
3. When hug commands call `gum`, they get the mock instead
4. The mock reads environment variables to determine behavior
5. Test mode bypasses TTY checks for reliable automation
6. `teardown_gum_mock()` restores the original PATH

## Advanced Features

### TTY Simulation
The mock properly handles TTY detection in test environments:
- Test mode automatically bypasses TTY requirements
- Maintains production safety in non-test environments
- Enables reliable automated testing without hanging

### Error Simulation
The mock can simulate various error conditions:
- Input cancellation via return codes
- Missing interactive input handling
- Gum unavailability scenarios

### Flexible Input Control
Tests can control both the content and return codes:
- Pre-defined input values
- Custom return codes for different scenarios
- Dynamic behavior based on test requirements

## Best Practices

1. **Always call setup/teardown**: Ensure proper PATH management
2. **Use helper functions**: Leverage the provided test helpers for cleaner code
3. **Test both success and failure**: Use `gum_mock_success()` and `gum_mock_cancel()` for comprehensive coverage
4. **Clean environment variables**: Use teardown functions to avoid test interference
5. **Document custom behavior**: Comment any non-standard mock configurations

## Debugging

If gum mocking is not working as expected:

1. Check that `setup_gum_mock()` was called
2. Verify environment variables are set correctly
3. Ensure `HUG_TEST_MODE=true` for TTY bypass
4. Check PATH contains `tests/bin` first
5. Use `command -v gum` to verify which gum is being used
