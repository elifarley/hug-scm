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
import os
import subprocess
import sys
from dataclasses import dataclass, field


@dataclass
class WorktreeInfo:
    """Information about a single worktree.

    Attributes:
        path: Absolute path to the worktree directory
        branch: Branch name (refs/heads/ prefix removed), empty for detached HEAD
        commit: Short commit hash (7 characters), empty if unavailable
        is_dirty: True if worktree has uncommitted changes
        is_locked: True if worktree is locked
        missing: True if the worktree directory no longer exists on disk
        dirty_details: Tuple of dirty-category labels, e.g. ("unstaged", "untracked").
            Empty tuple when clean or missing. Uses tuple (not list) to avoid the
            mutable-default-argument pitfall.
        commit_date: Unix timestamp of the HEAD commit (committer date), 0 when
            unknown (detached HEAD lookup failure, missing commit object, etc.).
            Populated only when the caller requests recency data — see
            populate_commit_dates() and parse_worktree_list(include_dates=True).
    """

    path: str
    branch: str
    commit: str
    is_dirty: bool
    is_locked: bool
    missing: bool = False
    dirty_details: tuple = ()
    commit_date: int = 0


def format_indicators(is_dirty: bool, is_locked: bool) -> str:
    """Build 2-char indicator string for worktree display.

    Column layout: + #
      + = dirty (uncommitted changes present)
      # = locked (git worktree lock)
      . = inactive (placeholder for visual alignment)

    The * (current) and @ (detached) indicators are no longer columns --
    they are part of the branch display in the calling code (format_display_rows).

    WHY 2 columns instead of 4: The * and @ indicators convey branch context,
    not worktree state. Embedding them in the branch display keeps the indicator
    block focused on state flags and makes each row easier to scan at a glance.

    Args:
        is_dirty: True if the worktree has uncommitted changes.
        is_locked: True if the worktree is locked via git worktree lock.

    Returns:
        A 2-character string like "+#" or "..".
    """
    return "".join(
        [
            "+" if is_dirty else ".",
            "#" if is_locked else ".",
        ]
    )


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
        missing_status: List of "true"/"false" strings (parallel to paths).
            Not exposed in to_bash_declare — Bash derives (gone) from [[ -d ]].
        dirty_details_list: List of tuple[str, ...] (parallel to paths).
            Each tuple is a subset of ("staged", "unstaged", "untracked").
    """

    paths: list[str]
    branches: list[str]
    commits: list[str]
    dirty_status: list[str]
    locked_status: list[str]
    missing_status: list[str] = field(default_factory=list)
    dirty_details_list: list[tuple] = field(default_factory=list)
    commit_dates: list[int] = field(default_factory=list)

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

    def to_json(self, current_worktree: str = "") -> str:
        """Serialize to JSON format for API consumption.

        WHY: Replaces manual JSON construction in Bash output_worktree_json().
        Python's json module handles proper string escaping (quotes, backslashes,
        unicode) that Bash printf cannot safely do, preventing malformed JSON.

        Output format matches the existing contract:
        {"worktrees": [...], "current": "<path>", "count": <n>}

        Args:
            current_worktree: Absolute path of the current worktree for marking
                the "current" field in the JSON output.

        Returns:
            JSON string with worktree array and metadata.
        """
        import json

        worktrees = []
        for i, path in enumerate(self.paths):
            worktrees.append(
                {
                    "path": path,
                    "branch": self.branches[i],
                    "commit": self.commits[i],
                    "commit_date": self.commit_dates[i] if i < len(self.commit_dates) else 0,
                    "dirty": self.dirty_status[i] == "true",
                    "locked": self.locked_status[i] == "true",
                    "current": path == current_worktree,
                    "missing": self.missing_status[i] == "true"
                    if i < len(self.missing_status)
                    else False,
                    "dirty_details": list(self.dirty_details_list[i])
                    if i < len(self.dirty_details_list)
                    else [],
                }
            )

        return json.dumps(
            {
                "worktrees": worktrees,
                "current": current_worktree,
                "count": len(worktrees),
            }
        )


@dataclass
class WorktreeDirtyInfo:
    """Categorized dirty status for a worktree.

    Provides detailed breakdown of uncommitted changes, enabling user-friendly
    messages like "unstaged changes, untracked files" instead of just "dirty".

    Attributes:
        is_dirty: True if any uncommitted changes exist
        has_unstaged: True if working directory has modified tracked files
        has_staged: True if index has files ready to commit
        has_untracked: True if new files exist that aren't in git
        details: Human-readable summary (e.g., "unstaged changes, untracked files")
    """

    is_dirty: bool
    has_unstaged: bool
    has_staged: bool
    has_untracked: bool
    details: str


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
    info = _check_worktree_dirty_details(worktree_path)
    return info.is_dirty


def _check_worktree_dirty_details(worktree_path: str) -> WorktreeDirtyInfo:
    """Check if a worktree has uncommitted changes and categorize them.

    Uses git subprocess calls to check for three types of changes:
    - Unstaged changes: modified tracked files in working directory
    - Staged changes: files in index ready to commit
    - Untracked files: new files not in git

    Args:
        worktree_path: Path to the worktree directory

    Returns:
        WorktreeDirtyInfo with detailed breakdown of changes
    """
    # WHY: Stale worktrees (directory deleted externally) cause all three
    # git subprocess calls to fail with exit code 128. Without this guard,
    # each call takes up to 5 seconds (timeout) before failing — wasting
    # ~15 seconds per stale entry in listing commands.
    if not os.path.isdir(worktree_path):
        return WorktreeDirtyInfo(
            is_dirty=False,
            has_unstaged=False,
            has_staged=False,
            has_untracked=False,
            details="",
        )
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

        # Build human-readable details
        parts = []
        if has_unstaged:
            parts.append("unstaged changes")
        if has_staged:
            parts.append("staged changes")
        if has_untracked:
            parts.append("untracked files")
        details = ", ".join(parts)

        is_dirty = has_unstaged or has_staged or has_untracked

        return WorktreeDirtyInfo(
            is_dirty=is_dirty,
            has_unstaged=has_unstaged,
            has_staged=has_staged,
            has_untracked=has_untracked,
            details=details,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, PermissionError):
        # On error, assume clean to avoid false positives
        return WorktreeDirtyInfo(
            is_dirty=False,
            has_unstaged=False,
            has_staged=False,
            has_untracked=False,
            details="",
        )


def _dirty_detail_labels(info: WorktreeDirtyInfo) -> tuple[str, ...]:
    """Extract machine-readable dirty-category labels from a WorktreeDirtyInfo.

    WHY: JSON consumers and structured output need categorized labels
    ("staged", "unstaged", "untracked") rather than the human-readable
    comma-separated string in WorktreeDirtyInfo.details. This helper keeps
    the categorization logic DRY between parse_worktree_list (JSON enrichment)
    and the dirty subcommand.

    Args:
        info: WorktreeDirtyInfo from _check_worktree_dirty_details.

    Returns:
        Tuple of matching labels, e.g. ("unstaged", "untracked"). Empty if clean.
    """
    parts: list[str] = []
    if info.has_staged:
        parts.append("staged")
    if info.has_unstaged:
        parts.append("unstaged")
    if info.has_untracked:
        parts.append("untracked")
    return tuple(parts)


def _fetch_branch_commit_dates() -> dict[str, int]:
    """Fetch HEAD committer dates for all local branches in one git call.

    Uses 'git for-each-ref' with null-separated fields so branch names
    containing unusual characters survive parsing. Returns a mapping of
    short branch name -> committer date (unix seconds). On any failure
    (not a repo, git missing, timeout) an empty mapping is returned and
    callers degrade to date=0, which sort_worktrees() orders last.

    WHY one batch call: a naive per-branch 'git show -s' costs one
    subprocess per worktree. Worktree counts are small, but the batch
    call is one subprocess total and is the same idiom hug_git_branch.py
    already uses for bll listings.
    """
    try:
        result = subprocess.run(
            [
                "git",
                "for-each-ref",
                "--format=%(refname:strip=2)%00%(committerdate:unix)%00",
                "refs/heads/",
            ],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode != 0:
            return {}
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return {}

    dates: dict[str, int] = {}
    parts = result.stdout.split("\0")
    # Fields arrive in (name, ts, name, ts, ...) order; trailing empty
    # string from the final %00 is skipped by the range bound.
    for i in range(0, len(parts) - 1, 2):
        name = parts[i].strip()
        ts_raw = parts[i + 1].strip()
        if not name:
            continue
        try:
            dates[name] = int(ts_raw)
        except ValueError:
            dates[name] = 0
    return dates


def _fetch_detached_commit_dates(worktrees: list[WorktreeInfo]) -> dict[str, int]:
    """Fetch committer dates for detached-HEAD worktrees, keyed by short hash.

    Detached worktrees have no branch ref, so for-each-ref cannot date them.
    Exactly TWO git subprocesses date the whole set regardless of count:
      1. `git cat-file --batch-check` filters the short hashes down to the
         objects that actually exist (missing/corrupt hashes come back as
         "missing" lines, not errors).
      2. one `git show -s --format=%ct` call resolves all surviving hashes
         (git prints one %ct line per rev, in argument order).
    Any failure — missing hash, batch error, timeout — maps to date 0 so a
    single bad ref never breaks the listing, and the aggregate latency of a
    listing stays bounded at two subprocess invocations.

    Note: WorktreeInfo.commit holds the short hash, and git show accepts it,
    so we can resolve directly from the parsed data.
    """
    unique_commits = sorted({wt.commit for wt in worktrees if not wt.branch and wt.commit})
    if not unique_commits:
        return {}
    missing: dict[str, int] = dict.fromkeys(unique_commits, 0)

    # Stage 1: existence check for the whole batch in one call.
    try:
        check = subprocess.run(
            ["git", "cat-file", "--batch-check"],
            input="\n".join(unique_commits) + "\n",
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return missing
    if check.returncode != 0:
        return missing

    existing = [
        line.split()[0][:7]
        for line in check.stdout.splitlines()
        if line.strip() and not line.rstrip().endswith(" missing")
    ]
    if not existing:
        return missing

    # Stage 2: date all existing hashes in one git show call.
    try:
        result = subprocess.run(
            ["git", "--no-pager", "show", "-s", "--format=%ct"] + existing,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return missing
    if result.returncode != 0:
        return missing

    # One %ct line per rev, in argument order.
    for short_hash, line in zip(existing, result.stdout.splitlines(), strict=False):
        try:
            missing[short_hash] = int(line.strip())
        except ValueError:
            missing[short_hash] = 0
    return missing


def main_worktree_path_from_porcelain(porcelain_output: str) -> str:
    """Return the main checkout's path: the first block of `worktree list --porcelain`.

    Git guarantees the main worktree is listed first. Deriving the pin from
    the porcelain itself is robust against the CWD trap: when hug runs inside
    a LINKED worktree, `git rev-parse --show-toplevel` returns that worktree,
    not the main checkout — so any main-path computed from the CWD is wrong
    there. Empty string when there is no worktree block.
    """
    for line in porcelain_output.splitlines():
        if line.startswith("worktree "):
            return line[len("worktree ") :].strip()
    return ""


def populate_commit_dates(worktrees: list[WorktreeInfo]) -> list[WorktreeInfo]:
    """Fill in commit_date on each WorktreeInfo (mutates in place, returns arg).

    Branch worktrees resolve via one batch for-each-ref call; detached
    worktrees resolve per unique commit hash. Unknown dates stay 0.
    Only call this when a date-aware feature (--sort recent, JSON) needs it —
    it spawns one extra git subprocess.
    """
    branch_dates = _fetch_branch_commit_dates()
    detached_dates = _fetch_detached_commit_dates(worktrees)
    for wt in worktrees:
        if wt.branch:
            wt.commit_date = branch_dates.get(wt.branch, 0)
        else:
            wt.commit_date = detached_dates.get(wt.commit, 0)
    return worktrees


def sort_worktrees(
    worktrees: list[WorktreeInfo],
    mode: str,
    pinned_path: str,
) -> list[WorktreeInfo]:
    """Return worktrees reordered per mode; the pinned worktree always stays first.

    pinned_path is normally the MAIN checkout path (see
    main_worktree_path_from_porcelain — do NOT derive it from the CWD via
    `rev-parse --show-toplevel`, which points at a linked worktree when hug
    runs inside one). Callers may also pin a different path — e.g.
    worktree_select.py pins the CURRENT worktree so interactive menus keep
    the user's own checkout first; pass "" to pin nothing.

    Modes:
        name    — alphabetical by branch (fallback: path). This matches the
                  documented behavior of wtl/wtll and the de-facto order of
                  `git worktree list` (paths sort lexicographically, and hug's
                  canonical <repo>.WT.<branch> naming makes path order == branch
                  order for all hug-created worktrees).
        recent  — descending HEAD committer date (most recently active first).
        oldest  — ascending HEAD committer date (most recently active last),
                  mirroring git-bll's static-listing convention.

    The pinned worktree is exempted from reordering: when present it is pulled
    out of the list, the rest are sorted, and it is reinserted at the front.
    When the pinned path is NOT in the list (e.g. a filtered view whose search
    terms exclude the main checkout), no pinning occurs and the whole list is
    sorted uniformly — pinning an entry the user explicitly filtered out would
    resurrect it at a position it never earned. Entries with an unknown date
    (0) sink to the bottom under both recency orders; Python's stable sort
    preserves their relative name order.
    """

    # Unknown dates (0) sort last in both directions: under "recent" the
    # sentinel flag makes them the largest key (negated 0 is still 0, so a
    # bare negative cannot push them down); under "oldest" 0 is naturally
    # smallest, so the flag pushes them last. Python's sort is stable, so
    # unknown-date entries keep their relative name order from the tail.
    def _recency_key(w: WorktreeInfo) -> tuple:
        if mode == "recent":
            return (w.commit_date == 0, -w.commit_date)
        return (w.commit_date == 0, w.commit_date)

    if mode == "name":
        # Byte-order (NOT lowercased): this must reproduce the pre-sort
        # porcelain emission order exactly, which sorts linked-worktree
        # paths in byte order (uppercase before lowercase). Lowercasing
        # here reorders mixed-case branch names and silently churns the
        # default listing vs older builds.
        def key(w: WorktreeInfo):
            return w.branch or w.path
    else:
        key = _recency_key

    # Extract the pinned entry wherever it sits (unfiltered listings put main
    # first, but a filtered view may leave it mid-list or absent entirely).
    pinned: list[WorktreeInfo] = []
    rest: list[WorktreeInfo] = []
    for w in worktrees:
        if pinned_path and w.path == pinned_path and not pinned:
            pinned.append(w)
        else:
            rest.append(w)

    return pinned + sorted(rest, key=key)


def parse_worktree_list(
    porcelain_output: str,
    main_repo_path: str,
    include_main: bool = False,
    include_dates: bool = False,
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
        include_dates: If True, populate commit_date on each entry via
            populate_commit_dates(). Costs one batch git subprocess; enable
            only when the caller needs recency data. Default: False.

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
                    # WHY: Call _check_worktree_dirty_details directly (not the
                    # thin _check_worktree_dirty wrapper) so we get both the dirty
                    # boolean AND the categorized labels in a single subprocess
                    # round-trip.  Avoids 3 extra git invocations per worktree.
                    dirty_info = _check_worktree_dirty_details(current_path)
                    missing = not os.path.isdir(current_path)

                    # Shorten commit to 7 characters if present
                    short_commit = current_commit[:7] if current_commit else ""

                    worktrees.append(
                        WorktreeInfo(
                            path=current_path,
                            branch=current_branch,
                            commit=short_commit,
                            is_dirty=dirty_info.is_dirty,
                            is_locked=current_locked,
                            missing=missing,
                            dirty_details=_dirty_detail_labels(dirty_info),
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
        elif line.startswith("HEAD "):
            # HEAD hash line (git worktree list --porcelain outputs HEAD, not commit)
            current_commit = line[len("HEAD ") :].strip()
        elif line.startswith("commit "):
            # Commit hash line (legacy format, some git versions use this)
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
            dirty_info = _check_worktree_dirty_details(current_path)
            missing = not os.path.isdir(current_path)
            short_commit = current_commit[:7] if current_commit else ""

            worktrees.append(
                WorktreeInfo(
                    path=current_path,
                    branch=current_branch,
                    commit=short_commit,
                    is_dirty=dirty_info.is_dirty,
                    is_locked=current_locked,
                    missing=missing,
                    dirty_details=_dirty_detail_labels(dirty_info),
                )
            )

    if include_dates:
        populate_commit_dates(worktrees)

    return worktrees


def filter_by_branch(
    worktrees: list[WorktreeInfo],
    branch_filters: list[str],
) -> list[WorktreeInfo]:
    """Filter worktrees by exact branch name match (OR logic).

    When multiple branch filters are provided, a worktree matches if its branch
    equals ANY of the filters (OR logic). This matches the behavior of
    `hug wtl --branch f1 --branch f2`.

    Empty filter list returns all worktrees (no filtering).

    Args:
        worktrees: Candidate worktrees to filter.
        branch_filters: List of exact branch names to match against.

    Returns:
        Worktrees whose branch exactly matches at least one filter.
    """
    if not branch_filters:
        return list(worktrees)
    filter_set = set(branch_filters)
    return [wt for wt in worktrees if wt.branch in filter_set]


def filter_by_search(
    worktrees: list[WorktreeInfo],
    search_terms: list[str],
) -> list[WorktreeInfo]:
    """Filter worktrees by substring match on path or branch (OR logic).

    Each term in search_terms is checked independently (OR logic). For each
    worktree, if ANY term matches (case-insensitive) against EITHER the path
    OR the branch, the worktree is included.

    Empty or whitespace-only terms are stripped; if no terms remain after
    stripping, all worktrees are returned (no filtering).

    Args:
        worktrees: Candidate worktrees to filter.
        search_terms: List of individual search terms (one per --search flag).

    Returns:
        Worktrees matching at least one search term in path or branch.
    """
    if not search_terms:
        return list(worktrees)
    terms = [t.lower() for t in search_terms if t.strip()]
    if not terms:
        return list(worktrees)
    result = []
    for wt in worktrees:
        path_lower = wt.path.lower()
        branch_lower = (wt.branch or "").lower()
        for term in terms:
            if term in path_lower or term in branch_lower:
                result.append(wt)
                break
    return result


def filter_by_existing(worktrees: list[WorktreeInfo]) -> list[WorktreeInfo]:
    """Filter out worktrees whose directory no longer exists on disk.

    WHY: Stale worktrees (directory deleted externally but not pruned from git)
    should be excludable via --existing. The check is os.path.isdir which is
    fast (no subprocess) and matches the Bash [[ -d "$path" ]] semantics.

    Args:
        worktrees: Candidate worktrees to filter.

    Returns:
        Worktrees whose path directories still exist.
    """
    return [wt for wt in worktrees if os.path.isdir(wt.path)]


def filter_worktrees_by_criteria(
    worktrees: list[WorktreeInfo],
    branch_filters: list[str],
    search_terms: list[str],
    existing_only: bool = False,
) -> list[WorktreeInfo]:
    """Apply branch, search, and optional existing filters (AND logic between stages).

    Stage 1: branch filter (exact match, OR between branches)
    Stage 2: search filter (substring match, OR between terms)
    Stage 3: existing filter (exclude stale directories) — only if existing_only=True

    All stages must pass (AND logic). This matches the semantics of:
    `hug wtl --branch main /home -e` — branch is "main" AND path contains "/home"
    AND directory still exists.

    Args:
        worktrees: Candidate worktrees to filter.
        branch_filters: Exact branch names (OR logic within stage).
        search_terms: Individual search terms (OR logic within stage).
        existing_only: If True, exclude worktrees whose directories don't exist.

    Returns:
        Worktrees passing all filter stages.
    """
    result = filter_by_branch(worktrees, branch_filters)
    result = filter_by_search(result, search_terms)
    if existing_only:
        result = filter_by_existing(result)
    return result


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
    missing_status = []
    dirty_details_list = []
    commit_dates = []

    for wt in worktrees:
        paths.append(wt.path)
        branches.append(wt.branch)
        commits.append(wt.commit)
        dirty_status.append("true" if wt.is_dirty else "false")
        locked_status.append("true" if wt.is_locked else "false")
        missing_status.append("true" if wt.missing else "false")
        dirty_details_list.append(wt.dirty_details)
        commit_dates.append(wt.commit_date)

    return WorktreeList(
        paths=paths,
        branches=branches,
        commits=commits,
        dirty_status=dirty_status,
        locked_status=locked_status,
        missing_status=missing_status,
        dirty_details_list=dirty_details_list,
        commit_dates=commit_dates,
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
        python3 worktree.py dirty <path>

    Commands:
        list    List worktrees and output bash variable declarations
        dirty   Check dirty status of a worktree and output categorized details

    Options (for 'list'):
        --include-main    Include main repository in output (default: false)

    The command auto-detects the main repo path via git rev-parse --show-toplevel.
    Outputs bash variable declarations via to_bash_declare().
    Returns exit code 1 on error.
    """
    # Use subparsers for different commands
    parser = argparse.ArgumentParser(description="Git worktree helpers for Hug SCM")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # 'list' subcommand
    list_parser = subparsers.add_parser("list", help="List worktrees")
    list_parser.add_argument(
        "--include-main",
        action="store_true",
        help="Include main repository in output (default: false)",
    )
    list_parser.add_argument(
        "--main-repo-path",
        default="",
        help="Main repository path (auto-detected if not provided)",
    )
    list_parser.add_argument(
        "--sort",
        choices=["name", "recent", "oldest"],
        default="name",
        help=(
            "Sort order for non-main worktrees: name (alphabetical, default), "
            "recent (HEAD committer date, newest first), oldest (newest last). "
            "The main worktree always stays first."
        ),
    )

    # 'dirty' subcommand
    dirty_parser = subparsers.add_parser("dirty", help="Check worktree dirty status")
    dirty_parser.add_argument(
        "path",
        help="Worktree path to check",
    )

    # 'json' subcommand
    json_parser = subparsers.add_parser(
        "json",
        help="Output worktree list as JSON",
    )
    json_parser.add_argument(
        "--include-main",
        action="store_true",
        help="Include main repository in output (default: false)",
    )
    json_parser.add_argument(
        "--main-repo-path",
        default="",
        help="Main repository path (auto-detected if not provided)",
    )
    json_parser.add_argument(
        "--current",
        default="",
        help="Current worktree path for marking in JSON output",
    )
    json_parser.add_argument(
        "-b",
        "--branch",
        action="append",
        default=[],
        help="Filter by exact branch name (repeatable, OR logic).",
    )
    json_parser.add_argument(
        "--search",
        action="append",
        default=[],
        help="Search term (substring match on path/branch, repeatable, OR logic).",
    )
    json_parser.add_argument(
        "-e",
        "--existing",
        action="store_true",
        default=False,
        help="Exclude worktrees whose directory doesn't exist on disk.",
    )
    json_parser.add_argument(
        "--sort",
        choices=["name", "recent", "oldest"],
        default="name",
        help=(
            "Sort order for non-main worktrees: name (alphabetical, default), "
            "recent (HEAD committer date, newest first), oldest (newest last). "
            "The main worktree always stays first."
        ),
    )

    args = parser.parse_args()

    try:
        if args.command == "list":
            _handle_list_command(args)
        elif args.command == "dirty":
            _handle_dirty_command(args.path)
        elif args.command == "json":
            _handle_json_command(args)
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)


def _handle_list_command(args):
    """Handle the 'list' subcommand."""
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

    # Parse worktrees (dates only needed for recency-aware sort modes)
    worktrees = parse_worktree_list(
        porcelain_output=porcelain_output,
        main_repo_path=main_repo_path,
        include_main=args.include_main,
        include_dates=args.sort != "name",
    )

    # Pin the MAIN checkout (first porcelain block — CWD-independent) so the
    # primary worktree stays first regardless of sort mode.
    main_wt_path = main_worktree_path_from_porcelain(porcelain_output)
    worktrees = sort_worktrees(worktrees, args.sort, main_wt_path)

    # Convert to WorktreeList
    result = to_worktree_list(worktrees)

    # Output bash declarations
    print(result.to_bash_declare())


def _handle_dirty_command(path: str):
    """Handle the 'dirty' subcommand.

    Outputs bash declare statements for:
        _wt_dirty        - "true" or "false"
        _wt_dirty_details - human-readable details string
    """
    info = _check_worktree_dirty_details(path)
    print(f"_wt_dirty={'true' if info.is_dirty else 'false'}")
    print(f"_wt_dirty_details='{info.details}'")


def _handle_json_command(args):
    """Handle the 'json' subcommand.

    Loads worktrees, applies optional branch/search filters, and outputs JSON.
    WHY: Replaces manual JSON construction in Bash output_worktree_json().
    Python's json module ensures proper escaping of special characters.
    """
    import json

    # Get main repo path
    if args.main_repo_path:
        main_repo_path = args.main_repo_path
    else:
        main_repo_path = _get_main_repo_path()
        if not main_repo_path:
            print(json.dumps({"worktrees": [], "current": args.current, "count": 0}))
            return

    # Get porcelain output
    porcelain_output = _get_worktree_porcelain()
    if not porcelain_output:
        print(json.dumps({"worktrees": [], "current": args.current, "count": 0}))
        return

    # Parse worktrees. Dates are always populated for JSON: the commit_date
    # field is part of the JSON contract so consumers can re-sort cheaply.
    worktrees = parse_worktree_list(
        porcelain_output=porcelain_output,
        main_repo_path=main_repo_path,
        include_main=args.include_main,
        include_dates=True,
    )

    if not worktrees:
        print(json.dumps({"worktrees": [], "current": args.current, "count": 0}))
        return

    # Apply filters if provided
    if args.branch or args.search or args.existing:
        worktrees = filter_worktrees_by_criteria(
            worktrees, args.branch, args.search, existing_only=args.existing
        )

    # Pin the MAIN checkout (first porcelain block — CWD-independent).
    main_wt_path = main_worktree_path_from_porcelain(porcelain_output)
    worktrees = sort_worktrees(worktrees, args.sort, main_wt_path)

    if not worktrees:
        print(json.dumps({"worktrees": [], "current": args.current, "count": 0}))
        return

    # Convert to JSON
    result = to_worktree_list(worktrees)
    print(result.to_json(args.current))


if __name__ == "__main__":
    main()
