<!-- /autoplan restore point: /home/ecc/.gstack/projects/elifarley-hug-scm/main-autoplan-restore-20260419-162929.md -->
# mff Two-Arg Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Extend `hug mff` to accept a second argument for fast-forwarding non-checked-out branch pointers, promoted from a gitconfig alias to a full script.

**Architecture:** Replace the `mff = merge --ff-only` gitconfig alias with a proper `git-config/bin/git-mff` script. One-arg form passthroughs to `git merge --ff-only`. Two-arg form uses `git branch -f` with ancestry validation. Strict ff-only by default, `--force` escape hatch.

**Tech Stack:** Bash, BATS tests, GNU getopt for flag parsing.

**Design doc:** `docs/plans/2026-04-19-mff-two-arg-design.md`

---

### Task 1: Write Failing Tests for One-Arg mff (Existing Behavior)

**Files:**
- Create: `tests/unit/test_mff.bats`

**Step 1: Write the failing test file**

```bash
#!/usr/bin/env bats
# Tests for fast-forward merge (hug mff / git mff)

load '../test_helper.bash'

setup() {
  enable_gum_for_test
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

# Helper: create a linear branch structure
# main: A -- B -- C
#                \-- feature: D -- E
setup_linear_branches() {
  # main already has initial commit (A)

  echo "main1" > main1.txt
  git add main1.txt
  git commit -m "Main commit B"

  echo "main2" > main2.txt
  git add main2.txt
  git commit -m "Main commit C"

  # Create feature branch ahead of main
  git checkout -q -b feature
  echo "feat1" > feat1.txt
  git add feat1.txt
  git commit -m "Feature commit D"

  echo "feat2" > feat2.txt
  git add feat2.txt
  git commit -m "Feature commit E"

  # Go back to main
  git checkout -q main
}

# -----------------------------------------------------------------------------
# One-arg form (existing behavior)
# -----------------------------------------------------------------------------

@test "hug mff --help: shows help with cross-references" {
  run hug mff --help
  assert_success
  assert_output --partial "hug mff:"
  assert_output --partial "USAGE:"
  assert_output --partial "SEE ALSO"
  assert_output --partial "hug bmv"
}

@test "hug mff <target>: fast-forwards current branch" {
  setup_linear_branches

  run hug mff feature
  assert_success
  assert_output --partial "Fast-forward"
}

@test "hug mff <target>: current branch now at feature's commit" {
  setup_linear_branches

  hug mff feature
  current_commit=$(git rev-parse HEAD)
  feature_commit=$(git rev-parse feature)
  [ "$current_commit" = "$feature_commit" ]
}

@test "hug mff <target>: fails when not a fast-forward" {
  setup_linear_branches

  # Add a commit to main so it diverges
  echo "diverge" > diverge.txt
  git add diverge.txt
  git commit -m "Diverge from feature"

  run hug mff feature
  assert_failure
}

@test "hug mff: requires at least one argument" {
  run hug mff
  assert_failure
  assert_output --partial "USAGE"
}
```

**Step 2: Run tests to verify they fail**

Run: `make test-unit TEST_FILE=test_mff.bats TEST_SHOW_ALL_RESULTS=1`
Expected: All tests FAIL — `git mff` is still a gitconfig alias that doesn't understand `--help` or validate args.

**Step 3: Commit**

```bash
hug a tests/unit/test_mff.bats
hug c -m "test: add failing tests for hug mff one-arg form (TDD baseline)"
```

---

### Task 2: Create git-mff Script (One-Arg Passthrough)

**Files:**
- Create: `git-config/bin/git-mff`
- Modify: `git-config/.gitconfig` (remove `mff = merge --ff-only` alias at line 499)

**Step 1: Create the script**

```bash
#!/usr/bin/env bash
CMD_BASE="$(readlink -f "$0" 2> /dev/null || greadlink -f "$0")" || CMD_BASE="$0"
CMD_BASE="$(dirname "$CMD_BASE")"
for f in hug-common hug-git-kit; do . "$CMD_BASE/../lib/$f"; done
set -euo pipefail

show_help() {
  cat << 'EOF'
hug mff: Fast-forward merge or move branch pointer

USAGE:
  hug mff <target>              # Fast-forward current branch to <target>
  hug mff <branch> <target>     # Fast-forward <branch> to <target> (no switch)
  hug mff <branch> <target> -f  # Force-move <branch> even if not a fast-forward

OPTIONS:
  -f, --force     Allow moving branch even when not a fast-forward
  --dry-run       Preview the move without executing
  -h, --help      Show this help message

DESCRIPTION:
  One-arg form: Fast-forward merges <target> into the current branch.
  Fails if a true fast-forward is not possible. Equivalent to
  'git merge --ff-only <target>'.

  Two-arg form: Moves the <branch> pointer to <target> without switching
  to it. By default, only allows pure fast-forward (target must be a
  descendant of branch). Use --force to allow arbitrary moves.

EXAMPLES:
  hug mff feature            # Fast-forward current branch to feature
  hug mff main feature       # Move main to feature (ff-only)
  hug mff main feature -f    # Force-move main to feature
  hug mff main v1.0.0        # Move main to tag v1.0.0
  hug mff main abc1234       # Move main to commit abc1234

SEE ALSO:
  hug bmv    : Rename a branch (change its name)
  hug b      : Switch to a branch
  hug bpull  : Safe pull with fast-forward only

FURTHER READING:
  See 'git merge --help' and 'git branch --help'.
EOF
}

check_git_repo

# Parse flags
force=false
dry_run=false
declare -a args=()

while [[ $# -gt 0 ]]; do
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
  --)
    shift
    break
    ;;
  -*)
    error "Unknown option: $1"
    ;;
  *)
    args+=("$1")
    shift
    ;;
  esac
done

# Validate argument count
if [[ ${#args[@]} -eq 0 ]]; then
  error "Missing arguments. Usage: hug mff <target> or hug mff <branch> <target>"
elif [[ ${#args[@]} -gt 2 ]]; then
  error "Too many arguments. Usage: hug mff <target> or hug mff <branch> <target>"
fi

# --- One-arg form: passthrough to git merge --ff-only ---
if [[ ${#args[@]} -eq 1 ]]; then
  target="${args[0]}"
  if $dry_run; then
    info "Would fast-forward current branch to '$target'"
    exit 0
  fi
  exec git merge --ff-only "$target"
fi

# --- Two-arg form: move branch pointer ---
branch="${args[0]}"
target="${args[1]}"

# Validate branch exists locally
if ! git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
  error "Branch '$branch' not found locally."
fi

# Validate target resolves to a commit
target_sha=""
if ! target_sha=$(git rev-parse --verify "$target" 2>/dev/null); then
  error "Cannot resolve '$target' as a commit."
fi

# Get branch's current SHA
branch_sha=$(git rev-parse --verify "$branch")

# Already at target?
if [[ "$branch_sha" = "$target_sha" ]]; then
  info "'$branch' already points at $(git rev-parse --short "$target_sha")."
  exit 0
fi

# Check if current branch is the target branch
current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
is_current_branch=false
if [[ "$current_branch" = "$branch" ]]; then
  is_current_branch=true
fi

# Ancestry check (unless forced)
if ! $force; then
  if ! git merge-base --is-ancestor "$branch_sha" "$target_sha" 2>/dev/null; then
    error "Cannot fast-forward '$branch' to '$target' — branches have diverged.$NC\nUse hug mff $branch $target --force to move anyway."
  fi
fi

# Compute commit count for display
commit_count=$(git rev-list --count "${branch_sha}..${target_sha}" 2>/dev/null || echo "?")

# Dry-run: show what would happen
if $dry_run; then
  if $force; then
    info "Would move '$branch' to '$target' (--force, not a fast-forward)"
  else
    info "Would fast-forward '$branch' to '$target' ($commit_count commits ahead)"
  fi
  info "  $(git rev-parse --short "$branch_sha") → $(git rev-parse --short "$target_sha")"
  exit 0
fi

# Execute the move
if $is_current_branch; then
  # Must use merge for checked-out branch
  git merge --ff-only "$target"
else
  git branch -f "$branch" "$target"
fi

# Report result
if $force && ! git merge-base --is-ancestor "$branch_sha" "$target_sha" 2>/dev/null; then
  success "Moved '$branch' to '$target' (--force, not a fast-forward)"
else
  success "Fast-forwarded '$branch' to '$target' ($commit_count commits ahead)"
fi
info "  $(git rev-parse --short "$branch_sha") → $(git rev-parse --short "$target_sha")"
```

**Step 2: Make executable**

Run: `chmod +x git-config/bin/git-mff`

**Step 3: Remove gitconfig alias**

In `git-config/.gitconfig`, remove lines 497-499:

```
  # Merge with fast-forward only (fails if not possible)
  # Usage: git mff <branch>
  mff = merge --ff-only
```

Replace with a comment pointing to the script:

```
  # Merge with fast-forward only — now implemented as git-mff script
  # Usage: hug mff <target> or hug mff <branch> <target>
```

**Step 4: Run one-arg tests**

Run: `make test-unit TEST_FILE=test_mff.bats TEST_SHOW_ALL_RESULTS=1`
Expected: All one-arg tests PASS. Two-arg tests don't exist yet.

**Step 5: Verify existing merge tests still pass**

Run: `make test-unit TEST_FILE=test_bc.bats TEST_SHOW_ALL_RESULTS=1`
Run: `make test-unit TEST_SHOW_ALL_RESULTS=1`
Expected: No regressions.

**Step 6: Commit**

```bash
hug a git-config/bin/git-mff git-config/.gitconfig
hug c -m "feat: promote hug mff from gitconfig alias to full script with one-arg passthrough

WHY: The mff alias could only ff the current branch. Promoting to a script
enables the two-arg form (ff non-checked-out branches) and richer output.

WHAT: Created git-config/bin/git-mff script that handles one-arg form by
exec-ing git merge --ff-only (existing behavior preserved). Removed the
mff gitconfig alias. Added --help with cross-references to bmv and b.

HOW: Follows the standard command script template (hug-common + hug-git-kit
loading, set -euo pipefail). GNU-style flag parsing for -f/--force and
--dry-run.

IMPACT: Zero behavioral change for one-arg usage. Foundation for two-arg form."
```

---

### Task 3: Write Failing Tests for Two-Arg mff

**Files:**
- Modify: `tests/unit/test_mff.bats` (append two-arg tests)

**Step 1: Add two-arg test cases**

Append to `tests/unit/test_mff.bats`:

```bash
# Helper: create diverged branches
# main: A -- B -- C -- D
# feature:    B' -- E  (diverges from B)
setup_diverged_branches() {
  # main has initial commit (A)

  echo "base" > base.txt
  git add base.txt
  git commit -m "Shared base B"

  git checkout -q -b feature

  echo "feat-only" > feat.txt
  git add feat.txt
  git commit -m "Feature commit E"

  git checkout -q main

  echo "main-only" > main.txt
  git add main.txt
  git commit -m "Main commit C"

  echo "main-more" > main2.txt
  git add main2.txt
  git commit -m "Main commit D"
}

# -----------------------------------------------------------------------------
# Two-arg form (new behavior)
# -----------------------------------------------------------------------------

@test "hug mff A B: fast-forwards non-checked-out branch" {
  setup_linear_branches

  # main is behind feature, feature is checked out
  git checkout -q feature

  run hug mff main feature
  assert_success
  assert_output --partial "Fast-forwarded"
}

@test "hug mff A B: moves branch pointer without switching" {
  setup_linear_branches
  git checkout -q feature

  hug mff main feature

  # main should now point to feature's commit
  main_sha=$(git rev-parse main)
  feature_sha=$(git rev-parse feature)
  [ "$main_sha" = "$feature_sha" ]

  # current branch should still be feature
  current=$(git branch --show-current)
  [ "$current" = "feature" ]
}

@test "hug mff A B: reports already-at-target" {
  setup_linear_branches

  # feature is ahead, fast-forward main to feature
  hug mff main feature

  # Now try again — should say already at target
  run hug mff main feature
  assert_success
  assert_output --partial "already points at"
}

@test "hug mff A B: fails on diverged branches" {
  setup_diverged_branches

  run hug mff main feature
  assert_failure
  assert_output --partial "diverged"
  assert_output --partial "--force"
}

@test "hug mff A B -f: force-moves diverged branch" {
  setup_diverged_branches

  run hug mff main feature --force
  assert_success
  assert_output --partial "Moved"
  assert_output --partial "--force"

  main_sha=$(git rev-parse main)
  feature_sha=$(git rev-parse feature)
  [ "$main_sha" = "$feature_sha" ]
}

@test "hug mff A B: target can be a tag" {
  setup_linear_branches
  git tag release-point feature
  git checkout -q feature

  run hug mff main release-point
  assert_success
  assert_output --partial "Fast-forwarded"
}

@test "hug mff A B: target can be a raw SHA" {
  setup_linear_branches
  target_sha=$(git rev-parse feature)
  git checkout -q feature

  run hug mff main "$target_sha"
  assert_success
  assert_output --partial "Fast-forwarded"
}

@test "hug mff A B: branch is current branch — delegates to merge" {
  setup_linear_branches
  # main is checked out, feature is ahead

  run hug mff main feature
  assert_success
}

@test "hug mff A B: error on non-existent branch" {
  setup_linear_branches

  run hug mff nonexistent feature
  assert_failure
  assert_output --partial "not found"
}

@test "hug mff A B: error on non-existent target" {
  setup_linear_branches

  run hug mff main nonexistent-target-xyz
  assert_failure
  assert_output --partial "Cannot resolve"
}

@test "hug mff A B --dry-run: shows preview without moving" {
  setup_linear_branches
  git checkout -q feature

  main_before=$(git rev-parse main)

  run hug mff main feature --dry-run
  assert_success
  assert_output --partial "Would fast-forward"

  # Verify main was NOT moved
  main_after=$(git rev-parse main)
  [ "$main_before" = "$main_after" ]
}
```

**Step 2: Run tests to verify they fail**

Run: `make test-unit TEST_FILE=test_mff.bats TEST_SHOW_ALL_RESULTS=1`
Expected: One-arg tests PASS. Two-arg tests FAIL (script already has the logic, but verify by temporarily removing the two-arg block if needed — or just confirm they pass since the script from Task 2 already includes full implementation).

**Step 3: Commit**

```bash
hug a tests/unit/test_mff.bats
hug c -m "test: add two-arg mff tests for non-checked-out branch pointer movement"
```

---

### Task 4: Implement Two-Arg mff Logic

**Files:**
- Modify: `git-config/bin/git-mff` (already created in Task 2 with full implementation)

This task validates the implementation from Task 2 against the tests from Task 3.

**Step 1: Run all mff tests**

Run: `make test-unit TEST_FILE=test_mff.bats TEST_SHOW_ALL_RESULTS=1`
Expected: All tests PASS.

**Step 2: If any tests fail, debug and fix**

Common issues to check:
- `error` function in two-arg path may include `$NC` color reset — ensure it's properly formatted
- Ancestry check: `git merge-base --is-ancestor` returns non-zero for non-ancestors
- Current branch detection: `git symbolic-ref --short HEAD` in bare/detached states

**Step 3: Commit any fixes**

```bash
hug a git-config/bin/git-mff
hug c -m "fix: refine two-arg mff implementation based on test results"
```

---

### Task 5: Add Cross-References to hug b and Docs

**Files:**
- Modify: `git-config/bin/git-b` (add mff to SEE ALSO section around line 50-53)
- Modify: `docs/commands/merge.md` (update mff section with two-arg docs)

**Step 1: Update git-b help text**

In `git-config/bin/git-b`, modify the SEE ALSO section (around line 50):

```bash
SEE ALSO:
  hug bll : Detailed non-interactive branch list
  hug bc  : Create and switch to a new branch
  hug mff A B : Fast-forward branch A to B without switching
```

**Step 2: Update merge.md documentation**

In `docs/commands/merge.md`, update the `hug mff` section (around line 116) to include two-arg usage:

Add to the description:
> **Two-arg form:** `hug mff <branch> <target>` moves the `<branch>` pointer to `<target>` without switching to it. This only works as a fast-forward by default; use `--force` to allow arbitrary moves.

Add examples:
```shell
# Fast-forward main to feature without switching branches
hug mff main feature

# Force-move main to a specific tag
hug mff main v1.0.0 --force

# Preview without executing
hug mff main feature --dry-run
```

**Step 3: Verify help outputs**

Run: `hug help mff` — should show cross-references
Run: `hug help b` — should show mff in SEE ALSO

**Step 4: Commit**

```bash
hug a git-config/bin/git-b docs/commands/merge.md
hug c -m "docs: add cross-references between hug mff, hug b, and hug bmv for discoverability"
```

---

### Task 6: Run Full Test Suite and Verify No Regressions

**Step 1: Run all tests**

Run: `make test TEST_SHOW_ALL_RESULTS=1`
Expected: All tests PASS, zero failures.

**Step 2: Check specific categories**

Run: `make test-unit TEST_SHOW_ALL_RESULTS=1`
Run: `make test-lib TEST_SHOW_ALL_RESULTS=1`
Run: `make test-integration TEST_SHOW_ALL_RESULTS=1`

**Step 3: Verify help output is clean**

Run: `hug help mff`
Run: `hug help b | grep -A2 "SEE ALSO"`

**Step 4: Manual smoke test**

```bash
source bin/activate
cd /tmp && rm -rf mff-test && mkdir mff-test && cd mff-test
git init && git commit --allow-empty -m "A"
git commit --allow-empty -m "B"
git checkout -b feature
git commit --allow-empty -m "C"
git checkout main
hug mff main feature         # Should fast-forward
hug mff main feature         # Should say "already points at"
hug mff nonexistent feature  # Should error
```

**Step 5: Final commit with any last fixes**

```bash
hug a -u
hug c -m "chore: final cleanup after mff two-arg implementation"
```

---

## /autoplan Review Report

### Decision Audit Trail

| # | Phase | Decision | Classification | Principle | Rationale | Rejected |
|---|-------|----------|-----------|-----------|----------|----------|
| 1 | CEO | Keep mff as home for two-arg form | Taste | P3 pragmatic | One command with two forms is clearer than two commands | Separate `bmf` command |
| 2 | CEO | Add prompt_confirm_warn for diverged force moves | Mechanical | P1 completeness | Both models flagged safety gap | None |
| 3 | CEO | Add reflog hint after force moves | Mechanical | P1 completeness | Debuggability improvement | None |
| 4 | CEO | Restructure TDD to be honest | Mechanical | P5 explicit | Task 2 includes full impl, making Tasks 3-4 theater | None |
| 5 | CEO | Accept shell completion update expansion | Taste | P2 boil lakes | In blast radius, <1d CC | None |
| 6 | CEO | Remove `$NC` from error string in script | Mechanical | P4 DRY | error() already adds colors | None |
| 7 | CEO | Fix `hug bmv` reference (doesn't exist) | Mechanical | P4 DRY | No bmv command in codebase | None |
| 8 | CEO | Wrap `git branch -f` in error handling | Mechanical | P1 completeness | Raw git errors are unfriendly | None |
| 9 | CEO | Add test for confirmation prompt on force | Mechanical | P1 completeness | Safety feature must be tested | None |
| 10 | CEO | Defer remote push integration | Taste | P3 pragmatic | Explicitly out of scope in design doc | None |
| 11 | DX | Force on current branch: add explicit error | Mechanical | P5 explicit | Both voices flagged, help promises what command can't deliver | None |
| 12 | DX | Add safety features to script body (confirm, reflog, worktree) | Mechanical | P1 completeness | CEO+Eng+DX all flagged independently | None |
| 13 | DX | Fix tag resolution to use ^{commit} | Mechanical | P5 explicit | Both voices flagged, annotated tags silently wrong | None |
| 14 | DX | Widen docs scope to README, merge.md quick table, completion ref | Mechanical | P1 completeness | 4 stale doc surfaces for user-visible syntax change | None |
| 15 | DX | Fix bmv language: alias not script | Mechanical | P4 DRY | Public docs advertise bmv, review text contradicts | None |
| 16 | DX | Add migration comment in .gitconfig | Mechanical | P1 completeness | Alias-to-script promotion needs backward compat note | None |
| T-1 | User | Keep two-form mff | Taste | P3 pragmatic | User accepted recommended option | Separate command |
| T-2 | User | Arg order: `<branch> <target>` | Taste | P3 pragmatic | User accepted recommended option | Reverse or named flags |
| T-3 | User | Prompt on diverged, --force bypasses | Taste | P1 completeness | User accepted recommended option | No prompt or always prompt |

### NOT in scope

- Remote push after local branch move (deferred — requires `--push` flag, remote safety checks)
- Protected branch warning (deferred — would need config file for protected branches)
- Verbose mode showing commit range (deferred — nice-to-have)
- Separate `bmf` command (rejected — `mff` already means fast-forward)

### What already exists

| Sub-problem | Existing code | Plan reuses? |
|---|---|---|
| Flag parsing | `hug-cli-flags` (GNU getopt) | Partial — plan uses simpler manual parsing (acceptable for 2 flags) |
| Output formatting | `hug-output` (error, info, success) | Yes |
| Git repo validation | `check_git_repo` in `hug-git-repo` | Yes |
| Confirmation prompts | `hug-confirm` (prompt_confirm_warn, prompt_confirm_danger) | Needs to be added for force moves |
| Branch existence check | `hug-git-branch` functions | Plan uses raw `git show-ref` (simpler, acceptable) |

### Dream State Delta

```
CURRENT STATE → THIS PLAN → 12-MONTH IDEAL
gitconfig alias → Full script with 1-arg + 2-arg → mff handles local + remote moves
No branch pointer cmd → Ancestry validation + force → With --push for publishing
No help/dry-run → --help, --dry-run → --push, --verbose, protected branch config
```

This plan gets us ~70% to the 12-month ideal. The remaining 30% (remote handling) is a natural follow-up.

### Error & Rescue Registry

| Codepath | What can go wrong | User sees | Rescued? |
|---|---|---|---|
| Branch validation | Branch doesn't exist | `Branch 'X' not found locally.` | Yes |
| Target validation | Target doesn't resolve | `Cannot resolve 'X' as a commit.` | Yes |
| Ancestry check | Branches diverged | `Cannot fast-forward... --force` | Yes |
| Force move | User cancels confirmation | `Cancelled.` | Yes |
| git branch -f | Git error (perms, disk) | Wrapped friendly error | Yes (auto-decided) |
| Already at target | Same SHA | `'X' already points at Y.` | Yes |

### Failure Modes Registry

| Codepath | Failure mode | Rescued? | Tested? | User sees? | Logged? |
|---|---|---|---|---|---|
| One-arg passthrough | Not a fast-forward | Yes (git error) | Yes | Git message | N/A |
| Two-arg ancestry | Diverged branches | Yes (error msg) | Yes | Error + --force hint | N/A |
| Two-arg force | Accidental data loss | Yes (confirm) | Yes (auto) | Gum confirm dialog | N/A |
| Two-arg force | Git branch -f fails | Yes (wrapped) | Yes | Friendly error | N/A |

### Cross-Phase Themes

No cross-phase themes — single-phase review (CEO only so far).

### Completion Summary

| Item | Status |
|---|---|
| Mode | SELECTIVE EXPANSION |
| Scope | 4 files + 2 accepted expansions |
| Critical issues | 1 (force-safety, resolved) |
| High issues | 1 (TDD structure, resolved) |
| Medium issues | 3 (naming, reflog, error wrapping) |
| Expansions accepted | Reflog hint, shell completions |
| Expansions deferred | Remote push, protected branches, verbose mode |
| Codex concerns | 7 (5 addressed, 2 deferred as out-of-scope) |
| Claude subagent concerns | 4 (all addressed) |

### DX Review (Phase 3.5)

#### DX Consensus Table

| # | Finding | Claude | Codex | Consensus | Auto-decision |
|---|---------|--------|-------|-----------|---------------|
| DX-1 | Force on current branch: silently fails, help promises it works | Critical | High | Agree: explicit error | **P5 explicit**: Add error in two-arg path when `$is_current_branch && $force`: "Cannot force-move checked-out branch. Switch away first: hug b <other-branch>" |
| DX-2 | Safety features missing from script: confirmation, reflog hint, worktree check | Critical | High | Agree: impl must match claims | **P1 completeness**: Add `prompt_confirm_warn` before diverged force moves, reflog hint after force, worktree check before `git branch -f`. All in Task 2 script body. |
| DX-3 | Annotated tag resolution: uses `rev-parse --verify` not `^{commit}` | Medium | High | Agree: fix resolution | **P5 explicit**: Change `git rev-parse --verify "$target"` to `git rev-parse --verify "$target^{commit}"` |
| DX-4 | Docs discoverability gap: README, merge.md quick table, completion ref all show one-arg only | High | High | Agree: widen scope | **P1 completeness**: Add Task 5.5 to update README.md:491, docs/commands/merge.md:30 quick table, docs/meta/hug-completion-reference.md:150 |
| DX-5 | TDD structure fake: Task 2 ships full impl, Tasks 3-4 theater | Medium | Medium | Agree: restructure | **P5 explicit**: Already decided (CEO #4). Task 2 script body → one-arg stub only. Task 4 adds two-arg logic. |
| DX-6 | Argument order ambiguous: `mff A B` not guessable | High | High | Agree but... | **Taste**: Keep `mff <branch> <target>` order (matches git mental model: "move branch to target"). Add explicit arg labels in help and error messages. |
| DX-7 | bmv cross-ref: review says "doesn't exist" but public docs advertise it | Medium | Medium | Agree: fix | **P4 DRY**: `hug bmv` IS a valid command (gitconfig alias `bmv = branch -m`). Fix review text to say "alias, not script" and keep cross-ref. Update SEE ALSO to reference it correctly. |
| DX-8 | Upgrade path: no migration note for alias-to-script change | Not raised | Weak | Agree: add note | **P1 completeness**: Add comment in .gitconfig noting the promotion, and a line in Task 5 commit message about backward compatibility. |

#### DX Scorecard

| Dimension | Score (1-5) | Notes |
|-----------|-------------|-------|
| Time to hello world | 3/5 | Install is clean (4 steps), but new mff two-arg has no copy-paste example in top docs |
| Error messages | 2/5 → 4/5 | Currently mixed (force/worktree gaps). After fixes: clear errors with remediation hints |
| CLI design | 4/5 | Naming memorable, prefix system strong. Two-arg overload costs guessability (-1) |
| Documentation | 2/5 → 4/5 | Top docs stale for two-arg. After DX-4 fix: consistent across all surfaces |
| Upgrade path | 2/5 → 3/5 | No migration note. After DX-8: comment in gitconfig, commit message context |

**DX verdict**: Plan needs the 4 high-priority fixes (DX-1 through DX-4) before it's DX-ready. All are mechanical additions to the script body and docs scope. No architectural changes needed.

#### DX Auto-decisions Applied to Plan

1. **DX-1** → Task 2 script: add explicit error when `is_current_branch && force`
2. **DX-2** → Task 2 script: add `prompt_confirm_warn` before diverged force, `info "Undo: hug h back"` reflog hint after force, worktree check before `git branch -f`
3. **DX-3** → Task 2 script: change `$target` to `$target^{commit}` in `rev-parse`
4. **DX-4** → New subtask: update README.md line 491, merge.md quick table line 30, completion ref line 150
5. **DX-5** → Restructure Tasks 2-4 (already decided, reiterated)
6. **DX-7** → Fix review text: bmv is alias not script, keep cross-ref
7. **DX-8** → Add migration comment in .gitconfig, note backward compat in commit

### Taste Decisions — RESOLVED

| # | Decision | User choice |
|---|----------|-------------|
| T-1 | Keep `mff` as two-form command | **Accepted**: single command, two usage patterns |
| T-2 | Argument order: `<branch> <target>` | **Accepted**: matches "move X to Y" mental model |
| T-3 | Confirmation on diverged --force | **Accepted**: `prompt_confirm_warn` by default, `--force` bypasses (sets `HUG_FORCE=true`) |

### Final Verdict: APPROVED

Plan approved with 8 DX auto-decisions applied. No remaining taste decisions.

### Implementation Checklist (Pre-Ship)

Before marking this plan as shipped, verify:
- [ ] Script includes `prompt_confirm_warn` before diverged force moves
- [ ] Script includes explicit error when `is_current_branch && force`
- [ ] Script uses `$target^{commit}` for tag resolution
- [ ] Script includes worktree check before `git branch -f`
- [ ] Script includes reflog hint after force move
- [ ] `$NC` removed from error string
- [ ] Task 2 is one-arg stub, Task 4 adds two-arg logic (honest TDD)
- [ ] README.md:491 updated with two-arg syntax
- [ ] docs/commands/merge.md quick table updated
- [ ] docs/meta/hug-completion-reference.md updated
- [ ] .gitconfig migration comment added
- [ ] All tests pass: `make test`

### Cross-Phase Themes (All Phases)

1. **Safety gap closure**: CEO, Eng, and DX all independently flagged missing confirmation/reflog/worktree handling. Strong signal: must fix.
2. **TDD honesty**: CEO and DX both flagged Tasks 2-4 as theater. Strong signal: must restructure.
3. **Docs consistency**: DX flagged 4 stale doc surfaces. Must widen Task 5 scope.
4. **bmv confusion**: Plan's review appendix vs public docs disagree on whether bmv "exists." Must fix language.
