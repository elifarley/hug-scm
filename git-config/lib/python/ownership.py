#!/usr/bin/env python3
"""
Hug SCM - Code Ownership Analysis

Identifies code experts using recency-weighted commit analysis.
Recent contributions are weighted higher than historical ones.

Usage:
    python3 ownership.py <file> [--since=<date>] [--format=<format>]
    python3 ownership.py --author <name> [--format=<format>]

Input: File path or author name
Output: JSON with ownership percentages and expertise areas

Example:
    python3 ownership.py src/auth.js --since="6 months ago"
    python3 ownership.py --author "Alice" --format=text
"""

import sys
import json
import argparse
import subprocess
import math
from datetime import datetime
from collections import defaultdict
from typing import Dict, List, Tuple


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Analyze code ownership and expertise")
    parser.add_argument("target", nargs="?", help="File path to analyze (for file mode)")
    parser.add_argument("--author", help="Author name (for author expertise mode)")
    parser.add_argument("--since", default=None, help="Only consider commits since this date")
    parser.add_argument(
        "--format", choices=["json", "text"], default="text", help="Output format (default: text)"
    )
    parser.add_argument(
        "--decay-days",
        type=int,
        default=180,
        help="Recency decay constant in days (default: 180 = 6 months)",
    )

    return parser.parse_args()


def get_file_commit_history(filepath: str, since: str = None) -> List[Dict]:
    """
    Get commit history for a file with author and timestamp.

    Returns: List of dicts with {hash, author, date, days_ago}
    """
    cmd = ["git", "log", "--follow", "--format=%H|%an|%ai", "--", filepath]

    if since:
        cmd.insert(2, f"--since={since}")

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)

        commits = []
        now = datetime.now()

        for line in result.stdout.strip().split("\n"):
            if not line:
                continue

            hash_val, author, date_str = line.split("|", 2)

            # Parse date
            commit_date = datetime.fromisoformat(date_str.replace(" ", "T", 1).rsplit(" ", 1)[0])
            days_ago = (now - commit_date).days

            commits.append(
                {"hash": hash_val, "author": author, "date": date_str[:10], "days_ago": days_ago}
            )

        return commits

    except subprocess.CalledProcessError as e:
        print(f"Error getting file history: {e}", file=sys.stderr)
        return []


def get_author_files(author: str, since: str = None) -> Dict[str, int]:
    """
    Get all files touched by an author with commit counts.

    Returns: Dict of {filepath: commit_count}
    """
    cmd = ["git", "log", "--all", "--name-only", f"--author={author}", "--format=%H"]

    if since:
        cmd.insert(2, f"--since={since}")

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)

        file_commits = defaultdict(int)

        lines = result.stdout.strip().split("\n")
        i = 0
        while i < len(lines):
            line = lines[i].strip()

            # Check if this is a commit hash
            if len(line) == 40 and all(c in "0123456789abcdef" for c in line.lower()):
                # Process all non-empty lines after hash until next hash or end
                i += 1
                while i < len(lines):
                    file_line = lines[i].strip()

                    if not file_line:
                        # Skip empty lines
                        i += 1
                        continue

                    # Check if we hit next commit hash
                    if len(file_line) == 40 and all(
                        c in "0123456789abcdef" for c in file_line.lower()
                    ):
                        # Don't increment i, we'll process this hash in outer loop
                        break

                    # This is a file path
                    file_commits[file_line] += 1
                    i += 1
            else:
                i += 1

        return dict(file_commits)

    except subprocess.CalledProcessError as e:
        print(f"Error getting author files: {e}", file=sys.stderr)
        return {}


def calculate_recency_weight(days_ago: int, decay_days: int) -> float:
    """
    Calculate recency weight using exponential decay.

    Formula: exp(-days_ago / decay_days)

    Recent commits (days_ago near 0) → weight near 1.0
    Old commits (days_ago >> decay_days) → weight near 0.0
    """
    return math.exp(-days_ago / decay_days)


def calculate_file_ownership(commits: List[Dict], decay_days: int) -> List[Dict]:
    """
    Calculate ownership percentages with recency weighting.

    Returns: List of {author, raw_commits, weighted_score, ownership_pct, classification}
    """
    author_data = defaultdict(
        lambda: {"raw_commits": 0, "weighted_score": 0.0, "last_commit_days": float("inf")}
    )

    for commit in commits:
        author = commit["author"]
        days_ago = commit["days_ago"]

        author_data[author]["raw_commits"] += 1
        author_data[author]["weighted_score"] += calculate_recency_weight(days_ago, decay_days)
        author_data[author]["last_commit_days"] = min(
            author_data[author]["last_commit_days"], days_ago
        )

    # Calculate total weighted score
    total_weighted = sum(data["weighted_score"] for data in author_data.values())

    if total_weighted == 0:
        return []

    # Build ownership list
    ownership = []
    for author, data in author_data.items():
        ownership_pct = (data["weighted_score"] / total_weighted) * 100

        # Classify ownership level
        if ownership_pct >= 40:
            classification = "primary"
        elif ownership_pct >= 20:
            classification = "secondary"
        else:
            classification = "historical"

        ownership.append(
            {
                "author": author,
                "raw_commits": data["raw_commits"],
                "weighted_score": data["weighted_score"],
                "ownership_pct": ownership_pct,
                "classification": classification,
                "last_commit_days": data["last_commit_days"],
            }
        )

    # Sort by ownership percentage (descending)
    ownership.sort(key=lambda x: x["ownership_pct"], reverse=True)

    return ownership


def format_days_ago(days: int) -> str:
    """Format days ago as human-readable string."""
    if days == 0:
        return "today"
    elif days == 1:
        return "yesterday"
    elif days < 7:
        return f"{days} days ago"
    elif days < 30:
        weeks = days // 7
        return f"{weeks} week{'s' if weeks > 1 else ''} ago"
    elif days < 365:
        months = days // 30
        return f"{months} month{'s' if months > 1 else ''} ago"
    else:
        years = days // 365
        return f"{years} year{'s' if years > 1 else ''} ago"


def format_file_ownership_text(filepath: str, ownership: List[Dict]) -> str:
    """Format file ownership as human-readable text."""
    lines = []

    lines.append(f"Experts for {filepath}:")
    lines.append("")

    # Group by classification
    primary = [o for o in ownership if o["classification"] == "primary"]
    secondary = [o for o in ownership if o["classification"] == "secondary"]
    historical = [o for o in ownership if o["classification"] == "historical"]

    if primary:
        lines.append("Primary maintainer:" if len(primary) == 1 else "Primary maintainers:")
        for owner in primary:
            stale_warning = " ⚠️  Stale" if owner["last_commit_days"] > 180 else ""
            lines.append(
                f"  {owner['author']} "
                f"({owner['ownership_pct']:.0f}%, {owner['raw_commits']} commits, "
                f"last: {format_days_ago(owner['last_commit_days'])}){stale_warning}"
            )
        lines.append("")

    if secondary:
        lines.append("Secondary:")
        for owner in secondary:
            stale_warning = " ⚠️  Stale" if owner["last_commit_days"] > 180 else ""
            lines.append(
                f"  {owner['author']} "
                f"({owner['ownership_pct']:.0f}%, {owner['raw_commits']} commits, "
                f"last: {format_days_ago(owner['last_commit_days'])}){stale_warning}"
            )
        lines.append("")

    if historical:
        lines.append("Historical:")
        for owner in historical:
            stale_warning = " ⚠️  Stale" if owner["last_commit_days"] > 180 else ""
            lines.append(
                f"  {owner['author']} "
                f"({owner['ownership_pct']:.0f}%, {owner['raw_commits']} commits, "
                f"last: {format_days_ago(owner['last_commit_days'])}){stale_warning}"
            )

    return "\n".join(lines)


def format_author_expertise_text(author: str, files: Dict[str, int]) -> str:
    """Format author expertise as human-readable text."""
    lines = []

    lines.append(f"{author}'s expertise areas:")
    lines.append("")

    if not files:
        lines.append("No files found.")
        return "\n".join(lines)

    # Sort by commit count
    sorted_files = sorted(files.items(), key=lambda x: x[1], reverse=True)

    # Show top 20
    for i, (filepath, count) in enumerate(sorted_files[:20], 1):
        lines.append(f"{i:2d}. {filepath:50s} ({count} commits)")

    if len(sorted_files) > 20:
        lines.append("")
        lines.append(f"... and {len(sorted_files) - 20} more files")

    return "\n".join(lines)


def main():
    """Main entry point."""
    args = parse_args()

    # Author expertise mode
    if args.author:
        files = get_author_files(args.author, args.since)

        if args.format == "json":
            result = {
                "author": args.author,
                "total_files": len(files),
                "files": [
                    {"path": path, "commits": count}
                    for path, count in sorted(files.items(), key=lambda x: x[1], reverse=True)
                ],
            }
            print(json.dumps(result, indent=2))
        else:
            print(format_author_expertise_text(args.author, files))

        return 0

    # File ownership mode
    if not args.target:
        print("Error: Must provide file path or --author", file=sys.stderr)
        return 1

    filepath = args.target

    # Get commit history
    commits = get_file_commit_history(filepath, args.since)

    if not commits:
        print(f"Error: No commits found for {filepath}", file=sys.stderr)
        return 1

    # Calculate ownership
    ownership = calculate_file_ownership(commits, args.decay_days)

    # Output
    if args.format == "json":
        result = {
            "file": filepath,
            "total_commits": len(commits),
            "decay_days": args.decay_days,
            "ownership": ownership,
        }
        print(json.dumps(result, indent=2))
    else:
        print(format_file_ownership_text(filepath, ownership))

    return 0


if __name__ == "__main__":
    sys.exit(main())
