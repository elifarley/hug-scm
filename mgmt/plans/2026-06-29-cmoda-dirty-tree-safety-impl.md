# cmoda Dirty-Tree Safety — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `hug cmoda` honest and safe in a dirty tree — demote the convenience framing, warn about the scope hazard, and add a narrow runtime guard that confirms before folding unstaged work into an amend.

**Architecture:** Help-text edits to two thin command scripts (`git-cmoda`, `git-cmod`); a new library function `confirm_amend_all_scope()` in `hug-git-commit` wired into `git-cmoda` before the amend; behavioral BATS tests in `tests/unit/test_commit.bats`; a search-relevance regression check via the Python corpus; and doc sync. The guard fires **only** on the footgun signature (`has_staged_changes && has_unstaged_changes`).

**Tech Stack:** Bash (command scripts + libraries), BATS (behavioral tests), pytest (help-search corpus), VitePress (docs).

**Spec:** `mgmt/plans/2026-06-29-cmoda-dirty-tree-safety-design.md` (issue elifarley/hug-scm#190)

**Worktree:** `/home/ecc/IdeaProjects/hug-scm.WT.fix-cmoda-dirty-tree-safety` (branch `fix-cmoda-dirty-tree-safety`). All work happens here. Run `make sanitize` inside the worktree before finishing (the Stop-hook sanitize targets the session's original dir, not this worktree).

**Environment note:** Before running `make test-lib-py` / `make docs-build` in this worktree, ensure deps exist (`make test-check` for BATS; `uv`-backed targets and VitePress node deps are provisioned by the make targets themselves on first run).

**Decomposition note:** The guard's behavioral tests live **with** the guard (Task 3) so the guard is TDD'd and independently verifiable. Task 4 is the regression/verification gate (corpus + full suite + docs build), not new behavioral authoring.

---

### Task 1: `git-cmoda` help text

**Goal:** Stop the help text from selling `cmoda` as a stage-free convenience; warn about the dirty-tree hazard and document the guard.

**Files:**
- Modify: `git-config/bin/git-cmoda` (show_help heredoc, lines ~17, ~39–42, ~54)

**Acceptance Criteria:**
- [ ] Tagline no longer contains "No need to stage files first."
- [ ] A "Dirty-tree scope hazard" WARNING block appears between the "Untracked files are NOT included." line and the existing history-rewrite WARNING.
- [ ] The WARNING ends with the escape-hatch line "Pass -y to confirm without prompting (-f also works)."
- [ ] SEE ALSO `cmod` line reads "...STAGED changes only (surgical — preferred in dirty trees)".

**Verify:** `git-config/bin/git-cmoda -h 2>&1 | grep -F "Dirty-tree scope hazard"` → prints the line (exit 0).

**Steps:**

- [ ] **Step 1: Replace the tagline.**

Replace (line 17):
```
hug cmoda: Commit MODify All - Amend the last commit with ALL tracked changes. No need to stage files first.
```
with:
```
hug cmoda: Commit MODify All - Amend the last commit with ALL tracked changes (staged + unstaged).
⚠️ In a dirty tree this captures every modified tracked file. Prefer 'hug cmod' after explicit 'hug a' for surgical amends.
```

- [ ] **Step 2: Insert the WARNING block.**

Replace:
```
  Untracked files are NOT included.

  WARNING: This rewrites history. Only amend commits that have not been pushed
  to a shared repository.
```
with:
```
  Untracked files are NOT included.

  WARNING: Dirty-tree scope hazard. cmoda stages and amends EVERY modified
  tracked file. If your working tree has changes unrelated to this amend,
  cmoda will fold them in. For a surgical amend, stage explicitly:

      hug a <file>...      # stage only the intended files
      hug cmod --no-edit   # amend with ONLY the staged set

  Safety guard: when you have a staged subset AND other unstaged tracked
  changes, cmoda shows what it will fold in and asks for confirmation before
  amending. Pass -y to confirm without prompting (-f also works).

  WARNING: This rewrites history. Only amend commits that have not been pushed
  to a shared repository.
```

- [ ] **Step 3: Update the SEE ALSO `cmod` line.**

Replace:
```
  hug cmod : Amend the last commit with staged changes only
```
with:
```
  hug cmod : Amend the last commit with STAGED changes only (surgical — preferred in dirty trees)
```

- [ ] **Step 4: Verify rendering.**

Run: `git-config/bin/git-cmoda -h 2>&1 | grep -F "Dirty-tree scope hazard"`
Expected: prints `  WARNING: Dirty-tree scope hazard. cmoda stages and amends EVERY modified`

- [ ] **Step 5: Commit.**

```bash
hug -C /home/ecc/IdeaProjects/hug-scm.WT.fix-cmoda-dirty-tree-safety a git-config/bin/git-cmoda
hug -C /home/ecc/IdeaProjects/hug-scm.WT.fix-cmoda-dirty-tree-safety c -F - <<'EOF'
docs(cmoda): warn about dirty-tree scope hazard in help text

WHY: The tagline sold cmoda as "No need to stage files first," nudging users
toward folding unrelated tracked changes into an amend. The help never warned
about the hazard. See elifarley/hug-scm#190.

WHAT: Demote the convenience framing, add a Dirty-tree scope hazard WARNING
that recommends the surgical `hug a` + `hug cmod` pattern and documents the
runtime guard + the -y/-f escape hatch, and contrast cmod in SEE ALSO.
EOF
```

---

### Task 2: `git-cmod` help text

**Goal:** Make `cmod`'s help actively steer users away from `cmoda` in a dirty tree.

**Files:**
- Modify: `git-config/bin/git-cmod` (show_help heredoc, lines ~39–40, ~57)

**Acceptance Criteria:**
- [ ] A new TIP contrasting `cmoda` appears after the existing "Run 'hug sls' first" TIP.
- [ ] SEE ALSO `cmoda` line reads "...ALL tracked changes (scope-expanding — avoid in dirty trees)".

**Verify:** `git-config/bin/git-cmod -h 2>&1 | grep -F "avoid in dirty trees"` → prints the line (exit 0).

**Steps:**

- [ ] **Step 1: Insert the contrasting TIP.**

Replace:
```
  TIP: Run 'hug sls' first to verify exactly what's staged before amending.
  Use 'hug a' to stage or 'hug us' to unstage specific files.
```
with:
```
  TIP: Run 'hug sls' first to verify exactly what's staged before amending.
  Use 'hug a' to stage or 'hug us' to unstage specific files.

  TIP: Prefer 'hug cmod' over 'hug cmoda' when your working tree has unrelated
  modified files. 'cmoda' auto-stages every tracked change and will fold
  unrelated work into the amended commit.
```

- [ ] **Step 2: Update the SEE ALSO `cmoda` line.**

Replace:
```
  hug cmoda: Amend the last commit with ALL tracked changes (no need to run `hug a` first)
```
with:
```
  hug cmoda: Amend the last commit with ALL tracked changes (scope-expanding — avoid in dirty trees)
```

- [ ] **Step 3: Verify rendering.**

Run: `git-config/bin/git-cmod -h 2>&1 | grep -F "avoid in dirty trees"`
Expected: prints the updated SEE ALSO line.

- [ ] **Step 4: Commit.**

```bash
hug -C /home/ecc/IdeaProjects/hug-scm.WT.fix-cmoda-dirty-tree-safety a git-config/bin/git-cmod
hug -C /home/ecc/IdeaProjects/hug-scm.WT.fix-cmoda-dirty-tree-safety c -F - <<'EOF'
docs(cmod): contrast cmoda's scope-expanding behavior in help text

WHY: cmod and cmoda differ by one letter; nothing in cmod's help flagged that
cmoda is the dangerous-in-a-dirty-tree sibling. See elifarley/hug-scm#190.

WHAT: Add a TIP steering toward cmod when the tree has unrelated changes, and
mark cmoda as scope-expanding in SEE ALSO.
EOF
```

---

### Task 3: cmoda footgun runtime guard (+ behavioral tests)

**Goal:** When the tree has a curated staged subset AND other unstaged tracked changes, preview what `cmoda` will fold in and require confirmation; prove it with BATS.

**Files:**
- Modify: `git-config/lib/hug-git-commit` (add `confirm_amend_all_scope()`)
- Modify: `git-config/bin/git-cmoda` (call the guard before the amend)
- Test: `tests/unit/test_commit.bats` (5 new cases)

**Acceptance Criteria:**
- [ ] Guard returns 0 immediately unless `has_staged_changes && has_unstaged_changes`.
- [ ] In the footgun case it prints a preview (staged vs additional-unstaged) to **stderr** and calls `prompt_confirm_warn`.
- [ ] `-y`/`HUG_YES` and `-f`/`HUG_FORCE` proceed; non-interactive decline/no-input blocks the amend.
- [ ] Pure-unstaged and all-staged trees amend without a prompt (unchanged behavior).
- [ ] All 5 BATS cases pass.

**Verify:** `make test-unit TEST_FILE=test_commit.bats` → `✓ All tests passed!` (includes the 5 new cases).

**Steps:**

- [ ] **Step 1: Write the failing tests** in `tests/unit/test_commit.bats` (append before the final `}` of the file, after the existing cmoda tests). These define the contract:

```bash
# --- issue #190: cmoda dirty-tree footgun guard ---------------------------

@test "hug cmoda: pure-unstaged tree amends without prompting" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"
  printf 'a1\n' > a.txt
  git add a.txt
  git commit -q -m "add a"

  printf 'a2\n' >> a.txt            # unstaged only; nothing staged

  run hug cmoda --no-edit
  assert_success
  run git show HEAD:a.txt
  assert_output --partial "a2"      # unstaged change folded in
}

@test "hug cmoda: all-staged tree amends without prompting" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"
  printf 'a1\n' > a.txt
  git add a.txt
  git commit -q -m "add a"

  printf 'a2\n' >> a.txt
  git add a.txt                     # everything staged; no unstaged

  run hug cmoda --no-edit
  assert_success
  run git show HEAD:a.txt
  assert_output --partial "a2"
}

@test "hug cmoda: footgun (staged subset + unstaged) blocks on decline" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"
  printf 'a1\n' > a.txt
  printf 'b1\n' > b.txt
  git add a.txt b.txt
  git commit -q -m "add a and b"

  printf 'a2\n' >> a.txt
  printf 'b2\n' >> b.txt
  git add a.txt                     # staged subset {a.txt}; unstaged {b.txt}

  local head_before
  head_before=$(git rev-parse HEAD)

  run bash -c 'printf "n\n" | hug cmoda --no-edit'
  assert_failure
  assert_output --partial "scope check"     # preview shown before the prompt

  run git rev-parse HEAD
  assert_output "$head_before"              # amend did NOT happen
  run git show HEAD:b.txt
  refute_output --partial "b2"              # unstaged change NOT folded in
}

@test "hug cmoda: footgun proceeds with -y (escape hatch)" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"
  printf 'a1\n' > a.txt
  printf 'b1\n' > b.txt
  git add a.txt b.txt
  git commit -q -m "add a and b"

  printf 'a2\n' >> a.txt
  printf 'b2\n' >> b.txt
  git add a.txt                     # footgun signature

  run hug cmoda -y --no-edit
  assert_success
  run git show HEAD:a.txt
  assert_output --partial "a2"      # staged folded in
  run git show HEAD:b.txt
  assert_output --partial "b2"      # unstaged ALSO folded in
}

@test "hug cmod: surgical amend ignores unstaged changes (contrast with cmoda)" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"
  printf 'a1\n' > a.txt
  printf 'b1\n' > b.txt
  git add a.txt b.txt
  git commit -q -m "add a and b"

  printf 'a2\n' >> a.txt
  printf 'b2\n' >> b.txt
  git add a.txt                     # stage subset {a.txt}

  run hug cmod --no-edit
  assert_success
  run git show HEAD:a.txt
  assert_output --partial "a2"      # staged folded in
  run git show HEAD:b.txt
  refute_output --partial "b2"      # unstaged NOT folded in
  run git diff --name-only
  assert_output --partial "b.txt"   # b.txt still has unstaged changes
}
```

Note: `refute_output` ships with bats-assert (already loaded via `test_helper`). If unavailable, replace with `[ "${output/b2/}" = "$output" ]`.

- [ ] **Step 2: Run the tests to verify they fail.**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="footgun"`
Expected: the footgun/decline and -y cases FAIL (guard not implemented yet — `cmoda` proceeds and amends, so the decline case's HEAD changes).

- [ ] **Step 3: Add the guard function** to `git-config/lib/hug-git-commit` (append at end of file):

```bash
# confirm_amend_all_scope: dirty-tree footgun guard for `hug cmoda`.
#
# WHY: cmoda runs `git commit -a --amend`, auto-staging EVERY modified tracked
# file. When the user has curated a staged subset but ALSO has other unstaged
# tracked changes, cmoda silently folds the unstaged work into the amend — the
# exact incident behind elifarley/hug-scm#190. We prompt ONLY in that ambiguous
# case:
#   - nothing staged   -> unambiguous "amend everything" intent -> no prompt
#   - nothing unstaged -> cmoda is identical to cmod            -> no prompt
# This preserves cmoda's power-tool ergonomics while catching the footgun.
#
# Tier: warn (recoverable via `hug h back 1 --force`). -y/HUG_YES and
# -f/HUG_FORCE both auto-confirm (prompt_confirm_warn honors them). In a
# non-interactive shell without either, prompt_confirm_warn cancels — the
# desired safety stop for an agent that staged a subset then ran cmoda.
#
# Output discipline: the preview is human-facing chatter -> stderr only.
confirm_amend_all_scope() {
  has_staged_changes && has_unstaged_changes || return 0  # not the footgun case

  warning "cmoda scope check: staged set is a SUBSET of all tracked changes."
  printf "    Staged — what 'hug cmod' would amend:\n" >&2
  list_staged_files --status | sed 's/^/      /' >&2
  printf '    Unstaged — cmoda will ALSO fold these in:\n' >&2
  list_unstaged_files --status | sed 's/^/      /' >&2

  prompt_confirm_warn "Amend with ALL tracked changes (staged + unstaged)? [y/N]: "
}
```

- [ ] **Step 4: Wire the guard into `git-config/bin/git-cmoda`.**

Replace:
```bash
info "Amending last commit with all tracked changes..."

git commit -a --amend "$@" && suggest_next_push_command --amend
```
with:
```bash
# Guard the dirty-tree footgun: amending with ALL tracked changes when the user
# curated only a subset is the elifarley/hug-scm#190 incident. No-op unless the
# tree has both staged and unstaged changes.
confirm_amend_all_scope

info "Amending last commit with all tracked changes..."

git commit -a --amend "$@" && suggest_next_push_command --amend
```

- [ ] **Step 5: Run the tests to verify they pass.**

Run: `make test-unit TEST_FILE=test_commit.bats`
Expected: `✓ All tests passed!` (all 5 new cases green, no existing regressions).

- [ ] **Step 6: Commit.**

```bash
hug -C /home/ecc/IdeaProjects/hug-scm.WT.fix-cmoda-dirty-tree-safety a git-config/lib/hug-git-commit git-config/bin/git-cmoda tests/unit/test_commit.bats
hug -C /home/ecc/IdeaProjects/hug-scm.WT.fix-cmoda-dirty-tree-safety c -F - <<'EOF'
feat(cmoda): guard the dirty-tree footgun with a scope-confirm prompt

WHY: cmoda amends with ALL tracked changes (git's -a --amend). When the user
staged a curated subset but left other tracked files modified, cmoda silently
swept the unrelated work into the amend (elifarley/hug-scm#190). Docs alone do
not stop a reflexive `cmoda` in a dirty tree.

WHAT: confirm_amend_all_scope() fires ONLY on the footgun signature — a staged
subset AND extra unstaged tracked changes. It previews the staged set vs the
unstaged changes cmoda will additionally fold in (stderr), then asks via the
warn tier. Pure-unstaged ("amend everything") and all-staged (cmoda == cmod)
proceed unprompted, exactly as before.

HOW: warn tier (recoverable amend) means -y/HUG_YES and -f/HUG_FORCE both
auto-confirm; non-interactive without either blocks — the desired stop. The
escape hatch needs no new plumbing: parse_common_flags already strips -y/-f.

IMPACT: the exact incident is now caught; clean cmoda flows are unchanged.
Five BATS cases lock the contract (footgun decline/‑y, pure-unstaged,
all-staged, and the surgical cmod contrast).
EOF
```

---

### Task 4: Corpus regression + full verification gate

**Goal:** Confirm the help-text edits don't regress help-search ranking, and that the whole change is green end-to-end.

**Files:**
- Run only (edit only if a regression must be fixed): `git-config/lib/python/tests/test_quality_corpus.py`

**Acceptance Criteria:**
- [ ] `test_quality_corpus.py` passes — the query `"amend"` still returns `hug cmod` in top-5.
- [ ] The full BATS commit suite passes.
- [ ] `make docs-build` succeeds.
- [ ] `make sanitize` leaves the tree clean (or its reformatting is committed).

**Verify:** commands below all succeed.

**Steps:**

- [ ] **Step 1: Corpus regression.**

Run: `make test-lib-py TEST_FILTER=test_quality_corpus`
Expected: PASS. If `"amend" -> hug cmod` regressed (cmoda displaced cmod), the fix is to tighten keywords/specs — but the WARNING text adds no "amend" weight to cmoda, so green is expected. Do not pre-emptively edit.

- [ ] **Step 2: Full commit suite.**

Run: `make test-unit TEST_FILE=test_commit.bats`
Expected: `✓ All tests passed!`

- [ ] **Step 3: Docs build.**

Run: `make docs-build`
Expected: build succeeds (validates the Task 5 doc edits too if run after Task 5).

- [ ] **Step 4: Static analysis.**

Run: `make sanitize`
Expected: no changes, or formatting changes that you then stage + commit:
```bash
hug -C /home/ecc/IdeaProjects/hug-scm.WT.fix-cmoda-dirty-tree-safety sl
# if sanitize reformatted anything related:
hug -C /home/ecc/IdeaProjects/hug-scm.WT.fix-cmoda-dirty-tree-safety a <reformatted files>
hug -C /home/ecc/IdeaProjects/hug-scm.WT.fix-cmoda-dirty-tree-safety c -m "style: apply make sanitize formatting"
```

---

### Task 5: Doc sync (commits.md + README)

**Goal:** Keep the user-facing docs consistent with the new help text.

**Files:**
- Modify: `docs/commands/commits.md` (cmoda section, lines ~149–166)
- Modify: `README.md` (line ~474)

**Acceptance Criteria:**
- [ ] `docs/commands/commits.md` cmoda section drops "so you don't need to stage them first" and adds a VitePress `::: warning` dirty-tree block recommending `cmod`.
- [ ] `README.md` cmoda one-liner notes "prefer cmod in dirty trees".
- [ ] `make docs-build` succeeds.

**Verify:** `grep -F "Dirty-tree hazard" docs/commands/commits.md` and `grep -F "prefer cmod in dirty trees" README.md` both match; `make docs-build` passes.

**Steps:**

- [ ] **Step 1: Update `docs/commands/commits.md`.**

Replace:
```
Similar to `hug cmod` (**C**ommit **MOD**ify), this command amends the last commit.
However, it automatically includes all changes to **ALL tracked files**, so you don't need to stage them first.
```
with:
```
Similar to `hug cmod` (**C**ommit **MOD**ify), this command amends the last commit.
However, it automatically includes all changes to **ALL tracked files**.

::: warning Dirty-tree hazard
Because `cmoda` stages **every** modified tracked file, a working tree with
unrelated changes will have them folded into the amend. For a surgical amend,
stage explicitly and use `hug cmod`:

```shell
hug a <file>...      # stage only the intended files
hug cmod --no-edit   # amend with ONLY the staged set
```

When you have a staged subset **and** other unstaged tracked changes, `cmoda`
previews what it will fold in and asks for confirmation (`-y` to skip).
:::
```

- [ ] **Step 2: Update `README.md` (line ~474).**

Replace:
```
hug cmoda [-m msg]    # Commit: Modify All (Amend last commit with all tracked changes)
```
with:
```
hug cmoda [-m msg]    # Commit: Modify All (Amend with all tracked changes — prefer cmod in dirty trees)
```

- [ ] **Step 3: Verify.**

Run: `grep -F "Dirty-tree hazard" docs/commands/commits.md && grep -F "prefer cmod in dirty trees" README.md && make docs-build`
Expected: both greps match and docs build succeeds.

- [ ] **Step 4: Commit.**

```bash
hug -C /home/ecc/IdeaProjects/hug-scm.WT.fix-cmoda-dirty-tree-safety a docs/commands/commits.md README.md
hug -C /home/ecc/IdeaProjects/hug-scm.WT.fix-cmoda-dirty-tree-safety c -F - <<'EOF'
docs: sync cmoda dirty-tree guidance to command reference and README

WHY: Keep user-facing docs consistent with the new help text and guard so the
warning is discoverable outside `hug help`. See elifarley/hug-scm#190.

WHAT: Add a VitePress warning block to the cmoda command page and annotate the
README one-liner to prefer cmod in dirty trees.
EOF
```

---

## Self-Review

**1. Spec coverage**
- Help text (cmoda WARNING/tagline/SEE ALSO) → Task 1. ✓
- Help text (cmod TIP/SEE ALSO) → Task 2. ✓
- Runtime guard (footgun trigger, warn tier, preview, escape hatch, non-interactive) → Task 3. ✓
- 5 behavioral tests → Task 3. ✓
- Corpus regression → Task 4. ✓
- Doc sync (commits.md + README) → Task 5. ✓
- Out-of-scope items (agent-memory file, always-prompt) → intentionally excluded. ✓

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"; every code step shows real content. ✓

**3. Type/name consistency:** `confirm_amend_all_scope` defined in Task 3, called in Task 3's git-cmoda edit. Helpers `has_staged_changes`/`has_unstaged_changes` (hug-git-state), `list_staged_files`/`list_unstaged_files --status` (hug-git-files), `prompt_confirm_warn`/`warning` (hug-confirm/hug-common) all confirmed reachable via git-cmoda's `hug-common hug-git-kit hug-git-commit` sourcing. ✓

**Ordering:** Task 4 is the gate — run it after Tasks 1, 2, 3, 5 (reflected in blockedBy). Within a PR, commit per task.
