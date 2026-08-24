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
- Uniform pathspec contract helpers (#292): `parse_common_flags_with_pathspecs`
  (split args at the first `--` into pre-args + pathspecs, then parse common
  flags on the pre-args only), `pathspec_pathspecs_into` (read the collected
  pathspecs into a caller-named array), `forward_pathspecs_to_picker`
  (append them to a picker option array behind a protective `--`), and
  `drain_pathspecs_after_separator` (the shared `--)` arm for
  separator-aware option loops — used by output_json_status, hug-git-json,
  and hug-select-files), `pathspecs_nonempty` (predicate — true iff the split collected
  post-`--` pathspec data), `error_unknown_option` (the short-form
  unknown-option usage rejection, exit 2), and
  `guard_single_file_candidates` (the two-stream single-file guard:
  loud empty-positional + pre-`--` unknown-option checks, verbatim
  post-`--` data merge, truthful cardinality, survivor written to a
  caller-named variable — used by git-fa/-fb/-fborn/-fcon)

**The parsing-order rule (structural, #292):** the pathspec split runs
BEFORE any other argument inspection — a command adopting the contract
calls `parse_common_flags_with_pathspecs` first, then its own loop sees
only pre-`--` args. Consequences every command script must preserve:
(1) a trailing bare `--` never survives the split (picker callers opt in
via `--picker`; everyone else gets it consumed inertly), (2) the
own-loop's `-*` arm is the loud unknown-option rejection — bare
positionals collect as pathspecs (git parity), and (3) post-`--` data is
verbatim pathspec data, so any forwarding to git or a picker goes behind
a protective second `--` (see `forward_pathspecs_to_picker`). The
user-facing contract this implements is documented in
`hug help :pathspec` (`git-config/lib/python/articles/pathspec.md`).

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
- Working tree state checks:
  - **Two-predicate dirty-detection model**: Hug uses two distinct predicates for different decision points:
    - `has_uncommitted_tracked_changes` -- tracked-only (staged + unstaged), excludes untracked. Used for **tier/safety decisions** AND for the **aligned-target gating** in `handle_standard_operation` (the skip-when-aligned decision), because no reset mode (`--soft`/`--mixed`/`--keep`/`--hard`) touches untracked files, so untracked files are irrelevant to safety.
    - `has_untracked_or_pending_changes` (renamed from `has_pending_changes`) -- tracked + untracked (the broadest dirtiness predicate). Used where untracked files matter contextually (e.g. `git-caa`, `git-rb`, `git-w-wip`) -- NOT for the aligned-target gate, which uses the tracked-only predicate above.
    - **Alignment vs. dirtiness:** alignment itself (whether two refs resolve to the same commit) is tested with `is_same_commit` -- NEVER with `count_commits_in_range … == 0` (which also reads `0` when one ref is *behind*). See the "Range counting" subsection under Commit Range Analysis.
  - Other state checks: `has_staged_changes`, `has_unstaged_changes`
- Cleanliness validation (`check_working_tree_clean`, `check_files_clean`)
- File state checking (`check_file_in_commit`, `check_file_staged`, `check_file_unstaged`)
- Binary file detection (`is_binary_staged`)
- Change preview (`preview_file_changes`)

#### hug-git-files
- List staged files (`list_staged_files`)
- List unstaged files (`list_unstaged_files`)
- List untracked files (`list_untracked_files`)
- List ignored files (`list_ignored_files`)
- List conflicted files (`list_conflicted_files`)
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
- Count commits in range (`count_commits_in_range` strict, `count_commits_in_range_or_zero` display-only)
- Identity and signed distance (`is_same_commit`, `commit_offset`) -- see "Range counting" below
- List changed files (`list_changed_files_in_range`, `count_changed_files_in_range`)
- Print commit lists (`print_commit_list_in_range`)
- Preview helpers (`print_preview_summary`, `print_commit_list_header`)
- Amend safety guards (`guard_content_null_amend`, `amend_args_message_intent`, `amend_editor_is_noop`) -- `cmod`/`cmoda` call these to refuse a content-null amend (no staged/modified content AND no message change) with exit 3 instead of silently rewriting HEAD's hash; `-f`/`HUG_FORCE` is the deliberate re-hash hatch. `amend_args_message_intent` is a three-way classifier (0 KEEP / 1 CHANGE / 2 EDITOR decides; capture with `rc=0; fn ... || rc=$?` -- under `set -e` a bare call returning 1/2 kills the script) and fail-opens on non-decidable inputs (`--pathspec-from-file`, a rewrite-capable commit-msg hook). Call `guard_content_null_amend` BARE, never via `$(...)` -- the refusal must exit the script, not a subshell. It also sets the caller global `_amend_content_null` so the command picks an honest info line (computed once, used twice).

#### hug-git-upstream
- Handle upstream operations (`handle_upstream_operation`) -- takes a required `tier` parameter (warn/danger) for the upstream confirmation path. This closes the inverted confirmation gradient: previously every upstream path was gated at warn regardless of the operation's actual danger level.
- Handle standard operations (`handle_standard_operation`) -- aligned-target gating uses `has_uncommitted_tracked_changes` (tracked-only) for the skip-when-aligned decision. Alignment itself is tested with `is_same_commit` (exact SHA equality), NEVER a one-directional `count_commits_in_range … == 0` -- see the "Range counting" subsection. Callers invoke this helper BARE (not via `$(…)`) so its aligned-path `exit 0` terminates the mover.
- Recovery hint helper (`emit_head_recovery_hint`) -- emits the `hug h restore <SHA> --<op> -y` recovery command to stderr after a successful warn-tier HEAD-mover. Suppressed under `HUG_QUIET=T`. Used by h-back, h-undo, h-rollback, h-rewind (warn), and h-squash.
- See also: `git-h-restore` -- the recovery primitive that `emit_head_recovery_hint` prints. Uses exact-SHA no-op (never the range-count gate) so it can move HEAD forward to a descendant commit.

#### hug-git-backup
- Create backup branches (`create_backup_branch`)
- List backup branches (`get_backup_branches`)
- Extract metadata (`extract_original_name`, `format_backup_display_name`)

#### hug-git-rebase
- Check for rebase conflicts (`abort_if_no_rebase_conflict`)
- Resolve current conflict (`rebase_pick`)
- Auto-resolve all remaining conflicts (`rebase_finish_all`)

#### hug-git-diff
- Run the canonical pinned changed-files invocation (`pinned_diff`) — the ONE
  flag set for commit/range file listing: determinism pins
  (`core.quotePath=false`, `diff.relative=false`, `--ignore-submodules=none`)
  on every call, range/single dispatch, and `--null` NUL mode.
- Rename contract is two-valued and explicit: default `--find-renames` is the
  DISPLAY stance (new path only / collapsed `{old => new}` stat line — use for
  human-facing output); `--no-renames` is the ACTION-LIST stance (both sides —
  use when the list feeds staging/untrack/add operations).
- Call `show_changed_file_names` (hug-git-show) instead when you need N/-N
  shorthand resolution — it resolves then delegates here.

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
- File parsing from --name-status output (`parse_file_to_json`)
- File collection helpers (`collect_git_files_json`)
- Optimized for batch Git operations
- Handles special characters in file paths and commit messages

**File Object Schema:**
```json
{
  "path": "path/to/file",
  "status": "modified"  // added|modified|deleted|renamed|copied|conflict|untracked|ignored
}
```

**Functions:**
- `parse_file_to_json "$line"` - Parse `--name-status` output line to JSON object
  - Input: `"M\tfile.txt"` from git's --name-status
  - Output: `{"path": "file.txt", "status": "modified"}`
  - Handles renamed/copied files: `"R100\told.txt\tnew.txt"` → `{"path": "new.txt", "status": "renamed"}`
- `collect_git_files_json "$type" [flags...] [-- pathspec...]` - Collect files of a type as JSON objects
  - `$type`: `staged`|`unstaged`|`untracked`|`ignored`|`conflicted` (unknown types error)
  - Prints one JSON object PER LINE to stdout (empty when none); `mapfile -t files < <(collect_git_files_json "$type")` yields the objects AND the file count (the array length)
  - Line-per-object keeps the count truthful — a newline in a filename is escaped to `\n` by `json_escape`, so each line is exactly one object (regression pin: #247)
  - Bash-4.0-safe: no nameref, no comma-split
  - Supports `--cwd` flag for scoping
  - `-- pathspec...` scopes every underlying `list_*` call (protective separator; option-shaped pathspecs like a file named `--cwd` stay data — #292)
- `count_files_with_status <state> [pathspec...]` - Count files by state (the sl* `-c` engine)
  - `<state>`: `staged`|`unstaged`|`untracked`|`ignored`|`conflicted`|`all`|`all+untracked`
  - Prints an integer (0 when none, exit 0). NUL-safe (newline filenames count once) and Bash 4.0-safe (no nameref).
  - `all`/`all+untracked` dedup via `git status --porcelain -z` (a file staged AND unstaged counts once)
  - Enforces the repo precondition internally (`check_git_repo`): exits 1 with "Not in a git repository" when called outside a repo (parity with `list_*_files`)
- `run_count_mode [--json] <state> [pathspec...]` - Terminating wrapper for the sl* `-c/--count` dispatch
  - Encapsulates the mutual-exclusion guard + `count_files_with_status` call + `exit 0` (formerly duplicated across the 6 `sl*` dispatchers)
  - `--json` is mutually exclusive with `-c` (errors and exits); the function ALWAYS exits (never returns) — call it as a statement, never in `$(...)`

**JSON Design Philosophy:**
- Pure Bash for portability and dependency-free operation
- Computational tasks (analytics, stats) use Python helpers
- Simple formatting stays in Bash - faster startup, no dependencies
- Complex processing can use Python via subprocess calls when needed
- JSON output focuses on data transformation, not computation
- File objects use zero subprocess spawns (pure Bash IFS parsing)

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

# Scoped: pathspecs after -- filter every list call; empty scopes keep the
# envelope shape (zero-length arrays, summary counts 0)
output_json_status_unified --filter "staged" -- src/

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
# Count commits between two refs -- a ONE-DIRECTIONAL ahead-count: how far HEAD is AHEAD
# of origin/main. A result of 0 means "HEAD is NOT ahead" (true when aligned OR behind) --
# it does NOT mean "aligned". STRICT: a bad ref propagates non-zero, never swallowed to 0.
count=$(count_commits_in_range "origin/main" "HEAD")

# List changed files
files=$(list_changed_files_in_range "origin/main" "HEAD")

# Print commit list for user preview
print_commit_list_in_range "origin/main" "HEAD"
```

#### Range counting -- pick the right primitive

- **`count_commits_in_range "start" ["end"]`** -- a ONE-DIRECTIONAL ahead-count: how far
  `end` is ahead of `start`. A result of `0` means "`end` is NOT ahead of `start`" — which
  is true BOTH when `end == start` (identity) AND when `end` is *behind* `start`. **Never
  treat `0` as "aligned."** STRICT: a failed `rev-list` (invalid ref, unborn HEAD)
  propagates non-zero — it is NOT swallowed into `0`; callers must handle failure.
- **`is_same_commit "a" "b"`** -- the ONLY sanctioned identity test. A minimal pure-boolean
  predicate (exit 0 iff `a` and `b` resolve to the same commit) implemented via `git
  rev-parse --verify --quiet …^{commit}` SHA equality -- NO `rev-list` traversal. Use this
  wherever you would otherwise write `count_commits_in_range … == 0` to mean "same commit."
  It is shallow-safe (rev-parse only resolves refs; it does not walk the graph).
- **`commit_offset "a" ["b"]`** -- signed distance from `a` to `b` (default `HEAD`).
  `0` means IDENTITY (short-circuited on SHA equality), NOT merely "not ahead." Positive
  `N` = `b` is ahead of `a` (clean forward distance); negative `-N` = `b` is behind `a`
  (forward target / recovery direction). Diverged ⟹ empty stdout + exit 2 (so the
  false-zero is unrepresentable by construction). Unresolvable ref ⟹ empty stdout + exit 3.
  Use this when a caller also needs direction/magnitude, not just yes/no.
- **`count_commits_in_range_or_zero`** -- display-only twin: a cosmetic `0` on rev-list
  failure, for rendered plans / tip text only. NEVER for a branching or alignment decision.
  This is the single sanctioned `echo 0`-on-failure swallow — it appears nowhere else
  (the canary `grep -rn '<pipe><pipe> echo 0' git-config/` must stay at exactly one hit;
  here `<pipe><pipe>` stands for the shell OR operator, written obfuscatedly so this README
  doesn't itself trip the canary -- the real command greps for that operator immediately
  followed by `echo 0`).

### Operation Handlers

```bash
# For upstream operations (rewind to upstream, etc.)
# The tier parameter (warn|danger) controls which prompt function is used.
# Prints the upstream commit SHA to stdout. Its internal ahead-count is STRICT
# (count_commits_in_range) and carries `|| return 1`, so capture it with a guard
# (callers use `|| exit $?`). WHY the explicit `|| return 1` below is load-bearing, two
# axes: errexit never fires MID-BODY inside $(…) — only the substitution's FINAL status
# propagates, via the assignment — and errexit is additionally suspended throughout any
# function called from a `||` position, which is exactly how every caller invokes this
# helper. Its internal `|| return 1` guards are therefore the ONLY failure-propagation path:
target=$(handle_upstream_operation "rewinding" "warn" "rewind" "danger reason") || exit $?

# For standard operations (back, undo, etc.)
target=$(resolve_head_target "$1")
# Called BARE (a plain command, NOT $(…)): when HEAD is already at $target its
# aligned-guard runs `exit 0`, terminating the whole mover. That guard depends on the
# bare call -- do NOT capture this helper via $(…) or the exit is swallowed. Alignment
# is tested with is_same_commit (exact SHA), never a one-directional count == 0.
handle_standard_operation "moving back" "$target"
prompt_confirm_warn "Proceed? [y/N]: "   # mover confirms AFTER the helper's preview

# Identity test -- the ONLY sanctioned way to ask "same commit?":
if is_same_commit "$target" HEAD; then
    info "Already at target; nothing to do."
fi

# Emit a recovery hint after a successful warn-tier HEAD-mover:
# Prints "hug h restore <SHA> --<op> -y" to stderr.
emit_head_recovery_hint "$pre_op_head" "back"
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
