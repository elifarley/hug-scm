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

import argparse
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

# When run as a script (python3 /path/to/worktree_select.py), Python does NOT
# automatically add the package root to sys.path, so `from git.worktree import`
# fails with ModuleNotFoundError.  We fix this by inserting the parent of the
# `git/` package directory — i.e., git-config/lib/python/ — into sys.path
# before the import.  We only do this when running as __main__ (script mode)
# to avoid polluting the path when imported as a library.
# WHY parent of __file__'s parent: __file__ is …/git/worktree_select.py, so
# Path(__file__).parent is …/git/ and Path(__file__).parent.parent is …/python/.
if __name__ == "__main__":
    _pkg_root = str(Path(__file__).resolve().parent.parent)
    if _pkg_root not in sys.path:
        sys.path.insert(0, _pkg_root)

from git.worktree import WorktreeInfo, parse_worktree_list


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


# ---------------------------------------------------------------------------
# Git integration
# ---------------------------------------------------------------------------


def _run_git(args: list[str]) -> str:
    """Run a git command and return stripped stdout; empty string on any failure.

    Failure-safe by design: worktree selection is a UI helper — crashing the
    shell with an unhandled exception would be far worse than silently returning
    an empty result that the caller can handle gracefully.

    Args:
        args: Arguments appended after 'git --no-pager'.  Caller is responsible
              for passing a complete, valid git sub-command.

    Returns:
        Stripped stdout on success, empty string on non-zero exit or exception.
    """
    try:
        result = subprocess.run(
            ["git", "--no-pager"] + args,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            return ""
        return result.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return ""


def _load_worktrees() -> tuple[list[WorktreeInfo], str, str]:
    """Load all worktrees from git and detect the main and current worktree paths.

    Two-step detection:
    1. current_path  — git rev-parse --show-toplevel (the worktree the CWD is in)
    2. main_path     — git rev-parse --git-common-dir
         ".git"   → we ARE in the main repo; main_path == current_path
         "<path>/.git" → strip /.git suffix to get the main worktree root

    parse_worktree_list is called with include_main=True so all worktrees are
    returned; filtering (which worktrees to offer the user) is deferred to
    filter_worktrees() so the caller retains full control.

    Returns:
        (all_worktrees, main_repo_path, current_worktree_path)
        On failure (not in a git repo, timeout, etc.): ([], "", "")
    """
    current_path = _run_git(["rev-parse", "--show-toplevel"])
    if not current_path:
        return [], "", ""

    git_common_dir = _run_git(["rev-parse", "--git-common-dir"])
    if git_common_dir == ".git":
        # Relative ".git" means we're running from the main worktree itself
        main_path = current_path
    elif git_common_dir:
        # Absolute path like /home/user/repo/.git — strip the /.git suffix
        main_path = git_common_dir.removesuffix("/.git")
    else:
        # Fallback: treat current as main (single-worktree repos)
        main_path = current_path

    porcelain = _run_git(["worktree", "list", "--porcelain"])
    if not porcelain:
        return [], main_path, current_path

    worktrees = parse_worktree_list(porcelain, main_path, include_main=True)
    return worktrees, main_path, current_path


# ---------------------------------------------------------------------------
# CLI commands
# ---------------------------------------------------------------------------


def _cmd_prepare(options: WorktreeFilterOptions) -> str:
    """Prepare worktree data for interactive selection via gum.

    Loads all worktrees, applies the given filters, formats display rows, and
    serialises everything to bash declare statements for the caller to eval.
    The Bash side can then pass ``worktree_paths`` and ``formatted_options``
    directly to ``gum choose``.

    When no worktrees survive filtering (including the case where git is not
    available), the output still contains all four variables with safe defaults
    so the Bash caller can branch on ``selection_status`` without guards.

    Args:
        options: Filtering criteria (include_main, exclude_current).

    Returns:
        Multi-line string of bash declare statements, safe for eval.
    """
    worktrees, main_path, current_path = _load_worktrees()
    if not worktrees:
        # Pass through empty lists — worktrees_to_bash_declare handles defaults
        return worktrees_to_bash_declare([], [])

    filtered = filter_worktrees(worktrees, options, main_path, current_path)
    if not filtered:
        return worktrees_to_bash_declare([], [])

    formatted = format_display_rows(filtered, current_path)
    return worktrees_to_bash_declare(filtered, formatted)


def _cmd_select(options: WorktreeFilterOptions, prompt: str) -> str:
    """Interactively select a worktree from a numbered list printed to stderr.

    Stdout is reserved for the bash declare output so the Bash caller can
    capture it cleanly with ``$(...)`` without mixing in UI text.  All
    interactive output (the numbered list and the prompt) goes to stderr.

    Selection outcomes:
    - Valid number   → status='selected', selected_path=<path>
    - Empty input    → status='cancelled' (user pressed Enter to skip)
    - Out-of-range   → status='cancelled' (silent; no second chance by design)
    - Non-numeric    → status='cancelled' (ditto)
    - EOFError       → status='cancelled' (Ctrl-D or piped /dev/null)
    - No worktrees   → status='no_worktrees' (prompt never shown)

    Design note: we intentionally do not retry on invalid input.  Retrying
    creates a loop that complicates the Bash caller and makes tests harder to
    write. Cancellation is cheap — the user can simply re-run the command.

    Args:
        options: Filtering criteria passed to filter_worktrees().
        prompt:  Prompt string shown to the user above the input field.

    Returns:
        Two-line string of bash assignments for selected_path and
        selection_status, safe for eval.
    """
    worktrees, main_path, current_path = _load_worktrees()
    if not worktrees:
        return selection_to_bash_declare(WorktreeSelectionResult(status="no_worktrees", path=""))

    filtered = filter_worktrees(worktrees, options, main_path, current_path)
    if not filtered:
        return selection_to_bash_declare(WorktreeSelectionResult(status="no_worktrees", path=""))

    formatted = format_display_rows(filtered, current_path)

    # Print numbered menu to stderr so stdout remains clean for declare output
    print(prompt, file=sys.stderr)
    for i, row in enumerate(formatted, start=1):
        print(f"  {i}) {row}", file=sys.stderr)

    try:
        raw = input()
    except EOFError:
        return selection_to_bash_declare(WorktreeSelectionResult(status="cancelled", path=""))

    if not raw.strip():
        return selection_to_bash_declare(WorktreeSelectionResult(status="cancelled", path=""))

    try:
        choice = int(raw.strip())
    except ValueError:
        return selection_to_bash_declare(WorktreeSelectionResult(status="cancelled", path=""))

    if choice < 1 or choice > len(filtered):
        return selection_to_bash_declare(WorktreeSelectionResult(status="cancelled", path=""))

    selected = filtered[choice - 1]
    return selection_to_bash_declare(WorktreeSelectionResult(status="selected", path=selected.path))


def main(argv: list[str] | None = None) -> None:
    """CLI entry point for worktree-select.

    Commands:
        prepare   Load and format worktrees for gum interactive picker.
        select    Present a numbered list, read one selection from stdin.

    Common flags (both commands):
        --include-main    Include the main repository worktree in candidates.
        --exclude-current Exclude the worktree the user is currently running in.

    Select-only flags:
        --prompt TEXT     Prompt string shown above the numbered list (stderr).

    All output is printed to stdout so the Bash caller can capture it with
    ``$(...)``.  Errors are written to stderr; exit code 1 on any exception.

    Design: argv parameter allows tests to call main() without touching
    sys.argv, keeping tests hermetic and avoiding global state mutations.
    """
    parser = argparse.ArgumentParser(
        prog="worktree-select",
        description="Worktree selection helper — outputs bash declare statements for eval.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    # Flags shared by both sub-commands are added to a common parent parser
    # so they only have to be defined once (DRY).
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument(
        "--include-main",
        action="store_true",
        default=False,
        help="Include the main repository worktree in the candidate list.",
    )
    common.add_argument(
        "--exclude-current",
        action="store_true",
        default=False,
        help="Exclude the worktree the user is currently in.",
    )

    sub.add_parser("prepare", parents=[common], help="Prepare worktrees for gum picker.")

    sel_parser = sub.add_parser("select", parents=[common], help="Numbered-list selection.")
    sel_parser.add_argument(
        "--prompt",
        default="Select a worktree:",
        help="Prompt shown above the numbered list on stderr.",
    )

    args = parser.parse_args(argv)

    opts = WorktreeFilterOptions(
        include_main=args.include_main,
        exclude_current=args.exclude_current,
    )

    try:
        if args.command == "prepare":
            output = _cmd_prepare(opts)
        else:
            output = _cmd_select(opts, args.prompt)
        print(output)
    except Exception as exc:  # noqa: BLE001  — top-level safety net
        print(f"worktree-select: error: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
