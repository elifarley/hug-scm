# Conflict Display Investigation

## Issue Description

Hug displays conflicted files as `U:Mod` instead of `Cnflt` during an active merge, even though the file is in a genuine merge conflict state.

## Current Behavior

```
$ hug sl
U:Mod  file.txt
🟡 HEAD: 4232381 🌿main │ 📦 Staged: 1 files, +0/-0 lines │ 📝 Unstaged: 2 files, +4/-0 lines │ K:0 I:2
```

Native `git status` correctly shows:
```
Unmerged paths:
  (use "git add <file>..." to mark resolution)
	both modified:   file.txt
```

## Expected Behavior

Conflicted files should display as `Cnflt` instead of `U:Mod` based on the status mapping in `hug-select-files`:

```bash
_format_unstaged_status() {
  case "$status" in
    U) status_text="${RED}${YELLOW}Cnflt${NC}"; status_code="U:Cnflt" ;;
    M) status_text="Mod"; status_code="U:Mod" ;;
    # ...
  esac
}
```

## Root Cause Analysis

### Git's Behavior During Active Merge

When a merge conflict occurs, `git diff --name-status` returns **duplicate entries** for the same file:

```bash
$ git diff --name-status
U	file.txt
M	file.txt
```

- `U` = Unmerged (conflicted)
- `M` = Modified (working tree has changes relative to the merge base)

Both statuses are technically correct, but `U` should take precedence for display purposes.

### How Hug Processes This

From `~/src/hug-scm/git-config/lib/hug-git-files`:

```bash
list_unstaged_files() {
    local -a git_cmd_base=("git" "diff")
    if $with_status; then
        git_cmd_base+=("--name-status")
    # ...
    fi
    "${git_cmd_base[@]}" "${pathspecs[@]}" "$@"
}
```

The function simply passes through the output from `git diff --name-status`, which includes both `U` and `M` entries for conflicted files.

### The Problem

When hug processes the list of files with status codes:
1. Git returns both `U	file.txt` and `M	file.txt`
2. Hug's status formatting correctly maps `U` → `Cnflt` and `M` → `Mod`
3. However, the **wrong status is being selected for display** (likely the `M` instead of `U`)

## Status Priority System

From `~/src/hug-scm/git-config/lib/hug-git-priorities`:

```bash
declare -gA STATUS_PRIORITY=(
  ["U:Cnflt"]=90  ["S:Cnflt"]=90  # Highest priority - shown LAST
  ["S:Add"]=80    ["S:Mod"]=80    ["S:Ren"]=80
  ["S:Copy"]=80   ["S:Del"]=80
  ["U:Mod"]=70    ["U:Del"]=70
  ["untrcK"]=60
  ["Ignore"]=50
)
```

The priority system shows that `U:Cnflt` (90) has higher priority than `U:Mod` (70), so the conflict status should win if both exist for the same file.

## Investigation Steps Taken

### Attempt 1: Manual Index Manipulation (Failed)

Created a file with conflict markers and manually manipulated the git index to create a 3-stage conflict state:

```bash
printf "100644 $OUR_BLOB 1\tconflicted.txt\n100644 $OUR_BLOB 2\tconflicted.txt\n100644 $THEIR_BLOB 3\tconflicted.txt\n" | git update-index --index-info
```

Result: `git status` showed "both modified" but `hug sl` showed `U:Mod`.

### Attempt 2: Genuine Merge Conflict (Reproduced Issue)

Created a real merge conflict:

```bash
# On main: "main branch content"
# On feature-branch: "feature branch content"
git merge feature-branch  # Creates conflict
```

Result: Still shows `U:Mod` instead of `Cnflt`.

## Key Files Involved

1. **`~/src/hug-scm/git-config/lib/hug-git-files`**
   - `list_staged_files()` - runs `git diff --cached --name-status`
   - `list_unstaged_files()` - runs `git diff --name-status`

2. **`~/src/hug-scm/git-config/lib/hug-select-files`**
   - `_format_staged_status()` - maps status codes to display labels (staged)
   - `_format_unstaged_status()` - maps status codes to display labels (unstaged)
   - Status mapping: `U` → `Cnflt`, `M` → `Mod`

3. **`~/src/hug-scm/git-config/lib/hug-git-priorities`**
   - Defines `STATUS_PRIORITY` array for sorting files

## Verification Commands

```bash
# Create a merge conflict:
git checkout -b feature-branch
echo "feature" > file.txt && git add . && git commit -m "feature"
git checkout main
echo "main" > file.txt && git add . && git commit -m "main"
git merge feature-branch  # Creates conflict

# Check git's view:
git diff --name-status  # Returns both "U" and "M" for same file

# Check hug's view:
hug sl  # Currently shows U:Mod, should show Cnflt
```

## Potential Solutions

1. **Filter duplicate entries in `list_unstaged_files()`**
   - When a file has both `U` and `M` status, prefer `U`
   - This would require post-processing the `git diff --name-status` output

2. **Add special handling for merge conflicts**
   - Detect if we're in a merge state (`git rev-parse -q --verify MERGE_HEAD`)
   - Use a different git command for conflict detection

3. **Use `git status --porcelain` instead**
   - This format has better conflict indicators (`DD`, `AU`, `UU`, etc.)
   - Would require changing the status parsing logic

## Related Documentation

- Status display logic: `~/src/hug-scm/git-config/lib/hug-select-files`
- Status priority: `~/src/hug-scm/git-config/lib/hug-git-priorities`
- File listing: `~/src/hug-scm/git-config/lib/hug-git-files`

## Next Steps

1. Decide which solution approach to take
2. Implement the fix in the appropriate file
3. Add test coverage for merge conflict scenarios
4. Verify the fix with both staged and unstaged conflicts
