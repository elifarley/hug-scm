#!/usr/bin/env python3
"""
Hug SCM - File and Line Churn Analysis

Analyzes how frequently files and individual lines change over time.
Used by `hug fblame --churn` to show "hot" lines that change frequently.

Usage:
    python3 churn.py <file> [--since=<date>] [--format=<format>]

Input: File path
Output: JSON with churn data per line

Example:
    python3 churn.py src/auth.js --since="3 months ago"
"""

import sys
import json
import subprocess
import argparse
import re
from collections import defaultdict
from datetime import datetime
from typing import Dict, List, Tuple


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Analyze file and line churn from Git history")
    parser.add_argument("file", help="File to analyze")
    parser.add_argument("--since", default=None, help="Only analyze commits since this date")
    parser.add_argument(
        "--format", choices=["json", "text"], default="json", help="Output format (default: json)"
    )
    parser.add_argument(
        "--hot-threshold",
        type=int,
        default=3,
        help='Minimum changes to consider a line "hot" (default: 3)',
    )

    return parser.parse_args()


def get_line_history(filepath: str, since: str = None) -> Dict[int, int]:
    """
    Get change count for each line using git log -L.

    Uses git log -L to track how many times each line has changed throughout history.
    This is expensive for large files, so use sparingly or with --since filters.

    Returns: Dict mapping line_number -> change_count
    """
    # First, get current line count
    try:
        with open(filepath, "r") as f:
            total_lines = sum(1 for _ in f)
    except (FileNotFoundError, IOError) as e:
        print(f"Error reading file {filepath}: {e}", file=sys.stderr)
        return {}

    line_churn = {}

    # For each line, use git log -L to count commits that touched it
    for line_num in range(1, total_lines + 1):
        cmd = ["git", "log", "-L", f"{line_num},{line_num}:{filepath}", "--oneline"]

        if since:
            cmd.insert(2, f"--since={since}")

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=False,  # git log -L returns non-zero if line never changed
            )

            # Count commits (only lines starting with commit hash in --oneline output)
            # Note: git log -L with --oneline includes diff context, not just commit headers
            if result.returncode == 0:
                commit_count = len(
                    [l for l in result.stdout.strip().split("\n") if re.match(r"^[a-f0-9]{7,}", l)]
                )
                if commit_count > 0:
                    line_churn[line_num] = commit_count
            else:
                # Line may not exist in history (newly added)
                line_churn[line_num] = 0

        except Exception as e:
            print(f"Warning: Could not analyze line {line_num}: {e}", file=sys.stderr)
            continue

    return line_churn


def get_file_churn(filepath: str, since: str = None) -> Dict[str, any]:
    """
    Calculate file-level churn metrics.

    Returns: Dict with total_commits, authors, date_range, etc.
    """
    cmd = ["git", "log", "--follow", "--format=%H|%an|%ai", "--", filepath]
    if since:
        cmd.insert(2, f"--since={since}")

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)

        commits = []
        authors = set()

        for line in result.stdout.strip().split("\n"):
            if not line:
                continue
            hash_val, author, date = line.split("|", 2)
            commits.append({"hash": hash_val, "author": author, "date": date})
            authors.add(author)

        return {
            "total_commits": len(commits),
            "unique_authors": len(authors),
            "authors": list(authors),
            "first_commit": commits[-1] if commits else None,
            "last_commit": commits[0] if commits else None,
        }

    except subprocess.CalledProcessError as e:
        print(f"Error running git log: {e}", file=sys.stderr)
        return None


def calculate_churn_score(changes: int, recency_days: int) -> float:
    """
    Calculate churn score with recency weighting.

    Formula: changes * exp(-days/90)
    Recent changes weighted higher.
    """
    import math

    decay_constant = 90  # 3 months
    recency_weight = math.exp(-recency_days / decay_constant)
    return changes * recency_weight


def analyze_churn(filepath: str, since: str = None, hot_threshold: int = 3) -> Dict:
    """
    Main analysis function.

    Returns comprehensive churn data structure with file-level and line-level metrics.
    """
    file_churn = get_file_churn(filepath, since)
    if not file_churn:
        return {"error": "Could not analyze file"}

    # Get line-level churn data
    line_churn = get_line_history(filepath, since)

    # Identify hot lines (lines changed frequently)
    hot_lines = []
    for line_num, change_count in sorted(line_churn.items()):
        if change_count >= hot_threshold:
            hot_lines.append(
                {
                    "line_number": line_num,
                    "changes": change_count,
                    "churn_score": calculate_churn_score(change_count, 0),  # 0 days = max recency
                }
            )

    # Sort hot lines by change count (descending)
    hot_lines.sort(key=lambda x: x["changes"], reverse=True)

    result = {
        "file": filepath,
        "file_churn": file_churn,
        "line_churn": line_churn,
        "hot_lines": hot_lines,
        "summary": {
            "total_lines": len(line_churn) if line_churn else 0,
            "lines_with_changes": sum(1 for c in line_churn.values() if c > 0),
            "hot_lines_count": len(hot_lines),
            "max_line_changes": max(line_churn.values()) if line_churn else 0,
            "avg_line_changes": sum(line_churn.values()) / len(line_churn) if line_churn else 0,
        },
        "analysis_params": {"since": since, "hot_threshold": hot_threshold},
    }

    return result


def format_text_output(data: Dict) -> str:
    """Format churn data as human-readable text."""
    lines = []

    lines.append(f"Churn analysis for: {data['file']}")
    lines.append("")

    # File-level metrics
    fc = data["file_churn"]
    lines.append("File-level metrics:")
    lines.append(f"  Total commits: {fc['total_commits']}")
    lines.append(f"  Unique authors: {fc['unique_authors']}")

    if fc["first_commit"]:
        lines.append(
            f"  First changed: {fc['first_commit']['date'][:10]} by {fc['first_commit']['author']}"
        )
    if fc["last_commit"]:
        lines.append(
            f"  Last changed: {fc['last_commit']['date'][:10]} by {fc['last_commit']['author']}"
        )

    # Line-level summary
    if "summary" in data:
        lines.append("")
        lines.append("Line-level summary:")
        s = data["summary"]
        lines.append(f"  Total lines analyzed: {s['total_lines']}")
        lines.append(f"  Lines with changes: {s['lines_with_changes']}")
        lines.append(
            f"  Hot lines (≥{data['analysis_params']['hot_threshold']} changes): {s['hot_lines_count']}"
        )

        if s["max_line_changes"] > 0:
            lines.append(f"  Most changed line: {s['max_line_changes']} changes")
            lines.append(f"  Average changes per line: {s['avg_line_changes']:.2f}")

    # Hot lines details
    if data.get("hot_lines"):
        lines.append("")
        lines.append("Hot lines (most frequently changed):")
        lines.append("")

        for hl in data["hot_lines"][:20]:  # Show top 20
            line_num = hl["line_number"]
            changes = hl["changes"]
            lines.append(f"  Line {line_num:4d}: {changes:3d} changes")

        if len(data["hot_lines"]) > 20:
            lines.append(f"  ... and {len(data['hot_lines']) - 20} more hot lines")

    return "\n".join(lines)


def main():
    """Main entry point."""
    args = parse_args()

    # Analyze churn
    data = analyze_churn(args.file, since=args.since, hot_threshold=args.hot_threshold)

    # Output
    if args.format == "json":
        print(json.dumps(data, indent=2))
    else:
        print(format_text_output(data))

    return 0 if "error" not in data else 1


if __name__ == "__main__":
    sys.exit(main())
