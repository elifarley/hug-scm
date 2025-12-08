# Hug SCM Library Documentation

This directory contains the core library functions used by all Hug commands.

## Libraries

### hug-common

General-purpose utility functions for shell scripting.

**Features:**
- Color definitions for terminal output
- Output functions (`error`, `warning`, `info`, `success`)
- User interaction (`prompt_confirm_warn`, `prompt_confirm_danger`, `prompt_confirm_safe`)
- String manipulation (`trim_message`)
- Array utilities (`dedupe_array`, `print_list`)
- File system checks (`is_symlink`)
- Command pattern helpers

### hug-output

Consistent output formatting and messaging for commands.

**Features:**
- Standard message functions (`error`, `warning`, `info`, `success`, `tip`)
- Action preview functions (`print_nothing_to_do`, `print_dry_run_preview`, `print_action_preview`)
- File list display helpers (`print_staged_unstaged_paths`, `print_untracked_ignored_paths`)

### hug-cli-flags

Command-line flag parsing utilities using GNU getopt (required).

**Features:**
- Common flag parsing with GNU getopt (`parse_common_flags`)
  - **Requires GNU getopt** (util-linux package)
  - Supports combined short options (e.g., `-fq` for `--force --quiet`)
  - Graceful handling of commands with additional custom options
  - Recognized flags: `-f/--force`, `-q/--quiet`, `-h/--help`, `--dry-run`, `--browse-root`
  - Special handling for trailing `--` (interactive file selection)
- Argument validation (`require_args`)
- Flag conflict detection (`check_browse_root_no_paths`)

**Requirements:**
- GNU getopt (provided by util-linux package on most Linux distributions)

### hug-gum

Interactive selection and filtering with charmbracelet/gum integration.

**Features:**
- Gum availability detection (`gum_available`)
- Height calculation for optimal UI (`gum_calculate_height`)
- Selection normalization with ANSI stripping (`normalize_selection`)
- Low-level filter invocation (`gum_invoke_filter`)
- Stdin filter wrapper (`gum_filter_select`)
- Index-based selection for flexible extraction (`gum_filter_by_index`)

**Important Notes:**
- ANSI color codes in options are automatically stripped during matching to ensure reliable selection
- All functions respect `HUG_QUIET` environment variable for silent operation
- `normalize_selection` handles git-specific formats (branch markers, upstream status, parentheses)
- Failed selections provide user-friendly feedback unless `HUG_QUIET` is set

### hug-git-kit

Git-specific operations library (main entry point).

**Organization:**
The hug-git-kit has been split into focused modules for better organization:

- **hug-git-repo**: Repository and commit validation functions
- **hug-git-state**: Working tree state checking functions
- **hug-git-files**: File listing functions (staged, unstaged, tracked, etc.)
- **hug-git-discard**: Discard operations for staged/unstaged/uncommitted changes
- **hug-git-branch**: Branch information, display, and selection
- **hug-git-commit**: Commit range analysis and preview helpers
- **hug-git-upstream**: Upstream operation handlers
- **hug-git-backup**: Branch backup management
- **hug-git-rebase**: Rebase conflict resolution helpers

The main `hug-git-kit` file sources all these modules to maintain backward compatibility.

**Features by Module:**

#### hug-git-repo
- Repository validation (`check_git_repo`)
- Path conversion utilities (`convert_to_relative_paths`)
- Commit validation (`validate_commit`, `ensure_commit_exists`)
- Upstream branch operations (`get_upstream_commit`)
- Commit ancestry checking (`ensure_ancestor_of_head`)
- HEAD target resolution (`resolve_head_target`)
- Commit history navigation (`get_commit_n_back`)

#### hug-git-state
- Working tree state checks (`has_pending_changes`, `has_staged_changes`, `has_unstaged_changes`)
- Cleanliness validation (`check_working_tree_clean`, `check_files_clean`)
- File state checking (`check_file_in_commit`, `check_file_staged`, `check_file_unstaged`)
- Binary file detection (`is_binary_staged`)
- Change preview (`preview_file_changes`)

#### hug-git-files
- List staged files (`list_staged_files`)
- List unstaged files (`list_unstaged_files`)
- List untracked files (`list_untracked_files`)
- List ignored files (`list_ignored_files`)
- List tracked files (`list_tracked_files`)
- Support for `--cwd` scoping and `--status` information

#### hug-git-discard
- Discard unstaged changes (`discard_all_unstaged`, `discard_unstaged`)
- Discard all uncommitted changes (`discard_all_uncommitted_changes`, `discard_uncommitted_changes`)
- Discard staged changes only (`discard_all_staged`, `discard_staged_no_unstaged`, `discard_staged_with_unstaged`)
- Dry-run and confirmation helpers

#### hug-git-branch
- Compute branch details (`compute_local_branch_details`)
- Print branch lists (`print_branch_list`, `print_branch_line`)
- Interactive branch selection (`print_interactive_branch_menu`)
- Selection helpers (`get_gum_selection_index`, `get_numbered_selection_index`)

#### hug-git-commit
- Count commits in range (`count_commits_in_range`)
- List changed files (`list_changed_files_in_range`, `count_changed_files_in_range`)
- Print commit lists (`print_commit_list_in_range`)
- Preview helpers (`print_preview_summary`, `print_commit_list_header`)

#### hug-git-upstream
- Handle upstream operations (`handle_upstream_operation`)
- Handle standard operations (`handle_standard_operation`)

#### hug-git-backup
- Create backup branches (`create_backup_branch`)
- List backup branches (`get_backup_branches`)
- Extract metadata (`extract_original_name`, `format_backup_display_name`)

#### hug-git-rebase
- Check for rebase conflicts (`abort_if_no_rebase_conflict`)
- Resolve current conflict (`rebase_pick`)
- Auto-resolve all remaining conflicts (`rebase_finish_all`)

### hug-json

JSON serialization and validation utilities (pure Bash).

**Features:**
- String escaping with Unicode support (`json_escape`)
- JSON object creation (`to_json_object`, `to_json_nested`)
- JSON array creation (`to_json_array`)
- Streaming array helpers (`json_array_start`, `json_array_add`, `json_array_end`)
- Error response generation (`json_error`)
- Metadata generation (`json_metadata`)
- JSON validation (`validate_json`)
- Pretty printing (`json_pretty`)

**Important Notes:**
- Pure Bash implementation - no external dependencies required
- Handles Unicode characters safely via `LC_ALL=C sed`
- Empty arrays produce `"[]"` explicitly
- Control characters are properly escaped
- Optional Python validation when available

### hug-git-json

Git-specific JSON output helpers (uses hug-json).

**Features:**
- Unified status JSON output (`output_json_status_unified`)
- Git status code mapping (`git_status_to_json_type`)
- File collection helpers (`collect_git_files_json`)
- Common parsing patterns (`parse_git_status_line`, `git_file_to_json`)
- Optimized for batch Git operations
- Handles special characters in file paths and commit messages

**JSON Design Philosophy:**
- Pure Bash for portability and dependency-free operation
- Computational tasks (analytics, stats) use Python helpers
- Simple formatting stays in Bash - faster startup, no dependencies
- Complex processing can use Python via subprocess calls when needed
- JSON output focuses on data transformation, not computation

## Usage in Command Scripts

All Hug command scripts should follow this standard pattern:

```bash
#!/usr/bin/env bash
CMD_BASE="$(readlink -f "$0" 2>/dev/null || greadlink -f "$0")" || CMD_BASE="$0"
CMD_BASE="$(dirname "$CMD_BASE")"
# shellcheck source=../lib/hug-common
. "$CMD_BASE/../lib/hug-common"
# shellcheck source=../lib/hug-git-kit
. "$CMD_BASE/../lib/hug-git-kit"
set -euo pipefail  # Exit on error, undefined vars, pipe failures
```

### Why This Pattern?

1. **Proper path resolution**: Works correctly even when the script is invoked via symlink
2. **Library sourcing**: Loads common functions from the lib directory
3. **Error handling**: `set -euo pipefail` ensures scripts fail fast on errors
4. **ShellCheck compatibility**: Source directives help ShellCheck analyze the code

## Common Patterns

### Error Handling

```bash
# Simple error with default exit code (1)
error "Something went wrong"

# Error with custom exit code
error "Invalid argument" 2

# Warning (doesn't exit)
warning "This might cause issues"

# Info message
info "Processing files..."

# Success message
success "Operation completed"
```

### User Confirmation

```bash
# Simple yes/no confirmation with NO default (for destructive operations)
prompt_confirm_warn "Proceed? [y/N]: "

# Require specific word confirmation (for dangerous operations)
prompt_confirm_danger "delete"  # User must type "delete"

# Simple yes/no confirmation with YES default (for safe operations)
prompt_confirm_safe "Create new branch?"  # Defaults to Yes
```

### JSON Operations

```bash
# Create a JSON object
json_obj=$(to_json_object "name" "John Doe" "age" "30" "active" "true")
# Result: {"name":"John Doe","age":"30","active":"true"}

# Create a JSON array
files=("file1.txt" "file2.txt")
json_array=$(to_json_array "${files[@]}")
# Result: ["file1.txt","file2.txt"]

# Handle special characters in JSON
special_text="café résumé 🦊 \"quoted\""
escaped=$(json_escape "$special_text")
# Properly escapes Unicode, quotes, and control characters

# Validate JSON
if validate_json "$json_obj"; then
    echo "Valid JSON"
else
    echo "Invalid JSON"
fi
```

### Git JSON Output

```bash
# Generate unified status JSON
# Include all file types, show empty arrays
output_json_status_unified --include-empty --filter "staged,unstaged,untracked,ignored"

# Include only specific types, exclude empty arrays
output_json_status_unified --filter "staged,unstaged" --cwd-only

# JSON status output with backward compatibility
# Bin version (includes empty arrays)
output_json_status --staged --unstaged --untracked --ignored

# Lib version (excludes empty arrays)
output_json_status --staged --unstaged
```

### Working with Arrays

```bash
# Remove duplicates from an array
files=("a.txt" "b.txt" "a.txt" "c.txt")
dedupe_array files
# Result: files=("a.txt" "b.txt" "c.txt")

# Print a titled list
print_list "Modified files" "${files[@]}"
# Output:
# Modified files (3):
#   a.txt
#   b.txt
#   c.txt
```

### Displaying File Status Lists

```bash
# Display staged and unstaged paths with appropriate labels
declare -a staged_paths=("file1.txt" "file2.txt")
declare -a unstaged_paths=("file3.txt")
print_staged_unstaged_paths staged_paths unstaged_paths true false
# Shows preservation note when only staged is targeted

# Display untracked and ignored paths
declare -a untracked=("new.txt")
declare -a ignored=(".DS_Store")
print_untracked_ignored_paths untracked ignored true true
# Only displays paths for targeted categories
```

### Flag Validation

```bash
# Validate that --browse-root is not used with explicit paths
check_browse_root_no_paths "$browse_root" true  # has_paths=true
# Exits with error if browse_root=true and paths provided
```

### Git Repository Checks

```bash
# Ensure we're in a git repo
check_git_repo

# Check if working tree is clean
check_working_tree_clean

# Check specific files are clean
check_files_clean file1.txt file2.txt
```

### Commit Operations

```bash
# Validate a commit exists
validate_commit "abc123"

# Ensure commit is ancestor of HEAD
ensure_ancestor_of_head "abc123"

# Resolve user input to commit reference
target=$(resolve_head_target "$1" "HEAD~1")
# "3" -> "HEAD~3"
# "abc123" -> "abc123"
# "" -> "HEAD~1" (default)
```

### Working Tree Operations

```bash
# Discard all unstaged changes
discard_all_unstaged

# Discard specific unstaged files
unstaged_files=("file1.txt" "file2.txt")
discard_unstaged unstaged_files

# Discard all uncommitted changes (staged + unstaged)
discard_all_uncommitted_changes

# With dry-run support
discard_all_uncommitted_changes --dry-run
```

### Branch Information

```bash
# Get branch details for display
declare -a branches hashes subjects tracks
declare max_len current_branch

if compute_local_branch_details branches hashes subjects tracks max_len current_branch; then
    # Print non-interactive list
    print_branch_list branches hashes subjects tracks "$max_len" "$current_branch"
    
    # Or interactive menu
    declare selected
    print_interactive_branch_menu selected branches hashes subjects tracks "$max_len" "$current_branch"
    echo "Selected: $selected"
fi
```

### Commit Range Analysis

```bash
# Count commits between two refs
count=$(count_commits_in_range "origin/main" "HEAD")

# List changed files
files=$(list_changed_files_in_range "origin/main" "HEAD")

# Print commit list for user preview
print_commit_list_in_range "origin/main" "HEAD"
```

### Operation Handlers

```bash
# For upstream operations (rewind to upstream, etc.)
target=$(handle_upstream_operation "rewinding")
# Displays preview, gets confirmation, returns upstream commit

# For standard operations (back, undo, etc.)
target=$(resolve_head_target "$1")
handle_standard_operation "moving back" "$target"
prompt_confirm_warn "Proceed? [y/N]: "
# Displays preview, handles already-at-target case
```

## Environment Variables

### Input Variables (set by user or command flags)

- `HUG_FORCE`: If `true`, skips confirmation prompts
- `HUG_QUIET`: If set (any value), suppresses output functions
- `GIT_PREFIX`: Git prefix path (usually set automatically)

### Output Variables (exported by libraries)

**Color codes** (from hug-common):
- `RED`, `GREEN`, `YELLOW`, `BLUE`, `MAGENTA`, `CYAN`, `GREY`
- `GREEN_BRIGHT`, `YELLOW_BRIGHT`
- `NC` (No Color - reset)

## Best Practices

### 1. Always Check Git Repository

```bash
check_git_repo
```

Call this at the start of any command that needs git operations.

### 2. Use Namerefs for Output Parameters

```bash
# Good - function modifies caller's array
my_function() {
    local -n output_ref="$1"
    output_ref=("value1" "value2")
}

declare -a results
my_function results
```

### 3. Handle Dry-Run Mode

```bash
if $dry_run; then
    printf 'Dry run: Would perform operation\n'
    return 0
fi

# Actual operation here
```

### 4. Provide Helpful Error Messages

```bash
# Bad
error "Failed"

# Good
error "File '$file' does not exist in commit $commit"

# Even better
error "Cannot proceed because some affected files have uncommitted changes.
       Affected files:
         ${affected_files[@]}
       
       Solutions:
       • Use 'hug w discard-all' to discard changes
       • Use 'hug w discard <file>' for specific files"
```

### 5. Use Color Consistently

- `RED`: Errors, dangerous operations
- `GREEN`: Success, current branch
- `YELLOW`: Warnings, important notices
- `BLUE`: Info messages
- `GREY`: Secondary/less important info

### 6. Respect Environment Variables

Always check `HUG_QUIET` before output and `HUG_FORCE` before confirmations.

## Command Structure Patterns

All Hug command scripts should follow consistent structural patterns for maintainability and code elegance.

### Standard Full Command Pattern

```bash
#!/usr/bin/env bash
CMD_BASE="$(readlink -f "$0" 2>/dev/null || greadlink -f "$0")" || CMD_BASE="$0"; CMD_BASE="$(dirname "$CMD_BASE")"
for f in hug-common hug-git-kit; do . "$CMD_BASE/../lib/$f"; done # Load common constants and functions
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Part of the Hug tool suite

show_help() {
  cat <<'EOF'
Usage: hug <command> [OPTIONS] [ARGS]

Description of what the command does.

Options:
  -f, --force      Skip confirmation prompt
      --dry-run    Preview without making changes
  -h, --help       Show this help

Examples:
  hug command example1
  hug command example2
EOF
}

# Parse arguments
dry_run=false
force=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -f|--force)
      force=true
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      error "unknown option: $1"
      show_help >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

# Set HUG_FORCE if needed
if [[ $force == true ]]; then
  export HUG_FORCE=true
fi

# Validate we're in a git repo
check_git_repo

# Main command logic here
# ...
```

### Simple Wrapper Command Pattern

For commands that are just aliases to other commands with specific flags:

```bash
#!/usr/bin/env bash
# Part of the Hug tool suite

# Alias for hug command --flag
exec hug command --flag "$@"
```

Or for slightly more complex wrappers:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Description of what this wrapper does
exec hug base-command -u -s "$@"
```

### Gateway Command Pattern

For commands that dispatch to sub-commands (like `git-h` and `git-w`):

```bash
#!/usr/bin/env bash
# git-x - Command category gateway
# Part of the Hug tool suite

set -euo pipefail  # Exit on error, undefined vars, pipe failures

case "${1:-}" in
  subcommand1)  shift; git x-subcommand1 "$@" ;;
  subcommand2)  shift; git x-subcommand2 "$@" ;;
  *)
    echo "Usage: hug x <subcommand>"
    echo "Available subcommands:"
    echo "  subcommand1  - Description"
    echo "  subcommand2  - Description"
    exit 1
    ;;
esac
```

### Help Function Naming

**Always use `show_help()` for consistency**, not `usage()`.

Benefits:
- Consistent across all commands
- Easier to grep and find
- Aligns with common conventions

### Confirmation Pattern

**Use `prompt_confirm_danger()` from hug-common**, not custom `confirm()` functions.

```bash
# Good - uses library function
if ! $force; then
  printf 'About to delete files:\n'
  print_list 'Files' "${files[@]}"
  prompt_confirm_danger 'delete'  # User types "delete" to confirm
fi

# Bad - duplicate implementation
confirm() {
  local prompt=$1 expected=$2 reply
  read -r -p "$prompt" reply
  # ...
}
```

Benefits of `prompt_confirm_danger()`:
- Respects `HUG_FORCE` environment variable
- Consistent output formatting with `info()`
- No code duplication
- Automatic cancellation handling

### Library Sourcing

**Always use the loop pattern** for consistency:

```bash
# Good - consistent pattern
for f in hug-common hug-git-kit; do . "$CMD_BASE/../lib/$f"; done

# Avoid - individual sourcing (harder to maintain)
. "$CMD_BASE/../lib/hug-common"
. "$CMD_BASE/../lib/hug-git-kit"
```

### Dry-Run Support

Commands that modify files should support `--dry-run`:

```bash
if $dry_run; then
  printf 'Dry run: Would perform these actions:\n'
  print_list 'Files to modify' "${files[@]}"
  return 0
fi

# Actual operation here
```

### Force Flag Support

Destructive commands should support `-f/--force`:

```bash
if [[ $force == true ]]; then
  export HUG_FORCE=true
fi

# Later, confirmations will be skipped if HUG_FORCE is set
```

## Testing Changes

After modifying libraries, test:

1. **ShellCheck**: `shellcheck git-config/lib/hug-*`
2. **Source test**: `bash -c '. git-config/lib/hug-common && . git-config/lib/hug-git-kit && echo OK'`
3. **Command test**: Try several commands to ensure no breakage

## Contributing

When adding new functions:

1. **Document thoroughly**: Include usage, parameters, returns, and examples
2. **Use consistent patterns**: Follow existing function structure
3. **Add section headers**: Group related functions with `###` headers
4. **Test with ShellCheck**: Ensure no warnings (or add suppressions with explanations)
5. **Consider reusability**: Make functions generic enough for multiple use cases
6. **Handle errors gracefully**: Provide helpful error messages

When adding new commands:

1. **Follow the standard patterns** described above
2. **Use `show_help()` for help text**, not `usage()`
3. **Source libraries with the loop pattern**
4. **Use library functions** instead of duplicating code (e.g., `prompt_confirm_danger()`)
5. **Support common flags** where appropriate (`--dry-run`, `-f/--force`, `-h/--help`)
6. **Test with ShellCheck** to ensure quality

## Examples

See the command scripts in `../bin/` for real-world usage examples:

- `git-w-discard`: Complex file state management with dry-run support
- `git-h-back`: HEAD movement operations with confirmation
- `git-w-purge`: Untracked file handling
- `git-bll`: Branch listing with details
- `git-s`: Status display with colors
- `git-w-wipe`: Simple wrapper command
- `git-h`: Gateway command pattern

## Testing

Library functions are tested using BATS (Bash Automated Testing System). Test files are located in `../../tests/lib/`:

**Test Organization:**
- `test_hug-common.bats`: Tests for hug-common library
- `test_hug-git-kit.bats`: Tests for hug-git-kit main entry point
- `test_hug-git-repo.bats`: Tests for repository validation functions
- `test_hug-git-state.bats`: Tests for working tree state functions
- `test_hug-git-files.bats`: Tests for file listing functions
- `test_hug-git-commit.bats`: Tests for commit range analysis functions
- Additional test files for other library modules

**Running Tests:**
```bash
make test-lib        # Run all library tests
make test           # Run all tests (library + unit + integration)
```

**Writing Tests:**
When adding or modifying library functions, always add corresponding tests:

1. Use `setup()` to create test repositories and fixtures
2. Use `teardown()` to clean up
3. Test both success and failure cases
4. Use BATS assertions (`assert_success`, `assert_failure`, `assert_output`)
5. Keep tests focused and independent

See existing test files for patterns and examples.
