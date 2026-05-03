# Worktree Branch-as-Default Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Redesign worktree commands so branch names are the default positional argument, replacing `-B`/`--branch` flags and path/search positionals with cleaner interfaces.

**Architecture:** Single big-bang commit changing 5 command scripts. Library layer (Bash + Python) requires no changes — only CLI argument parsing in command scripts is modified. All `-B`/`--branch` flags are removed; positional args become branch names (exact match); `-s/--search` provides substring matching; `-p/--path` provides path targeting.

**Tech Stack:** Bash (GNU getopt for arg parsing), BATS tests, Python worktree modules (unchanged).

---

### Task 1: Update git-wtdel — positional branches, -p/--path, remove -B

**Files:**
- Modify: `git-config/bin/git-wtdel`

**Step 1: Rewrite the help text (show_help function, lines 12-60)**

Replace the help text to reflect the new interface:

```bash
show_help() {
  cat << 'EOF'
hug wtdel: Remove worktree(s) safely

USAGE:
    hug wtdel [branch...] [options]
    hug wtdel -p <path> [options]
    hug wtdel -h|--help

ARGUMENTS:
    [branch...]       One or more branch names (exact match, removes worktree for each)

OPTIONS:
    -p, --path PATH   Target worktree by filesystem path (repeatable for batch)
    -f, --force       Skip confirmation prompts and remove even with uncommitted changes
    --dry-run         Show what would be removed without actually removing
    -h, --help        Show this help

DESCRIPTION:
    Removes Git worktree(s) safely. If no branch or path is provided, shows
    an interactive menu of all available worktrees for selection.

    Safety features:
    - Prevents removal of current worktree
    - Warns about uncommitted changes (unless --force is used)
    - Requires confirmation before deletion (unless --force is used)
    - Automatically cleans up Git worktree metadata
    - Supports batch removal of multiple worktrees

EXAMPLES:
    hug wtdel                                 # Interactive selection
    hug wtdel feature-auth                    # Remove worktree for branch "feature-auth"
    hug wtdel feat-1 feat-2 feat-3            # Batch remove by branch names
    hug wtdel feature-auth --dry-run          # Preview removal
    hug wtdel feature-auth -f                 # Force remove without confirmation
    hug wtdel -p /path/to/worktree            # Remove by path
    hug wtdel -p /path/a -p /path/b --force  # Batch remove by paths

SEE ALSO:
    hug wt      List and switch between worktrees
    hug wtc     Create worktree for existing branch
    hug wtl     List worktrees with optional branch filtering

FURTHER READING:
    See 'git worktree remove --help' for underlying implementation details.
EOF
}
```

**Step 2: Rewrite the argument parsing (lines 82-166)**

Replace the entire getopt + while loop + branch resolution block with:

```bash
check_git_repo

# Parse arguments using getopt
set +e
PARSED=$(getopt --options hp:f --longoptions help,force,dry-run,path: --name "hug wtdel" -- "$@" 2>&1)
getopt_status=$?
set -e

if [ $getopt_status -ne 0 ]; then
  if [ -n "$PARSED" ]; then
    echo "$PARSED" >&2
  fi
  exit 1
fi

eval set -- "$PARSED"

# Initialize variables
force=false
dry_run=false
declare -a branch_names=()
declare -a explicit_paths=()

# Process options
while true; do
  case "$1" in
  -h | --help)
    show_help
    exit 0
    ;;
  -f | --force)
    force=true
    shift
    ;;
  --dry-run)
    dry_run=true
    shift
    ;;
  -p | --path)
    explicit_paths+=("$2")
    shift 2
    ;;
  --)
    shift
    break
    ;;
  *)
    error "Internal error in option parsing"
    ;;
  esac
done

# Check HUG_FORCE environment variable
if [[ ${HUG_FORCE:-} == true ]]; then
  force=true
fi

# Parse positional arguments as branch names
while [[ $# -gt 0 ]]; do
  branch_names+=("$1")
  shift
done

# Validate: can't mix branch names and explicit paths
if [[ ${#branch_names[@]} -gt 0 && ${#explicit_paths[@]} -gt 0 ]]; then
  error "Branch names and --path are mutually exclusive. Use one or the other."
  exit 1
fi

# Resolve branch names to worktree paths
declare -a worktree_paths=()
if [[ ${#branch_names[@]} -gt 0 ]]; then
  main_worktree=$(get_main_worktree_path)
  for bn in "${branch_names[@]}"; do
    worktree_path=$(get_worktree_path_by_branch "$bn" || true)
    if [[ -z "$worktree_path" ]]; then
      error "No worktree found for branch '$bn'"
      exit 1
    fi
    if [[ "$worktree_path" == "$main_worktree" ]]; then
      error "Cannot remove the main worktree (branch '$bn'). Use a different branch or specify -p for path."
      exit 1
    fi
    worktree_paths+=("$worktree_path")
  done
elif [[ ${#explicit_paths[@]} -gt 0 ]]; then
  worktree_paths=("${explicit_paths[@]}")
fi
```

The rest of the file (from line 168 onwards — relative path resolution, interactive menu, batch processing loop, batch summary) stays **unchanged**. The only difference is how `worktree_paths` gets populated.

**Step 3: Verify the change manually**

Run: `hug help wtdel`
Expected: New help text with branch-first usage, `-p/--path` flag, no `-B`.

---

### Task 2: Update git-wtl — positional branches, -s/--search, remove -B

**Files:**
- Modify: `git-config/bin/git-wtl`

**Step 1: Rewrite the help text (lines 9-51)**

```bash
show_help() {
  cat << 'EOF'
hug wtl: List worktrees in short format, showing path, branch, and status.

USAGE:
  hug wtl [OPTIONS] [branch...]

ARGUMENTS:
  [branch...]         Filter by exact branch name (case-sensitive, OR logic)

OPTIONS:
  -h, --help          Show this help message and exit.
  --json              Output in JSON format instead of human-readable text.
  -s, --search TERM   Filter by substring match on path or branch (case-insensitive, repeatable, OR logic)

DESCRIPTION:
  Displays each worktree sorted alphabetically. The current worktree is highlighted in green and marked with an asterisk (*).
  Each entry shows: path [branch] [status indicators] (short commit).

  Indicators:
    *  current worktree
    +  dirty (uncommitted changes)
    #  locked
    @  detached HEAD
    .  (inactive)

  Filtering:
    - Branch (positional): Exact match, case-sensitive. Multiple = OR logic.
    - -s / --search: Case-insensitive substring match on path or branch. Multiple = OR logic.
    - Combined: Both filters must match (AND logic)

EXAMPLES:
  hug wtl                       # List all worktrees
  hug wtl feature-auth          # List worktrees on branch "feature-auth" (exact match)
  hug wtl feat-1 feat-2         # List worktrees on "feat-1" OR "feat-2"
  hug wtl -s feature            # List worktrees containing "feature" (substring)
  hug wtl -s auth -s api        # Substring search: "auth" OR "api"
  hug wtl feat-1 -s api         # Branch is "feat-1" AND path/branch contains "api"
  hug wtl --json                # Output in JSON format

SEE ALSO:
  hug wtll : For listing worktrees in long form
  hug wt   : For interactive worktree selection and switching
  hug wtdel : For removing worktrees safely
EOF
}
```

**Step 2: Rewrite the argument parsing (lines 53-82)**

Replace the entire parsing block with:

```bash
# Parse arguments
json_output=false
declare -a branch_filters=()
declare -a search_terms=()
while [[ $# -gt 0 ]]; do
  case "$1" in
  --json)
    json_output=true
    shift
    ;;
  -s | --search)
    if [[ -z "${2:-}" ]]; then
      error "--search requires a value"
      exit 1
    fi
    search_terms+=("$2")
    shift 2
    ;;
  -h | --help)
    show_help
    exit 0
    ;;
  *)
    # Treat non-flag arguments as branch names (exact match)
    branch_filters+=("$1")
    shift
    ;;
  esac
done

# Convert arrays to space-separated strings for passing to functions
branch_filters_str="${branch_filters[*]:-}"
search_terms_str="${search_terms[*]:-}"
```

**Step 3: Update the filter_worktrees call (line 122)**

The call at line 122 passes `"$search_terms"` (previously `$*` from positional args). Now it should pass `"$search_terms_str"`:

```bash
if ! filter_worktrees filtered_paths filtered_branches filtered_commits filtered_dirty filtered_locked "$branch_filters_str" "$search_terms_str"; then
```

Same change on line 94 for JSON output:

```bash
output_worktree_json "$current_worktree" "$search_terms_str" "$branch_filters_str"
```

**Step 4: Update the filter condition check (line 116)**

Replace:
```bash
if [[ -n "$branch_filters_str" || -n "$search_terms" ]]; then
```
With:
```bash
if [[ -n "$branch_filters_str" || -n "$search_terms_str" ]]; then
```

**Step 5: Verify**

Run: `hug help wtl`
Expected: New help text, no `-B` references.

---

### Task 3: Update git-wtll — positional branches, -s/--search, remove -B

**Files:**
- Modify: `git-config/bin/git-wtll`

This is structurally identical to Task 2 (git-wtl). Apply the same changes:

**Step 1: Rewrite the help text** — Same pattern as wtl but with "long format" descriptions. Update SEE ALSO to remove `hug wtwp` reference.

**Step 2: Rewrite the argument parsing** — Identical to wtl changes:
- `-B | --branch)` case becomes `*)` for branch names
- Add `-s | --search` case
- Replace `$search_terms` with `$search_terms_str` everywhere
- Replace `$*` capture with arrays

**Step 3: Update filter_worktrees call** — Same as wtl:
- `output_worktree_json` call: pass `"$search_terms_str"` instead of `"$search_terms"`
- `filter_worktrees` call: pass `"$search_terms_str"` instead of `"$search_terms"`
- Filter condition: `"$search_terms_str"` instead of `"$search_terms"`

**Step 4: Verify**

Run: `hug help wtll`

---

### Task 4: Update git-wtsh — positional branches, -s/--search

**Files:**
- Modify: `git-config/bin/git-wtsh`

**Step 1: Rewrite the help text (lines 9-57)**

Update to show branch positional and -s/--search:

```bash
show_help() {
  cat << 'EOF'
hug wtsh: Show detailed information about worktrees.

USAGE:
  hug wtsh [OPTIONS] [branch...]
  hug wtsh --           # Interactive worktree selection

ARGUMENTS:
  [branch...]         Filter by exact branch name (case-sensitive, OR logic)

OPTIONS:
  -h, --help          Show this help message and exit.
  -a, --all           Show all worktrees
  -s, --search TERM   Filter by substring match on path or branch (case-insensitive, repeatable, OR logic)

DESCRIPTION:
  Displays detailed information about worktrees with flexible viewing options:

  DEFAULT BEHAVIOR (no arguments):
    Shows details for the CURRENT worktree only.

  --all FLAG:
    Shows details for ALL worktrees.

  BRANCH NAME (positional):
    Filter by exact branch name match (case-sensitive).
    Multiple branches use OR logic.

  -s / --search:
    Case-insensitive substring match on path or branch name.
    Multiple -s flags use OR logic.
    Combined with branch: AND logic between both filter stages.

  -- (interactive mode):
    Presents an interactive menu to select which worktree to display.

EXAMPLES:
  hug wtsh                   # Current worktree only
  hug wtsh --all             # All worktrees
  hug wtsh feature-auth      # Show worktree on branch "feature-auth" (exact match)
  hug wtsh feat-1 feat-2     # Show worktrees on "feat-1" OR "feat-2"
  hug wtsh -s auth            # Substring search for "auth"
  hug wtsh --                # Interactive worktree selection

SEE ALSO:
  hug wtl  : For listing worktrees in short form
  hug wtll : For listing worktrees in long form
  hug wt   : For interactive worktree selection and switching
EOF
}
```

**Step 2: Rewrite the argument parsing (lines 295-321)**

Replace the custom flag parsing with:

```bash
# Parse common flags to detect -- pattern and standard flags
eval "$(parse_common_flags "$@")"

# Initialize behavior flags
show_all=false
declare -a branch_filters=()
declare -a search_terms_list=()

# Parse custom flags
while [[ $# -gt 0 ]]; do
  case "$1" in
  --all | -a)
    show_all=true
    shift
    ;;
  -s | --search)
    if [[ -z "${2:-}" ]]; then
      error "--search requires a value"
      exit 1
    fi
    search_terms_list+=("$2")
    shift 2
    ;;
  -h | --help)
    show_help
    exit 0
    ;;
  -*)
    error "Unknown option: $1"
    show_help
    exit 1
    ;;
  *)
    # Treat non-flag arguments as branch names (exact match)
    branch_filters+=("$1")
    shift
    ;;
  esac
done
```

**Step 3: Update the dispatch logic (lines 346-371)**

Replace the section that handles different command modes. The key change: when `$# > 0` previously meant search terms, now we need to check for branches OR search terms:

```bash
# Build filter strings
branch_filters_str="${branch_filters[*]:-}"
search_terms_str="${search_terms_list[*]:-}"

# Handle different command modes
if [[ "${HUG_INTERACTIVE_FILE_SELECTION:-}" == "true" ]]; then
  interactive_worktree_selection "$current_worktree" "${worktree_paths[@]}"
elif [[ "$show_all" == "false" && -z "$branch_filters_str" && -z "$search_terms_str" ]]; then
  # Default: show current worktree only
  show_current_worktree_only "$current_worktree"
elif [[ -n "$branch_filters_str" || -n "$search_terms_str" ]]; then
  # Filtering by branch names and/or search terms
  declare -a filtered_paths=() filtered_branches=() filtered_commits=()
  declare -a filtered_dirty=() filtered_locked=()
  if ! filter_worktrees filtered_paths filtered_branches filtered_commits filtered_dirty filtered_locked "$branch_filters_str" "$search_terms_str"; then
    exit 1
  fi

  # Show details for matching worktrees (filtered=true: show exact count)
  show_worktree_details "$current_worktree" --filtered "${filtered_paths[@]}"
else
  # --all or -a behavior
  show_worktree_details "$current_worktree" "${worktree_paths[@]}"
fi
```

**Step 4: Verify**

Run: `hug help wtsh`

---

### Task 5: Simplify git-wtwp — direct pass-through to wtl

**Files:**
- Modify: `git-config/bin/git-wtwp`

**Step 1: Simplify to transparent delegation**

Since `git-wtl` now accepts branch names as positional args, `wtwp` no longer needs to wrap them in `--branch` flags:

```bash
#!/usr/bin/env bash
# git-wtwp: List worktrees filtered by exact branch names
# Thin wrapper: delegates to git-wtl with positional branch args

show_help() {
  cat << 'EOF'
hug wtwp: List worktrees filtered by exact branch names.

USAGE:
  hug wtwp [OPTIONS] <branch> [branch...]

OPTIONS:
  -h, --help     Show this help message and exit.
  --json         Output in JSON format instead of human-readable text.

DESCRIPTION:
  Displays worktrees that are checked out to the specified branch(es).
  Multiple branches can be specified (OR logic: worktrees on any of the branches).

  This is equivalent to: hug wtl <branch1> <branch2> ...

EXAMPLES:
  hug wtwp main                 # List worktrees on branch "main"
  hug wtwp feat-1 feat-2        # List worktrees on "feat-1" OR "feat-2"
  hug wtwp main --json          # JSON output for worktrees on "main"

SEE ALSO:
  hug wtl  : For listing worktrees with substring search
  hug wtll : For listing worktrees in long form
  hug wt   : For interactive worktree selection and switching
  hug wtdel : For removing worktrees safely
EOF
}

# Parse help flag before delegating
case "${1:-}" in
-h | --help)
  show_help
  exit 0
  ;;
esac

# Delegate directly to git-wtl — positional args are already branch names
CMD_BASE="$(readlink -f "$0" 2> /dev/null || greadlink -f "$0")" || CMD_BASE="$0"
CMD_BASE="$(dirname "$CMD_BASE")"

exec "${CMD_BASE}/git-wtl" "$@"
```

**Step 2: Verify**

Run: `hug help wtwp`

---

### Task 6: Update all worktree test files

**Files:**
- Modify: `tests/unit/test_worktree_list.bats`
- Modify: `tests/unit/test_worktree_remove.bats`
- Modify: `tests/unit/test_worktree_show.bats`

**Step 1: Update test_worktree_list.bats**

The key changes:
- **Search term tests** (lines 221-251, 449-544): These tests pass positional args like `git-wtl feature` and `git-wtl FEATURE`. Since positionals are now branch names (exact match, case-sensitive), `feature` won't match branch `feature-1` and `FEATURE` won't match anything. These must be changed to use `-s`:
  - `git-wtl feature` → `git-wtl -s feature`
  - `git-wtl "$(basename "$FEATURE_WT")"` → `git-wtl -s "$(basename "$FEATURE_WT")"`
  - `git-wtl FEATURE` → `git-wtl -s FEATURE`
  - `git-wtl nonexistent` → `git-wtl -s nonexistent`
  - `git-wtl feature hotfix` → `git-wtl -s feature -s hotfix`
  - `git-wtl FEATURE HOTFIX` → `git-wtl -s FEATURE -s HOTFIX`
  - `git-wtl nonexistent1 nonexistent2` → `git-wtl -s nonexistent1 -s nonexistent2`
  - `git-wtll feature hotfix` → `git-wtll -s feature -s hotfix`
  - etc.

- **Branch filter tests** (lines 547-604): Replace `--branch` with positional args:
  - `git-wtl --branch feature-1` → `git-wtl feature-1`
  - `git-wtl --branch feature-1 --branch hotfix-1` → `git-wtl feature-1 hotfix-1`
  - `git-wtl --branch nonexistent` → `git-wtl nonexistent`
  - `git-wtl --branch feature-1 "$(basename "$FEATURE_WT")"` → `git-wtl feature-1 -s "$(basename "$FEATURE_WT")"`
  - `git-wtl --branch feature-1 "nonexistent-path"` → `git-wtl feature-1 -s nonexistent-path`
  - `git-wtl --branch Feature-1` → `git-wtl Feature-1` (still case-sensitive, still fails)
  - `git-wtl --json --branch feature-1` → `git-wtl --json feature-1`

- **JSON multi-term tests** (lines 524-543): Update search invocations to use `-s`:
  - `git-wtl --json feature` → `git-wtl --json -s feature`
  - `git-wtll --json feature` → `git-wtll --json -s feature`

- **Mixed branch+search tests** (lines 577-587): Update to use positional + -s:
  - `git-wtl --branch feature-1 "$(basename "$FEATURE_WT")"` → `git-wtl feature-1 -s "$(basename "$FEATURE_WT")"`
  - `git-wtl --branch feature-1 "nonexistent-path"` → `git-wtl feature-1 -s nonexistent-path`

- **wtwp tests** (lines 606-641): These should continue to pass as-is since wtwp still accepts `<branch>` positionals. Update the description line in the help test if needed. The key change: `git-wtwp feature-1 --json` should still work since wtwp passes through to wtl.

- **Error message test** (line 574): `assert_output --partial "--branch nonexistent"` needs updating since the error message no longer references `--branch`. Change to just check for "No worktrees found matching".

**Step 2: Update test_worktree_remove.bats**

The key changes:
- **Path-based tests** (lines 36-117): Tests that pass `$FEATURE_WT` as positional now need to use `-p`:
  - `git-wtdel "$FEATURE_WT" --force` → `git-wtdel -p "$FEATURE_WT" --force`
  - `git-wtdel "$FEATURE_WT" --dry-run` → `git-wtdel -p "$FEATURE_WT" --dry-run`
  - `git-wtdel "$FEATURE_WT"` → `git-wtdel -p "$FEATURE_WT"`
  - etc. Every test that uses a path positionally needs `-p`.

- **Branch flag tests** (lines 280-313): Replace `--branch` with positional:
  - `git-wtdel --branch feature-1 --force` → `git-wtdel feature-1 --force`
  - `git-wtdel --branch nonexistent-branch` → `git-wtdel nonexistent-branch`
  - `git-wtdel --branch feature-1 --dry-run` → `git-wtdel feature-1 --dry-run`
  - `git-wtdel --branch feature-1 "$FEATURE_WT"` → This test was for mutual exclusivity. Now it's branch names + -p that are exclusive: `git-wtdel feature-1 -p "$FEATURE_WT"`. Update assertion to match new error message.

- **Main worktree protection** (line 409-419): `git-wtdel --branch "$main_branch"` → `git-wtdel "$main_branch"`

- **Batch tests** (lines 317-361): Two patterns:
  - Path batches: `git-wtdel "$FEATURE_WT" "$HOTFIX_WT" --force` → `git-wtdel -p "$FEATURE_WT" -p "$HOTFIX_WT" --force`
  - Branch batches (new): Add new tests for `git-wtdel feature-1 hotfix-1 --force`

- **Relative path test** (lines 225-236): `git-wtdel "$relative_path" --force` → `git-wtdel -p "$relative_path" --force`

- **Not-in-repo tests** (line 270-276): `git-wtdel "/some/path"` → `git-wtdel -p "/some/path"` (or `git-wtdel some-branch`)

**Step 3: Update test_worktree_show.bats**

The key changes:
- **Search tests** (lines 123-129, 174-199, 418-521): Positionals that were search terms become branch names. Use `-s` for substring search:
  - `git-wtsh nonexistent` → `git-wtsh -s nonexistent` (substring search)
  - `git-wtsh main` → This already works as exact branch match for "main". Keep as-is.
  - `git-wtsh MAIN` → `git-wtsh -s MAIN` (was case-insensitive search, now needs -s)
  - `git-wtsh "$(basename "$TEST_REPO")"` → `git-wtsh -s "$(basename "$TEST_REPO")"` (path substring)
  - Multi-term tests: `git-wtsh feature hotfix` → `git-wtsh -s feature -s hotfix`
  - `git-wtsh TEST NEW` → `git-wtsh -s TEST -s NEW`
  - `git-wtsh nonexistent1 nonexistent2 nonexistent3` → `git-wtsh -s nonexistent1 -s nonexistent2 -s nonexistent3`
  - `git-wtsh foo bar baz` → `git-wtsh -s foo -s bar -s baz`

**Step 4: Add new positional branch tests**

Add tests for the new exact-match positional behavior:

In `test_worktree_list.bats`:
```bash
@test "hug wtl: positional branch filters by exact name" {
  cd "$TEST_REPO"
  run git-wtl feature-1
  assert_success
  assert_output --partial "feature-1"
  refute_output --partial "hotfix-1"
  refute_output --partial "main"
}

@test "hug wtl: multiple positional branches (OR logic)" {
  cd "$TEST_REPO"
  run git-wtl feature-1 hotfix-1
  assert_success
  assert_output --partial "feature-1"
  assert_output --partial "hotfix-1"
  refute_output --partial "main"
}
```

In `test_worktree_remove.bats`:
```bash
@test "hug wtdel: positional branch removes worktree" {
  cd "$TEST_REPO"
  run git-wtdel feature-1 --force
  assert_success
  assert_output --partial "Worktree removed"
  assert_worktree_not_exists "$FEATURE_WT"
}

@test "hug wtdel: multiple positional branches batch removes" {
  cd "$TEST_REPO"
  run git-wtdel feature-1 hotfix-1 --force
  assert_success
  assert_output --partial "Batch Removal Summary"
  assert_output --partial "Removed: 2"
  assert_worktree_not_exists "$FEATURE_WT"
  assert_worktree_not_exists "$HOTFIX_WT"
}
```

In `test_worktree_show.bats`:
```bash
@test "hug wtsh: positional branch shows exact match" {
  cd "$TEST_REPO"
  git branch feature-test
  local worktree_path="${TEST_REPO}-feature"
  git worktree add "$worktree_path" feature-test

  run git-wtsh feature-test
  assert_success
  assert_output --partial "feature-test"
  refute_output --partial "main"

  git worktree remove "$worktree_path"
  git branch -D feature-test
}
```

**Step 5: Run the tests to verify each file individually**

```bash
make test-unit TEST_FILE=test_worktree_list.bats TEST_SHOW_ALL_RESULTS=1
make test-unit TEST_FILE=test_worktree_remove.bats TEST_SHOW_ALL_RESULTS=1
make test-unit TEST_FILE=test_worktree_show.bats TEST_SHOW_ALL_RESULTS=1
```

---

### Task 7: Run full test suite and verify

**Step 1: Run the full test suite**

```bash
make test TEST_SHOW_ALL_RESULTS=1
```

Expected: All tests pass (0 failures).

**Step 2: If any tests fail, diagnose and fix**

Common failure patterns to check:
- Error messages referencing `--branch` that need updating
- Tests still using `-B` or `--branch` flags
- Tests passing search terms as positionals without `-s`
- Tests passing paths as positionals without `-p`

**Step 3: Re-run until clean**

```bash
make test
```

Expected: "All tests passed!"

---

### Task 8: Commit all changes

**Step 1: Review all changes**

```bash
hug sw  # Show all staged + unstaged changes
```

Verify:
- 5 command scripts modified (wtdel, wtl, wtll, wtsh, wtwp)
- 3 test files modified
- No unintended changes to library files
- No changes to Python modules

**Step 2: Stage and commit**

```bash
hug a git-config/bin/git-wtdel git-config/bin/git-wtl git-config/bin/git-wtll git-config/bin/git-wtsh git-config/bin/git-wtwp
hug a tests/unit/test_worktree_list.bats tests/unit/test_worktree_remove.bats tests/unit/test_worktree_show.bats
```

Commit message:

```
refactor: make branch the default positional in worktree commands

WHY: Worktrees are identified by branch in virtually every user-facing
scenario, yet the CLI required -B/--branch flags for branch targeting in
wtdel, wtl, and wtll while using paths or search terms as positionals.
This created unnecessary friction for the most common operation.

WHAT: Redesigned all worktree command interfaces so branch names are the
default positional argument. Removed all -B/--branch flags. Added -s/--search
for substring matching (replaces old positional search) and -p/--path for
path targeting (replaces old positional paths in wtdel). Simplified wtwp
to transparent pass-through since wtl now accepts branches positionally.

HOW: Only CLI argument parsing in command scripts changed — no library
or Python module modifications needed. The clean separation between CLI
parsing and library logic (filter_worktrees, get_worktree_path_by_branch)
made this a pure surface-level change.

Command interface changes:
  wtdel: [path...] [-B branch] → [branch...] [-p path]
  wtl:   [SEARCH] [-B branch]  → [branch...] [-s search]
  wtll:  [SEARCH] [-B branch]  → [branch...] [-s search]
  wtsh:  [SEARCH]              → [branch...] [-s search]
  wtwp:  simplified to pass-through to wtl

IMPACT: Shorter, more intuitive commands:
  hug wtdel feature-auth  (was: hug wtdel -B feature-auth)
  hug wtl feature-auth    (was: hug wtl -B feature-auth)
  hug wtll feature-auth   (was: hug wtll -B feature-auth)

Co-Authored-By: Claude <noreply@anthropic.com>
```
