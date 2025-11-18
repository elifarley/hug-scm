#!/usr/bin/env python3
"""
Hug SCM - Temporal Activity Analysis

Analyzes commit patterns over time to reveal team dynamics, productivity
patterns, and potential process issues.

Usage:
    python3 activity.py [--by-hour|--by-day|--by-author] [--since=<date>] [--format=<format>]

Input: Git log data via stdin (from git log --format='%ai|%an')
Output: JSON or formatted histograms showing temporal patterns

Example:
    git log --format='%ai|%an' --since="3 months ago" | python3 activity.py --by-hour
"""

import sys
import json
import argparse
from collections import defaultdict
from datetime import datetime
from typing import Dict, List, Tuple

def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description='Analyze temporal commit activity patterns'
    )
    parser.add_argument(
        '--by-hour',
        action='store_true',
        help='Group commits by hour of day'
    )
    parser.add_argument(
        '--by-day',
        action='store_true',
        help='Group commits by day of week'
    )
    parser.add_argument(
        '--by-author',
        action='store_true',
        help='Break down activity by author'
    )
    parser.add_argument(
        '--format',
        choices=['json', 'text'],
        default='text',
        help='Output format (default: text)'
    )
    parser.add_argument(
        '--since',
        help='Description of time range (for display)'
    )

    return parser.parse_args()


def parse_git_log(stdin_input: str) -> List[Dict]:
    """
    Parse git log output into commit records.

    Expected format: timestamp|author
    Example: 2024-03-20 14:32:15 -0400|Alice Smith

    Returns: List of {timestamp, author, hour, day_of_week, date}
    """
    commits = []

    for line in stdin_input.strip().split('\n'):
        if not line.strip():
            continue

        try:
            timestamp_str, author = line.split('|', 1)

            # Parse timestamp (format: "2024-03-20 14:32:15 -0400")
            # Remove timezone for simpler parsing
            timestamp_parts = timestamp_str.rsplit(' ', 1)[0]
            dt = datetime.strptime(timestamp_parts, '%Y-%m-%d %H:%M:%S')

            commits.append({
                'timestamp': timestamp_str,
                'author': author.strip(),
                'hour': dt.hour,
                'day_of_week': dt.strftime('%a'),  # Mon, Tue, etc.
                'date': dt.date().isoformat(),
                'datetime': dt
            })

        except (ValueError, IndexError) as e:
            print(f"Warning: Could not parse line: {line}", file=sys.stderr)
            continue

    return commits


def analyze_by_hour(commits: List[Dict], by_author: bool = False) -> Dict:
    """
    Group commits by hour of day.

    Returns: Dict with hour buckets and counts
    """
    if by_author:
        # author -> hour -> count
        data = defaultdict(lambda: defaultdict(int))
        for commit in commits:
            data[commit['author']][commit['hour']] += 1

        return {
            'type': 'by_hour_and_author',
            'data': {author: dict(hours) for author, hours in data.items()}
        }
    else:
        # hour -> count
        data = defaultdict(int)
        for commit in commits:
            data[commit['hour']] += 1

        return {
            'type': 'by_hour',
            'data': dict(data)
        }


def analyze_by_day(commits: List[Dict], by_author: bool = False) -> Dict:
    """
    Group commits by day of week.

    Returns: Dict with day buckets and counts
    """
    day_order = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

    if by_author:
        # author -> day -> count
        data = defaultdict(lambda: defaultdict(int))
        for commit in commits:
            data[commit['author']][commit['day_of_week']] += 1

        return {
            'type': 'by_day_and_author',
            'day_order': day_order,
            'data': {author: dict(days) for author, days in data.items()}
        }
    else:
        # day -> count
        data = defaultdict(int)
        for commit in commits:
            data[commit['day_of_week']] += 1

        return {
            'type': 'by_day',
            'day_order': day_order,
            'data': dict(data)
        }


def detect_patterns(analysis: Dict) -> List[str]:
    """
    Detect interesting patterns in the data.

    Returns: List of observation strings
    """
    observations = []

    if analysis['type'] == 'by_hour':
        data = analysis['data']

        # Late night work (10pm - 4am)
        late_night = sum(data.get(h, 0) for h in [22, 23, 0, 1, 2, 3, 4])
        total = sum(data.values())

        if late_night > 0 and total > 0:
            pct = (late_night / total) * 100
            if pct > 5:
                observations.append(f"⚠️  {pct:.1f}% of commits during late night (10pm-4am)")

        # Peak hours
        if data:
            peak_hour = max(data.items(), key=lambda x: x[1])
            observations.append(f"Peak activity: {peak_hour[0]:02d}:00 ({peak_hour[1]} commits)")

    elif analysis['type'] == 'by_day':
        data = analysis['data']

        # Weekend work
        weekend = data.get('Sat', 0) + data.get('Sun', 0)
        total = sum(data.values())

        if weekend > 0 and total > 0:
            pct = (weekend / total) * 100
            if pct > 10:
                observations.append(f"⚠️  {pct:.1f}% of commits on weekends")

        # Peak day
        if data:
            peak_day = max(data.items(), key=lambda x: x[1])
            observations.append(f"Most active day: {peak_day[0]} ({peak_day[1]} commits)")

    return observations


def create_histogram(data: Dict[int, int], max_width: int = 40) -> List[str]:
    """
    Create ASCII histogram bars.

    Returns: List of formatted strings
    """
    if not data:
        return []

    max_count = max(data.values())
    lines = []

    for key in sorted(data.keys()):
        count = data[key]
        if max_count > 0:
            bar_width = int((count / max_count) * max_width)
            bar = '█' * bar_width
        else:
            bar = ''

        lines.append(f"{key:02d}:00 {bar} {count}")

    return lines


def create_day_histogram(data: Dict[str, int], day_order: List[str], max_width: int = 40) -> List[str]:
    """
    Create ASCII histogram for days of week.

    Returns: List of formatted strings
    """
    if not data:
        return []

    max_count = max(data.values()) if data.values() else 0
    lines = []

    for day in day_order:
        count = data.get(day, 0)
        if max_count > 0:
            bar_width = int((count / max_count) * max_width)
            bar = '█' * bar_width
        else:
            bar = ''

        lines.append(f"{day} {bar} {count}")

    return lines


def format_text_output(analysis: Dict, commits_count: int, time_range: str = None) -> str:
    """Format analysis as human-readable text."""
    lines = []

    if time_range:
        lines.append(f"Commit Activity Analysis ({time_range}):")
    else:
        lines.append(f"Commit Activity Analysis ({commits_count} commits):")
    lines.append("")

    if analysis['type'] == 'by_hour':
        lines.append("Commits by Hour:")
        lines.append("")
        lines.extend(create_histogram(analysis['data']))

    elif analysis['type'] == 'by_day':
        lines.append("Commits by Day of Week:")
        lines.append("")
        lines.extend(create_day_histogram(analysis['data'], analysis['day_order']))

    elif analysis['type'] == 'by_hour_and_author':
        lines.append("Commits by Hour (per author):")
        lines.append("")
        for author, hours in sorted(analysis['data'].items()):
            lines.append(f"{author}:")
            lines.extend(['  ' + line for line in create_histogram(hours, max_width=35)])
            lines.append("")

    elif analysis['type'] == 'by_day_and_author':
        lines.append("Commits by Day (per author):")
        lines.append("")
        for author, days in sorted(analysis['data'].items()):
            lines.append(f"{author}:")
            lines.extend(['  ' + line for line in create_day_histogram(days, analysis['day_order'], max_width=35)])
            lines.append("")

    # Add pattern detection
    observations = detect_patterns(analysis)
    if observations:
        lines.append("")
        lines.append("Observations:")
        for obs in observations:
            lines.append(f"  {obs}")

    return '\n'.join(lines)


def main():
    """Main entry point."""
    args = parse_args()

    # Read git log from stdin
    stdin_input = sys.stdin.read()

    if not stdin_input.strip():
        print("Error: No input provided", file=sys.stderr)
        print("Usage: git log --format='%ai|%an' | python3 activity.py", file=sys.stderr)
        return 1

    # Parse commits
    commits = parse_git_log(stdin_input)

    if not commits:
        print("Error: No valid commits found in input", file=sys.stderr)
        return 1

    # Determine analysis type
    if args.by_hour:
        analysis = analyze_by_hour(commits, args.by_author)
    elif args.by_day:
        analysis = analyze_by_day(commits, args.by_author)
    else:
        # Default: show both hour and day
        hour_analysis = analyze_by_hour(commits, args.by_author)
        day_analysis = analyze_by_day(commits, args.by_author)

        if args.format == 'json':
            result = {
                'commits_analyzed': len(commits),
                'time_range': args.since,
                'by_hour': hour_analysis,
                'by_day': day_analysis
            }
            print(json.dumps(result, indent=2))
        else:
            print(format_text_output(hour_analysis, len(commits), args.since))
            print("")
            print(format_text_output(day_analysis, len(commits), args.since))

        return 0

    # Output single analysis
    if args.format == 'json':
        result = {
            'commits_analyzed': len(commits),
            'time_range': args.since,
            'analysis': analysis
        }
        print(json.dumps(result, indent=2))
    else:
        print(format_text_output(analysis, len(commits), args.since))

    return 0


if __name__ == '__main__':
    sys.exit(main())
