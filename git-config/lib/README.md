# Hug SCM Library Documentation

This directory contains the core library functions used by all Hug commands.

## Libraries

### hug-common

General-purpose utility functions for shell scripting.

**Features:**
- Color definitions for terminal output
- Output functions (`error`, `warning`, `info`, `success`)
- User interaction (`prompt_confirm`, `confirm_action`)
- String manipulation (`trim_message`)
- Array utilities (`dedupe_array`, `print_list`)
- File system checks (`is_symlink`)
- Command pattern helpers

### hug-git-kit

Git-specific operations and utilities.

**Features:**
- Repository validation (`check_git_repo`)
- Commit validation and ancestry checking
- Working tree state management
- File change operations (discard, wipe, purge)
- Branch information and navigation
- Commit history analysis
- Upstream operation handlers

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
# Simple yes/no confirmation (respects HUG_FORCE)
prompt_confirm "Proceed? [y/N]: "

# Require specific word confirmation
confirm_action "delete"  # User must type "delete"
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
prompt_confirm "Proceed? [y/N]: "
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

## Examples

See the command scripts in `../bin/` for real-world usage examples:

- `git-w-discard`: Complex file state management
- `git-h-back`: HEAD movement operations  
- `git-w-purge`: Untracked file handling
- `git-bll`: Branch listing with details
- `git-s`: Status display with colors
