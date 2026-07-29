# HEAD-mover confirmation tiers + recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved design spec (`docs/superpowers/specs/2026-07-28-head-movers-tier-and-recovery-design-v2.md`, PR elifarley/hug-scm#231): state-determined confirmation tiers + a `hug h restore` recovery primitive across the six HEAD-mover commands.

**Architecture:** Tier ⟺ recovery-completeness (warn iff a complete recovery command exists). One shared `tier` parameter on `handle_upstream_operation`; a new gate-less `git-h-restore` whose op-named flag (`--back|--undo|--rollback|--rewind`) selects the reset mode; recovery hints emitted by every warn-tier mover; two dirty predicates over one algorithm (`has_uncommitted_tracked_changes` tracked-only, `has_untracked_or_pending_changes` renamed). The empty-target guard is added to every upstream call site.

**Tech Stack:** Bash, BATS (bats-support/bats-assert/bats-file), git plumbing (`reset --soft|--mixed|--keep|--hard`, `rev-list`, `write-tree`). Tests run via `make` targets (never bare `bats`/`pytest`).

**Spec anchor baseline:** `origin/main` @ `1296dbf`; the branch is rebased onto it, so all `file:line` anchors in the spec match the working tree.

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `git-config/lib/hug-git-state` | Dirty-state predicates | Modify: add `has_uncommitted_tracked_changes`; rename `has_pending_changes` → `has_untracked_or_pending_changes` |
| `git-config/lib/hug-git-upstream` | Shared upstream/standard op helpers + recovery hint | Modify: `handle_upstream_operation` gains `tier` param; `handle_standard_operation` aligned-message uses tracked-only predicate; add `emit_head_recovery_hint` |
| `git-config/bin/git-h-restore` | The recovery primitive (`hug h restore`) | Create |
| `git-config/bin/git-h-back` / `git-h-undo` / `git-h-rollback` / `git-h-rewind` / `git-h-squash` | The five warn-tier movers | Modify: tier decl + empty-target guard + hint emission + `RESTORE` help section + rename usages |
| `git-config/bin/git-cmv` | The danger-tier mover | Modify: danger tier + unified clean-gate + "not restorable" help |
| `git-config/.gitconfig` | Command aliases | Modify: register `restore = h restore` |
| `git-config/completions/*` | Shell completion | Modify: add `h restore` |
| `git-config/lib/README.md` | Library docs | Modify: predicate model + `h-restore` + rename |
| `tests/lib/test_hug-git-state.bats` | Predicate tests | Modify: rename usages (11) + new predicate tests |
| `tests/unit/test_h_restore.bats` | `restore` unit tests | Create |
| `tests/unit/test_head.bats` | h* command tests | Modify: tier/guard/hint/RESTORE tests for the five movers |
| `tests/unit/test_commit.bats` | cmv tests | Modify: danger-tier tests |
| `tests/integration/test_workflows.bats` | End-to-end workflows | Modify: op→restore recovery cycles, synced-upstream guard |
| `docs/commands/head.md` | User docs for h* commands | Modify: `h restore`, `RESTORE` sections, `h-rewind` clean/dirty |

**Decomposition rationale:** Phase 1 (predicates) is the §10 prerequisite that the §9 sign-off depends on, so it lands first. Phase 2 is shared plumbing. Phase 3 is the standalone `restore` primitive. Phase 4 migrates each command (one task each; they change together with their tests). Phase 5 is integration + docs.

---

## Phase 1 — Predicate foundation (§10 prerequisite)

### Task 1: Add `has_uncommitted_tracked_changes`

**Goal:** A tracked-only dirty predicate (staged + unstaged, untracked excluded) for every safety/tier decision.

**Files:**
- Modify: `git-config/lib/hug-git-state` (after `get_dirty_files`, ~line 116)
- Test: `tests/lib/test_hug-git-state.bats`

**Acceptance Criteria:**
- [ ] `has_uncommitted_tracked_changes` returns 0 for staged-only, unstaged-only, and staged+unstaged trees.
- [ ] Returns 1 for a clean tree and for an untracked-only tree (untracked excluded).
- [ ] It is a thin boolean over the existing `get_dirty_files` (no new git invocation).

**Verify:** `make test-lib TEST_FILE=test_hug-git-state.bats TEST_FILTER="has_uncommitted_tracked_changes"` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing tests** (append to `tests/lib/test_hug-git-state.bats`):

```bash
################################################################################
# has_uncommitted_tracked_changes TESTS
################################################################################

@test "has_uncommitted_tracked_changes: clean repo → false" {
  echo "test" > file.txt && git add file.txt && git commit -q -m "c1"
  run has_uncommitted_tracked_changes
  assert_failure
}

@test "has_uncommitted_tracked_changes: unstaged tracked change → true" {
  echo "test" > file.txt && git add file.txt && git commit -q -m "c1"
  echo "more" >> file.txt
  run has_uncommitted_tracked_changes
  assert_success
}

@test "has_uncommitted_tracked_changes: staged change → true" {
  echo "test" > file.txt && git add file.txt && git commit -q -m "c1"
  echo "more" >> file.txt && git add file.txt
  run has_uncommitted_tracked_changes
  assert_success
}

@test "has_uncommitted_tracked_changes: untracked-only → false (excluded)" {
  echo "test" > file.txt && git add file.txt && git commit -q -m "c1"
  echo "untracked" > newfile.txt
  run has_uncommitted_tracked_changes
  assert_failure
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test-lib TEST_FILE=test_hug-git-state.bats TEST_FILTER="has_uncommitted_tracked_changes"`
Expected: FAIL (command not found).

- [ ] **Step 3: Implement** (in `git-config/lib/hug-git-state`, after `get_dirty_files`):

```bash
# Returns 0 if there are uncommitted TRACKED changes (staged or unstaged), 1 otherwise.
# Untracked files are deliberately EXCLUDED: no reset mode (--soft/--mixed/--keep/--hard)
# touches untracked files, so they are irrelevant to the safety/tier decisions that use this
# predicate. Tracked-only by construction — get_dirty_files uses git diff, which never
# reports untracked. This is the single tracked-dirty algorithm; do not add a parallel check.
has_uncommitted_tracked_changes() { [ -n "$(get_dirty_files)" ]; }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `make test-lib TEST_FILE=test_hug-git-state.bats TEST_FILTER="has_uncommitted_tracked_changes"`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
hug a && hug c -m "feat(lib): add has_uncommitted_tracked_changes (tracked-only dirty predicate)"
```

---

### Task 2: Rename `has_pending_changes` → `has_untracked_or_pending_changes`

**Goal:** Make the untracked-inclusion explicit in the name (behavior unchanged); update every caller, test, and doc.

**Files:**
- Modify: `git-config/lib/hug-git-state` (the function definition, ~line 22, and its doc comment)
- Modify: all callers: `git-config/bin/git-caa:85`, `git-config/bin/git-w-wip:111`, `git-config/bin/git-rb:138`, `git-config/lib/hug-git-upstream:99` (this last one is re-pointed in Task 3, but rename it here too)
- Modify: `tests/lib/test_hug-git-state.bats` (11 occurrences), `tests/lib/test_hug-git-kit.bats:33`, `git-config/lib/README.md:95`

**Acceptance Criteria:**
- [ ] No `has_pending_changes` token remains anywhere in `git-config/` or `tests/` (verify with grep).
- [ ] `has_untracked_or_pending_changes` keeps the exact body (the `git status --porcelain=2` capture incl. its SIGPIPE comment).
- [ ] The full existing suite still passes (behavior preserved).

**Verify:**
- `grep -rn 'has_pending_changes' git-config/ tests/` → no output.
- `make test-lib` → all pass.

**Steps:**

- [ ] **Step 1: Rename the definition** in `git-config/lib/hug-git-state`. Change the function name and update its doc comment to state it includes untracked files:

```bash
# Returns 0 if there is ANY pending change: staged, unstaged-tracked, OR untracked.
# (Renamed from has_pending_changes to make the untracked-inclusion explicit — the bare name
# let callers conflate it with tracked-only dirty.) For commands that act on everything
# (caa = git add -A; w-wip = save-all-work). Safety/tier decisions must use
# has_uncommitted_tracked_changes instead — reset never touches untracked files.
has_untracked_or_pending_changes() {
  # ... body UNCHANGED (the git status --porcelain=2 capture-then-filter, hug-git-state:23-31) ...
}
```

- [ ] **Step 2: Update the four callers** — replace `has_pending_changes` with `has_untracked_or_pending_changes` at `git-caa:85`, `git-w-wip:111`, `git-rb:138`, `hug-git-upstream:99`. (Do NOT change behavior; Task 3 re-points `:99` to the tracked predicate.)

- [ ] **Step 3: Update tests and docs** — rename all 11 occurrences in `test_hug-git-state.bats` (including the test names), the existence assertion in `test_hug-git-kit.bats:33`, and the README:95 bullet.

- [ ] **Step 4: Verify no token remains and suite is green**

Run: `grep -rn 'has_pending_changes' git-config/ tests/` (expect no output) then `make test-lib` (expect all pass).

- [ ] **Step 5: Commit**

```bash
hug a && hug c -m "refactor(lib): rename has_pending_changes → has_untracked_or_pending_changes (untracked-inclusion explicit)"
```

---

### Task 3: Fix `handle_standard_operation`'s aligned-target message (tracked-only)

**Goal:** The "local tracked changes will be reset" message must key on the tracked-only predicate, so an untracked-only tree no longer triggers it (the latent lie from spec §10).

**Files:**
- Modify: `git-config/lib/hug-git-upstream:99`
- Test: `tests/lib/test_hug-upstream.bats` (or the file that tests `handle_standard_operation`; create a focused test if none exists)

**Acceptance Criteria:**
- [ ] Aligned target + untracked-only tree → "Already at target", exit 0 (no "tracked changes will be reset" message).
- [ ] Aligned target + tracked dirty tree (with `skip_when_aligned=false`) → still prints "local tracked changes will be reset".

**Verify:** `make test-lib TEST_FILE=test_hug-upstream.bats TEST_FILTER="aligned"` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing tests:**

```bash
@test "handle_standard_operation: aligned + untracked-only → 'Already at target' (no tracked-reset message)" {
  create_test_repo_with_history
  git checkout -q -b feature            # aligned with its own tip
  echo "note" > untracked.txt           # untracked only
  run handle_standard_operation "moving" "$(git rev-parse HEAD)" true
  assert_success
  assert_output --partial "Already at target"
  refute_output --partial "tracked changes will be reset"
}

@test "handle_standard_operation: aligned + tracked-dirty, skip=false → tracked-reset message" {
  create_test_repo_with_history
  echo "edit" >> feature1.txt           # tracked, unstaged
  run handle_standard_operation "moving" "$(git rev-parse HEAD)" false
  assert_output --partial "local tracked changes will be reset"
}
```

- [ ] **Step 2: Run to verify failure** (the first test currently fails: untracked-only triggers the tracked-reset message).

- [ ] **Step 3: Implement** — at `hug-git-upstream:99`, change `! has_pending_changes` (now `! has_untracked_or_pending_changes`) to `! has_uncommitted_tracked_changes`:

```bash
    if [[ "$skip_when_aligned" == true ]] || ! has_uncommitted_tracked_changes; then
        info "Already at target $(git rev-parse --short "$target"). No action taken."
        exit 0
    fi
```

- [ ] **Step 4: Run to verify pass.**

- [ ] **Step 5: Commit**

```bash
hug a && hug c -m "fix(lib): aligned-target message keys on tracked-only predicate (no lie on untracked-only trees)"
```

---

### Task 4: Unify `cmv`'s clean-gate onto the tracked predicate

**Goal:** `cmv`'s pre-`--hard` clean-gate uses the same tracked-only algorithm as every other safety decision.

**Files:**
- Modify: `git-config/bin/git-cmv:130`
- Test: `tests/unit/test_commit.bats`

**Acceptance Criteria:**
- [ ] `cmv` with staged or unstaged tracked changes still refuses (gate fires).
- [ ] `cmv` with untracked-only files proceeds past the gate (untracked is irrelevant to `reset --hard`).

**Verify:** `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="cmv"` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing test** (untracked-only currently refused):

```bash
@test "cmv: untracked-only tree passes the clean-gate (reset --hard ignores untracked)" {
  create_test_repo_with_history
  echo "untracked" > scratch.txt
  run hug cmv 1 newbranch --new --force
  assert_success
}
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement** — at `git-cmv:130`, replace `if has_staged_changes || has_unstaged_changes; then` with the unified predicate:

```bash
if has_uncommitted_tracked_changes; then
```

- [ ] **Step 4: Run to verify pass** (tracked-dirty refusal tests still pass; untracked-only now proceeds).

- [ ] **Step 5: Commit**

```bash
hug a && hug c -m "refactor(cmv): unify clean-gate onto has_uncommitted_tracked_changes"
```

---

## Phase 2 — Shared plumbing

### Task 5: `handle_upstream_operation` gains a required `tier` parameter

**Goal:** The upstream helper confirms at the caller's tier (warn/danger) instead of hardcoded warn (the inverted-gradient root, spec §7 Step 1).

**Files:**
- Modify: `git-config/lib/hug-git-upstream` (`handle_upstream_operation`, ~lines 33-72)
- Test: `tests/lib/test_hug-upstream.bats`

**Acceptance Criteria:**
- [ ] `tier` is `${2:?}`-required (missing tier is a hard error, not a silent warn).
- [ ] `tier=danger` calls `prompt_confirm_danger "$action_word" "$danger_reason"`; `tier=warn` calls `prompt_confirm_warn`.
- [ ] The confirmation stays inside the existing `HUG_QUIET` block (quiet still skips preview+confirm together).
- [ ] `HUG_QUIET=T` still skips confirmation.

**Verify:** `make test-lib TEST_FILE=test_hug-upstream.bats TEST_FILTER="tier"` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing tests:**

```bash
@test "handle_upstream_operation: missing tier arg is a hard error" {
  create_test_repo_with_history
  run handle_upstream_operation "moving"     # only the verb, no tier
  assert_failure
}

@test "handle_upstream_operation: tier=warn auto-confirms under -y" {
  create_test_repo_with_history
  git checkout -q -b feature && echo x >> feature1.txt && git commit -qam "ahead"
  run env HUG_YES=1 handle_upstream_operation "moving" warn "move" "reason"
  assert_success
}

@test "handle_upstream_operation: tier=danger refuses -y (exit 3)" {
  create_test_repo_with_history
  git checkout -q -b feature && echo x >> feature1.txt && git commit -qam "ahead"
  run env HUG_YES=1 handle_upstream_operation "moving" danger "move" "irreversible"
  assert_failure
  [ "$status" -eq 3 ]
}
```

- [ ] **Step 2: Run to verify failure** (current signature is 1-arg, hardcoded warn).

- [ ] **Step 3: Implement** (replace the hardcoded `prompt_confirm_warn` per spec §7 Step 1):

```bash
handle_upstream_operation() {
  local action_name="$1" tier="${2:?handle_upstream_operation requires a confirmation tier}"
  local action_word="$3" danger_reason="${4:-}"
  # ... existing validation + preview (current lines 33-68) unchanged ...
  if [[ ${HUG_QUIET:-} != T ]]; then
    # ... existing preview output ...
    case "$tier" in
      danger) prompt_confirm_danger "$action_word" "$danger_reason" ;;
      warn)   prompt_confirm_warn   "Proceed with $action_name to upstream? [y/N]: " ;;
      *)      error "Unknown confirmation tier '$tier' for upstream operation '$action_name'." ;;
    esac
  fi
  echo "$target"
}
```

- [ ] **Step 4: Run to verify pass.** (Note: until Tasks 9-14 update callers, existing callers still pass 1 arg; update them in their own tasks. Temporarily, callers may fail — sequence Task 5 immediately before 9-14, or add the extra args to callers in the same commit if the suite must stay green between tasks.)

- [ ] **Step 5: Commit**

```bash
hug a && hug c -m "feat(lib): handle_upstream_operation takes a required confirmation tier (warn/danger)"
```

---

### Task 6: Add `emit_head_recovery_hint` helper

**Goal:** One quiet-aware helper that prints the recovery command, templated from the caller's op name (spec §7 Step 4b).

**Files:**
- Modify: `git-config/lib/hug-git-upstream` (append the helper)
- Test: `tests/lib/test_hug-upstream.bats`

**Acceptance Criteria:**
- [ ] Prints `ℹ️  HEAD moved. Recover with:\n    hug h restore <SHA> --<op> -y` to stderr.
- [ ] Suppressed under `HUG_QUIET=T` (prints nothing).
- [ ] Both args required (empty arg is an error).

**Verify:** `make test-lib TEST_FILE=test_hug-upstream.bats TEST_FILTER="recovery_hint"` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing tests:**

```bash
@test "emit_head_recovery_hint: prints the restore command to stderr" {
  run emit_head_recovery_hint "abc1234" "back"
  assert_output --partial "hug h restore abc1234 --back -y"
}

@test "emit_head_recovery_hint: suppressed under HUG_QUIET=T" {
  run env HUG_QUIET=T emit_head_recovery_hint "abc1234" "back"
  assert_output ""
}
```

- [ ] **Step 2: Run to verify failure** (function not found).

- [ ] **Step 3: Implement** (append to `git-config/lib/hug-git-upstream`):

```bash
# Prints the recovery hint to stderr, templated from the caller's own op name (no hand-built
# strings, no dead parameter). <op> ∈ back|undo|rollback|rewind. Called AFTER the op succeeds,
# so the SHA is final. Suppressed under HUG_QUIET (human-facing chatter — mirrors gum_log).
emit_head_recovery_hint() {
  local pre_op_head="${1:?}" op="${2:?}"
  test "${HUG_QUIET:-}" && return 0
  printf '\nℹ️  HEAD moved. Recover with:\n    hug h restore %s --%s -y\n' \
    "$pre_op_head" "$op" >&2
}
```

- [ ] **Step 4: Run to verify pass.**

- [ ] **Step 5: Commit**

```bash
hug a && hug c -m "feat(lib): add emit_head_recovery_hint (quiet-aware recovery hint helper)"
```

---

## Phase 3 — The `restore` primitive

### Task 7: `git-h-restore` core (op→mode table, exact-SHA no-op, forward reset) + registration

**Goal:** The recovery primitive: a gate-less reset whose op-named flag selects the mode, no-op only on exact SHA equality, that moves forward to a descendant (spec §7 Step 4a).

**Files:**
- Create: `git-config/bin/git-h-restore` (executable)
- Create: `tests/unit/test_h_restore.bats`
- Modify: `git-config/.gitconfig` (alias `restore = h restore`, mirror `back = h back` at :135)
- Modify: `git-config/completions/*` (add `h restore`, mirror the `h back` entries)

**Acceptance Criteria:**
- [ ] `hug h restore <SHA> --back` does `reset --soft`; `--undo` → `--mixed`; `--rollback` → `--keep`; `--rewind` → `--hard`.
- [ ] Exact-SHA target == HEAD → "Already at …", exit 0, HEAD unchanged.
- [ ] Forward (descendant) target → HEAD moves (does NOT no-op). This is the regression the primitive exists to fix.
- [ ] `hug h restore` is a registered, completable command.

**Verify:** `make test-unit TEST_FILE=test_h_restore.bats` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing tests** (`tests/unit/test_h_restore.bats`):

```bash
#!/usr/bin/env bats
load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"
}
teardown() { cleanup_test_repo; }

@test "restore --back is a soft reset (changes stay staged)" {
  original_head=$(git rev-parse HEAD)
  hug h back 1 --force                       # HEAD back 1, changes staged
  run hug h restore "$original_head" --back -y
  assert_success
  [ "$(git rev-parse HEAD)" = "$original_head" ]
}

@test "restore: exact-SHA target == HEAD is a true no-op" {
  run hug h restore "$(git rev-parse HEAD)" --back -y
  assert_success
  assert_output --partial "Already at"
}

@test "restore: forward (descendant) target MOVES HEAD (no short-circuit no-op)" {
  hug h back 2 --force                        # HEAD now 2 behind
  target=$(git rev-parse HEAD)
  ahead=$(git rev-parse "HEAD@{1}")           # a descendant of current HEAD
  run hug h restore "$ahead" --back -y
  assert_success
  [ "$(git rev-parse HEAD)" = "$ahead" ]      # moved forward — NOT 'Already at'
  refute_output --partial "Already at"
}

@test "restore --rewind is a hard reset" {
  hug h rewind 1 --force
  target=$(git rev-parse "HEAD@{1}")
  run hug h restore "$target" --rewind -y
  assert_success
  [ "$(git rev-parse HEAD)" = "$target" ]
}
```

- [ ] **Step 2: Run to verify failure** (`h restore` not found).

- [ ] **Step 3: Implement** `git-config/bin/git-h-restore` (core; safety additions in Task 8), per spec §7 Step 4a:

```bash
#!/usr/bin/env bash
_hug_category='["head"]'
_hug_keywords='["restore","recover","undo","rescue"]'
CMD_BASE="$(readlink -f "$0" 2>/dev/null || greadlink -f "$0")" || CMD_BASE="$0"
CMD_BASE="$(dirname "$CMD_BASE")"
for f in hug-common hug-git-kit; do . "$CMD_BASE/../lib/$f"; done
set -euo pipefail

show_help() { cat << EOF
hug h restore: Reset HEAD to a commit as the inverse of a prior HEAD-mover (recovery).

USAGE:
    hug h restore <full-or-short-SHA> --back|--undo|--rollback|--rewind [-y|-f]

FLAGS (one REQUIRED — names the op being inverted; the reset mode is implicit):
    --back      ≡ git reset --soft   (recover h-back / h-squash; keeps changes staged)
    --undo      ≡ git reset --mixed  (recover h-undo; keeps changes unstaged)
    --rollback  ≡ git reset --keep   (recover h-rollback; preserves uncommitted, aborts if unsafe)
    --rewind    ≡ git reset --hard   (recover h-rewind; danger if the tree has tracked changes)
EOF
}

eval "$(parse_common_flags "$@")"
op=""; target_arg=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --back|--undo|--rollback|--rewind) op="${1#--}"; shift ;;
    *) target_arg="$1"; shift ;;
  esac
done

check_git_repo

case "${op:?usage: hug h restore <SHA> --back|--undo|--rollback|--rewind}" in
  back)     mode=soft  ;;
  undo)     mode=mixed ;;
  rollback) mode=keep  ;;
  rewind)   mode=hard  ;;
esac

target=$(resolve_target_with_temporal "" "" "${target_arg:?target required}" '') || exit 1

# No-op ONLY on exact SHA equality — never the range-count gate. This is what lets recovery
# move FORWARD to a descendant (re-invoking the mover no-ops there; see spec §4.1/Appendix A).
if [ "$target" = "$(git rev-parse HEAD)" ]; then
  info "Already at $(git rev-parse --short "$target"). Nothing to restore."
  exit 0
fi

# (Task 8 adds the bare-numeric guard, the --rewind+dirty danger escalation, and the per-tier prompt.)
prompt_confirm_warn "Reset --$mode to $(git rev-parse --short "$target")? Uncommitted work is preserved. [y/N]: "

git reset --"$mode" "$target"
info "Restored HEAD to $(git rev-parse --short "$target") (--$mode)."
```

Make executable: `chmod +x git-config/bin/git-h-restore`.

- [ ] **Step 4: Register** the alias in `git-config/.gitconfig` (mirror `back = h back` at :135): add `restore = h restore`. Add `h restore` to the completion scripts (mirror the `h back` entries).

- [ ] **Step 5: Run to verify pass** → `make test-unit TEST_FILE=test_h_restore.bats`.

- [ ] **Step 6: Commit**

```bash
hug a && hug c -m "feat: add hug h restore recovery primitive (op-named mode, exact-SHA no-op, forward-capable)"
```

---

### Task 8: `git-h-restore` safety (bare-numeric guard, `--rewind`+dirty danger, per-tier prompt)

**Goal:** Harden `restore`: refuse the ambiguous bare numeric, escalate `--rewind` on a dirty tracked tree to danger, and dispatch the prompt by tier (warn/danger have different arg forms).

**Files:**
- Modify: `git-config/bin/git-h-restore`
- Test: `tests/unit/test_h_restore.bats`

**Acceptance Criteria:**
- [ ] Bare 1–3-digit numeric target (e.g. `42`) → `error_usage`, exit 2 (would read as `HEAD~42`).
- [ ] A 4+-char SHA (`a1b2`), `1234`, and explicit `HEAD~N` resolve normally.
- [ ] `--rewind` on a dirty tracked tree + `-y` → refused, exit 3; + `-f` → proceeds.
- [ ] `--back`/`--undo`/`--rollback` on a dirty tree + `-y` → proceeds (work preserved).
- [ ] Mid-conflict (unmerged) + `--rewind` → danger (the tracked predicate sees the unmerged file).

**Verify:** `make test-unit TEST_FILE=test_h_restore.bats` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing tests:**

```bash
@test "restore: bare numeric target refused (reads as HEAD~N)" {
  run hug h restore 42 --back -y
  assert_failure
  [ "$status" -eq 2 ]
  assert_output --partial "ambiguous target"
}

@test "restore: 4-char SHA resolves normally" {
  hug h back 1 --force
  short=$(git rev-parse --short HEAD@{1})
  run hug h restore "$short" --back -y
  assert_success
}

@test "restore --rewind on dirty tracked tree + -y → refused exit 3" {
  echo "edit" >> feature1.txt              # tracked, unstaged
  run hug h restore "$(git rev-parse HEAD)" --rewind -y
  [ "$status" -eq 3 ]
}

@test "restore --back on dirty tree + -y → proceeds (soft preserves)" {
  hug h back 1 --force
  target=$(git rev-parse HEAD@{1})
  run hug h restore "$target" --back -y
  assert_success
}
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement** — insert before the target resolution, and replace the prompt with the per-tier dispatch (per spec §7 Step 4a):

```bash
# Refuse the one genuinely ambiguous input: a bare 1–3 digit numeric (resolve_head_target's
# regex ^[1-9][0-9]{0,2}$ reads it as HEAD~N). 4+-char SHAs / explicit HEAD~N pass through.
[[ "${target_arg}" =~ ^[1-9][0-9]{0,2}$ ]] && \
  error_usage "ambiguous target '$target_arg': reads as HEAD~$target_arg — pass a 4+-char SHA prefix or an explicit HEAD~N"

# ... after computing $target and the no-op test ...

tier=warn
if [ "$mode" = hard ] && has_uncommitted_tracked_changes; then
  tier=danger   # --rewind would destroy uncommitted tracked edits (unrecoverable)
fi
# warn/danger take DIFFERENT arg forms (hug-confirm:28 vs :76) — dispatch, don't call uniformly.
case "$tier" in
  danger) prompt_confirm_danger "$op" "git reset --$mode discards uncommitted tracked edits (unrecoverable)" ;;
  warn)   prompt_confirm_warn "Reset --$mode to $(git rev-parse --short "$target")? Uncommitted work is preserved. [y/N]: " ;;
esac
```

- [ ] **Step 4: Run to verify pass.**

- [ ] **Step 5: Commit**

```bash
hug a && hug c -m "feat(restore): bare-numeric guard, --rewind+dirty danger escalation, per-tier prompt"
```

---

## Phase 4 — Per-command migration

Each task: declare the tier, add the empty-target guard on every upstream call site, emit the recovery hint on success, add a `RESTORE` help section, and rename any `has_pending_changes` usage. Preserve each command's existing conditional-skip logic (the `if dirty … else skip` stays byte-for-byte; only the prompt call changes to the tier's prompt). Capture `pre_op_head=$(git rev-parse HEAD)` immediately before the git op.

### Task 9: `h-back` → warn + guard + hint + RESTORE help

**Goal:** `h-back` is warn on both paths, guards its upstream call, and prints `restore --back` on success.

**Files:**
- Modify: `git-config/bin/git-h-back` (tier decl ~top; upstream call :81; non-upstream gate :108-112; reset :115; `show_help`)
- Test: `tests/unit/test_head.bats`

**Acceptance Criteria:**
- [ ] `h-back -u` on a synced upstream → exit 0, HEAD unchanged, no new commit (guard works; no exit-128 crash).
- [ ] `h-back 2 -y` proceeds (warn) and prints `hug h restore <SHA> --back -y`.
- [ ] `RESTORE` section present in `hug h back --help`.

**Verify:** `make test-unit TEST_FILE=test_head.bats TEST_FILTER="h back"` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing tests:**

```bash
@test "h-back: recovery hint printed on success" {
  create_test_repo_with_history
  run hug h back 1 --force
  assert_success
  assert_output --partial "hug h restore"
  assert_output --partial "--back -y"
}

@test "h-back -u on synced upstream: exit 0, HEAD unchanged (empty-target guard)" {
  create_test_repo_with_history
  git branch --set-upstream-to=origin/main 2>/dev/null || skip "no upstream"
  before=$(git rev-parse HEAD)
  run hug h back -u -y
  assert_success
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "h-back --help documents RESTORE" {
  run hug h back --help
  assert_output --partial "RESTORE"
  assert_output --partial "hug h restore"
}
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement** in `git-h-back`:
  - Near the top (after flag parse): `tier=warn`.
  - Upstream path (:81): `target=$(handle_upstream_operation "moving back" "$tier" "back" "discards local-only commits")` then immediately `[[ -z "${target:-}" ]] && exit 0`.
  - Before `git reset --soft "$target"` (:115): `pre_op_head=$(git rev-parse HEAD)`.
  - Non-upstream gate (:108-112): keep `if has_staged_changes; then … fi`, change the prompt to `prompt_confirm_warn "Move HEAD back, keeping changes staged? [y/N]: "`.
  - After the reset + success info: `emit_head_recovery_hint "$pre_op_head" "back"`.
  - `show_help`: append a `RESTORE` section (per spec §7 Step 5).

- [ ] **Step 4: Run to verify pass.**

- [ ] **Step 5: Commit**

```bash
hug a && hug c -m "feat(h-back): warn tier + empty-target guard + restore hint + RESTORE help"
```

---

### Task 10: `h-undo` → warn + guard (3 sites) + hint + RESTORE help

**Goal:** `h-undo` is warn on both paths, guards all three upstream call sites, prints `restore --undo`.

**Files:**
- Modify: `git-config/bin/git-h-undo` (upstream sites :85/:87/:90; gate :126-139; `show_help`)
- Test: `tests/unit/test_head.bats`

**Acceptance Criteria:**
- [ ] Each of the three `-u` sites guards the empty target (synced upstream → exit 0, HEAD unchanged).
- [ ] `h-undo 2 -y` proceeds (warn) and prints `hug h restore <SHA> --undo -y`; recovery leaves tracked worktree files byte-identical.
- [ ] `RESTORE` section present.

**Verify:** `make test-unit TEST_FILE=test_head.bats TEST_FILTER="h undo"` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing tests** (mirror Task 9's shape for `--undo`; add a synced-upstream test per `-u` site reachable via forced/staged-dirty/clean branches).
- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** — `tier=warn`; wrap all three upstream calls with the tier args + `[[ -z "${target:-}" ]] && exit 0` guard; capture `pre_op_head` before `git reset --mixed "$target"` (:139); keep the `should_prompt` conditional-skip, change the prompt to `prompt_confirm_warn`; emit `emit_head_recovery_hint "$pre_op_head" "undo"` on success; add `RESTORE` help.
- [ ] **Step 4: Run to verify pass.**
- [ ] **Step 5: Commit**

```bash
hug a && hug c -m "feat(h-undo): warn tier + empty-target guard (3 sites) + restore hint + RESTORE help"
```

---

### Task 11: `h-rollback` → warn + guard + hint + RESTORE help

**Goal:** `h-rollback` (normal path) is warn on both paths, guards its upstream call, prints `restore --rollback`. (Root path stays danger — untouched.)

**Files:**
- Modify: `git-config/bin/git-h-rollback` (upstream call :85; reset :122; `show_help`)
- Test: `tests/unit/test_head.bats`

**Acceptance Criteria:**
- [ ] `h-rollback -u` synced → exit 0, HEAD unchanged (guard).
- [ ] `h-rollback 1 -y` proceeds (warn) and prints `hug h restore <SHA> --rollback -y`.
- [ ] Root path still danger (no change).
- [ ] `RESTORE` section present.

**Verify:** `make test-unit TEST_FILE=test_head.bats TEST_FILTER="h rollback"` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing tests** (mirror Task 9 for `--rollback`; assert the root path still refuses `-y`).
- [ ] **Step 2: Run to verify failure.**
- [ ] **Step 3: Implement** — `tier=warn` for the normal path (leave the root path's `prompt_confirm_danger` intact); guard the upstream call; capture `pre_op_head` before `git reset --keep "$target"`; emit `emit_head_recovery_hint "$pre_op_head" "rollback"`; add `RESTORE` help.
- [ ] **Step 4: Run to verify pass.**
- [ ] **Step 5: Commit**

```bash
hug a && hug c -m "feat(h-rollback): warn tier (normal path) + empty-target guard + restore hint + RESTORE help"
```

---

### Task 12: `h-rewind` → state-dependent (clean=warn+hint, dirty=danger) — the signed-off change

**Goal:** Implement the §9 owner-signed-off behavior: clean-tree `h-rewind` lowers to warn + `restore --rewind` hint; dirty stays danger; the dirty op's success output states the edits are unrecoverable.

**Files:**
- Modify: `git-config/bin/git-h-rewind` (tier computed from `has_uncommitted_tracked_changes`; upstream call :94; non-upstream gate :103; reset :107; `show_help`)
- Test: `tests/unit/test_head.bats`

**Acceptance Criteria:**
- [ ] Clean tree + `-y` → proceeds (warn), prints `hug h restore <SHA> --rewind -y`.
- [ ] Dirty (tracked) tree + `-y` → refused, exit 3; + `-f` → proceeds, success output states "uncommitted edits were destroyed and cannot be recovered", and the commit-recovery hint prints.
- [ ] Upstream path honors the same state-dependent tier.
- [ ] `RESTORE` section + clean/dirty note in `hug h rewind --help`.

**Verify:** `make test-unit TEST_FILE=test_head.bats TEST_FILTER="h rewind"` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing tests:**

```bash
@test "h-rewind clean tree + -y → proceeds (warn) + restore hint" {
  create_test_repo_with_history
  run hug h rewind 1 -y
  assert_success
  assert_output --partial "hug h restore"
  assert_output --partial "--rewind -y"
}

@test "h-rewind dirty tree + -y → refused exit 3" {
  create_test_repo_with_history
  echo "edit" >> feature1.txt
  run hug h rewind 1 -y
  [ "$status" -eq 3 ]
}

@test "h-rewind dirty tree + -f → proceeds + states edits unrecoverable" {
  create_test_repo_with_history
  echo "edit" >> feature1.txt
  run hug h rewind 1 -f
  assert_success
  assert_output --partial "cannot be recovered"
}
```

- [ ] **Step 2: Run to verify failure** (clean `-y` currently refused).

- [ ] **Step 3: Implement** (per spec §7 Step 3 + §6 h-rewind rows):

```bash
local tier
if has_uncommitted_tracked_changes; then tier=danger; else tier=warn; fi
```
  - Upstream path (:94): `target=$(handle_upstream_operation "rewinding" "$tier" "rewind" "git reset --hard is irreversible")` + empty-target guard. (This retires the `HUG_FORCE=true handle_upstream_operation` wrapper hack from #225.)
  - Non-upstream gate (:103): `case "$tier" in danger) prompt_confirm_danger "rewind" "…" ;; warn) prompt_confirm_warn "…" ;; esac` (replaces the unconditional danger prompt).
  - Before `git reset --hard "$target"` (:107): `pre_op_head=$(git rev-parse HEAD)`.
  - On the dirty branch's success output: `warning "Uncommitted edits were destroyed and cannot be recovered."` then `emit_head_recovery_hint "$pre_op_head" "rewind"` (commit part). On the clean branch: just `emit_head_recovery_hint "$pre_op_head" "rewind"`.
  - `show_help`: `RESTORE` section + the clean/dirty evaluation-time note (spec §7 Step 5).

- [ ] **Step 4: Run to verify pass.**

- [ ] **Step 5: Commit**

```bash
hug a && hug c -m "feat(h-rewind): state-dependent tier — clean→warn+hint, dirty→danger (partial revert of #225, §9 signed off)"
```

---

### Task 13: `h-squash` → warn + guard (3 sites) + hint (op=back) + RESTORE help + dead-conditional cleanup

**Goal:** `h-squash` is warn on both paths, guards all three upstream sites (the silent-orphan fix), prints `restore --back` (squash inverts as a soft reset), and folds in the `:206/:208` dead-conditional cleanup.

**Files:**
- Modify: `git-config/bin/git-h-squash` (upstream sites :154/:156/:159; dead conditional :206/:208; `show_help`)
- Test: `tests/unit/test_head.bats`

**Acceptance Criteria:**
- [ ] `h-squash -u` synced → exit 0, HEAD unchanged, **no new commit created** (the only assertion that separates the fix from the silent-orphan bug).
- [ ] `h-squash 2 -y` proceeds (warn) and prints `hug h restore <SHA> --back -y`.
- [ ] The `:206/:208` byte-identical if/else arms are collapsed to one `prompt_confirm_warn`.
- [ ] `RESTORE` section present.

**Verify:** `make test-unit TEST_FILE=test_head.bats TEST_FILTER="h squash"` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing tests:**

```bash
@test "h-squash -u synced: exit 0, HEAD unchanged, NO new commit (silent-orphan guard)" {
  create_test_repo_with_history
  git branch --set-upstream-to=origin/main 2>/dev/null || skip "no upstream"
  before=$(git rev-parse HEAD); count_before=$(git rev-list --count HEAD)
  run hug h squash -u -y
  assert_success
  [ "$(git rev-parse HEAD)" = "$before" ]
  [ "$(git rev-list --count HEAD)" = "$count_before" ]   # no fabricated commit
}

@test "h-squash: recovery hint uses --back" {
  create_test_repo_with_history
  run hug h squash 2 --force
  assert_success
  assert_output --partial "--back -y"
}
```

- [ ] **Step 2: Run to verify failure** (synced `-u` currently orphans a commit).

- [ ] **Step 3: Implement** — `tier=warn`; wrap all three upstream calls with tier args + `[[ -z "${target:-}" ]] && exit 0` guard (this is what stops the empty `$target` word-splitting into `hug h back`'s `HEAD~1` default); collapse the `:206/:208` dead conditional to one `prompt_confirm_warn`; emit `emit_head_recovery_hint "$pre_op_head" "back"` after the squash commit succeeds; add `RESTORE` help.

- [ ] **Step 4: Run to verify pass.**

- [ ] **Step 5: Commit**

```bash
hug a && hug c -m "feat(h-squash): warn tier + empty-target guard (3 sites, fixes silent orphan) + restore hint + cleanup dead conditional"
```

---

### Task 14: `cmv` → danger + "not restorable" help (no hint)

**Goal:** `cmv` is danger on both paths (branch switch + SHA rewrite ⇒ no complete recovery), prints no recovery hint, and its help states it is not restorable.

**Files:**
- Modify: `git-config/bin/git-cmv` (tier; upstream call; `show_help`)
- Test: `tests/unit/test_commit.bats`

**Acceptance Criteria:**
- [ ] `cmv … -y` → refused, exit 3 (danger); `-f` proceeds.
- [ ] No recovery hint printed on success.
- [ ] The current branch changes after success (asserted — the reason recovery is incomplete).
- [ ] `cmv --help` states it is NOT restorable (manual, branch-aware recovery).

**Verify:** `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="cmv"` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing tests:**

```bash
@test "cmv: danger tier — -y refused exit 3, -f proceeds" {
  create_test_repo_with_history
  run hug cmv 1 newbranch --new -y
  [ "$status" -eq 3 ]
  run hug cmv 1 newbranch --new -f
  assert_success
}

@test "cmv: no recovery hint; branch changed after success" {
  create_test_repo_with_history
  run hug cmv 1 newbranch --new -f
  assert_success
  refute_output --partial "hug h restore"
  [ "$(git branch --show-current)" = "newbranch" ]
}

@test "cmv --help states not restorable" {
  run hug cmv --help
  assert_output --partial "not restorable"
}
```

- [ ] **Step 2: Run to verify failure.**

- [ ] **Step 3: Implement** — set `cmv`'s confirmation to `prompt_confirm_danger "cmv" "moves commits to another branch and rewrites SHAs; not auto-recoverable"` on both paths; do NOT emit a recovery hint; add the "not restorable" note to `show_help`. (Clean-gate already unified in Task 4.)

- [ ] **Step 4: Run to verify pass.**

- [ ] **Step 5: Commit**

```bash
hug a && hug c -m "feat(cmv): danger tier, no recovery hint, 'not restorable' help (branch switch + SHA rewrite)"
```

---

## Phase 5 — Integration + docs

### Task 15: Integration tests (recovery cycles, synced-upstream guard)

**Goal:** End-to-end proof that each mover's printed recovery actually restores the pre-op state (per-mode invariant), and the synced-upstream guard holds across the family.

**Files:**
- Modify: `tests/integration/test_workflows.bats`

**Acceptance Criteria:**
- [ ] For `h-back`/`h-undo`/`h-rollback`/`h-rewind`(clean)/`h-squash`: op → run printed recovery → HEAD == pre-op SHA, with the per-mode preservation invariant (`--back`: index/`write-tree` identical across the restore; `--undo`: tracked worktree identical; `--rollback`: out-of-range edits identical).
- [ ] Synced-upstream guard for all four crashers (`h-back/-undo/-rollback/-squash -u`) → exit 0, HEAD unchanged, no new commit.
- [ ] `h-rewind` clean→warn / dirty→danger end-to-end.

**Verify:** `make test-integration TEST_FILE=test_workflows.bats` → all pass.

**Steps:**

- [ ] **Step 1: Write the integration tests** (capture `pre=$(git rev-parse HEAD)` and `wt=$(git write-tree)` before the op; after op + recovery assert HEAD and the per-mode invariant; extract the printed `hug h restore …` line and `eval` it as a real invocation).
- [ ] **Step 2: Run to verify pass** (these exercise Tasks 1-14; should pass if those are correct).
- [ ] **Step 3: Commit**

```bash
hug a && hug c -m "test(integration): mover→restore recovery cycles + synced-upstream guard across the family"
```

---

### Task 16: Docs (head commands + library README)

**Goal:** User + library docs reflect the new command, the RESTORE sections, the h-rewind clean/dirty split, and the two-predicate model.

**Files:**
- Modify: `docs/commands/head.md` (add `h restore`, the `RESTORE` sections, `h-rewind` clean/dirty)
- Modify: `git-config/lib/README.md` (two-predicate model; `h-restore`; the rename)

**Acceptance Criteria:**
- [ ] `docs/commands/head.md` documents `hug h restore` (flags, mode table, examples) and the `RESTORE` help convention; `h-rewind` shows clean→warn / dirty→danger.
- [ ] `git-config/lib/README.md` documents `has_uncommitted_tracked_changes` (tracked-only) and `has_untracked_or_pending_changes` (renamed; incl. untracked), and `emit_head_recovery_hint`.
- [ ] `make docs-build` succeeds.

**Verify:** `make docs-build` → success.

**Steps:**

- [ ] **Step 1: Update `docs/commands/head.md`** — add the `h restore` section (lift the §4.2/§4.3 tables and the usage example), document the `RESTORE` help convention, and update `h-rewind` for the clean/dirty split.
- [ ] **Step 2: Update `git-config/lib/README.md`** — the two-predicate model (one algorithm, two named views), the rename, and `emit_head_recovery_hint`.
- [ ] **Step 3: Build docs** → `make docs-build` (expect success).
- [ ] **Step 4: Commit**

```bash
hug a && hug c -m "docs: h restore command, RESTORE sections, h-rewind clean/dirty, two-predicate model"
```

---

## Final validation

- [ ] Run the whole suite: `make test` → all pass (BATS + pytest).
- [ ] Run `make sanitize` (formatting/lint/type checks per project convention).
- [ ] Manual smoke: in a scratch repo, `hug h back 2` → copy the printed `hug h restore … --back -y`, run it, confirm HEAD restored and staged changes intact; `hug h rewind 1` on a clean tree proceeds at warn with a hint; on a dirty tree refuses `-y`.

---

## Sequencing / dependencies

- Task 1 → {2, 3, 4} (predicates first; §10 prerequisite for the §9 change).
- Tasks 5, 6 → {9, 10, 11, 12, 13, 14} (plumbing used by the per-command migrations).
- Task 1 → {7, 8} (`restore`'s `--rewind` escalation uses the tracked predicate); 7 → 8.
- {7, 8} before {9..14} (the hints point at `restore`).
- {9..14} → 15 (integration exercises the migrations) → 16 (docs last).
- **Task 5 sequencing note:** changing `handle_upstream_operation`'s signature breaks existing 1-arg callers until they're updated; either land Task 5 together with the caller updates (Tasks 9-14) in one green batch, or update each caller's call site in the same commit as Task 5 to keep the suite green between tasks.

**Not in this plan (separate work, per spec §12):** the systemic helper refactor in [elifarley/hug-scm#229](https://github.com/elifarley/hug-scm/issues/229) (`commit_offset`/`is_same_commit`, move synced-detection out of the subshell, `count_commits_in_range` audit) — `restore` bypasses the helper for now and can re-share it after #229 lands. The `h-back` naming investigation ([elifarley/hug-scm#230](https://github.com/elifarley/hug-scm/issues/230)). `--dry-run` coverage and exit-code reconciliation (concerns #3/#4). Root-path danger fixes for `h-rollback`/`h-back`/`h-undo`.
