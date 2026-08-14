# Design: Extend `hug mff` with Two-Arg Form for Moving Branch Pointers

**Date:** 2026-04-19
**Status:** Approved

## Problem

Moving branch A's pointer to branch B (when B is a descendant of A) requires either switching to A first or dropping to raw git:

```bash
hug b A && hug mff B       # switch + ff-merge (two steps)
git branch -f A B           # raw git (bypasses hug)
```

There's no single hug command for "fast-forward branch A to B without switching to it."

## Solution

Extend `hug mff` to accept an optional second argument:

```bash
hug mff <target>              # ff current branch to <target> (existing behavior)
hug mff <branch> <target>     # ff <branch> to point at <target> (new)
hug mff <branch> <target> -f  # force-move without ff check (escape hatch)
```

## Design Decisions

### Strict ff by default, --force escape hatch

Default behavior refuses if `<target>` is not a descendant of `<branch>`. This matches `mff`'s identity as "fast-forward only." The `-f/--force` flag allows arbitrary moves for power users, following hug's progressive destructiveness pattern.

### Promoted from gitconfig alias to full script

`mff` currently lives as `mff = merge --ff-only` in `.gitconfig`. Promoting to a proper `git-config/bin/git-mff` script enables rich output, validation, dry-run support, and confirmation prompts — consistent with how `bc` was promoted.

### No new command — reuse `mff`

The two-arg form lives under the existing `mff` name. The command already says "fast-forward," which is exactly what moving a branch pointer is. Two args = "ff branch A to B." One arg = "ff current branch to B."

### Discoverability via cross-references (not command overloading)

- `hug mff --help` → `SEE ALSO: hug bmv (rename branch), hug b (switch branch)`
- `hug b --help` → `SEE ALSO: hug mff A B (fast-forward branch A to B without switching)`
- `hug bmv` docs → `SEE ALSO: hug mff A B (move branch pointer to another commit)`

Mental model stays clean:
- `bmv` = rename a branch (change its name)
- `mff A B` = move a branch pointer (change what it points to)

## Command Signature

```
hug mff <target>              # ff current branch to <target>
hug mff <branch> <target>     # ff <branch> to <target> (no switch needed)
hug mff ... --force           # allow non-ff move
hug mff ... --dry-run         # preview without moving
hug mff -h/--help             # help with cross-references
```

## Two-Arg Semantics

- `<branch>` must exist locally as a branch
- `<target>` can be a branch name, tag, or any commitish
- Default: refuses if `<target>` is not a descendant of `<branch>` (strict ff)
- With `-f/--force`: uses `git branch -f <branch> <target>` (arbitrary move)
- Working tree is never touched for non-checked-out branches
- If `<branch>` is the current branch, delegates to `git merge --ff-only <target>` (git requirement)

## Output & UX

### Successful ff

```
Fast-forwarded 'feature' to 'main' (3 commits ahead)
  abc1234 → def5678
```

### Failed ff (diverged)

```
Cannot fast-forward 'feature' to 'main' — branches have diverged.
Use hug mff feature main --force to move anyway.
```

### Force move

```
Moved 'feature' to 'main' (--force, not a fast-forward)
  abc1234 → def5678
```

### Validation errors

- Branch doesn't exist locally: `Branch 'foo' not found.`
- Target doesn't resolve: `Cannot resolve 'bar' as a commit.`
- Same branch and target: `'feature' already points at abc1234.`

## Script Structure

**File:** `git-config/bin/git-mff`

1. Parse flags (`-f/--force`, `--dry-run`, `-h/--help`)
2. Validate args: 1 arg (existing) or 2 args (new)
3. Two-arg path:
   - Resolve both `<branch>` and `<target>` to SHAs
   - If same SHA → "already points at" message, exit 0
   - If not forced → check ancestry via `git merge-base --is-ancestor`
   - Execute: `git branch -f <branch> <target>` (non-checked-out) or `git merge --ff-only <target>` (current branch)
   - Print result with commit range
4. One-arg path: `exec git merge --ff-only <target>` (unchanged behavior)

**gitconfig change:** Remove `mff = merge --ff-only` alias.

**Key detail:** Detect current branch via `git symbolic-ref HEAD` comparison. If `<branch>` is checked out, must use `git merge --ff-only` instead of `git branch -f`.

## Testing

Unit tests in `tests/unit/test_mff.bats`:

1. One-arg ff on current branch (existing behavior preserved)
2. Two-arg ff: non-checked-out branch, clean fast-forward
3. Two-arg ff: branch already at target → "already points at" message
4. Two-arg ff: diverged branches → fails with clear error
5. Two-arg ff: diverged + `--force` → succeeds
6. Two-arg ff: target is a tag or raw SHA
7. Two-arg ff: branch is current branch → delegates to merge --ff-only
8. Error: non-existent branch
9. Error: non-existent target
10. `--dry-run` shows preview without moving
11. `-h/--help` shows help with cross-references
