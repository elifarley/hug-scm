#!/usr/bin/env python3
"""
Hug SCM - Co-change Analysis

Analyzes which files frequently change together in commit history.

DESIGN NOTE:
This module intentionally supports two explicit modes:
1. file mode    -> "Given this file, what else usually changes with it?"
2. repo-wide    -> "Which file pairs are most strongly coupled overall?"

Keeping both modes in one helper ensures we have one correlation model, one
sorting policy, and one JSON/text formatting family. That reduces drift between
CLI modes and makes tests teach the same behavior the product exposes.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict


def parse_args() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Analyze co-change patterns from Git history")
    mode_group = parser.add_mutually_exclusive_group(required=True)
    mode_group.add_argument("--target-file", help="Analyze files related to this file")
    mode_group.add_argument("--all", action="store_true", help="Analyze all file pairs")
    parser.add_argument(
        "--commits", type=int, default=100, help="Number of commits to analyze (default: 100)"
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.30,
        help="Minimum correlation threshold (0.0-1.0, default: 0.30)",
    )
    parser.add_argument(
        "--format", choices=["json", "text"], default="text", help="Output format (default: text)"
    )
    parser.add_argument("--top", type=int, default=20, help="Show top N results (default: 20)")
    return parser.parse_args()


def parse_git_log(stdin_input: str) -> list[set[str]]:
    """
    Parse `git log --name-only --format=%H` output into a file set per commit.

    LESSON LEARNED:
    The helper receives raw streamed Git output because that keeps the Bash layer
    simple and lets the Python layer own the analysis semantics. We parse only
    the minimum structure needed: commit boundaries and file paths.
    """
    commits = []
    current_files: set[str] = set()

    for line in stdin_input.strip().split("\n"):
        line = line.strip()

        if not line:
            if current_files:
                commits.append(current_files)
                current_files = set()
        elif len(line) == 40 and all(c in "0123456789abcdef" for c in line):
            if current_files:
                commits.append(current_files)
                current_files = set()
        else:
            current_files.add(line)

    if current_files:
        commits.append(current_files)

    return commits


def count_file_changes(commits: list[set[str]]) -> dict[str, int]:
    """Count how many commits touch each file."""
    file_counts: defaultdict[str, int] = defaultdict(int)

    for file_set in commits:
        for file_path in file_set:
            file_counts[file_path] += 1

    return dict(file_counts)


def build_co_occurrence_matrix(
    commits: list[set[str]],
) -> tuple[dict[str, dict[str, int]], dict[str, int]]:
    """
    Build pairwise co-occurrence counts for repo-wide analysis.

    Returns:
        - co_matrix: Dict[file_a][file_b] = times changed together
        - file_counts: Dict[file] = total times changed
    """
    co_matrix: defaultdict[str, defaultdict[str, int]] = defaultdict(lambda: defaultdict(int))
    file_counts = count_file_changes(commits)

    for file_set in commits:
        files = sorted(file_set)
        for i, file_a in enumerate(files):
            for file_b in files[i + 1 :]:
                co_matrix[file_a][file_b] += 1

    return dict(co_matrix), file_counts


def build_correlation_record(
    file_a: str,
    file_b: str,
    co_changes: int,
    changes_a: int,
    changes_b: int,
) -> dict[str, float | int | str]:
    """Create one normalized correlation record."""
    return {
        "file_a": file_a,
        "file_b": file_b,
        "correlation": co_changes / min(changes_a, changes_b),
        "co_changes": co_changes,
        "changes_a": changes_a,
        "changes_b": changes_b,
    }


def sort_correlations(correlations: list[dict]) -> list[dict]:
    """
    Sort correlations deterministically.

    WHY THIS MATTERS:
    Correlation ties are common in small repositories. Stable tie-breaking keeps
    CLI output, JSON snapshots, and tests predictable without changing the core
    meaning of the analysis.
    """
    return sorted(
        correlations,
        key=lambda item: (
            -item["correlation"],
            -item["co_changes"],
            item["file_a"],
            item["file_b"],
        ),
    )


def limit_correlations(correlations: list[dict], top: int | None) -> list[dict]:
    """Apply a top-N limit while keeping `top=None` semantics obvious."""
    if not top or top >= len(correlations):
        return correlations
    return correlations[:top]


def calculate_correlations(
    co_matrix: dict[str, dict[str, int]], file_counts: dict[str, int], threshold: float
) -> list[dict]:
    """Calculate repo-wide correlation scores for all file pairs above threshold."""
    correlations = []

    for file_a, co_files in co_matrix.items():
        for file_b, co_count in co_files.items():
            record = build_correlation_record(
                file_a=file_a,
                file_b=file_b,
                co_changes=co_count,
                changes_a=file_counts[file_a],
                changes_b=file_counts[file_b],
            )
            if record["correlation"] >= threshold:
                correlations.append(record)

    return sort_correlations(correlations)


def calculate_target_correlations(
    commits: list[set[str]],
    target_file: str,
    threshold: float,
    file_counts: dict[str, int] | None = None,
) -> list[dict]:
    """
    Calculate correlations for one target file against all peers.

    IMPORTANT:
    We do not build the full pair matrix here. File mode should answer a direct
    question cheaply and readably: scan commits containing the target file and
    count only the target's peers.
    """
    if file_counts is None:
        file_counts = count_file_changes(commits)

    target_changes = file_counts.get(target_file, 0)
    if target_changes == 0:
        return []

    peer_co_changes: defaultdict[str, int] = defaultdict(int)

    for file_set in commits:
        if target_file not in file_set:
            continue

        for peer_file in file_set:
            if peer_file != target_file:
                peer_co_changes[peer_file] += 1

    correlations = []
    for peer_file, co_changes in peer_co_changes.items():
        record = build_correlation_record(
            file_a=target_file,
            file_b=peer_file,
            co_changes=co_changes,
            changes_a=target_changes,
            changes_b=file_counts[peer_file],
        )
        if record["correlation"] >= threshold:
            correlations.append(record)

    return sort_correlations(correlations)


def split_by_strength(correlations: list[dict]) -> tuple[list[dict], list[dict], list[dict]]:
    """Group correlations into strong / moderate / weak buckets."""
    strong = [item for item in correlations if item["correlation"] >= 0.60]
    moderate = [item for item in correlations if 0.40 <= item["correlation"] < 0.60]
    weak = [item for item in correlations if item["correlation"] < 0.40]
    return strong, moderate, weak


def format_strength_sections(
    lines: list[str], correlations: list[dict], *, target_file: str | None
) -> None:
    """Append grouped correlation sections to the output lines."""
    strong, moderate, weak = split_by_strength(correlations)

    def append_group(title: str, group: list[dict], *, limit_weak: bool = False) -> None:
        if not group:
            return

        lines.append(title)
        visible_group = group[:10] if limit_weak else group

        for corr in visible_group:
            left = corr["file_b"] if target_file else f"{corr['file_a']} ↔ {corr['file_b']}"
            commits_together = min(corr["changes_a"], corr["changes_b"])
            detail = (
                f"{corr['correlation']:.0%} correlation "
                f"({corr['co_changes']}/{commits_together} commits)"
            )
            lines.append(f"  {left}")
            lines.append(f"    {detail}")

        if limit_weak and len(group) > 10:
            lines.append(f"  ... and {len(group) - 10} more results")

        lines.append("")

    append_group("Strong coupling (≥60%):", strong)
    append_group("Moderate coupling (40-60%):", moderate)
    append_group("Weak coupling (<40%):", weak, limit_weak=True)


def format_text_output(correlations: list[dict], threshold: float, total_commits: int) -> str:
    """Format repo-wide correlations as human-readable text."""
    lines = [
        f"Co-change Analysis (last {total_commits} commits, ≥{threshold:.0%} correlation):",
        "",
    ]

    if not correlations:
        lines.extend(
            [
                "No file pairs found above threshold.",
                "",
                "Try:",
                "  - Lowering --threshold (e.g., 0.20)",
                "  - Increasing --commits (e.g., 200)",
            ]
        )
        return "\n".join(lines)

    format_strength_sections(lines, correlations, target_file=None)
    lines.append("Interpretation:")
    lines.append("  High correlation = Files likely architecturally coupled")
    lines.append("  Consider: Co-locate, refactor into module, or document dependency")
    return "\n".join(lines)


def format_target_text_output(
    target_file: str,
    correlations: list[dict],
    threshold: float,
    total_commits: int,
    target_changes: int,
) -> str:
    """Format file-mode correlations as human-readable text."""
    lines = [
        f"Related files for {target_file} "
        f"(last {total_commits} commits, ≥{threshold:.0%} correlation):",
        f"Target file changed in {target_changes} analyzed commits.",
        "",
    ]

    if target_changes == 0:
        lines.extend(
            [
                "The target file does not appear in the analyzed commit window.",
                "",
                "Try:",
                "  - Increasing --commits (e.g., 200)",
                "  - Broadening --since to include older history",
            ]
        )
        return "\n".join(lines)

    if not correlations:
        lines.extend(
            [
                "No related files found above threshold.",
                "",
                "Try:",
                "  - Lowering --threshold (e.g., 0.20)",
                "  - Increasing --commits (e.g., 200)",
            ]
        )
        return "\n".join(lines)

    format_strength_sections(lines, correlations, target_file=target_file)
    lines.append("Interpretation:")
    lines.append("  High correlation = Files that usually move with the target file")
    lines.append("  Review these files together when modifying this area")
    return "\n".join(lines)


def format_json_output(
    *,
    mode: str,
    correlations: list[dict],
    total_commits: int,
    threshold: float,
    target_file: str | None = None,
    target_changes: int | None = None,
) -> str:
    """Format mode-aware JSON output."""
    result: dict[str, object] = {
        "mode": mode,
        "commits_analyzed": total_commits,
        "threshold": threshold,
        "result_count": len(correlations),
        "correlations": correlations,
    }

    if target_file is not None:
        result["target_file"] = target_file
        result["target_changes"] = target_changes or 0

    return json.dumps(result, indent=2)


def main() -> int:
    """Main entry point."""
    args = parse_args()
    stdin_input = sys.stdin.read()

    if not stdin_input.strip():
        print("Error: No input provided", file=sys.stderr)
        print(
            "Usage: git log --name-only --format=%H -n 50 | python3 co_changes.py --all",
            file=sys.stderr,
        )
        return 1

    commits = parse_git_log(stdin_input)
    if not commits:
        print("Error: No commits found in input", file=sys.stderr)
        return 1

    if args.target_file:
        file_counts = count_file_changes(commits)
        target_changes = file_counts.get(args.target_file, 0)
        correlations = calculate_target_correlations(
            commits,
            args.target_file,
            args.threshold,
            file_counts=file_counts,
        )
        correlations = limit_correlations(correlations, args.top)

        if args.format == "json":
            print(
                format_json_output(
                    mode="file",
                    correlations=correlations,
                    total_commits=len(commits),
                    threshold=args.threshold,
                    target_file=args.target_file,
                    target_changes=target_changes,
                )
            )
        else:
            print(
                format_target_text_output(
                    args.target_file,
                    correlations,
                    args.threshold,
                    len(commits),
                    target_changes,
                )
            )
        return 0

    co_matrix, file_counts = build_co_occurrence_matrix(commits)
    correlations = calculate_correlations(co_matrix, file_counts, args.threshold)
    correlations = limit_correlations(correlations, args.top)

    if args.format == "json":
        print(
            format_json_output(
                mode="all",
                correlations=correlations,
                total_commits=len(commits),
                threshold=args.threshold,
            )
        )
    else:
        print(format_text_output(correlations, args.threshold, len(commits)))

    return 0


if __name__ == "__main__":
    sys.exit(main())
