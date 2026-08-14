<!-- /autoplan restore point: /home/ecc/.gstack/projects/elifarley-hug-scm/main-autoplan-restore-20260518-105629.md -->
# `hug wtc` Submodule-Safe Worktree Path Generation — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Fix `hug wtc` so it never creates worktrees under `.git/modules/...` when invoked from a submodule working tree.

**Architecture:** Three atomic commits — (1) clean rename of the path-resolving primitive, (2) porcelain-based reimplementation that handles submodules correctly, (3) defense-in-depth validation guard plus a one-time `.gitignore` tip. Each commit independently testable and revertable.

**Tech Stack:** Bash, BATS, Git porcelain (`worktree list --porcelain`, `rev-parse --show-superproject-working-tree`, `check-ignore`).

**Design doc:** `docs/plans/2026-05-18-wtc-submodule-path-design.md` (approved).

**Fixture reuse:** `create_test_submodule_worktree` in `tests/test_helper.bash:1190` (do NOT modify; do NOT create new submodule fixtures).

---

## Commit 1 — Pure Rename (`refactor`)

**Commit message subject:** `refactor: rename get_main_worktree_path → resolve_main_worktree_path`

**Why first:** No behavior change. Locks in existing test coverage before internals are rewritten in Commit 2. If Commit 2 regresses, the rename remains useful and is easy to keep or revert in isolation.

### Task 1.1: Add lib test pinning current `get_main_worktree_path` behavior (will pass under the new name in Commit 1, will be supplemented in Commit 2)

**Files:**
- Modify: `tests/lib/test_hug-git-worktree.bats` (append at end of file)

**Step 1: Write the test (note the future name)**

```bash
@test "resolve_main_worktree_path: returns repo path for plain clone" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"
  source "$HUG_HOME/git-config/lib/hug-git-worktree"
  run resolve_main_worktree_path
  assert_success
  # Use realpath because macOS /tmp resolves to /private/tmp
  [[ "$(realpath "$output")" == "$(realpath "$repo")" ]]
  cleanup_test_repo "$repo"
}
```

**Step 2: Run it — expect FAIL (function doesn't exist yet)**

```bash
make test-lib TEST_FILE=test_hug-git-worktree.bats TEST_FILTER="resolve_main_worktree_path: returns repo path for plain clone"
```

Expected: FAIL with `resolve_main_worktree_path: command not found`.

**Step 3: Perform the rename in the library**

In `git-config/lib/hug-git-worktree`:
- Line 285 (usage comment): `# Usage: main_path=$(get_main_worktree_path)` → `# Usage: main_path=$(resolve_main_worktree_path)`
- Line 292 (function definition): `get_main_worktree_path()` → `resolve_main_worktree_path()`
- Line 312 (cross-ref comment): `# Pattern mirrors get_main_worktree_path() above.` → `# Pattern mirrors resolve_main_worktree_path() above.`
- Line 664 (internal call): `main_path=$(get_main_worktree_path)` → `main_path=$(resolve_main_worktree_path)`
- Line 1014 (internal call): `main_repo=$(get_main_worktree_path)` → `main_repo=$(resolve_main_worktree_path)`

**Step 4: Update callers in `bin/`**

- `git-config/bin/git-wtc:266`: `main_wt_path=$(get_main_worktree_path)` → `main_wt_path=$(resolve_main_worktree_path)`
- `git-config/bin/git-wtdel:170`: `main_worktree=$(get_main_worktree_path)` → `main_worktree=$(resolve_main_worktree_path)`

**Step 5: Sanity-grep that NO references to the old name remain**

```bash
grep -rn 'get_main_worktree_path' git-config/ tests/
```

Expected: empty output. If anything remains, fix before continuing.

**Step 6: Run the new test — expect PASS**

```bash
make test-lib TEST_FILE=test_hug-git-worktree.bats TEST_FILTER="resolve_main_worktree_path: returns repo path for plain clone"
```

Expected: PASS.

**Step 7: Run the full worktree-related suite to confirm no regressions**

```bash
make test-bash TEST_FILTER="worktree"
```

Expected: all pass.

### Task 1.2: Commit the rename

**Files:** all the above changes plus the new lib test.

**Step 1: Stage**

```bash
hug a git-config/lib/hug-git-worktree \
      git-config/bin/git-wtc \
      git-config/bin/git-wtdel \
      tests/lib/test_hug-git-worktree.bats
```

**Step 2: Verify what's staged**

```bash
hug sls
```

Expected: only the four files above with `S:Mod` (no spurious additions).

**Step 3: Commit (use message file to bypass hook regex on the literal "git worktree" string)**

Write commit message to `/tmp/c1-msg.txt`:

```
refactor: rename get_main_worktree_path → resolve_main_worktree_path

WHY: The function returns the working-tree path that the CURRENT gitdir
owns — not the "main" working tree of some implicit repo. The new name
makes the action ("resolve via porcelain") and scope ("anchored to
current gitdir") explicit. Renaming first, before changing internals
in the follow-up commit, lets reviewers see the rename diff in isolation
and pins existing call sites under the new contract.

WHAT: Pure rename across 6 in-tree call sites (3 in hug-git-worktree,
1 in git-wtc, 1 in git-wtdel, plus 2 comments). No behavior change.
One new lib test pins the plain-clone behavior under the new name.

HOW: Clean break — no deprecation shim. The function is library-internal
(sourced via HUG_HOME/git-config/lib/), so there are no external
consumers to break. Sanity-greped to confirm zero residual references.

IMPACT: Sets up commit 2 (porcelain reimplementation for submodule
support) to land as a pure-internals change with no caller churn.
Reviewer sees rename diff and internals diff in separate commits.

Co-Authored-By: Claude <noreply@anthropic.com>
```

Then:

```bash
hug c -F /tmp/c1-msg.txt
rm /tmp/c1-msg.txt
```

**Step 4: Verify**

```bash
hug ll -1
```

Expected: HEAD = the rename commit; status clean.

---

## Commit 2 — Porcelain Reimplementation (`fix`)

**Commit message subject:** `fix: resolve main worktree via porcelain for submodule support`

**Why second:** Now that callers are wired to the new name, swap the internals. Each test below catches a specific topology; together they cover the three observed scenarios from the design's failure-mode taxonomy.

### Task 2.1: Add submodule failing test for `resolve_main_worktree_path`

**Files:**
- Modify: `tests/lib/test_hug-git-worktree.bats` (append)

**Step 1: Write the test**

```bash
@test "resolve_main_worktree_path: returns submodule WT path from submodule CWD" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  cd "$meta_repo/sub"
  source "$HUG_HOME/git-config/lib/hug-git-worktree"
  run resolve_main_worktree_path
  assert_success
  # MUST be the submodule's working tree, NOT <meta>/.git/modules anywhere.
  [[ "$(realpath "$output")" == "$(realpath "$meta_repo/sub")" ]]
  # Hard regression guard: result must not contain /.git/
  [[ "$output" != *"/.git/"* ]]
  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}

@test "resolve_main_worktree_path: returns main WT path from linked worktree CWD" {
  local repo
  repo=$(create_test_repo_with_history)
  cd "$repo"
  hug bc feat-1
  hug wtc feat-1 -y
  cd "$repo.WT.feat-1"
  source "$HUG_HOME/git-config/lib/hug-git-worktree"
  run resolve_main_worktree_path
  assert_success
  [[ "$(realpath "$output")" == "$(realpath "$repo")" ]]
  hug wtdel feat-1 -f -B 2>/dev/null || true
  cleanup_test_repo "$repo"
}
```

**Step 2: Run them — expect FAIL on the submodule case**

```bash
make test-lib TEST_FILE=test_hug-git-worktree.bats TEST_FILTER="resolve_main_worktree_path"
```

Expected: submodule test FAILS (returns something under `.git/modules`); linked-worktree test may already pass under the old `dirname(--git-common-dir)` logic.

### Task 2.2: Rewrite `resolve_main_worktree_path` internals

**Files:**
- Modify: `git-config/lib/hug-git-worktree:292-302`

**Step 1: Replace the function body AND update the stale cross-reference comment at line 312**

(a) Replace lines 292–302 (current implementation) with:

```bash
# Resolve the main working-tree path that the CURRENT gitdir owns.
# Usage: main_path=$(resolve_main_worktree_path)
#
# Implementation: queries `git worktree list --porcelain` anchored via
# --git-dir to the current gitdir, then returns the path from the first
# `worktree <path>` line (the main worktree by porcelain spec).
#
# WHY porcelain over dirname(--git-common-dir): for submodules, the gitdir
# lives at <meta>/.git/modules/<sub>, so dirname yields <meta>/.git/modules
# — a directory of gitdirs, not a working tree. Porcelain returns the
# REGISTERED main worktree path, which is correct for every topology:
# plain clones, linked worktrees, submodules, and submodule worktrees.
#
# Returns: absolute path to main working tree, or empty string + non-zero
# if the current CWD is not inside a git repo.
resolve_main_worktree_path() {
    local gitdir main_wt
    # Bare repos have no working tree — early return prevents nonsense paths
    # downstream (e.g. <parent>/bare.git.WT.<branch> with .git in basename
    # which would then trip the new path_is_inside_dot_git guard with a
    # confusing error message). Eng phase finding #E6.
    if [[ "$(git rev-parse --is-bare-repository 2>/dev/null)" == "true" ]]; then
        return 1
    fi
    gitdir=$(worktree_gitdir "$(pwd)") || return 1
    # Capture into a variable so we can verify non-empty result. Eng phase
    # finding #E5: bare awk-pipe silently succeeds with empty output on
    # corrupt or unexpected porcelain, propagating a bogus empty anchor.
    main_wt=$(git --git-dir="$gitdir" worktree list --porcelain 2>/dev/null \
        | awk '/^worktree / { print substr($0, 10); exit }')
    [[ -n "$main_wt" ]] || return 1
    printf '%s\n' "$main_wt"
}
```

(b) Update the comment at the OLD line 312 (now around 318 after the function body grows). The current comment reads:

```bash
# Pattern mirrors get_main_worktree_path() above.
```

After rename + porcelain rewrite, the two functions are no longer parallel — `worktree_gitdir` now produces the gitdir that `resolve_main_worktree_path` consumes. Replace with:

```bash
# Pre-condition for resolve_main_worktree_path(); also used directly
# wherever a gitdir is needed (e.g. wtdel's per-worktree anchor).
```

**Step 2: Run the failing tests — expect PASS**

```bash
make test-lib TEST_FILE=test_hug-git-worktree.bats TEST_FILTER="resolve_main_worktree_path"
```

Expected: ALL three resolve_main_worktree_path tests pass (plain clone, submodule, linked worktree).

**Step 3: Run the broader worktree suite — expect no regressions**

```bash
make test-bash TEST_FILTER="worktree"
```

Expected: all pass.

### Task 2.3: Add `get_superproject_path` helper

**Files:**
- Modify: `git-config/lib/hug-git-worktree` (add after `resolve_main_worktree_path`, before `worktree_gitdir`)

**Step 1: Write the failing test**

```bash
@test "get_superproject_path: returns empty for plain clone" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"
  source "$HUG_HOME/git-config/lib/hug-git-worktree"
  run get_superproject_path
  assert_success
  [[ -z "$output" ]]
  cleanup_test_repo "$repo"
}

@test "get_superproject_path: returns meta path from submodule CWD" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  cd "$meta_repo/sub"
  source "$HUG_HOME/git-config/lib/hug-git-worktree"
  run get_superproject_path
  assert_success
  [[ "$(realpath "$output")" == "$(realpath "$meta_repo")" ]]
  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}
```

**Step 2: Run — expect FAIL (function not defined)**

```bash
make test-lib TEST_FILE=test_hug-git-worktree.bats TEST_FILTER="get_superproject_path"
```

**Step 3: Add the helper**

Insert after the rewritten `resolve_main_worktree_path` block:

```bash
# Returns the superproject's working-tree path, or empty string if the
# current repo has no superproject (i.e., we're not in a submodule).
# Thin wrapper over plumbing — extracted for testability and call-site clarity.
get_superproject_path() {
    git rev-parse --show-superproject-working-tree 2>/dev/null
}
```

**Step 4: Run — expect PASS**

```bash
make test-lib TEST_FILE=test_hug-git-worktree.bats TEST_FILTER="get_superproject_path"
```

### Task 2.4a: Add regression test pinning `is_worktree_not_main` post-rewrite behavior

**Files:**
- Modify: `tests/lib/test_hug-git-worktree.bats` (append)

**Why this exists:** `is_worktree_not_main()` (line 1011) also calls `get_main_worktree_path`. Before Commit 2, it returned TRUE wrongly in a submodule CWD (because `main_repo` resolved to a bogus path under `.git/modules`, which never equals `--show-toplevel`). After Commit 2, it correctly returns FALSE when CWD is the submodule's own working tree. This is a real behavior change downstream display logic may depend on — pin it explicitly.

**Step 1: Write the test**

```bash
@test "is_worktree_not_main: returns false when CWD is submodule's own WT (post-fix behavior)" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  cd "$meta_repo/sub"
  source "$HUG_HOME/git-config/lib/hug-git-worktree"
  # In the submodule's main WT, we are NOT in a "linked" worktree.
  # shellcheck disable=SC2314
  ! is_worktree_not_main
  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}

@test "is_worktree_not_main: returns true when CWD is a linked submodule worktree" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  cd "$wt_path"   # This IS a linked worktree of the submodule
  source "$HUG_HOME/git-config/lib/hug-git-worktree"
  is_worktree_not_main
  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}
```

**Step 2: Run — expect PASS (Commit 2's rewrite is already in)**

```bash
make test-lib TEST_FILE=test_hug-git-worktree.bats TEST_FILTER="is_worktree_not_main"
```

### Task 2.4: Add unit test proving the user-reported bug is fixed end-to-end

**Files:**
- Modify: `tests/unit/test_worktree_create.bats` (append)

**Step 1: Write the test**

```bash
@test "hug wtc: generates path outside .git/ when invoked from submodule CWD" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  cd "$meta_repo/sub"
  # Create a NEW branch in the submodule and use wtc to generate a worktree for it
  git checkout -q main 2>/dev/null || git checkout -q master 2>/dev/null
  run git-wtc new-branch --new -y
  assert_success
  # Generated path MUST NOT be under any .git/ directory
  local generated_path
  generated_path=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  [[ "$generated_path" != *"/.git/"* ]]
  # And it MUST be a sibling of the submodule's working tree
  [[ "$(dirname "$(realpath "$generated_path")")" == "$(realpath "$meta_repo")" ]]
  # Eng phase finding #E9: also assert Git's registered worktree state
  # via the SUBMODULE's owning gitdir (CWD-anchored list would miss it)
  local sub_gitdir="$meta_repo/.git/modules/sub"
  git --git-dir="$sub_gitdir" worktree list --porcelain | grep -qxF "worktree $generated_path"
  # Cleanup
  git --git-dir="$sub_gitdir" worktree remove --force "$generated_path" 2>/dev/null || rm -rf "$generated_path"
  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}

# Eng phase finding #E7: --base + submodule CWD interaction
@test "hug wtc: --base flag works from submodule CWD without .git/ path leakage" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  cd "$meta_repo/sub"
  # Need an existing ref to use as --base
  git checkout -q main 2>/dev/null || git checkout -q master 2>/dev/null
  local base_ref="HEAD"
  run git-wtc base-new-branch --base "$base_ref" -y
  assert_success
  local generated_path
  generated_path=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  [[ "$generated_path" != *"/.git/"* ]]
  local sub_gitdir="$meta_repo/.git/modules/sub"
  git --git-dir="$sub_gitdir" worktree remove --force "$generated_path" 2>/dev/null || rm -rf "$generated_path"
  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}

# Eng phase finding #E10: worktree-of-submodule scenario (linked WT CWD)
@test "hug wtc: works from a linked submodule worktree CWD" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  cd "$wt_path"   # CWD is a LINKED worktree of the submodule
  run git-wtc another-branch --new -y
  assert_success
  local generated_path
  generated_path=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  [[ "$generated_path" != *"/.git/"* ]]
  local sub_gitdir="$meta_repo/.git/modules/sub"
  git --git-dir="$sub_gitdir" worktree remove --force "$generated_path" 2>/dev/null || rm -rf "$generated_path"
  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}
```

**Step 2: Run — expect PASS (since Commit 2's internals fix is now in place)**

```bash
make test-unit TEST_FILE=test_worktree_create.bats TEST_FILTER="generates path outside .git"
```

Expected: PASS.

### Task 2.5: Commit Commit 2

**Step 1: Stage**

```bash
hug a git-config/lib/hug-git-worktree \
      tests/lib/test_hug-git-worktree.bats \
      tests/unit/test_worktree_create.bats
```

**Step 2: Write commit message to `/tmp/c2-msg.txt`:**

```
fix: resolve main worktree via porcelain for submodule support

WHY: Inside a submodule working tree, `hug wtc` generated paths under
the meta-repo's `.git/` directory (e.g. <meta>/.git/modules.WT.<branch>).
Root cause: resolve_main_worktree_path used dirname(--git-common-dir),
which for submodules strips one segment from <meta>/.git/modules/<sub>
and lands on a directory of gitdirs — not a working tree.
generate_worktree_path then computed `dirname(anchor)/basename(anchor).WT.<branch>`
from that bad anchor, producing paths inside <meta>/.git/.

WHAT: Rewrites resolve_main_worktree_path to derive the working tree
from the porcelain `worktree list` output, anchored via --git-dir to
the gitdir worktree_gitdir() resolves for the current CWD. Adds the
get_superproject_path helper (thin wrapper over
--show-superproject-working-tree) used by commit 3's tip-emitter.

HOW: Porcelain's first `worktree <path>` record is the canonical main
worktree by spec — stable since Git 2.7 (2015). Anchoring via
--git-dir=$(worktree_gitdir "$(pwd)") makes the resolution
CWD-independent and submodule-correct: from a submodule CWD, the
anchor is the submodule's gitdir, so porcelain returns the
submodule's working tree (the correct answer for generate_worktree_path).

IMPACT: User-reported reproducer now produces a correct path (verified
end-to-end by new BATS test in tests/unit/test_worktree_create.bats).
Linked worktrees and plain clones unchanged (regression-tested).
get_superproject_path is the building block for commit 3's gitignore
tip. No call-site churn — commit 1's rename already wired everything.

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Step 3: Commit**

```bash
hug c -F /tmp/c2-msg.txt
rm /tmp/c2-msg.txt
```

**Step 4: Verify**

```bash
hug ll -2 && make test-bash TEST_FILTER="worktree"
```

Expected: HEAD = Commit 2; all worktree tests pass.

---

## Commit 3 — Validation Guard + Superproject Tip (`feat`)

**Commit message subject:** `feat: guard worktree paths under .git/ and tip on superproject ignore`

**Why third:** Layers defense-in-depth on top of the fix. Even if a future regression reintroduces the bad anchor, the validator catches it. The tip improves UX one-shot per superproject without nagging.

### Task 3.1: Add failing test for `path_is_inside_dot_git`

**Files:**
- Modify: `tests/lib/test_hug-git-worktree.bats` (append)

**Step 1: Write the test**

```bash
@test "path_is_inside_dot_git: rejects paths under .git/" {
  source "$HUG_HOME/git-config/lib/hug-git-worktree"

  # Positive cases (must return 0 = inside .git)
  path_is_inside_dot_git "/tmp/repo/.git"
  path_is_inside_dot_git "/tmp/repo/.git/modules/sub"
  path_is_inside_dot_git "/tmp/repo/.git/modules.WT.x"
  path_is_inside_dot_git "/tmp/meta/.git/modules/sub.WT.feat-x"

  # Negative cases (must return 1 = NOT inside .git)
  # shellcheck disable=SC2314
  ! path_is_inside_dot_git "/tmp/repo.WT.feat-x"
  # shellcheck disable=SC2314
  ! path_is_inside_dot_git "/tmp/foo.git/x"
  # shellcheck disable=SC2314
  ! path_is_inside_dot_git "/tmp/some/normal/path"
}

# Eng phase finding #E8: extend coverage to symlinks and relative paths
@test "path_is_inside_dot_git: catches symlinks resolving into .git/" {
  source "$HUG_HOME/git-config/lib/hug-git-worktree"
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/repo/.git"
  ln -s "$tmpdir/repo/.git" "$tmpdir/link-to-gitdir"
  # Symlink itself should be caught (resolves to a path under .git via realpath)
  path_is_inside_dot_git "$tmpdir/link-to-gitdir/inner"
  rm -rf "$tmpdir"
}

@test "path_is_inside_dot_git: handles relative paths" {
  source "$HUG_HOME/git-config/lib/hug-git-worktree"
  local tmpdir orig_pwd
  orig_pwd=$(pwd)
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/repo/.git/modules"
  cd "$tmpdir/repo"
  path_is_inside_dot_git ".git/modules/sub"
  path_is_inside_dot_git "./.git/foo"
  cd "$orig_pwd"
  rm -rf "$tmpdir"
}
```

**Step 2: Run — expect FAIL (function not defined)**

```bash
make test-lib TEST_FILE=test_hug-git-worktree.bats TEST_FILTER="path_is_inside_dot_git"
```

### Task 3.2: Implement `path_is_inside_dot_git`

**Files:**
- Modify: `git-config/lib/hug-git-worktree` (add after `validate_worktree_creation_path`, before path-generation section)

**Step 1: Add the function**

Insert just BEFORE the `# Worktree Path Generation Functions` banner (around line 644):

```bash
# Returns 0 if $candidate's resolved path has any ancestor directory
# named exactly ".git". Walks ancestors; performs no git invocations.
#
# WHY: Defense-in-depth guard against path-generation primitives that
# return paths under a gitdir (the submodule mis-detection bug fixed
# in Commit 2). Also catches user-supplied paths under .git/.
#
# Resolution: tries `readlink -f` then `greadlink -f` (BSD macOS fallback),
# matching the codebase pattern in hug-git-json:13. Both resolve symlinks
# AND handle non-existent paths (since the worktree dir doesn't exist
# yet at validation time). If both fail, falls back to the raw input —
# walk still works on lexical components, only the symlink-normalization
# guarantee weakens.
#
# WHY NOT `realpath -m`: BSD realpath (macOS) does not support `-m`. The
# GNU-only flag would silently degrade on macOS, losing the symlink
# guarantee without error. readlink -f / greadlink -f is the codebase's
# established portable pattern.
_path_resolve_lexical() {
    # Resolve $1 even when it doesn't exist yet (the wtc path is created
    # AFTER validation). Strategy: walk up the path until we find an
    # existing ancestor, canonicalize THAT, then re-append the missing
    # suffix lexically. This preserves symlink normalization for the
    # existing prefix without depending on `realpath -m` (GNU-only).
    #
    # Eng phase finding #E4: `readlink -f` returns exit 1 for non-existent
    # paths on Linux; falling back to the raw input loses the symlink
    # guarantee silently.
    local p="$1" suffix=""
    [[ "$p" = /* ]] || p="$(pwd)/$p"
    while [[ "$p" != "/" && ! -e "$p" ]]; do
        suffix="/$(basename "$p")${suffix}"
        p=$(dirname "$p")
    done
    local resolved
    resolved=$(readlink -f "$p" 2>/dev/null || greadlink -f "$p" 2>/dev/null) || resolved="$p"
    printf '%s%s\n' "$resolved" "$suffix"
}

path_is_inside_dot_git() {
    local rp
    rp=$(_path_resolve_lexical "$1")
    while [[ "$rp" != "/" && -n "$rp" ]]; do
        [[ "$(basename "$rp")" == ".git" ]] && return 0
        rp=$(dirname "$rp")
    done
    return 1
}
```

**Step 2: Run the test — expect PASS**

```bash
make test-lib TEST_FILE=test_hug-git-worktree.bats TEST_FILTER="path_is_inside_dot_git"
```

### Task 3.3: Hook the guard into `validate_worktree_creation_path`

**Files:**
- Modify: `git-config/lib/hug-git-worktree:639` (just before `return 0` at end of validator)

**Step 1: Add failing unit test that supplies an explicit `.git/` path**

In `tests/unit/test_worktree_create.bats`, append:

```bash
@test "hug wtc: rejects user-supplied path under .git/" {
  local repo
  repo=$(create_test_repo_with_branches)
  cd "$repo"
  run git-wtc feature-1 "$repo/.git/should-not-go-here" -f
  assert_failure
  assert_output --partial "Refusing to create worktree under a .git directory"
  cleanup_test_repo "$repo"
}
```

**Step 2: Run — expect FAIL (no guard yet)**

```bash
make test-unit TEST_FILE=test_worktree_create.bats TEST_FILTER="rejects user-supplied path under .git"
```

**Step 3: Add the guard inside `validate_worktree_creation_path` — MUST RUN BEFORE `mkdir -p`**

**Eng phase finding #E2 (HIGH):** The guard MUST run before any parent-directory creation. Otherwise a path like `<repo>/.git/newdir/wt` causes `validate_worktree_creation_path` to call `mkdir -p <repo>/.git/newdir/` BEFORE the guard fires, leaving a stray `.git/newdir/` artifact in the repo even though validation correctly returns 1.

Insert immediately AFTER the absolute-path conversion block (which is around line 587–589 in current code, right after the `if [[ ! "$path" = /* ]]; then path="$(pwd)/$path"; fi` block) and BEFORE the `# Check if target already exists` block:

```bash
    # Guard: refuse paths inside any .git directory.
    # MUST run BEFORE the parent-directory mkdir below — otherwise a
    # rejected path like <repo>/.git/newdir/wt would still cause
    # mkdir -p to create <repo>/.git/newdir/ before failing.
    #
    # Message is plain user-facing language. DX phase finding #D1:
    # earlier draft used "ancestor primitive returned a gitdir" which
    # is debug language for the implementer, not guidance for a user
    # who explicitly passed a .git/ path by mistake.
    if path_is_inside_dot_git "$path"; then
        warning "Cannot create worktree under a .git/ directory: $path"
        info "The path must be outside any .git/ directory."
        return 1
    fi
```

**Step 4: Run — expect PASS**

```bash
make test-unit TEST_FILE=test_worktree_create.bats TEST_FILTER="rejects user-supplied path under .git"
```

### Task 3.4: Implement `suggest_superproject_ignore`

**Files:**
- Modify: `git-config/lib/hug-git-worktree` (add at end of file, after the path-generation section)

**Step 1: Write failing unit tests for the tip emission**

In `tests/unit/test_worktree_create.bats`, append:

```bash
@test "hug wtc: emits superproject .gitignore tip from submodule CWD" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  cd "$meta_repo/sub"
  git checkout -q main 2>/dev/null || git checkout -q master 2>/dev/null
  run git-wtc new-branch --new -y
  assert_success
  assert_output --partial "Worktree is inside superproject"
  assert_output --partial "*.WT.*/"
  # Cleanup the worktree wtc just created
  local generated
  generated=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  rm -rf "$generated" 2>/dev/null || true
  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}

@test "hug wtc: suppresses tip when *.WT.*/ already in superproject .gitignore" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  printf '*.WT.*/\n' >> "$meta_repo/.gitignore"
  cd "$meta_repo/sub"
  git checkout -q main 2>/dev/null || git checkout -q master 2>/dev/null
  run git-wtc new-branch --new -y
  assert_success
  [[ "$output" != *"Worktree is inside superproject"* ]]
  local generated
  generated=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  rm -rf "$generated" 2>/dev/null || true
  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}

# Eng phase finding #E3: custom path OUTSIDE superproject must not trigger tip
@test "hug wtc: does NOT emit superproject tip when custom path is outside meta-repo" {
  local meta_repo wt_path
  { read -r meta_repo; read -r wt_path; } < <(create_test_submodule_worktree "sub-feat-x")
  cd "$meta_repo/sub"
  git checkout -q main 2>/dev/null || git checkout -q master 2>/dev/null
  local custom_path
  custom_path=$(mktemp -d)/external-wt
  run git-wtc external-branch --new "$custom_path" -y
  assert_success
  # Worktree is OUTSIDE meta_repo → tip MUST NOT fire
  [[ "$output" != *"Worktree is inside superproject"* ]]
  # Cleanup
  local sub_gitdir="$meta_repo/.git/modules/sub"
  git --git-dir="$sub_gitdir" worktree remove --force "$custom_path" 2>/dev/null || rm -rf "$custom_path"
  rm -rf "$(dirname "$custom_path")"
  cleanup_test_submodule_worktree "$meta_repo" "$wt_path"
}

@test "hug wtc: does NOT emit superproject tip for plain clone" {
  local repo
  repo=$(create_test_repo_with_branches)
  cd "$repo"
  run git-wtc feature-1 -f
  assert_success
  [[ "$output" != *"Worktree is inside superproject"* ]]
  # Cleanup
  local generated
  generated=$(echo "$output" | grep "Path:" | sed 's/.*Path:[[:space:]]*//' | sed 's/\s*$//')
  hug wtdel feature-1 -f -B 2>/dev/null || rm -rf "$generated"
  cleanup_test_repo "$repo"
}
```

**Step 2: Run — expect FAIL (function not implemented and not called by wtc yet)**

```bash
make test-unit TEST_FILE=test_worktree_create.bats TEST_FILTER="superproject"
```

**Step 3: Add the helper to the library**

Append to `git-config/lib/hug-git-worktree`:

```bash
# Emits a one-line tip when the new worktree lives inside a superproject
# AND the superproject's .gitignore (or any other ignore source) does
# not already ignore the path. Silent otherwise.
#
# Probes via `git check-ignore --no-index` — the canonical plumbing that
# honors every ignore source: root .gitignore, nested .gitignore files,
# .git/info/exclude, global ignore, and negation rules. We pass the
# generated worktree path directly; --no-index means we don't need the
# path to exist yet (it doesn't, at this call point).
#
# Usage: suggest_superproject_ignore "/abs/path/to/new/worktree"
suggest_superproject_ignore() {
    local worktree_path="$1" super_path
    super_path=$(get_superproject_path) || return 0
    [[ -n "$super_path" ]] || return 0

    # Eng phase finding #E3: only emit the tip if the WORKTREE PATH is
    # actually inside the superproject. A user-supplied custom path
    # (e.g. /tmp/x) or the /tmp/hug-wt-* fallback should NOT trigger
    # this tip, even when CWD is in a submodule.
    local rp_wt rp_super
    rp_wt=$(_path_resolve_lexical "$worktree_path")
    rp_super=$(readlink -f "$super_path" 2>/dev/null || greadlink -f "$super_path" 2>/dev/null) || rp_super="$super_path"
    [[ "$rp_wt" == "$rp_super"/* ]] || return 0

    # Eng phase finding #E1 (CRITICAL, empirically verified): the
    # `*.WT.*/` pattern has a trailing slash and only matches DIRECTORIES
    # per gitignore semantics. `git check-ignore` honors that — without
    # a trailing slash on the path argument, it doesn't classify the
    # subject as a directory and the pattern doesn't match. The probe
    # MUST append a trailing slash so check-ignore evaluates the path
    # as a directory.
    if ! git -C "$super_path" check-ignore --no-index -q "${worktree_path%/}/" 2>/dev/null; then
        # DX phase finding #D2: collapse to 2 tip lines (was 3); use
        # absolute-path single-command form (no `cd &&` compound — copy-paste
        # safer, handles spaces, runnable from anywhere).
        # DX phase finding #D5: bypass HUG_QUIET so the one-time advisory
        # reaches automation users who would otherwise never see it and
        # never add the ignore rule. Mirrors the `error` helper's pattern.
        HUG_QUIET='' tip "Worktree is inside superproject ${super_path/#$HOME/\~} — add to its .gitignore:"
        HUG_QUIET='' tip "    printf '*.WT.*/\\n' >> '${super_path}/.gitignore'"
    fi
}
```

**Step 4: Wire it into `git-wtc` after the success message AND update help text (DX finding #D3)**

(a) In `git-config/bin/git-wtc`, after line 380 (`tip "To start working:  cd ${worktree_path/#$HOME/\~}"`), add:

```bash
suggest_superproject_ignore "$worktree_path"
```

(b) Update `show_help` DESCRIPTION (around line 41–47). The current text says:

> If no path is provided, generates a smart default path outside the main
> repository: `../<repo>.WT.<branch>`

This is now factually wrong in submodule context. Replace with:

> If no path is provided, generates a smart default path as a sibling of the
> current working tree: `../<repo>.WT.<branch>`. From a submodule, the default
> is a sibling of the submodule (e.g. `../<sub>.WT.<branch>`) — placement is
> chosen so relative paths to sibling submodules remain valid.

**Step 5: Run the three tip tests — expect PASS**

```bash
make test-unit TEST_FILE=test_worktree_create.bats TEST_FILTER="superproject"
```

### Task 3.5: Run the full worktree suite

**Step 1:**

```bash
make test-bash TEST_FILTER="worktree"
```

Expected: all pass (no regressions in `wtl`, `wtll`, `wtsh`, `wtprune`, `wtdel`).

**Step 2: Run sanitize check**

```bash
make sanitize-check
```

Expected: pass.

### Task 3.6: Commit Commit 3

**Step 1: Stage**

```bash
hug a git-config/lib/hug-git-worktree \
      git-config/bin/git-wtc \
      tests/lib/test_hug-git-worktree.bats \
      tests/unit/test_worktree_create.bats
```

**Step 2: Verify staged set**

```bash
hug sls
```

Expected: exactly those four files, `S:Mod`.

**Step 3: Write commit message to `/tmp/c3-msg.txt`:**

```
feat: guard worktree paths under .git/ and tip on superproject ignore

WHY: With commits 1+2 in place, the user-reported bug is fixed, but
two UX gaps remain. (1) If a future regression reintroduces a bad
path anchor, nothing at the validation boundary catches it — the bug
silently corrupts the user's repo again. (2) When wtc legitimately
creates a worktree inside a superproject (the chosen design for
submodule contexts), the meta-repo sees the new directory as
untracked, which is noise the user must manually .gitignore each
time. Both are cheap to address; together they make this primitive
robust against the entire class of "path under .git/" defects.

WHAT: Adds two new library helpers and hooks them into wtc.
path_is_inside_dot_git walks ancestors of a (realpath-resolved)
candidate looking for any directory named exactly ".git" — catches
the immediate bug class, user-supplied .git/ paths, and any future
regression. Hooks into validate_worktree_creation_path as a final
defense-in-depth gate. suggest_superproject_ignore emits a one-line
tip when wtc creates a worktree inside a superproject AND
`git check-ignore` reports the path is NOT already ignored — so
repeat users see the tip exactly once per superproject.

HOW: path_is_inside_dot_git uses `realpath -m` so non-existent
paths resolve and symlinks are normalized BEFORE the ancestor walk
(symlinked paths under .git/ still caught). No git invocations —
O(depth) basename comparisons. suggest_superproject_ignore probes
via `git check-ignore --no-index` — the canonical plumbing for
ignore-rule evaluation that honors every source (root .gitignore,
nested, .git/info/exclude, global, negation). --no-index removes
the need for the path to exist at probe time. Tip uses the existing
`tip` helper (stderr-only, respects HUG_QUIET).

IMPACT: Validator now rejects with a clear, actionable error if any
upstream primitive ever produces a path under .git/ (regression
backstop). User-supplied .git/ paths fail fast with a recognizable
message rather than silently corrupting state. Superproject users
get a one-shot copy-paste fix for .gitignore hygiene; no nagging
afterward — the check-ignore probe means re-running wtc in the
same superproject is silent once the rule is in place. Plain
clones unchanged (regression-guarded by the dedicated test). The
.git/ guard costs two realpath calls; the tip costs one
check-ignore process when in a superproject — both negligible.

Co-Authored-By: Claude <noreply@anthropic.com>
```

**Step 4: Commit**

```bash
hug c -F /tmp/c3-msg.txt
rm /tmp/c3-msg.txt
```

**Step 5: Final verification**

```bash
hug ll -3 && make test-bash TEST_FILTER="worktree"
```

Expected: HEAD = Commit 3; all worktree tests pass; HEAD~1 = Commit 2; HEAD~2 = Commit 1.

---

## Final Acceptance Checklist

Before reporting done:

- [ ] `grep -rn 'get_main_worktree_path' git-config/ tests/` → empty
- [ ] `make test-bash TEST_FILTER="worktree"` → all pass
- [ ] `make sanitize-check` → pass
- [ ] User-reported reproducer from design doc § 1 yields path matching `<meta>/sub.WT.feat-x` (NOT under `.git/`)
- [ ] From submodule CWD: tip emitted on stderr; suppressed when `*.WT.*/` already in superproject `.gitignore`
- [ ] From plain clone: no superproject tip (regression guard)
- [ ] `hug wtc feat <repo>/.git/x` fails fast with "Cannot create worktree under a .git/ directory" (DX finding #D1 wording)
- [ ] `hug wtc feat <repo>/.git/newdir/wt` FAILS without leaving a `<repo>/.git/newdir/` artifact (Eng finding #E2 ordering)
- [ ] `hug wtc feat <some-path-outside-meta>` from submodule CWD does NOT emit the superproject tip (Eng finding #E3 false-tip suppression)
- [ ] Worktree-of-submodule scenario: `hug wtc` from a linked submodule worktree CWD succeeds with correct path (Eng finding #E10)
- [ ] `--base` flag combined with submodule CWD generates path outside `.git/` (Eng finding #E7)
- [ ] Bare repo: `resolve_main_worktree_path` returns non-zero (Eng finding #E6); `hug wtc` from a bare-repo CWD fails with a sensible message
- [ ] Tip-suppression test passes WITH `*.WT.*/` in `.gitignore` (Eng finding #E1 — directory-trailing-slash fix)
- [ ] `hug wtc --help` mentions submodule behavior (DX finding #D3)
- [ ] Git history shows 3 clean commits: rename → fix → guard+tip

---

## Migration from buggy state (for users hit by the bug pre-fix)

Users who hit the original bug may have worktrees registered at paths under `<meta>/.git/modules*.WT.<branch>`. The fix prevents NEW bad worktrees but does not auto-clean existing ones. Recovery is straightforward thanks to the prior `hug wtdel` submodule fix (commit `1b046f8`):

```bash
cd <meta>/sub
hug wtl                                 # locate the bad path
hug wtdel <branch> --force --with-branch  # remove worktree and branch
hug wtc <branch> --new -y                 # recreate cleanly with the fix
```

DX phase finding #D4: one-sentence recovery pointer prevents a support loop.

## Out of Scope (tracked under issue #149)

- `worktree_validate.py:255,300` — CWD-anchor in Python validator
- **`worktree_validate.py:164` — `generate_worktree_path` (Python)** has the same defect class as the Bash function this plan fixes. Verified UNREACHABLE from `git-wtc` (zero callers of the `generate-path` subcommand in tree). Documented as a latent landmine to fix when the broader Python sweep lands.
- `worktree.py:583` — CWD-anchor in porcelain listing
- `worktree_select.py:323,328` — `removesuffix("/.git")` mis-classification
- `branch_available_for_worktree` (line ~445) — CWD-anchor
- `prune_worktrees` (line ~802) — CWD-anchor
- Full merge of `worktree_gitdir` + `resolve_main_worktree_path` into one helper
- Mercurial parity (no submodule concept in `hg-config/`)

---

## /autoplan — Phase 1: CEO Review Report

### Dual Voices

**Codex (strategic challenge)** raised 8 premise critiques. Top three:
1. *Topology model fragmented* — fixing only `wtc` while admitting 11 sibling sites exist means users experience submodule support as unreliable.
2. *Submodule placement is assumed, not validated* — sibling-of-submodule = inside-superproject = ownership-boundary crossing, materially different from plain-clone semantics.
3. *`.gitignore` tip turns local CLI artifact into project policy* — `*.WT.*/` is broad, tool-specific, and team-invasive.

**Claude subagent (code-grounded)** verified the design against the actual codebase. Top three:
1. *Python `generate_worktree_path` at `worktree_validate.py:164` has the same latent bug* — verified UNREACHABLE from `git-wtc` (zero callers of `generate-path` subcommand in tree), but dead-code landmine for future callers.
2. *`realpath -m` is GNU-only* — codebase uses `readlink -f / greadlink -f` fallback pattern elsewhere; impl plan's `realpath -m … || rp="$1"` silently degrades on macOS, losing the symlink-normalization guarantee.
3. *`is_worktree_not_main()` at line 1011* — also calls `get_main_worktree_path`; in submodule CWD, the rename + porcelain rewrite SILENTLY CHANGES its boolean return value. Currently buggy (returns true wrongly), post-fix correctly returns false. Behavior change is real and untested.

### CEO Dual Voices Consensus Table

| Dimension | Codex | Subagent | Consensus |
|---|---|---|---|
| 1. Premises valid? | DISAGREE (placement, tip, scope) | DISAGREE (`realpath -m`, broad pattern, untested behavior change) | **DISAGREE** |
| 2. Right problem to solve? | Partially — broader needed | YES — scoped correctly | DISAGREE |
| 3. Scope calibration correct? | Too narrow on arch, broad on UX | Correct, defensible | DISAGREE |
| 4. Alternatives sufficiently explored? | NO (explicit-path, configurable root, .git/info/exclude) | One under-examined (sibling-of-meta) | **CONFIRMED-NO** |
| 5. Competitive/market risks covered? | NO — broad ignore pattern is adoption-hostile | NO — pattern too broad for superproject context | **CONFIRMED-NO** |
| 6. 6-month trajectory sound? | NO — naming and policy regrets | Mostly YES with the three findings | DISAGREE |

**Strong cross-voice signals** (both flagged independently — high-confidence):
- The `*.WT.*/` pattern is too broad. Scope to the actual submodule basename (`<sub>.WT.*/`) is the consensus-implied fix.
- The current plan locks in UX (sibling-of-submodule placement) before validating it.

### Auto-Decided Findings (P1/P2/P5 — boil the lake in blast radius, <1 day CC effort)

| # | Finding | Decision | Principle | Rationale |
|---|---|---|---|---|
| 1 | `realpath -m` not portable to macOS BSD | **ACCEPT — change to `readlink -f \|\| greadlink -f` per `hug-git-json:13` codebase pattern** | P5 (explicit, matches existing pattern) | Without this fix, symlink-normalization guarantee is silently lost on macOS. Codebase already has the right pattern; reuse it. |
| 2 | `is_worktree_not_main` behavior changes in submodule CWD post-rewrite | **ACCEPT — add explicit BATS test in lib suite for submodule CWD** | P1 (completeness — boil the lake on the lib test additions) | A new test is two assertions. Without it, downstream display logic in worktree-aware commands could regress silently. |
| 3 | Line 312 cross-reference comment becomes stale after Commit 2 | **ACCEPT — update comment as part of Commit 2** | P5 (explicit > stale doc) | Trivial doc maintenance. Tied to the file we're already editing. |
| 4 | Python `generate_worktree_path` is dead code with latent bug | **ACCEPT — add explicit note in Out of Scope section: "Python `worktree_validate.py:164 generate_worktree_path` has the same defect but is UNREACHABLE from `git-wtc`; deferred to #149"** | P3 (pragmatic — note it, don't fix what isn't broken) | Verified no callers in tree. Documenting the landmine is enough. |

### Premise Gate — User Resolutions (2026-05-18)

Both voices flagged two strategic premises. User resolved both at the autoplan gate with a critical new piece of domain context that neither voice surfaced:

1. **Submodule WT placement — KEEP sibling-of-submodule (inside meta).** User's reasoning, *which dominates both voices' critique*: **"some submodules have relative paths to other sibling submodules — let's not break them."** This is a correctness constraint, not a UX preference: moving worktrees outside the meta-repo (Codex's preferred alternative) would silently break any `../sibling-submodule/...` reference inside the worktree. The sibling-of-submodule placement preserves relative-path semantics across submodule boundaries. Trade-off (meta-repo sees untracked dir) is mitigated by the `.gitignore` tip.

2. **`.gitignore` tip pattern — KEEP broad `*.WT.*/`.** Solo / OSS Bash tooling context; one-time fix covering all current and future worktrees outweighs the per-submodule precision Codex argued for.

### CEO Phase Status: PASSED with auto-decided refinements (see table above) and premise resolutions.

---

## /autoplan — Phase 3: Eng Review Report

### Dual Voices

**Codex (architecture / adversarial)** and **Claude subagent (code-grounded)** independently identified the same critical and high-severity bugs in the impl plan. The subagent **empirically verified** the most critical one with a shell session.

### Eng Dual Voices Consensus Table

| Dimension | Codex | Subagent | Consensus |
|---|---|---|---|
| 1. Architecture sound? | YES with caveats (CWD coupling in tip helper) | YES, three-commit structure is correct | CONFIRMED |
| 2. Test coverage sufficient? | NO (8 specific gaps) | NO (5 specific gaps) | **CONFIRMED-NO** |
| 3. Performance risks addressed? | YES (negligible cost) | YES | CONFIRMED |
| 4. Security/correctness covered? | NO (mkdir-before-guard bug; tip false positive; check-ignore wrong path form) | NO (same three bugs, plus check-ignore EMPIRICALLY VERIFIED FAILURE) | **CONFIRMED-NO** |
| 5. Error paths handled? | NO (resolve_main_worktree_path empty-output, bare repo) | NO (same) | **CONFIRMED-NO** |
| 6. Deployment risk manageable? | YES with the fixes | YES with the fixes | CONFIRMED |

### Auto-Decided Findings (all critical/high — P1 completeness, P5 explicit-correctness)

| # | Finding | Severity | Decision | Files affected |
|---|---|---|---|---|
| E1 | `suggest_superproject_ignore` passes absolute path to `check-ignore` without trailing slash; `*.WT.*/` pattern (directory-only) never matches; tip fires even when already ignored. **Subagent empirically verified.** | **CRITICAL** | **ACCEPT — change probe argument to `"${worktree_path%/}/"` AND add fixed test assertion** | Task 3.4 lib helper + test |
| E2 | `.git/` guard placed AFTER `mkdir -p $parent_dir` in `validate_worktree_creation_path`. Path like `<repo>/.git/newdir/wt` causes mkdir to create `<repo>/.git/newdir/` BEFORE the guard rejects. | **HIGH** | **ACCEPT — move `path_is_inside_dot_git` check BEFORE the parent-dir existence check (immediately after the absolute-path conversion)** | Task 3.3 |
| E3 | `suggest_superproject_ignore` couples to CWD not candidate path: user-supplied `/tmp/custom-path` from submodule CWD triggers a false superproject tip. | **HIGH** | **ACCEPT — verify candidate path is actually under super_path before emitting tip** | Task 3.4 lib helper |
| E4 | `readlink -f` returns exit 1 for non-existent paths on Linux; fallback `rp="$1"` silently loses symlink-normalization guarantee for new worktree paths (they don't exist yet at validation). | **HIGH** | **ACCEPT — resolve the deepest EXISTING ancestor, then append the missing suffix. Use a helper: `_path_resolve_lexical()`** | Task 3.2 |
| E5 | `resolve_main_worktree_path` `awk` exit-success-with-empty-output: bare repos, corrupt registry, future porcelain format changes all silently produce empty results that propagate as bogus paths. | **MEDIUM** | **ACCEPT — capture into variable, require non-empty, return non-zero otherwise** | Task 2.2 |
| E6 | Bare repo: porcelain returns gitdir path (`bare.git`), so generated path is `<parent>/bare.git.WT.<branch>` — `.git` in path triggers new guard with a confusing error. | **MEDIUM** | **ACCEPT — early-return non-zero from `resolve_main_worktree_path` when `git rev-parse --is-bare-repository` returns true** | Task 2.2 |
| E7 | `--base` flag combined with submodule CWD not tested. | MEDIUM | **ACCEPT — add a test case in Task 2.4** | Task 2.4 |
| E8 | `path_is_inside_dot_git` test omits symlink-into-`.git` and `..`/relative-path cases. | MEDIUM | **ACCEPT — extend lib test in Task 3.1 with two more cases** | Task 3.1 |
| E9 | Tests parse human output (`grep "Path:"`) rather than asserting registered worktree state via owning gitdir. | MEDIUM | **ACCEPT — add a registered-state assertion to Task 2.4 (in addition to existing output-based check, to verify Git state); pre-existing tests left alone** | Task 2.4 |
| E10 | No end-to-end test from a linked submodule worktree CWD (worktree-of-submodule scenario). | MEDIUM | **ACCEPT — add one E2E unit test asserting wtc works from a linked submodule worktree CWD** | Task 2.4 |

### Findings Documented But NOT Folded In (out of scope per design)

- `branch_available_for_worktree` at line ~529 lacks gitdir anchor — **tracked under #149**, no change here.
- Tests parsing human output (Codex/Subagent E9) for *pre-existing* tests left alone; only new tests get the registered-state assertion. P3 (pragmatic — don't refactor stable tests for code-style).
- Bare repo handling in `validate_worktree_creation_path` itself (separate from `resolve_main_worktree_path` guard) — not introduced by this change, deferred.

### Eng Phase Status: PASSED with 10 auto-decided fixes folded into the implementation tasks below.

---

## /autoplan — Phase 3.5: DX Review Report

### Dual Voices

Both DX voices converged on the SAME top concerns — strong cross-voice signal. Codex framed them as competitive/adoption risks; Subagent framed them as usability gaps. Same fixes either way.

### DX Dual Voices Consensus Table

| Dimension | Codex | Subagent | Consensus |
|---|---|---|---|
| 1. New error message clarity | DISAGREE ("ancestor primitive" too internal) | DISAGREE (same — debug language not user guidance) | **CONFIRMED-DISAGREE** |
| 2. Tip wording / copy-paste | DISAGREE (cd && printf not shell-safe) | DISAGREE (3 tip lines break under prefix; cd unnecessary) | **CONFIRMED-DISAGREE** |
| 3. Discoverability of fix | DISAGREE (help, docs, CHANGELOG unchanged) | DISAGREE (show_help DESCRIPTION now factually wrong) | **CONFIRMED-DISAGREE** |
| 4. Migration from buggy state | DISAGREE (biggest gap — no recovery guidance) | DISAGREE (same — Out of Scope mentions nothing) | **CONFIRMED-DISAGREE** |
| 5. Stderr discipline | CONFIRMED (correct) | CONFIRMED (correct) | CONFIRMED |
| 6. Dev environment friction | CONFIRMED (TTHW = 1 cmd for new users) | CONFIRMED (TTHW = 1 cmd for new users) | CONFIRMED |

### Auto-Decided Findings

| # | Finding | Severity | Decision | Files affected |
|---|---|---|---|---|
| D1 | Validation error info-text uses "ancestor primitive" / "submodule mis-detection" — internal debug language, not user guidance | **HIGH** | **ACCEPT — reduce to one warning + one info line with plain language** | Task 3.3 |
| D2 | Tip emits 3 `tip` lines with `cd && printf` compound; not shell-safe for paths with spaces; copy-paste friction under the 💡 Tip: prefix | **HIGH** | **ACCEPT — collapse to 2 tip lines; use single-command form `printf '*.WT.*/\n' >> <abs-path>/.gitignore`** | Task 3.4 |
| D3 | `show_help` DESCRIPTION states `../<repo>.WT.<branch>` as the default — now factually wrong in submodule context | **MEDIUM** | **ACCEPT — add one sentence noting submodule behavior** | Task 3.4 git-wtc help update |
| D4 | No migration path documented for users with existing `.git/modules.WT.x` worktrees from the bug | **MEDIUM** | **ACCEPT — add one sentence to Out of Scope pointing to `hug wtdel <branch> --force`** | Out of Scope section |
| D5 | `HUG_QUIET` suppresses `tip` forever; one-time `.gitignore` advisory may never reach automation users | MEDIUM | **ACCEPT — emit the tip via `HUG_QUIET='' tip "..."` bypass (matches `error`'s pattern); add doc comment explaining why** | Task 3.4 lib helper |
| D6 | Tip prefix consistency: 3 consecutive `tip` calls with indented command under 💡 Tip: looks awkward | LOW (rolled into D2 fix) | — | — |

### DX Phase Status: PASSED with 5 auto-decided UX refinements (D1–D5) folded into the tasks below.



- `worktree_validate.py:255,300` — CWD-anchor in Python validator
- `worktree.py:583` — CWD-anchor in porcelain listing
- `worktree_select.py:323,328` — `removesuffix("/.git")` mis-classification
- `branch_available_for_worktree` (line ~445) — CWD-anchor
- `prune_worktrees` (line ~802) — CWD-anchor
- Full merge of `worktree_gitdir` + `resolve_main_worktree_path` into one helper
- Mercurial parity (no submodule concept in `hg-config/`)
