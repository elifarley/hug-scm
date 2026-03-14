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

from dataclasses import dataclass


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
