# sh merge patch parity + shc -n wording cleanup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `shp`/`shcp` (and `shp --llm`) show a first-parent patch on merge commits (spec: [elifarley/hug-scm#346](https://github.com/elifarley/hug-scm/issues/346)) and drop the inaccurate "pipe-safe" label from `shc -n` docs ([elifarley/hug-scm#329](https://github.com/elifarley/hug-scm/issues/329)).

**Architecture:** One shared lib helper (`merge_first_parent_patch` in hug-git-diff) emits the probe-verified two-tree diff `git diff-tree -p --no-commit-id -r --root "$m^1" "$m"` for merges. Both call sites gate on the existing `is_merge_commit` predicate and keep today's invocation for non-merges/root — byte-identity is structural, not probe-best-effort. Help texts state one contract sentence: *patch = parent 1 (the `hug dd` rule, empty for `-s ours` merges); stats = each parent (issue-268 contract, untouched)*.

**Tech Stack:** Bash (command scripts + lib), BATS (bats-assert), GNU make targets, VitePress docs.

**Spec:** `docs/superpowers/specs/2026-09-12-sh-merge-patch-parity-and-shc-n-pipe-safe-wording-design.md` (Rev 2). Worktree: `~/src/hug-scm.WT.346-sh-merge-patch-parity-and-shc-n-pipe-safe-wording`. **Repo rule: use `hug` commands, never raw `git`/`git worktree`, for all repo operations in these steps.** Test fixtures inside `.bats` files use plain `git` (that is existing convention there).

**Key probe facts this plan relies on (git 2.34.1, all reproduced):**
- `git diff-tree -p -m --first-parent <merge>` emits the per-parent concatenation (BOTH flag orders) — never use it.
- `git diff-tree -p --no-commit-id -r --root M^1 M` ≡ `git show -m --first-parent M` on merges; ≡ single-rev diff-tree and ≡ `git show` on non-merges; exit 128 on bad refs in both forms.
- `git show` renders renames (`rename from/to`); `git diff-tree -p` does not — hence non-merges keep `git show` at the hug-git-show sites.
- `-s ours` merges: first-parent patch is empty (legitimate; wording must not promise non-empty patches on all clean merges).

---

### Task 1: #329 — drop the "pipe-safe" label from the four `shc -n` sites

**Goal:** No user-facing text claims `shc -n` line output is "pipe-safe"; `-z` stays documented as the fully-raw stream.

**Files:**
- Modify: `git-config/bin/git-shc:97`
- Modify: `docs/cookbook.md:192`
- Modify: `docs/skills/hug-repo-analysis/SKILL.md:114` and `:289`

**Acceptance Criteria:**
- [ ] `grep -rn "pipe-safe" git-config/bin/git-shc docs/cookbook.md docs/skills/hug-repo-analysis/SKILL.md` returns zero hits.
- [ ] The four example lines still read naturally (label dropped, nothing else reworded).
- [ ] `git-dd:105` and `git-shv:59` "pipe-safe" mentions untouched (they are accurate — patch commands).
- [ ] `make test-unit TEST_FILE=test_sh.bats` passes (no test pins the old label).

**Verify:** the grep above → empty; `make test-unit TEST_FILE=test_sh.bats TEST_FILTER="shc -h"` → pass.

**Steps:**

- [ ] **Step 1: Edit the four lines (label dropped, argument unchanged)**

`git-config/bin/git-shc:97` — in the CAPTURING OUTPUT block:
```
    hug shc -n main..HEAD            # Paths only (repo-relative)
```
(was: `# Paths only (repo-relative, pipe-safe)`)

`docs/cookbook.md:192`:
```
    hug shc -n abc1234        # same, but paths only (repo-relative)
```
(was: `(repo-relative, pipe-safe)`)

`docs/skills/hug-repo-analysis/SKILL.md:114` and `:289` (identical lines):
```
hug shc -n <commit-hash>      # files changed, paths only
```
(was: `# files changed, paths only (pipe-safe)`)

- [ ] **Step 2: Verify the sweep is clean**

Run: `grep -rn "pipe-safe" git-config/bin/git-shc docs/cookbook.md docs/skills/hug-repo-analysis/SKILL.md`
Expected: no output (exit 1). Also confirm the out-of-scope mentions survived:
`grep -c "pipe-safe" git-config/bin/git-dd git-config/bin/git-shv` → `1` and `1`.

- [ ] **Step 3: Run the sh tests (no pin referenced the label, but the help file changed)**

Run: `make test-unit TEST_FILE=test_sh.bats`
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
hug a git-config/bin/git-shc docs/cookbook.md docs/skills/hug-repo-analysis/SKILL.md
hug c -F - <<'EOF'
docs(shc): drop "pipe-safe" label from shc -n examples (issue elifarley/hug-scm#329)

WHY: shc -n line output is repo-relative and raw for non-ASCII bytes
(core.quotePath=false pin), but git still C-quotes structural characters
(newline, backslash, quote, tab) in line mode — "pipe-safe" overpromised
machine-parseability. Only -z is the fully-raw stream, and the -z help
example already documents that.

WHAT: Label dropped from all four occurrences: the shc CAPTURING OUTPUT
help example, docs/cookbook.md, and docs/skills/hug-repo-analysis/
SKILL.md (x2). The git-dd/git-shv "pipe-safe" pointers are untouched —
they refer to patch commands, where the claim is accurate.

HOW: Wording-only edits; the example arguments and the -z guidance are
unchanged, so nothing behavioral moves.

IMPACT: Scripts authors reading the help are nudged toward -z for
arbitrary filenames instead of trusting line mode with quote-sensitive
paths.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
```

---

### Task 2: `merge_first_parent_patch` helper in hug-git-diff (TDD)

**Goal:** A shared, directly testable lib function that prints the first-parent patch for a MERGE commit via the two-tree form.

**Files:**
- Modify: `git-config/lib/hug-git-diff` (insert after the `is_merge_commit()` function, before the `pinned_diff` banner comment)
- Test: `tests/lib/test_hug_git_diff.bats` (next to the existing pinned_diff merge tests, after `_make_merge_fixture`'s tests)

**Acceptance Criteria:**
- [ ] Helper exists, sourced by hug-git-diff, callable from tests.
- [ ] On the lib merge fixture it prints exactly the parent-1 patch (`side.txt` hunk) and is byte-identical to `git show -m --first-parent --pretty=format:`.
- [ ] Existing lib tests still pass (nothing else changes).

**Verify:** `make test-lib TEST_FILE=test_hug_git_diff.bats` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing tests** (append after the `pinned_diff: --merge-aware is a no-op on the root commit` test)

```bash
@test "merge_first_parent_patch: merge emits the parent-1 patch (two-tree diff-tree)" {
  _make_merge_fixture
  run merge_first_parent_patch HEAD
  assert_success
  assert_output --partial "diff --git a/side.txt b/side.txt"
  # The two-tree form is inherently parent-1-only: there is no second
  # section to leak (this fixture's parent-2 diff is empty by design, so
  # the byte-identity check below carries the cross-form guarantee).
}

@test "merge_first_parent_patch: byte-identical to git show -m --first-parent" {
  _make_merge_fixture
  local ours ref
  ours=$(merge_first_parent_patch HEAD)
  ref=$(git show -m --first-parent HEAD --pretty=format:)
  [[ "$ours" == "$ref" ]]
}

@test "merge_first_parent_patch: pathspecs thread after the two trees" {
  _make_merge_fixture
  run merge_first_parent_patch HEAD -- side.txt
  assert_success
  assert_output --partial "diff --git a/side.txt b/side.txt"
  run merge_first_parent_patch HEAD -- no-such.txt
  assert_success
  assert_output ""
}
```

- [ ] **Step 2: Run to red**

Run: `make test-lib TEST_FILE=test_hug_git_diff.bats TEST_FILTER="merge_first_parent_patch"`
Expected: FAIL — `merge_first_parent_patch: command not found` (or empty-output assertion failures).

- [ ] **Step 3: Implement** (insert in `git-config/lib/hug-git-diff` right after `is_merge_commit()`'s closing brace)

```bash
################################################################################
# merge_first_parent_patch — the shared first-parent MERGE patch primitive
################################################################################

# Prints the first-parent patch for a MERGE commit.
# Usage: merge_first_parent_patch <merge_commit> [git-arg...]
# Parameters:
#   $1     - a MERGE commit (caller MUST gate with is_merge_commit; calling
#            this on a non-merge diffs against its single parent, which is
#            NOT the contract the `git show` call sites want — they keep
#            `git show` off-merge to preserve rename rendering).
#   $2..   - optional extra git args (e.g. `-- <pathspec>...`), passed
#            through verbatim AFTER the two trees.
# Output:
#   `git diff-tree -p --no-commit-id -r --root "$m^1" "$m"` on stdout.
# WHY the two-tree form (probe-verified, git 2.34.1): `diff-tree -m
# --first-parent` emits the per-parent CONCATENATION — `--first-parent` is
# a history-traversal option and single-rev diff-tree does not traverse, so
# it cannot restrict `-m` pairing. `git show` (log family) honors the pair,
# but its output is git-version-sensitive (undocumented repo floor) — the
# two-tree form is version-insensitive by construction and byte-identical
# to `git show -m --first-parent` on merges. Note: diff-tree does not do
# rename detection (unlike `git show`), so merge patches render renames as
# delete+add — consistent with shcp's existing non-merge patch semantics.
merge_first_parent_patch() {
    local merge="$1"
    shift
    git diff-tree -p --no-commit-id -r --root "$merge^1" "$merge" ${1+"$@"}
}
```

- [ ] **Step 4: Run to green**

Run: `make test-lib TEST_FILE=test_hug_git_diff.bats`
Expected: all pass (new + existing).

- [ ] **Step 5: Commit**

```bash
hug a git-config/lib/hug-git-diff tests/lib/test_hug_git_diff.bats
hug c -F - <<'EOF'
feat(lib): merge_first_parent_patch — shared first-parent merge-patch primitive (issue elifarley/hug-scm#346)

WHY: shp/shcp merge patches are empty today (patch parity gap from the
issue-268 stats work). Both call sites need the same merge branch, and
the obvious flag pair is wrong: probed on git 2.34.1, `diff-tree -m
--first-parent` emits the per-parent concatenation because --first-parent
is a traversal option and single-rev diff-tree does not traverse.

WHAT: merge_first_parent_patch <merge> [args...] emits the two-tree diff
`git diff-tree -p --no-commit-id -r --root "$m^1" "$m"` — probe-verified
byte-identical to `git show -m --first-parent` on merges and version-
insensitive by construction (no documented repo git floor).

HOW: Caller gates with the existing is_merge_commit predicate; the helper
owns only the merge branch, keeping non-merge paths at each call site
byte-identical (git show keeps rename rendering there). Pathspecs pass
through verbatim after the two trees.

IMPACT: One proven merge mechanism for both shcp and hug-git-show, test-
pinnable directly at the lib level.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
```

---

### Task 3: shcp merge patch — gate + helper, shcp help, tests (TDD)

**Goal:** `hug shcp <merge>` shows the first-parent patch above its per-parent stats; non-merge/range paths untouched; shcp help states the contract.

**Files:**
- Modify: `git-config/bin/git-shcp:143-150` (single-commit else-branch) and `:49-51` (help text)
- Test: `tests/unit/test_sh.bats` (new tests near the existing `hug shcp: merge stats` test)

**Acceptance Criteria:**
- [ ] `hug shcp <merge>`: parent-1 file hunk present; parent-2-only file's `diff --git` hunk absent; stats still list both parents' files.
- [ ] `hug shcp HEAD~2..HEAD` (range whose tip is a merge): unchanged endpoint diff — both hunks present.
- [ ] `shcp -h` states the first-parent contract; no "stays empty" wording.
- [ ] `make test-unit TEST_FILE=test_sh.bats` passes.

**Verify:** `make test-unit TEST_FILE=test_sh.bats TEST_FILTER="shcp"` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing tests** (add next to the existing `hug shcp: merge stats list merged files` test)

```bash
@test "hug shcp: merge patch shows the first-parent diff (issue 346)" {
  # Patch contract: parent 1 only (the hug dd rule). side-shcp-patch.txt is
  # the parent-1-side file; feature2.txt exists only on main (parent 1's
  # history line is where it lives, but the MERGE introduced it relative to
  # parent 2 — it must appear in stats (per-parent) yet NOT as a patch hunk,
  # because it is identical to parent 1).
  _setup_merge_fixture side-shcp-patch
  run hug shcp HEAD
  assert_success
  assert_output --partial "diff --git a/side-shcp-patch.txt b/side-shcp-patch.txt"
  refute_output --partial "diff --git a/feature2.txt"
  # Stats stay per-parent (issue 268 contract, unchanged).
  assert_output --partial "File stats:"
  assert_output --partial "feature2.txt"
}

@test "hug shcp: range whose tip is a merge keeps the endpoint diff" {
  # Ranges have no merge semantics (two-endpoint diff). Pins that the new
  # merge gate does not leak into the range branch.
  _setup_merge_fixture side-shcp-range
  run hug shcp HEAD~2..HEAD
  assert_success
  assert_output --partial "diff --git a/side-shcp-range.txt b/side-shcp-range.txt"
  assert_output --partial "diff --git a/feature2.txt b/feature2.txt"
}

@test "hug shcp -h: documents the first-parent merge patch contract" {
  run hug shcp -h
  assert_success
  assert_output --partial "FIRST-PARENT"
  refute_output --partial "stays empty"
}
```

- [ ] **Step 2: Run to red**

Run: `make test-unit TEST_FILE=test_sh.bats TEST_FILTER="shcp"`
Expected: the two new merge/range patch tests FAIL (`feature2.txt` refute fails on the merge test because today's output is empty — actually the assert for the side hunk fails first: today the patch section is empty). The `-h` probe fails on "FIRST-PARENT".

- [ ] **Step 3: Implement — gate the single-commit branch** (replace the `else` block at `git-shcp:143-150`)

```bash
else
  # Single commit: use git diff-tree. On a MERGE, diff against parent 1
  # (two-tree form — what the merge brought in, the `hug dd` rule).
  # diff-tree's -m --first-parent does NOT yield a first-parent patch
  # (probed: it concatenates per-parent diffs), hence the gate + helper.
  # Non-merges keep the single-rev form byte-identical (--root covers
  # root commits, which have no ^1).
  printf '%s %s Diff for %s:\n' "$commit_emoji" "$diff_emoji" "$commit_ref"
  if is_merge_commit "$commit_ref"; then
    merge_first_parent_patch "$commit_ref" "${pathspec_args[@]+"${pathspec_args[@]}"}"
  else
    git diff-tree -p --no-commit-id -r --root "$commit_ref" "${pathspec_args[@]+"${pathspec_args[@]}"}"
  fi

  printf '\n%s %s File stats:\n' "$commit_emoji" "$stats_emoji"
  HUG_QUIET=T git shc "$commit_ref" "${pathspec_args[@]+"${pathspec_args[@]}"}"
fi
```

(`is_merge_commit` and `merge_first_parent_patch` come from hug-git-diff, which git-shcp already sources at line 9.)

- [ ] **Step 4: Run to green**

Run: `make test-unit TEST_FILE=test_sh.bats TEST_FILTER="shcp"`
Expected: FAIL only on the `-h` probe ("FIRST-PARENT" not yet in help).

- [ ] **Step 5: Update shcp help** (replace `git-shcp:49-51`)

```
    Merge commits: File stats list changes vs EACH parent (a file touched
    on both sides appears once per parent); the patch section shows the
    FIRST-PARENT diff — what the merge brought in (same rule as `hug dd`;
    empty when the merge introduces nothing vs parent 1, e.g. -s ours) —
    see 'hug shc -h' for the full stats contract.
```

- [ ] **Step 6: Run the full unit file, then commit**

Run: `make test-unit TEST_FILE=test_sh.bats` → all pass.

```bash
hug a git-config/bin/git-shcp tests/unit/test_sh.bats
hug c -F - <<'EOF'
feat(shcp): merge patches show the first-parent diff (issue elifarley/hug-scm#346)

WHY: Since the issue-268 stats fix, `hug shcp <merge>` prints an empty
patch section directly above merge-aware stats — the on-screen
inconsistency #346 reports.

WHAT: Single-commit branch gates on is_merge_commit: merges emit the
two-tree first-parent diff via the new hug-git-diff helper; non-merges
and root commits keep the exact single-rev invocation (byte-identical;
--root covers parentless commits). Range branch untouched — endpoint
diffs have no merge semantics (test-pinned). Help states the contract
(patch = parent 1, the hug dd rule; stats = each parent; empty for
-s ours merges).

HOW: merge_first_parent_patch is the probe-verified primitive (the
-m --first-parent flag pair concatenates per-parent diffs on diff-tree).
Pathspec args thread through unchanged after the two trees.

IMPACT: Merge review on shcp shows one coherent, reviewable diff —
exactly what the merge introduced — instead of silence above populated
stats.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
```

---

### Task 4: hug-git-show merge patch (standard + LLM), sh/shp/shv help, tests (TDD)

**Goal:** `hug shp <merge>` and `shp --llm` `<diff>` show the first-parent patch; non-merges keep `git show` byte-identical (rename rendering preserved); sh/shp/shv help state the contract.

**Files:**
- Modify: `git-config/lib/hug-git-show` — `_show_commit_standard` patch invocation (~`:287`) and `_show_commit_llm` `<diff>` CDATA invocation (~`:345`)
- Modify: `git-config/bin/git-sh:63-65`, `git-config/bin/git-shp:42-44`, `git-config/bin/git-shv:52-54` (help texts)
- Test: `tests/lib/test_hug_git_show.bats` (add lib-level merge pin), `tests/unit/test_sh.bats` (flip `:679`, add pins), `tests/unit/test_shv.bats` (add help probe)

**Acceptance Criteria:**
- [ ] `hug shp <merge>`: parent-1 hunk present, `diff --git a/feature2.txt` absent, stats keep both parents' files, "Changed files" chatter still contained.
- [ ] `shp --llm <merge>`: `<diff>` CDATA contains the parent-1 patch.
- [ ] Dirty merge: full first-parent diff (`diff --git`), no `diff --cc`.
- [ ] `-s ours` merge: patch section empty, stats populated.
- [ ] Non-merge rename commit: `rename from/to` still rendered (proves `git show` kept off-merge; repo-local `diff.renames true` set in fixture for determinism).
- [ ] Lib-level merge pin added; the non-merge pins at `test_hug_git_show.bats:562-570` unchanged.
- [ ] sh/shp/shv help updated; probes pass; `make test-unit TEST_FILE=test_sh.bats`, `make test-unit TEST_FILE=test_shv.bats`, and `make test-lib TEST_FILE=test_hug_git_show.bats` all pass.

**Verify:** `make test-lib TEST_FILE=test_hug_git_show.bats && make test-unit TEST_FILE=test_sh.bats && make test-unit TEST_FILE=test_shv.bats` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing lib test** (`tests/lib/test_hug_git_show.bats` — the file has NO merge fixture today; add fixture + test near the pathspec characterization tests)

```bash
# Fixture: branch `side` adds side.txt at HEAD~1; merge --no-ff back into
# main (same shape as tests/unit/test_sh.bats _setup_merge_fixture and the
# lib _make_merge_fixture in test_hug_git_diff.bats). main tip carries
# feature2.txt from earlier commits — the both-parents discriminator.
_setup_show_merge_fixture() {
  git checkout -qb side HEAD~1
  echo s > side.txt && git add side.txt && git commit -qm side
  git checkout -q main
  git merge -q --no-ff side -m "Merge side"
}

@test "_show_commit_standard: merge emits the first-parent patch (issue 346)" {
  # NO lib-level merge pin existed before this test (grep "merge" was zero
  # hits) — the unit test at test_sh.bats covered the command surface only.
  _setup_show_merge_fixture
  run _show_commit_standard HEAD true true
  assert_success
  # Patch side (stdout): parent-1 hunk only — feature2.txt is identical to
  # parent 1, so it must NOT render as a patch (it still appears in stats).
  assert_output --partial "diff --git a/side.txt b/side.txt"
  refute_output --partial "diff --git a/feature2.txt"
  assert_output --partial "feature2.txt"
}

@test "_show_commit_llm: merge <diff> CDATA carries the first-parent patch" {
  _setup_show_merge_fixture
  run _show_commit_llm HEAD true true
  assert_success
  assert_output --partial "<diff>"
  assert_output --partial "diff --git a/side.txt b/side.txt"
  refute_output --partial "diff --git a/feature2.txt"
}
```

(If this file's fixtures differ — check how its existing tests build repos in `setup()` and adapt the fixture to that layout; the assertions are the contract.)

- [ ] **Step 2: Run to red**

Run: `make test-lib TEST_FILE=test_hug_git_show.bats TEST_FILTER="merge"`
Expected: FAIL — patch side empty today.

- [ ] **Step 3: Implement the gate in both hug-git-show functions**

In `_show_commit_standard` (replace the `git show` invocation, keep the comment context):

```bash
        # Show the patch diff (suppress commit info from git show).
        # When pathspecs are given, restrict diff to them (nullsafe idiom —
        # expands to nothing when empty, `-- p...` otherwise).
        # Merge commits: two-tree first-parent diff (the `hug dd` rule).
        # diff-tree's -m --first-parent does NOT restrict diff-tree to
        # parent 1 (probed), and `git show -m --first-parent` is version-
        # sensitive — hence the gate + shared helper. NON-merges keep
        # `git show` byte-identical: it honors diff.renames (renders
        # `rename from/to`) while diff-tree does not.
        if is_merge_commit "$commit"; then
            merge_first_parent_patch "$commit" ${pathspecs[@]+"--" "${pathspecs[@]}"}
        else
            git show "$commit" --pretty=format:"" ${pathspecs[@]+"--" "${pathspecs[@]}"}
        fi
```

In `_show_commit_llm` (replace the invocation inside the `<diff>` CDATA block):

```bash
    if [[ "$show_patch" == "true" ]]; then
        printf '<diff><![CDATA[\n'
        # Same merge gate as _show_commit_standard: first-parent patch on
        # merges, byte-identical `git show` otherwise (rename rendering).
        if is_merge_commit "$commit"; then
            merge_first_parent_patch "$commit" ${pathspecs[@]+"--" "${pathspecs[@]}"}
        else
            git show "$commit" --pretty=format:"" ${pathspecs[@]+"--" "${pathspecs[@]}"}
        fi
        printf ']]></diff>\n'
    fi
```

(Both functions already call `_diff_emoji` from hug-git-diff, so `is_merge_commit`/`merge_first_parent_patch` are in scope wherever hug-git-show is loaded per the repo's sourcing convention.)

- [ ] **Step 4: Run lib to green**

Run: `make test-lib TEST_FILE=test_hug_git_show.bats` → all pass.

- [ ] **Step 5: Flip the unit pin and add the new unit tests** (`tests/unit/test_sh.bats`)

Replace the test at `:679` (through its final `refute_output --partial "diff --git"` at `:700`) with:

```bash
@test "hug shp: merge patch shows the first-parent diff; stats stay per-parent (issue 346)" {
  # git-shc's NOTE documents that sh/shp/shcp inherit merge-aware STATS via
  # their git shc delegation. The PATCH side used to stay empty (issue 268's
  # deliberate boundary); #346 flips it: the patch is the FIRST-PARENT diff
  # (the hug dd rule). The old pin refuted "diff --git" — inverted here.
  _setup_merge_fixture side-shp
  run hug shp HEAD
  assert_success
  # Stats side: merge-aware via delegation, unchanged. feature2.txt is the
  # both-parents discriminator (see the sh merge test above).
  assert_output --partial "File stats:"
  assert_output --partial "side-shp.txt"
  assert_output --partial "feature2.txt"
  # Chatter containment: shc runs under HUG_QUIET=T inside shp too.
  refute_output --partial "Changed files"
  # Patch side: FIRST-PARENT only. side-shp.txt is the parent-1-side file;
  # feature2.txt is identical to parent 1, so it appears in stats but must
  # NOT render as a patch hunk (targeted refute — a bare "feature2.txt"
  # refutation would wrongly fail on the stats section).
  assert_output --partial "diff --git a/side-shp.txt b/side-shp.txt"
  refute_output --partial "diff --git a/feature2.txt"
}
```

Add these new tests after it:

```bash
@test "hug shp --llm: merge <diff> CDATA carries the first-parent patch (issue 346)" {
  # The existing sh --llm merge pin covers <stats> (sh has no patch). shp is
  # the patch-bearing LLM surface: the CDATA must carry the parent-1 patch.
  _setup_merge_fixture side-llm2
  run hug shp --llm HEAD
  assert_success
  assert_output --partial "<diff>"
  assert_output --partial "diff --git a/side-llm2.txt b/side-llm2.txt"
  refute_output --partial "diff --git a/feature2.txt"
}

@test "hug shp: dirty merge shows the full first-parent diff (not combined hunks)" {
  # Pre-#346, git show rendered a combined --cc diff on dirty merges
  # (resolution hunks only). The first-parent contract shows the whole
  # parent-1 diff — a superset that includes the resolution (probe-checked:
  # diff --cc c.txt -> diff --git a/c.txt b/c.txt). Deliberate change, pinned.
  printf 'a\n' > c.txt && git add c.txt && git commit -qm c-base
  git checkout -qb dirty-side
  printf 'a\nside\n' > c.txt && git commit -qam side-edit
  git checkout -q main
  printf 'a\nmain\n' > c.txt && git commit -qam main-edit
  git merge --no-ff dirty-side >/dev/null 2>&1 || true # conflict expected
  printf 'a\nresolved\n' > c.txt && git add c.txt && git commit -qm resolved
  run hug shp HEAD
  assert_success
  assert_output --partial "diff --git a/c.txt b/c.txt"
  refute_output --partial "diff --cc"
}

@test "hug shp: ours-strategy merge keeps an empty patch section (legitimate)" {
  # -s ours: the merge result equals parent 1, so the FIRST-PARENT diff is
  # empty by construction. The help contract promises parent-1 content, not
  # non-empty content — this pin guards that wording (O-002 in the spec).
  git checkout -qb ours-side HEAD~1
  echo o > ours-side.txt && git add ours-side.txt && git commit -qm ours-side
  git checkout -q main
  git merge -q -s ours ours-side -m "Ours merge"
  run hug shp HEAD
  assert_success
  refute_output --partial "diff --git"
  assert_output --partial "File stats:"
  assert_output --partial "feature2.txt"
}

@test "hug shp: non-merge rename commit still renders rename entries (git show kept off-merge)" {
  # Guards the merge gate's off-branch: swapping `git show` for diff-tree
  # wholesale would silently turn renames into delete+add on EVERY non-merge
  # patch (diff-tree does not honor diff.renames; git show does). Repo-local
  # config keeps the pin deterministic against exotic global configs.
  git config diff.renames true
  git mv feature1.txt renamed1.txt && git commit -qm rename1
  run hug shp HEAD
  assert_success
  assert_output --partial "rename from feature1.txt"
  assert_output --partial "rename to renamed1.txt"
}
```

- [ ] **Step 6: Run unit to green (help edits still pending — expect only -h probes red)**

Run: `make test-unit TEST_FILE=test_sh.bats TEST_FILTER="shp"`
Expected: new tests pass EXCEPT any help probe added below; the flipped `:679` test now passes.

- [ ] **Step 7: Update sh, shp, shv help texts**

`git-config/bin/git-sh:63-65` — replace:
```
    Merge commits: File stats list changes vs EACH parent (a file touched
    on both sides appears once per parent) — see 'hug shc -h' for the
    full contract. (sh shows no patch; shp/shcp patches stay empty on
    clean merges.)
```
with:
```
    Merge commits: File stats list changes vs EACH parent (a file touched
    on both sides appears once per parent) — see 'hug shc -h' for the
    full contract. (sh shows no patch; shp/shcp patches show the
    FIRST-PARENT diff on merges — empty when the merge introduces nothing
    vs parent 1, e.g. -s ours.)
```

`git-config/bin/git-shp:42-44` — replace:
```
    Merge commits: File stats list changes vs EACH parent (a file touched
    on both sides appears once per parent); the patch section stays empty
    on clean merges — see 'hug shc -h' for the full contract.
```
with:
```
    Merge commits: File stats list changes vs EACH parent (a file touched
    on both sides appears once per parent); the patch section shows the
    FIRST-PARENT diff — what the merge brought in (same rule as `hug dd`;
    empty when the merge introduces nothing vs parent 1, e.g. -s ours) —
    see 'hug shc -h' for the full stats contract.
```

`git-config/bin/git-shv:52-54` — replace:
```
    A single commit is diffed against its FIRST parent, so `shv <merge>` can
    differ from `shp <merge>` (which renders a combined diff), and a root commit
    shows every file as added.
```
with:
```
    A single commit is diffed against its FIRST parent, so `shv <merge>` and
    `shp <merge>` agree on merges (both show the parent-1 diff — shv in a
    difftool window, shp as text), and a root commit shows every file as added.
```

Add an shv help probe to `tests/unit/test_shv.bats` (new test at the end):

```bash
@test "hug shv -h: shv and shp agree on merges (no combined-diff contrast)" {
  run hug shv -h
  assert_success
  refute_output --partial "combined diff"
  assert_output --partial "FIRST parent"
}
```

And add sh/shp help probes to `tests/unit/test_sh.bats` (near the `:443` shc -h probe):

```bash
@test "hug sh/shp -h: merge patch contract is first-parent, not empty" {
  run hug sh -h
  assert_success
  assert_output --partial "FIRST-PARENT"
  refute_output --partial "stay empty"
  run hug shp -h
  assert_success
  assert_output --partial "FIRST-PARENT"
  refute_output --partial "stays empty"
}
```

- [ ] **Step 8: Run all three files, then commit**

Run: `make test-unit TEST_FILE=test_sh.bats && make test-unit TEST_FILE=test_shv.bats && make test-lib TEST_FILE=test_hug_git_show.bats` → all pass.

```bash
hug a git-config/lib/hug-git-show git-config/bin/git-sh git-config/bin/git-shp git-config/bin/git-shv tests/lib/test_hug_git_show.bats tests/unit/test_sh.bats tests/unit/test_shv.bats
hug c -F - <<'EOF'
feat(sh/shp): first-parent merge patches via hug-git-show gate (issue elifarley/hug-scm#346)

WHY: shp's patch section (standard and --llm <diff> CDATA) is empty on
clean merges while its stats are merge-aware — the shp leg of #346.

WHAT: _show_commit_standard and _show_commit_llm gate on is_merge_commit:
merges emit the two-tree first-parent diff (shared helper); non-merges
and root commits keep `git show` byte-identical — load-bearing, since
git show honors diff.renames and diff-tree does not (regression-pinned).
Dirty merges deliberately change from combined --cc hunks to the full
first-parent superset (pinned). Ours-strategy merges keep an empty patch
section by construction (pinned; wording caveat). The old shp pin that
refuted any "diff --git" on merges is inverted (:679 -> parent-1 hunk
present, parent-2-only hunk absent). Lib-level merge pins added — none
existed before (grep zero hits). sh/shp/shv help state the contract;
shv's dead "renders a combined diff" contrast is reworded (shv and shp
now agree on merges).

HOW: The gate keeps byte-identity structural: off-merge code paths are
untouched, so rename rendering and every other git show property survive
without probe-best-effort claims.

IMPACT: Merge review via shp (human and LLM consumers) sees exactly what
the merge introduced; help texts no longer contradict each other about
shp's merge output.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
```

---

### Task 5: Family-wide docs — shc NOTE, head.md, stale test comment, sweep, full validation

**Goal:** Every remaining artifact that describes the family's merge behavior states the new contract; the whole suite and docs build pass.

**Files:**
- Modify: `git-config/bin/git-shc:14-19` (NOTE block)
- Modify: `docs/commands/head.md:217`
- Modify: `tests/unit/test_sh.bats:634-635` (comment inside the sh merge test)

**Acceptance Criteria:**
- [ ] The shc NOTE describes patch parity as DONE (patch = parent 1, stats = each parent, ours-merge caveat, hug-file-input boundary unchanged).
- [ ] `docs/commands/head.md:217` no longer says patch sections stay empty.
- [ ] The `:634` test comment no longer describes #346 as open.
- [ ] Sweep: `grep -rnE "stays? empty|patch parity|combined diff" docs/ README.md git-config/ tests/ CHANGELOG.md | grep -v .vitepress/dist` shows only expected residuals: `CHANGELOG.md:10` (released v1.18.0.0 history — stays; the NEXT release note must supersede it, recorded in the PR body), this spec/plan's own quotations, and historical spec/plan docs.
- [ ] `make test-bash` passes; `make docs-build` succeeds.

**Verify:** `make test-bash` → all pass; `make docs-build` → success.

**Steps:**

- [ ] **Step 1: Rewrite the shc NOTE** (replace `git-shc:14-19`)

```bash
# NOTE: since the issue-268 fix, merge commits list per-parent diffs (git -m);
# the contract is test-pinned in tests/unit/test_sh.bats. sh, shp and shcp
# inherit merge-aware STATS via their git shc delegation. Patch parity is DONE
# (elifarley/hug-scm#346): shp/shcp patches show the FIRST-PARENT diff on
# merges (the hug dd rule; empty when the merge introduces nothing vs parent 1,
# e.g. -s ours) — patch = parent 1, stats = each parent. hug-file-input does
# NOT pass --merge-aware and stays suppressed (deliberate boundary).
```

- [ ] **Step 2: Flip head.md:217** — replace the sentence "Patch sections stay empty on clean merges — that's git's own suppression; for the first-parent-only stat view, use `git show --stat <merge>`." with:

```markdown
Patch sections on merges show the FIRST-PARENT diff — what the merge brought in (the same rule as `hug dd`; empty when the merge introduces nothing vs parent 1, e.g. `-s ours`) — while stats list changes against EACH parent.
```

- [ ] **Step 3: Update the stale test comment** (replace `tests/unit/test_sh.bats:634-635`)

```bash
  # (sh has no patch section; shp/shcp patches diff against parent 1 on
  # merges — elifarley/hug-scm#346.)
```

- [ ] **Step 4: Run the sweep and audit residuals**

Run: `grep -rnE "stays? empty|patch parity|combined diff" docs/ README.md git-config/ tests/ CHANGELOG.md | grep -v ".vitepress/dist" | grep -v "superpowers/"`
Expected hits: `CHANGELOG.md:10` (released history — allowed; supersession recorded in the PR body), `git-config/bin/git-shc` NOTE's own "stays suppressed" line about hug-file-input (that one is about file-input, accurate — keep), and nothing else new.

- [ ] **Step 5: Full validation**

Run: `make test-bash` → all pass (2902+ tests).
Run: `make docs-build` → success.

- [ ] **Step 6: Commit**

```bash
hug a git-config/bin/git-shc docs/commands/head.md tests/unit/test_sh.bats
hug c -F - <<'EOF'
docs(sh): family-wide merge-contract wording — patch parity done (issue elifarley/hug-scm#346)

WHY: The shc NOTE ("patch parity is tracked as elifarley/hug-scm#346"),
head.md ("Patch sections stay empty on clean merges"), and a test comment
all describe the old behavior; after the parity change they contradict
the code and point readers at a closed issue as open.

WHAT: shc NOTE states the done split (patch = parent 1, stats = each
parent, -s ours empty-patch caveat, hug-file-input boundary unchanged);
head.md flip; stale comment updated. CHANGELOG.md:10 (v1.18.0.0) is
released history and stays — the NEXT release note must supersede it
explicitly (recorded in the PR body).

HOW: Wording-only; the sweep regex (stays? empty|patch parity|combined
diff) over docs/, README.md, git-config/, tests/, CHANGELOG.md now
surfaces only allowed residuals (released history + historical spec docs).

IMPACT: No user-facing or maintainer-facing text claims merge patches
stay empty or that shp renders a combined diff; the documented contract
is uniform across shc/sh/shp/shcp/shv help, head.md, and the lib NOTE.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
```

---

## Task dependency graph

Task 1 (independent) → Task 2 (helper) → Task 3 (shcp) → Task 4 (hug-git-show + help) → Task 5 (family docs + validation). Tasks 3 and 4 both depend on Task 2; they touch disjoint production files (git-shcp vs hug-git-show+sh/shp/shv) but the same test file's help-probe region — run serially.

## Out of scope (from the spec)

Stats axis, `pinned_diff` patch-format extension, CHANGELOG entry mechanics (ship workflow — but the superseding sentence is a PR-body requirement), unifying the shp/shcp rename-rendering split on non-merges, hg-config.

## PR body requirement (for cv-plan-pr)

The PR description MUST state: "Patch sections on merges now show the first-parent diff (supersedes the v1.18.0.0 CHANGELOG note)." so upgrading readers of CHANGELOG.md:10 get the supersession explicitly.
