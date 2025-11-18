# TODO: Complete Analysis Gateway Commands

This document tracks implementation of the `hug analyze` stub commands. Each command requires sophisticated algorithms best implemented in Python, following the Bash/Python hybrid pattern established in `git-config/lib/python/README.md`.

## Implementation Status

### ✅ Completed
- [x] `hug stats file` - File-level statistics (uses churn.py)
- [x] `hug stats author` - Author contribution analytics
- [x] `hug stats branch` - Branch statistics and metrics
- [x] `hug fblame --churn` - File churn analysis (uses churn.py)
- [x] `hug analyze co-changes` - Co-change matrix analysis (uses co_changes.py)
- [x] `hug analyze expert` - Code ownership detection (uses ownership.py)
- [x] `hug analyze activity` - Temporal activity patterns (uses activity.py)
- [x] Update README.md with implemented commands
- [x] Update skills/SKILL.md with new examples

### 🚧 In Progress
- [x] Python helper infrastructure improvements
  - [x] Using PyTest best practices, create unit tests for the python libs (**85/85 tests passing 100% ✓**)
    - activity.py: 39 tests ✓
    - co_changes.py: 21 tests ✓
    - ownership.py: 25 tests ✓
  - [x] Add Makefile targets for Python testing (test-lib-py, test-lib-py-coverage, test-deps-py-install)
  - [x] Updated git-config/lib/python/README.md with testing documentation
  - [ ] Complete line-level churn in `churn.py`
  - [ ] POSTPONED: Add caching mechanism for expensive operations
  - [ ] POSTPONED: Add progress indicators for long-running analysis

### 📋 Planned

#### 1. ~~`hug analyze co-changes` - Co-change Matrix Analysis~~ ✅ COMPLETED

**Status:** ✅ IMPLEMENTED
**Python Script:** `co_changes.py` (pure Python, no dependencies)

**WHY:** Files that change together reveal architectural coupling. When A and B always change together, they're likely coupled and should be reviewed together, refactored into a module, or documented as a dependency.

**IMPLEMENTATION:**
- **Bash Script:** `git-analyze-co-changes`
  - Parse arguments (commit count, min correlation threshold)
  - Run `git log --name-only --format=%H -n N`
  - Pipe file lists to Python helper
  - Format output (table, JSON, or visualization)

- **Python Script:** `git-config/lib/python/co_changes.py`
  ```python
  # Input: Commit hashes and file lists from git log
  # Algorithm:
  #   1. Build co-occurrence matrix: M[file_a][file_b] = times changed together
  #   2. Calculate correlation: correlation = co-occurrences / min(changes_a, changes_b)
  #   3. Filter by threshold (e.g., >30% correlation)
  #   4. Rank by correlation strength
  # Output: JSON with file pairs and correlation scores
  ```

- **Dependencies:** numpy (optional, fallback to pure Python with dict)

**OUTPUT EXAMPLE:**
```
Files that change together (>30% correlation):

  src/auth/login.js ↔ src/auth/session.js     (68%, 23/34 commits)
  src/api/users.js ↔ src/models/user.js       (54%, 18/33 commits)
  src/auth/*.js ↔ tests/auth/*.test.js        (45%, 15/33 commits)
```

**USE CASES:**
- Pre-merge: "What other files should I review?"
- Refactoring: "Which files form cohesive modules?"
- Architecture: "Where is coupling too high?"

---

#### 2. ~~`hug analyze activity` - Temporal Activity Patterns~~ ✅ COMPLETED

**Status:** ✅ IMPLEMENTED
**Python Script:** `activity.py` (standard library only)

**WHY:** Development patterns reveal team dynamics, risk windows, and process issues. Commits at 3am suggest pressure. Concentrated activity suggests knowledge silos. Weekend commits suggest work-life issues.

**IMPLEMENTATION:**
- **Bash Script:** `git-analyze-activity`
  - Parse arguments (--by-hour, --by-day, --by-author, --since)
  - Run `git log --format='%ai|%an'` with filters
  - Pipe to Python or use awk for simple aggregation
  - Display histogram or table

- **Python Script:** `git-config/lib/python/activity.py`
  ```python
  # Input: Timestamp and author from git log
  # Algorithm:
  #   1. Parse timestamps into hour/day/week buckets
  #   2. Count commits per bucket
  #   3. Calculate statistics (mean, median, peaks)
  #   4. Optional: Generate ASCII histogram with plotext
  # Output: JSON or formatted table with histogram
  ```

- **Dependencies:** plotext (optional, for terminal graphs)

**OUTPUT EXAMPLE:**
```
Commit Activity by Hour (Last 90 days):

09:00 ████████████████ 45 commits
10:00 ████████████████████ 58 commits
11:00 ███████████████████████ 67 commits
14:00 ██████████████ 38 commits
02:00 ██ 5 commits ⚠️  Late night activity

Commit Activity by Day of Week:

Mon ████████████████████ 89 commits
Tue ███████████████████ 84 commits
Wed ████████████████████ 92 commits
Sat ████ 12 commits ⚠️  Weekend work detected
```

**USE CASES:**
- Team health: "Are people working sustainable hours?"
- Sprint planning: "What's our peak productivity time?"
- Process improvement: "Is weekend work necessary?"

---

#### 3. `hug analyze deps` - Commit Dependency Graph

**Priority:** LOW
**Complexity:** HIGH
**Python Required:** Yes (networkx for graph algorithms)

**WHY:** Understanding commit relationships helps with cherry-picking, reverting, and feature branch management. "What else depends on this commit?" is critical for safe history rewriting.

**IMPLEMENTATION:**
- **Bash Script:** `git-analyze-deps`
  - Parse arguments (commit hash, --depth, --feature, --format)
  - Get commit and its file list
  - Find related commits (touching same files)
  - Pipe to Python for graph construction
  - Output as tree, JSON, or DOT (Graphviz)

- **Python Script:** `git-config/lib/python/deps.py`
  ```python
  # Input: Commit hashes and file relationships
  # Algorithm:
  #   1. Build graph: nodes=commits, edges=shared files
  #   2. Use BFS/DFS to traverse up to max depth
  #   3. Weight edges by number of shared files
  #   4. Render as ASCII tree or export as DOT
  # Output: ASCII tree or DOT format for Graphviz
  ```

- **Dependencies:** networkx (required for graph algorithms)

**OUTPUT EXAMPLE:**
```
abc1234 (feat: add authentication)
  ├─ def5678 (fix: auth bug in session handling)
  │   └─ mno7890 (fix: session timeout issue)
  ├─ ghi9012 (refactor: extract auth logic)
  └─ jkl3456 (test: add auth integration tests)
      └─ pqr1234 (test: fix test flakiness)

5 related commits found (depth=2)
Shared files: src/auth.js, src/session.js
```

**USE CASES:**
- Revert planning: "What will break if I revert this?"
- Feature tracking: "What commits are part of this feature?"
- Cherry-pick safety: "What dependencies must I include?"

---

#### 4. ~~`hug analyze expert` - Code Ownership Detection~~ ✅ COMPLETED

**Status:** ✅ IMPLEMENTED
**Python Script:** `ownership.py` (standard library only)

**WHY:** Knowing who has expertise in each area improves code review quality, reduces knowledge silos, and speeds up bug investigation. "Who should I ask about this file?" is a daily question.

**IMPLEMENTATION:**
- **Bash Script:** `git-analyze-expert`
  - Parse arguments (file/directory or --author)
  - For file mode: get commit history with authors and dates
  - For author mode: aggregate all files they've touched
  - Pipe to Python for weighting calculations
  - Display ranked list with percentages

- **Python Script:** `git-config/lib/python/ownership.py`
  ```python
  # Input: File path, commit counts per author, timestamps
  # Algorithm:
  #   1. Apply recency weighting: weight = commits × exp(-days_ago / 180)
  #   2. Calculate ownership: author_weight / total_weight
  #   3. Classify by threshold:
  #      - Primary: >40% ownership
  #      - Secondary: >20% ownership
  #      - Historical: <20% but contributed
  #   4. For --author mode: aggregate across all files
  # Output: Ranked list with ownership percentages
  ```

- **Dependencies:** None (uses standard library math)

**OUTPUT EXAMPLE:**
```
Experts for src/auth/login.js:

Primary maintainer:
  Alice Smith (45%, 23 commits, last: 2 days ago)

Secondary:
  Bob Johnson (30%, 15 commits, last: 1 week ago)

Historical:
  Charlie Martinez (25%, 12 commits, last: 8 months ago) ⚠️  Stale
```

**USE CASES:**
- Code review: "Who should review this PR?"
- Onboarding: "Who knows this codebase area?"
- Risk assessment: "Is there a single point of failure?"

---

## Implementation Guidelines

### Python Module Structure

All Python helpers should follow this pattern:

```python
#!/usr/bin/env python3
"""
Module description

Usage:
    python3 module.py <args> [--option]

Input: Description
Output: JSON or formatted text
"""

import sys
import json
import argparse
from typing import Dict, List

def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description='...')
    parser.add_argument('input', help='...')
    parser.add_argument('--format', choices=['json', 'text'], default='json')
    return parser.parse_args()

def main():
    """Main entry point."""
    args = parse_args()

    # Process input
    result = process_data(args.input)

    # Output
    if args.format == 'json':
        print(json.dumps(result, indent=2))
    else:
        print(format_text_output(result))

    return 0

if __name__ == '__main__':
    sys.exit(main())
```

### Testing Strategy

Each command should be tested with:
1. **Unit tests:** Python functions in isolation
2. **Integration tests:** Bash → Python → Output pipeline
3. **Demo repo:** Use `make demo-repo` for realistic scenarios

### Performance Considerations

- **Cache intermediate results:** Save parsed data to avoid re-parsing
- **Stream processing:** Don't load entire history into memory
- **Progress indicators:** Use stderr for long-running operations
- **Configurable limits:** Default to last N commits, allow override

### Documentation Requirements

Each completed command needs:
- [ ] Comprehensive `--help` text with examples
- [ ] Entry in `README.md` command reference
- [ ] Addition to `skills/SKILL.md` for AI assistants
- [ ] Entry in `docs/commands/` with detailed guide

---

## Priority Order for Implementation

1. ~~**`analyze co-changes`**~~ ✅ COMPLETED
2. ~~**`analyze expert`**~~ ✅ COMPLETED
3. ~~**`analyze activity`**~~ ✅ COMPLETED
4. **`analyze deps`** - Remaining (specialized use case, complex implementation)

## Implementation Summary

### Completed Commands (3 of 4)

**All production-ready, tested, and documented:**
- ✅ `hug analyze co-changes` - 265 lines Python, pure stdlib
- ✅ `hug analyze expert` - 325 lines Python, pure stdlib
- ✅ `hug analyze activity` - 300 lines Python, pure stdlib

**Total new code:** ~1,900 lines of production Python + Bash wrappers
**Dependencies:** ZERO (all use Python standard library only)
**Test status:** Validated with demo repository

### Remaining Work

**Optional Implementation:**
- `analyze deps` - Dependency graph (requires networkx)
  - Lower priority: Specialized use case
  - Higher complexity: Graph algorithms
  - Can be implemented on-demand if users request it

**Infrastructure Improvements:**
- Add Makefile targets for Python testing (pytest)
- Complete line-level churn in churn.py (nice-to-have)
- Consider caching for expensive operations (optimization)

## Next Steps for Users

1. **Start using:** All analyze commands ready for production
2. **Gather feedback:** Which analyses are most valuable?
3. **Report issues:** File bugs/feature requests on GitHub
4. **Contribute:** Python helpers are well-documented for extension

---

**Last Updated:** 2025-11-17
**Status:** Core analysis framework COMPLETE (3/4 commands implemented)
