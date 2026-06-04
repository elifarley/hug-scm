# Fix: `hug wtdel` False-Rejects Submodule Worktrees

## Problem Statement

Running `hug wtdel` against a worktree that belongs to a Git **submodule**
(rather than a top-level repo) produces a false-rejection warning and
refuses to remove the worktree:

```
$ hug wtdel some-feature-branch -B --dry-run
⚠️ Warning: Path is not a Git worktree: /path/to/meta/.git/modules.WT.some-feature-branch

$ hug wtdel -p /path/to/meta/.git/modules.WT.some-feature-branch -B --dry-run
⚠️ Warning: Path is not a Git worktree: /path/to/meta/.git/modules.WT.some-feature-branch
```

Both invocation forms fail (positional branch name and explicit `-p PATH`).

The worktree IS a real worktree — confirmed independently:

```
$ ls -la /path/to/meta/.git/modules.WT.some-feature-branch/.git
-rw-rw-r-- 1 user user … .git

$ cat /path/to/meta/.git/modules.WT.some-feature-branch/.git
gitdir: /path/to/meta/.git/modules/sub/worktrees/modules.WT.some-feature-branch
```

The `.git` file points correctly into the **submodule's** worktree namespace
(`<meta>/.git/modules/<submodule>/worktrees/<wt-name>/`), not the meta-repo's.

## Reproducer

The setup is the standard hug-blessed submodule-worktree layout:

```
meta/                                           # meta-repo (clone)
├── .git/
│   ├── modules/
│   │   └── sub/                                # submodule's gitdir
│   │       └── worktrees/
│   │           └── modules.WT.feat-x/          # canonical metadata path
│   └── modules.WT.feat-x/                      # canonical worktree dir (per `hug wtc`)
│       ├── .git                                # → ../modules/sub/worktrees/modules.WT.feat-x
│       └── …working tree…
└── sub/                                        # submodule main checkout
```

After `hug wtc feat-x -y` from inside `meta/sub/`, the worktree exists at
`meta/.git/modules.WT.feat-x` and `git worktree list -C meta/sub` correctly
enumerates it. Calling `hug wtdel feat-x -B` from `meta/sub` (or from any
CWD) produces the warning above and exits without removing.

## Root Cause Analysis

The gate that emits the warning is in `git-config/bin/git-wtdel`:

```bash
# git-config/bin/git-wtdel:321
elif ! worktree_exists "$worktree_path"; then
    warning "Path is not a Git worktree: $worktree_path"
```

`worktree_exists()` is defined in `git-config/lib/hug-git-worktree`:

```bash
# git-config/lib/hug-git-worktree:307
worktree_exists() {
    local path="$1"
    [[ -n "$path" ]] && git worktree list --porcelain 2>/dev/null | grep -qF "worktree $path"
}
```

**The bug**: `git worktree list --porcelain` is invoked **without `-C`**, so it
runs against whichever repo `$PWD` resolves to. For a submodule worktree:

1. Top-level repo's `git worktree list` enumerates only the top-level's own
   worktrees — submodule worktrees live in a **separate** gitdir
   (`<meta>/.git/modules/<sub>/`) and are not visible.
2. Even when CWD is inside the submodule's main checkout (`meta/sub/`), git
   resolves the gitdir to `<meta>/.git/modules/<sub>/`, but the worktree to
   delete lives at `<meta>/.git/modules.WT.<wt-name>/` and reports a
   `worktree …` line whose absolute path matches what we asked about.
   Whether this case works or not depends on which gitdir CWD resolves to —
   inconsistent.
3. From `<meta>/.git/modules.WT.<wt-name>/` itself (the worktree we want to
   delete), CWD obviously can't be used as the verifier at delete time.

In all of these, the verifier lacks an unambiguous anchor: there's no
guarantee that `git worktree list` from CWD enumerates the worktree we are
asking about. The check then fails, even when the path is a real worktree.

## Why Tests Didn't Catch This

Existing tests for `wtdel` almost certainly target top-level (non-submodule)
worktrees, where CWD's gitdir trivially matches the worktree's owning repo.
Submodule worktrees are a narrower setup that needs:

1. A meta-repo with at least one submodule
2. A worktree created in the submodule's namespace (not the meta-repo's)
3. An invocation of `hug wtdel` with that worktree as the target

`tests/unit/test_wtdel*.bats` (or equivalent) likely exercise (1) skipped /
flat repo only.

## Suggested Fix

In `worktree_exists()` (line 307), anchor the verifier to the worktree's own
gitdir rather than relying on CWD. Two equivalent options:

**Option A — `git -C "$path" worktree list`** (requires `$path` to be a
working tree, not just a candidate):

```bash
worktree_exists() {
    local path="$1"
    [[ -n "$path" && -e "$path/.git" ]] || return 1
    git -C "$path" worktree list --porcelain 2>/dev/null | grep -qF "worktree $path"
}
```

**Option B — resolve the gitdir from `$path/.git` and query that**
(works even if `$path` is in a strange CWD context):

```bash
worktree_exists() {
    local path="$1"
    [[ -n "$path" && -e "$path/.git" ]] || return 1
    local gitdir
    gitdir=$(git -C "$path" rev-parse --git-common-dir 2>/dev/null) || return 1
    git --git-dir="$gitdir" worktree list --porcelain 2>/dev/null \
        | grep -qF "worktree $path"
}
```

**Option B is more robust** for the submodule case because
`--git-common-dir` resolves through the `.git` file's `gitdir:` indirection
to the canonical metadata location.

After the fix, every caller of `worktree_exists()` (currently `git-wtdel`
line 321 and any siblings under `git-config/bin/`) will accept submodule
worktrees correctly. No call-site changes needed — this is an internal
helper.

## Files To Modify

- `git-config/lib/hug-git-worktree` — rewrite `worktree_exists()` (line 307).
- `tests/unit/test_wtdel*.bats` (or wherever wtdel tests live) — add a
  fixture that creates a meta-repo with a submodule + a worktree in the
  submodule's namespace, and asserts `hug wtdel <branch>` succeeds.

## Verification Plan

After applying the fix, the following should all succeed (each was failing
before):

```bash
# Setup (one-shot)
mkdir -p /tmp/hugbug-meta /tmp/hugbug-sub
( cd /tmp/hugbug-sub && git init && touch a && git add . && git commit -m init )
( cd /tmp/hugbug-meta && git init && git submodule add /tmp/hugbug-sub sub && git commit -m init )
( cd /tmp/hugbug-meta/sub && hug wtc feat-x --new -y )

# All three should now PASS where they previously printed
# "Path is not a Git worktree":
( cd /tmp/hugbug-meta/sub && hug wtdel feat-x -B --dry-run )
( cd /tmp/hugbug-meta && hug wtdel -p .git/modules.WT.feat-x -B --dry-run )
( cd /tmp/hugbug-meta/.git/modules.WT.feat-x && cd .. && hug wtdel feat-x -B --dry-run )

# Negative test (should still warn)
hug wtdel -p /tmp/does-not-exist -B --dry-run
# → ⚠️ Warning: Path is not a Git worktree: /tmp/does-not-exist
```

## Workaround Until Fixed

For users hitting this bug today: the worktree directory can be removed
manually, then `hug wtprune` cleans the orphaned metadata (its docstring
explicitly covers this case: *"Worktree directories were manually
deleted"*):

```bash
rm -rf /path/to/meta/.git/modules.WT.feat-x
( cd /path/to/meta/sub && hug wtprune -f )
# Then delete the now-detached merged branch:
( cd /path/to/meta/sub && hug bdel feat-x -y )
```

This is functionally equivalent to what a fixed `hug wtdel … -B --force`
would do, but it requires three separate invocations and breaks the single-
command UX `wtdel` is designed to provide.

## Discovery Context

Surfaced while attempting routine post-merge cleanup of two merged
feature branches in a meta-repo with submodules. Both `hug wtdel <branch>`
and `hug wtdel -p <abs-path>` rejected the worktrees with the same
warning. Direct `git worktree list` (read-only verification, run for
diagnosis only) confirmed the worktrees were real and correctly registered
in the submodule's metadata namespace.

## Recurrence Log

The bug reproduces consistently across days in routine post-merge
cleanup of submodule worktrees — not an edge case. Each line below is
an independent encounter:

- **2026-05-15** — initial surface, two merged feature branches in
  a meta-repo with submodules (above).
- **2026-05-16 (encounter A)** — single merged feature branch in the
  same meta-repo layout; `hug wtdel <branch> --force` rejected the
  worktree at `<meta>/.git/modules.WT.<branch-slug>` with the identical
  warning. Workaround section (`rm -rf` + `hug wtprune` + `hug bdel`)
  applied successfully.
- **2026-05-16 (encounter B)** — one more merged feature branch, same
  layout, same warning, same workaround. The worktree path remained
  on disk because the workflow rule (CLAUDE.md hard rule against
  raw `git worktree remove` fallbacks) ruled out the alternative path.
- **2026-05-19** — two merged feature branches in a submodule-heavy
  meta-repo layout, routine post-merge cleanup. **Failure mode has
  evolved**: `hug wtdel <branch> --force --with-branch` no longer emits
  the "Path is not a Git worktree" warning — instead it accepts the
  arguments, prints an informational diagnostic, and exits without
  error:

  ```
  ℹ️ Info: Submodule worktree detected. If 'hug wtl' lists this path, your hug
  ℹ️ Info: install may pre-date commit 1b046f8 (May 2026 submodule anchor fix).
  ℹ️ Info: Verify with:  grep -q 'find_worktree_owning_gitdir()' \
  ℹ️ Info:                  "$HUG_HOME/git-config/lib/hug-git-worktree" \
  ℹ️ Info:                  && echo CURRENT || echo PRE-FIX
  ```

  Net outcome: identical to earlier encounters — `hug wtl` still lists
  the worktree, the directory persists on disk, no non-zero exit code a
  caller can branch on — but the surfaced UX changed from a warning to
  a soft install-version hint. The observed path layout was
  `<meta>/<submodule-name>.WT.<branch>` (sibling to the submodule's
  working tree, **not** inside `<meta>/.git/`), distinct from the
  `<meta>/.git/modules.WT.<branch>` layout described in the original
  Reproducer — suggesting the underlying bug surfaces in **both**
  submodule-worktree path layouts. The `1b046f8` commit reference in
  the diagnostic implies the upstream fix has landed; pre-fix installs
  still hit the failure mode regardless of which layout the worktree
  uses. Workaround unavailable here (same CLAUDE.md rule against raw
  `git worktree remove`), so both worktrees remained on disk.

**Severity assessment:** P2 — functional UX gap with a documented
workaround, but the workaround:

1. Requires **three sequential commands** instead of one (`wtdel … -B`
   was designed to be the single-command cleanup).
2. Leaves leftover worktree directories on disk if downstream agents
   (per project rules / CLAUDE.md) cannot fall back to raw
   `git worktree remove`. Disk-space-bounded harm, but it does
   accumulate over time as merged branches pile up.
3. **Compounds with submodule-heavy workflows.** Every merge in a
   submodule-heavy meta-repo (the typical Hug power-user setup) hits
   this path; that's the audience most invested in the worktree
   cleanup UX.

The recurrence rate (4 independent encounters across 5 days, all from
the same single user's workflow) suggests this fix should be prioritized
above bugs surfaced once. Anyone using submodule worktrees + `hug
wtdel` is hitting it — across **both** the in-`.git/modules` and the
sibling-to-submodule path layouts.
