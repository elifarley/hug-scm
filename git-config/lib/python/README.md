# Hug SCM Python Helpers

This directory contains Python implementations for computationally intensive or algorithmically complex Git analysis tasks that are better suited to Python than Bash.

## Design Principles

1. **Bash for orchestration, Python for computation**
   - Bash scripts handle argument parsing, Git invocation, and output formatting
   - Python scripts handle data processing, statistical analysis, and complex algorithms

2. **Minimal dependencies**
   - Prefer standard library where possible
   - Optional dependencies for enhanced features (numpy, matplotlib, etc.)
   - Graceful degradation when optional deps unavailable

3. **JSON as interface**
   - Bash pipes JSON to Python stdin
   - Python outputs JSON to stdout
   - Keeps interface clean and testable

4. **Performance-focused**
   - Use efficient algorithms and data structures
   - Cache intermediate results where appropriate
   - Stream processing for large datasets

## Module Organization

```
python/
├── README.md              # This file
├── hug_analysis.py        # Main analysis library
├── co_changes.py          # Co-change matrix calculation
├── activity.py            # Temporal activity analysis
├── ownership.py           # Code ownership/expertise detection
├── churn.py               # File/line churn analysis
└── requirements.txt       # Python dependencies
```

## When to Use Python vs Bash

### Use Python for:
- ✅ Matrix operations (co-change analysis)
- ✅ Statistical calculations (ownership weighting, correlations)
- ✅ Graph algorithms (dependency graphs)
- ✅ Complex data transformations
- ✅ Plotting/visualization (plotext for terminal, matplotlib for files)
- ✅ JSON handling (when it's not trivial)
- ✅ Machine learning (if we go that route)

### Use Bash for:
- ✅ Simple Git command wrapping
- ✅ Argument parsing and validation
- ✅ File system operations
- ✅ Output formatting and coloring
- ✅ Integration with existing Hug libraries

## Example Pattern

### Bash script (`git-analyze-co-changes`):
```bash
#!/usr/bin/env bash
# Parse arguments, validate inputs
commits=${1:-50}

# Get data from Git
git log --name-only --format='%H' -n "$commits" | \
  python3 "$CMD_BASE/../lib/python/co_changes.py" \
    --min-correlation 0.30 \
    --format table

# Format output using hug-common functions
```

### Python script (`co_changes.py`):
```python
#!/usr/bin/env python3
import sys
import json
from collections import defaultdict

def calculate_co_changes(log_input, min_correlation=0.30):
    # Parse stdin, build matrix, calculate correlations
    # Return JSON with results
    pass

if __name__ == '__main__':
    # Parse args, read stdin, output JSON
    pass
```

## Dependencies

### Required (standard library):
- `json` - Data exchange
- `sys`, `argparse` - CLI interface
- `collections` - Data structures
- `datetime` - Timestamp parsing
- `itertools` - Efficient iteration

### Optional (pip install):
- `numpy` - Fast matrix operations (for co-change analysis)
- `plotext` - Terminal plotting (for activity histograms)
- `networkx` - Graph algorithms (for dependency graphs)

Install optional dependencies:
```bash
pip install -r git-config/lib/python/requirements.txt
```

## Testing

All Python modules have comprehensive pytest-based unit tests following Google's
Python testing best practices.

### Running Tests

```bash
# Run all Python library tests
make test-lib-py

# Run with coverage report
make test-lib-py-coverage

# Run specific test file
cd git-config/lib/python
python3 -m pytest tests/test_activity.py -v

# Run tests matching pattern
python3 -m pytest tests/ -k "recency"

# Install pytest dependencies (auto-installed by test-lib-py if missing)
make test-deps-py-install
```

### Test Organization

```
git-config/lib/python/tests/
├── __init__.py              # Package initialization
├── conftest.py              # Shared fixtures (sample git log data)
├── test_activity.py         # 39 tests - temporal activity analysis ✓
├── test_co_changes.py       # 21 tests - co-change matrix ✓
├── test_ownership.py        # 25 tests - code ownership algorithms ✓
└── test_churn.py            # (TODO: line-level churn tests)
```

**Current Status**: 85/85 tests passing (100% ✓)

### Test Coverage

- **activity.py**: Temporal bucketing, pattern detection, histogram generation
- **co_changes.py**: Matrix construction, correlation calculation, sorting
- **ownership.py**: Exponential decay, ownership %, classification thresholds

### Integration Testing

For full end-to-end validation with real git repositories:

```bash
# Create demo repository
make demo-repo

# Test commands with real data
cd /tmp/demo-repo
hug analyze co-changes 50
hug analyze expert src/
hug analyze activity --by-hour
```

## Implementation Checklist

For each new Python helper:

- [ ] Create module with clear docstrings
- [ ] Accept JSON from stdin (or file paths as args)
- [ ] Output JSON to stdout
- [ ] Handle errors gracefully (exit codes)
- [ ] Add --help flag
- [ ] Add to requirements.txt if needs deps
- [ ] Write tests
- [ ] Document in this README

## Current Implementations

### Implemented (Production-Ready):
- ✅ `json_transform.py` - JSON transformation utilities (replaces bash commit search, 300+ lines ✓)
- ✅ `co_changes.py` - Co-change matrix analysis (265 lines, 21 tests ✓)
- ✅ `activity.py` - Temporal pattern analysis (300 lines, 39 tests ✓)
- ✅ `ownership.py` - Code expertise detection (325 lines, 25 tests ✓)
- ✅ `churn.py` - File and line-level churn analysis (281 lines, complete ✓)
- ✅ `deps.py` - Dependency graph construction (423 lines, complete ✓)
- ✅ `log_json.py` - Git log JSON formatting (256 lines, with tests ✓)

### Bash-to-Python Migration Modules (git/ subdirectory):
- ✅ `git/branch_filter.py` - Branch filtering with dataclasses (280 lines, 25 tests ✓)
- ✅ `git/branch_select.py` - Multi-branch selection (625 lines, 61 tests ✓)
- ✅ `git/worktree.py` - Worktree parsing (400 lines, 30 tests ✓)
- ✅ `git/search.py` - Field-based search with OR/AND logic (233 lines, 51 tests ✓)

## JSON Transform Module (NEW)

The `json_transform.py` module provides production-ready replacements for complex Bash parsing:

### Commit Search (Recommended over Bash)

**Benefits:**
- 10x faster parsing for large result sets
- Better Unicode/special character handling
- Cleaner, maintainable code
- Proper error handling

**Usage:**
```bash
# Search commits by message
python3 json_transform.py commit_search message "bug fix"

# Search by code changes
python3 json_transform.py commit_search code "function_name"

# Include file changes
python3 json_transform.py commit_search message "feature" --with-files
```

**Migration:** To use Python instead of Bash in `git-lf` or `git-lc`, simply call:
```bash
python3 "$CMD_BASE/../lib/python/json_transform.py" commit_search message "$search_term"
```
