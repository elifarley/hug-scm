#!/usr/bin/env python3
"""Worktree validation functions for Hug SCM.

Moves validation logic from Bash (hug-git-worktree lines 404-559) to Python
for better testability and DRY compliance. Functions validate worktree paths,
creation paths, and branch availability.

Architecture: Python performs validation, Bash thin adapters call Python and
eval the output. This follows the established pattern: Python for computation,
Bash for CLI/UX.
"""

import argparse
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

# When run as a script, ensure package root is on sys.path
if __name__ == "__main__":
    _pkg_root = str(Path(__file__).resolve().parent.parent)
    if _pkg_root not in sys.path:
        sys.path.insert(0, _pkg_root)

from git.worktree import parse_worktree_list


@dataclass
class ValidationResult:
    """Result of a validation check.

    Attributes:
        is_valid: True if validation passed, False otherwise
        error_message: Human-readable error (empty if valid)
    """

    is_valid: bool
    error_message: str


def validate_worktree_path(path: str) -> ValidationResult:
    """Validate that a path is a valid, accessible worktree.

    Checks:
    - Path is not empty
    - Path exists
    - Path is a directory
    - Path is registered as a worktree (git worktree list --porcelain)
    - Path is readable

    Args:
        path: Worktree path to validate

    Returns:
        ValidationResult with is_valid and optional error_message
    """
    if not path:
        return ValidationResult(False, "Worktree path cannot be empty")

    # Convert to absolute path
    path = str(Path(path).resolve())

    if not os.path.exists(path):
        return ValidationResult(False, f"Worktree path does not exist: {path}")

    if not os.path.isdir(path):
        return ValidationResult(False, f"Worktree path is not a directory: {path}")

    # Check if it's actually a worktree
    if not _is_registered_worktree(path):
        return ValidationResult(False, f"Path is not a Git worktree: {path}")

    if not os.access(path, os.R_OK):
        return ValidationResult(False, f"No read permission for worktree: {path}")

    return ValidationResult(True, "")


def validate_creation_path(path: str, auto_create_parent: bool = True) -> ValidationResult:
    """Validate that a path is safe for worktree creation.

    Checks:
    - Path is not empty
    - Target doesn't already exist
    - Parent directory exists (or can be created)
    - Parent is writable
    - Path is not inside main repository

    Args:
        path: Target path for worktree creation
        auto_create_parent: If True, auto-create missing parent directories

    Returns:
        ValidationResult with is_valid and optional error_message
    """
    if not path:
        return ValidationResult(False, "Worktree path cannot be empty")

    # Convert to absolute path
    path = str(Path(path).resolve())

    if os.path.exists(path):
        return ValidationResult(
            False,
            f"Target path already exists: {path}\n"
            "Choose a different path or remove the existing directory",
        )

    parent_dir = os.path.dirname(path)

    if not os.path.isdir(parent_dir):
        if auto_create_parent:
            try:
                os.makedirs(parent_dir, exist_ok=True)
            except OSError:
                return ValidationResult(False, f"Cannot create parent directory: {parent_dir}")
        else:
            return ValidationResult(False, f"Parent directory does not exist: {parent_dir}")

    if not os.access(parent_dir, os.W_OK):
        return ValidationResult(False, f"No write permission to parent directory: {parent_dir}")

    # Check that path is not inside main repository
    main_repo = _get_main_repo_path()
    if main_repo and _is_path_inside(path, main_repo):
        return ValidationResult(
            False,
            f"Cannot create worktree inside main repository: {path}\n"
            "Choose a location outside the main repository",
        )

    return ValidationResult(True, "")


def branch_available(branch: str) -> tuple[bool, str]:
    """Check if a branch is available for worktree creation.

    A branch is available if:
    - It exists locally
    - It's not already checked out in any worktree

    Args:
        branch: Branch name to check

    Returns:
        Tuple of (is_available, error_message)
    """
    if not branch:
        return False, "Branch name cannot be empty"

    # Check if branch exists
    if not _branch_exists(branch):
        return False, f"Branch '{branch}' does not exist locally"

    # Check if branch is checked out elsewhere
    worktree_path = _get_worktree_for_branch(branch)
    if worktree_path:
        return False, f"Branch '{branch}' is already checked out at {worktree_path}"

    return True, ""


def generate_worktree_path(branch: str, main_path: str | None = None) -> str:
    """Generate a smart default worktree path for a branch.

    Pattern: ../<repo>.WT.<branch> (flat sibling, not nested)

    Design rationale:
    - Avoids breaking relative paths in git submodules
    - .WT. infix provides visual clarity in directory listings
    - Sanitizes branch name for filesystem safety

    Args:
        branch: Branch name
        main_path: Main repository path (auto-detected if None)

    Returns:
        Generated worktree path
    """
    if not main_path:
        main_path = _get_main_repo_path()
        if not main_path:
            # Fallback to /tmp if can't determine main path
            return f"/tmp/hug-wt-unknown-{os.getpid()}-{_sanitize_branch(branch)}"

    repo_name = os.path.basename(main_path)
    parent_dir = os.path.dirname(main_path)
    safe_branch = _sanitize_branch(branch)

    # Check if parent is writable
    if not os.access(parent_dir, os.W_OK):
        return f"/tmp/hug-wt-{repo_name}-{os.getpid()}-{safe_branch}"

    return f"{parent_dir}/{repo_name}.WT.{safe_branch}"


def generate_unique_worktree_path(branch: str, main_path: str | None = None) -> str:
    """Generate a unique worktree path that doesn't conflict with existing paths.

    Appends -1, -2, etc. to the base path until a non-existent path is found.

    Args:
        branch: Branch name
        main_path: Main repository path (auto-detected if None)

    Returns:
        Unique path that doesn't exist
    """
    base_path = generate_worktree_path(branch, main_path)

    if not os.path.exists(base_path):
        return base_path

    counter = 1
    while os.path.exists(f"{base_path}-{counter}"):
        counter += 1

    return f"{base_path}-{counter}"


# ============================================================================
# Internal helpers
# ============================================================================


def _sanitize_branch(branch: str) -> str:
    """Sanitize branch name for filesystem use.

    Converts:
    - / → -
    - . → -
    - uppercase → lowercase

    Args:
        branch: Raw branch name

    Returns:
        Sanitized branch name safe for filesystem
    """
    safe = branch.replace("/", "-").replace(".", "-")
    return safe.lower()


def _is_registered_worktree(path: str) -> bool:
    """Check if path is registered as a worktree.

    Args:
        path: Path to check

    Returns:
        True if path is in git worktree list
    """
    try:
        result = subprocess.run(
            ["git", "worktree", "list", "--porcelain"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode != 0:
            return False

        # Check if path appears in porcelain output
        return f"worktree {path}" in result.stdout
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False


def _branch_exists(branch: str) -> bool:
    """Check if a local branch exists.

    Args:
        branch: Branch name

    Returns:
        True if branch exists
    """
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--verify", f"refs/heads/{branch}"],
            capture_output=True,
            timeout=5,
        )
        return result.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False


def _get_worktree_for_branch(branch: str) -> str | None:
    """Get the worktree path where a branch is checked out.

    Args:
        branch: Branch name

    Returns:
        Worktree path or None if not checked out
    """
    try:
        result = subprocess.run(
            ["git", "worktree", "list", "--porcelain"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode != 0:
            return None

        worktrees = parse_worktree_list(result.stdout, "", include_main=True)
        for wt in worktrees:
            if wt.branch == branch:
                return wt.path
        return None
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None


def _get_main_repo_path() -> str:
    """Get the main repository path.

    Returns:
        Main repo path or empty string on failure
    """
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        return result.stdout.strip() if result.returncode == 0 else ""
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return ""


def _is_path_inside(path: str, parent: str) -> bool:
    """Check if path is inside or equal to parent.

    Uses resolved paths to handle symlinks and relative components.

    Args:
        path: Path to check
        parent: Parent directory

    Returns:
        True if path is inside or equal to parent
    """
    path_resolved = str(Path(path).resolve())
    parent_resolved = str(Path(parent).resolve())

    # Add trailing separator to ensure directory boundary matching
    parent_with_sep = parent_resolved + os.sep
    return path_resolved == parent_resolved or path_resolved.startswith(parent_with_sep)


# ============================================================================
# CLI entry point
# ============================================================================


def main():
    """CLI for worktree validation functions.

    Outputs bash declare statements for eval by Bash adapters.
    """
    parser = argparse.ArgumentParser(description="Worktree validation for Hug SCM")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # validate-path
    vp = subparsers.add_parser("validate-path", help="Validate worktree path")
    vp.add_argument("path", help="Worktree path")

    # validate-creation-path
    vcp = subparsers.add_parser("validate-creation-path", help="Validate creation path")
    vcp.add_argument("path", help="Target path")
    vcp.add_argument("--no-auto-create", action="store_true", help="Don't auto-create parent")

    # branch-available
    ba = subparsers.add_parser("branch-available", help="Check branch availability")
    ba.add_argument("branch", help="Branch name")

    # generate-path
    gp = subparsers.add_parser("generate-path", help="Generate worktree path")
    gp.add_argument("branch", help="Branch name")
    gp.add_argument("--main-path", default="", help="Main repo path")

    # generate-unique-path
    gup = subparsers.add_parser("generate-unique-path", help="Generate unique worktree path")
    gup.add_argument("branch", help="Branch name")
    gup.add_argument("--main-path", default="", help="Main repo path")

    args = parser.parse_args()

    try:
        if args.command == "validate-path":
            result = validate_worktree_path(args.path)
            print(f"_wt_valid={'true' if result.is_valid else 'false'}")
            print(f"_wt_error='{result.error_message}'")

        elif args.command == "validate-creation-path":
            auto_create = not args.no_auto_create
            result = validate_creation_path(args.path, auto_create_parent=auto_create)
            print(f"_wt_valid={'true' if result.is_valid else 'false'}")
            print(f"_wt_error='{result.error_message}'")

        elif args.command == "branch-available":
            available, error = branch_available(args.branch)
            print(f"_wt_available={'true' if available else 'false'}")
            print(f"_wt_error='{error}'")

        elif args.command == "generate-path":
            main_path = args.main_path if args.main_path else None
            path = generate_worktree_path(args.branch, main_path)
            print(f"_wt_path='{path}'")

        elif args.command == "generate-unique-path":
            main_path = args.main_path if args.main_path else None
            path = generate_unique_worktree_path(args.branch, main_path)
            print(f"_wt_path='{path}'")

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
