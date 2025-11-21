# Command Mock Framework

High-fidelity command mocking framework for Python tests. Records real command outputs (git, docker, npm, etc.) to TOML files for reproducible, fast test execution.

## Table of Contents
- [Overview](#overview)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Core Components](#core-components)
- [Usage Examples](#usage-examples)
- [Advanced Features](#advanced-features)
- [Extracting to Other Projects](#extracting-to-other-projects)
- [Troubleshooting](#troubleshooting)

## Overview

### Why This Framework?

**Problem**: Tests that mock CLI commands often use invented, low-fidelity data that doesn't match real command output, leading to brittle tests that break when command behavior changes.

**Solution**: Record real command outputs once, store them in version-controlled TOML files, and replay them in tests for high-fidelity mocking with zero command execution overhead.

### Key Benefits

✅ **High Fidelity**: Mocks based on real command outputs, not invented data
✅ **Fast**: No command execution during tests (100x+ faster)
✅ **DRY**: Mock setup defined once in TOML, reused across tests
✅ **Maintainable**: Update mocks with `pytest --regenerate-mocks`
✅ **Portable**: Easy to extract and use in other projects
✅ **Command-Agnostic**: Works with git, docker, npm, kubectl, aws-cli, etc.
✅ **Discoverable**: TOML files document actual command behavior

## Quick Start

### 1. Install Dependencies

```bash
cd git-config/lib/python
pip install -r requirements.txt
```

Required dependencies:
- `tomli` (Python < 3.11) or built-in `tomllib` (Python >= 3.11)
- `tomli-w` for writing TOML files

### 2. View Example Tests

See `test_example.py` for comprehensive usage examples.

### 3. Run Tests

```bash
# Run with existing mocks (defaults to git commands)
pytest tests/fixtures/test_example.py

# Regenerate mocks from real command calls
pytest tests/fixtures/test_example.py --regenerate-mocks

# Test with different command type
pytest tests/fixtures/test_example.py --command-type=docker
```

## Architecture

### Directory Structure

```
tests/fixtures/
├── recorder.py              # CommandMockRecorder: records command outputs
├── player.py                # CommandMockPlayer: replays mocks in tests
├── conftest.py              # pytest plugin (--regenerate-mocks, --command-type flags, command_mock fixture)
├── generate_mocks.py        # Script to generate all mock data
├── test_example.py          # Example tests showing fixture usage
│
├── test-repos/              # Repo setup scripts (organized by command type)
│   └── git/
│       ├── churn-basic.sh       # Creates test repo with basic commits
│       ├── churn-with-since.sh  # Creates repo with time-based commits
│       └── churn-binary.sh      # Creates repo with binary files
│
└── mocks/                   # Mock data storage (gitignored except .example)
    ├── .gitignore           # Ignores *.toml, allows *.toml.example
    └── git/                 # Git command mocks
        └── log/
            ├── follow.toml           # Scenarios for git log --follow
            ├── L-line.toml           # Scenarios for git log -L
            ├── binary-errors.toml    # Binary file error scenarios
            ├── follow.toml.example   # Template (committed to git)
            └── outputs/
                ├── .gitkeep          # Keeps directory in git
                ├── follow-basic.txt  # Actual command output for scenario
                └── ...
```

### File Format

**TOML files** contain scenarios with metadata:

```toml
[metadata]
description = "Mock data for git log --follow"
generated_by = "generate_mocks.py"
repo_setup = "churn-basic.sh"

[[scenario]]
name = "basic"
description = "Basic file history without filters"
command = ["git", "log", "--follow", "--format=%H|%an|%ai", "--", "project.py"]
returncode = 0
output_file = "outputs/follow-basic.txt"
stderr = ""
```

**Output files** contain actual command output (text files).

## Core Components

### CommandMockRecorder

Records real command outputs to TOML files.

```python
from recorder import CommandMockRecorder

recorder = CommandMockRecorder("git")

# Create test repo from script
repo_path = recorder.create_test_repo("git/churn-basic.sh")

# Record single scenario
scenario = recorder.record_scenario(
    command=["git", "log", "--follow", "--format=%H|%an|%ai", "--", "{filepath}"],
    scenario_name="basic",
    output_path=Path("log/follow.toml"),
    repo_path=repo_path,
    description="Basic file history",
    template_vars={"filepath": "file.txt"},
    output_prefix="follow-"  # Avoids filename collisions
)

# Or record multiple scenarios at once
recorder.record_multiple_scenarios(
    scenario_specs=[...],
    output_file=Path("log/follow.toml"),
    repo_setup_script="git/churn-basic.sh",
    metadata={"description": "..."},
    output_prefix="follow-"
)
```

### CommandMockPlayer

Replays mocks from TOML files in tests.

```python
from player import CommandMockPlayer

player = CommandMockPlayer("git")

# Get mock for single scenario
mock_fn = player.get_subprocess_mock("log/follow.toml", "basic")

# Get mock for multiple commands
mock_fn = player.get_multi_scenario_mock({
    "git log --follow": ("log/follow.toml", "basic"),
    "git log -L": ("log/L-line.toml", "basic")
})

# Dynamic scenario selection
def choose_scenario(cmd):
    if "--since" in cmd:
        return "with_since_filter"
    return "basic"

mock_fn = player.get_dynamic_mock("log/follow.toml", choose_scenario)
```

### pytest Plugin (conftest.py)

Provides `command_mock` fixture and `--regenerate-mocks` flag.

```python
def test_something(command_mock):
    # command_mock is CommandMockPlayer in normal runs
    # command_mock is CommandMockRecorder when using --regenerate-mocks
    mock_fn = command_mock.get_subprocess_mock("log/follow.toml", "basic")

    with patch('subprocess.run', side_effect=mock_fn):
        result = my_function_that_calls_git()
```

## Usage Examples

### Basic Scenario

```python
def test_basic(command_mock):
    # Arrange
    mock_fn = command_mock.get_subprocess_mock("log/follow.toml", "basic")

    # Act
    with patch('subprocess.run', side_effect=mock_fn):
        result = get_file_history("project.py")

    # Assert
    assert result['total_commits'] == 5
```

### Multiple Scenarios in One Test

```python
def test_multiple_commands(command_mock):
    mock_fn = command_mock.get_multi_scenario_mock({
        "git log --follow": ("log/follow.toml", "basic"),
        "git log -L": ("log/L-line.toml", "basic")
    })

    with patch('subprocess.run', side_effect=mock_fn):
        # Both commands work with different scenarios
        file_history = get_file_history("file.txt")
        line_history = get_line_history("file.txt", 2)
```

### Dynamic Scenario Selection

```python
def test_conditional_behavior(command_mock):
    def choose_scenario(cmd):
        if "--since" in cmd:
            return "with_since_filter"
        return "basic"

    mock_fn = command_mock.get_dynamic_mock("log/follow.toml", choose_scenario)

    with patch('subprocess.run', side_effect=mock_fn):
        # Different scenarios based on command
        all_history = get_file_history("file.txt")
        recent_history = get_file_history("file.txt", since="1 week ago")
```

### Error Scenarios

```python
def test_binary_file_error(command_mock):
    mock_fn = command_mock.get_subprocess_mock("log/binary-errors.toml", "binary_file")

    with patch('subprocess.run', side_effect=mock_fn):
        result = subprocess.run(
            ["git", "log", "-L", "1,1:image.png", "--oneline"],
            capture_output=True,
            check=False
        )

    assert result.returncode == 128  # Git error for binary files
```

## Advanced Features

### Template Variables

Use `{placeholders}` in commands for reusable scenarios:

```python
scenario = recorder.record_scenario(
    command=["git", "log", "--follow", "--", "{filepath}"],
    scenario_name="basic",
    template_vars={"filepath": "myfile.txt"}  # Substituted at record time
)
```

The recorded TOML will have the actual filepath:

```toml
command = ["git", "log", "--follow", "--", "myfile.txt"]
```

### Output File Prefixes

Avoid filename collisions when multiple TOML files use same scenario names:

```python
recorder.record_multiple_scenarios(
    scenario_specs=[...],
    output_file=Path("log/follow.toml"),
    output_prefix="follow-"  # Creates follow-basic.txt, not basic.txt
)
```

### Test Repo Setup Scripts

Create reproducible test repositories:

```bash
#!/usr/bin/env bash
# test-repos/git/churn-basic.sh
set -euo pipefail

git init
git config user.name "Test User"
git config user.email "test@example.com"

echo "content" > file.txt
git add file.txt
GIT_AUTHOR_DATE="2024-01-01 10:00:00 -0500" \
GIT_COMMITTER_DATE="2024-01-01 10:00:00 -0500" \
git commit -m "Initial commit"

# More commits...
```

### Regenerating Mocks

When command behavior changes or you need fresh data:

```bash
# Regenerate all mocks
python generate_mocks.py

# Or run tests with --regenerate-mocks
pytest tests/ --regenerate-mocks

# Regenerate for different command type
pytest tests/ --regenerate-mocks --command-type=docker
```

## Extracting to Other Projects

The framework is designed for easy extraction and reuse.

### Decision: Track Mock Files or Not?

Before extracting, decide your mock file tracking strategy:

**Option A: Track Mock Files (Recommended for Most Projects)**
- ✅ Tests work immediately after `git clone`
- ✅ Faster CI/CD (no regeneration needed)
- ✅ Consistent test data across all environments
- ❌ Slightly larger repo size
- ❌ Must remember to regenerate/commit when commands change

**Option B: Don't Track Mock Files**
- ✅ Always fresh data from real commands
- ✅ Smaller repository size
- ✅ Forces developers to understand mock generation
- ❌ Requires commands installed to run tests
- ❌ Slower initial setup and CI/CD

### Step 1: Copy Core Files

Copy these files to your project:

```
your-project/tests/fixtures/
├── recorder.py
├── player.py
├── conftest.py
└── mocks/
    └── .gitignore  # Customize based on your tracking decision
```

### Step 2: Configure .gitignore

**If tracking mock files (Option A):**
```gitignore
# Keep .example files for documentation
*.toml.example
.gitkeep
```

**If NOT tracking mock files (Option B):**
```gitignore
# Ignore generated mock data
*.toml
outputs/*.txt

# Keep .example files and structure
!*.toml.example
!.gitkeep
```

### Step 3: Install Dependencies

Add to your `requirements.txt` or `pyproject.toml`:

```
tomli>=2.0.0; python_version < '3.11'
tomli-w>=1.0.0
```

### Step 4: Create Test Setup Scripts

Create setup scripts for your command scenarios:

```bash
# tests/fixtures/test-repos/git/my-scenario.sh
#!/usr/bin/env bash
# Create repo with specific commits/files for your tests

# OR for Docker:
# tests/fixtures/test-repos/docker/my-scenario.sh
# Create containers/images for your tests
```

### Step 5: Generate Mocks

Create `generate_mocks.py` for your project:

```python
from pathlib import Path
from recorder import CommandMockRecorder

def generate_my_mocks():
    # For Git commands
    recorder = CommandMockRecorder("git")

    scenarios = [
        {
            "command": ["git", "log", "--oneline"],
            "scenario_name": "basic",
            "description": "Basic commit history"
        }
    ]

    recorder.record_multiple_scenarios(
        scenario_specs=scenarios,
        output_file=Path("log/my-command.toml"),
        repo_setup_script="git/my-scenario.sh",
        metadata={"description": "My mocks"},
        output_prefix="my-"
    )

if __name__ == "__main__":
    generate_my_mocks()
```

### Step 6: Write Tests

```python
def test_my_feature(command_mock):
    mock_fn = command_mock.get_subprocess_mock("log/my-command.toml", "basic")

    with patch('subprocess.run', side_effect=mock_fn):
        result = my_function()

    assert result == expected
```

### Step 7: CI Integration

Add to your CI pipeline:

```yaml
# .github/workflows/test.yml
- name: Install dependencies
  run: pip install -r requirements.txt

- name: Run tests
  run: pytest tests/
```

### Customization Points

When extracting, you may want to customize:

1. **Directory structure**: Change `fixtures_root` in CommandMockRecorder/CommandMockPlayer
2. **Mock storage**: Modify `mocks_dir` paths
3. **TOML format**: Extend `scenario` dict with custom fields
4. **Command matching**: Override `command_matches()` in CommandMockPlayer

## Troubleshooting

### Mock file not found

**Error**: `FileNotFoundError: Mock file not found: mocks/git/log/follow.toml`

**Solution**:
```bash
python generate_mocks.py  # Generate mocks first
# OR
pytest --regenerate-mocks  # Regenerate during test run
```

### Scenario not found

**Error**: `KeyError: Scenario 'basic' not found in follow.toml`

**Solution**: Check available scenarios:

```bash
cat mocks/git/log/follow.toml | grep "name ="
```

### Output file collision

**Problem**: Multiple TOML files create `basic.txt`, overwriting each other

**Solution**: Use `output_prefix`:

```python
recorder.record_multiple_scenarios(
    ...,
    output_prefix="follow-"  # Creates follow-basic.txt
)
```

### Binary file errors

**Error**: `UnicodeDecodeError` when recording command output

**Solution**: The recorder automatically handles this by catching the exception and returning a synthetic error response (returncode=128). This is expected for binary files or non-text output.

### Tests pass with mocks but fail with real commands

**Root cause**: Mock data is outdated or doesn't match actual command behavior

**Solution**:
```bash
# Regenerate mocks from real commands
python generate_mocks.py

# Verify tests still pass
pytest tests/
```

### Missing output files

**Error**: `FileNotFoundError: Output file not found: outputs/basic.txt`

**Solution**: Ensure output files are generated:

```bash
ls mocks/git/log/outputs/  # Should list .txt files
python generate_mocks.py   # Regenerate if missing
```

## Best Practices

### 1. Use Descriptive Scenario Names

```python
# Good
scenario_name = "with_since_filter_multiple_authors"

# Bad
scenario_name = "test1"
```

### 2. Add Metadata to TOML Files

```python
metadata = {
    "description": "Mock data for git log --follow (file churn analysis)",
    "generated_by": "generate_mocks.py",
    "date_generated": "2024-11-21",
    "command_version": "git 2.43.0"
}
```

### 3. Keep Test Setups Simple

Create minimal setups that test specific behaviors:

```bash
# Good: Focused on specific scenario
git init && echo "v1" > file.txt && git add . && git commit -m "v1"
echo "v2" > file.txt && git commit -am "v2"

# Bad: Complex setup that's hard to understand
# 50 lines of bash creating 20 files with complex history
```

### 4. Use .example Files

Commit `.toml.example` files to document expected structure:

```bash
cp mocks/git/log/follow.toml mocks/git/log/follow.toml.example
git add mocks/git/log/follow.toml.example
```

### 5. Test Both Success and Error Cases

```python
# Success case
mock_fn = command_mock.get_subprocess_mock("log/follow.toml", "basic")

# Error case
mock_fn = command_mock.get_subprocess_mock("log/binary-errors.toml", "binary_file")
```

## FAQ

**Q: Should I commit mock data files?**
A: **For this project**: Yes, mock files are tracked in git to enable immediate testing after clone. **For extracted usage in other projects**: You can choose either approach based on your needs:
- **Track mocks** (like this project): Tests work immediately, faster CI/CD, consistent test data across environments
- **Don't track mocks** (regenerate on each machine): Always fresh data, smaller repo, forces developers to understand mock generation

To switch to not tracking mocks in extracted projects, update `.gitignore` to add `*.toml` and `*/outputs/*.txt`.

**Q: How often should I regenerate mocks?**
A: When command behavior changes, when adding new scenarios, or when tests fail unexpectedly. After regenerating, commit the updated mock files to keep tests consistent across the team.

**Q: Can I use this for non-Git commands?**
A: Yes! The framework is command-agnostic. Works with any subprocess call (docker, npm, kubectl, aws-cli, etc.). Just pass the appropriate `command_type` when creating recorder/player instances.

**Q: What if my commands have dynamic arguments?**
A: Use template variables or dynamic scenario selection (see examples above).

**Q: How do I debug mock matching issues?**
A: Add debug logging to `command_matches()` in `player.py` to see why commands aren't matching.

**Q: Can I test multiple command types in one test suite?**
A: Yes! Create separate recorder instances for each command type:
```python
git_recorder = CommandMockRecorder("git")
docker_recorder = CommandMockRecorder("docker")
```

## Contributing

When extending this framework:

1. Add new scenarios to `generate_mocks.py`
2. Create test repo scripts in `test-repos/`
3. Add example tests to `test_example.py`
4. Update this README with new patterns
5. Run `pytest --regenerate-mocks` to verify

## License

Part of the Hug SCM project. See main project LICENSE.
