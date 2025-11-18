#!/usr/bin/env python3
"""
Parse git log output with numstat and format as JSON.

Usage:
    git log --format='<format>' --numstat | python3 log_json.py [--with-stats]

Input format expected:
    hash|~|short|~|author_name|~|author_email|~|...|~|refs
    <blank line>
    <numstat lines>
    <blank line>
    next commit...
"""

import sys
import json
import argparse


def parse_log_with_stats(lines):
    """Parse git log output with --numstat"""
    commits = []
    current_commit = None
    in_numstat = False

    for line in lines:
        line = line.rstrip('\n')

        # Check if this is a commit line (contains our delimiter)
        if '|~|' in line:
            # Save previous commit if exists
            if current_commit:
                commits.append(current_commit)

            # Parse new commit
            fields = line.split('|~|')
            if len(fields) < 12:
                continue

            # Extract message
            subject = fields[8]
            full_body = fields[9]
            body_parts = full_body.strip().split('\n', 1)
            body = body_parts[1].strip() if len(body_parts) > 1 else ""

            # Parse refs
            refs = []
            if fields[11]:
                for ref in fields[11].split(','):
                    ref = ref.strip()
                    if ' -> ' in ref:
                        parts = ref.split(' -> ')
                        refs.append(parts[0].strip())
                        refs.append(parts[1].strip())
                    else:
                        refs.append(ref)

            current_commit = {
                'hash': fields[0],
                'hash_short': fields[1],
                'author': {'name': fields[2], 'email': fields[3]},
                'committer': {'name': fields[4], 'email': fields[5]},
                'date': fields[6],
                'date_relative': fields[7],
                'message': {
                    'subject': subject,
                    'body': body if body else None
                },
                'parents': fields[10].split() if fields[10] else [],
                'refs': refs if refs else None,
                'stats': {
                    'files_changed': 0,
                    'insertions': 0,
                    'deletions': 0
                }
            }
            in_numstat = True

        elif in_numstat and current_commit:
            # This might be a numstat line or blank line
            if not line.strip():
                # Blank line - might separate commits or be between format and numstat
                continue

            # Try to parse as numstat: "additions\tdeletions\tfilename"
            parts = line.split('\t')
            if len(parts) >= 3:
                try:
                    add = 0 if parts[0] == '-' else int(parts[0])
                    delete = 0 if parts[1] == '-' else int(parts[1])
                    current_commit['stats']['insertions'] += add
                    current_commit['stats']['deletions'] += delete
                    current_commit['stats']['files_changed'] += 1
                except ValueError:
                    # Not a numstat line
                    pass

    # Save last commit
    if current_commit:
        commits.append(current_commit)

    return commits


def main():
    parser = argparse.ArgumentParser(description='Format git log output as JSON')
    parser.add_argument('--with-stats', action='store_true',
                       help='Parse numstat output')
    args = parser.parse_args()

    # Read all input
    lines = sys.stdin.readlines()

    if args.with_stats:
        commits = parse_log_with_stats(lines)
    else:
        # Should not reach here (bash handles non-stats case inline)
        commits = []

    # Build output
    output = {
        'command': 'hug ll',
        'commits': commits,
        'summary': {'total_commits': len(commits)}
    }

    if commits:
        earliest = min(c['date'] for c in commits)
        latest = max(c['date'] for c in commits)
        output['summary']['date_range'] = {
            'earliest': earliest,
            'latest': latest
        }

    print(json.dumps(output, indent=2))


if __name__ == '__main__':
    main()
