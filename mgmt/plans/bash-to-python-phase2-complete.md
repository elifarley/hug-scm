# Phase 2 Complete: Migrate filter_branches to Python

## Summary

Successfully completed Phase 2 of the Bash to Python migration plan: migrated `filter_branches` (14 parameters, highest fragility risk) to Python with type-safe dataclasses.

## What Was Done

### 1. Created Python Module: `git/branch_filter.py`

**File:** `git-config/lib/python/git/branch_filter.py` (NEW, ~280 lines)

Key components:
- `FilterOptions` dataclass: Configuration options (exclude_current, exclude_backup, custom_filter)
- `FilteredBranches` dataclass: Result container with parallel arrays
- `filter_branches()` function: Type-safe filtering logic
- `main()` CLI entry point: Direct invocation support

### 2. Created Comprehensive pytest Tests

**File:** `git-config/lib/python/tests/test_branch_filter.py` (NEW, ~470 lines)

- 25 tests covering all functionality
- 100% pass rate (25/25)
- Tests for edge cases: empty input, all filtered out, inconsistent arrays
- CLI tests for all command-line flags

### 3. Added Feature Flag Integration

**File:** `git-config/lib/hug-git-branch` (updated)

```bash
if [[ "${HUG_USE_PYTHON_FILTER:-true}" == "true" ]]; then
    # Python module: type-safe filtering
    eval "$(python3 ... branch_filter.py filter ...)"
else
    # Bash fallback: 14 positional parameters
    filter_branches ...
fi
```

### 4. Created Git Package Structure

**File:** `git-config/lib/python/git/__init__.py` (NEW)

Established `git/` package for future branch-related modules.

## Metrics

| Metric | Value |
|--------|-------|
| **Python module created** | branch_filter.py (~280 lines) |
| **pytest tests created** | test_branch_filter.py (~470 lines) |
| **pytest tests passing** | 25/25 (100%) |
| **Library tests passing** | 19/19 (100%) |
| **Breaking changes** | 0 |
| **Regressions** | 0 |

## Test Results

### Python Tests (pytest)
```bash
make test-lib-py TEST_FILTER="test_branch_filter"
# Result: 25 passed in 0.08s
```

### Library Tests (BATS)
```bash
make test-lib TEST_FILE=test_hug_git_branch.bats
# Result: 1..19 ✓ All tests passed!
```

### Manual Verification
```bash
python3 git-config/lib/python/git/branch_filter.py filter \
    --branches "main feature hug-backups/tmp" \
    --hashes "abc def ghi" \
    --subjects "Init Feature Backup" \
    --dates "2026-01-30 2026-01-31 2026-01-31" \
    --exclude-backup \
    --current-branch "main"

# Output:
# declare -a filtered_branches=('main' 'feature')
# declare -a filtered_hashes=('abc' 'def')
# declare -a filtered_subjects=('Init' 'Feature')
# declare -a filtered_tracks=('' '')
# declare -a filtered_dates=('2026-01-30' '2026-01-31')
```

## Implementation Details

### Type Safety vs Bash Fragility

**Before (Bash - 14 positional parameters):**
```bash
filter_branches input_branches input_hashes input_subjects input_tracks input_dates \
    current_branch output_branches output_hashes output_subjects output_tracks output_dates \
    exclude_current exclude_backup filter_function
# ^^^ Fragile: one mistake causes "unbound variable" errors
```

**After (Python - type-safe dataclasses):**
```python
@dataclass
class FilterOptions:
    exclude_current: bool = False
    exclude_backup: bool = True
    custom_filter: Optional[str] = None

def filter_branches(
    branches: list[str],
    hashes: list[str],
    subjects: list[str],
    tracks: list[str],
    dates: list[str],
    current_branch: str,
    options: FilterOptions  # Single options object!
) -> FilteredBranches:
    # Type-safe filtering with clear API
```

### CLI Array Padding

The Python module gracefully handles inconsistent array lengths from CLI by padding shorter arrays with empty strings:

```python
# Pad shorter arrays to match the longest array length
def pad_array(arr, target_len):
    return arr + [""] * (target_len - len(arr))

max_len = max(len(branches), len(hashes), len(subjects), len(tracks), len(dates))
branches = pad_array(branches, max_len)
# ... etc
```

This makes the CLI more lenient while the direct `filter_branches()` function still validates array consistency.

## Known Limitations

### Custom Filter Function Not Supported

The Bash version supports an optional custom filter function:
```bash
filter_branches ... "$filter_function"  # Calls user-provided function
```

The Python version currently falls back to Bash when a custom filter is provided:
```bash
if [[ -n "$filter_function" ]]; then
    # Fall back to Bash for custom filter support
    filter_branches ... "$filter_function"
else
    # Use Python for standard filtering
    eval "$(python3 ...)"
fi
```

**Future work:** Implement custom filter function support in Python (requires callback mechanism).

## Files Created/Modified

### Created
1. `git-config/lib/python/git/__init__.py` - Package initialization
2. `git-config/lib/python/git/branch_filter.py` - Python module (~280 lines)
3. `git-config/lib/python/tests/test_branch_filter.py` - pytest tests (~470 lines)

### Modified
1. `git-config/lib/hug-git-branch` - Added feature flag wrapper (~40 lines added)

## Rollback Options

### Quick Rollback (< 1 minute)
```bash
export HUG_USE_PYTHON_FILTER=false
```

### Git Revert (< 5 minutes)
```bash
git revert HEAD
```

## Next Steps

Phase 2 is complete. Ready to proceed with:

- **Phase 3:** Migrate `multi_select_branches` (9 parameters, input parsing)
- **Phase 4:** Migrate `get_worktrees` (state machine parsing)
- **Phase 5:** Migrate `search_items_by_fields` (foundation function)

## Lessons Learned

### CLI Leniency is Important

The Bash caller may not always provide all arrays with consistent lengths. The Python module pads shorter arrays to avoid errors, making it more robust for CLI usage.

### Feature Flag Pattern Works Well

The `HUG_USE_PYTHON_FILTER` environment variable allows instant rollback without code changes:
- Default: `true` (use Python)
- Rollback: `false` (use Bash)
- Per-session: `export HUG_USE_PYTHON_FILTER=false`

### Pre-existing Test Issues

Some unit tests fail due to pre-existing gum/TTY issues (`unable to run filter: could not open a new TTY`), not related to this migration. Library tests pass completely.
