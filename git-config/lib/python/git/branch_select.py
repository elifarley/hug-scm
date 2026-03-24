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

    Commands:
        select           Run interactive selection (numbered list mode)
        format-options   Output formatted options for gum (one per line)

    Options:
        --branches LIST      Space-separated branch names
        --hashes LIST        Space-separated commit hashes
        --dates LIST         Space-separated commit dates
        --subjects LIST      Space-separated commit subjects
        --tracks LIST        Space-separated tracking info
        --placeholder STR    Prompt text (default: "Select branches")
        --selection STR      Pre-selected input for testing (simulates user typing)
        --array-name NAME    Name for result array (default: "selected_branches")
        --no-gum             Disable gum usage

    Outputs bash variable declarations for 'select' command.
    Outputs formatted options (one per line) for 'format-options' command.
    Returns exit code 1 on error.
    """
    parser = argparse.ArgumentParser(description="Multi-branch selection for Hug SCM")
    parser.add_argument(
        "command",
        choices=["select", "format-options"],
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

    args = parser.parse_args()

    try:
        # Parse space-separated values into lists
        branches = args.branches.split() if args.branches else []
        hashes = args.hashes.split() if args.hashes else []
        dates = args.dates.split() if args.dates else []
        subjects = args.subjects.split() if args.subjects else []
        tracks = args.tracks.split() if args.tracks else []

        # Pad shorter arrays with empty strings to match branches array length
        max_len = max(len(branches), len(hashes), len(dates), len(subjects), len(tracks))

        def pad_array(arr, target_len):
            return arr + [""] * (target_len - len(arr))

        branches = pad_array(branches, max_len)
        hashes = pad_array(hashes, max_len)
        dates = pad_array(dates, max_len)
        subjects = pad_array(subjects, max_len)
        tracks = pad_array(tracks, max_len)

        if args.command == "format-options":
            # Output formatted options for gum (one per line)
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

        # Command: select
        # Build options
        options = SelectOptions(
            placeholder=args.placeholder,
            use_gum=not args.no_gum,
            test_selection=args.selection,
        )

        # Run selection
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
