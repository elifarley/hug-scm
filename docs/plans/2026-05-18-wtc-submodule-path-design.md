# `hug wtc` — Submodule-Safe Worktree Path Generation (Design)

**Date:** 2026-05-18
**Status:** APPROVED — ready for implementation plan
**Authors:** Claude Code (Opus 4.7) with Elifarley
**Related:** Commit `1b046f8` (wtdel submodule fix), Issue #149 (broader sweep)

---

## 1. Problem

`hug wtc` sometimes creates worktrees under `<meta>/.git/modules.WT.<branch>` (or similar paths inside a meta-repo's `.git/` directory) when invoked from a submodule working tree. The intended path is a sibling of the current working tree, outside any `.git/` directory.

### Reproducer

```bash
mkdir hugbug-sub hugbug-meta
( cd hugbug-sub && git init -q && touch a && hug a a && hug c -m init )
( cd hugbug-meta && git init -q && touch m && hug a m && hug c -m init \
  && git -c protocol.file.allow=always submodule add -q ../hugbug-sub sub \
  && hug a . && hug c -m sub )
( cd hugbug-meta/sub && hug wtc feat-x --new -y )

# Observed: worktree at hugbug-meta/.git/modules.WT.feat-x
# Expected: worktree at hugbug-meta/sub.WT.feat-x
```

## 2. Root Cause

Three layered defects compound:

### 2.1 `get_main_worktree_path()` is submodule-naive

`git-config/lib/hug-git-worktree:292` derives the main worktree path via `dirname(git rev-parse --git-common-dir)`. The assumption is that `--git-common-dir` looks like `/path/to/repo/.git`, so stripping the last segment yields the working tree.

For submodules, `--git-common-dir` returns the submodule's gitdir at `<meta>/.git/modules/<sub>`. Stripping one segment yields `<meta>/.git/modules` — a directory of gitdirs, not a working tree.

### 2.2 `generate_worktree_path()` inherits the bad anchor

`git-config/lib/hug-git-worktree:655` calls `get_main_worktree_path()` and computes `$(dirname anchor)/$(basename anchor).WT.<branch>`. Given the bogus anchor above, this produces `<meta>/.git/modules.WT.<branch>` — inside the meta-repo's `.git/` directory.

### 2.3 `validate_worktree_creation_path()` lacks a `.git/` guard

`git-config/lib/hug-git-worktree:577` only refuses paths *inside the current working tree* (`--show-toplevel`). A path under `<meta>/.git/modules.WT.<branch>` is not inside the current submodule WT, so the check passes and the worktree is created in the wrong place.

## 3. Goals & Non-Goals

### Goals

- `hug wtc` invoked from a submodule produces a worktree path that is a sibling of the submodule's working tree, outside any `.git/` directory.
- The library primitive `resolve_main_worktree_path()` (renamed from `get_main_worktree_path`) returns the correct working-tree path for all three topologies: plain clone, linked worktree, submodule.
- A defense-in-depth guard prevents any future regression from creating a worktree path under a `.git/` directory.
- When the worktree lives inside a superproject, emit a one-time tip suggesting a `.gitignore` entry — silently skipped when the path is already ignored.

### Non-Goals (deferred to issue #149 sweep)

- The 11 sibling CWD-anchor sites in `wtl/wtll/wtsh/wtprune` and the Python worktree modules.
- `worktree_select.py:323` `removesuffix("/.git")` mis-classification.
- Full merge of `worktree_gitdir` and `resolve_main_worktree_path` into one helper (start of consolidation only; finish in #149).
- Mercurial parity (no equivalent topology in `hg-config/`).

## 4. Design

### 4.1 Library architecture (`git-config/lib/hug-git-worktree`)

Four new/renamed helpers:

```bash
# RENAMED from get_main_worktree_path. Returns the main working-tree path
# that the current gitdir owns (anchored by porcelain, not by string
# manipulation of --git-common-dir).
resolve_main_worktree_path() {
    local gitdir
    gitdir=$(worktree_gitdir "$(pwd)") || return 1
    git --git-dir="$gitdir" worktree list --porcelain 2>/dev/null \
        | awk '/^worktree / { print substr($0, 10); exit }'
}

# NEW. Returns the superproject working-tree path, or empty string.
get_superproject_path() {
    git rev-parse --show-superproject-working-tree 2>/dev/null
}

# NEW. Returns 0 if $candidate's realpath has any ancestor named ".git".
# Walks ancestors (no git invocations). Handles non-existent paths via
# `realpath -m`, resolves symlinks first so symlinked paths under .git/
# are still caught.
path_is_inside_dot_git() {
    local rp
    rp=$(realpath -m "$1" 2>/dev/null) || rp="$1"
    while [[ "$rp" != "/" && -n "$rp" ]]; do
        [[ "$(basename "$rp")" == ".git" ]] && return 0
        rp=$(dirname "$rp")
    done
    return 1
}

# NEW. Emits a one-line tip when the new worktree lives inside a
# superproject AND the superproject's .gitignore does not already
# ignore it. Probes via `git check-ignore`, the canonical plumbing
# that honors every ignore source (root .gitignore, nested ones,
# .git/info/exclude, global ignore, negation rules).
suggest_superproject_ignore() {
    local worktree_path="$1" super_path
    super_path=$(get_superproject_path) || return 0
    [[ -n "$super_path" ]] || return 0
    if ! git -C "$super_path" check-ignore --no-index -q "$worktree_path" 2>/dev/null; then
        tip "Worktree lives inside superproject ${super_path/#$HOME/\~}."
        tip "Add to its .gitignore (covers all future worktrees):"
        tip "    cd ${super_path/#$HOME/\~} && printf '*.WT.*/\\n' >> .gitignore"
    fi
}
```

**Why `worktree list --porcelain | awk` over `dirname(--git-common-dir)`:** porcelain output's first `worktree <path>` line is the canonical main-worktree path. It is anchored to the gitdir we pass via `--git-dir`, so submodules resolve correctly. No string manipulation, no special cases, no `.git`-suffix stripping. Format has been stable since Git 2.7 (2015).

**Why a separate `resolve_main_worktree_path` rather than reusing `worktree_gitdir`:** they answer different questions. `worktree_gitdir` returns a *gitdir*; `resolve_main_worktree_path` returns a *working-tree path*. They share the absolutize step (centralized in `worktree_gitdir`), but their contracts diverge from there.

### 4.2 Path generation (rewritten `generate_worktree_path`)

```bash
generate_worktree_path() {
    local branch="$1"
    [[ -n "$branch" ]] || return 1
    local main_path parent_dir repo_name safe_branch
    main_path=$(resolve_main_worktree_path) || return 1
    parent_dir=$(dirname "$main_path")
    repo_name=$(basename "$main_path")
    safe_branch=$(printf '%s' "$branch" | sed 's|/|-|g; s|\.|-|g' | tr '[:upper:]' '[:lower:]')
    if [[ ! -w "$parent_dir" ]]; then
        printf '/tmp/hug-wt-%s-%s-%s' "$repo_name" "$$" "$safe_branch"
        return 0
    fi
    printf '%s/%s.WT.%s' "$parent_dir" "$repo_name" "$safe_branch"
}
```

The function shape is unchanged — only the anchor is now correct.

**Resulting placements:**

| CWD when running `hug wtc feat-x` | `resolve_main_worktree_path()` | Generated path |
|---|---|---|
| Plain clone `~/work/foo/` | `~/work/foo` | `~/work/foo.WT.feat-x` |
| Linked WT `~/work/foo.WT.bug-1/` | `~/work/foo` | `~/work/foo.WT.feat-x` |
| Submodule `~/work/meta/sub/` | `~/work/meta/sub` | `~/work/meta/sub.WT.feat-x` |

### 4.3 Validation guard (`validate_worktree_creation_path` extension)

After the existing checks (empty, exists, parent writable, not inside CWD), add:

```bash
if path_is_inside_dot_git "$path"; then
    warning "Refusing to create worktree under a .git directory: $path"
    info "This usually means an ancestor primitive returned a gitdir as if it"
    info "were a working tree (e.g. submodule mis-detection). Pass an explicit"
    info "path outside any .git/ directory."
    return 1
fi
```

Catches:
- Future regressions in any path-generation primitive.
- User-supplied paths under `.git/` (typos, completion misfires, scripts).
- Unanticipated repo topologies (worktrees of worktrees, multi-superproject nesting).

### 4.4 `git-wtc` integration

After the success message (line 378 area), call `suggest_superproject_ignore "$worktree_path"`. The helper is silent when there's no superproject or when the path is already ignored, so plain-clone behavior is unchanged.

## 5. Rollout

Three atomic commits, each independently testable and revertable:

1. **`refactor: rename get_main_worktree_path → resolve_main_worktree_path`**
   Pure rename across 6 call sites (`hug-git-worktree:285,292,312 comment,664,1014`, `git-wtdel:170`, `git-wtc:266`). Tests pin existing behavior before internals change.

2. **`fix: resolve main worktree via porcelain for submodule support`**
   Rewrites `resolve_main_worktree_path` internals; adds `get_superproject_path`. Fixes the user-reported bug. New BATS tests validate all three topologies.

3. **`feat: guard worktree paths under .git/ and tip on superproject ignore`**
   Adds `path_is_inside_dot_git`, `suggest_superproject_ignore`; hooks into `validate_worktree_creation_path` and `git-wtc` post-success.

## 6. Tests

### 6.1 `tests/lib/test_hug_git_worktree.bats` (new cases)

- `resolve_main_worktree_path` returns repo path for plain clone.
- `resolve_main_worktree_path` returns submodule WT path when CWD is a submodule (reuses `create_test_submodule_worktree` fixture from commit `1b046f8`).
- `resolve_main_worktree_path` returns main WT path when CWD is a linked worktree.
- `get_superproject_path` returns `""` for plain clone; returns meta path for submodule CWD.
- `path_is_inside_dot_git`: returns 0 for `.git/`, `.git/modules/x`, `<repo>/.git/x.WT.y`, symlink-into-`.git`; returns 1 for `.WT.x`, `foo.git/x`, sibling-of-`.git`.

### 6.2 `tests/unit/test_worktree_create.bats` (new cases, extend the existing file)

- **From submodule CWD:** generated path is `<submodule-wt>.WT.<branch>` — assert path does not contain `/.git/` substring.
- **From submodule CWD:** tip about superproject `.gitignore` is emitted on stderr.
- **From submodule CWD with `*.WT.*/` already in `<super>/.gitignore`:** tip is NOT emitted.
- **From plain clone:** tip is NOT emitted (regression guard against false positives).
- **User-supplied path under `.git/`:** `hug wtc feat <meta>/.git/whatever` fails with the new validation error message before any state change.
- **Validation guard error message format:** assert presence of "Refusing to create worktree under a .git directory" phrase.

### 6.3 `tests/test_helper.bash`

Reuses `create_test_submodule_worktree` verbatim from the `wtdel` PR. No new fixtures required.

## 7. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `git worktree list --porcelain` format change | Format stable since Git 2.7 (2015). Pinned to documented `worktree <path>` prefix at record start. |
| `realpath -m` portability (macOS) | Codebase already uses `readlink -f` with `greadlink` fallback (`git-wtc:CMD_BASE`). Reuse same pattern if `realpath -m` proves unreliable. |
| Renaming `get_main_worktree_path` breaks external scripts | Function is library-internal (sourced via `HUG_HOME/git-config/lib/`). 6 in-tree call sites updated atomically; no external consumers known. |
| `check-ignore` semantics edge cases | Short-circuited by `get_superproject_path` empty-check — never runs without a superproject. |
| Future repo topologies (worktree-of-submodule-of-worktree) | Caught by `path_is_inside_dot_git` even if primitive misbehaves. |

## 8. Out of Scope

Tracked under issue #149:

- `worktree_validate.py:255,300`, `worktree.py:583`, `worktree_select.py:323,328` — Python CWD-anchor + suffix mis-classification.
- `branch_available_for_worktree` (line ~445), `prune_worktrees` (line ~802) — Bash CWD-anchor sites.
- Full merger of `worktree_gitdir` and `resolve_main_worktree_path` into one `resolve_repo_anchor()` triple-returner.
- Sweep tests for `wtl/wtll/wtsh/wtprune` using `create_test_submodule_worktree`.

## 9. Open Questions

None. All UX decisions resolved during the brainstorming session:

- **Submodule WT placement:** sibling of submodule WT, inside meta. (Mirrors plain-clone semantics; the `.gitignore` tip handles the only downside.)
- **`.gitignore` pattern:** broad — `*.WT.*/` — covers all current and future worktrees.
- **Tip suppression:** silent when `git check-ignore` reports the path is already ignored.
- **Validator scope:** broadened — any ancestor named `.git`, not just CWD/superproject gitdirs.
- **Rename strategy:** clean break (no deprecation shim); 6 call sites updated atomically.
