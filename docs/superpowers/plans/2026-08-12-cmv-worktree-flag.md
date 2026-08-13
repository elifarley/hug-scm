# `hug cmv --wt` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `--wt` flag to `hug cmv` so one command moves commits to a target branch AND ensures that branch has a worktree (create if missing, reuse if present), leaving the user on the source branch.

**Architecture:** Extract a reusable `create_worktree_for_branch` library function from `git-wtc` into `hug-git-worktree`, have both `wtc` and `cmv` call it, then implement `cmv --wt`'s four-phase flow (confirm → create wt → pick in wt → reset source). The move stays danger-tier; worktree creation stays safe-tier. Recovery is the inverse cmv.

**Tech Stack:** Bash + GNU getopt; BATS test suite; existing `hug-git-worktree`, `hug-confirm`, `hug-output` libraries.

## Global Constraints

- All state-modifying commands follow the family-wide tier model: `safe` (additive/reversible), `warn` (destructive but recoverable), `danger` (irreversible/data-loss).
- `-y`/`HUG_YES` auto-confirms `safe` and `warn` prompts only; it must HARD-REFUSE `danger` prompts with exit 3.
- `-f`/`HUG_FORCE` auto-confirms all tiers and overrides blocked states.
- `error_blocked` (exit 3) for safety-blocked states; `error_usage` (exit 2) for bad flags/args; `error` (exit 1) for operational failures.
- Worktrees are managed ONLY via `hug wtc`/`hug wtl`/`hug wtdel` at the user level; internal `git worktree add` is only allowed inside library code.
- Auto-generated worktree path is always `../<repo>.WT.<safe-branch>` with `generate_unique_worktree_path` collision fallback (`-N` suffix).
- Never rewrite history beyond what cmv already does; no `mff` SHA-preserving tip.
- Run `make sanitize` before finishing; never call `make format`/`make lint`/`make typecheck` separately.

---

### Task 1: Extract `create_worktree_for_branch` library function

**Files:**
- Create: (none — function goes into an existing file)
- Modify: `git-config/lib/hug-git-worktree` — append a new function at the end of the file
- Modify: `git-config/bin/git-wtc` — replace the inline worktree-creation block with a call to the new function
- Test: `tests/lib/test_hug-git-worktree.bats` — add library tests
- Test: `tests/unit/test_worktree_create.bats` — existing tests are the no-regression guard

**Interfaces:**
- Consumes: `generate_worktree_path`, `generate_unique_worktree_path`, `validate_worktree_creation_path`, `prompt_confirm_safe`, `info`, `warning`, `success`, `tip`, `suggest_superproject_ignore`, `error` (all already sourced in `hug-git-worktree` / `hug-common`).
- Produces: `create_worktree_for_branch <branch> [--base <point>] [--path <path>] [--force] [--quiet] [--dry-run]`
  - Creates `<branch>` if it doesn't exist (from `--base`, else HEAD), then creates the worktree at the path from `--path` (a custom caller-supplied path) or, when `--path` is absent, the auto-generated (collision-fallback) path.
  - Owns: path resolution (custom path OR generation + collision fallback), path validation, safe-tier confirmation, dry-run, branch-creation rollback on worktree failure.
  - Does NOT own: the "checked out elsewhere / main worktree" guards (callers do that before calling).
  - Prints THREE tab-separated fields to stdout on success: `RESOLVED_PATH<TAB>CREATED_BRANCH<TAB>DRY_RUN`, where `CREATED_BRANCH` and `DRY_RUN` are `true`/`false`. (Callers split on the tab to recover each; cmv needs only the path, wtc needs all three for its `--json` emitter.)
  - Exit codes: 0 success (or dry-run preview), 1 cancelled (via `prompt_confirm_safe`, which `exit 1`s on decline) OR operational error, 2 usage error, 3 blocked by safety.
  - CRITICAL — `set -euo pipefail` + command substitution: `x=$(func ...)` where `func` exits non-zero ABORTS the caller at that assignment; the `rc=$?` line never runs. Callers MUST use the `set -e`-exempt `if x=$(func ...); then ... else rc=$?; ...; fi` form (a command in an `if` condition is exempt). Do NOT use `x=$(func ...); rc=$?` — that is broken under `set -e`.

- [ ] **Step 1: Write the failing library test**

Append to `tests/lib/test_hug-git-worktree.bats`:

```bats
@test "create_worktree_for_branch: creates a new branch + worktree and prints resolved path + created_branch" {
  local repo
  repo=$(create_test_repo)
  pushd "$repo" >/dev/null

  local out path created dry
  out=$(HUG_FORCE=true create_worktree_for_branch feature-x --base HEAD --force)
  assert_success
  IFS=$'\t' read -r path created dry <<< "$out"
  assert_equal "$created" "true"
  assert_equal "$dry" "false"

  # Branch exists and worktree is valid
  git rev-parse --verify refs/heads/feature-x >/dev/null
  assert_worktree_exists "$path"
  assert_worktree_branch "$path" "feature-x"

  popd >/dev/null
  rm -rf "$repo"
}

@test "create_worktree_for_branch: reuses existing branch without --base" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q -b existing-wt
  git checkout -q main

  local out path created dry
  out=$(HUG_FORCE=true create_worktree_for_branch existing-wt --force)
  assert_success
  IFS=$'\t' read -r path created dry <<< "$out"
  assert_equal "$created" "false"
  assert_equal "$dry" "false"
  assert_worktree_exists "$path"
  assert_worktree_branch "$path" "existing-wt"

  popd >/dev/null
  rm -rf "$repo"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test-lib TEST_FILE=test_hug-git-worktree.bats TEST_FILTER="create_worktree_for_branch"`
Expected: FAIL — `create_worktree_for_branch: command not found`

- [ ] **Step 3: Add the library function**

Append to the end of `git-config/lib/hug-git-worktree`:

```bash
################################################################################
# Create a worktree for a branch (create the branch if missing), returning the
# resolved worktree path on stdout.
#
# Usage: create_worktree_for_branch <branch> [--base <point>] [--path <path>] [--force] [--quiet] [--dry-run] [--confirmed-branch]
#   <branch>      Branch to create/worktree (created if missing).
#   --base POINT  Create the branch from POINT (implies branch creation; errors
#                 if the branch already exists).
#   --path PATH   Create the worktree at PATH (custom caller-supplied path).
#                 When absent, auto-generate with collision fallback.
#   --force       Skip safe-tier confirmation and allow force worktree creation.
#   --quiet       Suppress informational chatter.
#   --dry-run     Print the plan without creating anything.
#   --confirmed-branch  Caller already confirmed branch creation; skip the branch
#                 prompt and the worktree prompt (same single decision). Use when
#                 the caller gathered the safe prompt first (cmv does this).
#
# Exit: 0 success (resolved path on stdout), 1 cancelled/operational error,
#       2 usage error, 3 blocked by safety.
#
# NOTE: Callers own the "branch checked out elsewhere / main worktree" guards.
#       This function only creates.
create_worktree_for_branch() {
    local branch="${1:?create_worktree_for_branch requires a branch}"
    shift
    local base="" custom_path="" force=false dry_run=false confirmed_branch=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --base) base="$2"; shift 2 ;;
        --path) custom_path="$2"; shift 2 ;;
        --force) force=true; shift ;;
        --quiet) export HUG_QUIET=T; shift ;;
        --dry-run) dry_run=true; shift ;;
        --confirmed-branch) confirmed_branch=true; shift ;;
        *) error_usage "Unknown option: $1" ;;
        esac
    done

    local branch_exists=false branch_needs_creation=false confirmed_via_branch_prompt=false
    if git rev-parse --verify "refs/heads/$branch" > /dev/null 2>&1; then
        branch_exists=true
    fi

    if [[ -n "$base" ]] && $branch_exists; then
        error "Branch '$branch' already exists; --base only applies when creating new branches"
    fi

    if ! $branch_exists; then
        if $dry_run; then
            branch_needs_creation=true
        elif [[ -n "$base" ]] || $force || $confirmed_branch; then
            branch_needs_creation=true
        else
            echo >&2
            info "Branch '$branch' does not exist locally."
            if ! prompt_confirm_safe "Create branch '$branch' and its worktree?"; then
                exit 1
            fi
            branch_needs_creation=true
            confirmed_via_branch_prompt=true
        fi
    fi

    local worktree_path
    if [[ -n "$custom_path" ]]; then
        worktree_path="$custom_path"
    else
        worktree_path=$(generate_worktree_path "$branch")
        if [[ -e "$worktree_path" ]]; then
            worktree_path=$(generate_unique_worktree_path "$branch")
            info "Default path exists, using: $worktree_path"
        fi
    fi

    if [[ ! "$worktree_path" = /* ]]; then
        worktree_path="$(pwd)/$worktree_path"
    fi

    if $dry_run; then
        [[ -z "${HUG_QUIET:-}" ]] && {
            echo >&2
            printf 'Worktree Creation Preview (DRY RUN):\n' >&2
            if $branch_needs_creation; then
                printf '  Branch: %s (new)\n' "$branch" >&2
            else
                printf '  Branch: %s\n' "$branch" >&2
            fi
            printf '  Path:   %s\n' "${worktree_path/#$HOME/\~}" >&2
            echo >&2
        }
        info "No changes made (dry run)."
        printf '%s\t%s\t%s\n' "$worktree_path" "$branch_needs_creation" "true"
        return 0
    fi

    if ! $force && ! $confirmed_via_branch_prompt && ! $confirmed_branch; then
        if ! prompt_confirm_safe "Create worktree?"; then
            exit 1
        fi
    fi

    if $branch_needs_creation; then
        local git_err=""
        if [[ -n "$base" ]]; then
            if ! git_err=$(git branch "$branch" "$base" 2>&1); then
                error "Failed to create branch '$branch' from '$base': $git_err"
            fi
            info "Created branch '$branch' from $base ($(git rev-parse --short "$base"))"
        else
            if ! git_err=$(git branch "$branch" 2>&1); then
                error "Failed to create branch '$branch': $git_err"
            fi
            info "Created branch '$branch' from $(git rev-parse --short HEAD)"
        fi
    fi

    if ! validate_worktree_creation_path "$worktree_path"; then
        if $branch_needs_creation; then
            git branch -d "$branch" 2> /dev/null || true
            warning "Rolled back branch '$branch' (worktree path invalid)."
        fi
        exit 1
    fi

    local git_wt_args=("$worktree_path" "$branch")
    if $force; then
        git_wt_args+=("--force")
    fi
    git_err=""
    if ! git_err=$(git worktree add "${git_wt_args[@]}" 2>&1); then
        if $branch_needs_creation; then
            git branch -d "$branch" 2> /dev/null || true
            warning "Rolled back branch '$branch'."
        fi
        error "Failed to create worktree: $git_err"
    fi

    if [[ ! -f "$worktree_path/.git" ]]; then
        error "Worktree creation appeared to succeed but the directory is invalid."
    fi

    success "Worktree created for '$branch'"
    echo >&2
    tip "To start working:  cd ${worktree_path/#$HOME/\~}"
    suggest_superproject_ignore "$worktree_path"

    printf '%s\t%s\t%s\n' "$worktree_path" "$branch_needs_creation" "false"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test-lib TEST_FILE=test_hug-git-worktree.bats TEST_FILTER="create_worktree_for_branch"`
Expected: PASS

- [ ] **Step 5: Refactor `git-wtc` to call the function (no behavior change)**

Replace `git-config/bin/git-wtc` lines 325-437 (from the `# Generate path if not provided` block through the success tip/`suggest_superproject_ignore` call) with:

```bash
# Create worktree via shared library (owns path gen, validation, safe confirm,
# dry-run, and branch-creation rollback). wtc keeps the "checked out elsewhere /
# main worktree" guards above, and the JSON output below.
#
# IMPORTANT: use the set -e-exempt `if x=$(func ...)` form. A bare
# `x=$(func ...); rc=$?` aborts at the assignment when func exits non-zero
# (set -e), so the rc=$? line never runs. The if-condition form captures the
# failure branch correctly.
local _helper_out
if _helper_out=$(create_worktree_for_branch "$branch_name" \
      $([[ -n "$base" ]] && echo "--base" "$base") \
      $([[ -n "$worktree_path" ]] && echo "--path" "$worktree_path") \
      $($force && echo "--force") \
      $($dry_run && echo "--dry-run")); then
    :
else
    local _create_rc=$?
    exit $_create_rc
fi

# Split the helper's three tab-separated fields.
IFS=$'\t' read -r worktree_path branch_needs_creation _wt_dry_run <<< "$_helper_out"

# Dry-run is terminal: preview already printed; do not reach the JSON block.
if [[ "$_wt_dry_run" == "true" ]]; then
    exit 0
fi
```

Note: `worktree_path` passed IN is the caller-supplied custom path (positional or `-p`) when present, else empty (auto-generated by the helper). The helper returns the resolved path AND the `branch_needs_creation` flag, so the existing `--json` block (which reads `$branch_needs_creation`, `$base`, `$worktree_path`) stays correct without recomputation.

- [ ] **Step 6: Run wtc tests to confirm no regression**

Run: `make test-unit TEST_FILE=test_worktree_create.bats`
Expected: PASS (all existing wtc tests)

- [ ] **Step 7: Run sanitize**

Run: `make sanitize`
Expected: PASS (no shellcheck errors)

- [ ] **Step 8: Commit**

```bash
hug a git-config/lib/hug-git-worktree git-config/bin/git-wtc tests/lib/test_hug-git-worktree.bats
hug c -F - <<'EOF'
refactor(wtc): extract create_worktree_for_branch into hug-git-worktree

WHY: cmv --wt needs the same worktree-creation logic (path gen, collision
fallback, safe-tier confirm, branch rollback) without duplicating it.

WHAT: New library function create_worktree_for_branch; git-wtc refactored
to call it. No behavior change — existing wtc tests are the guard.

IMPACT: Single source of truth for worktree creation; cmv can reuse it next.
EOF
```

---

### Task 2: Add `--wt` flag parsing and help text to `git-cmv`

**Files:**
- Modify: `git-config/bin/git-cmv:13-82` (help text) and `:87-111` (flag parsing)

**Interfaces:**
- Consumes: `parse_common_flags` (already sourced), the `--new`/`-u` flags (already parsed).
- Produces: `wt=false` local variable set true when `--wt` is passed; help text documenting `--wt`.

- [ ] **Step 1: Write the failing test for the flag being accepted**

Add to `tests/unit/test_commit.bats` (cmv section, after existing tests):

```bats
@test "hug cmv: --wt is accepted and help documents it" {
  run hug cmv -h
  assert_success
  assert_output --partial -- "--wt"
  assert_output --partial "ensure the target branch has a worktree"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="--wt is accepted"`
Expected: FAIL — help text has no `--wt`

- [ ] **Step 3: Add `--wt` to help text**

In `git-cmv` `show_help()`, update:

USAGE line (line 18) to:
```
    hug cmv [N|COMMIT] <target-branch> [--new] [--wt] [-u, --upstream] [--quiet] [--force]
```

OPTIONS section, after the `--new` line (line 23), add:
```
    --wt            Ensure the target branch has a worktree: create one if missing,
                    otherwise reuse the existing one. The move is performed in/for
                    that worktree and you stay on the source branch.
```

DESCRIPTION, replace the `NOT RESTORABLE:` paragraph (line 41) with:
```
    RECOVERY: cmv is its own inverse. After a successful move, run the printed
    inverse command to move the commits back (see the post-op hint). For new
    branches SHAs are preserved; for existing branches the inverse cherry-picks
    new SHAs. Requires an undrifted tree and knowing N + the original branch.
```

- [ ] **Step 4: Add `--wt` to flag parsing**

In `git-cmv`, after `new_branch=false` (line 89), add `wt=false`. In the `while` case, after the `--new)` arm (line 98-100), add:

```bash
  --wt)
    wt=true
    shift
    ;;
```

- [ ] **Step 5: Run test to verify it passes**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="--wt is accepted"`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
hug a git-config/bin/git-cmv tests/unit/test_commit.bats
hug c -F - <<'EOF'
feat(cmv): parse --wt flag and document it in help text

WHAT: --wt flag parsed (no behavior yet); help text documents the flag and
replaces NOT RESTORABLE with the inverse-cmv recovery wording.

IMPACT: CLI surface ready; behavior lands next task.
EOF
```

---

### Task 3: Implement `cmv --wt` (new branch / flagship path)

**Files:**
- Modify: `git-config/bin/git-cmv` — the branch-existence/creation block (lines 181-207), the reset/move tail (lines 232-263)
- Modify: `git-config/bin/git-cmv:9` — add `hug-git-worktree` to the source loop
- Test: `tests/unit/test_commit.bats` — flagship and missing-branch tests

**Interfaces:**
- Consumes: `create_worktree_for_branch` (Task 1), `get_worktree_path_by_branch` (already in `hug-git-worktree`), `prompt_confirm_danger`, `prompt_confirm_safe`, `$target`, `$original_head`, `$branch_name`.
- Produces: `wt=true` now changes cmv's end-state to stay on source branch and create/reuse the target worktree.

- [ ] **Step 1: Write the failing flagship test**

Add to `tests/unit/test_commit.bats`:

```bats
@test "hug cmv: --wt flagship — new branch + worktree, stays on source" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main
  local original_head
  original_head=$(git rev-parse HEAD)
  local target
  target=$(git rev-parse HEAD~1)

  run hug cmv 1 feature --new --wt --force
  assert_success

  # Source reset back; still on main
  assert_equal "$(git rev-parse main)" "$target"
  run git branch --show-current
  assert_output "main"

  # feature points at original_head (exact SHA preserved)
  assert_equal "$(git rev-parse feature)" "$original_head"

  # Worktree exists for feature at the resolved path
  local wt
  wt=$(get_worktree_path_by_branch feature)
  assert_worktree_exists "$wt"
  assert_worktree_branch "$wt" "feature"

  popd >/dev/null
  rm -rf "$repo"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="--wt flagship"`
Expected: FAIL — cmv ignores `--wt` and ends on `feature`, not `main`

- [ ] **Step 3: Source the worktree library**

In `git-cmv` line 9, change:
```bash
for f in hug-common hug-git-kit; do . "$CMD_BASE/../lib/$f"; done
```
to:
```bash
for f in hug-common hug-git-kit hug-git-worktree; do . "$CMD_BASE/../lib/$f"; done
```

- [ ] **Step 4: Implement the `--wt` new-branch path**

Replace the block from line 181 (branch existence) through the end (line 263) with a `--wt` branch that, for a new target branch, creates the worktree+branch (via `create_worktree_for_branch --base "$original_head"`), then resets source, and stays on source.

The key insertion (before the existing non-`--wt` tail) is:

```bash
if $wt; then
    # Confirm-first: gather safe (worktree) + danger (move) prompts before mutating.
    # For -u, the danger prompt already happened in handle_upstream_operation; skip
    # the danger prompt here (never a second danger prompt for the same move).
    local wt_safe_confirmed=false
    if ! $branch_exists && ! $new_branch && [[ ${HUG_FORCE:-} != true ]]; then
        if ! prompt_confirm_safe "Create branch '$branch_name' and its worktree?"; then
            info "Cancelled."
            exit 0
        fi
        # Track that WE confirmed the combined branch+worktree decision, so the
        # helper skips its own safe prompts (single confirmation per decision).
        wt_safe_confirmed=true
    fi

    # Danger-tier move prompt, but ONLY on the non-upstream path. The -u path
    # already confirmed danger during handle_upstream_operation in step 1.
    if ! $upstream && [[ ${HUG_FORCE:-} != true ]]; then
        prompt_confirm_danger "cmv" "moves commits to another branch and rewrites SHAs; not auto-recoverable"
    fi

    local resolved_wt=""
    if $branch_exists; then
        resolved_wt=$(get_worktree_path_by_branch "$branch_name") || true
    fi

    if [[ -z "$resolved_wt" ]]; then
        # IMPORTANT: use the set -e-exempt `if x=$(func ...)` form. A bare
        # `x=$(func ...); rc=$?` aborts at the assignment under set -e when the
        # helper exits non-zero, so rc is never captured.
        local _helper_out _created_dummy _dry_dummy
        if _helper_out=$(create_worktree_for_branch "$branch_name" \
              $([[ -n "$original_head" && ! $branch_exists ]] && echo "--base" "$original_head") \
              $([[ ${HUG_FORCE:-} == true ]] && echo "--force") \
              $( $wt_safe_confirmed && echo "--confirmed-branch" )); then
            :
        else
            local _create_rc=$?
            exit $_create_rc
        fi
        IFS=$'\t' read -r resolved_wt _created_dummy _dry_dummy <<< "$_helper_out"
        # cmv never passes --dry-run, so _dry_dummy is always false here; the
        # other two fields are ignored (wtc is the only --json consumer).
    fi

    # Pick in the worktree FIRST (cherry-pick case only), then reset source.
    if $branch_exists; then
        git -C "$resolved_wt" cherry-pick "$target".."$original_head"
    fi

    # Reset source to target (safe since tree/index clean).
    git reset --hard "$target"

    test "${HUG_QUIET:-f}" = T && exit

    info "Moved $commits_to_relocate $commit_word to '$branch_name' (worktree: $resolved_wt). Still on '$original_branch'."
    tip "Recovery: cd $resolved_wt && hug cmv $commits_to_relocate $original_branch --wt"
    exit 0
fi
```

- [ ] **Step 5: Run test to verify it passes**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="--wt flagship"`
Expected: PASS

- [ ] **Step 6: Add the missing-branch no-`--new` test**

Add to `tests/unit/test_commit.bats`:

```bats
@test "hug cmv: --wt missing branch without --new prompts; n = nothing" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main
  local original_head
  original_head=$(git rev-parse HEAD)

  run bash -c 'echo "n" | hug cmv 1 missing --wt'
  assert_failure
  assert_output --partial "Cancelled."

  # Nothing mutated: main unchanged, no branch, no worktree
  assert_equal "$(git rev-parse main)" "$original_head"
  run git branch --list missing
  refute_output
  run git worktree list --porcelain
  refute_output --partial "missing"

  popd >/dev/null
  rm -rf "$repo"
}
```

- [ ] **Step 7: Run test to verify it passes**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="missing branch without --new"`
Expected: PASS

- [ ] **Step 8: Run full cmv test set**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="cmv"`
Expected: PASS (existing cmv tests + new)

- [ ] **Step 9: Commit**

```bash
hug a git-config/bin/git-cmv tests/unit/test_commit.bats
hug c -F - <<'EOF'
feat(cmv): --wt flagship path — new branch + worktree, stays on source

WHY: One-shot accidental-commit fix that also creates a worktree.

WHAT: --wt now creates the branch+worktree (via create_worktree_for_branch),
resets source, and leaves the user on the source branch. Exact SHA preserved
for new branches. Confirm-first, pick-then-reset ordering.

IMPACT: The flagship scenario works end-to-end.
EOF
```

---

### Task 4: Implement `cmv --wt` existing-branch path (create wt + cherry-pick inside it)

**Files:**
- Modify: `git-config/bin/git-cmv` — the `--wt` existing-branch sub-path in the block added in Task 3
- Test: `tests/unit/test_commit.bats`

**Interfaces:**
- Consumes: `get_worktree_path_by_branch` (main-inclusive), `create_worktree_for_branch`, `$target`, `$original_head`.
- Produces: existing target branch with no worktree → worktree created then cherry-pick inside it; existing with worktree → reuse and cherry-pick inside it.

- [ ] **Step 1: Write the failing tests**

Add to `tests/unit/test_commit.bats`:

```bats
@test "hug cmv: --wt existing branch without worktree — create wt + cherry-pick" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main
  local original_head
  original_head=$(git rev-parse HEAD)
  local target
  target=$(git rev-parse HEAD~1)
  local moved_subject
  moved_subject=$(git log -1 --format=%s "$original_head")

  # Existing branch, no worktree
  git checkout -q -b feature HEAD~1
  git checkout -q main

  run hug cmv 1 feature --wt --force
  assert_success

  assert_equal "$(git rev-parse main)" "$target"
  run git branch --show-current
  assert_output "main"

  # feature now points at a NEW cherry-picked commit whose subject matches X
  run git log -1 --format=%s feature
  assert_output "$moved_subject"
  run git rev-parse feature
  refute_output "$original_head"

  # Worktree exists for feature
  local wt
  wt=$(get_worktree_path_by_branch feature)
  assert_worktree_exists "$wt"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: --wt existing branch with worktree — reuse, no new worktree" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main
  local original_head
  original_head=$(git rev-parse HEAD)
  local target
  target=$(git rev-parse HEAD~1)

  git checkout -q -b feature HEAD~1
  git checkout -q main
  local pre_wt
  pre_wt=$(create_test_worktree "feature" "$repo")
  local before_count
  before_count=$(get_worktree_count)

  run hug cmv 1 feature --wt --force
  assert_success

  # No new worktree
  assert_equal "$(get_worktree_count)" "$before_count"
  assert_worktree_exists "$pre_wt"

  # Source reset, feature updated in the existing worktree
  assert_equal "$(git rev-parse main)" "$target"
  local moved_subject
  moved_subject=$(git log -1 --format=%s "$original_head")
  run git -C "$pre_wt" log -1 --format=%s
  assert_output "$moved_subject"

  popd >/dev/null
  cleanup_test_worktrees "$repo"
  rm -rf "$repo"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="--wt existing"`
Expected: FAIL — the existing-branch path isn't implemented

- [ ] **Step 3: Complete the existing-branch `--wt` path**

In the Task 3 `--wt` block, the existing-branch logic is already stubbed. Verify it handles both sub-cases:

- `branch_exists && no worktree` → `resolved_wt` is empty → `create_worktree_for_branch "$branch_name"` (no `--base`), then `git -C "$resolved_wt" cherry-pick "$target".."$original_head"`.
- `branch_exists && worktree exists` → `resolved_wt` is non-empty → reuse; `git -C "$resolved_wt" cherry-pick "$target".."$original_head"`.

The Task 3 block already does this. If `get_worktree_path_by_branch` returns empty for a branch with NO worktree (main-inclusive), the `create_worktree_for_branch` fallback handles it.

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="--wt existing"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
hug a git-config/bin/git-cmv tests/unit/test_commit.bats
hug c -F - <<'EOF'
feat(cmv): --wt existing-branch path — create/reuse worktree + cherry-pick

WHAT: Existing target branches get a worktree created (or reused) and the
move cherry-picks inside it before resetting source. New SHA for the moved
commit; source stays intact until the pick succeeds.

IMPACT: All four real --wt scenarios now work.
EOF
```

---

### Task 5: Invert the two stale cmv contract tests

**Files:**
- Modify: `tests/unit/test_commit.bats:1073-1089` (no recovery hint) and `:1110-1114` (help states not restorable)
- Modify: `git-config/bin/git-cmv:163` — update the comment that references 'NOT RESTORABLE'

**Interfaces:**
- Consumes: the recovery-hint output from cmv (plain + `--wt` forms).
- Produces: tests now assert the NEW contract (recovery hint present, help states restorable).

- [ ] **Step 1: Replace the "no recovery hint" test**

Replace `tests/unit/test_commit.bats:1073-1089` with:

```bats
@test "hug cmv: recovery hint emitted on success (plain form), suppressed under --quiet" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main
  git checkout -q -b target-branch HEAD~1
  git checkout -q main

  run hug cmv 1 target-branch -f
  assert_success
  assert_output --partial "hug cmv 1 main"

  run bash -c 'hug cmv 1 target-branch -f --quiet'
  assert_success
  refute_output --partial "hug cmv 1 main"

  popd >/dev/null
  rm -rf "$repo"
}
```

- [ ] **Step 2: Replace the "help states not restorable" test**

Replace `tests/unit/test_commit.bats:1110-1114` with:

```bats
@test "hug cmv: help states restorable via inverse cmv" {
  run hug cmv -h
  assert_output --partial "RECOVERY"
  assert_output --partial "cmv is its own inverse"
}
```

- [ ] **Step 3: Run tests to verify they fail (they now assert the old behavior)**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="recovery hint emitted on success|help states restorable"`
Expected: FAIL — old tests still assert `refute_output --partial "recover"` and `NOT RESTORABLE`

- [ ] **Step 4: Implement the plain-cmv recovery hint**

In `git-cmv`, after the final `tip` (line 263), add a recovery-hint emitter for the non-`--wt` path:

```bash
# Recovery: inverse cmv (suppressed under --quiet; same guard as
# emit_head_recovery_hint in hug-git-upstream).
test "${HUG_QUIET:-}" && return 0
printf '\nℹ️  Recovery: hug cmv %s %s\n' "$commits_to_relocate" "$original_branch" >&2
```

- [ ] **Step 5: Update the `git-cmv:163` comment**

Change the comment's 'NOT RESTORABLE' parenthetical to reference the inverse-cmv recovery, preserving the load-bearing `== 0` guard rationale:

```
# FORWARD + switch branch on a 'danger-tier' command). Strict: a bad ref now fails
```

(Keep the sentence about "cmv's target MUST be an ancestor" and "a forward target is an incoherent cmv request" intact; only drop the 'NOT RESTORABLE' label.)

- [ ] **Step 6: Run tests to verify they pass**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="recovery hint emitted on success|help states restorable"`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
hug a git-config/bin/git-cmv tests/unit/test_commit.bats
hug c -F - <<'EOF'
feat(cmv): emit inverse-cmv recovery hint + invert stale contract tests

WHAT: cmv now prints a recovery hint (hug cmv N <original-branch>) on
success, suppressed under --quiet. Help text says "restorable via inverse
cmv" instead of NOT RESTORABLE. The two tests pinning the old contract are
inverted.

IMPACT: Recovery is discoverable and honest; no single-command recovery is
no longer claimed.
EOF
```

---

### Task 6: Guards — locked/stale worktree, target-in-current-worktree

**Files:**
- Modify: `git-config/bin/git-cmv` — the `--wt` block (add guards)
- Test: `tests/unit/test_commit.bats`

**Interfaces:**
- Consumes: `error_blocked`, `get_worktree_path_by_branch`.
- Produces: safety-blocked states exit 3 with clear messages.

- [ ] **Step 1: Write failing guard tests**

Add to `tests/unit/test_commit.bats`:

```bats
@test "hug cmv: --wt target checked out in current worktree → error_blocked" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main
  run hug cmv 1 main --wt --force
  [ "$status" -eq 3 ]
  assert_output --partial "checked out in the current worktree"

  popd >/dev/null
  rm -rf "$repo"
}

@test "hug cmv: --wt stale worktree dir → error suggesting wtdel/wtprune" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main
  git checkout -q -b feature HEAD~1
  git checkout -q main
  local wt
  wt=$(create_test_worktree "feature" "$repo")
  rm -rf "$wt"   # make it stale (registered but missing dir)

  run hug cmv 1 feature --wt --force
  [ "$status" -eq 3 ]
  assert_output --partial "wtdel"

  popd >/dev/null
  cleanup_test_worktrees "$repo"
  rm -rf "$repo"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="target checked out in current|stale worktree dir"`
Expected: FAIL — no guards yet

- [ ] **Step 3: Implement the guards**

At the top of the `--wt` block in `git-cmv` (before any mutation), add:

```bash
# Guard: target == current branch (the inverted end-state makes this impossible
# to honor — we'd need to create a worktree for the branch we're on).
if [[ "$branch_name" == "$original_branch" ]]; then
    error_blocked "Target branch '$branch_name' is checked out in the current worktree. The --wt end-state requires the target to live in its own worktree."
fi

# Guard: existing branch with a STALE (registered-but-missing) or LOCKED worktree.
if $branch_exists; then
    local _wt_path _wt_gitdir
    if _wt_path=$(get_worktree_path_by_branch "$branch_name" 2>/dev/null); then
        if [[ -n "$_wt_path" && ! -d "$_wt_path" ]]; then
            error_blocked "Worktree for '$branch_name' is stale (missing dir: $_wt_path). Run 'hug wtdel $branch_name' or 'hug wtprune' first."
        fi
        _wt_gitdir=$(worktree_gitdir "$_wt_path" 2>/dev/null || true)
        if [[ -n "$_wt_gitdir" ]] && worktree_is_locked "$_wt_path" "$_wt_gitdir"; then
            error_blocked "Worktree for '$branch_name' is locked (git worktree unlock '$_wt_path'). Unlock it first."
        fi
    fi
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="target checked out in current|stale worktree dir"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
hug a git-config/bin/git-cmv tests/unit/test_commit.bats
hug c -F - <<'EOF'
feat(cmv): --wt safety guards for target-in-current-worktree and stale wt

WHAT: --wt now blocks (exit 3) when the target is the current branch or its
worktree dir is stale/missing, with actionable wtdel/wtprune hints.

IMPACT: No git hard-rule violations; no silent path-into-void failures.
EOF
```

---

### Task 7: Tier separation test — `-y` refuses with no side effects

**Files:**
- Test: `tests/unit/test_commit.bats` (add)
- Modify: `git-config/bin/git-cmv` (only if the confirm-first ordering needs adjustment — expected already correct from Task 3)

**Interfaces:**
- Consumes: `prompt_confirm_danger`, `prompt_confirm_safe`, `HUG_YES`.
- Produces: `-y` on `--wt` refuses the move with exit 3 AND no worktree/branch created.

- [ ] **Step 1: Write the failing test**

Add to `tests/unit/test_commit.bats`:

```bats
@test "hug cmv: --wt -y refuses move (exit 3) and creates nothing" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main
  local original_head
  original_head=$(git rev-parse HEAD)

  run hug cmv 1 feature --new --wt -y
  [ "$status" -eq 3 ]
  assert_output --partial "Dangerous operation requires --force (not -y)"

  # No branch, no worktree, main unchanged
  run git branch --list feature
  refute_output
  run git worktree list --porcelain
  refute_output --partial "feature"
  assert_equal "$(git rev-parse main)" "$original_head"

  popd >/dev/null
  rm -rf "$repo"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="refuses move (exit 3) and creates nothing"`
Expected: FAIL — either `-y` is not wired or the safe prompt fires first and creates the wt

- [ ] **Step 3: Verify/confirm ordering in the `--wt` block**

Confirm the Task 3 `--wt` block gathers the danger prompt (which refuses `-y` via `prompt_confirm_danger`) BEFORE the safe worktree prompt runs any mutation. The order must be:

1. safe worktree prompt is *gathered* (not executed) — but for `-y`, `prompt_confirm_safe` returns 0 immediately, so this is fine;
2. danger move prompt fires — `prompt_confirm_danger` hard-errors on `HUG_YES` with exit 3, BEFORE `create_worktree_for_branch`.

If the block currently places the danger prompt AFTER `create_worktree_for_branch`, move the danger prompt to before it (gather-then-execute).

- [ ] **Step 4: Run test to verify it passes**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="refuses move (exit 3) and creates nothing"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
hug a git-config/bin/git-cmv tests/unit/test_commit.bats
hug c -F - <<'EOF'
test(cmv): --wt -y refuses with exit 3 and creates no side effects

WHAT: Verifies confirm-first ordering — -y hard-refuses the danger move
before the worktree or branch is created, leaving the repo untouched.

IMPACT: No orphan branch/worktree on a blocked exit.
EOF
```

---

### Task 8: Main-worktree reuse test (target checked out in main worktree)

**Files:**
- Test: `tests/unit/test_commit.bats` (add)

**Interfaces:**
- Consumes: `get_worktree_path_by_branch` (main-inclusive).
- Produces: verifies the undo-from-linked-worktree shape reuses the main worktree.

- [ ] **Step 1: Write the failing test**

Add to `tests/unit/test_commit.bats`:

```bats
@test "hug cmv: --wt target in main worktree reuses main, doesn't create one" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main
  # Create a feature branch with one extra commit to move back to main
  git checkout -q -b feature HEAD~1
  echo "feature work" > f.txt
  git add f.txt
  git commit -q -m "Feature work"

  # Put the PRIMARY checkout back on main BEFORE creating the feature worktree.
  # Otherwise main has no worktree when cmv runs and the reuse path is untested.
  git checkout -q main

  local feature_wt
  feature_wt=$(create_test_worktree "feature" "$repo")
  pushd "$feature_wt" >/dev/null

  # Count worktrees before, so we can assert no NEW one was created for main.
  local before_count
  before_count=$(git -C "$repo" worktree list --porcelain | grep -c '^worktree ')

  run hug cmv 1 main --wt --force
  assert_success

  # main should be reused (not a new worktree for main)
  run git branch --show-current
  assert_output "feature"

  # Worktree count unchanged — main was NOT given a new linked worktree.
  local after_count
  after_count=$(git -C "$repo" worktree list --porcelain | grep -c '^worktree ')
  assert_equal "$after_count" "$before_count"

  popd >/dev/null
  # Back in main repo: feature lost the moved commit, main gained it
  run git -C "$repo" log -1 --format=%s main
  assert_output "Feature work"

  popd >/dev/null
  cleanup_test_worktrees "$repo"
  rm -rf "$repo"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="target in main worktree reuses main"`
Expected: FAIL — if the resolver wrongly excludes main, cmv tries to create a worktree for main and git refuses (exit 128)

- [ ] **Step 3: Confirm the main-inclusive resolver is used**

In `git-cmv`'s `--wt` block, confirm the existing-worktree resolution uses `get_worktree_path_by_branch` (which includes main, per `hug-git-worktree:1390`) and NOT `get_worktrees` (excludes main). This should already be the case from Task 3/4; no code change expected unless the test reveals otherwise.

- [ ] **Step 4: Run test to verify it passes**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="target in main worktree reuses main"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
hug a tests/unit/test_commit.bats
hug c -F - <<'EOF'
test(cmv): --wt reuses main worktree for a target checked out there

WHAT: Pins the main-inclusive resolver: undoing from a linked worktree
targeting main reuses the main checkout instead of trying to create a
worktree for it.

IMPACT: The §5 recovery shape is verified end-to-end.
EOF
```

---

### Task 9: Detached-leftover path-collision test

**Files:**
- Test: `tests/unit/test_commit.bats` (add)

**Interfaces:**
- Consumes: `generate_unique_worktree_path` (via `create_worktree_for_branch`).
- Produces: verifies a detached leftover at the auto path causes the new wt to land at `-1` suffix, stale one untouched.

- [ ] **Step 1: Write the failing test**

Add to `tests/unit/test_commit.bats`:

```bats
@test "hug cmv: --wt detached leftover at auto path → new wt lands at -1" {
  local repo
  repo=$(create_test_repo_with_branches)
  pushd "$repo" >/dev/null

  git checkout -q main
  local original_head
  original_head=$(git rev-parse HEAD)

  # Simulate a detached leftover at the canonical path
  local base_path
  base_path="$(dirname "$repo")/$(basename "$repo").WT.feature"
  git worktree add --detach "$base_path" HEAD~2 >/dev/null 2>&1

  run hug cmv 1 feature --new --wt --force
  assert_success

  # Fresh worktree should be at the suffixed path
  local resolved
  resolved=$(get_worktree_path_by_branch feature)
  [[ "$resolved" == "${base_path}-1" ]] || fail "Expected suffixed path ${base_path}-1, got $resolved"

  # Stale detached leftover untouched
  assert_dir_exists "$base_path"

  popd >/dev/null
  rm -rf "$repo"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="detached leftover at auto path"`
Expected: FAIL — collision fallback not yet asserted

- [ ] **Step 3: Confirm no code change needed**

`create_worktree_for_branch` (Task 1) already calls `generate_unique_worktree_path` when the base path exists. The test should pass without cmv changes. If it fails because the detached leftover path is not detected as "existing", verify `[[ -e "$worktree_path" ]]` is true for a detached worktree (it is — the directory exists).

- [ ] **Step 4: Run test to verify it passes**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="detached leftover at auto path"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
hug a tests/unit/test_commit.bats
hug c -F - <<'EOF'
test(cmv): --wt collision fallback lands at suffixed path, stale wt untouched

WHAT: Verifies the detached-leftover edge case: the fresh worktree uses the
-N suffix, and the stale detached directory is left for hug wtdel.

IMPACT: The §1 path promise holds even when the canonical path is occupied.
EOF
```

---

### Task 10: Documentation updates

**Files:**
- Modify: `docs/commands/commits.md` — cmv section usage + a `--wt` paragraph
- Modify: `docs/practical-workflows.md:96-135` — add the one-shot `--wt` flow to §3b
- Modify: `README.md:480` — cmv one-liner
- Modify: `docs/command-map.md:124` — cmv entry note
- Modify: `CHANGELOG.md` — feature entry

**Interfaces:**
- Consumes: the final `--wt` behavior from Tasks 3-9.
- Produces: user-facing docs match the shipped behavior.

- [ ] **Step 1: Update `docs/commands/commits.md`**

Change the usage line (line 15) and the `## hug cmv` usage line (line 220) to include `[--wt]`. Add a `--wt` paragraph after the existing description:

```markdown
**`--wt` (worktree):** ensure the target branch has a worktree. Create one if
missing, otherwise reuse the existing one. The move is performed in/for that
worktree, and you stay on the source branch. Auto-generated path only
(`../<repo>.WT.<branch>`). The move is danger-tier; worktree creation is
safe-tier.
```

- [ ] **Step 2: Update `docs/practical-workflows.md` §3b**

After the existing cmv examples (~line 126), add:

```markdown
**One-shot worktree variant:**

```bash
hug cmv 3 feature/new-feature --new --wt
```

Creates `feature/new-feature` at your current HEAD, moves the last 3 commits
there, resets your current branch, creates a worktree for the new branch, and
leaves you on your original branch. Work on the feature in the new worktree,
no manual branch-switching.
```

- [ ] **Step 3: Update `README.md:480`**

Change:
```
hug cmv [N] <branch> [--new] # Commit MoVe: Relocate commits to another branch (resets source, switches to target)
```
to:
```
hug cmv [N] <branch> [--new] [--wt] # Commit MoVe: Relocate commits to another branch (resets source; --wt also creates/reuses its worktree)
```

- [ ] **Step 4: Update `docs/command-map.md:124`**

Change the cmv line to note `--wt`:
```
│   └── cmv          # Commit Move to branch (--wt: also create/reuse its worktree)
```

- [ ] **Step 5: Update `CHANGELOG.md`**

Add a feature entry under the next unreleased section (or create one if absent):
```
- **`cmv --wt`** — move commits to a branch AND ensure it has a worktree (create if missing, reuse if present), staying on the source branch. Move is danger-tier; worktree creation is safe-tier; recovery is the inverse cmv.
```

- [ ] **Step 6: Build docs to verify no VitePress breakage**

Run: `make docs-build`
Expected: PASS (no broken links/markdown)

- [ ] **Step 7: Commit**

```bash
hug a docs/commands/commits.md docs/practical-workflows.md README.md docs/command-map.md CHANGELOG.md
hug c -F - <<'EOF'
docs(cmv): document --wt flag across user-facing docs

WHAT: cmv --wt added to commits.md, practical-workflows.md, README one-liner,
command-map, and CHANGELOG.

IMPACT: The one-shot accidental-commit + worktree scenario is discoverable.
EOF
```

---

### Task 11: Final verification

**Files:**
- (none)

- [ ] **Step 1: Run the full cmv test set**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="cmv"`
Expected: PASS

- [ ] **Step 2: Run the library test set**

Run: `make test-lib TEST_FILE=test_hug-git-worktree.bats`
Expected: PASS

- [ ] **Step 3: Run the full unit + library suites**

Run: `make test-unit && make test-lib`
Expected: PASS

- [ ] **Step 4: Run sanitize**

Run: `make sanitize`
Expected: PASS

- [ ] **Step 5: Run the full test gate**

Run: `make test`
Expected: PASS (BATS + pytest)

- [ ] **Step 6: Final review of uncommitted state**

Run: `hug s` — confirm only the expected files are staged/modified; no stray artifacts.

- [ ] **Step 7: Commit any remaining changes (if sanitize reformatted anything)**

```bash
hug a  # stage sanitize reformat if needed
hug c -F - <<'EOF'
chore(cmv): sanitize fixes after --wt implementation

WHAT: Folded any make sanitize reformatting into the feature work.

IMPACT: CI-green.
EOF
```
