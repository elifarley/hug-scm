#!/usr/bin/env python3
"""
Hug SCM - Co-change Analysis

Analyzes which files frequently change together in commit history.
Reveals architectural coupling and helps identify modules that should be
reviewed together or refactored.

Usage:
    python3 co_changes.py [--commits=<N>] [--threshold=<pct>] [--format=<format>]

Input: Git log data via stdin (from git log --name-only)
Output: JSON with file pairs and correlation scores

Example:
    git log --name-only --format=%H -n 50 | python3 co_changes.py --threshold=0.30
"""

import sys
import json
import argparse
from collections import defaultdict
from typing import Dict, List, Tuple, Set


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Analyze co-change patterns from Git history")
    parser.add_argument(
        "--commits", type=int, default=100, help="Number of commits to analyze (default: 100)"
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.30,
        help="Minimum correlation threshold (0.0-1.0, default: 0.30)",
    )
    parser.add_argument(
        "--format", choices=["json", "text"], default="text", help="Output format (default: text)"
    )
    parser.add_argument(
        "--top", type=int, default=20, help="Show top N co-change pairs (default: 20)"
    )

    return parser.parse_args()


def parse_git_log(stdin_input: str) -> List[Set[str]]:
    """
    Parse git log --name-only output into list of file sets per commit.

    Format expected:
    commit_hash
    file1
    file2

    commit_hash
    file3
    file4

    Returns: List of sets, each containing files changed in one commit
    """
    commits = []
    current_files = set()

    for line in stdin_input.strip().split("\n"):
        line = line.strip()

        if not line:
            # Empty line separates commits
            if current_files:
                commits.append(current_files)
                current_files = set()
        elif len(line) == 40 and all(c in "0123456789abcdef" for c in line):
            # Looks like a commit hash - start of new commit
            if current_files:
                commits.append(current_files)
                current_files = set()
        else:
            # File path
            current_files.add(line)

    # Don't forget the last commit
    if current_files:
        commits.append(current_files)

    return commits


def build_co_occurrence_matrix(
    commits: List[Set[str]],
) -> Tuple[Dict[str, Dict[str, int]], Dict[str, int]]:
    """
    Build co-occurrence matrix and file change counts.

    Returns:
        - co_matrix: Dict[file_a][file_b] = times changed together
        - file_counts: Dict[file] = total times changed
    """
    co_matrix = defaultdict(lambda: defaultdict(int))
    file_counts = defaultdict(int)

    for file_set in commits:
        # Count individual file changes
        for file in file_set:
            file_counts[file] += 1

        # Count co-occurrences (pairs)
        files = list(file_set)
        for i in range(len(files)):
            for j in range(i + 1, len(files)):
                file_a, file_b = sorted([files[i], files[j]])
                co_matrix[file_a][file_b] += 1

    return dict(co_matrix), dict(file_counts)


def calculate_correlations(
    co_matrix: Dict[str, Dict[str, int]], file_counts: Dict[str, int], threshold: float
) -> List[Dict]:
    """
    Calculate correlation scores for file pairs.

    Correlation = co_occurrences / min(changes_a, changes_b)

    This measures: "When file A changes, how often does B also change?"

    Returns: List of dicts with file pairs and correlation data
    """
    correlations = []

    for file_a, co_files in co_matrix.items():
        for file_b, co_count in co_files.items():
            count_a = file_counts[file_a]
            count_b = file_counts[file_b]

            # Calculate correlation (Jaccard-like coefficient)
            # Using min to ask: "When the less-changed file changes,
            # how often does the other change too?"
            correlation = co_count / min(count_a, count_b)

            if correlation >= threshold:
                correlations.append(
                    {
                        "file_a": file_a,
                        "file_b": file_b,
                        "correlation": correlation,
                        "co_changes": co_count,
                        "changes_a": count_a,
                        "changes_b": count_b,
                    }
                )

    # Sort by correlation (descending)
    correlations.sort(key=lambda x: x["correlation"], reverse=True)

    return correlations


def format_text_output(correlations: List[Dict], threshold: float, total_commits: int) -> str:
    """Format correlations as human-readable text."""
    lines = []

    lines.append(
        f"Co-change Analysis (last {total_commits} commits, ≥{threshold:.0%} correlation):"
    )
    lines.append("")

    if not correlations:
        lines.append("No file pairs found above threshold.")
        lines.append("")
        lines.append("Try:")
        lines.append("  - Lowering --threshold (e.g., 0.20)")
        lines.append("  - Increasing --commits (e.g., 200)")
        return "\n".join(lines)

    # Group by correlation strength
    high = [c for c in correlations if c["correlation"] >= 0.60]
    medium = [c for c in correlations if 0.40 <= c["correlation"] < 0.60]
    low = [c for c in correlations if c["correlation"] < 0.40]

    if high:
        lines.append("Strong coupling (≥60%):")
        for corr in high:
            lines.append(f"  {corr['file_a']} ↔ {corr['file_b']}")
            lines.append(
                f"    {corr['correlation']:.0%} correlation "
                f"({corr['co_changes']}/{min(corr['changes_a'], corr['changes_b'])} commits)"
            )
        lines.append("")

    if medium:
        lines.append("Moderate coupling (40-60%):")
        for corr in medium:
            lines.append(f"  {corr['file_a']} ↔ {corr['file_b']}")
            lines.append(
                f"    {corr['correlation']:.0%} correlation "
                f"({corr['co_changes']}/{min(corr['changes_a'], corr['changes_b'])} commits)"
            )
        lines.append("")

    if low:
        lines.append("Weak coupling (<40%):")
        for corr in low[:10]:  # Limit weak correlations shown
            lines.append(f"  {corr['file_a']} ↔ {corr['file_b']} ({corr['correlation']:.0%})")
        if len(low) > 10:
            lines.append(f"  ... and {len(low) - 10} more pairs")
        lines.append("")

    lines.append("Interpretation:")
    lines.append("  High correlation = Files likely architecturally coupled")
    lines.append("  Consider: Co-locate, refactor into module, or document dependency")

    return "\n".join(lines)


def main():
    """Main entry point."""
    args = parse_args()

    # Read git log from stdin
    stdin_input = sys.stdin.read()

    if not stdin_input.strip():
        print("Error: No input provided", file=sys.stderr)
        print(
            "Usage: git log --name-only --format=%H -n 50 | python3 co_changes.py", file=sys.stderr
        )
        return 1

    # Parse commits
    commits = parse_git_log(stdin_input)

    if not commits:
        print("Error: No commits found in input", file=sys.stderr)
        return 1

    # Build co-occurrence matrix
    co_matrix, file_counts = build_co_occurrence_matrix(commits)

    # Calculate correlations
    correlations = calculate_correlations(co_matrix, file_counts, args.threshold)

    # Limit to top N
    if args.top and args.top < len(correlations):
        correlations = correlations[: args.top]

    # Output
    if args.format == "json":
        result = {
            "commits_analyzed": len(commits),
            "threshold": args.threshold,
            "total_pairs": len(correlations),
            "correlations": correlations,
        }
        print(json.dumps(result, indent=2))
    else:
        print(format_text_output(correlations, args.threshold, len(commits)))

    return 0


if __name__ == "__main__":
    sys.exit(main())
