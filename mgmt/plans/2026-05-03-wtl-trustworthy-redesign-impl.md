# Make `hug wtl` Trustworthy — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Make `hug wtl` output capture-friendly by sending only listing lines to stdout, moving legend to stderr, removing the header, and adding `-q` support.

**Architecture:** Modify `git-wtl` to adopt `parse_common_flags()` (matching `git-wtsh` pattern), remove the "Worktrees:" header, redirect legend to stderr with "Legend: " prefix. Update `print_worktree_legend()` in the library. No changes to formatting functions — `hug-terminal` already handles non-TTY color stripping via `test -t 1`. Update existing tests and add new ones.

**Tech Stack:** Bash, BATS testing, Python (no changes needed)

---

### Task 0: Update library — redirect `print_worktree_legend()` to stderr

**Files:**
- Modify: `git-config/lib/hug-git-worktree:986-993`

**Step 1: Write the failing test**

Add to `tests/lib/test_hug_git_worktree_indicators.bats`:

```bash
@test "print_worktree_legend: outputs to stderr" {
  # Run in a subshell where stdout is a TTY-equivalent (force colors via script)
  # BATS runs non-TTY, so the legend is suppressed. Use HUG_QUIET unset + force TTY.
  # We verify the function works by calling it with a pty.
  # Since BATS is non-TTY and print_worktree_legend checks -t 1, we test that
  # when called, its output goes to stderr.
  run bash -c 'source git-config/lib/hug-terminal; source git-config/lib/hug-common; source git-config/lib/hug-git-worktree; print_worktree_legend 2>/dev/null'
  assert_success
  # stdout should be empty (legend goes to stderr)
  assert_output ""
}

@test "print_worktree_legend: includes Legend prefix on stderr" {
  # Force TTY-like conditions by using script(1) to provide a pty
  if ! command -v script >/dev/null 2>&1; then
    skip "script command not available"
  fi
  run bash -c 'script -qc "source git-config/lib/hug-terminal; source git-config/lib/hug-common; source git-config/lib/hug-git-worktree; print_worktree_legend" /dev/null 2>&1'
  assert_success
  assert_output --partial "Legend:"
}
```

**Step 2: Run test to verify it fails**

Run: `make test-lib TEST_FILE=test_hug_git_worktree_indicators.bats TEST_FILTER="print_worktree_legend"`
Expected: The "outputs to stderr" test fails because legend currently goes to stdout.

**Step 3: Write minimal implementation**

In `git-config/lib/hug-git-worktree`, modify `print_worktree_legend()` (lines 986-993):

```bash
print_worktree_legend() {
    # Respect quiet mode and non-TTY
    [[ -n "${HUG_QUIET:-}" ]] && return 0
    [[ ! -t 1 ]] && return 0

    printf "  Legend: %s dirty  %s locked  %s current\n" \
        "${YELLOW}+${NC}" "${RED}#${NC}" "${GREEN}*${NC}" >&2
}
```

Changes:
1. Added "Legend: " prefix to the printf format string
2. Added `>&2` to redirect to stderr
3. Removed the trailing `\n` (the format already ends with `\n`)

**Step 4: Run test to verify it passes**

Run: `make test-lib TEST_FILE=test_hug_git_worktree_indicators.bats TEST_FILTER="print_worktree_legend"`
Expected: PASS

**Step 5: Commit**

```bash
hug a git-config/lib/hug-git-worktree tests/lib/test_hug_git_worktree_indicators.bats
hug commit -m "refactor: redirect print_worktree_legend to stderr with Legend prefix

WHY: Library functions that print user-facing messages (not data) should
use stderr so that stdout remains clean for capture. Adding 'Legend: '
prefix clarifies what the indicator line is.

IMPACT: Callers (git-wtl, git-wtll, git-wtsh) will now have the legend
on stderr instead of stdout. This is a prerequisite for clean capture
of listing output."
```

---

### Task 1: Update `git-wtl` — adopt `parse_common_flags`, remove header, redirect legend

**Files:**
- Modify: `git-config/bin/git-wtl` (full rewrite of arg parsing + output)

**Step 1: Write the failing tests**

Add to `tests/unit/test_worktree_list.bats`:

```bash
@test "hug wtl: stdout contains only listing lines (no header, no legend)" {
  cd "$TEST_REPO"
  run git-wtl

  assert_success
  refute_output --partial "Worktrees:"
  refute_output --partial "Legend:"
  assert_output --partial "main"
  assert_output --partial "feature-1"
}

@test "hug wtl: -q suppresses legend on stderr" {
  cd "$TEST_REPO"
  run git-wtl -q

  assert_success
  refute_output --partial "Legend:"
}

@test "hug wtl: piped output has no ANSI escape codes" {
  cd "$TEST_REPO"
  # Capture to file to verify no ANSI codes
  local tmpfile
  tmpfile=$(mktemp)
  git-wtl > "$tmpfile" 2>/dev/null
  # Check no ANSI escape sequences (hug-terminal strips colors in non-TTY)
  if grep -qP '\x1b\[' "$tmpfile"; then
    rm -f "$tmpfile"
    fail "Found ANSI escape codes in piped output"
  fi
  rm -f "$tmpfile"
}

@test "hug wtl: no-match error goes to stderr" {
  cd "$TEST_REPO"
  run git-wtl nonexistent

  assert_failure
  assert_output --partial "No worktrees found matching"
}

@test "hug wtl: help mentions capturing output" {
  run git-wtl --help

  assert_success
  assert_output --partial "CAPTURING OUTPUT"
}

@test "hug wtl: help clarifies positional vs search semantics" {
  run git-wtl --help

  assert_success
  assert_output --partial "exact match"
  assert_output --partial "substring"
}
```

**Step 2: Run tests to verify they fail**

Run: `make test-unit TEST_FILE=test_worktree_list.bats TEST_FILTER="stdout contains only listing lines"`
Expected: FAIL — "Worktrees:" still appears in output.

Run: `make test-unit TEST_FILE=test_worktree_list.bats TEST_FILTER="-q suppresses legend"`
Expected: FAIL — `-q` is not a recognized flag.

Run: `make test-unit TEST_FILE=test_worktree_list.bats TEST_FILTER="help mentions capturing"`
Expected: FAIL — help text doesn't have CAPTURING OUTPUT section yet.

**Step 3: Implement the changes**

Replace `git-config/bin/git-wtl` with the updated version. Key changes:

1. **Adopt `parse_common_flags()`** (pattern from `git-wtsh:298`):
```bash
# Parse common flags first (handles -q, -h, --help, etc.)
eval "$(parse_common_flags "$@")"
```

2. **Remove the header** (delete line 115):
```bash
# DELETE THIS LINE:
printf "${BLUE}Worktrees:%s${NC}\n" ""
```

3. **Legend call already goes to stderr** (from Task 0), but we need to verify it still works with parse_common_flags setting HUG_QUIET.

4. **Update help text** — add CAPTURING OUTPUT section and clarify semantics.

5. **Add `hug-cli-flags` to sourced libraries** — add it to the source line.

Full new `git-wtl`:

```bash
#!/usr/bin/env bash
CMD_BASE="$(readlink -f "$0" 2> /dev/null || greadlink -f "$0")" || CMD_BASE="$0"
CMD_BASE="$(dirname "$CMD_BASE")"
for f in hug-common hug-git-kit hug-git-worktree hug-cli-flags; do . "$CMD_BASE/../lib/$f"; done
set -euo pipefail

show_help() {
  cat << 'EOF'
hug wtl: List worktrees in short format, showing branch, path, and status.

USAGE:
  hug wtl [OPTIONS] [branch...]

ARGUMENTS:
  [branch...]         Filter by EXACT branch name (case-sensitive, OR logic)

OPTIONS:
  -h, --help          Show this help message and exit.
  -q, --quiet         Suppress legend line (listing still shown).
  --json              Output in JSON format instead of human-readable text.
  -s, --search TERM   Filter by SUBSTRING match on path or branch (case-insensitive, repeatable, OR logic)

DESCRIPTION:
  Displays each worktree sorted alphabetically. The current worktree is
  highlighted and marked with an asterisk (*).

  Indicators:
    *  current worktree
    +  dirty (uncommitted changes)
    #  locked
    @  detached HEAD
    .  (inactive)

  Filtering:
    Positional [branch]:  EXACT match, case-sensitive. Multiple = OR logic.
    -s / --search TERM:   SUBSTRING match, case-insensitive. Multiple = OR logic.
    Combined: Both filters must match (AND logic).

  NOTE: Positional arguments and -s have different semantics:
    hug wtl feature-1     # Exact branch name "feature-1" only
    hug wtl -s feature    # Any branch/path containing "feature"

CAPTURING OUTPUT:
  Listing lines go to stdout. Legend and errors go to stderr.
  Colors are automatically stripped when output is piped.

    worktrees=$(hug wtl)       # Capture listing to variable
    hug wtl | grep main        # Pipe to other commands
    hug wtl 2>/dev/null        # Suppress legend/errors

EXAMPLES:
  hug wtl                       # List all worktrees
  hug wtl feature-auth          # Exact branch "feature-auth"
  hug wtl feat-1 feat-2         # Exact: "feat-1" OR "feat-2"
  hug wtl -s feature            # Substring: anything containing "feature"
  hug wtl -s auth -s api        # Substring: "auth" OR "api"
  hug wtl feat-1 -s api         # Branch="feat-1" AND path/branch contains "api"
  hug wtl --json                # JSON output

SEE ALSO:
  hug wtll : Long-format listing with commit subjects
  hug wt   : Interactive worktree selection and switching
  hug wtdel : Remove worktrees safely
EOF
}

# Parse common flags first (handles -q, -h, --help)
eval "$(parse_common_flags "$@")"

# Parse command-specific arguments
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
  --)
    shift
    break
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

# Early exit if not in Git repo
check_git_repo

# JSON output mode
if $json_output; then
  current_worktree=$(get_current_worktree_path)
  output_worktree_json "$current_worktree" "$search_terms_str" "$branch_filters_str"
  exit 0
fi

# Get worktree data
declare -a worktree_paths=() branches=() commits=() status_dirty=() locked_status=()
if ! get_all_worktrees_including_main worktree_paths branches commits status_dirty locked_status; then
  printf "No worktrees found.\n" >&2
  exit 1
fi

# Get current worktree path for comparison
current_worktree=$(get_current_worktree_path)

# Print legend to stderr (suppressed by -q or non-TTY)
print_worktree_legend

# Build and print worktree list
if [[ -n "$branch_filters_str" || -n "$search_terms_str" ]]; then
  declare -a filtered_paths=() filtered_branches=() filtered_commits=()
  declare -a filtered_dirty=() filtered_locked=()
  if ! filter_worktrees filtered_paths filtered_branches filtered_commits filtered_dirty filtered_locked "$branch_filters_str" "$search_terms_str"; then
    exit 1
  fi

  for i in "${!filtered_paths[@]}"; do
    path="${filtered_paths[$i]}"
    branch="${filtered_branches[$i]}"
    commit="${filtered_commits[$i]}"
    dirty="${filtered_dirty[$i]}"
    locked="${filtered_locked[$i]}"

    path_display="${path/#$HOME/\~}"
    is_current="false"
    [[ "$path" == "$current_worktree" ]] && is_current="true"
    is_detached="false"
    [[ -z "$branch" || "$branch" == "detached" ]] && is_detached="true"
    status_indicators="$(format_worktree_indicators "$dirty" "$locked") "
    branch_display="$(format_worktree_branch_display "$is_current" "$is_detached" "$branch")"

    printf "%s%-20s %s %s\n" "$status_indicators" "$branch_display" "($commit)" "$path_display"
  done
else
  for i in "${!worktree_paths[@]}"; do
    path="${worktree_paths[$i]}"
    branch="${branches[$i]}"
    commit="${commits[$i]}"
    dirty="${status_dirty[$i]}"
    locked="${locked_status[$i]}"

    path_display="${path/#$HOME/\~}"
    is_current="false"
    [[ "$path" == "$current_worktree" ]] && is_current="true"
    is_detached="false"
    [[ -z "$branch" || "$branch" == "detached" ]] && is_detached="true"
    status_indicators="$(format_worktree_indicators "$dirty" "$locked") "
    branch_display="$(format_worktree_branch_display "$is_current" "$is_detached" "$branch")"

    printf "%s%-20s %s %s\n" "$status_indicators" "$branch_display" "($commit)" "$path_display"
  done
fi
```

**Step 4: Run tests to verify they pass**

Run: `make test-unit TEST_FILE=test_worktree_list.bats TEST_SHOW_ALL_RESULTS=1`
Expected: ALL PASS

**Step 5: Commit**

```bash
hug a git-config/bin/git-wtl tests/unit/test_worktree_list.bats
hug commit -m "feat: make hug wtl capture-friendly with stdout/stderr discipline

WHY: hug wtl mixed header, legend, and data on stdout, making
'worktrees=\$(hug wtl)' capture garbage. Users expect Unix convention:
data on stdout, chatter on stderr.

WHAT:
- Remove 'Worktrees:' header entirely
- Legend goes to stderr (from library change in previous commit)
- Adopt parse_common_flags() for -q/--quiet support
- -q suppresses legend, keeps listing colored on TTY
- Add CAPTURING OUTPUT section to help text
- Clarify positional (exact) vs -s (substring) semantics in help
- Colors auto-stripped when piped (hug-terminal handles this)

HOW:
- parse_common_flags() runs first, consuming -q/-h/--help
- Remaining args parsed in second pass for --json and -s
- Pattern matches git-wtsh (line 298)

IMPACT:
- 'worktrees=\$(hug wtl)' now captures clean listing
- 'hug wtl | grep main' works without ANSI noise
- -q flag available for suppressing legend in interactive use"
```

---

### Task 2: Fix existing tests broken by the header removal

**Files:**
- Modify: `tests/unit/test_worktree_list.bats`

**Step 1: Identify broken tests**

The following existing tests assert on "Worktrees:" which is now removed:

1. Line 192: `assert_output --partial "Worktrees:"` in "hug wtl: lists worktrees in short format"
2. Line 266: `assert_output --partial "Worktrees:"` in "hug wtl: handles repository with no worktrees"

**Step 2: Fix the broken assertions**

Test "hug wtl: lists worktrees in short format" (line 187):
```bash
@test "hug wtl: lists worktrees in short format" {
  cd "$TEST_REPO"
  run git-wtl

  assert_success
  # Header removed — listing lines go to stdout, legend to stderr
  assert_output --partial "*"
  assert_output --partial "main"
  assert_output --partial "feature-1"
  assert_output --partial "hotfix-1"
  assert_output --partial "("  # Should show commit in parentheses
}
```

Test "hug wtl: handles repository with no worktrees" (line 258):
```bash
@test "hug wtl: handles repository with no worktrees" {
  cleanup_test_worktrees "$TEST_REPO"

  cd "$TEST_REPO"
  run git-wtl

  assert_success
  # Only main worktree remains — should still be listed
  assert_output --partial "*"
  assert_output --partial "main"
}
```

**Step 3: Run full test suite**

Run: `make test-unit TEST_FILE=test_worktree_list.bats TEST_SHOW_ALL_RESULTS=1`
Expected: ALL PASS (both old and new tests)

**Step 4: Commit**

```bash
hug a tests/unit/test_worktree_list.bats
hug commit -m "test: update wtl tests for header removal and stderr legend

WHY: Previous commit removed the 'Worktrees:' header from stdout and
moved legend to stderr. Two existing tests asserted on the header.

WHAT: Remove 'Worktrees:' assertions from two tests, keeping the
meaningful assertions (branch names, indicators) intact."
```

---

### Task 3: Run full test suite and verify no regressions

**Step 1: Run the full BATS test suite**

Run: `make test-bash TEST_SHOW_ALL_RESULTS=1`
Expected: ALL PASS

**Step 2: Run the Python test suite**

Run: `make test-lib-py`
Expected: ALL PASS

**Step 3: If any tests fail, investigate and fix**

Common issues to check:
- Tests in other files asserting on "Worktrees:" from `git-wtl`
- Tests checking legend in stdout instead of stderr
- Tests that pipe wtll output and expect header

**Step 4: Commit any fixes**

```bash
hug a <fixed-files>
hug commit -m "test: fix regressions from wtl stdout/stderr split"
```

---

### Task 4: Verify capture workflow end-to-end

**Step 1: Source hug and test capture manually**

```bash
source bin/activate

# Test basic capture
worktrees=$(hug wtl)
echo "Captured: $worktrees"
# Should show only listing lines, no header or legend

# Test piping
hug wtl | cat
# Should show plain text (no ANSI codes)

# Test -q flag
hug wtl -q
# Should show listing with colors but no legend

# Test legend goes to stderr
hug wtl 2>/dev/null
# Should show listing without legend

# Test error goes to stderr
hug wtl nonexistent-branch
# Should show error message
```

**Step 2: If any issues found, fix and commit**

No commit needed if everything works — this is a verification step.
