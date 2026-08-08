# Head-Mover Correctness Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make explicit garbage/forward targets in `h back`/`h undo`/`h rollback` fail loudly instead of triggering root-recovery (#234), make `-u` operations report "behind upstream" truthfully instead of "Already synced" (#237), and pin/correct the hygiene residue (#235/#236/#239).

**Architecture:** One shared validator (`validate_backward_target`) in `git-config/lib/hug-git-upstream`, built on `commit_offset`'s four-outcome dispatch (garbage→error, diverged→silent pass/sideways, ahead→error with restore hint, ancestor/self→pass), wired into the three movers' non-upstream paths with a structural `-z target_arg` root-guard tightening. The §2 fix replaces the `== 0` branch of `handle_upstream_operation` with an aligned-vs-behind split. Spec: `docs/superpowers/specs/2026-08-06-head-mover-correctness-batch-design.md` (read it first — it carries the binding decisions).

**Tech Stack:** Bash (`set -euo pipefail`), BATS test suite via `make test-*` targets, hug CLI.

**Worktree:** ALL work happens in `/home/ecc/src/hug-scm.WT.mover-correctness-batch` (branch `mover-correctness-batch`). Prefix every shell command with `cd /home/ecc/src/hug-scm.WT.mover-correctness-batch &&` (the harness clamps CWD between commands).

**House rules that apply to every task:**
- NEVER write the literal two-character pipe + `echo 0` swallow form into comments — the canary `grep -rn '|| echo 0' git-config/` must stay at exactly 1 hit.
- Inside functions, NEVER merge declaration+capture (`local x=$(cmd)` masks failure); declare then assign.
- Never use `local` outside a function body.
- Commits: `hug a <files>` then `hug c -F -` with a WHY/WHAT/HOW/IMPACT body (load the `commit-message` skill).
- Tests run ONLY via `make test-*` targets.

---

### Task 1: `validate_backward_target` helper + library tests (#234 core)

**Goal:** Add the shared backward-target validator to `git-config/lib/hug-git-upstream`, TDD'd at the library layer.

**Files:**
- Modify: `git-config/lib/hug-git-upstream` (insert after `handle_standard_operation`, before the "Root Commit Operations" banner at ~:159)
- Test: `tests/lib/test_hug-upstream.bats` (new section at the end)

**Acceptance Criteria:**
- [ ] garbage target → failure with `'X' is not a valid commit`
- [ ] forward target → failure with `is ahead of HEAD by N commit(s)` and a pasteable `hug h restore <target> --<op>` hint
- [ ] diverged target → silent pass (exit 0, empty output) — sideways moves preserved
- [ ] ancestor and self targets → silent pass
- [ ] capture idiom is `local rc=0` + `offset=$(commit_offset …) || rc=$?` (assignment left of `||`); the catch-all arm is an `error`, not a bare return

**Verify:** `make test-lib TEST_FILE=test_hug-upstream.bats` → all pass (10 existing + 4 new)

**Steps:**

- [ ] **Step 1: Write the failing tests** — append to `tests/lib/test_hug-upstream.bats`:

```bash
################################################################################
# validate_backward_target: #234 — explicit targets must be valid BACKWARD moves
################################################################################
# NOTE on test layers: bats `run` DISABLES errexit, so these helper-layer tests would
# pass green even on a capture idiom broken under set -e. The mover-layer e2e tests in
# tests/unit/test_head.bats (real scripts under set -euo pipefail) are the layer that
# catches that — do not delete them in favor of these.

@test "validate_backward_target: garbage target -> 'not a valid commit', non-zero" {
  run validate_backward_target "definitely-not-a-ref" "back"
  assert_failure
  assert_output --partial "'definitely-not-a-ref' is not a valid commit"
}

@test "validate_backward_target: forward (descendant) target -> 'ahead of HEAD' + pasteable restore hint" {
  local descendant; descendant=$(git rev-parse HEAD)
  git update-ref HEAD HEAD~1                  # plumbing: HEAD back one, descendant now ahead
  run validate_backward_target "$descendant" "back"
  assert_failure
  assert_output --partial "is ahead of HEAD by 1 commit(s)"
  assert_output --partial "hug h restore $descendant --back"
}

@test "validate_backward_target: diverged target -> silent pass (sideways move preserved)" {
  git checkout -q -b diverger                 # branch at HEAD
  echo "d" > diverger.txt; git add diverger.txt; git commit -q -m "branch diverges"
  git checkout -q -                           # back to the original branch
  echo "l" > local-only.txt; git add local-only.txt; git commit -q -m "HEAD diverges"
  run validate_backward_target "diverger" "undo"
  assert_success
  [ -z "$output" ]                            # silent: today's sideways behavior, NOT an error
}

@test "validate_backward_target: ancestor and self -> silent pass" {
  run validate_backward_target "HEAD~1" "back"
  assert_success
  [ -z "$output" ]
  local self; self=$(git rev-parse HEAD)
  run validate_backward_target "$self" "back"
  assert_success
  [ -z "$output" ]
}
```

- [ ] **Step 2: Run to verify they fail** — `make test-lib TEST_FILE=test_hug-upstream.bats` → 4 failures with `command not found: validate_backward_target` (bats surfaces the missing function as failure).

- [ ] **Step 3: Implement the helper** — insert into `git-config/lib/hug-git-upstream` between `handle_standard_operation` and the Root Commit Operations banner:

```bash
# Validates an EXPLICIT target for a backward HEAD-mover (h-back / h-undo / h-rollback).
# Usage: validate_backward_target <target> <op> [<user_input>]
# Parameters:
#   $1 - resolved target (may be the raw ref if resolution failed upstream)
#   $2 - mover name for messages: "back" | "undo" | "rollback"
#   $3 - (Optional) the user's LITERAL input, quoted in error messages (defaults to $1)
#
# Contract — keep ISOMORPHIC to commit_offset's outcome table (hug-git-commit):
#   unresolvable (exit 3)   -> error "'<input>' is not a valid commit", non-zero
#   diverged     (exit 2)   -> silent pass — a valid SIDEWAYS move; today's behavior, NOT an error
#   ahead        (offset<0) -> error "…is ahead of HEAD by N commit(s)…", non-zero
#   self/ancestor (offset>=0)-> silent pass
#
# WHY this gate exists (#234): pre-fix, an unresolvable explicit target at the root commit
# was indistinguishable from the legitimate "no parent of root" case, so `hug h back garbage`
# triggered reset_root_commit — the most destructive path — on nonsense input. Callers ALSO
# tighten their root-path guard to `[[ -z "$target_arg" ]]` (defense in depth).
validate_backward_target() {
    local target="$1" op="${2:?validate_backward_target: op required}" user_input="${3:-$1}"
    local offset rc=0
    # Capture via `|| rc=$?` — the assignment MUST sit left of `||`: a bare
    # `offset=$(commit_offset …)` aborts a `set -e` caller at the assignment for exit 2/3,
    # before the dispatch below can run (same failure class as the local-x-capture masking).
    offset=$(commit_offset "$target" HEAD) || rc=$?
    case $rc in
      3) error "'$user_input' is not a valid commit" ;;
      2) return 0 ;;   # diverged: valid sideways move — today's behavior, NOT an error
      0) ;;
      # unreachable today (commit_offset's exit surface is total over {0,2,3}) — but an
      # `error`, not a bare return: a bare non-zero return would surface as a MESSAGELESS
      # errexit abort, the opposite of this batch's loud-failure promise.
      *) error "internal error: commit_offset returned unexpected status $rc for '$user_input'" ;;
    esac
    if [ "$offset" -lt 0 ]; then
        error "hug h $op moves HEAD back, but '$user_input' is ahead of HEAD by ${offset#-} commit(s) (use 'hug h restore $user_input --$op' to move forward)"
    fi
}
```

- [ ] **Step 4: Run to verify they pass** — `make test-lib TEST_FILE=test_hug-upstream.bats` → all green.

- [ ] **Step 5: Commit**

```bash
hug a git-config/lib/hug-git-upstream tests/lib/test_hug-upstream.bats
```
Message subject: `feat(lib): validate_backward_target — loud failure for garbage/forward explicit targets (#234)` with WHY/WHAT/HOW/IMPACT body (WHY: garbage at root triggered reset_root_commit; WHAT: shared commit_offset-based validator, four-outcome dispatch; HOW: `|| rc=$?` capture idiom, isomorphic contract table; IMPACT: movers wire it in the next commits).

---

### Task 2: Wire the validator into h-back + full mover-level matrix

**Goal:** Wire `validate_backward_target` into `git-h-back`, tighten the root guard, and pin the behavior change end-to-end — including FLIPPING the #229 forward-headline test (forward explicit targets now error instead of proceeding; spec §1 decision).

**Files:**
- Modify: `git-config/bin/git-h-back` (~:93-96)
- Test: `tests/unit/test_head.bats`

**Acceptance Criteria:**
- [ ] wiring line inserted after `resolve_target_with_temporal` in the non-upstream branch: `[[ -n "$target_arg" ]] && validate_backward_target "$target" "back" "$target_arg"`
- [ ] root-path guard now begins `[[ -z "$target_arg" ]] &&`
- [ ] garbage at root → loud failure, root commit intact
- [ ] `h back 1` at root → loud failure quoting the literal `'1'` (behavior change, documented)
- [ ] no-arg at root → root-recovery unchanged (existing test stays green)
- [ ] forward/descendant explicit target → loud failure pointing at restore (headline flipped)
- [ ] diverged orphan ref at root → proceeds (sideways move preserved)

**Verify:** `make test-unit TEST_FILE=test_head.bats` → all green (the suite count changes: +4 new, 1 rewritten)

**Steps:**

- [ ] **Step 1: Write/rewrite the mover-level tests** in `tests/unit/test_head.bats`.

(a) REWRITE the existing test `"hug h back <descendant>: moves HEAD FORWARD instead of no-op'ing (#229 headline)"` (~:2201) — the batch deliberately narrows this guarantee (spec §1: forward explicit targets are a direction mistake; restore is the sanctioned forward mover):

```bash
@test "hug h back <descendant>: rejected loudly, points at restore (#234 narrows the #229 headline)" {
  # Evolution: #229 made forward targets PROCEED through the movers; the #234 batch narrows
  # that — a FORWARD explicit target through a backward-NAMED mover is a direction mistake,
  # rejected loudly and pointing at restore (the sanctioned forward mover, which encodes the
  # reset mode explicitly). A silent forward move through a command named "back" surprised
  # users; restore is unambiguous.
  local descendant
  descendant=$(git rev-parse HEAD)   # capture the tip BEFORE moving — the forward target (C)
  git reset -q --hard HEAD~2         # HEAD -> A (root); tree clean, descendant is ahead of HEAD

  run env HUG_FORCE=true hug h back "$descendant"

  assert_failure
  assert_output --partial "is ahead of HEAD by 2 commit(s)"
  assert_output --partial "hug h restore"
  refute_output --partial "Already at target"
  [ "$(git rev-parse HEAD)" != "$descendant" ]   # HEAD did NOT move
}
```

(b) REWRITE the stale LESSON comment in `"hug h back recovering at root (unborn HEAD)…"` (~:2251): replace the paragraph starting "LESSON / why the input is NOT `h back 1` at a valid root: that input takes git-h-back's dedicated reset_root_commit branch and SUCCEEDS" with:

```
  # LESSON / `h back 1` at a VALID root: since the #234 batch an explicit target is validated
  # FIRST — `h back 1` (HEAD~1, unresolvable at root) fails loudly with "'1' is not a valid
  # commit" (pinned below). The root-recovery branch is now reachable ONLY with no positional
  # target (the `-z target_arg` structural guard), and the no-arg form stays pinned by
  # "hug h back: undoes root commit, files stay staged".
```

(c) APPEND new tests (same file, after the #229 enforcement section):

```bash
# ============================================================================
# #234 enforcement: explicit targets are validated — garbage/forward fail loudly,
# sideways (diverged) proceeds, root-recovery is no-arg-only
# ============================================================================

@test "hug h back <garbage> at root: loud failure, root commit intact (#234)" {
  # THE reason this batch exists: pre-fix, a garbage explicit target at root was
  # indistinguishable from "no parent of root" and triggered reset_root_commit.
  local test_repo; test_repo=$(create_test_repo)
  cd "$test_repo"
  local root_sha; root_sha=$(git rev-parse HEAD)

  run env HUG_FORCE=true hug h back definitely-not-a-ref

  assert_failure
  assert_output --partial "'definitely-not-a-ref' is not a valid commit"
  [ "$(git rev-parse HEAD)" = "$root_sha" ]   # the destructive path never ran
}

@test "hug h back 1 at root: loud failure quoting the user's literal (#234 behavior change)" {
  # HEAD~1 does not exist at root. Pre-fix this triggered root-recovery; an explicit target
  # is a user assertion, so it now fails loudly — quoting what the user TYPED ('1'), not the
  # internally-resolved HEAD~1 (the validator receives the literal input).
  local test_repo; test_repo=$(create_test_repo)
  cd "$test_repo"

  run env HUG_FORCE=true hug h back 1

  assert_failure
  assert_output --partial "'1' is not a valid commit"
}

@test "hug h back <diverged-orphan-ref> at root: silent pass, sideways move preserved (#234)" {
  # Orphan branches DO diverge from the root (no common ancestor) — the "diverged at root"
  # shape is reachable. Policy: silent pass; today's sideways preview/reset, unchanged.
  local test_repo; test_repo=$(create_test_repo)
  cd "$test_repo"
  local other_root; other_root=$(git rev-parse HEAD)
  git checkout -q --orphan sideway
  echo "s" > sideways.txt; git add sideways.txt; git commit -q -m "orphan root"

  run env HUG_FORCE=true hug h back "$other_root"

  assert_success
  [ "$(git rev-parse HEAD)" = "$other_root" ]   # sideways reset happened
}

@test "hug h back <diverged-branch>: proceeds (THE errexit-detection assertion) (#234)" {
  # CRITICAL layer: this runs the REAL mover under set -euo pipefail. A broken capture idiom
  # (offset=$(commit_offset …); rc=$?) dies silently at the assignment for exit 2; bats `run`
  # at the HELPER layer cannot catch that (run disables errexit). This assertion — diverged
  # target PROCEEDS instead of exiting silently — is the batch's only defense against a
  # regression of the capture idiom.
  create_test_repo_with_history
  git checkout -q -b advanced-branch
  echo "adv" > advanced.txt; git add advanced.txt; git commit -q -m "branch advances"
  git checkout -q -
  echo "loc" > local-advance.txt; git add local-advance.txt; git commit -q -m "HEAD advances"
  local target; target=$(git rev-parse advanced-branch)   # diverged from HEAD

  run env HUG_FORCE=true hug h back advanced-branch

  assert_success
  [ "$(git rev-parse HEAD)" = "$target" ]                 # sideways move, NOT a silent exit
}
```

- [ ] **Step 2: Run to verify the new/rewritten tests fail** — `make test-unit TEST_FILE=test_head.bats TEST_FILTER="#234"` → the four new tests fail (validator not wired); the flipped headline fails (forward still proceeds).

- [ ] **Step 3: Wire the validator** in `git-config/bin/git-h-back`. In the `else` (non-upstream) branch, after the `resolve_target_with_temporal` line (~:93), insert:

```bash
  # #234: an EXPLICIT target must be a valid BACKWARD move — garbage fails loudly (never a
  # root-recovery on nonsense input) and a forward target points at restore instead of moving
  # HEAD through a backward-named command. The default HEAD~1 is skipped by design: at root it
  # legitimately does not resolve — that unresolved default IS the root-recovery trigger below.
  [[ -n "$target_arg" ]] && validate_backward_target "$target" "back" "$target_arg"
```

and tighten the root-path guard (~:96) from

```bash
  if ! git rev-parse --verify --quiet "$target" > /dev/null 2>&1 && is_at_root_commit; then
```

to

```bash
  if [[ -z "$target_arg" ]] && ! git rev-parse --verify --quiet "$target" > /dev/null 2>&1 && is_at_root_commit; then
```

(Defense in depth: root-recovery becomes structurally unreachable for ANY explicit target, even if the validator is later refactored.)

- [ ] **Step 4: Run the whole head suite** — `make test-unit TEST_FILE=test_head.bats` → all green. If the no-arg root-recovery test ("hug h back: undoes root commit, files stay staged") fails, the `-z target_arg` clause or wiring position is wrong — fix before continuing.

- [ ] **Step 5: Commit**

```bash
hug a git-config/bin/git-h-back tests/unit/test_head.bats
```
Message subject: `fix(h-back): loud failure for garbage/forward explicit targets; root-recovery is no-arg-only (#234)` — WHY/WHAT/HOW/IMPACT body (WHY: garbage at root triggered the most destructive path; WHAT: validator wiring + `-z target_arg` guard + headline flip; HOW: validator-first + structural clause, defense in depth; IMPACT: root commit is unreachable from nonsense input).

---

### Task 3: Wire h-undo + h-rollback; sibling spot-checks; the documented everyday shape

**Goal:** Same wiring in the two sibling movers (op names `"undo"`/`"rollback"`), with spot-checks and the `hug h undo main` sideways-PROCEEDS assertion.

**Files:**
- Modify: `git-config/bin/git-h-undo` (~:103-106), `git-config/bin/git-h-rollback` (~:98-101)
- Test: `tests/unit/test_head.bats`

**Acceptance Criteria:**
- [ ] both movers carry the identical wiring with their own op literal (`"undo"` / `"rollback"`)
- [ ] both root guards carry the `[[ -z "$target_arg" ]] &&` clause
- [ ] garbage at root fails loudly for each mover (error text names the mover's own op)
- [ ] `hug h undo <advanced-branch>` (diverged) proceeds — the documented `hug h undo main` everyday shape

**Verify:** `make test-unit TEST_FILE=test_head.bats` → all green

**Steps:**

- [ ] **Step 1: Append the spot-check tests** to `tests/unit/test_head.bats`:

```bash
@test "hug h undo <garbage> at root: loud failure, mover named correctly (#234 spot-check)" {
  local test_repo; test_repo=$(create_test_repo)
  cd "$test_repo"
  run env HUG_FORCE=true hug h undo nope-ref
  assert_failure
  assert_output --partial "'nope-ref' is not a valid commit"
}

@test "hug h rollback <garbage> at root: loud failure, mover named correctly (#234 spot-check)" {
  local test_repo; test_repo=$(create_test_repo)
  cd "$test_repo"
  run env HUG_FORCE=true hug h rollback nope-ref
  assert_failure
  assert_output --partial "'nope-ref' is not a valid commit"
}

@test "hug h undo <diverged-branch>: proceeds (the documented 'hug h undo main' shape) (#234)" {
  # docs/commands/head.md ships `hug h undo main` as an everyday example; on a branch whose
  # main has advanced, the target is DIVERGED. The batch must preserve today's sideways
  # preview/reset — a silent non-zero exit here would regress the everyday shape.
  create_test_repo_with_history
  git checkout -q -b advanced-main
  echo "adv" > advanced.txt; git add advanced.txt; git commit -q -m "main advances"
  git checkout -q -
  echo "loc" > local-advance.txt; git add local-advance.txt; git commit -q -m "HEAD advances"
  local target; target=$(git rev-parse advanced-main)

  run env HUG_FORCE=true hug h undo advanced-main

  assert_success
  [ "$(git rev-parse HEAD)" = "$target" ]
}
```

- [ ] **Step 2: Run to verify they fail** — `make test-unit TEST_FILE=test_head.bats TEST_FILTER="#234 spot-check"` and `TEST_FILTER="documented"` → failures (validators not wired).

- [ ] **Step 3: Wire both movers.** In `git-config/bin/git-h-undo`, after the non-upstream `resolve_target_with_temporal` line (~:103) insert the same comment block as Task 2 Step 3 with op `"undo"`:

```bash
  [[ -n "$target_arg" ]] && validate_backward_target "$target" "undo" "$target_arg"
```

and tighten its root guard (~:106) to begin `[[ -z "$target_arg" ]] &&`. Apply the identical pair to `git-config/bin/git-h-rollback` (~:98 wiring with `"rollback"`, ~:101 guard).

- [ ] **Step 4: Run the whole head suite** — `make test-unit TEST_FILE=test_head.bats` → all green (existing no-arg root tests for undo/rollback stay green).

- [ ] **Step 5: Commit**

```bash
hug a git-config/bin/git-h-undo git-config/bin/git-h-rollback tests/unit/test_head.bats
```
Message subject: `fix(h-undo,h-rollback): same explicit-target validation as h-back (#234)`.

---

### Task 4: Truthful sync-state messaging in handle_upstream_operation (#237)

**Goal:** In the `== 0` branch, distinguish aligned ("Already synced", unchanged) from behind ("HEAD is N commit(s) behind upstream … pull or rebase") via `commit_offset` — its first production caller.

**Files:**
- Modify: `git-config/lib/hug-git-upstream` (`handle_upstream_operation` `== 0` branch, ~:51-54)
- Test: `tests/lib/test_hug-upstream.bats`

**Acceptance Criteria:**
- [ ] aligned → `Already synced to upstream (<short>).` + exit 0 (unchanged text)
- [ ] behind by N → `Nothing to move: HEAD is N commit(s) behind upstream (<branch>). Pull or rebase to catch up.` + exit 0
- [ ] branch computes `target_short`/`upstream_branch` locally (split declaration/assignment); no unbound variables under `set -u`
- [ ] all five existing "Already synced" assertions stay green (workflows ×4, test_head ×1)

**Verify:** `make test-lib TEST_FILE=test_hug-upstream.bats` + `make test-integration TEST_FILE=test_workflows.bats` + `make test-unit TEST_FILE=test_head.bats TEST_FILTER="synced"`

**Steps:**

- [ ] **Step 1: Write the failing tests** — append to `tests/lib/test_hug-upstream.bats`:

```bash
################################################################################
# handle_upstream_operation: truthful aligned-vs-behind messaging (#237)
################################################################################
# count(target..HEAD) == 0 means "not AHEAD" — also true when HEAD is BEHIND upstream.
# Diverged cannot reach the branch (diverged ⇒ ahead > 0), so it is a clean 2-state split.

# Shared fixture: repo + bare origin + push + attached upstream (HEAD synced with origin).
setup_synced_upstream() {
  local branch; branch=$(git branch --show-current)
  REMOTE_REPO=$(mktemp -d)/origin.git
  git init --bare -q "$REMOTE_REPO"
  git remote add origin "$REMOTE_REPO"
  git push -q origin "$branch"
  git branch --set-upstream-to="origin/$branch" >&2
}

# Advances origin by N empty commits (via a clone), leaving HEAD BEHIND upstream.
advance_remote() {
  local n="$1" clone_dir
  clone_dir=$(mktemp -d)/clone
  git clone -q "$REMOTE_REPO" "$clone_dir"
  local i=1
  while [ "$i" -le "$n" ]; do
    git -C "$clone_dir" -c user.email=test@test -c user.name=test \
        commit -q --allow-empty -m "remote advance $i"
    i=$((i + 1))
  done
  git -C "$clone_dir" push -q origin HEAD
}

@test "handle_upstream_operation: aligned -> 'Already synced' (unchanged), exit 0 (#237)" {
  create_test_repo_with_history
  setup_synced_upstream
  run handle_upstream_operation "moving back" "warn" "back" "discards local-only commits"
  assert_success
  assert_output --partial "Already synced to upstream"
}

@test "handle_upstream_operation: HEAD BEHIND upstream -> truthful behind message, exit 0 (#237)" {
  create_test_repo_with_history
  setup_synced_upstream
  advance_remote 2
  run handle_upstream_operation "moving back" "warn" "back" "discards local-only commits"
  assert_success
  assert_output --partial "Nothing to move: HEAD is 2 commit(s) behind upstream"
  assert_output --partial "Pull or rebase to catch up"
  refute_output --partial "Already synced"
}
```

- [ ] **Step 2: Run to verify the behind test fails** — `make test-lib TEST_FILE=test_hug-upstream.bats TEST_FILTER="behind upstream"` → fails (still prints "Already synced").

- [ ] **Step 3: Replace the `== 0` branch** in `handle_upstream_operation` (~:51-54):

```bash
    if [ "$local_commits" -eq 0 ]; then
        # == 0 means "not AHEAD": aligned OR behind (diverged is unreachable here —
        # diverged ⇒ ahead > 0). commit_offset distinguishes exactly these two states;
        # this is its first production caller (#238).
        local offset
        offset=$(commit_offset "$target" HEAD) || return 1
        local target_short
        target_short=$(git rev-parse --short "$target")
        if [ "$offset" -eq 0 ]; then
            info "Already synced to upstream ($target_short)."
            exit 0
        fi
        local upstream_branch
        # Parity with the preview block's computation; the fallback cannot actually fire
        # here (get_upstream_commit already resolved @{u}, which requires an attached HEAD).
        upstream_branch=$(git for-each-ref --format='%(upstream:short)' "$(git symbolic-ref HEAD)" 2>/dev/null || echo "upstream")
        info "Nothing to move: HEAD is ${offset#-} commit(s) behind upstream ($upstream_branch). Pull or rebase to catch up."
        exit 0
    fi
```

- [ ] **Step 4: Run all affected suites** — `make test-lib TEST_FILE=test_hug-upstream.bats` (both new tests green) + `make test-integration TEST_FILE=test_workflows.bats` (the 4 synced assertions green) + `make test-unit TEST_FILE=test_head.bats TEST_FILTER="synced"` (the rewind -u assertion green).

- [ ] **Step 5: Commit**

```bash
hug a git-config/lib/hug-git-upstream tests/lib/test_hug-upstream.bats
```
Message subject: `fix(upstream): report 'behind upstream' truthfully instead of 'Already synced' (#237)`.

---

### Task 5: Hygiene trio — pin both guards (#235), README set-e axes (#236), oxymoron (#239)

**Goal:** Pin the load-bearing `|| return 1` guards with function-shadowing stub tests; correct the README's errexit attribution with the two-axis truth; fix the "STRICT-display twin" oxymoron.

**Files:**
- Test: `tests/lib/test_hug-upstream.bats`
- Modify: `git-config/lib/README.md` (~:458-461), `git-config/lib/hug-git-commit` (:237)

**Acceptance Criteria:**
- [ ] stub test 1: with `count_commits_in_range` shadowed to `return 1`, `handle_upstream_operation` fails non-zero with NO preview output; deleting the `|| return 1` at hug-git-upstream:49 turns this test red (verify by temporary removal, then restore)
- [ ] stub test 2 (symmetry): with `commit_offset` shadowed to `return 1` in a synced repo, the helper fails non-zero with neither synced nor behind message; the new Task-4 guard is pinned
- [ ] README comment attributes errexit suspension to BOTH axes (mid-body `$(…)` never fires; functions called from a `||` position run errexit-disabled) — not the false blanket "capture does not suspend errexit"
- [ ] `grep -q 'STRICT-display' git-config/` fails (oxymoron gone); the "NEVER use for a branching or alignment decision" guidance intact

**Verify:** `make test-lib TEST_FILE=test_hug-upstream.bats` + the greps above

**Steps:**

- [ ] **Step 1: Write the stub tests** — append to `tests/lib/test_hug-upstream.bats`:

```bash
################################################################################
# #235: pin the load-bearing `|| return 1` guards with function-shadowing stubs
################################################################################
# WHY stubs: the guards cannot fail naturally (a resolved upstream always counts), which is
# exactly why they were untested — deleting them keeps every natural-path test green. Bash
# redefinition shadows the library function for `run`'s subshell. If a guard is removed,
# the stub's failure falls through into the preview/message blocks and these tests go red.

@test "#235: count guard pinned — failing count_commits_in_range -> non-zero, no preview" {
  # Pins the guard at hug-git-upstream:49 (NOT the get_upstream_commit guard at :41).
  create_test_repo_with_history
  setup_synced_upstream
  advance_remote 1
  count_commits_in_range() { return 1; }
  run handle_upstream_operation "moving back" "warn" "back" "discards local-only commits"
  assert_failure
  refute_output --partial "Commits to be affected"
}

@test "#235 symmetry: commit_offset guard pinned — failing offset in the ==0 branch -> non-zero" {
  create_test_repo_with_history
  setup_synced_upstream                    # count is 0 -> the ==0 branch executes
  commit_offset() { return 1; }
  run handle_upstream_operation "moving back" "warn" "back" "discards local-only commits"
  assert_failure
  refute_output --partial "Already synced"
  refute_output --partial "behind upstream"
}
```

- [ ] **Step 2: Verify they pass, then prove discrimination** — run the suite (green). Then temporarily delete `|| return 1` from the count line (~:49), re-run → stub test 1 RED; restore the guard, re-run → green. (This proves the test pins the guard; do NOT skip the restore.)

- [ ] **Step 3: Fix the README attribution** — in `git-config/lib/README.md`, replace the line (~:460):

```
# (callers use `|| exit $?`) -- set -e is suspended inside $(…):
```

with:

```
# (callers use `|| exit $?`). WHY the explicit `|| return 1` below is load-bearing, two
# axes: errexit never fires MID-BODY inside $(…) — only the substitution's FINAL status
# propagates, via the assignment — and errexit is additionally suspended throughout any
# function called from a `||` position, which is exactly how every caller invokes this
# helper. Its internal `|| return 1` guards are therefore the ONLY failure-propagation path:
```

- [ ] **Step 4: Fix the oxymoron** — in `git-config/lib/hug-git-commit` (:237), replace:

```
# STRICT-display twin of count_commits_in_range.
```

with:

```
# Display-only, failure-tolerant twin of count_commits_in_range.
```

Leave the surrounding "NEVER use this for a branching or alignment decision" block (:240-244) verbatim.

- [ ] **Step 5: Run + commit** — `make test-lib TEST_FILE=test_hug-upstream.bats` green, then:

```bash
hug a tests/lib/test_hug-upstream.bats git-config/lib/README.md git-config/lib/hug-git-commit
```
Message subject: `test+docs(lib): pin the || return 1 guards; correct set-e attribution; fix oxymoron (#235/#236/#239)`.

---

### Task 6: Perimeter docs — head.md rewrites + CHANGELOG (spec §6/§7)

**Goal:** Bring the user-facing docs into the change-set: head.md's two stale passages about forward recovery, and the CHANGELOG entries (including the duplicate-`[Unreleased]` wart).

**Files:**
- Modify: `docs/commands/head.md` (~:125, ~:155-165), `CHANGELOG.md` (:5-6, :71)

**Acceptance Criteria:**
- [ ] head.md:125 no longer claims re-invoking the mover "would short-circuit on the aligned-target check"
- [ ] head.md's "Why a dedicated recovery command?" rationale states the post-batch truth (backward movers reject descendant targets loudly; restore is the sanctioned forward mover); the two design-decision bullets stay (they remain true)
- [ ] CHANGELOG top `[Unreleased]` gains the batch's three entries
- [ ] exactly ONE `## [Unreleased]` header remains; the orphan block's entries are merged under `[1.3.0]`

**Verify:** `grep -c '^## \[Unreleased\]' CHANGELOG.md` → 1 · `grep -q 'short-circuit on the aligned-target check' docs/commands/head.md` fails · `make docs-build` succeeds

**Steps:**

- [ ] **Step 1: Rewrite head.md:125** — in the `hug h restore` Description bullet, replace:

```
Unlike re-invoking the mover (which would short-circuit on the aligned-target check), `hug h restore` uses exact-SHA equality for its no-op test, allowing it to move HEAD **forward** to a descendant commit.
```

with:

```
Unlike re-invoking the mover (backward movers reject a forward target loudly — `hug h back <descendant>` errors and points here), `hug h restore` is the sanctioned forward mover: its no-op test is exact-SHA equality, never a range count, so it can move HEAD **forward** to a descendant commit.
```

- [ ] **Step 2: Rewrite the rationale paragraph** (~:159, under "Why a dedicated recovery command?") — replace:

```
Re-invoking a HEAD-mover (e.g., `hug h back abc123`) to recover forward **does not work** -- the mover's aligned-target check (`count_commits_in_range target HEAD == 0`) short-circuits to a no-op whenever the target is a descendant of HEAD. Since the pre-op HEAD is always ahead after a successful backward move, any re-invocation of the mover silently exits 0 without moving HEAD.
```

with:

```
Re-invoking a HEAD-mover (e.g., `hug h back abc123`) to recover forward **does not work** — backward movers validate direction: a descendant target is rejected with a loud error ("…is ahead of HEAD… use `hug h restore <target> --<op>`"), because a forward move through a backward-named command is a direction mistake. Since the pre-op HEAD is always ahead after a successful backward move, forward recovery goes through `hug h restore`.
```

- [ ] **Step 3: CHANGELOG entries** — under the top `## [Unreleased]` (:5), add:

```markdown
### Fixed

- **`h back`/`h undo`/`h rollback` reject invalid and forward explicit targets loudly** — a garbage target could previously trigger the root-recovery path (undoing the root commit on nonsense input), and a forward target moved HEAD through a backward-named command; both now error, with forward targets pointing at `hug h restore <target> --<op>` (elifarley/hug-scm#234). Root-recovery is now reachable only with no positional target.
- **`commit_offset`'s Usage docstring corrected to the errexit-safe capture idiom** (`offset=$(…) || rc=$?`) — the previous form (capture, then read the status on the next line) is dead code under `set -e` for exactly the exit codes the dispatch exists to distinguish (discovered while specifying #234's gate).

### Changed

- **`-u` operations report "N commit(s) behind upstream" instead of the false "Already synced" when HEAD is behind upstream** — aligned keeps its message; the exit-0 no-op contract is unchanged (elifarley/hug-scm#237).
```

- [ ] **Step 4: Merge the orphan block** — the second `## [Unreleased]` (~:71) holds worktree-family entries that shipped before 1.3.0 was cut (verify: `git log --format='%ad' --date=short -1 4b81519` prints a date ≤ 2026-07-15). Delete that `## [Unreleased]` header line so its Fixed/Changed/Added subsections fall under the `## [1.3.0] - 2026-07-15` section above. Confirm `grep -c '^## \[Unreleased\]' CHANGELOG.md` prints 1.

- [ ] **Step 5: Build docs + commit** — `make docs-build` succeeds, then:

```bash
hug a docs/commands/head.md CHANGELOG.md
```
Message subject: `docs: head.md forward-recovery truth + CHANGELOG entries for the correctness batch (#234/#237)`.

---

### Task 7: Final verification gate — sanitize, full suite, canaries, smoke

**Goal:** The full quality gate proving the batch ships green with no leakage or residue.

**Files:** (verification only; if sanitize reformats anything, fold it into the relevant task's commit via `hug cmod --no-edit` after `hug a`)

**Acceptance Criteria:**
- [ ] `make sanitize` passes
- [ ] `make test` passes except the two documented pre-existing environmental failures (test_hug-file-input `.env` gitignore; `hug c` git-identity sanitization) — both reproduce identically on `main`
- [ ] canary: `grep -rn '|| echo 0' git-config/ | wc -l` → 1
- [ ] no stale names: `grep -rnE 'is_aligned|commits_ahead_behind' git-config/ tests/` → empty
- [ ] `commit_offset` docstring carries the errexit-safe idiom (already committed in `afb753e` — verify-only): `grep -q 'offset=$(commit_offset "target" HEAD) || rc=$?' git-config/lib/hug-git-commit`
- [ ] head.md stale phrasing gone: `grep -q 'short-circuit on the aligned-target check' docs/commands/head.md` → non-zero exit
- [ ] Phase-2 absent: `grep -rnE 'direction_between|report_head_move|HUG_HEAD_MOVE_DIRECTION' git-config/` → empty
- [ ] smoke: in a scratch repo, `hug h back garbage` at root fails loudly with the root commit intact

**Verify:** the commands above, in order

**Steps:**

- [ ] **Step 1:** `make sanitize` — if it reformats anything, `hug a <files>` and fold into the originating commit (`hug cmod --no-edit` only if it is the tip; otherwise leave staged and note it).
- [ ] **Step 2:** `make test` — full suite; compare failures against the two documented environmental ones (verify they reproduce on main if in doubt).
- [ ] **Step 3:** Run the four greps above; each must match its expectation exactly.
- [ ] **Step 4:** Smoke — `SCRATCH=$(mktemp -d) && git init -q "$SCRATCH" && cd "$SCRATCH" && echo x > f && git add f && git -c user.email=s@s -c user.name=s commit -q -m root`, then run `env HUG_FORCE=true hug h back garbage` → expect non-zero exit and `'garbage' is not a valid commit`; confirm `git rev-parse HEAD` still resolves.
- [ ] **Step 5:** No commit needed unless Step 1 produced changes. Report the gate results.

---

## Task dependencies

```
T1 ──> T2 ──> T3 ──┐
T4 ──> T5          ├──> T6 ──> T7
       (T5 also ───┘ via T4's guard)
```

T4 is independent of T1–T3 and may run in parallel with T2/T3.
