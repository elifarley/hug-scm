#!/usr/bin/env python3
"""
Script to generate all mock data for Git command tests.

This script demonstrates the Command Mock Framework with Git commands.
For other commands (docker, npm, etc.), copy this file and adapt.

This script:
1. Creates test repositories from setup scripts
2. Executes real Git commands
3. Stores outputs in TOML files for later replay

Run this once to generate mocks, then re-run when Git behavior changes.

Usage:
    python generate_mocks.py
"""

from pathlib import Path
from recorder import CommandMockRecorder


def generate_git_log_follow_mocks():
    """Generate mocks for git log --follow commands."""
    print("Generating git log --follow mocks...")

    recorder = CommandMockRecorder("git")

    # Basic scenario - use different repo for follow (which creates project.py)
    scenarios = [
        {
            "command": ["git", "log", "--follow", "--format=%H|%an|%ai", "--", "{filepath}"],
            "scenario_name": "basic",
            "description": "Basic file history without filters",
            "template_vars": {"filepath": "project.py"}
        },
        {
            "command": ["git", "log", "--follow", "--format=%H|%an|%ai", "--since={since}", "--", "{filepath}"],
            "scenario_name": "with_since_filter",
            "description": "File history filtered by --since date",
            "template_vars": {"filepath": "project.py", "since": "2 months ago"}
        },
    ]

    recorder.record_multiple_scenarios(
        scenario_specs=scenarios,
        output_file=Path("log/follow.toml"),
        repo_setup_script="git/churn-with-since.sh",
        metadata={
            "description": "Mock data for git log --follow (file churn analysis)",
            "generated_by": "generate_mocks.py"
        },
        output_prefix="follow-"
    )

    print("✓ Generated git log --follow mocks")


def generate_git_log_L_mocks():
    """Generate mocks for git log -L commands (line history)."""
    print("Generating git log -L mocks...")

    recorder = CommandMockRecorder("git")

    scenarios = [
        {
            "command": ["git", "log", "-L", "{line_range}:{filepath}", "--oneline"],
            "scenario_name": "basic",
            "description": "Basic line history without filters",
            "template_vars": {"line_range": "2,2", "filepath": "file.txt"}
        },
        {
            "command": ["git", "log", "-L", "{line_range}:{filepath}", "--oneline", "--since={since}"],
            "scenario_name": "with_since_filter",
            "description": "Line history filtered by --since date",
            "template_vars": {"line_range": "2,2", "filepath": "file.txt", "since": "1 month ago"}
        },
        {
            "command": ["git", "log", "-L", "{line_range}:{filepath}", "--oneline"],
            "scenario_name": "no_commits",
            "description": "Line that has never been modified (empty result)",
            "template_vars": {"line_range": "1,1", "filepath": "file.txt"}
        },
    ]

    recorder.record_multiple_scenarios(
        scenario_specs=scenarios,
        output_file=Path("log/L-line.toml"),
        repo_setup_script="git/churn-basic.sh",
        metadata={
            "description": "Mock data for git log -L (line history analysis)",
            "generated_by": "generate_mocks.py"
        },
        output_prefix="L-line-"
    )

    print("✓ Generated git log -L mocks")


def generate_binary_file_mocks():
    """Generate mocks for binary file error scenarios."""
    print("Generating binary file mocks...")

    recorder = CommandMockRecorder("git")

    # Binary file returns error from git log -L
    scenarios = [
        {
            "command": ["git", "log", "-L", "{line_range}:{filepath}", "--oneline"],
            "scenario_name": "binary_file",
            "description": "Git error when running -L on binary file",
            "template_vars": {"line_range": "1,1", "filepath": "image.png"}
        },
    ]

    recorder.record_multiple_scenarios(
        scenario_specs=scenarios,
        output_file=Path("log/binary-errors.toml"),
        repo_setup_script="git/churn-binary.sh",
        metadata={
            "description": "Mock data for binary file error handling",
            "generated_by": "generate_mocks.py"
        },
        output_prefix="binary-"
    )

    print("✓ Generated binary file error mocks")


def main():
    """Generate all mock data."""
    print("=== Generating Mock Data for Git Commands ===\n")

    try:
        generate_git_log_follow_mocks()
        generate_git_log_L_mocks()
        generate_binary_file_mocks()

        print("\n✓ All mocks generated successfully!")
        print("\nMock files created:")
        print("  - mocks/git/log/follow.toml")
        print("  - mocks/git/log/L-line.toml")
        print("  - mocks/git/log/binary-errors.toml")
        print("\nOutput files created in mocks/git/log/outputs/")

    except Exception as e:
        print(f"\n✗ Error generating mocks: {e}")
        raise


if __name__ == "__main__":
    main()
