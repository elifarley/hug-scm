# Design: `hug cmv --wt` — move commits to a branch and ensure it has a worktree

**Date:** 2026-08-12
**Status:** Approved (brainstorming)
**Related:** `hug cmv` (git-config/bin/git-cmv), `hug wtc` (git-config/bin/git-wtc), `hug-git-worktree` library

## Summary

Add a `--wt` flag to `hug cmv` so a single command can move commits to another branch *and* ensure that branch has a worktree. The flag's meaning is deliberately narrow: **"if the target branch doesn't have a worktree, create one for it — otherwise use the existing one."** The move is performed in/for that worktree; the user stays on the source branch in the current worktree.

This makes the common "accidentally committed to the wrong branch, I want to keep working on it in a worktree" scenario a one-shot operation, and it also routes cmv's existing-branch path through the worktree (closing a pre-existing gap where plain cmv errors on a target checked out elsewhere).

## Terminology

- **source branch** — the branch the commits are moved *from* (where cmv runs).
- **target branch** — the branch the commits are moved *to* (`<branch>` argument).
- **detach case** — target branch is new (created by cmv at original HEAD): exact SHAs preserved, no conflicts possible.
- **cherry-pick case** — target branch exists: commits are cherry-picked onto it (new SHAs, may conflict).

## Goals

- One-shot `cmv ... --wt`: move commits AND ensure target branch has a worktree.
- End-state: user stays on the source branch; the target branch lives in its worktree.
- Reuse `hug-git-worktree`'s existing machinery (path generation, validation, safe-tier confirmation) — no duplicate logic.
- Composable with `--new`, `-u`/`--upstream`, `--force`, `--quiet`.
- Follow the family-wide safety-tier model exactly: the move stays danger-tier; worktree creation stays safe-tier.
- Recovery is the inverse cmv; no separate recovery command.

## Non-goals (YAGNI)

- No `--wt-path` / custom worktree path (auto-generated only; `hug wtc <branch> <path>` covers custom paths).
- No SHA-preserving `mff` tip (inverse cmv is correct in every case).
- No changes to cmv's default (non-`--wt`) end-state: still ends up on the target branch.
- No `--detach` worktree support, no changes to `hug wt`/`hug wtl`/`hug wtdel`.

## Section 1 — Flag & semantics

**New flag:** `hug cmv [N|COMMIT] <branch> --wt`

- `--wt` = "ensure the target branch has a worktree: create one if missing, otherwise use the existing one." The move is performed in/for that worktree; the user stays on the source branch.
- Auto-generated path only: `../<repo>.WT.<branch>` via `generate_worktree_path`.
- Composable with `--new` (creates the branch if missing) and `-u`/`--upstream`.
- Implies nothing about branch creation (that's `--new`'s job).
- Without `--wt`, behavior is unchanged.

**End-state inversion under `--wt`:** today cmv ends with you *on the target branch* in the current worktree. A branch checked out in your current worktree can't also get a worktree (git hard rule). So with `--wt`, the target branch lives in its worktree and you stay on the source branch (reset back, as cmv already does).

## Section 2 — The 4 real scenarios

2×2×2 (branch exists × `--new` × worktree exists) collapses to 4 real cases; `--new` is a no-op when the branch exists, and a branch can't have a worktree if it doesn't exist.

| # | Branch exists | `--new` | Worktree exists | Behavior under `--wt` |
|---|---|---|---|---|
| 1 | no | no | no | Prompt: create branch + worktree? → same result as #2 |
| 2 | no | yes | no | **Flagship**: branch at original HEAD, wt auto-created, main reset, you stay on main |
| 3 | no | yes/no | yes | Impossible (no branch ⇒ no wt) |
| 4 | yes | no/yes | no | Create wt, cherry-pick X inside it, main reset, you stay on main |
| 5 | yes | no/yes | yes | Use existing wt: cherry-pick X inside it, main reset, you stay on main |

**Worked examples** (repo `proj`, on `main`: `M2 ← M1 ← X` — X is the accidental commit):

**A. Flagship — `hug cmv 1 feature --new --wt`** (#2)
```
Before:  main = M1→X        feature: —          wt: —
After:   main = M1           feature = X (original SHA preserved)
         wt: ../proj.WT.feature  @ feature      You: still on main, clean
```
One command, no SHA rewrite, no conflict possible.

**B. Missing branch, no `--new`** (#1) — `hug cmv 1 feature --wt`
Same as A, but cmv first prompts "Branch 'feature' doesn't exist. Create it and its worktree?" → `n` = nothing happens.

**C. Branch exists, no wt** (#4) — `hug cmv 1 feature --wt`
```
Before:  main = M1→X   feature = F1   wt: —
After:   main = M1      feature = X' (new SHA, cherry-picked)   wt: @ feature
```
The cherry-pick runs **inside the new worktree** — if it conflicts, the mid-move state lives in `feature`'s own worktree (resolve there, `hug caa`), which is a cleaner recovery story than today's abort-stuck-on-target.

**D. Branch exists + wt exists** (#5) — `hug cmv 1 feature --wt`
```
Before:  main = M1→X   feature = F1   wt: ../proj.WT.feature @ feature
After:   main = M1      feature = X'   wt: same path, updated in place
```
No worktree created. The move runs via `git -C <wt> cherry-pick`, so the branch ref moves and the existing worktree follows.

**Edge case** (#3/#4): a *deleted* branch can leave a detached worktree behind. Treat "has a worktree" as "a non-detached worktree on that branch" — a detached leftover doesn't count; we create a fresh one and leave the stale one for `hug wtdel`.

## Section 3 — Operation order & safety tiers

**Order of operations (critical):**

1. Resolve target & range (as today).
2. If branch missing + `--new`/prompt → create branch at original HEAD.
3. **If `--wt`: create/verify the worktree FIRST** (before any reset or cherry-pick), so failures leave the repo untouched.
4. Reset source branch back to target (danger tier, as today).
5. Perform the move in/for the worktree (detach for new branch, cherry-pick inside wt for existing).

**Tier separation (the key standard):**

- The **move** stays **danger-tier**: `prompt_confirm_danger`, `-y` refuses with exit 3, `-f` proceeds.
- The **worktree creation** is **safe-tier**: `prompt_confirm_safe` (defaults Yes), `-y` auto-confirms, no `-f` needed.

They compose: with `--wt`, the worktree creation confirms at safe tier, then the move confirms at danger tier (or is skipped by `-f`). A `-y` invocation still refuses the *move* — the safe worktree prompt never authorizes the danger-tier move.

## Section 4 — Guards & error handling

- **Locked worktree** → error clearly (don't plow through a lock).
- **Dirty worktree** (existing wt case) → let git refuse cleanly if cherry-pick would clobber; surface the error; mid-move state stays in the wt where it's visible.
- **Stale/missing worktree dir** → error, suggest `hug wtdel`/`wtprune` first.
- **`--wt` with a target branch checked out in the current worktree** → error (git hard rule; we never create a wt for the branch we're on — that's the whole point of the inverted end-state).
- **Guards use `error_blocked` / exit 3** for safety-blocked states, consistent with wtc/wtdel.

## Section 5 — Recovery (inverse cmv)

**cmv is its own inverse** — no separate recovery command needed.

**Plain cmv (no `--wt`):**
```
$ hug cmv 1 feature --new        # main: M1→X  ⇒  main: M1, feature: X, you're on feature
# undo:
$ hug cmv 1 main                 # run from feature (where you are)
                                 # feature: X ⇒ feature: M1, main: M1→X', you're back on main
```

**With `--wt`:**
```
$ hug cmv 1 feature --new --wt   # main: M1, feature: X in ../proj.WT.feature, you're on main
# undo:
$ cd ../proj.WT.feature
$ hug cmv 1 main --wt            # main's worktree exists ⇒ move happens in main's wt
                                 # feature: M1, main: M1→X', you stay in feature's wt
# cleanup (optional):
$ hug wtdel feature -B           # remove the now-empty feature worktree + branch
```

**Honest caveats:**

1. **SHA rewriting:** the inverse cmv cherry-picks, so X comes back as X′ (content-identical, new SHA). Bit-exact SHA restore (e.g. for already-pushed commits) is out of scope for cmv.
2. **Drift:** recovery is clean only if you haven't committed more on either branch since. If feature gained commits, `cmv 1 main` moves those, not the originals — the user adjusts N.
3. **Tier consequence:** a real recovery path makes the "NOT RESTORABLE" contract obsolete. Keep the **danger tier** — recovery requires knowing N + the original branch + undrifted state, and SHA rewriting is irreversible once published. The messaging changes, not the tier.

**Design decisions:**
- Post-op, cmv prints a recovery hint (suppressed under `--quiet`, like `emit_head_recovery_hint`):
  - No `--wt`: `hug cmv <N> <original-branch>` (run from wherever you are).
  - With `--wt`: `cd <wt-path> && hug cmv <N> <original-branch> --wt` (or `hug wtdel` cleanup note).
- Help text's "NOT RESTORABLE" becomes "restorable via the inverse cmv."
- **No mff tip** — the inverse cmv is correct in every case; a SHA-preserving tip would only serve a narrow already-pushed scenario that's not the flagship use case.

## Section 6 — Implementation (approach A)

- Extract a shared library function `create_worktree_for_branch <branch> [--base <point>]` into `hug-git-worktree` (path gen, validation, safe-tier confirm, dry-run).
- `wtc` refactored to call it (no behavior change); cmv calls it too.
- cmv's `--wt` invokes it with `--base <original_head>` when creating a new branch; when the branch exists, it resolves the existing worktree (and only creates one if none exists — never "bare create for existing").
- Existing-branch move: `git -C <wt-path> cherry-pick <target>..HEAD` (no temp-branch dance needed inside the wt).
- Update `docs/commands/commits.md`, command-map, help text, and add BATS tests for all 5 scenarios + guards + tier separation.

### Section 6.1 — Documentation updates

User-facing docs are updated **when the feature lands** (not before — the design spec is the only pre-implementation artifact). The full list:

| File | Change |
|---|---|
| `docs/commands/commits.md` | cmv section: add `--wt` to usage line, scenario table, examples, safety notes |
| `git-config/bin/git-cmv` help text | Add `--wt` to USAGE/OPTIONS/DESCRIPTION; update "NOT RESTORABLE" → inverse-cmv recovery wording |
| `README.md` (line ~480) | cmv one-liner: `hug cmv [N] <branch> [--new]` → add `[--wt]` |
| `docs/command-map.md` (line ~124) | cmv entry: note `--wt` |
| `CHANGELOG.md` | Feature entry when released |

**Not to update:** `docs/commands/worktree.md`, `git-config/lib/python/articles/agents.md`, `git-config/lib/python/articles/worktree.md` (worktree *management* docs — cmv is a commit command, not a worktree command; at most a "see also" cross-ref once it lands). `CLAUDE.md` / `.github/copilot-instructions.md` are command lists, no usage detail. Historical specs (2026-07-27/-28/-29/-30) stay as-is — they record the then-current danger-tier/not-restorable contract and are immutable once merged.

## Section 7 — Testing

Add to `tests/unit/test_commit.bats` (cmv's home):

1. **Flagship** (#2): `cmv 1 feature --new --wt` → main reset, feature at X, wt exists, you stay on main.
2. **Missing branch, no `--new`** (#1): prompt to create branch + worktree; `n` = nothing.
3. **Existing branch, no wt** (#4): wt created, cherry-pick inside it, main reset.
4. **Existing branch + wt** (#5): no new wt; move via `git -C <wt> cherry-pick`; branch ref moves in place.
5. **Detached leftover wt** (edge): fresh wt created, stale one untouched.
6. **Tier separation:** `-y` refuses the move (exit 3) even though wt creation would be safe; `-f` proceeds.
7. **Guards:** locked wt → error; stale/missing wt dir → error suggesting wtdel/wtprune; target checked out in current worktree → error_blocked.
8. **Recovery hint:** post-op prints `hug cmv <N> <original-branch>`; suppressed under `--quiet`.

## Section 8 — Verification commands

```bash
make test-unit TEST_FILE=test_commit.bats TEST_FILTER="cmv"
make test-bash
make test
```

## Risks / notes

- The existing-branch cherry-pick inside a worktree changes where mid-move conflict state lives (in the wt, not the current worktree). This is a *better* recovery story, but tests must assert the state is visible in the wt.
- `--wt` routes around a pre-existing cmv gap: plain cmv errors when the target branch is checked out in another worktree. No behavior change for plain cmv.
- Refactoring `wtc` to call the shared function must be behavior-preserving — existing wtc tests are the guard.
