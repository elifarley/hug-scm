#!/usr/bin/env python3
"""
Hug SCM - Commit Dependency Graph

Analyzes commit dependencies by identifying commits that modify the same files.
Reveals related changes that should be reviewed together or that form a logical
feature evolution.

Usage:
    python3 deps.py <commit-hash> [--depth=<n>] [--format=<format>]
    python3 deps.py --all [--threshold=<n>] [--format=<format>]

Input: Commit hash or --all for repository-wide analysis
Output: Dependency graph showing related commits

Example:
    python3 deps.py abc1234 --depth=2
    python3 deps.py --all --threshold=3
"""

import sys
import os
import json
import argparse
import subprocess
import signal
from collections import defaultdict
from typing import Dict, List, Set, Tuple, Optional
from functools import lru_cache


class TimeoutError(Exception):
    """Custom timeout exception."""
    pass


class timeout:
    """Context manager for timeout support using signal handling."""

    def __init__(self, seconds):
        self.seconds = seconds

    def __enter__(self):
        def handle_timeout(signum, frame):
            raise TimeoutError(f"Operation timed out after {self.seconds} seconds")

        signal.signal(signal.SIGALRM, handle_timeout)
        signal.alarm(self.seconds)

    def __exit__(self, type, value, traceback):
        signal.alarm(0)


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description='Analyze commit dependencies via file overlap'
    )
    parser.add_argument(
        'commit',
        nargs='?',
        help='Commit hash to analyze (for single commit mode)'
    )
    parser.add_argument(
        '--all',
        action='store_true',
        help='Analyze all commits in repository'
    )
    parser.add_argument(
        '--depth',
        type=int,
        default=1,
        help='Depth of dependency traversal (default: 1)'
    )
    parser.add_argument(
        '--threshold',
        type=int,
        default=2,
        help='Minimum file overlap for dependency (default: 2)'
    )
    parser.add_argument(
        '--since',
        default=None,
        help='Only consider commits since this date'
    )
    parser.add_argument(
        '--format',
        choices=['json', 'text', 'graph'],
        default='graph',
        help='Output format (default: graph)'
    )
    parser.add_argument(
        '--max-results',
        type=int,
        default=20,
        help='Maximum number of related commits to show (default: 20)'
    )

    return parser.parse_args()


def run_git_command(cmd: List[str], timeout_seconds: int = 60) -> str:
    """Run git command and return output with timeout protection."""
    try:
        with timeout(timeout_seconds):
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=True,
                timeout=timeout_seconds
            )
            return result.stdout.strip()
    except (subprocess.TimeoutExpired, TimeoutError) as e:
        print(f"Git command timed out: {' '.join(cmd)}", file=sys.stderr)
        return ""
    except subprocess.CalledProcessError as e:
        print(f"Error running git command: {e}", file=sys.stderr)
        return ""


def get_commit_info(commit_hash: str) -> Optional[Dict]:
    """
    Get commit information including hash, subject, author, and date.

    Returns: Dict with commit metadata or None if commit not found
    """
    output = run_git_command([
        'git', 'log', '-1',
        '--format=%H|%s|%an|%ai',
        commit_hash
    ])

    if not output:
        return None

    hash_val, subject, author, date = output.split('|', 3)

    return {
        'hash': hash_val[:7],  # Short hash
        'full_hash': hash_val,
        'subject': subject,
        'author': author,
        'date': date[:10]  # YYYY-MM-DD
    }


@lru_cache(maxsize=1000)
def get_commit_info_cached(commit_hash: str) -> Optional[Dict]:
    """
    Cached version of get_commit_info.

    Returns: Dict with commit metadata or None if commit not found
    """
    return get_commit_info(commit_hash)


def get_commit_files(commit_hash: str) -> Set[str]:
    """
    Get list of files modified in a commit.

    Returns: Set of file paths
    """
    # Use --root to handle initial commits properly
    output = run_git_command([
        'git', 'diff-tree', '--no-commit-id', '--name-only', '-r', '--root',
        commit_hash
    ])

    if not output:
        return set()

    return set(line.strip() for line in output.split('\n') if line.strip())


@lru_cache(maxsize=500)
def get_commit_files_cached(commit_hash: str) -> frozenset:
    """
    Cached version of get_commit_files using immutable frozenset for LRU cache.

    Returns: frozenset of file paths
    """
    return frozenset(get_commit_files(commit_hash))


def detect_repository_size(commits: List[str]) -> str:
    """
    Detect repository size for strategy selection.

    Returns: 'small', 'medium', 'large', or 'massive'
    """
    commit_count = len(commits)
    if commit_count < 100:
        return "small"
    elif commit_count < 1000:
        return "medium"
    elif commit_count < 10000:
        return "large"
    else:
        return "massive"


def get_all_commits(since: Optional[str] = None) -> List[str]:
    """
    Get all commit hashes in the repository.

    Returns: List of commit hashes (newest first)
    """
    cmd = ['git', 'log', '--all', '--format=%H']

    if since:
        cmd.append(f'--since={since}')

    output = run_git_command(cmd)

    if not output:
        return []

    return [line.strip() for line in output.split('\n') if line.strip()]


def build_commit_file_index(commits: List[str]) -> Dict[str, Set[str]]:
    """
    Build index mapping each file to commits that modified it.

    Returns: Dict[filepath, Set[commit_hashes]]
    """
    file_to_commits = defaultdict(set)

    for commit_hash in commits:
        files = get_commit_files(commit_hash)
        for filepath in files:
            file_to_commits[filepath].add(commit_hash)

    return dict(file_to_commits)


def find_related_commits(
    commit_hash: str,
    file_to_commits: Dict[str, Set[str]],
    threshold: int = 2
) -> List[Tuple[str, int]]:
    """
    Find commits related to the given commit via file overlap.

    Returns: List of (commit_hash, overlap_count) tuples, sorted by overlap
    """
    # Get files modified by target commit (cached)
    target_files = get_commit_files_cached(commit_hash)

    if not target_files:
        return []

    # Count overlaps with other commits
    overlap_counts = defaultdict(int)

    for filepath in target_files:
        related_commits = file_to_commits.get(filepath, set())
        for related_commit in related_commits:
            if related_commit != commit_hash:
                overlap_counts[related_commit] += 1

    # Filter by threshold and sort by overlap count
    related = [
        (commit, count)
        for commit, count in overlap_counts.items()
        if count >= threshold
    ]

    related.sort(key=lambda x: x[1], reverse=True)

    return related


def build_dependency_graph(
    root_commit: str,
    file_to_commits: Dict[str, Set[str]],
    depth: int = 1,
    threshold: int = 2,
    max_results: int = 20,
    max_commits: int = 1000
) -> Dict[str, List[Tuple[str, int]]]:
    """
    Build dependency graph starting from root commit.

    Returns: Dict mapping each commit to its related commits with overlap counts
    """
    graph = {}
    visited = set()
    to_visit = [(root_commit, 0)]  # (commit, current_depth)
    processed_commits = 0

    while to_visit and processed_commits < max_commits:
        current_commit, current_depth = to_visit.pop(0)

        if current_commit in visited:
            continue

        visited.add(current_commit)
        processed_commits += 1

        # Find related commits with timeout protection
        try:
            with timeout(30):  # 30 second timeout for each commit analysis
                related = find_related_commits(current_commit, file_to_commits, threshold)
        except TimeoutError:
            print(f"Timeout analyzing commit {current_commit[:8]}, skipping", file=sys.stderr)
            related = []

        # Limit results
        related = related[:max_results]

        graph[current_commit] = related

        # Add related commits for traversal if within depth limit
        if current_depth < depth:
            for related_commit, _ in related:
                if related_commit not in visited and len(to_visit) < max_commits:
                    to_visit.append((related_commit, current_depth + 1))

    return graph


def format_graph_output(
    root_commit: str,
    graph: Dict[str, List[Tuple[str, int]]],
    depth: int
) -> str:
    """Format dependency graph as ASCII tree."""
    lines = []

    root_info = get_commit_info(root_commit)
    if not root_info:
        return f"Error: Commit {root_commit} not found"

    root_files = get_commit_files(root_commit)

    lines.append(f"Dependency graph for commit {root_info['hash']}:")
    lines.append(f"{root_info['subject']}")
    lines.append(f"Author: {root_info['author']}, Date: {root_info['date']}")
    lines.append(f"Files modified: {len(root_files)}")
    lines.append("")

    if root_commit not in graph or not graph[root_commit]:
        lines.append("No related commits found (no file overlap above threshold).")
        return '\n'.join(lines)

    lines.append(f"Related commits (depth={depth}):")
    lines.append("")

    # Format as tree
    def format_commit_node(commit_hash: str, overlap: int, prefix: str, is_last: bool):
        """Format a single commit node in the tree."""
        info = get_commit_info(commit_hash)
        if not info:
            return []

        node_lines = []

        connector = "└─" if is_last else "├─"
        node_lines.append(
            f"{prefix}{connector} {info['hash']} ({overlap} files) {info['subject']}"
        )
        node_lines.append(
            f"{prefix}{'   ' if is_last else '│  '}   {info['author']}, {info['date']}"
        )

        return node_lines

    # Show first level of dependencies
    related = graph.get(root_commit, [])
    for i, (commit_hash, overlap) in enumerate(related):
        is_last = (i == len(related) - 1)
        node_lines = format_commit_node(commit_hash, overlap, "", is_last)
        lines.extend(node_lines)

    if len(related) == 0:
        lines.append("  (none)")

    return '\n'.join(lines)


def format_text_output(
    root_commit: str,
    graph: Dict[str, List[Tuple[str, int]]]
) -> str:
    """Format dependency graph as simple text list."""
    lines = []

    root_info = get_commit_info(root_commit)
    if not root_info:
        return f"Error: Commit {root_commit} not found"

    lines.append(f"Related commits for {root_info['hash']} ({root_info['subject']}):")
    lines.append("")

    related = graph.get(root_commit, [])

    if not related:
        lines.append("No related commits found.")
        return '\n'.join(lines)

    for commit_hash, overlap in related:
        info = get_commit_info(commit_hash)
        if info:
            lines.append(
                f"{info['hash']}  {info['subject'][:60]:60s}  "
                f"({overlap} files)  {info['date']}"
            )

    return '\n'.join(lines)


def format_json_output(
    root_commit: str,
    graph: Dict[str, List[Tuple[str, int]]]
) -> str:
    """Format dependency graph as JSON."""
    result = {
        'root_commit': root_commit,
        'dependencies': {}
    }

    for commit_hash, related_list in graph.items():
        info = get_commit_info(commit_hash)
        if not info:
            continue

        related_commits = []
        for related_hash, overlap in related_list:
            related_info = get_commit_info(related_hash)
            if related_info:
                related_commits.append({
                    'hash': related_info['hash'],
                    'full_hash': related_info['full_hash'],
                    'subject': related_info['subject'],
                    'author': related_info['author'],
                    'date': related_info['date'],
                    'file_overlap': overlap
                })

        result['dependencies'][commit_hash] = {
            'info': info,
            'related': related_commits
        }

    return json.dumps(result, indent=2)


def analyze_all_commits(
    commits: List[str],
    file_to_commits: Dict[str, Set[str]],
    threshold: int,
    max_results: int
) -> Dict[str, List[Tuple[str, int]]]:
    """
    Analyze all commits and find highly coupled commit pairs.

    Returns: Dict of commits with their most related commits
    """
    high_coupling = {}

    for commit in commits:
        related = find_related_commits(commit, file_to_commits, threshold)
        if related:
            high_coupling[commit] = related[:max_results]

    return high_coupling


def format_all_commits_output(
    coupling: Dict[str, List[Tuple[str, int]]],
    threshold: int,
    output_format: str
) -> str:
    """Format repository-wide coupling analysis."""
    if output_format == 'json':
        result = {
            'threshold': threshold,
            'total_commits_with_dependencies': len(coupling),
            'coupling': {}
        }

        for commit, related in coupling.items():
            info = get_commit_info(commit)
            if info:
                result['coupling'][commit] = {
                    'info': info,
                    'related_count': len(related),
                    'top_related': [
                        {
                            'hash': get_commit_info(r[0])['hash'],
                            'subject': get_commit_info(r[0])['subject'],
                            'overlap': r[1]
                        }
                        for r in related[:5] if get_commit_info(r[0])
                    ]
                }

        return json.dumps(result, indent=2)

    # Text format
    lines = []
    lines.append(f"Commit Coupling Analysis (threshold: {threshold} files):")
    lines.append("")
    lines.append(f"Found {len(coupling)} commits with dependencies")
    lines.append("")

    # Sort by most related commits
    sorted_commits = sorted(
        coupling.items(),
        key=lambda x: (len(x[1]), max((r[1] for r in x[1]), default=0)),
        reverse=True
    )

    for commit, related in sorted_commits[:20]:  # Show top 20
        info = get_commit_info(commit)
        if not info:
            continue

        lines.append(f"{info['hash']} {info['subject']}")
        lines.append(f"  {len(related)} related commits:")

        for related_hash, overlap in related[:5]:  # Show top 5 related
            related_info = get_commit_info(related_hash)
            if related_info:
                lines.append(
                    f"    {related_info['hash']} ({overlap} files) "
                    f"{related_info['subject'][:50]}"
                )

        if len(related) > 5:
            lines.append(f"    ... and {len(related) - 5} more")

        lines.append("")

    if len(sorted_commits) > 20:
        lines.append(f"... and {len(sorted_commits) - 20} more commits")

    return '\n'.join(lines)


def main():
    """Main entry point."""
    args = parse_args()

    # Validate arguments
    if not args.commit and not args.all:
        print("Error: Must provide commit hash or --all flag", file=sys.stderr)
        print("\nUsage:", file=sys.stderr)
        print("  python3 deps.py <commit-hash> [options]", file=sys.stderr)
        print("  python3 deps.py --all [options]", file=sys.stderr)
        return 1

    # Get all commits for indexing
    all_commits = get_all_commits(args.since)

    if not all_commits:
        print("Error: No commits found", file=sys.stderr)
        return 1

    # Detect repository size for strategy selection
    repo_size = detect_repository_size(all_commits)

    # Adjust parameters based on repository size
    if repo_size == "small":
        max_commits_limit = 500
        default_timeout = 30
    elif repo_size == "medium":
        max_commits_limit = 1000
        default_timeout = 60
    elif repo_size == "large":
        max_commits_limit = 2000
        default_timeout = 90
    else:  # massive
        max_commits_limit = 5000
        default_timeout = 120

    # Apply environment overrides
    max_commits_limit = int(os.environ.get('HUG_ANALYZE_DEPS_MAX_COMMITS', max_commits_limit))

    # Build file-to-commits index
    file_to_commits = build_commit_file_index(all_commits)

    if args.all:
        # Analyze all commits
        coupling = analyze_all_commits(
            all_commits,
            file_to_commits,
            args.threshold,
            args.max_results
        )

        print(format_all_commits_output(coupling, args.threshold, args.format))
    else:
        # Single commit analysis
        commit = args.commit

        # Validate commit exists
        commit_info = get_commit_info(commit)
        if not commit_info:
            print(f"Error: Commit {commit} not found", file=sys.stderr)
            return 1

        # Build dependency graph with repository size limits
        graph = build_dependency_graph(
            commit_info['full_hash'],
            file_to_commits,
            args.depth,
            args.threshold,
            args.max_results,
            max_commits_limit
        )

        # Format output
        if args.format == 'json':
            print(format_json_output(commit_info['full_hash'], graph))
        elif args.format == 'text':
            print(format_text_output(commit_info['full_hash'], graph))
        else:  # graph
            print(format_graph_output(commit_info['full_hash'], graph, args.depth))

    return 0


if __name__ == '__main__':
    sys.exit(main())
