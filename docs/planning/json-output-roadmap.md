# JSON Output Support in Hug

**Status**: Phase 4b Complete (hybrid GitHub-compatible schema) ✅
**Date**: 2025-11-18
**Updated**: 2025-11-18 (Phase 4b completion - GitHub API compatibility)
**Purpose**: Document JSON support implementation and future roadmap

---

## Design Philosophy: GitHub API Compatibility

**Key Principle**: When implementing JSON output, align with GitHub REST API formats where possible while preserving Hug-specific enhancements.

**Rationale**:
- **Ecosystem Integration**: Tools already built for GitHub API can consume Hug data
- **Developer Familiarity**: Developers know GitHub's schema (commits, trees, refs)
- **Future Extensibility**: GitHub-compatible baseline makes future integrations easier
- **Best of Both**: Adopt GitHub structure + add Hug enhancements (refs, relative dates, pre-parsed fields)

**Hybrid Approach**:
- Use GitHub field names where applicable (`sha` not `hash`, structured `parents`)
- Add Hug conveniences that GitHub doesn't provide (subject/body split, relative timestamps)
- Preserve GitHub compatibility as a subset (tools can ignore Hug extras)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current JSON Support](#current-json-support)
3. [Prioritized Recommendations](#prioritized-recommendations)
4. [Implementation Patterns](#implementation-patterns)
5. [Detailed Command Analysis](#detailed-command-analysis)
6. [Implementation Roadmap](#implementation-roadmap)

---

## Executive Summary

**✅ Phase 4a Complete**: All 4 analysis/stats commands now have JSON support with comprehensive test coverage
**✅ Phase 4b Complete**: `hug ll` now outputs GitHub-compatible JSON with Hug enhancements

**Current State**:
- ✅ 4 core analysis commands with JSON output
- ✅ `hug ll` with hybrid GitHub-compatible schema
- ✅ 18 BATS tests validating JSON structure and validity
- ✅ All JSON outputs validated by Python json.tool
- ✅ jq-compatible output for command-line pipelines
- ✅ GitHub API alignment for commit log data

**Future Opportunity**: 14+ workflow commands would benefit from JSON output (Phase 4c+)

**Primary Use Cases**: CI/CD automation, MCP server integration, IDE tooling, dashboards, GitHub API compatibility

**Key Achievements**:
- All analysis/stats commands use consistent `--json` flag pattern
- **GitHub-Compatible Commit Schema**: Aligns with `GET /repos/:owner/:repo/commits` API
- Python scripts already return structured data (easy JSON serialization)
- Comprehensive test coverage ensures reliability
- Valid JSON output compatible with standard tools (jq, json.tool)

---

## Current JSON Support (Phase 4a ✅)

### Commands with `--json` Flag (Fully Tested)

| Command | Purpose | Implementation | Test Coverage |
|---------|---------|----------------|---------------|
| `hug analyze co-changes` | Files that change together | Python (co_changes.py) | ✅ 6 tests |
| `hug analyze expert` | Code ownership detection | Python (ownership.py) | ✅ 5 tests |
| `hug stats file` | File-level statistics | Python (churn.py) | ✅ 5 tests |
| `hug analyze activity` | Temporal commit patterns | Python (activity.py) | ✅ 6 tests |

**Total**: 4 commands, 18 comprehensive tests, 100% passing

### Additional Commands with JSON (Not in Phase 4a scope)

| Command | Purpose | Implementation | Test Coverage |
|---------|---------|----------------|---------------|
| `hug stats author` | Author contributions | Bash + JSON output | ⏳ Basic |
| `hug stats branch` | Branch statistics | Python | ⏳ Basic |
| `hug analyze deps` | Dependency graphs | Python (deps.py) | ⏳ Existing |

### Pattern Observed

All existing JSON implementations:
- Use `--json` flag (not `--format=json`)
- Delegate to Python scripts OR use bash string formatting
- Return valid JSON to stdout
- Maintain human-readable output as default

---

## Prioritized Recommendations (Phase 4c and Beyond)

### ✅ Phase 4a Complete (Analysis Commands)

The top-priority analysis commands now have full JSON support:
1. ✅ `hug analyze co-changes --json`
2. ✅ `hug analyze expert --json`
3. ✅ `hug stats file --json`
4. ✅ `hug analyze activity --json`

### ✅ Phase 4b Complete (Commit Log - GitHub Compatible)

**`hug ll --json`** - Commit History with GitHub API Alignment

**Status**: ✅ Complete with hybrid schema

**GitHub API Compatibility**: Aligns with `GET /repos/:owner/:repo/commits` response format

**Hybrid Schema** (GitHub-compatible + Hug enhancements):
```json
{
  "commits": [{
    "sha": "80c0d5d...",              // ✅ GitHub compat
    "sha_short": "80c0d5d",           // ⭐ Hug convenience
    "author": {
      "name": "...",
      "email": "...",
      "date": "2025-11-18T20:13:20-03:00",
      "date_relative": "8 minutes ago"  // ⭐ Hug convenience
    },
    "committer": {
      "name": "...",
      "email": "...",
      "date": "2025-11-18T20:15:00-03:00",
      "date_relative": "6 minutes ago"  // ⭐ Hug convenience
    },
    "message": "fix: repair...\n\nWHY: ...",  // ✅ GitHub compat (full text)
    "subject": "fix: repair...",             // ⭐ Hug convenience (pre-parsed)
    "body": "WHY: ...",                      // ⭐ Hug convenience (pre-parsed)
    "tree": {"sha": "e1ae8ec..."},           // ✅ GitHub compat
    "parents": [{"sha": "09f88db..."}],      // ✅ GitHub compat (structured)
    "refs": ["HEAD", "main"],                // ⭐ Hug enhancement (git context)
    "stats": {...}                           // ⭐ Hug enhancement (with --with-stats)
  }],
  "summary": {
    "total_commits": 5,
    "date_range": {"earliest": "...", "latest": "..."}
  }
}
```

**Key Achievements**:
- ✅ Renamed `hash` → `sha` (GitHub standard)
- ✅ Added committer timestamps (author vs committer dates)
- ✅ Structured parents as objects (GitHub format)
- ✅ Full `message` text + parsed `subject`/`body` (hybrid)
- ✅ Tree SHA included (GitHub compat)
- ✅ Preserved Hug enhancements (refs, relative dates, short hash, pre-parsed fields)

**Use Cases Enabled**:
```bash
# Get commit subjects (using Hug convenience field)
hug ll -10 --json | jq '.commits[].subject'

# GitHub-style access
hug ll -10 --json | jq '.commits[].message | split("\n")[0]'

# Find commits with stats
hug ll --json --with-stats | jq '.commits[] | select(.stats.insertions > 100)'

# Extract git context (Hug enhancement)
hug ll --json | jq '.commits[] | select(.refs | contains(["HEAD"]))'
```

### Tier 1: Essential Workflow Commands (Phase 4c - HIGH PRIORITY)

Commands used daily that would provide immediate automation value.

#### 1. `hug sl` / `hug sla` - File Status Listing

**Priority**: ⭐⭐⭐⭐⭐ (Highest)

**Current Output**:
```
S:Add  new-file.txt          (+12 lines)
U:Mod  README.md              (+5 -3 lines)
UnTrck untracked.txt
```

**Proposed JSON Format**:
```json
{
  "repository": "/path/to/repo",
  "timestamp": "2025-11-18T10:30:00Z",
  "summary": {
    "staged": 1,
    "unstaged": 1,
    "untracked": 1,
    "total": 3
  },
  "files": {
    "staged": [
      {
        "path": "new-file.txt",
        "status": "added",
        "additions": 12,
        "deletions": 0
      }
    ],
    "unstaged": [
      {
        "path": "README.md",
        "status": "modified",
        "additions": 5,
        "deletions": 3
      }
    ],
    "untracked": [
      {
        "path": "untracked.txt"
      }
    ]
  }
}
```

**Use Cases**:
- Pre-commit hooks validating changes
- CI/CD pipelines analyzing changeset scope
- IDE status bar integrations
- Automated code review tools

**Implementation Complexity**: 🟢 LOW
- Already uses `list_files_with_status()` from hug-select-files
- Data is already structured internally
- Just needs JSON serialization layer

**Implementation Location**: `git-config/bin/git-statusbase`

---

#### 2. `hug bl` / `hug bll` - Branch Listing

**Priority**: ⭐⭐⭐⭐⭐ (Highest)

**Current Output** (`hug bll`):
```
* main (a1b2c3d) [origin/main: ahead 2] Fix authentication bug
  feature/new-ui (e4f5a6b) [origin/feature/new-ui] Add dashboard
  hotfix/critical (c7d8e9f) Emergency security patch
```

**Proposed JSON Format**:
```json
{
  "repository": "/path/to/repo",
  "current_branch": "main",
  "branches": [
    {
      "name": "main",
      "current": true,
      "hash": "a1b2c3d",
      "upstream": {
        "name": "origin/main",
        "ahead": 2,
        "behind": 0
      },
      "commit": {
        "hash": "a1b2c3d4e5f6",
        "message": "Fix authentication bug",
        "author": "Alice",
        "date": "2025-11-18T09:00:00Z"
      }
    },
    {
      "name": "feature/new-ui",
      "current": false,
      "hash": "e4f5a6b",
      "upstream": {
        "name": "origin/feature/new-ui",
        "ahead": 0,
        "behind": 0
      },
      "commit": {
        "hash": "e4f5a6b7c8d9",
        "message": "Add dashboard",
        "author": "Bob",
        "date": "2025-11-17T14:30:00Z"
      }
    }
  ]
}
```

**Use Cases**:
- Branch management dashboards
- Automated stale branch cleanup scripts
- CI/CD branch selection logic
- Release automation tools

**Implementation Complexity**: 🟢 LOW
- `hug-git-branch` library already provides structured data
- Functions like `get_current_branch()`, `get_branch_list()` exist
- Upstream tracking info available via git commands

**Implementation Location**: `git-config/bin/git-bll` (detailed list)

---

#### 3. `hug s` - Repository Status Summary

**Priority**: ⭐⭐⭐⭐ (Very High)

**Current Output**:
```
🔴 HEAD: b8527cd 🌿copilot/fix-failing-tests-one-more-time...origin/copilot/fix-failing-tests-one-more-time │ 📝 4 files, +41/-2 lines (Unstaged) │ 📦 - (Staged) │ U6 I5029
```

**Proposed JSON Format**:
```json
{
  "repository": "/path/to/repo",
  "branch": {
    "name": "copilot/fix-failing-tests-one-more-time",
    "upstream": "origin/copilot/fix-failing-tests-one-more-time",
    "ahead": 0,
    "behind": 0
  },
  "status": {
    "clean": false,
    "unstaged_count": 4,
    "staged_count": 0,
    "untracked_count": 6,
    "ignored_count": 5029,
    "conflicts": 0
  },
  "files": {
    "unstaged": ["README.md", "2.txt", "3.txt", "4.txt"],
    "staged": [],
    "untracked": ["a", "b", "c", "d", "e", "f"],
    "conflicts": []
  }
}
```

**Use Cases**:
- IDE status bar widgets
- Shell prompt customization (e.g., Starship, Powerlevel10k)
- Monitoring dashboards
- Pre-operation validation scripts

**Implementation Complexity**: 🟢 LOW
- Wraps existing `list_files_with_status()`
- Can leverage same data as `hug sl`
- Simpler than `hug sl` (just counts + file lists)

**Implementation Location**: `git-config/bin/git-s`, `git-config/bin/git-statusbase`

---

### Tier 2: Search & History Commands (MEDIUM-HIGH PRIORITY)

#### 4. `hug lf` - Search Commits by Message

**Priority**: ⭐⭐⭐⭐ (Very High)

**Current Output**:
```
a1b2c3d Fix authentication bug
e4f5a6b Add user authentication
```

**With `--with-files` flag**:
```
a1b2c3d Fix authentication bug
  M src/auth/login.js
  M src/auth/session.js

e4f5a6b Add user authentication
  A src/auth/login.js
```

**Proposed JSON Format**:
```json
{
  "query": "authentication",
  "options": {
    "case_sensitive": false,
    "all_branches": true,
    "with_files": true
  },
  "results": [
    {
      "hash": "a1b2c3d4e5f6",
      "hash_short": "a1b2c3d",
      "author": "Alice",
      "date": "2025-11-18T09:00:00Z",
      "message": "Fix authentication bug",
      "files": [
        {
          "path": "src/auth/login.js",
          "status": "modified"
        },
        {
          "path": "src/auth/session.js",
          "status": "modified"
        }
      ]
    },
    {
      "hash": "e4f5a6b7c8d9",
      "hash_short": "e4f5a6b",
      "author": "Bob",
      "date": "2025-11-15T11:20:00Z",
      "message": "Add user authentication",
      "files": [
        {
          "path": "src/auth/login.js",
          "status": "added"
        }
      ]
    }
  ]
}
```

**Use Cases**:
- Automated release note generation
- Change tracking and impact analysis
- Bug correlation analysis
- Compliance and audit reporting

**Implementation Complexity**: 🟡 MEDIUM
- Uses `git log --grep` internally
- Needs to parse git log output
- `--with-files` adds complexity (--name-status parsing)
- Can use `git log --format` for structured output

**Implementation Location**: `git-config/bin/git-lf`

---

#### 5. `hug lc` - Search Commits by Code Changes

**Priority**: ⭐⭐⭐⭐ (Very High)

**Current Output**:
```
a1b2c3d Refactor getUserById function
c7d8e9f Add getUserById helper
```

**Proposed JSON Format**:
```json
{
  "query": "getUserById",
  "options": {
    "case_sensitive": false,
    "all_branches": false,
    "with_files": true
  },
  "results": [
    {
      "hash": "a1b2c3d4e5f6",
      "hash_short": "a1b2c3d",
      "author": "Alice",
      "date": "2025-11-18T09:00:00Z",
      "message": "Refactor getUserById function",
      "files": [
        {
          "path": "src/api/users.js",
          "status": "modified"
        }
      ]
    }
  ]
}
```

**Use Cases**:
- API change tracking
- Finding when specific code was introduced/removed
- Regression hunting automation
- Code archaeology for debugging

**Implementation Complexity**: 🟡 MEDIUM
- Uses `git log -S` or `git log -G` (pickaxe search)
- Similar to `hug lf` implementation
- Same parsing requirements

**Implementation Location**: `git-config/bin/git-lc`

---

#### 6. `hug l` / `hug ll` / `hug la` - Commit Log

**Priority**: ⭐⭐⭐ (High)

**Current Output** (`hug ll`):
```
a1b2c3d (2025-11-18) Alice    [origin/main: ahead 2] Fix authentication bug
e4f5a6b (2025-11-17) Bob                             Add dashboard component
```

**Proposed JSON Format**:
```json
{
  "commits": [
    {
      "hash": "a1b2c3d4e5f6",
      "hash_short": "a1b2c3d",
      "author": {
        "name": "Alice",
        "email": "alice@example.com"
      },
      "date": "2025-11-18T09:00:00Z",
      "message": {
        "subject": "Fix authentication bug",
        "body": "Detailed explanation..."
      },
      "parents": ["parent_hash"],
      "upstream": {
        "name": "origin/main",
        "ahead": 2,
        "behind": 0
      },
      "stats": {
        "files_changed": 2,
        "insertions": 15,
        "deletions": 8
      }
    }
  ]
}
```

**Use Cases**:
- Custom log viewers and visualizations
- Commit analytics and reporting
- Change frequency analysis
- Team productivity dashboards

**Implementation Complexity**: 🟢 LOW-MEDIUM
- Git 2.31+ supports `--format=json` natively
- For older Git, can use custom format strings
- Already has various log commands (ll, la, lp, etc.)

**Implementation Location**: Multiple (`git-config/bin/git-l*`)

---

### Tier 3: File Analysis Commands (MEDIUM PRIORITY)

#### 7. `hug fcon` - File Contributors

**Priority**: ⭐⭐⭐ (High)

**Current Output**:
```
Contributors to src/auth/login.js:

Alice   (15 commits, 45% ownership)
Bob     (8 commits, 25% ownership)
Charlie (5 commits, 30% ownership)
```

**Proposed JSON Format**:
```json
{
  "file": "src/auth/login.js",
  "contributors": [
    {
      "name": "Alice",
      "email": "alice@example.com",
      "commits": 15,
      "ownership_percent": 45,
      "lines_contributed": 234,
      "first_commit": {
        "hash": "abc123",
        "date": "2024-01-15T10:00:00Z"
      },
      "last_commit": {
        "hash": "def456",
        "date": "2025-11-18T09:00:00Z"
      }
    }
  ]
}
```

**Use Cases**:
- Automated code review assignment
- Expertise routing
- Team ownership documentation
- Onboarding guidance

**Implementation Complexity**: 🟢 LOW
- Simple git log parsing by file
- Can use `git log --follow` for renames
- Similar to existing `git-stats-author` pattern

**Implementation Location**: `git-config/bin/git-fcon`

---

#### 8. `hug fa` - File Author Commits

**Priority**: ⭐⭐⭐ (High)

**Similar to `hug fcon` but filtered by author**

**Implementation Complexity**: 🟢 LOW

**Implementation Location**: `git-config/bin/git-fa`

---

#### 9. `hug fborn` - File Creation Info

**Priority**: ⭐⭐ (Medium)

**Current Output**:
```
src/auth/login.js was born in:
  commit abc123
  Date: 2024-01-15
  Author: Alice
  Message: Add authentication system
```

**Proposed JSON Format**:
```json
{
  "file": "src/auth/login.js",
  "born": {
    "hash": "abc123def456",
    "hash_short": "abc123",
    "date": "2024-01-15T10:00:00Z",
    "author": {
      "name": "Alice",
      "email": "alice@example.com"
    },
    "message": "Add authentication system"
  }
}
```

**Implementation Complexity**: 🟢 LOW

---

### Tier 4: Advanced Analysis (MEDIUM PRIORITY)

#### 10. `hug analyze deps` - Commit Dependencies

**Priority**: ⭐⭐⭐ (High)

**Current Status**: Recently implemented, no JSON support yet

**Proposed JSON Format**:
```json
{
  "analysis_range": {
    "commits": 50,
    "since": "a1b2c3d",
    "until": "HEAD"
  },
  "dependencies": {
    "nodes": [
      {
        "hash": "a1b2c3d",
        "hash_short": "a1b2c3d",
        "message": "Fix authentication bug",
        "author": "Alice",
        "date": "2025-11-18T09:00:00Z"
      }
    ],
    "edges": [
      {
        "from": "a1b2c3d",
        "to": "e4f5a6b",
        "reason": "modifies same file: src/auth/login.js",
        "strength": 1.0
      }
    ]
  },
  "insights": {
    "clusters": [
      {
        "commits": ["a1b2c3d", "e4f5a6b"],
        "description": "Authentication module changes"
      }
    ]
  }
}
```

**Use Cases**:
- Rebase planning and conflict prediction
- Cherry-pick dependency detection
- Commit grouping for PR creation
- Visualizing commit relationships

**Implementation Complexity**: 🟡 MEDIUM
- Python script already exists (`deps.py`)
- Needs JSON serialization added
- Similar to other analyze commands

**Implementation Location**: `git-config/bin/git-analyze-deps`

---

#### 11. `hug h files` - Files in HEAD Commits

**Priority**: ⭐⭐ (Medium)

**Proposed JSON Format**:
```json
{
  "commits": [
    {
      "hash": "a1b2c3d",
      "message": "Fix authentication bug",
      "files": [
        {
          "path": "src/auth/login.js",
          "status": "modified",
          "additions": 10,
          "deletions": 5
        }
      ]
    }
  ]
}
```

**Use Cases**:
- Test scope determination (run tests for changed files)
- Build optimization (rebuild affected modules)
- Impact analysis

**Implementation Complexity**: 🟢 LOW

---

### Tier 5: Additional Commands (LOWER PRIORITY)

#### 12. `hug t` / `hug ta` - Tag Listing

**Priority**: ⭐⭐ (Medium)

**JSON Format**:
```json
{
  "tags": [
    {
      "name": "v1.0.0",
      "hash": "abc123",
      "date": "2025-01-15T10:00:00Z",
      "message": "Release 1.0.0",
      "type": "annotated"
    }
  ]
}
```

**Use Cases**:
- Release automation
- Version tracking
- Changelog generation

**Implementation Complexity**: 🟢 LOW

---

#### 13. `hug log-outgoing` - Commits to be Pushed

**Priority**: ⭐⭐ (Medium)

**JSON Format**: Similar to `hug l`

**Use Cases**:
- Pre-push validation
- CI/CD pipeline triggers
- Release notes preview

**Implementation Complexity**: 🟢 LOW

---

#### 14. Working Directory State Commands

**Priority**: ⭐ (Lower)

Commands like `hug w` status checks, while useful, are less critical for automation as they typically precede operations that users would run manually.

---

## Implementation Patterns

### Pattern 1: Pure Bash JSON Output (Simple Commands)

**Used by**: `git-stats-author`, future `git-s`, `git-bl`

```bash
#!/usr/bin/env bash
# ... standard setup ...

show_help() {
  cat << 'EOF'
USAGE:
    hug command [options]

OPTIONS:
    --json    Output as JSON
    -h        Show this help
EOF
}

# Parse arguments
json_output=false
remaining_args=()

while [ $# -gt 0 ]; do
  case "$1" in
    --json)
      json_output=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      remaining_args+=("$1")
      shift
      ;;
  esac
done

check_git_repo

# Gather data
data=$(git ...)

if $json_output; then
  # JSON output using bash string formatting
  echo "{"
  echo "  \"key\": \"$value\","
  echo "  \"array\": ["
  # ... format array elements ...
  echo "  ]"
  echo "}"
else
  # Human-readable output
  info "Human readable: $data"
fi
```

**Pros**:
- No external dependencies
- Simple implementation
- Full control over output

**Cons**:
- Manual escaping required (quotes, newlines, etc.)
- Error-prone for complex structures
- No validation

**Best for**: Simple, flat JSON structures

---

### Pattern 2: Python Script Delegation (Complex Commands)

**Used by**: All `analyze-*` and most `stats-*` commands

**Bash wrapper** (`git-config/bin/git-command`):
```bash
#!/usr/bin/env bash
# ... standard setup ...

show_help() {
  cat << 'EOF'
OPTIONS:
    --json    Output as JSON
EOF
}

json_output=false
py_args=()

while [ $# -gt 0 ]; do
  case "$1" in
    --json)
      json_output=true
      shift
      ;;
    --since)
      py_args+=("--since=$2")
      shift 2
      ;;
    # ... other args ...
    *)
      py_args+=("$1")
      shift
      ;;
  esac
done

check_git_repo

python_script="$CMD_BASE/../lib/python/script.py"

if [ ! -f "$python_script" ]; then
  error "Analysis not available: $python_script not found"
  exit 1
fi

# Set format flag for Python
if $json_output; then
  py_args+=("--format=json")
else
  py_args+=("--format=text")
fi

# Execute pipeline: git command | python script
git log ... | python3 "$python_script" "${py_args[@]}"
```

**Python script** (`git-config/lib/python/script.py`):
```python
#!/usr/bin/env python3
import sys
import json
import argparse

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--format', choices=['text', 'json'], default='text')
    parser.add_argument('--since', type=str)
    args = parser.parse_args()

    # Read from stdin (git log output)
    data = process_input(sys.stdin)

    if args.format == 'json':
        print(json.dumps(data, indent=2))
    else:
        print_human_readable(data)

if __name__ == '__main__':
    main()
```

**Pros**:
- Robust JSON serialization
- Complex data structures easily handled
- Reusable Python logic
- Easy testing

**Cons**:
- Requires Python dependency
- More files to maintain
- Slightly slower (Python startup)

**Best for**: Complex analysis, nested structures, computations

---

### Pattern 3: Git Native JSON (Where Available)

**Used by**: Future `git l` commands (Git 2.31+)

```bash
#!/usr/bin/env bash
# ... standard setup ...

json_output=false

while [ $# -gt 0 ]; do
  case "$1" in
    --json)
      json_output=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if $json_output; then
  # Use Git's native JSON output (Git 2.31+)
  if git_version_at_least 2.31; then
    exec git log --format=json "$@"
  else
    error "JSON output requires Git 2.31 or later"
    exit 1
  fi
else
  exec git log --oneline "$@"
fi
```

**Pros**:
- Leverages Git's own JSON formatting
- No parsing required
- Guaranteed correct format

**Cons**:
- Only available in newer Git versions
- Limited to what Git supports
- May need fallback for older Git

**Best for**: Log-related commands where Git has native support

---

### Pattern 4: Library Function JSON Support

**For reusable functions in `git-config/lib/`**

```bash
# In git-config/lib/hug-json-utils (NEW FILE)

# JSON-encode a string (escape quotes, newlines, backslashes)
json_escape() {
  local str="$1"
  str="${str//\\/\\\\}"  # Escape backslashes
  str="${str//\"/\\\"}"  # Escape quotes
  str="${str//$'\n'/\\n}"  # Escape newlines
  str="${str//$'\r'/\\r}"  # Escape carriage returns
  str="${str//$'\t'/\\t}"  # Escape tabs
  echo "$str"
}

# Output JSON array from bash array
json_array() {
  local -a items=("$@")
  local first=true

  echo "["
  for item in "${items[@]}"; do
    if $first; then
      first=false
    else
      echo ","
    fi
    printf '  "%s"' "$(json_escape "$item")"
  done
  echo ""
  echo "]"
}

# Output JSON object from key-value pairs
json_object() {
  # Usage: json_object "key1" "value1" "key2" "value2"
  local first=true

  echo "{"
  while [ $# -gt 0 ]; do
    if $first; then
      first=false
    else
      echo ","
    fi
    printf '  "%s": "%s"' "$(json_escape "$1")" "$(json_escape "$2")"
    shift 2
  done
  echo ""
  echo "}"
}
```

**Usage in commands**:
```bash
source "$CMD_BASE/../lib/hug-json-utils"

if $json_output; then
  json_object \
    "branch" "main" \
    "status" "clean" \
    "files" "0"
fi
```

---

## Detailed Command Analysis

### Command: `hug sl` / `hug sla`

**File**: `git-config/bin/git-statusbase`

**Current Implementation**:
- Uses `list_files_with_status()` from `hug-select-files` library
- Already has structured data: status, filename, line stats
- Outputs formatted text with color codes

**Implementation Steps**:

1. Add `--json` flag parsing to `git-statusbase`
2. When `--json` enabled, collect data instead of printing
3. Build JSON structure from `list_files_with_status()` output
4. Use Pattern 1 (Pure Bash) or create JSON utility library

**Data Flow**:
```
git status --porcelain → list_files_with_status() → parse into arrays → JSON output
```

**Estimated Effort**: 2-3 hours
- Simple flag addition
- Data already structured
- Straightforward JSON formatting

---

### Command: `hug b` / `hug bl` / `hug bll`

**File**: `git-config/bin/git-bll` (most detailed)

**Current Implementation**:
- Uses `hug-git-branch` library functions
- Calls `git for-each-ref` for branch info
- Formats with color codes and branch metadata

**Implementation Steps**:

1. Add `--json` flag to `git-bll`
2. Use existing `git for-each-ref` with custom format
3. Parse output into JSON structure
4. Include: name, hash, upstream, ahead/behind, commit message

**Data Source**:
```bash
git for-each-ref --format='%(refname:short)|%(objectname:short)|%(upstream:short)|%(upstream:track)|%(contents:subject)' refs/heads/
```

**Estimated Effort**: 3-4 hours
- Need to parse git output
- Handle upstream tracking info
- Format as nested JSON

---

### Command: `hug lf` - Search by Message

**File**: `git-config/bin/git-lf`

**Current Implementation**:
- Uses `git log --grep=<term>`
- Optional `--with-files` shows file changes
- Outputs oneline format by default

**Implementation Steps**:

1. Add `--json` flag parsing
2. Use `git log` with custom `--format` to extract fields
3. If `--with-files`, parse `--name-status` output
4. Build JSON array of commit objects

**Git Command**:
```bash
git log --grep="$term" --format='%H|%h|%an|%ae|%ai|%s'
# With files:
git log --grep="$term" --format='%H|%h|%an|%ae|%ai|%s' --name-status
```

**Estimated Effort**: 4-5 hours
- Parse git log output
- Handle `--with-files` complexity
- Build nested JSON (commits + files)

---

### Command: `hug analyze deps`

**File**: `git-config/bin/git-analyze-deps`

**Current Implementation**:
- Delegates to `git-config/lib/python/deps.py`
- Python script analyzes commit dependencies
- Outputs human-readable text

**Implementation Steps**:

1. Add `--format=json` flag support in bash wrapper
2. Modify `deps.py` to output JSON
3. Use Python's `json` module for serialization

**Python Changes**:
```python
if args.format == 'json':
    output = {
        'nodes': [{'hash': n.hash, 'message': n.message} for n in nodes],
        'edges': [{'from': e.from, 'to': e.to, 'reason': e.reason} for e in edges]
    }
    print(json.dumps(output, indent=2))
```

**Estimated Effort**: 2-3 hours
- Python already has logic
- Just add JSON serialization
- Following existing pattern

---

## Implementation Roadmap

### Phase 1: Core Workflow Commands (Week 1-2)

**Goal**: Enable JSON for most-used daily commands

1. **`hug s` / `hug sl` / `hug sla`** (Status commands)
   - Estimated: 4 hours
   - Impact: ⭐⭐⭐⭐⭐
   - Dependencies: None
   - Deliverable: JSON status output for CI/CD

2. **`hug b` / `hug bll`** (Branch listing)
   - Estimated: 4 hours
   - Impact: ⭐⭐⭐⭐⭐
   - Dependencies: None
   - Deliverable: JSON branch data for automation

**Milestone 1**: 2 core commands with JSON support

---

### Phase 2: Search & History (Week 3-4)

**Goal**: Enable JSON for search and log commands

3. **`hug lf`** (Search by message)
   - Estimated: 5 hours
   - Impact: ⭐⭐⭐⭐
   - Dependencies: None
   - Deliverable: JSON search results

4. **`hug lc`** (Search by code)
   - Estimated: 5 hours
   - Impact: ⭐⭐⭐⭐
   - Dependencies: None (similar to lf)
   - Deliverable: Code search JSON

5. **`hug l` / `hug ll`** (Basic log)
   - Estimated: 3 hours
   - Impact: ⭐⭐⭐
   - Dependencies: None
   - Deliverable: Commit log JSON

**Milestone 2**: 5 total commands with JSON

---

### Phase 3: File Analysis (Week 5)

**Goal**: JSON for file-centric commands

6. **`hug fcon`** (File contributors)
   - Estimated: 3 hours
   - Impact: ⭐⭐⭐
   - Dependencies: None
   - Deliverable: Contributor data JSON

7. **`hug fa`** (File author commits)
   - Estimated: 2 hours
   - Impact: ⭐⭐⭐
   - Dependencies: Similar to fcon
   - Deliverable: Author commit JSON

8. **`hug fborn`** (File creation)
   - Estimated: 2 hours
   - Impact: ⭐⭐
   - Dependencies: None
   - Deliverable: File origin JSON

**Milestone 3**: 8 total commands with JSON

---

### Phase 4: Advanced Analysis (Week 6)

**Goal**: Complete analysis command JSON support

9. **`hug analyze deps`** (Dependencies)
   - Estimated: 3 hours
   - Impact: ⭐⭐⭐
   - Dependencies: Python script exists
   - Deliverable: Dependency graph JSON

10. **`hug h files`** (HEAD files)
    - Estimated: 2 hours
    - Impact: ⭐⭐
    - Dependencies: None
    - Deliverable: Changed files JSON

**Milestone 4**: 10 total commands with JSON

---

### Phase 5: Polish & Documentation (Week 7)

**Goal**: Consistency, testing, documentation

11. **Create JSON utility library**
    - `git-config/lib/hug-json-utils`
    - Shared escaping and formatting functions
    - Estimated: 4 hours

12. **Add tests for JSON output**
    - BATS tests for each JSON command
    - Validate JSON structure with `jq`
    - Estimated: 8 hours

13. **Documentation**
    - Update command docs with JSON examples
    - Add JSON output guide to docs/
    - Estimated: 4 hours

**Milestone 5**: Production-ready JSON support

---

### Optional: Phase 6+ (Future)

- Tag listing (`hug t`, `hug ta`)
- Outgoing commits (`hug log-outgoing`)
- Working directory commands
- Remote operations

---

## Implementation Guidelines

### General Principles

1. **Backward Compatibility**
   - Default to human-readable output
   - JSON is opt-in via `--json` flag
   - Never break existing output

2. **Consistency**
   - All JSON output should be valid JSON
   - Use consistent field names across commands
   - ISO 8601 dates (`2025-11-18T10:30:00Z`)
   - Include metadata (timestamp, repo path) where relevant

3. **Error Handling**
   - Errors should still be JSON when `--json` enabled
   - Format: `{"error": "message", "code": 1}`
   - Exit codes remain the same

4. **Performance**
   - JSON generation should not significantly slow commands
   - Stream output where possible (for large datasets)
   - Consider pagination for very large results

5. **Testing**
   - Every JSON command needs BATS tests
   - Validate JSON structure with `jq`
   - Test both success and error cases

### JSON Field Naming Conventions

**Use**:
- `snake_case` for field names (not camelCase)
- Plural for arrays (`"files"`, not `"file"`)
- Descriptive names (`"staged_count"`, not `"sc"`)

**Standard fields across commands**:
```json
{
  "repository": "/absolute/path",     // Current repo path
  "timestamp": "2025-11-18T10:30:00Z", // When generated (ISO 8601)
  "command": "hug sl --json",         // Command that generated output
  "version": "1.0.0"                  // Hug version
}
```

**Commit objects** (standardized):
```json
{
  "hash": "a1b2c3d4e5f6...",  // Full hash
  "hash_short": "a1b2c3d",    // Short hash
  "author": {
    "name": "Alice",
    "email": "alice@example.com"
  },
  "date": "2025-11-18T09:00:00Z",
  "message": {
    "subject": "First line",
    "body": "Full message"
  }
}
```

**File objects** (standardized):
```json
{
  "path": "src/file.js",           // Relative to repo root
  "status": "modified",            // added/modified/deleted/renamed
  "additions": 10,                 // Lines added
  "deletions": 5,                  // Lines removed
  "old_path": "old/file.js"        // For renames (optional)
}
```

### Error JSON Format

```json
{
  "error": {
    "message": "Not a git repository",
    "code": "ERR_NOT_GIT_REPO",
    "exit_code": 1
  }
}
```

### Testing Template

```bash
# In tests/unit/test_command.bats

@test "hug command --json: valid JSON output" {
  echo "test" > file.txt
  git add file.txt

  run hug command --json
  assert_success

  # Validate JSON structure
  echo "$output" | jq . >/dev/null
  assert_success "Output should be valid JSON"

  # Check specific fields
  count=$(echo "$output" | jq -r '.staged_count')
  [ "$count" = "1" ]
}

@test "hug command --json: error handling" {
  cd /tmp  # Not a git repo

  run hug command --json
  assert_failure

  # Should still be valid JSON
  echo "$output" | jq . >/dev/null
  assert_success

  # Check error structure
  error=$(echo "$output" | jq -r '.error.message')
  [[ "$error" =~ "Not a git repository" ]]
}
```

---

## Use Case Examples

### Example 1: CI/CD Pre-Commit Validation

**Scenario**: Validate that no large files are staged before committing

```bash
#!/bin/bash
# .git/hooks/pre-commit

# Get staged files with JSON
staged_json=$(hug sl --json)

# Extract staged file paths
files=$(echo "$staged_json" | jq -r '.files.staged[].path')

# Check file sizes
for file in $files; do
  size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file")
  if [ "$size" -gt 1048576 ]; then  # 1MB
    echo "Error: $file is too large ($size bytes)"
    exit 1
  fi
done

echo "✓ All staged files are under 1MB"
```

---

### Example 2: Branch Cleanup Automation

**Scenario**: Delete stale branches merged into main

```bash
#!/bin/bash
# cleanup-merged-branches.sh

# Get all branches as JSON
branches_json=$(hug bll --json)

# Find branches merged into main
merged=$(echo "$branches_json" | jq -r '
  .branches[] |
  select(.upstream.name == "origin/main") |
  select(.upstream.behind == 0) |
  select(.current == false) |
  .name
')

for branch in $merged; do
  echo "Deleting merged branch: $branch"
  git branch -d "$branch"
done
```

---

### Example 3: Release Notes Generation

**Scenario**: Generate release notes from commit messages since last tag

```bash
#!/bin/bash
# generate-release-notes.sh

last_tag=$(git describe --tags --abbrev=0)

# Search for commits with "feat:", "fix:", "breaking:" markers
features=$(hug lf "feat:" --json --all | jq -r '.results[].message')
fixes=$(hug lf "fix:" --json --all | jq -r '.results[].message')
breaking=$(hug lf "breaking:" --json --all | jq -r '.results[].message')

cat > RELEASE_NOTES.md <<EOF
# Release Notes

## New Features
$features

## Bug Fixes
$fixes

## Breaking Changes
$breaking
EOF
```

---

### Example 4: Code Review Assignment

**Scenario**: Automatically assign reviewers based on file expertise

```bash
#!/bin/bash
# assign-reviewers.sh

# Get changed files in current branch
changed_files=$(hug sl --json | jq -r '.files.staged[].path')

declare -A reviewers

# For each changed file, find top contributor
for file in $changed_files; do
  expert=$(hug fcon "$file" --json | jq -r '.contributors[0].name')
  reviewers["$expert"]=1
done

# Output reviewer list
echo "Suggested reviewers:"
for reviewer in "${!reviewers[@]}"; do
  echo "- $reviewer"
done
```

---

### Example 5: IDE Status Bar Integration

**Scenario**: Display git status in IDE status bar

```javascript
// VSCode extension example
import { exec } from 'child_process';

function updateGitStatus() {
  exec('hug s --json', (error, stdout) => {
    if (error) return;

    const status = JSON.parse(stdout);
    const statusText = `
      ↑${status.branch.ahead}
      ↓${status.branch.behind}
      +${status.status.staged_count}
      ~${status.status.unstaged_count}
    `;

    statusBarItem.text = statusText;
  });
}

// Update every 2 seconds
setInterval(updateGitStatus, 2000);
```

---

## Migration Guide for Existing Scripts

If you have existing scripts that parse Hug's text output, migrating to JSON will make them more robust.

### Before (Text Parsing):

```bash
#!/bin/bash
# Fragile: breaks if output format changes

staged_count=$(hug sl | grep "^S:" | wc -l)
unstaged_count=$(hug sl | grep "^U:" | wc -l)
```

### After (JSON Parsing):

```bash
#!/bin/bash
# Robust: schema-based parsing

status=$(hug sl --json)
staged_count=$(echo "$status" | jq -r '.summary.staged')
unstaged_count=$(echo "$status" | jq -r '.summary.unstaged')
```

**Benefits**:
- ✅ No regex needed
- ✅ Handles special characters in filenames
- ✅ Stable schema
- ✅ Easy to extract nested data
- ✅ Type-safe with proper JSON parsers

---

## Performance Considerations

### Benchmarking JSON Output

For each command with JSON support, benchmark:

```bash
# Human-readable output
time hug sl

# JSON output
time hug sl --json

# Acceptable overhead: <10% slower
```

### Optimization Strategies

1. **Avoid redundant git calls**
   - Cache git output when generating both formats
   - Parse once, format twice

2. **Stream large outputs**
   - For commands with many results (git log)
   - Print JSON array incrementally

3. **Use efficient parsers**
   - In Python, use `json` module (C-optimized)
   - In bash, minimize string manipulation

---

## Future Enhancements

### JSON Schema Validation

Provide JSON schemas for each command:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "hug sl output",
  "type": "object",
  "required": ["summary", "files"],
  "properties": {
    "summary": {
      "type": "object",
      "properties": {
        "staged": {"type": "integer"},
        "unstaged": {"type": "integer"}
      }
    }
  }
}
```

Users can validate output:
```bash
hug sl --json | jq -s '.[0]' > output.json
jsonschema -i output.json schema.json
```

### Versioned JSON Output

Support schema versioning:

```bash
hug sl --json --json-version=2
```

Allows breaking changes while maintaining compatibility.

### Machine-Readable Errors

When `--json` enabled, all output (including errors) is JSON:

```bash
$ hug sl --json
{"error": {"message": "Not a git repository", "code": 1}}

$ echo $?
1
```

---

## Testing Strategy

### Unit Tests (BATS)

**Coverage Requirements**:
- ✅ Valid JSON structure (parse with `jq`)
- ✅ Required fields present
- ✅ Correct data types
- ✅ Error cases return JSON errors
- ✅ No output to stderr when `--json` enabled

**Test Template**:
```bash
@test "hug command --json: basic structure" {
  run hug command --json
  assert_success

  # Valid JSON
  echo "$output" | jq . >/dev/null
  assert_success

  # Check required fields
  echo "$output" | jq -e '.repository' >/dev/null
  echo "$output" | jq -e '.timestamp' >/dev/null

  # Check field types
  [ "$(echo "$output" | jq -r '.staged_count | type')" = "number" ]
}
```

### Integration Tests

Test JSON output in real workflows:

```bash
@test "workflow: use JSON to filter files" {
  echo "test" > file.txt
  git add file.txt

  # Extract staged files via JSON
  staged_files=$(hug sl --json | jq -r '.files.staged[].path')

  # Should include our file
  [[ "$staged_files" =~ "file.txt" ]]
}
```

### Schema Validation Tests

```bash
@test "hug sl --json: matches schema" {
  run hug sl --json
  assert_success

  # Validate against schema
  echo "$output" | jq -s '.[0]' | \
    jsonschema -i /dev/stdin docs/schemas/hug-sl.schema.json
  assert_success
}
```

---

## Documentation Requirements

### Command Documentation Updates

For each command with JSON support, update docs to include:

1. **JSON flag in OPTIONS**
   ```
   --json    Output as JSON (machine-readable)
   ```

2. **JSON OUTPUT FORMAT section**
   - Show example JSON output
   - Document all fields
   - Include data types

3. **EXAMPLES with JSON**
   ```
   hug sl --json                        # Status as JSON
   hug sl --json | jq '.summary'        # Extract summary
   hug sl --json | jq -r '.files.staged[].path'  # List staged files
   ```

### New Documentation Files

1. **`docs/json-output-guide.md`**
   - Overview of JSON support
   - Common use cases
   - Integration examples
   - Schema documentation

2. **`docs/schemas/`** (directory)
   - JSON schema files for each command
   - Versioned schemas

3. **Update `README.md`**
   - Mention JSON output support
   - Link to JSON guide
   - Show quick example

---

## Summary

This document outlines a comprehensive plan for adding JSON output support to Hug commands.

**Key Takeaways**:

1. **7 commands already have JSON** (all analysis/stats commands)
2. **15+ commands would benefit from JSON** (status, branch, log, search)
3. **3 implementation patterns** (bash, Python delegation, git native)
4. **Phased rollout** (6 weeks for 10 commands + testing/docs)
5. **Clear use cases** (CI/CD, IDE integration, automation, dashboards)

**Immediate Next Steps**:

1. ✅ Review this document
2. ⏭️ Decide on priority commands to implement first
3. ⏭️ Create `git-config/lib/hug-json-utils` (shared utilities)
4. ⏭️ Implement Phase 1: `hug s`, `hug sl`, `hug b`
5. ⏭️ Add BATS tests for JSON output
6. ⏭️ Update documentation

**Questions to Resolve**:

- Should we create JSON schemas from the start?
- Do we want to support `--json-version` for future compatibility?
- Should JSON be the default for piped output? (e.g., `hug sl | jq`)
- Do we want a global `HUG_OUTPUT=json` environment variable?

---

**Document Version**: 1.0
**Last Updated**: 2025-11-18
**Maintained By**: Hug Development Team
