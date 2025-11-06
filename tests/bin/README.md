# Gum Mock for Testing

This directory contains `gum-mock`, a test double for the `gum` command used in Hug's interactive tests.

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

## Environment Variables

- `HUG_TEST_GUM_SELECTION_INDEX`: Which item to select in `gum filter` (0-based index)
- `HUG_TEST_GUM_CONFIRM`: Set to "yes" or "no" to control `gum confirm` behavior

## Commands Supported

- `gum filter`: Returns the item at `HUG_TEST_GUM_SELECTION_INDEX` (default: 0)
- `gum confirm`: Returns based on `HUG_TEST_GUM_CONFIRM` or passes through to real gum
- `gum log`: Passes through to real gum or echoes the message
- Other commands: Passes through to real gum if available

## How It Works

1. `setup_gum_mock()` adds `tests/bin` to the beginning of PATH
2. A symlink `tests/bin/gum` points to `tests/bin/gum-mock`
3. When hug commands call `gum`, they get the mock instead
4. The mock reads environment variables to determine behavior
5. `teardown_gum_mock()` restores the original PATH
