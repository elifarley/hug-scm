#!/usr/bin/env python3
"""
Hug Git Worktree Select Library — Python implementation

Consolidates worktree selection logic from three Bash scripts (git-wt, git-wtdel,
git-wtsh) into a single module with filtering, formatting, and interactive selection.

Key design decisions:
- Imports WorktreeInfo from worktree.py (DRY — first cross-module import in git/).
  Copying WorktreeInfo here would re-introduce the duplication we're eliminating.
- Reuses worktree.py's parse_worktree_list() for all git interaction — no duplicated
  subprocess code in this module.
- Two CLI modes: 'prepare' (gum path) and 'select' (numbered-list path).
- Single-select only (all three callers select one worktree at a time).

Exit codes: 0 always (status communicated through bash variables).
Non-zero only for genuine Python failures (import error, git not found).
"""

import os
from dataclasses import dataclass

from git.worktree import WorktreeInfo


@dataclass
class WorktreeFilterOptions:
    """Filtering criteria for worktree selection.

    Attributes:
        include_main: If True, include the main repository worktree.
            False for git-wt (switching) and git-wtdel (can't delete main).
            True for git-wtsh (show details of any worktree).
        exclude_current: If True, exclude the worktree the user is currently in.
            True for git-wt (can't switch to self) and git-wtdel (can't delete self).
            False for git-wtsh (may want to show current worktree details).
    """

    include_main: bool = True
    exclude_current: bool = False


@dataclass
class WorktreeSelectionResult:
    """Explicit outcome of a worktree selection operation.

    Using a typed result object instead of exit codes + empty arrays avoids
    the implicit conventions that caused bugs in the Bash implementation.

    Attributes:
        status: One of:
            "selected"      — user picked a worktree; path is populated
            "cancelled"     — user pressed Enter / gave empty input
            "no_worktrees"  — no worktrees match the filters
            "error"         — unexpected failure
        path: Selected worktree path; non-empty only when status == "selected"
    """

    status: str
    path: str


def filter_worktrees(
    worktrees: list[WorktreeInfo],
    options: WorktreeFilterOptions,
    main_path: str,
    current_path: str,
) -> list[WorktreeInfo]:
    """Apply inclusion/exclusion filters to a list of worktrees.

    Pure function — no side effects, no git calls.  The original list is
    never mutated; a new list is always returned.

    Args:
        worktrees: Candidate worktrees to filter.
        options: Filtering criteria (include_main, exclude_current).
        main_path: Absolute path of the main repository worktree.
            Compared against WorktreeInfo.path for the include_main filter.
        current_path: Absolute path of the worktree the user is currently in.
            Compared against WorktreeInfo.path for the exclude_current filter.

    Returns:
        A new list containing only the worktrees that pass all filters.
    """
    result = list(worktrees)  # Snapshot — never mutate the caller's list
    if not options.include_main:
        result = [w for w in result if w.path != main_path]
    if options.exclude_current:
        result = [w for w in result if w.path != current_path]
    return result


def format_display_rows(worktrees: list[WorktreeInfo], current_path: str) -> list[str]:
    """Build formatted selection rows for interactive display.

    Format per row (only non-empty tags appear):
        "[CURRENT] [DIRTY] [LOCKED] branch (commit) → ~/path"

    Design rationale — plain text, no ANSI:
    - gum handles its own terminal styling; injecting ANSI here would conflict
      with gum's colour management and break column alignment.
    - The numbered-list fallback path also consumes these rows, so keeping them
      plain text makes both paths consistent.

    Args:
        worktrees: Ordered list of worktrees to format.
        current_path: Absolute path of the user's current worktree; used to
            emit the [CURRENT] tag.

    Returns:
        A list of plain-text strings, one per input worktree, in the same order.
    """
    home = os.path.expanduser("~")
    rows: list[str] = []
    for wt in worktrees:
        parts: list[str] = []

        # Status tags (order matters for readability: who > state > lock)
        if wt.path == current_path:
            parts.append("[CURRENT]")
        if wt.is_dirty:
            parts.append("[DIRTY]")
        if wt.is_locked:
            parts.append("[LOCKED]")

        # Branch + commit — detached HEAD has an empty branch field
        branch_display = wt.branch if wt.branch else "(detached)"
        parts.append(f"{branch_display} ({wt.commit})")

        # Path: shorten to ~/... when possible to reduce line width
        display_path = wt.path
        if display_path.startswith(home):
            display_path = "~" + display_path[len(home):]
        parts.append(f"\u2192 {display_path}")  # → (U+2192 RIGHTWARDS ARROW)

        rows.append(" ".join(parts))
    return rows


def worktrees_to_bash_declare(
    worktrees: list[WorktreeInfo],
    formatted: list[str],
    status: str = "no_worktrees",
) -> str:
    """Serialise worktrees and display rows to bash declare statements.

    Used by the 'prepare' CLI command (the gum path) so the Bash caller can
    eval the output and obtain parallel arrays ready for gum choose.

    Variables emitted:
        worktree_paths       — bash array of absolute worktree paths
        formatted_options    — bash array of plain-text display rows
        selection_status     — 'ready' if worktrees present, else 'no_worktrees'
                               (or a custom status provided by the caller)
        worktree_count       — integer count of available worktrees

    Design note: when the list is empty we still emit all four variables with
    safe defaults so the Bash caller can branch on selection_status without
    needing to guard against unbound variables.

    Args:
        worktrees: Filtered list of WorktreeInfo objects.
        formatted: Parallel list of display strings (one per worktree).
        status: Override status for empty-list case (default 'no_worktrees').

    Returns:
        Multi-line string of bash declare statements, safe for eval.
    """
    if not worktrees:
        return (
            "declare -a worktree_paths=()\n"
            "declare -a formatted_options=()\n"
            f"selection_status={_bash_escape(status)}\n"
            "worktree_count=0"
        )
    lines: list[str] = []
    paths_arr = " ".join(_bash_escape(w.path) for w in worktrees)
    lines.append(f"declare -a worktree_paths=({paths_arr})")
    opts_arr = " ".join(_bash_escape(f) for f in formatted)
    lines.append(f"declare -a formatted_options=({opts_arr})")
    lines.append("selection_status='ready'")
    lines.append(f"worktree_count={len(worktrees)}")
    return "\n".join(lines)


def selection_to_bash_declare(result: WorktreeSelectionResult) -> str:
    """Serialise a WorktreeSelectionResult to bash declare statements.

    Used by the 'select' CLI command (the numbered-list path) so the Bash
    caller can eval the output and branch on selection_status.

    Variables emitted:
        selected_path      — path of chosen worktree, or empty string
        selection_status   — one of: 'selected', 'cancelled', 'no_worktrees', 'error'

    Args:
        result: Typed selection outcome from interactive selection logic.

    Returns:
        Two-line string of bash assignments, safe for eval.
    """
    lines: list[str] = []
    lines.append(f"selected_path={_bash_escape(result.path)}")
    lines.append(f"selection_status={_bash_escape(result.status)}")
    return "\n".join(lines)


def _bash_escape(s: str) -> str:
    """Escape a string for safe use inside bash declare statements.

    Strategy: wrap in single quotes, using the '\\'' idiom for embedded
    single quotes. Backslashes doubled first so bash doesn't interpret them.

    This is intentionally a module-local copy rather than importing from
    worktree.py. The design explicitly avoids unifying _bash_escape across
    modules at this stage — premature abstraction before the full module is
    implemented would complicate future refactoring.

    Args:
        s: String to escape

    Returns:
        Escaped string wrapped in single quotes, safe for bash eval
    """
    s = s.replace("\\", "\\\\")  # Backslashes first (order matters)
    s = s.replace("'", "'\\''")  # Single quotes using close-escape-reopen idiom
    return f"'{s}'"
