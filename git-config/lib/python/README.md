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

Each Python module should be testable independently:

```bash
# Unit tests
python3 -m pytest git-config/lib/python/test_*.py

# Integration test via Bash
hug analyze co-changes 10
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

### Planned (stubs exist):
- `co_changes.py` - Co-change matrix analysis
- `activity.py` - Temporal pattern analysis
- `ownership.py` - Code expertise detection
- `churn.py` - Line/file churn calculation

### To Be Implemented:
- `deps.py` - Dependency graph construction
- `stats.py` - Repository statistics aggregation
