#!/usr/bin/env python3
"""
Parse git log output with numstat and format as JSON.

Usage:
    git log --format='<format>' --numstat | python3 log_json.py [--with-stats]

Input format expected:
    The format string splits across multiple lines:
    Line 1: hash|~|short|~|...|~|subject|~|<start of body>
    Lines 2-N: <continuation of body>
    Last line of commit: <end of body>|~|parent_hash|~|refs

    Then optionally followed by numstat lines and blank lines.
"""

import sys
import json
import argparse
import re


def parse_log_with_stats(lines, include_stats=True, omit_body=False):
    """Parse git log output with --numstat

    Args:
        lines: Lines from git log output
        include_stats: Whether to include stats field in output (default: True)
        omit_body: Whether to omit body text from output (default: False)

    The git log format we use is:
    %H|~|%h|~|%an|~|%ae|~|%cn|~|%ce|~|%aI|~|%ar|~|%s|~|%B|~|%P|~|%D

    This produces output where:
    - First line starts with commit hash (40 hex chars)
    - Body (%B) spans multiple lines
    - Last line of commit metadata ends with |~|parent_hashes|~|refs
    - Optionally followed by blank line and numstat lines

    Strategy: Accumulate lines until we find the next commit hash
    """
    commits = []
    current_lines = []
    current_numstats = []
    in_numstat = False

    for line in lines:
        line = line.rstrip('\n')

        # Always check for new commit first - this prevents subsequent commit lines
        # from being absorbed into previous commit's body.
        # Accept only 40 char hashes (git commit SHAs are always 40 hexadecimal characters)
        if re.match(r'^[0-9a-f]{40}\|~\|', line):
            # Process previous commit if exists
            if current_lines:
                commit = parse_single_commit(current_lines, current_numstats, include_stats, omit_body)
                if commit:
                    commits.append(commit)
            # Validate that commit line has enough fields before starting new commit
            # Expected format has 15 fields separated by |~|
            field_count = line.count('|~|') + 1
            if field_count >= 14:  # At least 14 fields required
                # Start new commit
                current_lines = [line]
                current_numstats = []
                in_numstat = False
            # Skip incomplete commit lines (field_count < 14)
            continue

        # Skip lines before the first commit (e.g., incomplete or malformed lines)
        if not current_lines:
            continue

        # Check if this is a numstat line (N\tM\tfilename)
        if '\t' in line and not '|~|' in line:
            parts = line.split('\t')
            if len(parts) >= 3:
                # This is a numstat line
                current_numstats.append(line)
                in_numstat = True
                continue

        # If we're not in numstat and not blank, it's part of commit body
        # Skip blank lines that appear between commits (when in_numstat=True)
        if not in_numstat or line.strip():
            current_lines.append(line)

    # Process last commit
    if current_lines:
        commit = parse_single_commit(current_lines, current_numstats, include_stats, omit_body)
        if commit:
            commits.append(commit)

    return commits


def parse_single_commit(lines, numstat_lines=None, include_stats=True, omit_body=False):
    """Parse a single commit from accumulated lines

    Args:
        lines: List of lines containing commit metadata and body
        numstat_lines: Optional list of numstat lines (N\tM\tfilename format)
        include_stats: Whether to include stats field in output (default: True)
        omit_body: Whether to omit body text from output (default: False)

    Returns None if parsing fails.

    Format (15 fields):
    hash|~|short|~|author_name|~|author_email|~|committer_name|~|committer_email|~|
    author_date|~|author_date_rel|~|committer_date|~|committer_date_rel|~|tree|~|
    subject|~|body|~|parents|~|refs
    """
    if not lines:
        return None

    if numstat_lines is None:
        numstat_lines = []

    # First line has: hash|~|short|~|...|~|subject|~|<body starts>
    first_line = lines[0]

    # Join all lines and look for the parent/refs trailer at the end
    full_text = '\n'.join(lines)

    # The last |~| separator should be followed by refs (or empty string)
    # The second-to-last |~| separator should be followed by parent hashes (or empty)
    # Find these by looking from the end

    # Strategy: Split first line to get fields 0-11 (up to subject)
    # Then reconstruct the body from the remaining text
    # Then extract parents and refs from the end

    fields = first_line.split('|~|', 12)  # Split into at most 13 parts (0-12)
    if len(fields) < 13:
        return None

    hash_val = fields[0]
    hash_short = fields[1]
    author_name = fields[2]
    author_email = fields[3]
    committer_name = fields[4]
    committer_email = fields[5]
    author_date = fields[6]
    author_date_relative = fields[7]
    committer_date = fields[8]
    committer_date_relative = fields[9]
    tree_sha = fields[10]
    subject = fields[11]
    body_start = fields[12]  # This is the start of %B (which includes subject line again)

    # Now we need to extract the body, parents, and refs from the full text
    # The last line should end with: |~|parent_hashes|~|refs
    # Find the last two |~| separators

    last_sep = full_text.rfind('|~|')
    if last_sep == -1:
        # Malformed - no trailer
        return None

    refs_str = full_text[last_sep + 3:].strip()

    # Find second-to-last separator
    remaining = full_text[:last_sep]
    second_last_sep = remaining.rfind('|~|')
    if second_last_sep == -1:
        # Malformed
        return None

    parents_str = remaining[second_last_sep + 3:].strip()

    # Everything before that is the body
    body_end_pos = second_last_sep

    # Body starts after field 12 in first line
    first_line_prefix = '|~|'.join(fields[:12]) + '|~|'
    body_full = full_text[len(first_line_prefix):body_end_pos]

    # Extract subject and body from full body text
    body_parts = body_full.strip().split('\n', 1)
    body = body_parts[1].strip() if len(body_parts) > 1 else ""

    # Parse refs
    refs = []
    if refs_str:
        # Filter out numstat lines that got mixed into refs
        # Numstat lines contain \t characters
        if '\t' not in refs_str:
            for ref in refs_str.split(','):
                ref = ref.strip()
                if ' -> ' in ref:
                    parts = ref.split(' -> ')
                    refs.append(parts[0].strip())
                    refs.append(parts[1].strip())
                else:
                    refs.append(ref)

    # Parse parents - convert to GitHub-style objects
    parents = []
    if parents_str:
        for parent_sha in parents_str.split():
            parents.append({'sha': parent_sha})

    # Parse numstat lines
    stats = {
        'files_changed': 0,
        'insertions': 0,
        'deletions': 0
    }
    files = []  # Detailed file changes for GitHub compatibility

    for numstat_line in numstat_lines:
        parts = numstat_line.split('\t')
        if len(parts) >= 3:
            try:
                add = 0 if parts[0] == '-' else int(parts[0])
                delete = 0 if parts[1] == '-' else int(parts[1])
                filename = parts[2]
                stats['insertions'] += add
                stats['deletions'] += delete
                stats['files_changed'] += 1

                # Add file details to files array
                files.append({
                    'filename': filename,
                    'status': 'modified',  # Default status
                    'additions': add,
                    'deletions': delete,
                    'changes': add + delete
                })
            except ValueError:
                # Not a valid numstat line
                pass

    # Apply omit_body flag if requested
    if omit_body:
        body = None

    # Construct full message (GitHub compat)
    full_message = subject
    if body:
        full_message = subject + '\n\n' + body

    # Build commit object
    commit = {
        'sha': hash_val,
        'sha_short': hash_short,
        'author': {
            'name': author_name,
            'email': author_email,
            'date': author_date,
            'date_relative': author_date_relative
        },
        'committer': {
            'name': committer_name,
            'email': committer_email,
            'date': committer_date,
            'date_relative': committer_date_relative
        },
        'message': full_message,
        'subject': subject,
        'body': body if body else None,
        'tree': {'sha': tree_sha},
        'parents': parents,
        'refs': refs if refs else None
    }

    # Conditionally add stats field
    if include_stats:
        commit['stats'] = stats
        commit['files'] = files

    return commit


def main():
    parser = argparse.ArgumentParser(description='Format git log output as JSON')
    parser.add_argument('--with-stats', action='store_true',
                       help='Include file change statistics in output')
    parser.add_argument('--no-body', action='store_true',
                       help='Omit commit message body (subject only)')
    args = parser.parse_args()

    # Read all input
    lines = sys.stdin.readlines()

    # Parse commits with conditional stats and body
    commits = parse_log_with_stats(lines, include_stats=args.with_stats, omit_body=args.no_body)

    # Build output
    output = {
        'command': 'hug ll',
        'commits': commits,
        'summary': {'total_commits': len(commits)}
    }

    if commits:
        earliest = min(c['author']['date'] for c in commits)
        latest = max(c['author']['date'] for c in commits)
        output['summary']['date_range'] = {
            'earliest': earliest,
            'latest': latest
        }

    # Output compact JSON (spaces after : and , for readability but no newlines)
    # Use separators with spaces to match bash JSON output format
    print(json.dumps(output, separators=(', ', ': ')))


if __name__ == '__main__':
    main()
