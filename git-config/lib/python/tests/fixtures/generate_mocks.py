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

import sys
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


def generate_activity_mocks():
    """Generate mocks for activity analysis (git log --follow for commit patterns)."""
    print("Generating activity analysis mocks...")

    recorder_burst = CommandMockRecorder("git")
    recorder_weekend = CommandMockRecorder("git")
    recorder_empty = CommandMockRecorder("git")

    # Generate all three scenarios with their respective repos
    # Templates will be converted to string format in TOML for player.py matching
    burst_scenario = {
        "command": ["git", "log", "--date=format:%Y-%m-%d %H:%M:%S %z", "--pretty=format:%ad|%an", "--follow", "--", "{filepath}"],
        "scenario_name": "burst",
        "description": "Burst pattern - many commits in short time",
        "template_vars": {"filepath": "file.py"}
    }

    weekend_scenario = {
        "command": ["git", "log", "--date=format:%Y-%m-%d %H:%M:%S %z", "--pretty=format:%ad|%an", "--follow", "--", "{filepath}"],
        "scenario_name": "weekend",
        "description": "Weekend work pattern - commits on Saturday/Sunday",
        "template_vars": {"filepath": "file.py"}
    }

    empty_scenario = {
        "command": ["git", "log", "--date=format:%Y-%m-%d %H:%M:%S %z", "--pretty=format:%ad|%an", "--follow", "--", "{filepath}"],
        "scenario_name": "empty",
        "description": "No commits for file",
        "template_vars": {"filepath": "nonexistent.py"}
    }

    # Record burst scenario
    recorder_burst.record_multiple_scenarios(
        scenario_specs=[burst_scenario],
        output_file=Path("log/activity-burst.toml"),
        repo_setup_script="git/activity-burst.sh",
        metadata={
            "description": "Mock data for git log --follow (activity burst detection)",
            "generated_by": "generate_mocks.py"
        },
        output_prefix="activity_"
    )

    # Record weekend scenario
    recorder_weekend.record_multiple_scenarios(
        scenario_specs=[weekend_scenario],
        output_file=Path("log/activity-weekend.toml"),
        repo_setup_script="git/activity-weekend.sh",
        metadata={
            "description": "Mock data for git log --follow (weekend activity)",
            "generated_by": "generate_mocks.py"
        },
        output_prefix="activity_"
    )

    # Record empty scenario
    recorder_empty.record_multiple_scenarios(
        scenario_specs=[empty_scenario],
        output_file=Path("log/activity-empty.toml"),
        repo_setup_script="git/activity-burst.sh",
        metadata={
            "description": "Mock data for git log --follow (no results)",
            "generated_by": "generate_mocks.py"
        },
        output_prefix="activity_"
    )

    # Now merge all three TOML files into one activity.toml
    import tomli_w
    if sys.version_info >= (3, 11):
        import tomllib
    else:
        import tomli as tomllib

    final_scenarios = []
    final_metadata = {
        "description": "Mock data for git log --follow (activity analysis)",
        "generated_by": "generate_mocks.py"
    }

    # Read each file and collect scenarios
    for toml_file in ["activity-burst.toml", "activity-weekend.toml", "activity-empty.toml"]:
        toml_path = recorder_burst.mocks_dir / "log" / toml_file
        with open(toml_path, "rb") as f:
            data = tomllib.load(f)
            final_scenarios.extend(data.get("scenario", []))

    # Write combined file
    combined_data = {
        "metadata": final_metadata,
        "scenario": final_scenarios
    }
    final_path = recorder_burst.mocks_dir / "log" / "activity.toml"
    with open(final_path, "wb") as f:
        tomli_w.dump(combined_data, f)

    # Clean up individual files
    for toml_file in ["activity-burst.toml", "activity-weekend.toml", "activity-empty.toml"]:
        toml_path = recorder_burst.mocks_dir / "log" / toml_file
        if toml_path.exists():
            toml_path.unlink()

    print("✓ Generated activity analysis mocks")


def generate_search_mocks():
    """Generate mocks for commit search (git log --grep and git log -G)."""
    print("Generating commit search mocks...")

    recorder = CommandMockRecorder("git")

    field_sep = '|~|'
    format_str = f"%H{field_sep}%h{field_sep}%an{field_sep}%ae{field_sep}%cn{field_sep}%ce{field_sep}%aI{field_sep}%ar{field_sep}%cI{field_sep}%cr{field_sep}%T{field_sep}%s{field_sep}%B{field_sep}%P{field_sep}%D"

    scenarios = [
        {
            "command": ["git", "log", f"--format={format_str}", "--grep={term}"],
            "scenario_name": "message_match",
            "description": "Search commit messages for 'fix'",
            "template_vars": {"term": "fix"}
        },
        {
            "command": ["git", "log", f"--format={format_str}", "-S{code}"],
            "scenario_name": "code_match",
            "description": "Search code changes for 'def calculate'",
            "template_vars": {"code": "def calculate"}
        },
        {
            "command": ["git", "log", f"--format={format_str}", "--name-status", "--grep={term}"],
            "scenario_name": "with_files",
            "description": "Search with file changes included",
            "template_vars": {"term": "feature"}
        },
        {
            "command": ["git", "log", f"--format={format_str}", "--grep={term}"],
            "scenario_name": "no_match",
            "description": "Search with no results",
            "template_vars": {"term": "nonexistent"}
        },
        {
            "command": ["git", "log", f"--format={format_str}", "--invalid-flag"],
            "scenario_name": "git_error",
            "description": "Git command error",
            "template_vars": {}
        },
    ]

    recorder.record_multiple_scenarios(
        scenario_specs=scenarios,
        output_file=Path("log/search.toml"),
        repo_setup_script="git/search-commits.sh",
        metadata={
            "description": "Mock data for git search commands",
            "generated_by": "generate_mocks.py"
        },
        output_prefix="search_"
    )

    print("✓ Generated commit search mocks")


def main():
    """Generate all mock data."""
    print("=== Generating Mock Data for Git Commands ===\n")

    try:
        generate_git_log_follow_mocks()
        generate_git_log_L_mocks()
        generate_binary_file_mocks()
        generate_activity_mocks()
        generate_search_mocks()

        print("\n✓ All mocks generated successfully!")
        print("\nMock files created:")
        print("  - mocks/git/log/follow.toml")
        print("  - mocks/git/log/L-line.toml")
        print("  - mocks/git/log/binary-errors.toml")
        print("  - mocks/git/log/activity.toml")
        print("  - mocks/git/log/search.toml")
        print("\nOutput files created in mocks/git/log/outputs/")

    except Exception as e:
        print(f"\n✗ Error generating mocks: {e}")
        raise


if __name__ == "__main__":
    main()
