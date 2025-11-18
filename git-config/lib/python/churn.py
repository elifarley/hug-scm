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
from collections import defaultdict
from datetime import datetime
from typing import Dict, List, Tuple

def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description='Analyze file and line churn from Git history'
    )
    parser.add_argument(
        'file',
        help='File to analyze'
    )
    parser.add_argument(
        '--since',
        default=None,
        help='Only analyze commits since this date'
    )
    parser.add_argument(
        '--format',
        choices=['json', 'text'],
        default='json',
        help='Output format (default: json)'
    )
    parser.add_argument(
        '--hot-threshold',
        type=int,
        default=3,
        help='Minimum changes to consider a line "hot" (default: 3)'
    )

    return parser.parse_args()


def get_line_history(filepath: str, since: str = None) -> Dict[int, int]:
    """
    Get change count for each line using git blame --line-porcelain.

    Returns: Dict mapping line_number -> change_count
    """
    # Use git blame --line-porcelain to get commit hash per line
    # Then count unique commits per line
    cmd = ['git', 'blame', '--line-porcelain', '-w', '-C', '-C', '-C', '--', filepath]

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True
        )

        line_commits = {}  # line_number -> set of commit hashes
        current_commit = None
        current_line = None

        for line in result.stdout.split('\n'):
            if not line:
                continue

            # Line starts with commit hash
            if not line.startswith('\t'):
                parts = line.split(' ', 2)
                if len(parts) >= 3 and len(parts[0]) == 40:  # SHA-1 hash
                    current_commit = parts[0]
                    # Parts[1] is original line, parts[2] is final line
                    try:
                        current_line = int(parts[2])
                    except (ValueError, IndexError):
                        pass

        # For now, return simple commit count per line from blame
        # This gives us "how many times has this line's current state been committed"
        # Full implementation would use git log -L to track all historical changes

        # Simplified: just return line number -> 1 for now
        # Full line history tracking is expensive and should be opt-in

        return {}  # Simplified for performance

    except subprocess.CalledProcessError as e:
        print(f"Error running git blame: {e}", file=sys.stderr)
        return {}


def get_file_churn(filepath: str, since: str = None) -> Dict[str, any]:
    """
    Calculate file-level churn metrics.

    Returns: Dict with total_commits, authors, date_range, etc.
    """
    cmd = ['git', 'log', '--follow', '--format=%H|%an|%ai', '--', filepath]
    if since:
        cmd.insert(2, f'--since={since}')

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=True
        )

        commits = []
        authors = set()

        for line in result.stdout.strip().split('\n'):
            if not line:
                continue
            hash_val, author, date = line.split('|', 2)
            commits.append({
                'hash': hash_val,
                'author': author,
                'date': date
            })
            authors.add(author)

        return {
            'total_commits': len(commits),
            'unique_authors': len(authors),
            'authors': list(authors),
            'first_commit': commits[-1] if commits else None,
            'last_commit': commits[0] if commits else None,
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

    Returns comprehensive churn data structure.
    """
    file_churn = get_file_churn(filepath, since)
    if not file_churn:
        return {'error': 'Could not analyze file'}

    # TODO: Implement line-level analysis
    # For now, return file-level data

    result = {
        'file': filepath,
        'file_churn': file_churn,
        'line_churn': {},  # TODO: Implement
        'hot_lines': [],   # Lines with changes > hot_threshold
        'analysis_params': {
            'since': since,
            'hot_threshold': hot_threshold
        }
    }

    return result


def format_text_output(data: Dict) -> str:
    """Format churn data as human-readable text."""
    lines = []

    lines.append(f"Churn analysis for: {data['file']}")
    lines.append("")

    fc = data['file_churn']
    lines.append("File-level metrics:")
    lines.append(f"  Total commits: {fc['total_commits']}")
    lines.append(f"  Unique authors: {fc['unique_authors']}")

    if fc['first_commit']:
        lines.append(f"  First changed: {fc['first_commit']['date'][:10]} by {fc['first_commit']['author']}")
    if fc['last_commit']:
        lines.append(f"  Last changed: {fc['last_commit']['date'][:10]} by {fc['last_commit']['author']}")

    lines.append("")
    lines.append("Line-level churn: (Not yet implemented)")
    lines.append("TODO: Show hot lines with change counts")

    return '\n'.join(lines)


def main():
    """Main entry point."""
    args = parse_args()

    # Analyze churn
    data = analyze_churn(
        args.file,
        since=args.since,
        hot_threshold=args.hot_threshold
    )

    # Output
    if args.format == 'json':
        print(json.dumps(data, indent=2))
    else:
        print(format_text_output(data))

    return 0 if 'error' not in data else 1


if __name__ == '__main__':
    sys.exit(main())
