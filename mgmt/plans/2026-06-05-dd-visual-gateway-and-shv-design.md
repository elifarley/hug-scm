# Design: `dd` visual-diff gateway + `shv` (introduced-diff semantics for committishes)

**Date:** 2026-06-05
**Status:** Approved (user-directed, brainstorming session).
**Relationship to prior art:** Refines `mgmt/plans/2026-06-04-visual-diff-flag-design.md`. The
`s`/`u`/`w` working-tree family and *all* guards from that doc (TTY, difftool preflight,
strict-mode wrap, no-changes, one-window batching, pathspec normalization) are **unchanged**.
This doc revises only the **committish/range row** of that design (which treated a positional
ref as `git difftool <ref>` = worktree-vs-ref) and adds the `shv` command.

## Context

The 2026-06-04 design productized `dd` with `s`/`u`/`w` subcommands (mirroring `ss`/`su`/`sw`)
and accepted `dd <committish>|<range>` as `git difftool <ref>` — i.e. **worktree-vs-ref**.

Field observation that triggered this redesign:

- `hug shp HEAD` shows the patch **the HEAD commit introduced** (`git show HEAD` → HEAD vs its
  parent).
- `hug dd HEAD` shows **worktree-vs-HEAD** (`git difftool HEAD`) — i.e. all uncommitted changes,
  ≈ `hug sw`. So `dd HEAD` ≡ bare `dd`; the explicit `HEAD` argument has no visible effect.
- **Root cause:** `dd <committish>` inherited git's `diff <ref>` semantics (worktree-vs-ref),
  while `shp` uses `show <ref>` semantics (commit-vs-parent). The *same* `HEAD` token means two
  different things across the two commands — confusing, and the more common intent ("what did
  this commit change?") is unserved by `dd`.

Two facts shape the fix:

1. **Worktree-vs-*arbitrary*-ref is rarely useful.** The one common case (worktree-vs-HEAD) is
   already `dd` / `dd w`. "Compare against a branch" is better expressed as a **range**
   (`dd main..HEAD`), which sidesteps the merge-base subtlety of `git diff main`. So the
   positional-committish slot is low-value as worktree-vs-ref.
2. **No users yet** → no backward-compatibility constraint (explicit).

## Decision (user-directed)

1. **`dd` becomes the visual-diff gateway.** Users reach for `dd` when they want to *see any diff
   visually*. The argument selects *which* diff:
   - `s` / `u` / `w` (and bare = `w`) → working-tree diffs (unchanged).
   - a **committish / range / N / -N** → a commit-history diff.
2. **A single committish ⇒ its *introduced* diff** (commit vs its first parent), matching
   `shp` / `git show`. This **reconciles the reported inconsistency**: `dd HEAD` ≡ `shp HEAD`.
   The low-value worktree-vs-arbitrary-ref behavior is dropped.
3. **Add `shv`** — the show-family-named, thin alias for the commit/range/N subset, built over the
   **same engine** as `dd`'s ref path. Rationale: mnemonic transfer (`shp` → `shv`, "patch →
   visual") and `sh*`-family discoverability — a user who knows `shp` and guesses `shv` is right,
   with no help-text detour. ("The command you'd guess just works.")
4. **Adopt the `N`/`-N` convention** (identical to `sh`/`shp`, via the existing `resolve_commit_ref`):
   `N` (0–999) → single commit `HEAD~N` (0 → HEAD); `-N` (1–999) → range `HEAD~N..HEAD`;
   numbers ≥ 1000 pass through as refs.
5. **Drop worktree-vs-arbitrary-ref for v1.** Reserve `dd w [ref]` as a future, non-breaking
   addition. For now, "diff against a ref" is a range. (See *Rejected / reserved*.)

## Command surface (new + changed only)

| Command | Semantics | git invocation (conceptual) | Status |
|---|---|---|---|
| `hug dd` / `hug dd w` | worktree vs HEAD (net, all uncommitted) | `git difftool … HEAD` | unchanged |
| `hug dd s` | index vs HEAD (staged) | `git difftool … --cached` | unchanged |
| `hug dd u` | worktree vs index (unstaged) | `git difftool …` | unchanged |
| `hug dd <committish>` / `hug dd N` | **diff that commit introduced** (commit vs first parent; root commit vs empty tree) | `git difftool … <C>^ <C>` | **changed** (was worktree-vs-ref) |
| `hug dd <range>` / `hug dd -N` | cumulative diff across the range (endpoints) | `git difftool … <A>..<B>` | semantics unchanged; now also via `-N` |
| `hug shv [N\|-N\|<committish>\|<range>] [-- <path>…]` | same as `dd` for the commit/range/N subset; **default HEAD** | delegates to the shared engine | **new** |

### Equivalences that MUST hold (test these directly)

- `dd HEAD` ≡ `shv HEAD` ≡ bare `shv` ≡ (content of) `shp HEAD`.
- `dd N` ≡ `shv N`; `dd -N` ≡ `shv -N`; `dd A..B` ≡ `shv A..B` (identical difftool argv).
- bare `dd` ≡ `dd w` (working, all uncommitted) — **distinct from** bare `shv` (HEAD's own patch).
  This mirrors the existing split: bare `sw` (working) vs bare `shp` (HEAD's patch).

## Semantic honesty (document these, don't hide them)

- **Single committish = commit vs *first parent*.** Merges diff against the first parent (`<C>^1`);
  `git show` may instead render a combined diff for merges, so `shv <merge>` and `shp <merge>` can
  differ for merges — documented. A **root commit** (no parent) diffs against the empty tree
  (`4b825dc642cb6eb9a060e54bf8d69288fbee4904`), showing every file as added.
- **Range / `-N` = cumulative endpoint diff** (like `shcp`), **not** per-commit patches. A single
  `--dir-diff` window shows two snapshots; per-commit visual review would require N blocking tool
  launches — rejected, consistent with the one-window `--dir-diff` contract from the 2026-06-04 design.
- **bare `dd` ≠ `dd HEAD`** now: bare `dd` = uncommitted (working-vs-HEAD); `dd HEAD` = HEAD's own
  patch. Both are intuitive once framed as "current changes" vs "that commit's changes," and it is
  exactly the `sw` vs `shp` distinction.

## Must-carry requirements

- **No-changes guard now covers the committish/range path** — this fixes a latent bug: the current
  `dd_ref` (`hug-git-difftool:252`) is the *only* dispatcher lacking the guard that `dd_staged`,
  `dd_unstaged`, and `dd_working` all have, so today `dd HEAD` launches an **empty difftool** on a
  clean tree while bare `dd` prints `No changes.` — despite emitting the identical git command.
  The new engine guards with `git diff --quiet <endpoints> [-- <path>…]` before launching
  (empty commit, `A..A`, etc. → friendly message, exit 0, no launch).
- **TTY guard, difftool preflight, strict-mode wrap, pathspec normalization, one-window batching**
  — unchanged; apply equally to `shv`.
- **`shv` rejects `s`/`u`/`w` tokens** with a friendly redirect ("`shv` shows a commit's diff; for
  staged/unstaged/working use `hug dd s|u|w` or `hug ss|su|sw`"), since "show a commit" has no
  staged/unstaged notion.

## Implementation outline

Scripts stay thin; logic lives in `git-config/lib/` (per `bin/CLAUDE.md`). DRY: one engine, two
entry points.

- **T1 — Shared engine** in `git-config/lib/hug-git-difftool` (e.g. `dd_commit_diff <token> [-- paths]`):
  resolve `token` via `resolve_commit_ref`; classify single-commit vs range (presence of `..`/`...`);
  compute endpoints (single → `<C>^ <C>`, with root-commit → empty-tree fallback; range → pass
  through); run the **no-changes guard**; call `run_visual_diff`. **Replaces** the current `dd_ref`.
  - *Reuse decision (finalize in plan):* `resolve_commit_ref` currently lives in `hug-git-show`.
    Prefer the minimal move — `source` it from `hug-git-difftool` — unless that pulls in heavy
    deps, in which case hoist the resolver to a lower shared lib. Do **not** duplicate it.
- **T2 — `git-config/bin/git-dd`:** route the positional ref/range to the new engine (introduced
  diff) instead of old `dd_ref`; keep `s`/`u`/`w`, bare-default-`w`, and the interactive picker.
  Update `show_help`: the `<ref>` line, the `N`/`-N` convention, the introduced-diff semantics,
  the "bare `dd` vs `dd HEAD`" note, and `SEE ALSO` → `shv` / `shp`.
- **T3 — `git-config/bin/git-shv` (new, thin):** default arg `HEAD`; arg grammar mirrors `shp`
  (`[N|-N|<committish>|<range>] [-- <path>…]`); reject `s`/`u`/`w`; `show_help`;
  `_hug_category='["show"]'`, `_hug_keywords` (e.g. `visual`, `difftool`, `shp`, `patch`,
  `side-by-side`); `SEE ALSO` → `shp` / `dd`. Add shell completion.
- **T4 — Docs & cross-refs:** `README.md` (add `shv` to the `sh*` family; update the `dd` row);
  `docs/command-map.md`; `docs/commands/status-staging.md` (the `dd` "Visual diff" section — update
  the ref behavior) and the show-family doc for `shv`; `docs/DOCS_ORGANIZATION.md` if needed;
  completions. Cross-reference both directions (`shp` ↔ `shv` ↔ `dd`). Record the reserved
  `dd w [ref]` as a backlog note.
- **T5 — Tests (BATS):** assert every equivalence above + guards + root/merge/empty/range/`N`/`-N`
  cases; **update** the existing `test_dd.bats` case that asserts `dd HEAD~1` forwards `HEAD~1`
  verbatim (it now forwards computed endpoints `HEAD~1^ HEAD~1`); new `test_shv.bats`; assert
  `dd <token>` and `shv <token>` produce identical difftool argv; add the missing
  no-changes-guard-on-ref test (the bug above).
- **T6 — OpenWolf bookkeeping:** update `.wolf/anatomy.md` (new `git-shv`, changed `git-dd` /
  `hug-git-difftool`), append `.wolf/memory.md`, and log the `dd_ref` no-changes-guard bug to
  `.wolf/buglog.json` when fixed.

## Verification (manual smoke, after BATS passes)

1. `hug dd HEAD` opens **HEAD's own patch** (== `hug shp HEAD` content), *not* all-uncommitted.
2. bare `hug dd` still shows all uncommitted (working-vs-HEAD).
3. `hug shv` ≡ `hug dd HEAD`.
4. `hug dd 3` / `hug shv 3` → HEAD~3's introduced patch.
5. `hug dd -3` / `hug shv -3` → cumulative diff of the last 3 commits.
6. `hug dd HEAD~1..HEAD` → range diff (endpoints).
7. root-commit `hug dd <root-sha>` → every file shown as added.
8. empty commit / `A..A` → `No changes.`, no tool launch (guard).
9. `hug shv s` → friendly error pointing to `dd s` / `ss`.
10. TTY refusal, unconfigured-difftool error, mid-review cancel → all behave as in the 2026-06-04 design.
11. `hug help dd` + `hug help shv` render; `SEE ALSO` cross-refs resolve both ways.

## Rejected / reserved

- **Worktree-vs-arbitrary-ref via a `--base`/`--against` flag** → rejected: non-idiomatic for a
  *humane* CLI, lowest value-per-concept, and it reintroduces "two meanings of `dd` + a ref" behind
  a flag. If the capability is ever wanted, **`dd w [ref]`** (an optional ref on the existing `w`
  subcommand; `dd w` defaults to HEAD) is the preferred vehicle — natural language, no new flag
  vocabulary, no positional ambiguity. **Reserved, not built in v1.**
- **`shv` as a `--visual` flag on `shp`** → rejected: it would make `shp` conditionally TTY-only and
  break its stdout/pipe discipline. A separate command isolates the blocking-GUI concern — the same
  rationale that made `dd` a separate command from `sw` (`hug-git-difftool:9-13`).
- **Keep `dd <committish>` = worktree-vs-ref** → rejected: low value, and the source of the
  reported inconsistency.
- **Per-commit visual diff for ranges** → rejected: N blocking windows; violates the one-window
  `--dir-diff` contract.
