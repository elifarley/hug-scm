# Worktree Indicators: Fixed-Column Single-Character Design

**Date:** 2026-05-03
**Status:** Approved

## Problem

Worktree listing commands (`git-wtl`, `git-wtll`, `git-wt`, `git-wtsh`) display
status indicators as bracketed words like `[CURRENT]`, `[DIRTY]`, `[LOCKED]`. These
are verbose, variable-width, and make vertical scanning difficult when multiple
worktrees are listed.

Additionally, the indicator-building code is duplicated across **7 Bash locations**
and **1 Python location**, violating DRY and making changes error-prone.

## Design

### Indicator Character Map

Four fixed columns, always present, using single characters:

| Column | Active Char | Color    | Meaning                     | Inactive |
|--------|-------------|----------|-----------------------------|----------|
| 1      | `*`         | Green    | Current worktree            | `.`      |
| 2      | `+`         | Yellow   | Dirty (uncommitted changes) | `.`      |
| 3      | `#`         | Red      | Locked                      | `.`      |
| 4      | `@`         | Cyan     | Detached HEAD               | `.`      |

Inactive `.` uses dim styling for subtlety.

**Rationale for characters:**
- `*` — star = "you are here" (universal convention)
- `+` — plus = changes added on top
- `#` — hash = blocked/restricted
- `@` — "at" = pointing at a specific commit (mirrors git's `HEAD@{1}` syntax)

### Output Examples

```
*+.. main           (abc1234) ~/repo
.... feature-1       (def5678) ~/repo/.WT.feature-1
..#. hotfix-2        (123abcd) ~/repo/.WT.hotfix-2
*+.#. broken-wt      (def4567) ~/repo/.WT.broken-wt
...@ detached-wt     (abc9999) ~/repo/.WT.detached-wt
```

### Architecture Decision: Keep Bash/Python Boundary

The project follows "Python for computation, Bash for display." This design
respects that boundary:

- **Bash** owns ANSI-colored indicator formatting (uses native `$GREEN`, `$YELLOW`,
  `$RED`, `$CYAN` variables)
- **Python** owns plain-text indicator formatting (for gum interactive menus)

Both implement the same character mapping but through their respective idioms.

### Implementation

#### Bash: `format_worktree_indicators()` in `hug-git-worktree`

```bash
format_worktree_indicators() {
  local is_current="${1:-false}"
  local is_dirty="${2:-false}"
  local is_locked="${3:-false}"
  local is_detached="${4:-false}"

  local DIM='\e[2m'
  local i1 i2 i3 i4

  if [[ "$is_current" == "true" ]]; then i1="${GREEN}*${NC}"; else i1="${DIM}.${NC}"; fi
  if [[ "$is_dirty" == "true" ]];   then i2="${YELLOW}+${NC}"; else i2="${DIM}.${NC}"; fi
  if [[ "$is_locked" == "true" ]];  then i3="${RED}#${NC}";    else i3="${DIM}.${NC}"; fi
  if [[ "$is_detached" == "true" ]]; then i4="${CYAN}@${NC}";  else i4="${DIM}.${NC}"; fi

  printf '%s%s%s%s' "$i1" "$i2" "$i3" "$i4"
}
```

#### Python: `format_indicators()` in `worktree.py`

```python
def format_indicators(is_current: bool, is_dirty: bool,
                      is_locked: bool, is_detached: bool) -> str:
    chars = [
        "*" if is_current else ".",
        "+" if is_dirty else ".",
        "#" if is_locked else ".",
        "@" if is_detached else ".",
    ]
    return "".join(chars)
```

#### Call Sites to Update (7 Bash + 1 Python)

1. `git-config/lib/hug-git-worktree` — `show_worktree_summary()` (line ~891)
2. `git-config/lib/hug-git-worktree` — `format_worktree_line()` (line ~930)
3. `git-config/lib/hug-git-worktree` — `format_worktree_long_line()` (line ~955)
4. `git-config/bin/git-wtl` — filtered loop (line ~127)
5. `git-config/bin/git-wtl` — unfiltered loop (line ~146)
6. `git-config/bin/git-wt` — summary mode (line ~121)
7. `git-config/bin/git-wtsh` — show details (line ~237)
8. `git-config/lib/python/git/worktree_select.py` — `format_display_rows()` (line ~139)

### Scope Changes

- `[DETACHED]` indicator (previously `git-wtsh`-only) now appears in ALL listing
  commands as the 4th column (`@` character)
- `git-wtl`'s two inline indicator copies are eliminated by delegating to the
  library function

### Test Changes

- **Python tests** (`test_worktree_select.py`): Update indicator assertions from
  `[CURRENT]`/`[DIRTY]`/`[LOCKED]` to `*`/`+`/`#`/`@`/`.`
- **BATS tests** (`test_worktree_list.bats`): Update assertions similarly
- **New Python test**: `test_format_indicators()` covering all 16 boolean
  combinations

### Legend / Help Text

Every worktree listing command that shows the indicators must include a legend
so users can decode the symbols. Two mechanisms:

#### 1. `--help` flag

Each command's help text includes an indicator reference:

```
Indicators:
  *  current worktree
  +  dirty (uncommitted changes)
  #  locked
  @  detached HEAD
  .  (inactive)
```

#### 2. Inline legend in listing output

The first time a user runs a worktree listing command (or when `--verbose` is
used), a one-line legend appears above the worktree rows:

```
  * current  + dirty  # locked  @ detached

  *+.. main           (abc1234) ~/repo
  .... feature-1       (def5678) ~/repo/.WT.feature-1
```

This legend is printed by the Bash library function
`print_worktree_legend()` in `hug-git-worktree`, so all commands share a
single implementation. It uses the same colors as the active indicators
for immediate visual association.

The legend respects `HUG_QUIET` — suppressed when quiet mode is active.
It is also suppressed when output is piped (non-TTY) or when `--json` is used.

### Commands Affected

| Command        | Change                                        |
|----------------|-----------------------------------------------|
| `git-wtl`      | New indicator format, use library function    |
| `git-wtll`     | New indicator format via library function     |
| `git-wt`       | New indicator format in summary + interactive |
| `git-wtsh`     | New indicator format, detached now shared     |
| `git-wtwp`     | Inherits via `git-wtl` delegation             |

## Task IDs

- Task #1: Explore project context (completed)
- Task #2: Clarifying questions (completed)
- Task #3: Propose approaches (completed)
- Task #4: Present design (completed)
- Task #5: Write design doc (this file)
- Task #6: Transition to implementation planning
