# `cmoda` Dirty-Tree Safety — Design Spec

**Date:** 2026-06-29
**Status:** Approved (brainstorming complete; awaiting spec review → writing-plans)
**Issue:** [elifarley/hug-scm#190](https://github.com/elifarley/hug-scm/issues/190)
**Branch / worktree:** `fix-cmoda-dirty-tree-safety`

## Problem

`hug cmoda` (Commit MODify **A**ll) amends the last commit with **all tracked
changes** via `git commit -a --amend`. The semantics are correct, but the
command is **hostile in a dirty working tree**: when the tree contains modified
tracked files unrelated to the amend intent, `cmoda` silently folds them in —
no preview, no confirmation.

The help text actively nudges toward this footgun: its tagline sells
`cmoda` as a convenience (*"No need to stage files first"*) and never warns
that a dirty tree turns that convenience into a scope-expansion hazard. `cmod`
and `cmoda` differ by one letter, and that letter's effect ("all tracked") is
not surfaced as a risk.

### Real incident (2026-06-29)

The user had explicitly staged exactly three intended files, then ran
`hug cmoda --no-edit` (reaching for it by reflex) instead of `hug cmod
--no-edit`. Result: a commit with **7 files changed** — three unrelated files
swept in. Recovery required `hug h back 1 --force` + redo with `cmod`.

This is a **documentation + UX safety** gap, not a behavioral bug in the git
layer. Hug's calling card is being *safer-than-git for autonomous agents*; the
current help text and lack of a runtime guard fail that promise for `cmoda`.

## Scope (decided with the user)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **How far** | Docs **+** tests **+** blocking runtime guard | The user opted for runtime protection, not docs-only. Accepts the backward-compat cost (below), bounded by the narrow trigger. |
| **Guard trigger** | **Footgun signature only**: `has_staged_changes && has_unstaged_changes` | Catches the exact incident with minimal blast radius. Pure-unstaged and all-staged trees never prompt. |

**Backward-compat cost (accepted):** a `warn`-tier prompt cancels in
non-interactive shells (no TTY) without `-y`/`-f`. Because the trigger is the
footgun signature only, **the only flows that break are the genuinely dangerous
ones** — an agent that staged a subset and then ran `cmoda` non-interactively
gets stopped (the desired outcome). Pure-unstaged and all-staged `cmoda` calls
continue to work unprompted, non-interactively, exactly as today.

## Design

### Section 1 — `git-cmoda` help text (`git-config/bin/git-cmoda`)

**Tagline** (currently line 17) — demote the convenience framing that caused the
mistake:

```
hug cmoda: Commit MODify All - Amend the last commit with ALL tracked changes (staged + unstaged).
⚠️ In a dirty tree this captures every modified tracked file. Prefer 'hug cmod' after explicit 'hug a' for surgical amends.
```

**New WARNING block** — inserted after `"Untracked files are NOT included."`,
before the existing history-rewrite WARNING (two distinct concerns: scope vs.
history):

```
  WARNING: Dirty-tree scope hazard. cmoda stages and amends EVERY modified
  tracked file. If your working tree has changes unrelated to this amend,
  cmoda will fold them in. For a surgical amend, stage explicitly:

      hug a <file>...      # stage only the intended files
      hug cmod --no-edit   # amend with ONLY the staged set

  Safety guard: when you have a staged subset AND other unstaged tracked
  changes, cmoda shows what it will fold in and asks for confirmation before
  amending. Pass -y to confirm without prompting (-f also works).
```

**SEE ALSO** — change the `cmod` line to carry the behavioral contrast:

```
  hug cmod : Amend the last commit with STAGED changes only (surgical — preferred in dirty trees)
```

### Section 2 — `git-cmod` help text (`git-config/bin/git-cmod`)

**New TIP** — after the existing `"Run 'hug sls' first ..."` TIP:

```
  TIP: Prefer 'hug cmod' over 'hug cmoda' when your working tree has unrelated
  modified files. 'cmoda' auto-stages every tracked change and will fold
  unrelated work into the amended commit.
```

**SEE ALSO** — change the `cmoda` line to carry the behavioral contrast:

```
  hug cmoda: Amend the last commit with ALL tracked changes (scope-expanding — avoid in dirty trees)
```

### Section 3 — Runtime guard

**Location:** a new function `confirm_amend_all_scope()` in
`git-config/lib/hug-git-commit` (already sourced by `git-cmoda`). The script
stays a thin wrapper, per the `bin/` convention ("keep most of the work in
library functions").

**Building blocks (all already exist):**
- `has_staged_changes()` / `has_unstaged_changes()` — `hug-git-state`
- `list_staged_files --status` / `list_unstaged_files --status` — `hug-git-files`
- `prompt_confirm_warn` — `hug-confirm` (warn tier)

**Shape:**

```bash
# confirm_amend_all_scope: guard for `hug cmoda`.
# WHY: cmoda runs `git commit -a --amend`, auto-staging every tracked change.
# In a mixed tree (curated staged subset + other unstaged edits) that silently
# captures unrelated work. We prompt ONLY in that ambiguous case; pure-unstaged
# (clear "amend everything" intent) and all-staged (cmoda ≡ cmod) proceed
# unprompted to preserve cmoda's power-tool ergonomics.
# Escape hatch: -y/HUG_YES or -f/HUG_FORCE auto-confirm (warn tier).
confirm_amend_all_scope() {
  has_staged_changes && has_unstaged_changes || return 0   # not the footgun case
  # preview (to stderr): staged set vs the additional unstaged files
  # prompt_confirm_warn "Amend with ALL tracked changes (staged + unstaged)? [y/N]: "
}
```

**Preview format** (to **stderr** — chatter, not data; `cmoda` produces no
machine-consumable stdout):

```
⚠️  cmoda scope check: your staged set is a SUBSET of all tracked changes.

    Staged — what 'hug cmod' would amend:
      <list_staged_files --status>

    Unstaged — cmoda will ALSO fold these in:
      <list_unstaged_files --status>

Amend with ALL tracked changes (staged + unstaged)? [y/N]:
```

**Partially-staged files** (a file with both staged *and* unstaged hunks)
legitimately satisfy the trigger and appear in **both** preview lists — this is
correct and informative: it signals the file has unstaged hunks that `cmoda`
will additionally include but `cmod` would not. No special-casing needed.

**Tier — `warn` (not `danger`):** an amend is destructive-but-**recoverable**
(`hug h back 1 --force` / reflog). `warn` means both `-y` and `-f` auto-confirm
— which is exactly what we want as the escape hatch. `danger` tier would make
`-y` a hard error (exit 3) and demand `-f`, friction we explicitly reject for
agents. (Per `hug-confirm`'s tier table, `-y` vs `-f` differ only at `danger`
tier and in blocked states; at `warn` they are equivalent.)

**Non-interactive (no TTY) without `-y`/`-f`:** the preview + a one-line
guidance tip print first, then `prompt_confirm_warn` cancels with
"Non-interactive environment: cancelled." The agent sees exactly why and the two
ways forward: `hug cmod` (staged-only) or `hug cmoda -y` (fold in everything).

**Escape hatch — already wired:** `parse_common_flags` consumes `-y`/`-f`/`-q`
and emits `set -- <leftover>`, so they are stripped from the args forwarded to
`git commit -a --amend` and surfaced as `HUG_YES` / `HUG_FORCE`. No new flag
plumbing needed. `prompt_confirm_warn` already honors both env vars.

**Call site (`git-cmoda`):** `check_git_repo` → `confirm_amend_all_scope` →
`info "Amending…"` → `git commit -a --amend "$@"`. (Move the existing
`info "Amending…"` to *after* the guard so we don't announce an amend we then
cancel.) Guard logic is orthogonal to message flags (`-m`, `--no-edit`, `-C`,
`-c`), which continue to flow through untouched.

### Section 4 — Tests

**Behavioral → `tests/unit/test_commit.bats`** (NOT `test_quality_corpus.py`,
which tests help-search relevance, not commit behavior). Five cases, using the
file's existing non-interactive harness:

1. **Pure unstaged** (nothing staged), N modified files → `cmoda --no-edit`
   non-interactive **proceeds**, amends all N. (Guard does not fire.)
2. **All staged** (no unstaged) → `cmoda --no-edit` **proceeds**, amends the
   staged set. (Guard does not fire; `cmoda ≡ cmod`.)
3. **Footgun**: stage a subset, leave other tracked files unstaged →
   `cmoda --no-edit` non-interactive **cancels**; commit unchanged (file count
   stable) + cancellation message.
4. **Footgun + `-y`**: same setup + `cmoda -y --no-edit` → **proceeds**, folds
   in staged + unstaged.
5. **Paired `cmod` control** (the issue's explicitly-requested assertion): stage
   a subset → `cmod --no-edit` amends **exactly** the staged set; unstaged files
   remain unstaged.

**Search regression → `git-config/lib/python/tests/test_quality_corpus.py`:**
run it to confirm the help-text edits don't drop `hug cmod` out of top-5 for the
query `"amend"` (current assertion, line 57). No new behavioral assertion added
here — the corpus stays a relevance net.

### Section 5 — Doc sync (consistency with the new help text)

- `docs/commands/commits.md` — the `cmoda` section (~lines 147–165): add a short
  dirty-tree note + "prefer `hug cmod` for surgical amends," mirroring the help
  text.
- `README.md` (~line 474) — lightly annotate the `cmoda` one-liner (e.g. "…all
  tracked changes — prefer `cmod` in dirty trees"). Keep it terse.
- `make docs-build` must still succeed.

## Out of scope

- **Agent-facing memory file** (`~/.../AGENTS.d/git-repos.md`): lives in a
  *different* repo and is **already hardened** with this exact dirty-tree
  warning + `cmoda` anti-pattern + recovery steps. A possible follow-up there is
  adding `-y` to its `cmoda` examples so they keep working under the footgun
  guard — but that is not this PR.
- **Broader "always prompt" guard**: rejected. Would add friction to the
  unambiguous power-tool cases and break far more non-interactive callers.

## Acceptance criteria

From the issue, plus our additions:

- [ ] `git-cmoda` help carries a WARNING block describing the dirty-tree hazard,
      recommends `cmod` for surgical amends, and documents the guard + `-y`.
- [ ] `git-cmoda` tagline no longer leads with "No need to stage files first."
- [ ] `git-cmod` help adds a TIP contrasting `cmoda`.
- [ ] Both scripts' SEE ALSO sections describe the trade-off in one line.
- [ ] `cmoda` runtime guard fires **only** on the footgun signature, previews
      the captured files, and confirms via `prompt_confirm_warn`.
- [ ] `-y` / `-f` skip the guard; non-interactive + neither = cancel with
      guidance.
- [ ] `tests/unit/test_commit.bats` has the 5 cases above (incl. paired
      cmod/cmoda dirty-tree behavior).
- [ ] `test_quality_corpus.py` stays green (`"amend"` → `hug cmod` in top-5).
- [ ] `docs/commands/commits.md` + `README.md` synced; `make docs-build` green.

## Files touched

| File | Change |
|------|--------|
| `git-config/bin/git-cmoda` | Tagline, WARNING block, SEE ALSO; call guard before amend |
| `git-config/bin/git-cmod` | TIP, SEE ALSO |
| `git-config/lib/hug-git-commit` | New `confirm_amend_all_scope()` |
| `tests/unit/test_commit.bats` | 5 behavioral cases |
| `docs/commands/commits.md` | Dirty-tree note in cmoda section |
| `README.md` | cmoda one-liner annotation |

## Verification

```bash
hug help cmoda            # WARNING block + new SEE ALSO present
hug help cmod             # new TIP + new SEE ALSO present
make test-unit TEST_FILE=test_commit.bats
make test-lib-py TEST_FILTER=test_quality_corpus
make docs-build
make sanitize-check       # static analysis
```

## References

- Issue: [elifarley/hug-scm#190](https://github.com/elifarley/hug-scm/issues/190)
- Sources: `git-config/bin/git-cmod`, `git-config/bin/git-cmoda`
- Libraries: `git-config/lib/hug-git-state` (`has_staged_changes`,
  `has_unstaged_changes`), `git-config/lib/hug-git-files`
  (`list_staged_files`, `list_unstaged_files`), `git-config/lib/hug-confirm`
  (`prompt_confirm_warn`, tier table), `git-config/lib/hug-cli-flags`
  (`parse_common_flags` arg-stripping)
- Prior art: `mgmt/plans/2026-05-05-non-interactive-y-flag-design.md`
  (the `-y` / `HUG_YES` three-tier model this guard relies on)
