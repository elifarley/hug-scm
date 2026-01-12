#!/usr/bin/env python3
"""
Hug Git Branch Library - Python implementation

Provides branch information retrieval with upstream tracking.
Replaces hug-git-branch bash library (v1 with namerefs).

This module maintains API compatibility with the bash library while using
proper data structures (dataclasses) instead of nameref pass-by-reference.
"""

from dataclasses import dataclass, field
from typing import List, Optional, Callable
from enum import Enum
import subprocess
import json
import sys
import re


class BranchType(Enum):
    """Branch type classification."""
    LOCAL = "local"
    REMOTE = "remote"
    WIP = "wip"


@dataclass
class BranchInfo:
    """Single branch information."""
    name: str
    hash: str
    subject: str = ""
    track: str = ""  # e.g., "[origin/main: 2 ahead, 1 behind]"
    remote_ref: str = ""  # Full remote ref for remote branches


@dataclass
class BranchDetails:
    """Complete branch listing result."""
    current_branch: str
    max_len: int
    branches: List[BranchInfo]

    def to_json(self) -> str:
        """Serialize to JSON for bash consumption.

        Returns a JSON object with current_branch, max_len, and branches array.
        Each branch has name, hash, subject, track, and remote_ref fields.
        """
        return json.dumps({
            'current_branch': self.current_branch,
            'max_len': self.max_len,
            'branches': [
                {
                    'name': b.name,
                    'hash': b.hash,
                    'subject': b.subject,
                    'track': b.track,
                    'remote_ref': b.remote_ref,
                }
                for b in self.branches
            ]
        })

    def to_bash_declare(self) -> str:
        """Format as bash variable declarations.

        Outputs bash 'declare' statements that can be eval'd to set variables:
        - current_branch (scalar)
        - max_len (scalar)
        - branches (array)
        - hashes (array)
        - tracks (array)
        - subjects (array)
        - remote_refs (array, only for remote branches)

        All strings are properly escaped for safe bash evaluation.
        Arrays maintain consistent lengths (all same size).
        """
        lines = []

        # Scalar variables
        lines.append(f"declare current_branch={_bash_escape(self.current_branch)}")
        lines.append(f"declare max_len={self.max_len}")

        # Build arrays - use space-separated values for bash arrays
        branches_arr = " ".join(_bash_escape(b.name) for b in self.branches)
        hashes_arr = " ".join(_bash_escape(b.hash) for b in self.branches)
        tracks_arr = " ".join(_bash_escape(b.track) for b in self.branches)
        subjects_arr = " ".join(_bash_escape(b.subject) for b in self.branches)

        lines.append(f"declare -a branches=({branches_arr})")
        lines.append(f"declare -a hashes=({hashes_arr})")
        lines.append(f"declare -a tracks=({tracks_arr})")
        lines.append(f"declare -a subjects=({subjects_arr})")

        # Add remote_refs array if any branch has a remote_ref (for remote branches)
        if any(b.remote_ref for b in self.branches):
            remote_refs_arr = " ".join(_bash_escape(b.remote_ref) for b in self.branches)
            lines.append(f"declare -a remote_refs=({remote_refs_arr})")

        return "\n".join(lines)


def _bash_escape(s: str) -> str:
    """Escape string for safe bash declare usage.

    Uses single quotes with inner quote escaping for maximum compatibility.
    Handles: backslashes, single quotes, and most special characters.

    Strategy: '...' with '\'' for embedded single quotes.
    """
    s = s.replace('\\', '\\\\')  # Backslashes first (order matters)
    s = s.replace("'", "'\\''")   # Single quotes
    return f"'{s}'"


def _run_git(args: List[str], check: bool = True) -> str:
    """Run git command and return stdout.

    Args:
        args: Git command arguments (without 'git' prefix)
        check: If True, raise CalledProcessError on non-zero exit

    Returns:
        Command stdout as string, stripped of trailing whitespace

    Raises:
        subprocess.CalledProcessError: If command fails and check=True
    """
    result = subprocess.run(
        ['git'] + args,
        capture_output=True,
        text=True,
        check=check
    )
    return result.stdout.rstrip('\n\r')


def _run_git_for_each_ref(format_str: str, ref_pattern: str) -> List[str]:
    """Run git for-each-ref with null-delimited output.

    Args:
        format_str: Format string for --format (uses %00 as delimiter)
        ref_pattern: Ref pattern to query (e.g., 'refs/heads/')

    Returns:
        List of null-delimited field values
    """
    output = _run_git([
        'for-each-ref',
        '--format=' + format_str,
        '--sort=refname',
        ref_pattern
    ], check=False)
    if not output:
        return []
    return output.split('\0')


def _sanitize_string(s: str) -> str:
    """Remove all leading/trailing whitespace from string.

    Critical for robust string comparisons in branch names and subjects.
    Removes newlines, carriage returns, and other whitespace from both ends.
    """
    return s.strip()


def _compute_divergence(branch: str, upstream: str) -> tuple[str, str, str]:
    """Compute ahead/behind divergence for a branch relative to upstream.

    Args:
        branch: Local branch name
        upstream: Upstream branch name

    Returns:
        Tuple of (status_string, ahead, behind) where status_string is formatted
        like "[ahead 2, behind 1]" or empty if no divergence
    """
    try:
        divergence = _run_git([
            'rev-list', '--left-right', '--count',
            f'{branch}...{upstream}'
        ], check=False)
        if not divergence:
            return '', '0', '0'

        parts = divergence.split('\t')
        if len(parts) != 2:
            return '', '0', '0'

        ahead, behind = parts[0], parts[1]

        if ahead != '0' and behind != '0':
            return f'[ahead {ahead}, behind {behind}]', ahead, behind
        elif ahead != '0':
            return f'[ahead {ahead}]', ahead, behind
        elif behind != '0':
            return f'[behind {behind}]', ahead, behind

        return '', ahead, behind
    except subprocess.CalledProcessError:
        return '', '0', '0'


def get_local_branch_details(
    include_subjects: bool = True,
    exclude_backup: bool = True,
    batch_divergence: bool = True,
) -> Optional[BranchDetails]:
    """Get local branch details with upstream tracking.

    Args:
        include_subjects: Include commit subject messages
        exclude_backup: Exclude hug-backup/* branches
        batch_divergence: Use parallel divergence calculation for 5+ branches

    Returns:
        BranchDetails object or None if no branches exist

    Raises:
        subprocess.CalledProcessError: If git commands fail
    """
    # Get current branch
    current_branch = _run_git(['branch', '--show-current'], check=False)
    if not current_branch:
        current_branch = 'detached HEAD'

    # Build format string - include upstream and upstream:track for divergence info
    format_str = '%(refname:short)%00%(objectname:short)'
    if include_subjects:
        format_str += '%00%(subject)'
    format_str += '%00%(upstream:short)%00%(upstream:track)%00'

    # Get branch data
    git_output = _run_git_for_each_ref(format_str, 'refs/heads/')
    if not git_output:
        return None

    branches: List[BranchInfo] = []
    max_len = 0
    divergence_commands: List[tuple[int, str, str]] = []  # (index, branch, upstream)

    # Parse output in chunks
    chunk_size = 5 if include_subjects else 4
    for i in range(0, len(git_output) - chunk_size + 1, chunk_size):
        branch = _sanitize_string(git_output[i])
        hash_val = git_output[i + 1]

        # Skip backup branches
        if exclude_backup and branch.startswith('hug-backups/'):
            continue

        subject = ''
        if include_subjects:
            subject = _sanitize_string(git_output[i + 2])
            upstream_idx = i + 3
            track_idx = i + 4
        else:
            upstream_idx = i + 2
            track_idx = i + 3

        upstream = _sanitize_string(git_output[upstream_idx])
        upstream_track = _sanitize_string(git_output[track_idx])

        # Update max length
        if len(branch) > max_len:
            max_len = len(branch)

        # Store upstream info for divergence calculation
        if upstream and batch_divergence:
            divergence_commands.append((len(branches), branch, upstream))

        # Build initial track string (without divergence info)
        track = ''
        if upstream:
            track = f'[{upstream}]'

        branches.append(BranchInfo(
            name=branch,
            hash=hash_val,
            subject=subject,
            track=track,
        ))

    if not branches:
        return None

    # Batch compute divergence if requested and there are upstreams
    divergence_results: dict[int, str] = {}

    if batch_divergence and divergence_commands:
        for idx, branch, upstream in divergence_commands:
            status, _, _ = _compute_divergence(branch, upstream)
            if status:
                # Replace simple [upstream] with [upstream: status]
                divergence_results[idx] = status

    # Update track strings with divergence info
    for idx, branch_info in enumerate(branches):
        if idx in divergence_results:
            # Add divergence info to track string
            upstream_name = branch_info.track[1:-1]  # Remove [ and ]
            branch_info.track = f'[{upstream_name}: {divergence_results[idx]}]'

    return BranchDetails(
        current_branch=current_branch,
        max_len=max_len,
        branches=branches,
    )


def get_remote_branch_details(
    include_subjects: bool = True,
    exclude_backup: bool = True,
) -> Optional[BranchDetails]:
    """Get remote branch details.

    Args:
        include_subjects: Include commit subject messages
        exclude_backup: Exclude hug-backup/* remote branches

    Returns:
        BranchDetails object or None if no remote branches exist
    """
    # Build format string
    format_str = '%(refname:short)%00%(objectname:short)'
    if include_subjects:
        format_str += '%00%(subject)'
    format_str += '%00'

    # Get remote branch data
    git_output = _run_git_for_each_ref(format_str, 'refs/remotes/')
    if not git_output:
        return None

    branches: List[BranchInfo] = []
    max_len = 0

    # Parse output in chunks
    chunk_size = 3 if include_subjects else 2
    for i in range(0, len(git_output) - chunk_size + 1, chunk_size):
        remote_ref = _sanitize_string(git_output[i])

        # Skip HEAD references
        if not remote_ref or remote_ref.endswith('/HEAD'):
            continue

        # Skip backup branches
        if exclude_backup and remote_ref.startswith('hug-backups/'):
            continue

        hash_val = git_output[i + 1]

        subject = ''
        if include_subjects:
            subject = _sanitize_string(git_output[i + 2])

        # Extract local branch name by stripping remote prefix (e.g., "origin/feature" -> "feature")
        parts = remote_ref.split('/', 1)
        branch = parts[1] if len(parts) > 1 else remote_ref

        if not branch or branch == remote_ref:
            continue

        if len(branch) > max_len:
            max_len = len(branch)

        branches.append(BranchInfo(
            name=branch,
            hash=hash_val,
            subject=subject,
            remote_ref=remote_ref,
        ))

    if not branches:
        return None

    return BranchDetails(
        current_branch='',  # No concept of "current" for remote branches
        max_len=max_len,
        branches=branches,
    )


def get_wip_branch_details(
    include_subjects: bool = True,
    ref_pattern: str = 'refs/heads/WIP/',
) -> Optional[BranchDetails]:
    """Get WIP/temporary branch details.

    Args:
        include_subjects: Include commit subject messages
        ref_pattern: Git ref pattern to search (default: refs/heads/WIP/)

    Returns:
        BranchDetails object with branches matching WIP patterns
    """
    format_str = '%(refname:short)%00%(objectname:short)'
    if include_subjects:
        format_str += '%00%(subject)'
    format_str += '%00'

    git_output = _run_git_for_each_ref(format_str, ref_pattern)
    if not git_output:
        return None

    branches: List[BranchInfo] = []
    max_len = 0

    chunk_size = 3 if include_subjects else 2
    for i in range(0, len(git_output) - chunk_size + 1, chunk_size):
        branch = _sanitize_string(git_output[i])
        if not branch:
            continue

        hash_val = git_output[i + 1]

        subject = ''
        if include_subjects:
            subject = _sanitize_string(git_output[i + 2])

        if len(branch) > max_len:
            max_len = len(branch)

        branches.append(BranchInfo(
            name=branch,
            hash=hash_val,
            subject=subject,
        ))

    if not branches:
        return None

    return BranchDetails(
        current_branch='',  # No current branch concept for WIP listing
        max_len=max_len,
        branches=branches,
    )


def find_remote_branch(branch_name: str) -> Optional[str]:
    """Find a remote branch matching the given branch name.

    Args:
        branch_name: Branch name to search for (can be short name or full remote ref)

    Returns:
        Full remote ref name (e.g., "origin/feature") if found, None otherwise

    Note:
        If multiple remotes have the same branch, prefers "origin" if available,
        otherwise returns the first match alphabetically.
    """
    # If branch_name already looks like a remote ref, check if it exists
    if '/' in branch_name:
        try:
            _run_git(['show-ref', '--verify', '--quiet', f'refs/remotes/{branch_name}'])
            return branch_name
        except subprocess.CalledProcessError:
            pass

    # Get all remote branches, excluding HEAD
    output = _run_git(['for-each-ref', '--format=%(refname:short)', 'refs/remotes/'])
    remote_refs = [
        line for line in output.split('\n')
        if line and not line.endswith('/HEAD')
    ]

    # Find matches
    matches = []
    for remote_ref in remote_refs:
        ref_branch = remote_ref.split('/', 1)[1] if '/' in remote_ref else remote_ref
        if ref_branch == branch_name:
            matches.append(remote_ref)

    if not matches:
        return None

    if len(matches) == 1:
        return matches[0]

    # Prefer origin
    for match in matches:
        if match.startswith('origin/'):
            return match

    # Return first alphabetically
    return sorted(matches, key=str.lower)[0]


# CLI entry point for direct invocation from bash
def main():
    """CLI entry point for bash wrapper calls.

    Usage:
        python3 -m hug_git_branch <type> [options]

    Types:
        local     Local branches
        remote    Remote branches
        wip       WIP/temporary branches

    Options:
        --json            Output JSON instead of bash declarations
        --pattern PATTERN Ref pattern for WIP branches (default: refs/heads/WIP/)

    Outputs bash variable declarations by default, JSON with --json flag.
    Returns exit code 1 if no branches found or on error.
    """
    import argparse

    parser = argparse.ArgumentParser(
        description='Get git branch information for Hug SCM'
    )
    parser.add_argument(
        'type',
        choices=['local', 'remote', 'wip'],
        help='Branch type to query'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output JSON instead of bash declarations'
    )
    parser.add_argument(
        '--pattern',
        default='refs/heads/WIP/',
        help='Ref pattern for WIP branches (default: refs/heads/WIP/)'
    )

    args = parser.parse_args()

    try:
        # Get branch details based on type
        if args.type == 'local':
            details = get_local_branch_details(
                include_subjects=True,
                exclude_backup=True,
                batch_divergence=True
            )
        elif args.type == 'remote':
            details = get_remote_branch_details(
                include_subjects=True,
                exclude_backup=True
            )
        else:  # wip
            details = get_wip_branch_details(
                include_subjects=True,
                ref_pattern=args.pattern
            )

        # No branches found
        if not details or not details.branches:
            sys.exit(1)

        # Output based on format
        if args.json:
            print(details.to_json())
        else:
            print(details.to_bash_declare())

    except subprocess.CalledProcessError:
        sys.exit(1)
    except Exception as e:
        print(f'Error: {e}', file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
