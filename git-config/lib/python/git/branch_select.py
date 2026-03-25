#!/usr/bin/env python3
"""
Hug Git Branch Select Library - Python implementation

Provides multi-branch selection to replace the Bash multi_select_branches()
function which had 9 parameters and was prone to "unbound variable" bugs.

Supports:
- Parsing comma-separated indices (e.g., "1,2,3")
- Handling 'a' or 'all' for select all
- Supporting ranges like "1-5"
- Formatting multi-select options with colors
- Numbered list display with user input parsing
"""

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

# When run as a script (python3 /path/to/branch_select.py), Python does NOT
# automatically add the package root to sys.path, so `from git.selection_core
# import` fails with ModuleNotFoundError.  We fix this by inserting the parent
# of the `git/` package directory — i.e. git-config/lib/python/ — into sys.path
# before the import.  This guard runs only in __main__ (script mode) to avoid
# polluting sys.path when the module is imported as a library (e.g. in tests
# where pytest already sets PYTHONPATH correctly).
# WHY parent.parent: __file__ is …/git/branch_select.py, so
# Path(__file__).parent is …/git/ and .parent.parent is …/python/.
if __name__ == "__main__":
    _pkg_root = str(Path(__file__).resolve().parent.parent)
    if _pkg_root not in sys.path:
        sys.path.insert(0, _pkg_root)

# All shared primitives live in selection_core — the single source of truth for
# bash escaping, declare-statement generation, input parsing, and ANSI colors.
# Importing them here (rather than re-defining locally) ensures that every
# selection module produces byte-for-byte identical output and reads identical
# environment variables for test overrides.
# This import must come AFTER the sys.path fixup above so that both script mode
# (__main__) and library-import mode (pytest) resolve the package correctly.
from git.selection_core import (
    BLUE,
    CYAN,
    GREEN,
    GREY,
    NC,
    YELLOW,
    BashDeclareBuilder,
    bash_escape,
    get_selection_input,
    parse_numbered_input,
)

# Minimum items for gum usage (matches Bash constant)
MIN_ITEMS_FOR_GUM = 10


@dataclass
class SelectOptions:
    """Configuration options for branch selection.

    Attributes:
        placeholder: Prompt text to display to user
        use_gum: If True, use gum for selection (when available and enough items)
        test_selection: For testing: pre-selected input (simulates user typing)
    """

    placeholder: str = "Select branches"
    use_gum: bool = True
    test_selection: str | None = None


@dataclass
class SelectedBranches:
    """Result of branch selection operation.

    Attributes:
        branches: List of selected branch names
        selected_indices: List of 0-based indices that were selected
    """

    branches: list[str]
    selected_indices: list[int]

    def to_bash_declare(self, array_name: str = "selected_branches") -> str:
        """Format as bash variable declarations.

        Outputs bash 'declare' statements that can be eval'd to set variables:
        - selected_branches (array) - or custom name via array_name
        - selected_indices (array) - 0-based indices

        All strings are properly escaped for safe bash evaluation.

        Args:
            array_name: Name for the result array (default: "selected_branches")

        Returns:
            Bash declare statements as a string
        """
        # BashDeclareBuilder handles escaping and validates variable names eagerly,
        # so invalid array_name values produce a clear error at call time rather
        # than silently emitting broken bash syntax.
        return (
            BashDeclareBuilder()
            .add_array(array_name, self.branches)
            .add_array("selected_indices", [str(i) for i in self.selected_indices])
            .build()
        )


@dataclass
class SingleSelectResult:
    """Result of a single-branch selection operation.

    Models one of three outcomes:
        "selected"    — user picked a branch; branch and index are populated.
        "cancelled"   — user pressed Enter / gave empty or invalid input.
        "no_branches" — no branches were available to select.

    This explicit status field replaces the implicit convention of using
    exit codes or empty-string sentinels, which was the source of subtle
    bugs in the Bash implementation.

    Attributes:
        status:  One of "selected", "cancelled", "no_branches".
        branch:  Selected branch name; empty string unless status == "selected".
        index:   0-based index of the selected branch; -1 if not selected.
    """

    status: str   # "selected" | "cancelled" | "no_branches"
    branch: str   # empty unless status == "selected"
    index: int    # -1 if not selected

    def to_bash_declare(self) -> str:
        """Format as bash variable declarations for `eval` consumption.

        Outputs three bash `declare` statements in this order:
            declare selected_branch='...'   — branch name (empty if not selected)
            declare selection_status='...'  — one of: selected/cancelled/no_branches
            declare -i selected_index=N     — 0-based index (-1 if not selected)

        Variable naming mirrors worktree_select (selected_path → selected_branch)
        so Bash adapters have a consistent shape across all selection modules.

        Returns:
            Three-line string of bash declare statements, safe for eval.
        """
        # BashDeclareBuilder validates variable names eagerly and handles
        # bash_escape() for all string values — no manual escaping needed here.
        b = BashDeclareBuilder()
        b.add_scalar("selected_branch", self.branch)
        b.add_scalar("selection_status", self.status)
        b.add_int("selected_index", self.index)
        return b.build()


def parse_single_input(user_input: str, num_items: int) -> int | None:
    """Parse user input for single-branch selection — strict single-integer parser.

    This intentionally differs from parse_numbered_input (the multi-select parser)
    in two important ways:

    1. STRICT — any input that is not exactly one integer in range returns None.
       Multi-select silently skips bad tokens; single-select treats them as
       cancellation because there is no ambiguity to resolve.

    2. NO RANGE / NO ALL — '1-3', 'a', 'all' are all invalid for single-select.
       They return None, not a partial result.

    This strictness is intentional UX: if the user types '1,2' or '1-3' in a
    single-select prompt, returning the first match silently would be confusing.
    Returning None (→ cancelled) forces them to type exactly one number.

    Args:
        user_input: Raw string typed by the user.
        num_items:  Total number of selectable items (1-based display).

    Returns:
        0-based index within [0, num_items) on success, or None on any failure:
        - empty / whitespace-only input
        - non-integer token (including commas, hyphens, 'all', 'a')
        - out-of-bounds number (0, negative, or > num_items)
    """
    stripped = user_input.strip()

    # Empty input → cancelled (user pressed Enter)
    if not stripped:
        return None

    # Reject any input containing commas or hyphens — these are multi-select
    # syntax.  Accepting them silently (like parse_numbered_input does) would
    # be confusing: "1,2" should not silently select only index 0.
    if "," in stripped or "-" in stripped:
        return None

    # Reject 'a' / 'all' (multi-select "select all" shortcut)
    if stripped.lower() in ("a", "all"):
        return None

    # Require a bare integer — anything else (e.g. '2 3', 'abc') is invalid
    try:
        one_based = int(stripped)
    except ValueError:
        return None

    # Convert from 1-based display index to 0-based internal index
    zero_based = one_based - 1

    # Validate bounds: must be within [0, num_items)
    if zero_based < 0 or zero_based >= num_items:
        return None

    return zero_based


def format_single_select_options(
    branches: list[str],
    hashes: list[str],
    dates: list[str],
    subjects: list[str],
    tracks: list[str],
    current_branch: str,
) -> list[str]:
    """Format branch options for single-select display.

    Each row uses the same color scheme as format_multi_select_options with one
    addition: the current branch receives a green '* ' prefix so the user
    immediately recognises where HEAD is.

    Format per row:
        [GREEN '* ' NC] <branch-name> [YELLOW hash NC] [BLUE date NC]
                        [GREY subject NC] [CYAN [track] NC]

    The '* ' prefix mimics `git branch` output conventions, which most Git users
    already know.  Non-current branches get two plain spaces to keep alignment.

    Color scheme:
        Current marker: GREEN
        Hash:           YELLOW
        Date:           BLUE
        Subject:        GREY  (secondary / lower-information-density)
        Track:          CYAN

    Args:
        branches:       List of branch names.
        hashes:         Parallel list of short commit hashes.
        dates:          Parallel list of commit dates.
        subjects:       Parallel list of commit subjects.
        tracks:         Parallel list of tracking-remote info strings.
        current_branch: Name of the currently checked-out branch (may be empty).
                        A branch whose name exactly matches this string gets the
                        green '* ' prefix.

    Returns:
        List of ANSI-coloured display strings, one per input branch, in the
        same order.  Empty branch names produce empty strings (same as
        format_multi_select_options for consistency).

    Raises:
        ValueError: If input arrays have inconsistent lengths.
    """
    # Validate parallel arrays up front — fail fast with a clear message rather
    # than producing silently misaligned output for the user.
    array_lengths = {
        "branches": len(branches),
        "hashes": len(hashes),
        "dates": len(dates),
        "subjects": len(subjects),
        "tracks": len(tracks),
    }
    if len(set(array_lengths.values())) > 1:
        raise ValueError(
            f"Input arrays have inconsistent lengths: {array_lengths}. "
            "All arrays must be parallel with the same length."
        )

    formatted_options: list[str] = []

    for i, branch in enumerate(branches):
        if not branch:
            # Preserve index alignment — empty branch name → empty row
            formatted_options.append("")
            continue

        # Current-branch marker: green '* ' prefix (matches git branch output)
        # Non-current branches get two plain spaces to keep visual alignment.
        if branch == current_branch:
            prefix = f"{GREEN}* {NC}"
        else:
            prefix = "  "

        parts = [f"{prefix}{branch}"]

        # Optional fields — only emitted when non-empty to avoid blank tokens
        if hashes[i]:
            parts.append(f"{YELLOW}{hashes[i]}{NC}")

        if dates[i]:
            parts.append(f"{BLUE}{dates[i]}{NC}")

        if subjects[i]:
            parts.append(f"{GREY}{subjects[i]}{NC}")

        if tracks[i]:
            parts.append(f"{CYAN}{tracks[i]}{NC}")

        formatted_options.append(" ".join(parts))

    return formatted_options


def format_multi_select_options(
    branches: list[str],
    hashes: list[str],
    dates: list[str],
    subjects: list[str],
    tracks: list[str],
) -> list[str]:
    """Format branch options for multi-select display.

    Each formatted option includes:
    - Branch name
    - Hash (if available) in YELLOW
    - Date (if available) in BLUE
    - Subject (if available) in GREY
    - Tracking info (if available) in CYAN

    Args:
        branches: List of branch names
        hashes: List of commit hashes (parallel to branches)
        dates: List of commit dates (parallel to branches)
        subjects: List of commit subjects (parallel to branches)
        tracks: List of tracking info (parallel to branches)

    Returns:
        List of formatted option strings with ANSI colors

    Raises:
        ValueError: If input arrays have inconsistent lengths
    """
    # Validate input arrays have consistent lengths
    array_lengths = {
        "branches": len(branches),
        "hashes": len(hashes),
        "dates": len(dates),
        "subjects": len(subjects),
        "tracks": len(tracks),
    }

    if len(set(array_lengths.values())) > 1:
        raise ValueError(
            f"Input arrays have inconsistent lengths: {array_lengths}. "
            "All arrays must be parallel with the same length."
        )

    formatted_options = []

    for i, branch in enumerate(branches):
        if not branch:
            # Skip empty branch names
            formatted_options.append("")
            continue

        parts = [branch]

        # Add hash in YELLOW if available
        if i < len(hashes) and hashes[i]:
            parts.append(f"{YELLOW}{hashes[i]}{NC}")

        # Add date in BLUE if available
        if i < len(dates) and dates[i]:
            parts.append(f"{BLUE}{dates[i]}{NC}")

        # Add subject in GREY if available
        if i < len(subjects) and subjects[i]:
            parts.append(f"{GREY}{subjects[i]}{NC}")

        # Add tracking info in CYAN if available
        if i < len(tracks) and tracks[i]:
            parts.append(f"{CYAN}[{tracks[i]}]{NC}")

        formatted_options.append(" ".join(parts))

    return formatted_options


def multi_select_branches(
    branches: list[str],
    hashes: list[str],
    dates: list[str],
    subjects: list[str],
    tracks: list[str],
    options: SelectOptions,
) -> SelectedBranches:
    """Multi-branch selection with formatted display and input parsing.

    This function replaces the Bash multi_select_branches() function which had
    9 parameters and was prone to "unbound variable" bugs.

    Selection modes:
    1. Gum mode: If gum is available and num_items >= MIN_ITEMS_FOR_GUM,
       outputs formatted options and returns empty (Bash handles gum interaction)
    2. Numbered list mode: Displays numbered list and reads user input

    Args:
        branches: List of branch names to select from
        hashes: List of commit hashes (parallel to branches)
        dates: List of commit dates (parallel to branches)
        subjects: List of commit subjects (parallel to branches)
        tracks: List of tracking info (parallel to branches)
        options: SelectOptions configuration

    Returns:
        SelectedBranches dataclass with selected branches and indices

    Raises:
        ValueError: If input arrays have inconsistent lengths
    """
    num_items = len(branches)

    if num_items == 0:
        return SelectedBranches(branches=[], selected_indices=[])

    # Validate input arrays have consistent lengths
    array_lengths = {
        "branches": len(branches),
        "hashes": len(hashes),
        "dates": len(dates),
        "subjects": len(subjects),
        "tracks": len(tracks),
    }

    if len(set(array_lengths.values())) > 1:
        raise ValueError(
            f"Input arrays have inconsistent lengths: {array_lengths}. "
            "All arrays must be parallel with the same length."
        )

    # Format options for display
    formatted_options = format_multi_select_options(
        branches=branches,
        hashes=hashes,
        dates=dates,
        subjects=subjects,
        tracks=tracks,
    )

    # NOTE: Gum integration is intentionally left as a no-op here.
    # The original _should_use_gum() had a latent bug: passing a list as the
    # first argument to subprocess.run(..., shell=True) is undefined behavior
    # (shell=True + list argv ignores all elements after argv[0] on POSIX).
    # The correct approach when gum detection is needed in Python is:
    #   import shutil; shutil.which("gum")
    # For now, gum interaction is handled by the Bash caller, not Python.

    # Numbered list mode
    # Display placeholder
    print(options.placeholder)
    print()

    # Display numbered list
    for i, option in enumerate(formatted_options):
        if option:  # Skip empty options
            print(f"  {i + 1:2d}: {option}")

    print()

    # Get user selection via the canonical three-level precedence chain:
    # test_selection arg > HUG_TEST_NUMBERED_SELECTION env var > stdin.
    # Using get_selection_input() instead of inlining this logic ensures every
    # selection module reads the same env var and handles EOFError identically.
    selection = get_selection_input(test_selection=options.test_selection)

    # parse_numbered_input is the canonical implementation from selection_core,
    # replacing the former local parse_user_input() + validate_indices() pair.
    # validate_indices() is now redundant: parse_numbered_input already clamps
    # and filters indices to [0, num_items), so no second pass is needed.
    selected_indices = parse_numbered_input(selection, num_items, allow_all=True)

    # Convert indices to branch names
    selected_branches = [branches[i] for i in selected_indices if i < len(branches)]

    return SelectedBranches(
        branches=selected_branches,
        selected_indices=selected_indices,
    )


def single_select_branches(
    branches: list[str],
    hashes: list[str],
    dates: list[str],
    subjects: list[str],
    tracks: list[str],
    current_branch: str,
    options: SelectOptions,
) -> SingleSelectResult:
    """Interactively select a single branch from a numbered list.

    This is the single-branch counterpart of multi_select_branches().  It uses:
      - format_single_select_options() for display (green '* ' on current branch)
      - get_selection_input() for the canonical three-level input chain
        (test_selection arg > HUG_TEST_NUMBERED_SELECTION env var > stdin)
      - parse_single_input() for STRICT single-integer validation — any input
        that is not exactly one valid integer returns None (→ cancelled).

    WHY strict parsing: multi-select silently skips bad tokens because there are
    multiple valid answers; for single-select '1,2' should NOT silently pick the
    first match — that would be confusing and hard to debug.  Cancellation is cheap;
    the user simply re-runs and types one number.

    Outcome:
        "selected"    — user typed a valid 1-based number → branch + index set
        "cancelled"   — empty, invalid, or out-of-bounds input
        "no_branches" — branches list was empty; prompt is never shown

    Numbered list is printed to stdout (same as multi_select_branches) so Bash
    callers that capture stdout via $(...) see the menu alongside the declare output.
    This mirrors the existing multi_select_branches() convention; the worktree_select
    module uses stderr to keep stdout clean, but branch_select has always used stdout
    for the numbered list.

    Args:
        branches:       List of branch names.
        hashes:         Parallel list of short commit hashes.
        dates:          Parallel list of commit dates.
        subjects:       Parallel list of commit subjects (may all be empty).
        tracks:         Parallel list of tracking-remote info strings.
        current_branch: Name of the currently checked-out branch; may be empty.
        options:        SelectOptions — only test_selection is consulted here.

    Returns:
        SingleSelectResult with status, branch, and 0-based index.

    Raises:
        ValueError: If input arrays have inconsistent lengths.
    """
    num_items = len(branches)

    # Guard: empty list → no_branches immediately (don't waste time formatting)
    if num_items == 0:
        return SingleSelectResult(status="no_branches", branch="", index=-1)

    # Delegate formatting to the canonical single-select formatter so color
    # choices (GREEN marker for current branch) stay DRY.
    formatted_options = format_single_select_options(
        branches=branches,
        hashes=hashes,
        dates=dates,
        subjects=subjects,
        tracks=tracks,
        current_branch=current_branch,
    )

    # Display the numbered list to stderr, NOT stdout.
    # WHY stderr: the Bash caller captures stdout with $(...) to get only the
    # bash declare statements for eval.  Mixing the menu into stdout would
    # corrupt the declare output and break the eval guard ("starts with declare").
    # This mirrors worktree_select.py's _cmd_select() which uses the same pattern.
    for i, option in enumerate(formatted_options):
        if option:  # skip empty rows (empty branch names)
            print(f"  {i + 1:2d}: {option}", file=sys.stderr)

    print(file=sys.stderr)  # blank line before the prompt

    # Read input via the canonical three-level chain:
    # options.test_selection → HUG_TEST_NUMBERED_SELECTION env var → stdin
    selection = get_selection_input(test_selection=options.test_selection)

    # parse_single_input is strictly single-integer — it returns None for empty,
    # non-integer, comma-separated, range syntax, and out-of-bounds input.
    idx = parse_single_input(selection, num_items)

    if idx is None:
        return SingleSelectResult(status="cancelled", branch="", index=-1)

    return SingleSelectResult(status="selected", branch=branches[idx], index=idx)


def format_options_for_gum(
    branches: list[str],
    hashes: list[str],
    dates: list[str],
    subjects: list[str],
    tracks: list[str],
) -> list[str]:
    """Format options for gum filter display.

    This is a separate command that outputs formatted options
    for Bash to use with gum_filter_by_index.

    Args:
        branches: List of branch names
        hashes: List of commit hashes (parallel to branches)
        dates: List of commit dates (parallel to branches)
        subjects: List of commit subjects (parallel to branches)
        tracks: List of tracking info (parallel to branches)

    Returns:
        List of formatted option strings (output one per line for Bash)
    """
    return format_multi_select_options(branches, hashes, dates, subjects, tracks)


def main():
    """CLI entry point for bash wrapper calls.

    Usage:
        python3 branch_select.py select [options]
        python3 branch_select.py format-options [options]
        python3 branch_select.py prepare [options]
        python3 branch_select.py single-select [options]

    Commands:
        select           Run interactive multi-branch selection (numbered list mode)
        format-options   Output formatted options for gum (one per line)
        prepare          Format options for gum path (outputs bash declare statements)
        single-select    Run interactive single-branch selection

    Options (all commands):
        --branches LIST          Space-separated branch names
        --hashes LIST            Space-separated commit hashes
        --dates LIST             Space-separated commit dates
        --subjects LIST          Space-separated commit subjects
        --tracks LIST            Space-separated tracking info
        --current-branch NAME    Name of current branch (for '* ' marker)

    Multi-select / format-options options:
        --placeholder STR    Prompt text (default: "Select branches")
        --array-name NAME    Name for result array (default: "selected_branches")
        --no-gum             Disable gum usage

    Single-select / prepare options:
        --selection STR      Pre-selected input for testing (simulates user typing)

    Output:
        select        → bash array declare statements (selected_branches, selected_indices)
        format-options→ formatted option lines (one per stdout line, for gum)
        prepare       → bash declare: formatted_options[], selection_status, branch_count
        single-select → bash declare: selected_branch, selection_status, selected_index

    Exit code: 0 on success, 1 on error.
    """
    parser = argparse.ArgumentParser(description="Multi-branch selection for Hug SCM")
    parser.add_argument(
        "command",
        choices=["select", "format-options", "prepare", "single-select"],
        help="Command to run",
    )
    parser.add_argument("--branches", required=True, help="Space-separated branch names")
    parser.add_argument("--hashes", default="", help="Space-separated commit hashes")
    parser.add_argument("--dates", default="", help="Space-separated commit dates")
    parser.add_argument("--subjects", default="", help="Space-separated commit subjects")
    parser.add_argument("--tracks", default="", help="Space-separated tracking info")
    parser.add_argument("--placeholder", default="Select branches", help="Prompt text for user")
    parser.add_argument(
        "--selection",
        default=None,
        help="Pre-selected input for testing (simulates user typing)",
    )
    parser.add_argument(
        "--array-name",
        default="selected_branches",
        help="Name for result array (default: selected_branches)",
    )
    parser.add_argument(
        "--no-gum",
        action="store_true",
        help="Disable gum usage",
    )
    parser.add_argument(
        "--current-branch",
        default="",
        help="Name of currently checked-out branch (used for the '* ' marker in single-select and prepare)",
    )

    args = parser.parse_args()

    try:
        # Parse space-separated values into lists
        branches = args.branches.split() if args.branches else []
        hashes = args.hashes.split() if args.hashes else []
        dates = args.dates.split() if args.dates else []
        subjects = args.subjects.split() if args.subjects else []
        tracks = args.tracks.split() if args.tracks else []

        # Pad shorter arrays with empty strings to match branches array length.
        # This allows callers to omit trailing empty fields without causing
        # "inconsistent lengths" errors in the formatting functions.
        max_len = max(len(branches), len(hashes), len(dates), len(subjects), len(tracks))

        def pad_array(arr, target_len):
            return arr + [""] * (target_len - len(arr))

        branches = pad_array(branches, max_len)
        hashes = pad_array(hashes, max_len)
        dates = pad_array(dates, max_len)
        subjects = pad_array(subjects, max_len)
        tracks = pad_array(tracks, max_len)

        if args.command == "format-options":
            # Output formatted options for gum (one per line).
            # The Bash caller passes these lines directly to gum_filter_by_index.
            formatted = format_options_for_gum(
                branches=branches,
                hashes=hashes,
                dates=dates,
                subjects=subjects,
                tracks=tracks,
            )
            for option in formatted:
                if option:  # Skip empty options
                    print(option)
            return

        if args.command == "prepare":
            # Prepare branch data for the gum interactive picker path.
            # Outputs bash declare statements so the Bash caller can eval the
            # output and pass formatted_options directly to gum choose.
            # When the branch list is empty we still emit all variables with safe
            # defaults so the caller can branch on selection_status without guards.
            num_branches = len(branches)
            if num_branches == 0:
                print(
                    BashDeclareBuilder()
                    .add_array("formatted_options", [])
                    .add_scalar("selection_status", "no_branches")
                    .add_int("branch_count", 0)
                    .build()
                )
                return

            formatted = format_single_select_options(
                branches=branches,
                hashes=hashes,
                dates=dates,
                subjects=subjects,
                tracks=tracks,
                current_branch=args.current_branch,
            )
            print(
                BashDeclareBuilder()
                .add_array("formatted_options", [opt for opt in formatted if opt])
                .add_scalar("selection_status", "ready")
                .add_int("branch_count", num_branches)
                .build()
            )
            return

        if args.command == "single-select":
            # Single-branch selection: display numbered list, read one number,
            # output a SingleSelectResult as bash declare statements.
            options = SelectOptions(
                placeholder=args.placeholder,
                use_gum=not args.no_gum,
                test_selection=args.selection,
            )
            result = single_select_branches(
                branches=branches,
                hashes=hashes,
                dates=dates,
                subjects=subjects,
                tracks=tracks,
                current_branch=args.current_branch,
                options=options,
            )
            print(result.to_bash_declare())
            return

        # Command: select (multi-branch)
        options = SelectOptions(
            placeholder=args.placeholder,
            use_gum=not args.no_gum,
            test_selection=args.selection,
        )

        # Run multi-branch selection
        result = multi_select_branches(
            branches=branches,
            hashes=hashes,
            dates=dates,
            subjects=subjects,
            tracks=tracks,
            options=options,
        )

        # Output bash declarations
        print(result.to_bash_declare(array_name=args.array_name))

    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
