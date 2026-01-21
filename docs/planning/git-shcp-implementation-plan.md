# Plan: Implement git-shcp Command

## Overview

Create `git-shcp` to show cumulative diff and file stats for a commit range, completing the logical pair with `git-shc`.

## Design Rationale

### Why This Command Makes Sense

1. **Logical pairing**: `shc` and `shcp` form a natural pair - one shows cumulative stats (simpler, shorter name), the other adds cumulative patch (more output, longer name)

2. **Hug's core principle**: "Shorter = simpler/safer" - `shcp` being longer than `shc` correctly signals it produces more output

3. **Mnemonic reinforcement**: The `c` in `shc` originally meant "changes" but now elegantly doubles as "cumulative", reinforcing the semantic grouping

4. **Consistent with existing patterns**: Just as `sh` → `shp` adds patch to a single commit view, `shc` → `shcp` adds patch to a cumulative view

### Command Family Structure

```
Single Commit Commands          Cumulative/Range Commands
─────────────────────────       ─────────────────────────
git-sh   (info + stats)         git-shc  (stats only)
git-shp  (info + diff + stats)  git-shcp (diff + stats)  ← NEW
```

### Naming Convention

| Command | Mnemonic | Purpose |
|---------|----------|---------|
| `sh`    | **S**how **H**ead | Single commit info + stats |
| `shp`   | **S**how **H**ead with **P**atch | Single commit info + diff + stats |
| `shc`   | **S**how **H**ead **C**hanges/**C**umulative | Cumulative file stats for range |
| `shcp`  | **S**how **H**ead **C**umulative with **P**atch | Cumulative diff + stats for range |

## Numeric N Convention

Per project rules (`.qoder/rules/numeric-git-commit-locator-convention.md`):

- Empty or `0` → `HEAD` (single commit, default)
- `N` (1-999) → `HEAD~N..HEAD` (cumulative last N commits)
- Values 1000+ → treated as short commit hashes
- Ranges (containing `..`) → pass through unchanged

## Critical Files

| File | Purpose |
|------|---------|
| `git-config/bin/git-shc` | Reference for cumulative range handling |
| `git-config/bin/git-shp` | Reference for diff + stats output |
| `git-config/lib/hug-git-repo` | Contains `resolve_head_target_as_range()` |
| `git-config/lib/hug-git-diff` | Contains `_diff_emoji()` |
| `tests/unit/test_sh.bats` | Existing tests for sh/shp/shc family |

## Implementation Details

### Output Format (diff first, then stats)

```
📄️ 🔀 Cumulative diff:
<git diff output>

📄️ 📊 Cumulative file stats:
<git diff --stat output>
```

### Core Logic (mirroring git-shc pattern)

```bash
# Resolve argument to range
range=$(resolve_head_target_as_range "$arg" "HEAD")

# Detect single commit vs range
if [[ "$range" == *..* ]]; then
    git diff "$range"           # cumulative diff
    git diff --stat "$range"    # cumulative stats
else
    git diff-tree -p -r "$range"   # single commit diff
    git diff-tree --stat -r "$range"  # single commit stats
fi
```

### Flags

- `-h/--help`: Show help (standard)
- No quiet mode (keep it simple)

## Files to Create/Modify

### New File

- `git-config/bin/git-shcp` (~70 lines)

### Test Additions

- `tests/unit/test_sh.bats` - Add ~6 tests for shcp

### Documentation Updates

| File | Update |
|------|--------|
| `README.md` | Add `hug shcp` to "Status & Show" section (line ~531) |
| `.qoder/rules/numeric-git-commit-locator-convention.md` | Add git-shcp to reference commands list |

## Implementation Steps

1. **Create `git-config/bin/git-shcp`**
   - Standard template with library sourcing
   - Help text mirroring git-shc structure  
   - Use `resolve_head_target_as_range()`
   - Single commit vs range detection (same as git-shc)
   - Show diff section with emoji header
   - Show stats section with emoji header

2. **Make executable**: `chmod +x git-config/bin/git-shcp`

3. **Add tests to `tests/unit/test_sh.bats`**
   - Basic output test
   - Numeric N shorthand test (cumulative)
   - Explicit range test
   - Help flag test
   - Invalid commit test
   - Single commit vs range behavior test

4. **Update README.md**
   - Add line after `hug shc`: `hug shcp [N|commit|range] # SHow: Cumulative with Patch (diff + stats)`

5. **Update numeric convention rule**
   - Add `git-shcp` to reference commands in `.qoder/rules/numeric-git-commit-locator-convention.md`

## Verification

```bash
# Run tests
make test-unit TEST_FILE=test_sh.bats TEST_FILTER="shcp"

# Manual verification
hug shcp             # Last commit diff + stats
hug shcp 3           # Cumulative diff + stats for last 3 commits  
hug shcp HEAD~2..HEAD  # Explicit range
hug shcp -h          # Help output
```
