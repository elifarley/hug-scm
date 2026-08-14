# Design: Make `hug wtl` a Trustworthy Command

**Date:** 2026-05-03
**Status:** Approved

## Problem

`hug wtl` has several usability issues that undermine trust:

1. **stdout is polluted** — header ("Worktrees:"), legend, and listing lines all go to stdout, making `worktrees=$(hug wtl)` capture garbage
2. **No `-q` flag** — can't suppress chatter for script use
3. **Colors in piped output** — ANSI codes survive piping to `grep`/`awk`
4. **`-B` flag doesn't exist** — user tried `hug wtl -B branch` and it silently treated `-B` as a positional branch name
5. **`-s` vs positional confusion** — both filter but with different semantics (exact vs substring, case-sensitive vs insensitive)

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| stdout/stderr split | Listing → stdout, legend → stderr, header removed entirely | Unix convention: data on stdout, chatter on stderr |
| Non-TTY color stripping | Format functions check `-t 1` | Clean output when piped/captured |
| `-q`/`--quiet` | Adopt `parse_common_flags()` | Standard pattern, suppresses legend |
| `-s` vs positional | Keep both, improve docs | Different semantics justify both |
| `-B` flag | Docs-only fix | Positional args are the documented way; clarify in help |

## Changes

### 1. stdout/stderr Discipline

**Current:** Everything on stdout (header + legend + listing).

**New:**
- Header ("Worktrees:") → **removed entirely**
- Legend → **stderr**, prefixed with "Legend: "
- Listing lines → **stdout** (only thing on stdout)
- Error messages → **stderr** (already the case)

**Files changed:**
- `git-config/bin/git-wtl`: Remove line 115 (`printf "Worktrees:"`), redirect `print_worktree_legend` to stderr
- `git-config/lib/hug-git-worktree`: `print_worktree_legend()` printf → stderr, add "Legend: " prefix

### 2. Non-TTY Color Stripping

When stdout is not a TTY, listing lines have no ANSI color codes.

**Implementation:** `format_worktree_indicators()` and `format_worktree_branch_display()` check `[[ -t 1 ]]`. When not a TTY, return plain text without color codes.

**Files changed:**
- `git-config/lib/hug-git-worktree`: Both formatting functions get TTY guard

### 3. Quiet Mode (`-q`/`--quiet`)

Adopt `parse_common_flags()` from `hug-cli-flags`.

**Behavior with `-q`:**
- `HUG_QUIET=T` is set by `parse_common_flags()`
- `print_worktree_legend()` already checks `HUG_QUIET` → legend suppressed
- Colors remain on listing lines (interactive terminal use)
- Consistent with other hug commands

**Files changed:**
- `git-config/bin/git-wtl`: Replace custom arg parsing with `parse_common_flags()` + second pass for `--json` and `-s`

### 4. Help Text Improvements

**Files changed:**
- `git-config/bin/git-wtl`: `show_help()` updated with:
  - Clear contrast between positional args (exact, case-sensitive) and `-s` (substring, case-insensitive)
  - "CAPTURING OUTPUT" section explaining stdout-only listing

### 5. Tests

Add to `tests/unit/test_worktree_list.bats`:

| Test | What it verifies |
|------|-----------------|
| stdout is listing-only | No header or legend in stdout |
| legend on stderr | "Legend:" appears on stderr |
| non-TTY strips colors | Piped output has no ANSI codes |
| `-q` suppresses legend | No legend with `-q` |
| `-q` keeps colors on TTY | Listing still colored with `-q` on TTY |
| error on stderr | "No worktrees found" on stderr |

## Impact on Existing Tests

Tests that assert output includes "Worktrees:" must be updated — the header is removed. Tests asserting legend in stdout must check stderr instead.

## Non-Goals

- Adding `-B`/`--branch` flag to CLI (positional args are the documented way)
- Changing filter semantics (exact vs substring behavior stays as-is)
- Modifying `git-wtll` (can be done as follow-up using same patterns)
