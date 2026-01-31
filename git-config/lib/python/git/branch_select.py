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
import os
import sys
from dataclasses import dataclass

# ANSI color codes (matching hug-terminal)
YELLOW = "\x1b[33m"
BLUE = "\x1b[34m"
GREY = "\x1b[90m"
CYAN = "\x1b[36m"
NC = "\x1b[0m"  # No Color

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
        lines = []

        # Build arrays - use space-separated values for bash arrays
        branches_arr = " ".join(_bash_escape(b) for b in self.branches)
        indices_arr = " ".join(str(i) for i in self.selected_indices)

        lines.append(f"declare -a {array_name}=({branches_arr})")
        lines.append(f"declare -a selected_indices=({indices_arr})")

        return "\n".join(lines)


def _bash_escape(s: str) -> str:
    """Escape string for safe bash declare usage.

    Uses single quotes with inner quote escaping for maximum compatibility.
    Handles: backslashes, single quotes, and most special characters.

    Args:
        s: String to escape

    Returns:
        Escaped string wrapped in single quotes
    """
    s = s.replace("\\", "\\\\")  # Backslashes first (order matters)
    s = s.replace("'", "'\\''")  # Single quotes
    return f"'{s}'"


def _should_use_gum(num_items: int, options: SelectOptions) -> bool:
    """Determine if gum should be used for selection.

    Args:
        num_items: Number of items to select from
        options: SelectOptions configuration

    Returns:
        True if gum should be used, False otherwise
    """
    if not options.use_gum:
        return False

    # Check HUG_DISABLE_GUM environment variable
    if os.environ.get("HUG_DISABLE_GUM", "").lower() == "true":
        return False

    # Check if gum is available
    # In test mode, we can assume gum is available if HUG_TEST_MODE is set
    if os.environ.get("HUG_TEST_MODE", "").lower() == "true":
        return num_items >= MIN_ITEMS_FOR_GUM

    # Check if gum command exists
    try:
        import subprocess

        subprocess.run(
            ["command", "-v", "gum"],
            shell=True,
            check=True,
            capture_output=True,
        )
        has_gum = True
    except (subprocess.CalledProcessError, FileNotFoundError):
        has_gum = False

    if not has_gum:
        return False

    # Check if we have a TTY
    return sys.stdout.isatty() and num_items >= MIN_ITEMS_FOR_GUM


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


def parse_user_input(user_input: str, num_items: int, allow_all: bool = True) -> list[int]:
    """Parse user selection input into 0-based indices.

    Supports:
    - 'a' or 'all' or 'A' or 'ALL' -> select all items
    - Comma-separated numbers: "1,2,3"
    - Ranges: "1-5" (inclusive)
    - Mixed: "1,3-5,7"
    - Empty string -> no selection

    Args:
        user_input: Raw user input string
        num_items: Total number of items available
        allow_all: Whether 'a'/'all' selects all items (default: True)

    Returns:
        List of 0-based indices (sorted, unique, within bounds)

    Examples:
        >>> parse_user_input("1,2,3", 5)
        [0, 1, 2]
        >>> parse_user_input("1-3", 5)
        [0, 1, 2]
        >>> parse_user_input("all", 3)
        [0, 1, 2]
        >>> parse_user_input("1,3-5,7", 10)
        [0, 2, 3, 4, 6]
    """
    user_input = user_input.strip()

    # Handle empty input
    if not user_input:
        return []

    # Handle 'all' or 'a' for select all
    if allow_all and user_input.lower() in ("a", "all"):
        return list(range(num_items))

    indices = set()

    # Split by comma and parse each part
    for part in user_input.split(","):
        part = part.strip()

        # Handle range: "1-5"
        if "-" in part:
            try:
                start_str, end_str = part.split("-", 1)
                start = int(start_str.strip())
                end = int(end_str.strip())

                # Convert to 0-based and ensure inclusive range
                start_idx = max(0, start - 1)
                end_idx = min(num_items - 1, end - 1)

                for i in range(start_idx, end_idx + 1):
                    indices.add(i)
            except ValueError:
                # Invalid range format, skip this part
                continue
        else:
            # Handle single number
            try:
                num = int(part)
                idx = num - 1  # Convert to 0-based

                if 0 <= idx < num_items:
                    indices.add(idx)
            except ValueError:
                # Invalid number, skip this part
                continue

    # Return sorted list
    return sorted(indices)


def validate_indices(indices: list[int], num_items: int) -> list[int]:
    """Validate and filter indices to be within bounds.

    Args:
        indices: List of 0-based indices
        num_items: Total number of items available

    Returns:
        List of valid indices (0 <= idx < num_items)
    """
    return [idx for idx in indices if 0 <= idx < num_items]


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

    # Check if gum should be used
    if _should_use_gum(num_items, options):
        # Gum mode: output formatted options for Bash to handle
        # In this case, we can't actually select from Python
        # Return empty selection and let Bash handle it
        # But we need to signal that gum should be used
        # For now, we'll fall through to numbered list mode
        # since gum interaction must be handled by Bash
        pass

    # Numbered list mode
    # Display placeholder
    print(options.placeholder)
    print()

    # Display numbered list
    for i, option in enumerate(formatted_options):
        if option:  # Skip empty options
            print(f"  {i + 1:2d}: {option}")

    print()

    # Get user selection
    if options.test_selection is not None:
        # Test mode: use pre-selected input
        selection = options.test_selection
    elif "HUG_TEST_NUMBERED_SELECTION" in os.environ:
        # Test environment variable
        selection = os.environ["HUG_TEST_NUMBERED_SELECTION"]
    else:
        # Interactive: read from stdin
        try:
            selection = input("Enter numbers to select (comma-separated, or 'a' for all): ")
        except EOFError:
            # Non-interactive environment
            selection = ""

    # Parse selection
    selected_indices = parse_user_input(selection, num_items, allow_all=True)

    # Validate indices
    selected_indices = validate_indices(selected_indices, num_items)

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
