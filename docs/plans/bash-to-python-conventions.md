# Bash to Python Migration Conventions

## Purpose

This document establishes the conventions and patterns for migrating Bash functions to Python in the Hug SCM project. The goal is to eliminate "unbound variable" bugs and improve code maintainability through type safety.

## Motivation

### The Problem: Fragility of Bash Positional Parameters

Recent bugs (`filter_branches` with 14 parameters, `print_interactive_branch_menu` with missing `dates` parameter) highlight a fundamental fragility in Bash:

```bash
# FRAGILE: 14 positional parameters - one mistake causes silent bugs
filter_branches input_branches input_hashes input_subjects input_tracks input_dates \
    current_branch output_branches output_hashes output_subjects output_tracks output_dates \
    exclude_current exclude_backup filter_function

# When function signature changes, ALL call sites must be updated perfectly
# Or you get: "unbound variable" errors at runtime
```

### The Python Solution: Type Safety with Dataclasses

```python
@dataclass
class FilterOptions:
    exclude_current: bool = False
    exclude_backup: bool = True
    custom_filter: Optional[str] = None

@dataclass
class FilteredBranches:
    branches: list[str]
    hashes: list[str]
    subjects: list[str]
    tracks: list[str]
    dates: list[str]

def filter_branches(
    branches: list[str],
    hashes: list[str],
    subjects: list[str],
    tracks: list[str],
    dates: list[str],
    current_branch: str,
    options: FilterOptions
) -> FilteredBranches:
    # Type-safe filtering with no positional parameter confusion
```

## When to Migrate to Python

### Migrate When:

| Criterion | Threshold | Rationale |
|-----------|-----------|-----------|
| **Parameter count** | 5+ positional parameters | Higher fragility risk |
| **Array manipulation** | 3+ nameref arrays | Synchronization error-prone |
| **Algorithmic complexity** | State machines, multi-pass loops | Python clearer for complex logic |
| **String parsing** | Complex regex/splitting | Python's string handling superior |
| **Already has Python equivalent** | Python exists, Bash is fallback | Remove duplication |

### Keep in Bash When:

- Simple Git command wrappers (< 50 lines)
- Primarily orchestrating other Bash functions
- User-interactive operations (gum integration - keep Bash glue)
- Heavy use of Bash-specific features for good reason

## Module Structure

```
git-config/lib/python/
├── git/
│   ├── __init__.py
│   ├── branch.py              # hug_git_branch.py (rename for clarity)
│   ├── branch_filter.py       # filter_branches migration
│   ├── branch_select.py       # multi_select_branches migration
│   └── worktree.py            # get_worktrees migration
├── search.py                  # search_items_by_fields migration
└── utils/
    └── (existing utility modules)
```

## Integration Pattern: `eval "$(python ...)"`

### Bash Calls Python

```bash
# Bash caller
eval "$(python3 "$HUG_HOME/git-config/lib/python/git/branch_filter.py" \
    filter \
    --branches "${branches[*]}" \
    --hashes "${hashes[*]}" \
    --subjects "${subjects[*]}" \
    --tracks "${tracks[*]}" \
    --dates "${dates[*]}" \
    --current-branch "$current_branch" \
    --exclude-current \
    --exclude-backup)"

# Variables now available: filtered_branches, filtered_hashes, etc.
```

### Python Outputs Bash Variable Declarations

```python
def to_bash_declare(self) -> str:
    """Format as bash variable declarations.

    Outputs bash 'declare' statements that can be eval'd to set variables.
    All strings are properly escaped for safe bash evaluation.
    Arrays maintain consistent lengths (all same size).
    """
    lines = []

    # Scalar variables
    lines.append(f"declare current_branch={_bash_escape(self.current_branch)}")
    lines.append(f"declare max_len={self.max_len}")

    # Build arrays - use space-separated values for bash arrays
    branches_arr = " ".join(_bash_escape(b.name) for b in self.branches)
    hashes_arr = " ".join(_bash_escape(b.hash) for b in self.branches)

    lines.append(f"declare -a branches=({branches_arr})")
    lines.append(f"declare -a hashes=({hashes_arr})")

    return "\n".join(lines)


def _bash_escape(s: str) -> str:
    """Escape string for safe bash declare usage.

    Strategy: '...' with '\'' for embedded single quotes.
    """
    s = s.replace("\\", "\\\\")  # Backslashes first (order matters)
    s = s.replace("'", "'\\''")  # Single quotes
    return f"'{s}'"
```

## CLI Entry Point Pattern

Each Python module should be directly invocable from bash:

```python
def main():
    """CLI entry point for bash wrapper calls.

    Usage:
        python3 branch_filter.py <command> [options]

    Commands:
        filter    Apply filters to branch lists

    Options:
        --branches LIST    Space-separated branch names
        --hashes LIST      Space-separated commit hashes
        --exclude-current  Exclude current branch from results
        --exclude-backup   Exclude backup branches (default: true)

    Outputs bash variable declarations by default.
    Returns exit code 1 on error.
    """
    import argparse

    parser = argparse.ArgumentParser(description="Filter git branches for Hug SCM")
    parser.add_argument("command", choices=["filter"], help="Command to run")
    parser.add_argument("--branches", required=True, help="Space-separated branch names")
    parser.add_argument("--hashes", required=True, help="Space-separated commit hashes")
    parser.add_argument("--exclude-current", action="store_true", help="Exclude current branch")
    parser.add_argument("--exclude-backup", action="store_true", default=True, help="Exclude backup branches")

    args = parser.parse_args()

    try:
        # Parse space-separated values into lists
        branches = args.branches.split()
        hashes = args.hashes.split()

        # Run filter logic
        result = filter_branches(branches, hashes, ...)

        # Output bash declarations
        print(result.to_bash_declare())

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
```

## Feature Flag Pattern for Gradual Rollout

**NOTE:** Feature flags have been removed as of the cleanup completion (2026-01-31). The pattern below is retained for historical reference and may be used for future migrations.

During migration, use feature flags to enable parallel testing:

```bash
# In Bash caller
if [[ "${HUG_USE_PYTHON_FILTER:-true}" == "true" ]]; then
    eval "$(python3 "$HUG_HOME/git-config/lib/python/git/branch_filter.py" filter ...)"
else
    filter_branches ...  # Bash fallback
fi
```

### Rollout Process:

1. **Week 1-2**: Run both Bash and Python in parallel, compare outputs
2. **Week 3-4**: Set `HUG_USE_PYTHON_FILTER=true` by default
3. **Week 5+**: Remove Bash fallback after validation
4. **Cleanup**: Remove feature flag entirely once migration is validated

## Testing Strategy

### Three-Tier Testing

1. **Unit Tests (pytest)**: Test Python functions in isolation
   - Mock subprocess calls
   - Test edge cases
   - Target: 80%+ coverage

2. **Comparison Tests (temporary)**: Run Bash and Python in parallel, compare outputs
   - Only during migration phase
   - Remove once Python is proven

3. **Integration Tests (BATS)**: End-to-end tests still pass
   - Existing BATS test suite validates behavior
   - No breaking changes to users

### Test File Locations

```
git-config/lib/python/tests/
├── test_branch.py              # Existing (rename from test_hug_git_branch.py)
├── test_branch_filter.py       # NEW
├── test_branch_select.py       # NEW
├── test_worktree.py            # NEW
└── test_search.py              # NEW
```

### pytest Best Practices

```python
"""Unit tests for branch_filter.py.

Following Google Python testing best practices:
- Arrange-Act-Assert pattern
- Descriptive test names
- Test edge cases and error conditions
- Mock subprocess calls to avoid external dependencies
"""

from unittest.mock import patch
import pytest

class TestFilterBranches:
    """Tests for filter_branches function."""

    def test_excludes_current_branch_when_enabled(self):
        """Should exclude current branch when exclude_current=True."""
        # Arrange
        branches = ["main", "feature", "bugfix"]
        options = FilterOptions(exclude_current=True, exclude_backup=False)

        # Act
        result = filter_branches(branches, ..., current_branch="main", options=options)

        # Assert
        assert "main" not in result.branches
        assert "feature" in result.branches

    def test_handles_empty_input(self):
        """Should handle empty input arrays."""
        result = filter_branches([], ..., current_branch="", options=FilterOptions())
        assert len(result.branches) == 0
```

## Dataclass Design Patterns

### Use dataclasses for complex return values

```python
from dataclasses import dataclass
from typing import Optional

@dataclass
class BranchInfo:
    """Single branch information."""
    name: str
    hash: str
    date: str = ""
    subject: str = ""
    track: str = ""
    remote_ref: str = ""


@dataclass
class BranchDetails:
    """Complete branch listing result."""
    current_branch: str
    max_len: int
    branches: list[BranchInfo]

    def to_bash_declare(self) -> str:
        """Format as bash variable declarations."""
        # Implementation...
```

### Use Optional for nullable fields

```python
from typing import Optional

@dataclass
class FilterOptions:
    """Filter configuration options."""
    exclude_current: bool = False
    exclude_backup: bool = True
    custom_filter: Optional[str] = None  # May be None
```

## Naming Conventions

### Python Modules

- Use lowercase with underscores: `branch_filter.py`, `worktree.py`
- Name after primary functionality, not bash function name
- Examples:
  - `filter_branches` → `branch_filter.py`
  - `multi_select_branches` → `branch_select.py`
  - `get_worktrees` → `worktree.py`

### Python Functions

- Use snake_case: `filter_branches()`, `get_worktrees()`
- Match bash function names where appropriate for familiarity
- Return dataclass instances, not tuples

### Dataclasses

- Use descriptive names: `BranchInfo`, `FilterOptions`, `WorktreeInfo`
- Plural for collections: `BranchDetails`, `FilteredBranches`

## Error Handling

### Python should raise exceptions, not return error codes

```python
# BAD: Return None on error
def get_branch_details() -> Optional[BranchDetails]:
    try:
        ...
    except Exception:
        return None

# GOOD: Raise exceptions
def get_branch_details() -> BranchDetails:
    # Let CalledProcessError propagate
    output = subprocess.run(["git", ...], check=True, capture_output=True)
    ...
```

### Bash callers check exit code

```bash
if ! eval "$(python3 ...)" 2>/dev/null; then
    error "Failed to get branch details"
    return 1
fi
```

## Performance Considerations

- Subprocess overhead is negligible for complex functions (>100 lines of Bash)
- For simple wrappers (<10 lines), keep in Bash
- Batch git operations where possible (use `git for-each-ref` with multiple fields)

## Documentation

### Docstrings follow Google style

```python
def filter_branches(
    branches: list[str],
    hashes: list[str],
    subjects: list[str],
    tracks: list[str],
    dates: list[str],
    current_branch: str,
    options: FilterOptions
) -> FilteredBranches:
    """Filter branch lists based on criteria.

    Args:
        branches: List of branch names to filter
        hashes: List of commit hashes (parallel to branches)
        subjects: List of commit subjects (parallel to branches)
        tracks: List of tracking info (parallel to branches)
        dates: List of commit dates (parallel to branches)
        current_branch: Name of the current branch
        options: FilterOptions configuration

    Returns:
        FilteredBranches dataclass with filtered arrays

    Raises:
        ValueError: If input arrays have inconsistent lengths

    Example:
        >>> options = FilterOptions(exclude_current=True)
        >>> result = filter_branches(
        ...     ["main", "feature"], ["abc", "def"], ...
        ...     current_branch="main", options=options
        ... )
        >>> result.branches
        ['feature']
    """
```

## Migration Checklist

Before considering a migration complete:

- [ ] Python module created with proper dataclasses
- [ ] All functions have comprehensive docstrings
- [ ] pytest tests written with 80%+ coverage
- [ ] Bash wrapper updated to call Python
- [ ] Feature flag added (if gradual rollout)
- [ ] Integration tests (BATS) pass
- [ ] Manual smoke test performed
- [ ] Performance check passed (no noticeable slowdown)
- [ ] Documentation updated (README.md, command docs)
- [ ] Git commit message follows project conventions
- [ ] **Cleanup phase:** Remove feature flag and Bash fallback after validation

## Rollback Plan

Each migration should support instant rollback:

1. **Feature flags**: Set `HUG_USE_PYTHON_<MODULE>=false` (< 1 minute)
2. **Git revert**: `git revert <commit>` (< 5 minutes)
3. **Document rollback steps** in migration PR description

## Success Metrics

- Zero breaking changes to users (no regressions)
- 80%+ test coverage for all new Python modules
- Reduced nameref usage (measure: `grep -r "local -n" git-config/lib/`)
- Reduced Bash LOC (target: ~800 lines removed across all phases)
- All 961+ unit tests passing throughout migration
- Zero "unbound variable" bugs in migrated code

## References

- Phase 1-5 completion summary: `docs/plans/bash-to-python-phase1-complete.md`
- Cleanup completion summary: `docs/plans/bash-to-python-cleanup-complete.md`
- Existing implementation: `git-config/lib/python/hug_git_branch.py`
- Test examples: `git-config/lib/python/tests/test_hug_git_branch.py`
- Project testing guide: `TESTING.md`
- Commit message conventions: `CLAUDE.md` (Commit Message Philosophy section)
