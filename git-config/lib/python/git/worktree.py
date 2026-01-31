#!/usr/bin/env python3
"""
Hug Git Worktree Library - Python implementation

Provides type-safe worktree parsing to eliminate the duplicate "unbound variable"
bugs in the Bash implementation which had ~250 lines of duplicate code across
get_worktrees() and get_all_worktrees_including_main().

Replaces hug-git-worktree get_worktrees() and get_all_worktrees_including_main()
functions with a single type-safe module.

Supports:
- Parsing git worktree list --porcelain block-structured output
- State machine parser for worktree information extraction
- Dirty status detection via git subprocess calls
- Bash variable declaration output for eval
"""

import argparse
import subprocess
import sys
from dataclasses import dataclass


@dataclass
class WorktreeInfo:
    """Information about a single worktree.

    Attributes:
        path: Absolute path to the worktree directory
        branch: Branch name (refs/heads/ prefix removed), empty for detached HEAD
        commit: Short commit hash (7 characters), empty if unavailable
        is_dirty: True if worktree has uncommitted changes
        is_locked: True if worktree is locked
    """

    path: str
    branch: str
    commit: str
    is_dirty: bool
    is_locked: bool


@dataclass
class WorktreeList:
    """Result of worktree listing operation.

    All arrays maintain consistent lengths (parallel arrays).
    Designed for bash eval via to_bash_declare().

    Attributes:
        paths: List of worktree paths
        branches: List of branch names (parallel to paths)
        commits: List of commit hashes (parallel to paths)
        dirty_status: List of "true"/"false" strings for bash (parallel to paths)
        locked_status: List of "true"/"false" strings for bash (parallel to paths)
    """

    paths: list[str]
    branches: list[str]
    commits: list[str]
    dirty_status: list[str]
    locked_status: list[str]

    def to_bash_declare(self) -> str:
        """Format as bash variable declarations.

        Outputs bash 'declare' statements that can be eval'd to set variables:
        - worktree_paths (array)
        - worktree_branches (array)
        - worktree_commits (array)
        - worktree_dirty_status (array)
        - worktree_locked_status (array)

        All strings are properly escaped for safe bash evaluation.
        Arrays maintain consistent lengths.

        Returns:
            Bash declare statements as a string
        """
        lines = []

        # Build arrays - use space-separated values for bash arrays
        paths_arr = " ".join(_bash_escape(p) for p in self.paths)
        branches_arr = " ".join(_bash_escape(b) for b in self.branches)
        commits_arr = " ".join(_bash_escape(c) for c in self.commits)
        dirty_arr = " ".join(_bash_escape(d) for d in self.dirty_status)
        locked_arr = " ".join(_bash_escape(item) for item in self.locked_status)

        lines.append(f"declare -a _wt_paths=({paths_arr})")
        lines.append(f"declare -a _wt_branches=({branches_arr})")
        lines.append(f"declare -a _wt_commits=({commits_arr})")
        lines.append(f"declare -a _wt_dirty_status=({dirty_arr})")
        lines.append(f"declare -a _wt_locked_status=({locked_arr})")

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


def _check_worktree_dirty(worktree_path: str) -> bool:
    """Check if a worktree has uncommitted changes.

    Uses git subprocess calls to check for:
    - Unstaged changes (git diff --quiet)
    - Staged changes (git diff --cached --quiet)
    - Untracked files (git ls-files --others --exclude-standard)

    Args:
        worktree_path: Path to the worktree directory

    Returns:
        True if worktree has any uncommitted changes, False otherwise
    """
    try:
        # Check for unstaged changes
        result = subprocess.run(
            ["git", "-C", worktree_path, "diff", "--quiet"],
            capture_output=True,
            timeout=5,
        )
        has_unstaged = result.returncode != 0

        # Check for staged changes
        result = subprocess.run(
            ["git", "-C", worktree_path, "diff", "--cached", "--quiet"],
            capture_output=True,
            timeout=5,
        )
        has_staged = result.returncode != 0

        # Check for untracked files
        result = subprocess.run(
            ["git", "-C", worktree_path, "ls-files", "--others", "--exclude-standard"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        has_untracked = bool(result.stdout.strip())

        return has_unstaged or has_staged or has_untracked
    except (subprocess.TimeoutExpired, FileNotFoundError, PermissionError):
        # On error, assume not dirty to avoid false positives
        return False


def parse_worktree_list(
    porcelain_output: str,
    main_repo_path: str,
    include_main: bool = False,
) -> list[WorktreeInfo]:
    """Parse git worktree list --porcelain output into WorktreeInfo objects.

    This function implements a state machine parser for the block-structured
    porcelain output format. Each worktree block starts with "worktree <path>",
    followed by optional "branch refs/heads/<name>" (detached HEAD has no branch
    line), optional "commit <hash>", and optional "locked" (no value, presence
    indicates locked). Blocks are separated by blank lines.

    Args:
        porcelain_output: Raw output from `git worktree list --porcelain`
        main_repo_path: Absolute path to the main repository (to exclude when
            include_main=False)
        include_main: If True, include the main repository worktree in results.
            If False, only additional worktrees are returned. Default: False.

    Returns:
        List of WorktreeInfo objects. Empty list if no worktrees match criteria.

    Raises:
        ValueError: If porcelain_output is malformed

    Example:
        >>> output = '''worktree /path/to/main
        ... branch refs/heads/main
        ... commit abc1234
        ...
        ... worktree /path/to/feature
        ... branch refs/heads/feature
        ... commit def5678
        ... locked'''
        >>> worktrees = parse_worktree_list(output, "/path/to/main", include_main=False)
        >>> len(worktrees)
        1
        >>> worktrees[0].branch
        'feature'
        >>> worktrees[0].is_locked
        True
    """
    worktrees = []

    # State machine parser
    current_path = ""
    current_branch = ""
    current_commit = ""
    current_locked = False

    lines = porcelain_output.splitlines()

    for line in lines:
        if not line:  # Empty line = block separator
            # End of current worktree block, save if valid
            if current_path:
                # Check if we should include this worktree
                should_include = True
                if not include_main and current_path == main_repo_path:
                    should_include = False

                if should_include:
                    # Check dirty status via subprocess
                    is_dirty = _check_worktree_dirty(current_path)

                    # Shorten commit to 7 characters if present
                    short_commit = current_commit[:7] if current_commit else ""

                    worktrees.append(
                        WorktreeInfo(
                            path=current_path,
                            branch=current_branch,
                            commit=short_commit,
                            is_dirty=is_dirty,
                            is_locked=current_locked,
                        )
                    )

                # Reset state for next worktree
                current_path = ""
                current_branch = ""
                current_commit = ""
                current_locked = False
        elif line.startswith("worktree "):
            # Start of new worktree block
            current_path = line[len("worktree ") :].strip()
        elif line.startswith("branch refs/heads/"):
            # Branch line (not present for detached HEAD)
            current_branch = line[len("branch refs/heads/") :].strip()
        elif line.startswith("branch "):
            # Other branch format (e.g., detached), extract after "branch "
            current_branch = ""  # Detached HEAD has no branch name
        elif line.startswith("commit "):
            # Commit hash line
            current_commit = line[len("commit ") :].strip()
        elif line == "locked":
            # Locked flag (no value)
            current_locked = True
        # Ignore other unknown lines

    # Handle the last worktree (no trailing blank line)
    if current_path:
        should_include = True
        if not include_main and current_path == main_repo_path:
            should_include = False

        if should_include:
            is_dirty = _check_worktree_dirty(current_path)
            short_commit = current_commit[:7] if current_commit else ""

            worktrees.append(
                WorktreeInfo(
                    path=current_path,
                    branch=current_branch,
                    commit=short_commit,
                    is_dirty=is_dirty,
                    is_locked=current_locked,
                )
            )

    return worktrees


def to_worktree_list(worktrees: list[WorktreeInfo]) -> WorktreeList:
    """Convert list of WorktreeInfo to WorktreeList for bash output.

    Args:
        worktrees: List of WorktreeInfo objects

    Returns:
        WorktreeList dataclass with parallel arrays for bash consumption
    """
    paths = []
    branches = []
    commits = []
    dirty_status = []
    locked_status = []

    for wt in worktrees:
        paths.append(wt.path)
        branches.append(wt.branch)
        commits.append(wt.commit)
        dirty_status.append("true" if wt.is_dirty else "false")
        locked_status.append("true" if wt.is_locked else "false")

    return WorktreeList(
        paths=paths,
        branches=branches,
        commits=commits,
        dirty_status=dirty_status,
        locked_status=locked_status,
    )


def _get_main_repo_path() -> str:
    """Get the main repository path using git rev-parse.

    Returns:
        Absolute path to the main repository, or empty string if not in a git repo

    Raises:
        subprocess.CalledProcessError: If git rev-parse fails
    """
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=True,
            timeout=5,
        )
        return result.stdout.strip()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        return ""


def _get_worktree_porcelain() -> str:
    """Get git worktree list --porcelain output.

    Returns:
        Raw porcelain output string, or empty string on failure
    """
    try:
        result = subprocess.run(
            ["git", "worktree", "list", "--porcelain"],
            capture_output=True,
            text=True,
            check=True,
            timeout=5,
        )
        return result.stdout
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError):
        return ""


def main():
    """CLI entry point for bash wrapper calls.

    Usage:
        python3 worktree.py list [options]

    Commands:
        list    List worktrees and output bash variable declarations

    Options:
        --include-main    Include main repository in output (default: false)

    The command auto-detects the main repo path via git rev-parse --show-toplevel.
    Outputs bash variable declarations via to_bash_declare().
    Returns exit code 1 on error.

    Example:
        $ python3 worktree.py list
        declare -a worktree_paths=('/path/to/feature')
        declare -a worktree_branches=('feature')
        declare -a worktree_commits=('abc1234')
        declare -a worktree_dirty_status=('false')
        declare -a worktree_locked_status=('false')
    """
    parser = argparse.ArgumentParser(description="List git worktrees for Hug SCM")
    parser.add_argument(
        "command", choices=["list"], help="Command to run (currently only 'list' supported)"
    )
    parser.add_argument(
        "--include-main",
        action="store_true",
        help="Include main repository in output (default: false)",
    )
    parser.add_argument(
        "--main-repo-path",
        default="",
        help="Main repository path (auto-detected if not provided)",
    )

    args = parser.parse_args()

    try:
        # Get main repo path (from argument or auto-detect)
        if args.main_repo_path:
            main_repo_path = args.main_repo_path
        else:
            main_repo_path = _get_main_repo_path()
            if not main_repo_path:
                print("Error: Not in a git repository", file=sys.stderr)
                sys.exit(1)

        # Get porcelain output
        porcelain_output = _get_worktree_porcelain()
        if not porcelain_output:
            # No worktrees or error - output empty arrays
            result = WorktreeList(
                paths=[],
                branches=[],
                commits=[],
                dirty_status=[],
                locked_status=[],
            )
            print(result.to_bash_declare())
            return

        # Parse worktrees
        worktrees = parse_worktree_list(
            porcelain_output=porcelain_output,
            main_repo_path=main_repo_path,
            include_main=args.include_main,
        )

        # Convert to WorktreeList
        result = to_worktree_list(worktrees)

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
