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
- ✅ `git/selection_core.py` - Shared selection toolkit (405 lines, 103 tests ✓)
- ✅ `git/branch_filter.py` - Branch filtering with dataclasses (288 lines, 25 tests ✓)
- ✅ `git/branch_select.py` - Multi- and single-branch selection (800 lines, 61 tests ✓)
- ✅ `git/worktree.py` - Worktree parsing (448 lines, 30 tests ✓)
- ✅ `git/search.py` - Field-based search with OR/AND logic (233 lines, 51 tests ✓)
- ✅ `git/tag_select.py` - Tag selection with direct git integration (629 lines, 93 tests ✓)
- ✅ `git/worktree_select.py` - Worktree selection with cross-module import (493 lines, 60 tests ✓)

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

## Selection Core Module (`git/selection_core.py`)

`git/selection_core.py` is the **single source of truth** for all interactive selection primitives shared across `branch_select.py`, `tag_select.py`, `worktree_select.py`, and `branch_filter.py`.

Before this module existed, each selection module duplicated `_bash_escape()` and inlined `declare`-statement generation — a DRY violation that caused subtle divergence bugs. Centralising these primitives ensures byte-for-byte identical output and identical environment variable names across every module.

### ANSI Color Constants

```python
from git.selection_core import YELLOW, BLUE, GREY, CYAN, GREEN, NC
```

| Constant | Escape Code | Intended Use |
|----------|-------------|--------------|
| `YELLOW` | `\x1b[33m` | Branch names, tag names, commit hashes |
| `BLUE`   | `\x1b[34m` | Dates, timestamps |
| `GREY`   | `\x1b[90m` | Secondary info (commit subjects, descriptions) |
| `CYAN`   | `\x1b[36m` | Tracking / remote info |
| `GREEN`  | `\x1b[32m` | Positive indicators (current item, success) |
| `NC`     | `\x1b[0m`  | No Color — reset all attributes |

### `bash_escape(s)`

Canonical bash string escaping using single-quote wrapping with the `'\''` idiom for embedded single quotes.

```python
bash_escape("hello")          # "'hello'"
bash_escape("it's alive")     # "'it'\\''s alive'"
bash_escape("path\\to")       # "'path\\\\to'"
bash_escape("")               # "''"
```

**Why single-quote wrapping?** Single-quoted strings in bash are literal — no variable expansion, no glob expansion, no backslash interpretation — making them the safest quoting strategy for arbitrary user data fed into `eval`.

**Order matters:** backslashes are doubled *before* single quotes are handled. Swapping the order would double-escape the backslashes introduced by the `'\''` idiom, producing garbled output.

### `BashDeclareBuilder`

Fluent builder that accumulates `declare` statements and renders them as a newline-separated string suitable for `eval` in a Bash adapter script.

```python
from git.selection_core import BashDeclareBuilder

output = (
    BashDeclareBuilder()
    .add_array("filtered_tags", ["v1.0", "v2.0"])
    .add_scalar("selection_status", "ready")
    .add_int("tag_count", 2)
    .build()
)
# declare -a filtered_tags=('v1.0' 'v2.0')
# declare selection_status='ready'
# declare -i tag_count=2
```

| Method | Bash output | Notes |
|--------|-------------|-------|
| `add_array(name, values)` | `declare -a name=('v1' 'v2')` | Each value is `bash_escape()`d |
| `add_scalar(name, value)` | `declare name='val'` | Value is `bash_escape()`d |
| `add_int(name, value)` | `declare -i name=42` | Integer emitted bare (safe, prevents quoting issues) |

Variable name validation is **eager**: invalid names (anything not matching `[a-zA-Z_][a-zA-Z0-9_]*`) raise `ValueError` immediately at `add_*` call time, following the fail-fast principle. Deferring to `build()` would produce confusing late errors when the invalid name has already been forgotten.

### `parse_numbered_input(user_input, num_items, allow_all=True)`

Parse a user selection string into a sorted list of 0-based indices.

```python
parse_numbered_input("1,2,3", 5)       # [0, 1, 2]
parse_numbered_input("1-3", 5)         # [0, 1, 2]
parse_numbered_input("all", 3)         # [0, 1, 2]
parse_numbered_input("1,3-5,7", 10)    # [0, 2, 3, 4, 6]
parse_numbered_input("", 5)            # []
parse_numbered_input("99", 5)          # []  (out-of-bounds silently skipped)
```

Supported input formats:

| Format | Example | Result |
|--------|---------|--------|
| Empty | `""` | `[]` |
| `a` / `all` (when `allow_all=True`) | `"all"` | `[0..n-1]` |
| Single number (1-based) | `"3"` | `[2]` |
| Comma-separated | `"1,3,5"` | `[0, 2, 4]` |
| Inclusive range | `"2-4"` | `[1, 2, 3]` |
| Mixed | `"1,3-5,7"` | `[0, 2, 3, 4, 6]` |

Out-of-bounds numbers and malformed tokens are **silently skipped** so the function never raises for bad user input. This is intentional: selection prompts should degrade gracefully rather than crash.

### `get_selection_input(test_selection=None, env_var="HUG_TEST_NUMBERED_SELECTION")`

Return user selection from the highest-priority available source, encoding the three-level precedence chain used uniformly across every selection module:

1. `test_selection` argument — if not `None`, returned as-is (the `None` sentinel means "not set"; `""` is a valid deliberate choice)
2. `env_var` environment variable — allows shell-script test suites to override selection
3. `input()` from stdin — the normal interactive path
4. `""` — returned silently when stdin raises `EOFError` (non-interactive CI environments)

```python
# In automated tests: inject a selection directly
get_selection_input(test_selection="1,3")   # returns "1,3" immediately

# In CI: set HUG_TEST_NUMBERED_SELECTION=2 in the environment
get_selection_input()                        # reads env var

# Interactively: user types at the terminal
get_selection_input()                        # reads stdin
```

### `add_common_cli_args(parser, include_no_gum=False)`

Register shared `argparse` arguments that every selection-module CLI accepts:

| Argument | Default | Purpose |
|----------|---------|---------|
| `--placeholder` | `""` | Prompt text displayed above the selection list |
| `--selection` | `None` | Pre-selected input for automated testing (simulates user typing) |
| `--no-gum` | *(not added)* | Only registered when `include_no_gum=True`; disables gum, falls back to numbered-list mode |

`--no-gum` is optional because only callers that drive `gum` should advertise the flag. Advertising an unknown flag confuses users who don't need it.

---

## Branch Select CLI Commands (`git/branch_select.py`)

`branch_select.py` exposes four CLI commands for use by Bash adapter scripts:

```bash
python3 branch_select.py <command> --branches "main dev feature/x" [options]
```

### Common Options (all commands)

| Option | Description |
|--------|-------------|
| `--branches LIST` | **Required.** Space-separated branch names |
| `--hashes LIST` | Space-separated commit hashes (optional, padded with `""` if shorter) |
| `--dates LIST` | Space-separated commit dates |
| `--subjects LIST` | Space-separated commit subjects |
| `--tracks LIST` | Space-separated tracking info |
| `--current-branch NAME` | Currently checked-out branch (used for the `* ` marker) |

### `select` — Multi-branch selection (numbered list)

Displays a numbered list, reads the user's comma/range selection, outputs bash declare statements.

```bash
python3 branch_select.py select \
  --branches "main dev feature/x" \
  --hashes "abc1234 def5678 ghi9012" \
  --placeholder "Select branches to delete"
```

**Output** (bash declare statements, `eval`-safe):
```bash
declare -a selected_branches=('main' 'dev')
declare -a selected_indices=(0 1)
```

Additional options: `--placeholder`, `--array-name` (default: `selected_branches`), `--no-gum`, `--selection`.

### `format-options` — Format options for gum

Outputs formatted option lines (one per stdout line) for piping directly into `gum filter` or `gum choose`. Each line includes ANSI-colored branch name, hash, date, subject, and tracking info.

```bash
python3 branch_select.py format-options \
  --branches "main dev" \
  --hashes "abc1234 def5678" \
  --dates "2024-01-15 2024-01-10"
```

**Output**: One colored line per branch, for display in `gum filter`.

### `prepare` — Prepare for gum interactive picker (single-select path)

Formats branch data and outputs bash declare statements so the Bash caller can `eval` the output and pass `formatted_options[]` directly to `gum choose`. Includes the `* ` marker on the current branch.

```bash
python3 branch_select.py prepare \
  --branches "main dev feature/x" \
  --current-branch "main"
```

**Output**:
```bash
declare -a formatted_options=('* main abc1234 ...' 'dev def5678 ...' 'feature/x ...')
declare selection_status='ready'
declare -i branch_count=3
```

When `--branches` is empty, emits safe defaults: `selection_status='no_branches'`, `branch_count=0`.

### `single-select` — Interactive single-branch selection

Displays a numbered list, reads exactly one number from the user (ranges and "all" are rejected), outputs a single-branch result as bash declare statements.

```bash
python3 branch_select.py single-select \
  --branches "main dev feature/x" \
  --current-branch "main" \
  --placeholder "Switch to branch"
```

**Output**:
```bash
declare selected_branch='dev'
declare selection_status='selected'
declare -i selected_index=1
```

`selection_status` values: `'selected'` (valid pick), `'cancelled'` (empty input or invalid token), `'no_branches'` (empty list).

Additional options: `--selection` (for automated testing).

---

## Adding a New Selection Domain — Checklist

When implementing a new interactive selection domain (e.g. stashes, remotes, worktrees), follow this six-step convention so the new module integrates seamlessly with the existing toolkit:

1. **Dataclass** — define a domain-specific item record with typed fields:
   ```python
   @dataclass
   class StashEntry:
       ref: str       # e.g. "stash@{0}"
       message: str
       date: str
   ```

2. **`load_*` function** — call `git` (via `subprocess`), parse stdout, return `list[YourDataclass]`:
   ```python
   def load_stashes(repo_path: str = ".") -> list[StashEntry]:
       ...
   ```

3. **`filter_*` function** — pure function, no I/O, takes a list and filter criteria, returns filtered list:
   ```python
   def filter_stashes(stashes: list[StashEntry], pattern: str = "") -> list[StashEntry]:
       ...
   ```
   Keeping this pure makes it trivially testable without mocking git.

4. **`format_display_rows`** — build ANSI-colored display strings for the selection list, using color constants from `selection_core`:
   ```python
   def format_display_rows(stashes: list[StashEntry]) -> list[str]:
       return [f"{YELLOW}{s.ref}{NC} {GREY}{s.message}{NC}" for s in stashes]
   ```

5. **CLI `main()`** — call `add_common_cli_args()`, dispatch on `prepare` / `select` subcommands using the same pattern as `branch_select.main()`:
   ```python
   def main():
       parser = argparse.ArgumentParser(...)
       parser.add_argument("command", choices=["prepare", "select"])
       add_common_cli_args(parser, include_no_gum=True)
       ...
   ```

6. **`to_bash_declare()`** — on your result dataclass, use `BashDeclareBuilder` to emit `eval`-safe output:
   ```python
   def to_bash_declare(self) -> str:
       return (
           BashDeclareBuilder()
           .add_scalar("selected_stash", self.ref)
           .add_scalar("selection_status", self.status)
           .add_int("selected_index", self.index)
           .build()
       )
   ```

**Why this structure?** The dataclass / load / filter / format / CLI split mirrors the Single Responsibility Principle: each layer is independently testable, and the pure `filter_*` function can be unit-tested without spawning git processes.
