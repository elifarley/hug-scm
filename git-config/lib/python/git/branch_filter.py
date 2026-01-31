#!/usr/bin/env python3
"""
Hug Git Branch Filter Library - Python implementation

Provides type-safe branch filtering to eliminate "unbound variable" bugs
that plagued the Bash implementation with 14 positional parameters.

Replaces hug-git-branch filter_branches() function.
"""

import argparse
import sys
from dataclasses import dataclass


@dataclass
class FilterOptions:
    """Configuration options for branch filtering.

    Attributes:
        exclude_current: If True, exclude the current branch from results
        exclude_backup: If True, exclude hug-backup/* branches
        custom_filter: Optional name of custom filter function (not yet implemented)
    """

    exclude_current: bool = False
    exclude_backup: bool = True
    custom_filter: str | None = None


@dataclass
class FilteredBranches:
    """Result of branch filtering operation.

    All arrays maintain consistent lengths (parallel arrays).
    """

    branches: list[str]
    hashes: list[str]
    subjects: list[str]
    tracks: list[str]
    dates: list[str]

    def to_bash_declare(self) -> str:
        """Format as bash variable declarations.

        Outputs bash 'declare' statements that can be eval'd to set variables:
        - filtered_branches (array)
        - filtered_hashes (array)
        - filtered_subjects (array)
        - filtered_tracks (array)
        - filtered_dates (array)

        All strings are properly escaped for safe bash evaluation.
        Arrays maintain consistent lengths.
        """
        lines = []

        # Build arrays - use space-separated values for bash arrays
        branches_arr = " ".join(_bash_escape(b) for b in self.branches)
        hashes_arr = " ".join(_bash_escape(h) for h in self.hashes)
        subjects_arr = " ".join(_bash_escape(s) for s in self.subjects)
        tracks_arr = " ".join(_bash_escape(t) for t in self.tracks)
        dates_arr = " ".join(_bash_escape(d) for d in self.dates)

        lines.append(f"declare -a filtered_branches=({branches_arr})")
        lines.append(f"declare -a filtered_hashes=({hashes_arr})")
        lines.append(f"declare -a filtered_subjects=({subjects_arr})")
        lines.append(f"declare -a filtered_tracks=({tracks_arr})")
        lines.append(f"declare -a filtered_dates=({dates_arr})")

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


def filter_branches(
    branches: list[str],
    hashes: list[str],
    subjects: list[str],
    tracks: list[str],
    dates: list[str],
    current_branch: str,
    options: FilterOptions,
) -> FilteredBranches:
    """Filter branch lists based on criteria.

    This function replaces the Bash filter_branches() function which had
    14 positional parameters and was prone to "unbound variable" bugs.

    Args:
        branches: List of branch names to filter
        hashes: List of commit hashes (parallel to branches)
        subjects: List of commit subjects (parallel to branches)
        tracks: List of tracking info strings (parallel to branches)
        dates: List of commit dates (parallel to branches)
        current_branch: Name of the current branch
        options: FilterOptions configuration

    Returns:
        FilteredBranches dataclass with filtered arrays

    Raises:
        ValueError: If input arrays have inconsistent lengths

    Example:
        >>> options = FilterOptions(exclude_current=True, exclude_backup=True)
        >>> result = filter_branches(
        ...     ["main", "feature", "hug-backups/tmp"],
        ...     ["abc123", "def456", "ghi789"],
        ...     ["Init", "Feature", "Backup"],
        ...     ["[origin/main]", "", ""],
        ...     ["2026-01-30", "2026-01-31", "2026-01-31"],
        ...     current_branch="main",
        ...     options=options
        ... )
        >>> result.branches
        ['feature']
    """
    # Validate input arrays have consistent lengths
    array_lengths = {
        "branches": len(branches),
        "hashes": len(hashes),
        "subjects": len(subjects),
        "tracks": len(tracks),
        "dates": len(dates),
    }

    if len(set(array_lengths.values())) > 1:
        raise ValueError(
            f"Input arrays have inconsistent lengths: {array_lengths}. "
            "All arrays must be parallel with the same length."
        )

    filtered_branches = []
    filtered_hashes = []
    filtered_subjects = []
    filtered_tracks = []
    filtered_dates = []

    for i, branch in enumerate(branches):
        # Skip current branch if exclusion enabled
        if options.exclude_current and branch == current_branch:
            continue

        # Skip backup branches if exclusion enabled
        if options.exclude_backup and branch.startswith("hug-backups/"):
            continue

        # Custom filter function support (placeholder for future implementation)
        # In Bash, this would call a user-provided function
        # For now, we skip this feature as it's rarely used
        if options.custom_filter:
            # TODO: Implement custom filter function support
            # This would require a way to call back into Bash or
            # implement the filter logic in Python
            pass

        # Branch passed all filters, add to output
        filtered_branches.append(branch)
        filtered_hashes.append(hashes[i])
        filtered_subjects.append(subjects[i])
        filtered_tracks.append(tracks[i])
        filtered_dates.append(dates[i] if i < len(dates) else "")

    return FilteredBranches(
        branches=filtered_branches,
        hashes=filtered_hashes,
        subjects=filtered_subjects,
        tracks=filtered_tracks,
        dates=filtered_dates,
    )


def main():
    """CLI entry point for bash wrapper calls.

    Usage:
        python3 branch_filter.py filter [options]

    Options:
        --branches LIST    Space-separated branch names
        --hashes LIST      Space-separated commit hashes
        --subjects LIST    Space-separated commit subjects
        --tracks LIST      Space-separated tracking info
        --dates LIST       Space-separated commit dates
        --current-branch STR  Current branch name
        --exclude-current  Exclude current branch from results
        --exclude-backup   Exclude backup branches (default: true)
        --include-backup   Include backup branches
        --no-exclude-backup

    Outputs bash variable declarations by default.
    Returns exit code 1 on error.
    """
    parser = argparse.ArgumentParser(description="Filter git branches for Hug SCM")
    parser.add_argument(
        "command", choices=["filter"], help="Command to run (currently only 'filter' supported)"
    )
    parser.add_argument("--branches", required=True, help="Space-separated branch names")
    parser.add_argument("--hashes", required=True, help="Space-separated commit hashes")
    parser.add_argument("--subjects", default="", help="Space-separated commit subjects")
    parser.add_argument("--tracks", default="", help="Space-separated tracking info")
    parser.add_argument("--dates", default="", help="Space-separated commit dates")
    parser.add_argument("--current-branch", default="", help="Current branch name")
    parser.add_argument(
        "--exclude-current", action="store_true", help="Exclude current branch from results"
    )
    parser.add_argument(
        "--exclude-backup",
        action="store_true",
        default=True,
        help="Exclude backup branches (default: enabled)",
    )
    parser.add_argument(
        "--include-backup",
        action="store_true",
        help="Include backup branches (overrides --exclude-backup)",
    )

    args = parser.parse_args()

    try:
        # Parse space-separated values into lists
        branches = args.branches.split() if args.branches else []
        hashes = args.hashes.split() if args.hashes else []
        subjects = args.subjects.split() if args.subjects else []
        tracks = args.tracks.split() if args.tracks else []
        dates = args.dates.split() if args.dates else []

        # Pad shorter arrays with empty strings to match branches array length
        # This handles cases where CLI doesn't provide all arrays
        max_len = max(len(branches), len(hashes), len(subjects), len(tracks), len(dates))

        def pad_array(arr, target_len):
            return arr + [""] * (target_len - len(arr))

        branches = pad_array(branches, max_len)
        hashes = pad_array(hashes, max_len)
        subjects = pad_array(subjects, max_len)
        tracks = pad_array(tracks, max_len)
        dates = pad_array(dates, max_len)

        # Handle backup exclusion flags
        exclude_backup = args.exclude_backup
        if args.include_backup:
            exclude_backup = False

        # Build options
        options = FilterOptions(
            exclude_current=args.exclude_current,
            exclude_backup=exclude_backup,
        )

        # Run filter
        result = filter_branches(
            branches=branches,
            hashes=hashes,
            subjects=subjects,
            tracks=tracks,
            dates=dates,
            current_branch=args.current_branch,
            options=options,
        )

        # Output bash declarations
        print(result.to_bash_declare())

    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
