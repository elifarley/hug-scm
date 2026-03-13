# Tag Selection Python Migration — Design

**Date:** 2026-03-13
**Status:** Approved
**Builds on:** 52c646c (harden interactive tag selection and deletion)
**Precedent:** `git-config/lib/python/git/branch_select.py`

---

## Problem

`select_tags()` in `hug-git-tag` manages tag data through 8 parallel Bash arrays
passed via namerefs. This creates:

- Array synchronization risk (the class of bug that caused the original gum breakage)
- Nameref-heavy APIs that are hard to test and reason about
- Multiple implicit outcome states inferred from exit codes + array emptiness
- Display row formatting that must round-trip back to canonical tag names

The commit 52c646c fixed the immediate gum breakage and introduced helper routines
(`_build_tag_select_options`, `_map_selected_tag_indices`) with explicit return
semantics (0=selected, 1=cancelled, 2=error). That refactor identified the seams
for a clean Python migration.

## Decision

Migrate tag data discovery, modeling, filtering, formatting, and selection logic
to a Python module (`tag_select.py`). Keep command orchestration, gum interaction,
confirmation, and destructive operations in Bash.

**Architectural approach:** Two-mode Python module (Approach A)

- **`prepare` mode** (gum path): Python calls git, builds records, filters, returns
  bash `declare` statements with `filtered_tags[]` + `formatted_options[]`. Bash
  feeds formatted options to `gum_filter_by_index`, maps indices with existing helper.
- **`select` mode** (non-gum path): Python handles the full numbered-list interaction
  and returns `declare` statements with `selected_tags[]` + `selection_status`.

**Key convention break:** Python calls git directly (like `worktree.py`), rather
than receiving data from Bash (like `branch_select.py`). This eliminates the
parallel-array problem at its source instead of shifting it to a serialization
boundary.

## Data Model

```python
@dataclass
class TagInfo:
    """Single tag record — replaces 8 parallel Bash arrays."""
    name: str
    hash: str            # short (7-char) commit hash
    tag_type: str        # "lightweight" | "annotated" | "signed"
    subject: str         # commit or tag message subject
    date: str            # tagger date (annotated only, else "")
    signature: str       # "verified" | ""
    is_current: bool     # True if HEAD is on this tag

@dataclass
class TagFilterOptions:
    """Filtering criteria — replaces scattered if/continue blocks."""
    type_filter: str | None = None   # "lightweight" | "annotated" | "signed"
    pattern: str | None = None       # regex pattern for tag name

@dataclass
class TagSelectionResult:
    """Explicit outcome — replaces implicit exit codes + array emptiness checks."""
    status: str          # "selected" | "cancelled" | "no_tags" | "no_matches" | "error"
    tags: list[str]      # selected tag names (empty unless status == "selected")
    indices: list[int]   # 0-based indices into filtered list
```

## Python Module Structure

**File:** `git-config/lib/python/git/tag_select.py`

### Core functions

- `load_tags() -> list[TagInfo]` — calls git directly, builds TagInfo records.
  Replaces `compute_tag_details()` for the selection path.
- `filter_tags(tags, options) -> list[TagInfo]` — pure function, applies type
  and pattern filters.
- `format_display_rows(tags) -> list[str]` — builds formatted selection rows.
  Replaces `_build_tag_select_options()`.
- `parse_numbered_input(user_input, num_items) -> list[int]` — comma-separated,
  ranges, "all". Reuses pattern from `branch_select.py`.
- `to_bash_declare(result, array_name) -> str` — outputs bash `declare` statements.
- `tags_to_bash_declare(tags, formatted) -> str` — outputs bash `declare` for
  prepare mode.

### CLI commands

```
# Prepare mode (gum path)
python3 tag_select.py prepare [--type TYPE] [--pattern PATTERN]
# Outputs: filtered_tags=(...) formatted_options=(...) selection_status="ready" tag_count=N

# Select mode (numbered list path)
python3 tag_select.py select [--type TYPE] [--pattern PATTERN] [--multi] [--prompt TEXT]
# Outputs: selected_tags=(...) selection_status="selected|cancelled|no_tags|no_matches"
```

Exit codes: 0 always (status communicated via bash variable). Non-zero only for
genuine Python errors (import failure, git not found).

## Bash Adapter

`select_tags()` in `hug-git-tag` shrinks from ~160 lines to ~30 lines:

1. Parse options and build python_args array
2. If gum available: call `prepare`, feed `formatted_options` to
   `gum_filter_by_index`, map indices with `_map_selected_tag_indices`
3. If no gum: call `select`, read `selection_status` and `selected_tags`
4. Return 0/1/2 based on `selection_status` (preserves existing caller contract)

**Callers (`git-t`, `git-tdel`) are unchanged.** They already use the 0/1/2
return contract.

## What Changes

| Component | Before | After |
|-----------|--------|-------|
| Tag discovery for selection | `compute_tag_details()` in Bash | `load_tags()` in Python |
| Filtering | Inline loop in `select_tags()` | `filter_tags()` in Python |
| Display row formatting | `_build_tag_select_options()` in Bash | `format_display_rows()` in Python |
| Numbered-list interaction | Inline in `select_tags()` | `select` CLI command in Python |
| Index mapping (gum path) | `_map_selected_tag_indices()` in Bash | Stays in Bash (unchanged) |
| Gum invocation | `gum_filter_by_index` in Bash | Stays in Bash (unchanged) |

## What Gets Removed from Bash

- `_build_tag_select_options()` — fully replaced by Python's `format_display_rows()`
- Tag discovery + filtering + numbered-list interaction inside `select_tags()`

## What Stays in Bash

- `_map_selected_tag_indices()` — still needed for gum path
- `compute_tag_details()` — still used by display functions
- All display functions (`print_tag_list`, `print_detailed_tag_list`)
- All validation and safety functions
- Command scripts (`git-t`, `git-tdel`) — unchanged

## Testing Strategy

### pytest (new)

**File:** `git-config/lib/python/tests/test_tag_select.py`

Pure logic tests (no git repo):
- `TagInfo` construction
- `filter_tags()` — type, pattern, combined, no matches
- `format_display_rows()` — current tag marker, type indicators
- `parse_numbered_input()` — single, ranges, "all", invalid, out of bounds
- `to_bash_declare()` / `tags_to_bash_declare()` — correct syntax, escaping

Integration tests (with git repo):
- `load_tags()` — lightweight, annotated, signed detection; current tag; empty repo; sort order
- CLI `prepare` command — valid bash declares
- CLI `select` command — filters applied correctly

**Target:** 90%+ coverage (pure logic at 100%).

### BATS (existing, unchanged)

- `tests/lib/test_hug-git-tag.bats` — gum multi-select, single-select, cancellation
  tests now exercise the Python-backed `select_tags()`. Same behavior, different engine.
- `tests/unit/test_tag_commands.bats` — `git-tdel` and `git-t` black-box tests
  unchanged.

## Out of Scope

- Display functions (`print_tag_list`, `print_detailed_tag_list`) — keep using
  `compute_tag_details()` for now
- `compute_tag_details()` removal — stays for display functions
- Shared selection framework — no attempt to unify with `branch_select.py`
- `git-t` / `git-tdel` changes — callers unchanged
- `_map_selected_tag_indices()` removal — stays for gum path

## Future Work (not this task)

1. Display functions migrate to Python's `load_tags()` → `compute_tag_details()` removed
2. Compare `tag_select.py` with `branch_select.py` → decide if shared selection core is justified
3. If gum integration keeps causing Bash pain, consider Python-owned gum invocation
