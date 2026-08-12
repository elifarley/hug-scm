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
- **move target** (`$target`) — the ancestor commit the source branch returns to; the resolved SHA from `resolve_head_target` (as `git-cmv:151-157` already computes).
- **original HEAD** (`$original_head`) — the source branch's pre-op tip, captured before any mutation (as `git-cmv:138` already does).
- **detach case** — target branch is new (created by cmv at original HEAD): exact SHAs preserved, no conflicts possible.
- **cherry-pick case** — target branch exists: commits are cherry-picked onto it (new SHAs, may conflict).
- **has a worktree** — a non-detached worktree on that branch, **INCLUDING the main worktree**. Resolver: `get_worktree_path_by_branch` (main-inclusive, `hug-git-worktree:1390`). The main checkout counts; `get_worktrees` (which excludes main) is NOT the resolver.

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
- Auto-generated path only: `../<repo>.WT.<branch>` via `generate_worktree_path`, with the `generate_unique_worktree_path` collision fallback (`-N` suffix) when that path already exists (`git-wtc:326-334`). Messaging and the recovery hint interpolate the **resolved** path (the runtime variable), never the `../<repo>.WT.<branch>` template.
- Composable with `--new` (creates the branch if missing) and `-u`/`--upstream`.
- Implies nothing about branch creation (that's `--new`'s job).
- Without `--wt`, the move mechanics and end-state are unchanged (still ends on the target branch); **messaging changes**: cmv now prints a recovery hint (suppressed under `--quiet`) and the help text states the inverse-cmv recovery (see Section 5).

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
The cherry-pick runs **inside the new worktree** — if it conflicts, the mid-move state lives in `feature`'s own worktree (resolve there, `hug caa` for a single-commit move; for N>1, `hug caa` completes the current pick and `hug rbc`/`hug ccp` advances the sequencer), which is a cleaner recovery story than today's abort-stuck-on-target.

**D. Branch exists + wt exists** (#5) — `hug cmv 1 feature --wt`
```
Before:  main = M1→X   feature = F1   wt: ../proj.WT.feature @ feature
After:   main = M1      feature = X'   wt: same path, updated in place
```
No worktree created. The move runs via `git -C <wt> cherry-pick`, so the branch ref moves and the existing worktree follows.

**Edge case** (#3/#4): a detached leftover worktree can occupy `../proj.WT.<branch>`. This state is reached by **detaching the worktree's HEAD first (check out a SHA there), then deleting the branch** — not by `git branch -D` while it's checked out (that errors). Treat "has a worktree" as "a non-detached worktree on that branch" — a detached leftover doesn't count. The fresh worktree then lands at the collision-fallback path (`../proj.WT.<branch>-1`); the stale one is left untouched for `hug wtdel`.

## Section 3 — Operation order & safety tiers

**Order of operations (critical — pick-then-reset, confirm-before-mutate):**

1. Resolve the move target (`$target`) and capture `$original_head` (both before any mutation, as `git-cmv:138,151-157` already do).
2. Resolve branch existence (prompt/`--new` **decision only** — branch creation happens inside the worktree call in step 4, not as an independent step).
3. **Gather ALL confirmations before ANY mutation**: if a worktree will be created, the safe-tier prompt; then the danger-tier move prompt. `-y` therefore fails fast with the repo untouched (matching the `-u` path, whose `handle_upstream_operation` confirms danger before any worktree step).
4. **Create the worktree** (and the branch with it, if new) via `create_worktree_for_branch` — this step is additive and rolls back the branch if worktree creation fails (`git-wtc:406-412`).
5. **Pick in the worktree FIRST** (cherry-pick case only): `git -C <wt-path> cherry-pick "$target".."$original_head"`. The moved commits remain reachable via the still-unmoved source branch while the pick is in flight. The detach case needs no pick (the branch is already at `$original_head`).
6. **Reset the source branch to `$target` only after the pick succeeds.** A failed/aborted pick now leaves the repo genuinely untouched, and re-running the identical command retries the *same* move.

**Tier separation (the key standard):**

- The **move** stays **danger-tier**: `prompt_confirm_danger`, `-y` refuses with exit 3, `-f` proceeds.
- The **worktree creation** is **safe-tier**: `prompt_confirm_safe` (defaults Yes), `-y` auto-confirms, no `-f` needed.

They compose **confirm-first, then execute**: with `--wt`, the safe-tier worktree prompt is gathered, then the danger-tier move prompt, and only then does any mutation run (or `-f` skips the move prompt). A `-y` invocation refuses the *move* before the worktree or branch is created — the safe worktree prompt never authorizes the danger-tier move, and no orphan state can appear on a "blocked" exit.

Note: plain cmv uses ONE combined danger prompt for create+move (`git-cmv:195`); under `--wt` the design deliberately splits it into safe (create wt) + danger (move) so the worktree creation can stay safe-tier.

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
$ hug cmv 1 feature --new --wt   # main: M1, feature: X in ../proj.WT.feature (resolved path), you're on main
# undo (from the resolved feature worktree path):
$ cd ../proj.WT.feature
$ hug cmv 1 main --wt            # main's worktree is the MAIN worktree (main-inclusive resolver) ⇒ move happens there
                                 # feature: M1, main: M1→X', you stay in feature's wt
# cleanup (optional):
$ hug wtdel feature -B           # remove the now-empty feature worktree + branch
```
The undo's `--wt` **reuses the main worktree** for `main` — it must not try to create a worktree for a branch checked out in the main worktree (git refuses that, exit 128). This is the concrete test of the "has a worktree = main-inclusive" definition.

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

- Extract a shared library function `create_worktree_for_branch <branch> [--base <point>]` into `hug-git-worktree`. It owns: path generation + `generate_unique_worktree_path` collision fallback, path validation, safe-tier confirmation, dry-run, and the branch-creation rollback on worktree failure (`git-wtc:406-426`). It does **not** own the "checked out elsewhere / main worktree" guards — those stay in the callers (wtc and cmv), since cmv's `--wt` semantics differ (it may *reuse* a worktree rather than refuse).
- `wtc` refactored to call it (no behavior change); cmv calls it too.
- cmv's `--wt` invokes it with `--base <original_head>` **only for the detach case** (new branch); for the cherry-pick case it resolves the existing worktree via `get_worktree_path_by_branch` (main-inclusive) and only creates one if none exists. The branch is created *by* the function (fused, as wtc does), never as an independent step before it.
- Existing-branch move: `git -C <wt-path> cherry-pick "$target".."$original_head"` (a stable SHA range that survives the reset — no temp-branch dance, and `HEAD` is never used as the endpoint because inside the worktree it's the target branch's tip).
- Update `docs/commands/commits.md`, command-map, help text, and add BATS tests for all 5 scenarios + guards + tier separation.

### Section 6.1 — Documentation updates

User-facing docs are updated **when the feature lands** (not before — the design spec is the only pre-implementation artifact). The full list:

| File | Change |
|---|---|
| `docs/commands/commits.md` | cmv section: add `--wt` to usage line, scenario table, examples, safety notes |
| `docs/practical-workflows.md` | §3b "Rescuing Commits on the Wrong Branch with hug cmv": add the one-shot `--wt` flow (natural home for the flagship scenario) |
| `git-config/bin/git-cmv` help text | Add `--wt` to USAGE/OPTIONS/DESCRIPTION; update "NOT RESTORABLE" → inverse-cmv recovery wording |
| `README.md` (line ~480) | cmv one-liner: `hug cmv [N] <branch> [--new]` → add `[--wt]` |
| `docs/command-map.md` (line ~124) | cmv entry: note `--wt` |
| `CHANGELOG.md` | Feature entry when released |

**Not to update:** `docs/commands/worktree.md`, `git-config/lib/python/articles/agents.md`, `git-config/lib/python/articles/worktree.md` (worktree *management* docs — cmv is a commit command, not a worktree command; at most a "see also" cross-ref once it lands). `CLAUDE.md` / `.github/copilot-instructions.md` are command lists, no usage detail. Historical specs (2026-07-27/-28/-29/-30) stay as-is — they record the then-current danger-tier/not-restorable contract and are immutable once merged.

## Section 7 — Testing

In `tests/unit/test_commit.bats` (cmv's home):

**New tests (add):**

1. **Flagship** (#2): `cmv 1 feature --new --wt` → main reset, feature at X (original SHA), wt exists, you stay on main.
2. **Missing branch, no `--new`** (#1): prompt to create branch + worktree; `n` = nothing.
3. **Existing branch, no wt** (#4): wt created, cherry-pick inside it, main reset; **assert feature's tip is X′ (content of X), not merely that a cherry-pick ran**.
4. **Existing branch + wt** (#5): no new wt; move via `git -C <wt> cherry-pick`; branch ref moves in place.
5. **Detached leftover wt** (edge): fresh wt created at the **suffixed** path (`../proj.WT.<branch>-1`), stale one untouched.
6. **Tier separation:** `-y` refuses the move (exit 3) **and no worktree or branch is created**; `-f` proceeds.
7. **Guards:** locked wt → error; stale/missing wt dir → error suggesting wtdel/wtprune; target checked out in current worktree → error_blocked.
8. **Recovery hint:** post-op prints `hug cmv <N> <original-branch>` (plain form) and the `--wt` form with the **resolved** wt path; suppressed under `--quiet`.
9. **Main-worktree reuse:** undo move whose target branch is checked out in the main worktree reuses the main worktree instead of creating one.

**Existing tests to invert (contract change — F-003):**

- Replace `test_commit.bats:1073` ("no recovery hint emitted on success") with "recovery hint emitted on success (plain and --wt forms), suppressed under --quiet".
- Replace `test_commit.bats:1110` ("help states not restorable") with "help states restorable via inverse cmv".

**Code-comment to update (S4):** `git-cmv:163` embeds the 'NOT RESTORABLE' contract in a load-bearing comment — update it alongside the help text.

## Section 8 — Verification commands

```bash
make test-unit TEST_FILE=test_commit.bats TEST_FILTER="cmv"
make test-bash
make test
```

## Risks / notes

- The existing-branch cherry-pick inside a worktree changes where mid-move conflict state lives (in the wt, not the current worktree). With pick-then-reset ordering, the source branch stays intact until the pick succeeds, so abort is clean and the mid-move state is visible in the wt. For N>1 conflicts, `hug caa` completes only the current pick; the continuation is `hug rbc`/`hug ccp` to advance the sequencer — or scope conflict advice to the single-commit case.
- `--wt` routes around a pre-existing cmv gap: plain cmv errors when the target branch is checked out in another worktree. For plain cmv (no `--wt`), move mechanics and end-state are unchanged; only the recovery hint and help text change.
- Reusing the **main worktree** for a target checked out there mirrors today's checkout-carry semantics: the clean-tree guard checks only the *current* worktree, so a dirty main worktree with non-overlapping files could mix into the cherry-pick. Acknowledge this in the help text (parity with plain cmv), rather than adding a new cross-worktree cleanliness scan.
- Refactoring `wtc` to call the shared function must be behavior-preserving — existing wtc tests are the guard.
