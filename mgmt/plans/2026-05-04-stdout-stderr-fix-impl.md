# Stdout/Stderr Discipline — Full Compliance Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Fix all stdout/stderr discipline violations across 5 libraries and 21 commands so that `stdout = data` and `stderr = chatter`.

**Architecture:** Library-first cascade — fix shared libraries first (cascading benefits to callers), then fix commands in grouped commits by category. Each task is one commit with regression testing via `make test`.

**Tech Stack:** Bash, BATS testing (regression only)

---

### Task 0: Fix `print_list()` in `hug-arrays` → stderr

**Files:**
- Modify: `git-config/lib/hug-arrays:49,52`

**Step 1: Implement the change**

Change lines 49 and 52 to redirect to stderr:

```bash
# Line 49 — add >&2
printf '%s (%d):\n' "$title" "$#" >&2

# Line 52 — add >&2
printf '  %s\n' "$item" >&2
```

**Step 2: Run regression tests**

Run: `make test`
Expected: ALL PASS

**Step 3: Commit**

```bash
hug a git-config/lib/hug-arrays
hug commit -m "refactor: redirect print_list() to stderr in hug-arrays

WHY: print_list outputs human-facing labels and file lists (chatter),
not machine-consumable data. It should go to stderr per our stdout/stderr
discipline principles (see CLAUDE.md).

IMPACT: Cascading fix — all callers automatically benefit:
- hug-output: print_staged_unstaged_paths, print_untracked_ignored_paths
- hug-git-discard: 8+ call sites
- git-w-purge: 3 call sites"
```

---

### Task 1: Fix `hug-output` section headers → stderr

**Files:**
- Modify: `git-config/lib/hug-output:120,122,128,133`

**Step 1: Implement the changes**

Add `>&2` to 4 `printf` statements in `print_staged_unstaged_paths`:

- Line 120: `printf '  Staged paths (unstaged changes in these files would be preserved):\n' >&2`
- Line 122: `printf '  Staged paths:\n' >&2`
- Line 128: `printf '  Unstaged paths:\n' >&2`
- Line 133: `printf '  (Both staged and unstaged would be fully discarded for affected paths)\n' >&2`

**Step 2: Run regression tests**

Run: `make test`
Expected: ALL PASS

**Step 3: Commit**

```bash
hug a git-config/lib/hug-output
hug commit -m "refactor: redirect hug-output section headers to stderr

WHY: 'Staged paths:', 'Unstaged paths:', and explanatory notes are
human-facing chatter, not data. print_list calls already fixed by
previous commit.

IMPACT: Callers of print_staged_unstaged_paths (git-w-discard, etc.)
now have clean stdout."
```

---

### Task 2: Fix `hug-git-discard` status messages → stderr

**Files:**
- Modify: `git-config/lib/hug-git-discard` (lines 44, 49, 59, 124, 130, 140, 167, 173, 216, 304, 370, 376, 424, 440, 460)

**Step 1: Implement the changes**

Add `>&2` to standalone `printf` statements that output success messages, dry-run previews, and "no changes" notices. Lines to change:

- 44: `'No unstaged changes to discard...'`
- 49: `'Dry run: Would discard...'`
- 59: `'Discarded all unstaged changes...'`
- 124: `'No uncommitted changes to discard...'`
- 130: `'Dry run: Would discard all uncommitted...'`
- 140: `'Successfully discarded all uncommitted...'`
- 167: `'No uncommitted changes to discard for specified paths...'`
- 173: `'Dry run: Would discard all uncommitted... for paths...'`
- 216: `'Discarded staged changes from...'`
- 304: `'Discarded staged changes from... (unstaged preserved)'`
- 370: `'No staged changes to discard...'`
- 376: `'Dry run: Would discard staged...'`
- 424: `'Successfully discarded all staged...'`
- 440: `'Dry run: ...'` in `handle_dry_run_confirmation`
- 460: `printf '%s\n' "$message"` in `check_no_changes`

Note: `print_list` calls are already fixed by Task 0. Skip those.

**Step 2: Run regression tests**

Run: `make test`
Expected: ALL PASS

**Step 3: Commit**

```bash
hug a git-config/lib/hug-git-discard
hug commit -m "refactor: redirect hug-git-discard status messages to stderr

WHY: Success messages, dry-run previews, and 'no changes' notices
are human-facing chatter. print_list calls already fixed by hug-arrays
change.

IMPACT: All discard operations now have clean stdout for data output."
```

---

### Task 3: Fix `hug-git-worktree` summary/prune → stderr

**Files:**
- Modify: `git-config/lib/hug-git-worktree` (lines 828, 832, 838, 846, 879-881, 902)

**Step 1: Implement the changes**

In `show_worktree_summary` (lines 879-902), redirect chatter:
- Line 879: `echo` → `echo >&2`
- Line 880: `printf "${BLUE}Worktrees (%d):${NC}\n" "$count"` → add `>&2`
- Line 881: `echo` → `echo >&2`
- Line 902: `echo` → `echo >&2`

In `prune_worktrees` (lines 828-848), redirect chatter:
- Line 828: `echo "Found ..."` → add `>&2`
- Line 832: `echo "Would prune ..."` → add `>&2`
- Line 838: `echo "Pruning will remove..."` → add `>&2`
- Line 846: `echo "Pruning orphaned..."` → add `>&2`

Note: Line 829 (`printf '  %s\n'`) is the orphaned worktree listing — this is DATA, keep on stdout.

**Step 2: Run regression tests**

Run: `make test`
Expected: ALL PASS

**Step 3: Commit**

```bash
hug a git-config/lib/hug-git-worktree
hug commit -m "refactor: redirect worktree summary/prune headers to stderr

WHY: Headers and status messages in show_worktree_summary and
prune_worktrees are human-facing chatter. Worktree data lines stay
on stdout.

IMPACT: Callers (git-wt, git-wtsh) get cleaner stdout."
```

---

### Task 4: Fix `hug-git-show` section headers → stderr

**Files:**
- Modify: `git-config/lib/hug-git-show` (lines 220, 229, 239)

**Step 1: Implement the changes**

Add `>&2` to 3 section header `printf` statements in `_show_commit_standard`:

- Line 220: `printf '%s %s Commit info:\n' "$commit_emoji" "$info_emoji" >&2`
- Line 229: `printf '\n%s %s Commit diff:\n' "$commit_emoji" "$diff_emoji" >&2`
- Line 239: `printf '\n%s %s File stats:\n' "$commit_emoji" "$stats_emoji" >&2`

**Step 2: Run regression tests**

Run: `make test`
Expected: ALL PASS

**Step 3: Commit**

```bash
hug a git-config/lib/hug-git-show
hug commit -m "refactor: redirect commit section headers to stderr in hug-git-show

WHY: 'Commit info:', 'Commit diff:', 'File stats:' are section labels
(chatter), not data. The actual git output between them is data and
stays on stdout.

IMPACT: git-sh, git-shp output is now capture-friendly."
```

---

### Task 5: Fix worktree display commands (wtsh, wtll, wt)

**Files:**
- Modify: `git-config/bin/git-wtsh` (lines 181-183, 186, 206-207)
- Modify: `git-config/bin/git-wtll` (line 115)
- Modify: `git-config/bin/git-wt` (line 111)

**Step 1: Fix git-wtsh**

Add `>&2` to 6 lines:
- Line 181: `"Worktree Summary"` header
- Line 182: `"───────"` separator
- Line 183: `"Current: %s"` label
- Line 186: `"No worktrees found"` message
- Line 206: `"Worktrees (%d total)"` header
- Line 207: `"───────"` separator

**Step 2: Fix git-wtll**

- Line 115: `printf "${BLUE}Worktrees (long format):%s${NC}\n" "" >&2`

**Step 3: Fix git-wt**

- Line 111: `printf "${BLUE}Worktrees (%d)${NC}\n" "$additional_count" >&2`

**Step 4: Run regression tests**

Run: `make test`
Expected: ALL PASS

**Step 5: Commit**

```bash
hug a git-config/bin/git-wtsh git-config/bin/git-wtll git-config/bin/git-wt
hug commit -m "refactor: redirect worktree display headers to stderr

WHY: 'Worktree Summary', 'Worktrees (N)', 'Worktrees (long format):',
separators, and 'No worktrees found' are all decorative chatter.
Data lines (worktree entries) stay on stdout.

IMPACT: hug wtsh, hug wtll, hug wt --summary now pipe-friendly."
```

---

### Task 6: Fix worktree create/delete commands (wtc, wtdel)

**Files:**
- Modify: `git-config/bin/git-wtc` (lines 209, 251-259, 265-273, 324)
- Modify: `git-config/bin/git-wtdel` (lines 246-251, 266-275, 285-294, 338, 348-354)

**Step 1: Fix git-wtc**

Add `>&2` to all preview/summary `printf` and bare `echo` lines:
- Lines 209, 251, 259, 265, 273, 324: bare `echo` → `echo >&2`
- Lines 252-258: dry-run preview block (Branch/Path display)
- Lines 266-272: creation summary block (Branch/Path display)

**Step 2: Fix git-wtdel**

Add `>&2` to all summary/preview `printf` and bare `echo` lines:
- Lines 246, 251, 266, 275, 285, 294, 338, 348, 354: bare `echo` → `echo >&2`
- Lines 247-250: removal summary (Branch/Path/Status)
- Lines 268-274: dry-run preview (Branch/Path/Status)
- Lines 287-293: removal summary (Branch/Path/Status)
- Lines 349-353: batch summary (Removed/Failed counts)

**IMPORTANT:** Line 74 (`printf '%s' "$selected_path"`) is DATA — do NOT change it.

**Step 3: Run regression tests**

Run: `make test`
Expected: ALL PASS

**Step 4: Commit**

```bash
hug a git-config/bin/git-wtc git-config/bin/git-wtdel
hug commit -m "refactor: redirect wtc/wtdel summary blocks to stderr

WHY: Creation and removal summaries (branch, path, status) are
human-facing feedback, not machine-consumable data. Dry-run previews
are also chatter. The selected_path on stdout (wtdel line 74) is
preserved as data.

IMPACT: hug wtc and hug wtdel now pipe-friendly."
```

---

### Task 7: Fix status/snapshot commands (sx, shc)

**Files:**
- Modify: `git-config/bin/git-sx` (lines 96, 99, 141, 148, 152-157, 163, 168, 172)
- Modify: `git-config/bin/git-shc` (lines 112, 120)

**Step 1: Fix git-sx**

Add `>&2` to all chatter lines:
- Lines 96, 99: `print_top_list` title and bullet items
- Line 141: `summarize_paths` output
- Line 148: `"Working tree is clean."`
- Lines 152-156: snapshot header + stat lines (Staged/Unstaged/Untracked/Ignored counts)
- Line 157: blank `printf '\n'`
- Line 163: `"Untracked samples"` label
- Line 168: `"Ignored samples"` label
- Line 172: tip text

**Step 2: Fix git-shc**

- Line 112: `printf '%s %s Changed files in range %s:\n' ... >&2`
- Line 120: `printf '%s %s Changed files:\n' ... >&2`

**Step 3: Run regression tests**

Run: `make test`
Expected: ALL PASS

**Step 4: Commit**

```bash
hug a git-config/bin/git-sx git-config/bin/git-shc
hug commit -m "refactor: redirect sx/shc headers and labels to stderr

WHY: 'Working tree snapshot', 'Working tree is clean', section labels,
stat counts, tips, and 'Changed files:' headers are all chatter.

IMPACT: hug sx and hug shc now pipe-friendly."
```

---

### Task 8: Fix HEAD operation commands (h-steps, h-files)

**Files:**
- Modify: `git-config/bin/git-h-steps` (lines 114, 117)
- Modify: `git-config/bin/git-h-files` (lines 170-175, 183)

**Step 1: Fix git-h-steps**

- Line 114: `echo "0 steps back from HEAD (last change in current commit);" >&2`
- Line 117: `echo "$steps steps back from HEAD (last commit $short_hash);" >&2`

**Step 2: Fix git-h-files**

- Line 170: patch label → add `>&2`
- Line 171: bare `echo` → `echo >&2`
- Line 174: full patch label → add `>&2`
- Line 175: bare `echo` → `echo >&2`
- Line 183: bare `echo` → `echo >&2`

**Step 3: Run regression tests**

Run: `make test`
Expected: ALL PASS

**Step 4: Commit**

```bash
hug a git-config/bin/git-h-steps git-config/bin/git-h-files
hug commit -m "refactor: redirect h-steps/h-files labels to stderr

WHY: 'steps back from HEAD' prose and patch labels are chatter
mixed with hug ll / git diff data on stdout.

IMPACT: hug h-steps and hug h-files data output is now clean."
```

---

### Task 9: Fix tag operation commands (t, tc, tdel)

**Files:**
- Modify: `git-config/bin/git-t` (lines 152, 155, 158, 161, 167, 169, 172, 269-273, 298, 301, 304, 307)
- Modify: `git-config/bin/git-tc` (lines 171, 341, 349, 357, 394-398, 400-402, 416)
- Modify: `git-config/bin/git-tdel` (lines 152, 155, 158, 161, 239, 245, 248, 251, 254, 261, 263, 267, 330-336)

**Step 1: Fix git-t**

Add `>&2` to tag type labels (lightweight/annotated/signed), action menu prompts, and interactive prompts on all listed lines.

**Step 2: Fix git-tc**

Add `>&2` to suggestions display, name/target/type fields, tag summary block, commit preview, and blank lines.

**Step 3: Fix git-tdel**

Add `>&2` to tag display labels, "Tags to delete:" header, deletion list entries, and "Deletion Summary:" block.

**Step 4: Run regression tests**

Run: `make test`
Expected: ALL PASS

**Step 5: Commit**

```bash
hug a git-config/bin/git-t git-config/bin/git-tc git-config/bin/git-tdel
hug commit -m "refactor: redirect tag command labels and summaries to stderr

WHY: Tag type labels, deletion summaries, interactive prompts, and
suggestion displays are all human-facing chatter. git show output
(data) stays on stdout.

IMPACT: hug t, hug tc, hug tdel now pipe-friendly."
```

---

### Task 10: Fix working directory commands (w-discard, w-purge, w-purge-all, w-unwip)

**Files:**
- Modify: `git-config/bin/git-w-discard` (lines 199, 206)
- Modify: `git-config/bin/git-w-purge` (lines 170, 189, 202, 207, 211)
- Modify: `git-config/bin/git-w-purge-all` (lines 98, 104)
- Modify: `git-config/bin/git-w-unwip` (lines 170, 176)

**Step 1: Fix git-w-discard**

- Lines 199, 206: `printf '\n'` → `printf '\n' >&2`

**Step 2: Fix git-w-purge**

- Lines 170, 189: `printf '\n'` → `printf '\n' >&2`
- Lines 202, 207, 211: `print_list` calls already go to stderr (from Task 0), but add explicit `>&2` for clarity

**Step 3: Fix git-w-purge-all**

- Lines 98, 104: `printf '\n%s\n' "$preview_output"` → `printf '\n%s\n' "$preview_output" >&2`

**Step 4: Fix git-w-unwip**

- Lines 170, 176: add `>&2` to branch deletion messages

**Step 5: Run regression tests**

Run: `make test`
Expected: ALL PASS

**Step 6: Commit**

```bash
hug a git-config/bin/git-w-discard git-config/bin/git-w-purge git-config/bin/git-w-purge-all git-config/bin/git-w-unwip
hug commit -m "refactor: redirect working dir command chatter to stderr

WHY: Blank lines, preview output, and branch deletion messages are
chatter, not data. print_list calls already fixed at library level.

IMPACT: hug w-discard, w-purge, w-purge-all, w-unwip pipe-friendly."
```

---

### Task 11: Fix commit/staging commands (ccp, aa)

**Files:**
- Modify: `git-config/bin/git-ccp` (lines 117, 137, 152)
- Modify: `git-config/bin/git-aa` (lines 42, 43)

**Step 1: Fix git-ccp**

- Line 117: `"Staging N file(s)..."` → add `>&2`
- Line 137: `"Creating commit with message..."` → add `>&2`
- Line 152: `"Copying onto current branch..."` → add `>&2`

**Step 2: Fix git-aa**

- Line 42: error message → add `>&2`
- Line 43: hint message → add `>&2`

**Step 3: Run regression tests**

Run: `make test`
Expected: ALL PASS

**Step 4: Commit**

```bash
hug a git-config/bin/git-ccp git-config/bin/git-aa
hug commit -m "refactor: redirect ccp/aa progress and errors to stderr

WHY: 'Staging N files...', 'Creating commit...', and error messages
are chatter/errors, not data.

IMPACT: hug ccp and hug aa pipe-friendly."
```

---

### Task 12: Fix stats commands + reverse violation (stats-author, stats-branch, log-outgoing)

**Files:**
- Modify: `git-config/bin/git-stats-author` (awk lines ~201-203)
- Modify: `git-config/bin/git-stats-branch` (awk lines ~355-359)
- Modify: `git-config/bin/git-log-outgoing` (lines 98, 103, 104, 106, 107)

**Step 1: Fix git-stats-author**

In the awk block, redirect `printf` to `/dev/stderr`:
```awk
printf "  Added:   +%d lines\n", added > "/dev/stderr";
printf "  Deleted: -%d lines\n", deleted > "/dev/stderr";
printf "  Net:     %+d lines\n", added-deleted > "/dev/stderr";
```

**Step 2: Fix git-stats-branch**

In the awk block, redirect `printf` to `/dev/stderr`:
```awk
printf "\n" > "/dev/stderr";
printf "Code:\n" > "/dev/stderr";
printf "  Added:   +%d lines\n", added > "/dev/stderr";
printf "  Deleted: -%d lines\n", deleted > "/dev/stderr";
printf "  Net:     %+d lines\n", added-deleted > "/dev/stderr";
```

**Step 3: Fix git-log-outgoing (REVERSE violation — remove `>&2`)**

These lines have DATA wrongly on stderr. **Remove** `>&2`:
- Line 98: `print_commit_list_in_range "$target" HEAD` (remove `>&2`)
- Line 103: `printf '\nExact commits missing from %s:\n' "$remote_branch"` (remove `>&2`)
- Line 104: `git cherry -v "$target" HEAD` (remove `>&2`)
- Line 106: `printf '\nExact commits missing from upstream:\n'` (remove `>&2`)
- Line 107: `git cherry -v @{upstream} HEAD` (remove `>&2`)

**Step 4: Run regression tests**

Run: `make test`
Expected: ALL PASS

**Step 5: Commit**

```bash
hug a git-config/bin/git-stats-author git-config/bin/git-stats-branch git-config/bin/git-log-outgoing
hug commit -m "refactor: fix stats awk output + reverse log-outgoing violation

WHY: awk 'Code changes:' section labels in stats commands are chatter
→ redirect to /dev/stderr. git-log-outgoing had the REVERSE problem:
commit list data and cherry output were wrongly on stderr → move to
stdout where data belongs.

IMPACT: hug stats-author, stats-branch pipe-friendly. hug log-outgoing
data now capture-friendly on stdout."
```

---

### Task 13: Run full test suite and verify end-to-end

**Step 1: Run full test suite**

Run: `make test`
Expected: ALL PASS (2457 tests)

**Step 2: Spot-check key commands**

```bash
source bin/activate

# Verify chatter on stderr, data on stdout
hug sx 2>/dev/null        # Should show nothing (all chatter)
hug wtsh 2>/dev/null      # Should show only data lines
hug shc HEAD 2>/dev/null  # Should show only git diff output
```

**Step 3: No commit needed if everything passes**
