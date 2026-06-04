# Worktree Commands Exercise Report: wtc / wtl / wtdel

> **Date:** 2026-06-03
> **Repo used:** `/var/tmp/hug-wt-exercise` (ephemeral, deleted after exercise)
> **Branches created:** `main`, `feature-alpha`, `feature-beta`, `release-v1` (plus worktree-specific branches)
> **Purpose:** Exhaustively exercise all flag combinations of `hug wtc`, `hug wtl`, and `hug wtdel` to surface DX inconsistencies, safety-model gaps, and behavioral edge cases for future investigation.

---

## Table of Contents

1. [Test Environment](#test-environment)
2. [hug wtc — Worktree Create](#hug-wtc--worktree-create)
3. [hug wtl — Worktree List](#hug-wtl--worktree-list)
4. [hug wtdel — Worktree Delete](#hug-wtdel--worktree-delete)
5. [Cross-Command DX Observations](#cross-command-dx-observations)
6. [Inconsistency Matrix](#inconsistency-matrix)
7. [Recommended Investigations](#recommended-investigations)

---

## Test Environment

### Repo Setup

```bash
REPO=/var/tmp/hug-wt-exercise
mkdir -p "$REPO" && cd "$REPO"
git init --initial-branch=main
git config user.email "test@example.com"
git config user.name "Test User"

# Three commits on main
echo "# README" > README.md && echo "v1" > file.txt
hug a . && hug c -m "Initial commit"
echo "v2" > file.txt
hug a . && hug c -m "Second commit"

# Feature branches off second commit
hug bc feature-alpha && echo "alpha" > alpha.txt && hug a . && hug c -m "Alpha feature"
hug bc feature-beta  && echo "beta"  > beta.txt  && hug a . && hug c -m "Beta feature"
hug bc release-v1    && echo "release" > release.txt && hug a . && hug c -m "Release v1"

# Back to main for one more commit
hug b main && echo "v3" > file.txt && hug a . && hug c -m "Third commit"

# Tag for --base tests
git tag v1.0
```

### Commit Graph

```
* a078eaa (HEAD -> main, tag: v1.0) Third commit
| * 83495f6 (release-v1) Release v1
| * fadb69e (feature-beta) Beta feature
| * fae95e4 (feature-alpha) Alpha feature
|/
* 79233a9 Second commit
* 224db76 Initial commit
```

---

## hug wtc — Worktree Create

### Forms Exercised

| # | Command | Outcome | Notes |
|---|---------|---------|-------|
| 1 | `hug wtc feature-alpha -y` | ✅ Success | Worktree for **existing** branch. Auto-generated sibling path: `../hug-wt-exercise.WT.feature-alpha` |
| 2 | `hug wtc experiment-1 --new -y` | ✅ Success | **New** branch from HEAD. Reports `Branch: experiment-1 (new, from HEAD)`. Auto-generated path. |
| 3 | `hug wtc hotfix-from-beta --base feature-beta -y` | ✅ Success | New branch from **specific branch**. `--base` implies `--new`. Reports start-point hash. |
| 4 | `hug wtc dry-run-test --dry-run` | ✅ Success (no-op) | Preview mode. Shows branch + path but prints `No changes made (dry run)`. |
| 5 | `hug wtc from-tag --base v1.0 -y` | ✅ Success | New branch from **tag** ref. `--base` accepts tags. |
| 6 | `hug wtc from-past --base <hash> -y` | ✅ Success | New branch from **explicit commit hash** (resolved `HEAD~1`). Short hash shown in summary. |
| 6a | `hug wtc from-past --base HEAD~1 -y` | ❌ Error | `Invalid start-point 'HEAD~3': not a valid commit, branch, or tag` — relative refs like `HEAD~1` are **not** resolved by `wtc`. See [DX-1]. |
| 7 | `hug wtc main -f` | ✅ Success | **Force** worktree for branch already checked out in main worktree. Without `-f` this fails. |
| 8 | `hug wtc feature-alpha -y` | ❌ Error | Branch already checked out in **another worktree** (not main). |
| 8b | `hug wtc feature-alpha -f` | ❌ Error | Even `-f` cannot override — blocked at git level. |
| 9 | `hug wtc custom-path-branch --new -y /var/tmp/my-custom-wt` | ✅ Success | **Custom path** as positional arg (not a flag). Path is the second positional. |
| 10 | `hug wtc nonexistent-branch -y` | ✅ Success | Without `--new`, `-y` **auto-answers "yes"** to the create-branch prompt. Branch auto-created from HEAD. |

### wtc Output Format

**Success:**
```
Worktree Creation Summary:
  Branch: <name> [(new, from <base>)]
  Path:   <path>

ℹ️ Info: Created branch '<name>' from <hash>
✅ Success: Worktree created for '<name>'
💡 Tip: To start working:  cd <path>
```

**Dry run:**
```
Worktree Creation Preview (DRY RUN):
  Branch: <name> (new, from HEAD)
  Path:   <path>

ℹ️ Info: No changes made (dry run).
```

**Error:**
```
❌ Error: Branch '<name>' is already checked out in another worktree. Use 'hug wtl' to see worktree assignments.
```

### wtc DX Observations

- **[DX-1] Relative refs rejected by `--base`:** `HEAD~1`, `HEAD~3`, `HEAD^^` etc. are not resolved by `wtc`. The user must pre-resolve with `git rev-parse`. This is a usability gap — these are valid git refs that `git worktree add -b <name> HEAD~1` accepts natively.
- **[DX-2] `-y` auto-creates branches without `--new`:** The `-y` flag's "skip confirmation prompts" semantic silently escalates to "auto-create branch" when the branch doesn't exist. This is surprising — `-y` should mean "skip the yes/no prompt", not "assume yes for branch creation". A user running `hug wtc typo-branch -y` gets a new branch they didn't intend.
- **[DX-3] Error message for branch-in-use is unclear:** When a branch is checked out in another worktree (not main), the error says "already checked out in another worktree" — which is correct but doesn't distinguish between "checked out in main WT" (solvable with `-f`) vs "checked out in a non-main WT" (unsolvable without deleting that WT first). The error message should guide the user differently for each case.
- **[DX-4] Custom path is a positional, not a flag:** `hug wtc <branch> --new -y /path` — the path is the second positional argument. This is ambiguous when the user has a branch name that looks like a path. Consider `--path` flag for clarity.

---

## hug wtl — Worktree List

### Forms Exercised

| # | Command | Outcome | Notes |
|---|---------|---------|-------|
| 1 | `hug wtl` | ✅ Full listing | All worktrees, alphabetically sorted. Main WT marked with `*`. Legend on stderr. |
| 2 | `hug wtl feature` | ✅ Substring filter | Case-insensitive substring on path OR branch. Shows only `feature-alpha`. |
| 3 | `hug wtl alpha hotfix` | ✅ Multi-substring OR | Shows `feature-alpha` and `hotfix-from-beta`. OR logic between positional terms. |
| 4 | `hug wtl -b main` | ✅ Exact branch | Shows **both** main worktrees (original + `.WT.main`). Case-sensitive exact match. |
| 5 | `hug wtl -b main -b experiment-1` | ✅ Multi-branch OR | Repeatable `-b` flag, OR logic. |
| 6 | `hug wtl main -b main` | ✅ AND filter | Substring `main` AND exact branch `main` — both filters must match. |
| 7 | `hug wtl --json` | ✅ Valid JSON | Clean JSON to stdout, legend suppressed. Validates with `python3 -m json.tool`. |
| 8 | `hug wtl -p` | ✅ Path-only | One absolute path per line to stdout. Count line (`N worktrees found`) to stderr. |
| 9 | `hug wtl -p -b feature-alpha` | ✅ Single path | Scriptable: capture exact path for a branch. |
| 10 | `hug wtl -e` | ✅ Existing-only | Excludes worktrees whose directories were removed externally (stale git metadata). |
| 11 | `hug wtl -p -e` | ✅ Path + existing | Scriptable path list, only on-disk dirs. |
| 12 | `hug wtl` (with dirty WT) | ✅ Dirty indicator | Untracked file in `experiment-1` WT → `+. experiment-1`. The `+` replaces the first `.` in the indicator column. |
| 13 | `hug wtl -q` | ✅ Quiet | Suppresses the legend line. Listing still shown. |

### wtl Output Format

**Human-readable (default):**
```
  Legend: + dirty  # locked  * current
.. *main                (a078eaa) /var/tmp/hug-wt-exercise
+. experiment-1         (a078eaa) /var/tmp/hug-wt-exercise.WT.experiment-1
```

Indicator column format: `[+][#][*][@][.]` where each character replaces the `.` at its position.

**Path-only (`-p`):**
```
9 worktrees found          ← stderr
/var/tmp/hug-wt-exercise   ← stdout
/var/tmp/hug-wt-exercise.WT.experiment-1
```

**JSON (`--json`):**
```json
{
  "worktrees": [
    {
      "path": "/var/tmp/hug-wt-exercise",
      "branch": "main",
      "commit": "a078eaa",
      "dirty": false,
      "locked": false,
      "current": true
    }
  ]
}
```

### wtl DX Observations

- **[DX-5] Path-only mode shows count on stderr:** `hug wtl -p` outputs `N worktrees found` to stderr. This is correct per stdout/stderr discipline, but the message format ("N worktrees found") reads like a listing header, not a diagnostic. Consider omitting entirely in `-p` mode (the count is implicit from the number of lines).
- **[DX-6] `-b` matches branch name across multiple worktrees:** `hug wtl -b main` shows both the main worktree and the `.WT.main` worktree. This is correct (same branch, two checkouts) but may surprise users who expect `-b` to return exactly one result. The help text could clarify this.
- **[DX-7] `-e` vs stale metadata interaction:** After externally `rm -rf`-ing a worktree directory, `hug wtl` (without `-e`) still shows it — the git metadata is stale. `hug wtprune` reports "No orphaned worktrees found" in this case. Only after a subsequent `wtdel` or `wtl` call does the stale entry disappear. This suggests lazy/on-access pruning, but the behavior is inconsistent — `wtprune` should catch these, or `wtl` should auto-prune.
- **[DX-8] Dirty detection granularity:** The `+` indicator appears for any dirty state (staged, unstaged, or untracked). The user cannot distinguish "I have staged changes I care about" from "there's an untracked `.DS_Store`". Consider finer-grained indicators or at least mentioning the dirty type in `--json`.

---

## hug wtdel — Worktree Delete

### Forms Exercised

| # | Command | Outcome | Notes |
|---|---------|---------|-------|
| 1 | `hug wtdel feature-alpha --dry-run` | ✅ Preview | Shows branch, path, status. No changes made. |
| 2 | `hug wtdel feature-alpha -y` | ❌ Error | `-y` is insufficient; requires `-f`. Error: "Dangerous operation requires --force (not -y)". |
| 3 | `hug wtdel feature-alpha -f` | ✅ Removed | Clean worktree removed. Branch preserved (tip printed). |
| 4 | `hug wtdel -p /path -f` | ✅ Removed | Removal by filesystem path instead of branch name. |
| 5 | `hug wtdel hotfix-from-beta -B -f` | ✅ Removed + branch deleted | `-B` / `--with-branch` deletes the branch after removing the worktree. Two success lines. |
| 6 | `hug wtdel experiment-1 nonexistent-branch -f` | ✅ Batch (2/2) | Batch by multiple branch names. Reports status per-item. Dirty detection works per-item. |
| 6a | `hug wtdel experiment-1 from-past -f` | ❌ Error (partial) | `from-past` was stale (dir removed externally). Error: "No worktree found for branch 'from-past'". **Neither worktree was removed** — the batch failed entirely. See [DX-9]. |
| 7 | `hug wtdel -p /path/a -p /path/b -f` | ✅ Batch by path | Multiple `-p` flags for batch path-based removal. |
| 8 | `hug wtdel main -f` | ❌ Error | "Cannot remove the main worktree". Correct safety guard. |

### wtdel Output Format

**Single removal:**
```
Worktree Removal Summary:
  Branch: <name>
  Path:   <path>
  Status: Clean | Dirty -- <reason>

✅ Success: Worktree removed for branch '<name>'
ℹ️ Info: Deleted directory: <path>
💡 Tip: Branch '<name>' still exists. To delete it: hug bdel <name>
```

**Batch removal:**
```
Worktree Removal Summary [1/2]:
  Branch: <name>
  Path:   <path>
  Status: Clean

✅ Success: ...

Worktree Removal Summary [2/2]:
  ...

✅ Success: ...

Batch Removal Summary:
  Removed: 2
```

**With `-B`:**
```
✅ Success: Worktree removed for branch '<name>'
ℹ️ Info: Deleted directory: <path>
✅ Success: Branch '<name>' deleted
```

**Error:**
```
❌ Error: Dangerous operation requires --force (not -y). Reason: This operation is irreversible and may cause data loss.
```
```
❌ Error: Cannot remove the main worktree (branch 'main'). Use a different branch or specify -p for path.
```

### wtdel DX Observations

- **[DX-9] Batch failure is all-or-nothing:** When removing `experiment-1 from-past` and `from-past` has no worktree, the **entire batch fails** with exit code 1 and **nothing is removed**. This is a correctness concern: if item 1 is valid but item 2 is invalid, the user expects item 1 to succeed. Either: (a) process valid items and skip invalid ones with a warning, or (b) validate all items before removing any (dry-run-first approach). Current behavior is worst-of-both-worlds — it validates lazily but rolls back nothing.
- **[DX-10] `-y` vs `-f` semantic inconsistency with `wtc`:** In `wtc`, `-y` skips confirmation prompts and performs the operation. In `wtdel`, `-y` is explicitly rejected with "requires --force (not -y)". The `-y` flag's meaning is inconsistent across the worktree command family. See [Inconsistency Matrix](#inconsistency-matrix).
- **[DX-11] Main worktree error message is misleading:** `Cannot remove the main worktree (branch 'main'). Use a different branch or specify -p for path.` — but `-p /path/to/main/worktree` would also fail for the main worktree. The "specify -p for path" suggestion implies there's a workaround, but there isn't.
- **[DX-12] Dirty detection in removal:** The removal summary correctly reports dirty status (`Dirty -- untracked files (will be permanently lost)`). With `-f`, the removal proceeds anyway. This is good — the user is warned but not blocked. However, the warning only appears in the output text, not in the exit code or structured output.
- **[DX-13] `-B` deletes branch even if worktree removal partially fails:** Not directly observed (batch + `-B` wasn't tested together), but worth investigating: if batch removal with `-B` fails on item 2, does item 1's branch still get deleted?

---

## Cross-Command DX Observations

- **[DX-14] Flag naming inconsistency:** `wtc` uses `--new` for auto-creating branches. `wtdel` uses `-B` / `--with-branch` for branch deletion. The branch lifecycle uses different flag conventions for creation vs. deletion. Consider a consistent prefix (e.g., `--create-branch` / `--delete-branch`).
- **[DX-15] No `--json` for `wtdel`:** `wtl` has `--json` but `wtc` and `wtdel` don't. For CI/CD scripting, machine-readable output for create/delete operations would be valuable (especially to capture the generated path).
- **[DX-16] No `--json` for `wtc`:** The worktree path is only available in the human-readable summary. Scripts must parse the `Tip: To start working:` line or use `hug wtl -p -b <branch>` as a separate call.
- **[DX-17] `-q` only exists on `wtl`:** Neither `wtc` nor `wtdel` have a quiet mode. For scripting, suppressing all non-data output would be useful.
- **[DX-18] Exit codes are binary (0/1):** No distinction between "validation error" (bad args), "safety error" (branch in use), and "runtime error" (disk full). Scriptable commands would benefit from distinct exit codes.
- **[DX-19] `wtc --base` doesn't validate start-point existence eagerly:** With `--dry-run`, the start-point is validated. Without `--dry-run`, a non-existent start-point still fails — but the error message could be more specific about what was wrong (not a commit, not a branch, not a tag).
- **[DX-20] No `wtc --detach` equivalent:** Git supports `git worktree add --detach <path> <ref>` to create a detached-HEAD worktree. Hug's `wtc` always requires a branch name. This limits use cases like inspecting a specific commit without creating a branch.

---

## Inconsistency Matrix

| Aspect | `wtc` | `wtl` | `wtdel` | Consistent? |
|--------|-------|-------|---------|-------------|
| **Skip prompts** | `-y` / `--yes` | N/A | `-y` rejected; requires `-f` | ❌ **No** |
| **Force destructive** | `-f` / `--force` | N/A | `-f` / `--force` | ✅ Yes |
| **Dry-run** | `--dry-run` | N/A | `--dry-run` | ✅ Yes |
| **JSON output** | ❌ None | `--json` | ❌ None | ❌ **No** |
| **Quiet mode** | ❌ None | `-q` / `--quiet` | ❌ None | ❌ **No** |
| **Help flag** | `-h` / `--help` | `-h` / `--help` | `-h` / `--help` | ✅ Yes |
| **Target by branch** | positional `<branch>` | `-b <name>` | positional `<branch>` | ⚠️ Partial |
| **Target by path** | positional `[path]` | N/A | `-p <path>` | ⚠️ Partial |
| **Batch operation** | ❌ Single only | ✅ Multiple search terms | ✅ Multiple branches/paths | ❌ **No** |
| **Error on stale WT** | Creates new | Shows with indicator | "No worktree found" | ⚠️ Partial |
| **Tip messages** | ✅ Always | N/A | ✅ Always | ✅ Yes |
| **Color stripping** | N/A (no pipe use) | `[[ -t 1 ]]` check | N/A | ✅ Yes |

---

## Recommended Investigations

### High Priority (Safety / Correctness)

1. **Batch `wtdel` all-or-nothing behavior [DX-9]** — Investigate whether batch deletion should be best-effort (remove what's valid, warn about invalid) or pre-validated (validate all before removing any). Current behavior fails silently on valid items when an invalid item is encountered.

2. **`-y` semantic inconsistency [DX-10]** — Decide on a unified model: either `-y` means "skip prompts" everywhere (including `wtdel`), or rename it to something clearer in `wtc` (e.g., `--no-prompt`). Document the decision.

3. **Stale worktree metadata lifecycle [DX-7]** — Map out when stale entries are cleaned up: `wtprune` vs `wtl -e` vs `wtdel` vs `wtc`. Ensure consistent behavior.

### Medium Priority (Usability)

4. **Relative refs in `--base` [DX-1]** — Evaluate whether `wtc --base HEAD~3` should resolve relative refs. If yes, use `git rev-parse` internally before validation.

5. **`-y` auto-creating branches [DX-2]** — Decide whether this is intentional or a bug. If intentional, document it. If not, separate "skip prompt" from "auto-create branch" semantics.

6. **`--json` for `wtc` and `wtdel` [DX-15, DX-16]** — For scriptability, machine-readable output for create/delete is as important as for list.

7. **Finer-grained dirty indicator [DX-8]** — `--json` could expose `dirty_type: "staged" | "unstaged" | "untracked"` for better scripting.

### Low Priority (Polish)

8. **Quiet mode for `wtc` / `wtdel` [DX-17]** — Useful for scripting but not critical.

9. **Error message improvements [DX-3, DX-11]** — Distinguish between "checked out in main WT" (use `-f`) and "checked out in another WT" (delete that WT first). Fix misleading `-p` suggestion for main worktree.

10. **`wtc --detach` support [DX-20]** — For commit inspection without branch creation.

---

## Appendix: Raw Exercise Log

<details>
<summary>wtc exercise transcript</summary>

```
=== 1. wtc for existing branch ===
$ hug wtc feature-alpha -y
✅ Success: Worktree created for 'feature-alpha'
Path: /var/tmp/hug-wt-exercise.WT.feature-alpha

=== 2. wtc --new ===
$ hug wtc experiment-1 --new -y
ℹ️ Info: Created branch 'experiment-1' from a078eaa
✅ Success: Worktree created for 'experiment-1'

=== 3. wtc --base (branch) ===
$ hug wtc hotfix-from-beta --base feature-beta -y
ℹ️ Info: Created branch 'hotfix-from-beta' from feature-beta (fadb69e)
✅ Success: Worktree created for 'hotfix-from-beta'

=== 4. wtc --dry-run ===
$ hug wtc dry-run-test --dry-run
Worktree Creation Preview (DRY RUN):
  Branch: dry-run-test (new, from HEAD)
  Path: /var/tmp/hug-wt-exercise.WT.dry-run-test
ℹ️ Info: No changes made (dry run).

=== 5. wtc --base (tag) ===
$ hug wtc from-tag --base v1.0 -y
ℹ️ Info: Created branch 'from-tag' from v1.0 (a078eaa)
✅ Success: Worktree created for 'from-tag'

=== 6a. wtc --base HEAD~3 ===
$ hug wtc from-past --base HEAD~3 -y
❌ Error: Invalid start-point 'HEAD~3': not a valid commit, branch, or tag

=== 6b. wtc --base (resolved hash) ===
$ hug wtc from-past --base 79233a9 -y
ℹ️ Info: Created branch 'from-past' from 79233a9
✅ Success: Worktree created for 'from-past'

=== 7. wtc main -f (already in main WT) ===
$ hug wtc main -f
✅ Success: Worktree created for 'main'
Path: /var/tmp/hug-wt-exercise.WT.main

=== 8. wtc feature-alpha (already in another WT) ===
$ hug wtc feature-alpha -y
❌ Error: Branch 'feature-alpha' is already checked out in another worktree.

=== 8b. wtc feature-alpha -f (still blocked) ===
$ hug wtc feature-alpha -f
❌ Error: Branch 'feature-alpha' is already checked out in another worktree.

=== 9. wtc with custom path ===
$ hug wtc custom-path-branch --new -y /var/tmp/my-custom-wt
✅ Success: Worktree created for 'custom-path-branch'
Path: /var/tmp/my-custom-wt

=== 10. wtc nonexistent branch with -y ===
$ hug wtc nonexistent-branch -y
ℹ️ Info: Branch 'nonexistent-branch' does not exist locally.
ℹ️ Info: Created branch 'nonexistent-branch' from a078eaa
✅ Success: Worktree created for 'nonexistent-branch'
```

</details>

<details>
<summary>wtl exercise transcript</summary>

```
=== 1. Plain listing ===
$ hug wtl
  Legend: + dirty  # locked  * current
.. *main                (a078eaa) /var/tmp/hug-wt-exercise
.. experiment-1         (a078eaa) /var/tmp/hug-wt-exercise.WT.experiment-1
.. feature-alpha        (fae95e4) /var/tmp/hug-wt-exercise.WT.feature-alpha
.. from-past            (79233a9) /var/tmp/hug-wt-exercise.WT.from-past
.. from-tag             (a078eaa) /var/tmp/hug-wt-exercise.WT.from-tag
.. hotfix-from-beta     (fadb69e) /var/tmp/hug-wt-exercise.WT.hotfix-from-beta
.. main                 (a078eaa) /var/tmp/hug-wt-exercise.WT.main
.. nonexistent-branch   (a078eaa) /var/tmp/hug-wt-exercise.WT.nonexistent-branch
.. custom-path-branch   (a078eaa) /var/tmp/my-custom-wt

=== 2. Substring search ===
$ hug wtl feature
.. feature-alpha        (fae95e4) /var/tmp/hug-wt-exercise.WT.feature-alpha

=== 3. Multi-substring OR ===
$ hug wtl alpha hotfix
.. feature-alpha        (fae95e4) /var/tmp/hug-wt-exercise.WT.feature-alpha
.. hotfix-from-beta     (fadb69e) /var/tmp/hug-wt-exercise.WT.hotfix-from-beta

=== 4. Exact branch ===
$ hug wtl -b main
.. *main                (a078eaa) /var/tmp/hug-wt-exercise
.. main                 (a078eaa) /var/tmp/hug-wt-exercise.WT.main

=== 5. Multi-branch OR ===
$ hug wtl -b main -b experiment-1
.. *main                (a078eaa) /var/tmp/hug-wt-exercise
.. experiment-1         (a078eaa) /var/tmp/hug-wt-exercise.WT.experiment-1
.. main                 (a078eaa) /var/tmp/hug-wt-exercise.WT.main

=== 7. JSON ===
$ hug wtl --json | python3 -m json.tool
{
    "worktrees": [
        {"path": "/var/tmp/hug-wt-exercise", "branch": "main", "commit": "a078eaa", ...},
        ...
    ]
}

=== 8. Path-only ===
$ hug wtl -p
9 worktrees found
/var/tmp/hug-wt-exercise
/var/tmp/hug-wt-exercise.WT.experiment-1
...

=== 10-11. Existing-only ===
$ rm -rf /var/tmp/hug-wt-exercise.WT.from-past
$ hug wtl -e          # from-past excluded
$ hug wtl -p -e       # path list excludes from-past

=== 12. Dirty indicator ===
$ echo "dirty" > /var/tmp/hug-wt-exercise.WT.experiment-1/dirty.txt
$ hug wtl
+. experiment-1         (a078eaa) /var/tmp/hug-wt-exercise.WT.experiment-1

=== 13. Quiet ===
$ hug wtl -q            # No legend line
```

</details>

<details>
<summary>wtdel exercise transcript</summary>

```
=== 1. Dry-run ===
$ hug wtdel feature-alpha --dry-run
Worktree Removal Preview (DRY RUN):
  Branch: feature-alpha
  Path: /var/tmp/hug-wt-exercise.WT.feature-alpha
  Status: Clean

=== 2. wtdel with -y (rejected) ===
$ hug wtdel feature-alpha -y
❌ Error: Dangerous operation requires --force (not -y).

=== 3. wtdel with -f ===
$ hug wtdel feature-alpha -f
✅ Success: Worktree removed for branch 'feature-alpha'
ℹ️ Info: Deleted directory: ...

=== 4. wtdel by path ===
$ hug wtdel -p /var/tmp/hug-wt-exercise.WT.from-tag -f
✅ Success: Worktree removed for branch 'from-tag'

=== 5. wtdel with -B (branch deletion) ===
$ hug wtdel hotfix-from-beta -B -f
✅ Success: Worktree removed for branch 'hotfix-from-beta'
✅ Success: Branch 'hotfix-from-beta' deleted

=== 6. Batch delete (valid) ===
$ hug wtdel experiment-1 nonexistent-branch -f
[1/2] experiment-1: Status: Dirty -- untracked files (will be permanently lost)
[2/2] nonexistent-branch: Status: Clean
Batch Removal Summary: Removed: 2

=== 6a. Batch delete (stale entry) ===
$ hug wtdel experiment-1 from-past -f
❌ Error: No worktree found for branch 'from-past'
(Nothing removed)

=== 7. Batch by path ===
$ hug wtdel -p /var/tmp/hug-wt-exercise.WT.main -p /var/tmp/my-custom-wt -f
[1/2] main: Clean
[2/2] custom-path-branch: Clean
Batch Removal Summary: Removed: 2

=== 8. Main worktree (blocked) ===
$ hug wtdel main -f
❌ Error: Cannot remove the main worktree (branch 'main').
```

</details>
