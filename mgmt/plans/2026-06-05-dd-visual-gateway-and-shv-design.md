# Design: `dd` visual-diff gateway + `shv` (introduced-diff semantics for committishes)

**Date:** 2026-06-05
**Status:** Approved (user-directed). Path A (gateway) **re-confirmed 2026-06-05** at the `/autoplan`
CEO premise gate, after a 6/6 dual-voice (Codex + independent Claude) challenge toward an orthogonal
split. User rebuttals on record: (a) docs follow design, not vice-versa; (b) `shv` reframed as the
visual counterpart to `shp` *and* `shcp`; (c) numeric filenames are safe behind `--`; (d)
worktree-vs-*arbitrary*-ref is genuinely low-value. Surviving edge accepted with mitigation —
bare `dd` ≠ `dd HEAD` (see *Semantic honesty*). Refinements folded in below.
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

1. **Worktree-vs-*arbitrary*-ref is rarely useful.** The one *high-value* case (worktree-vs-HEAD)
   is already `dd` / `dd w` and stays there. The case people reach for next — `dd main` ("how do
   I compare to main?") — is itself muddy: `git diff main` diffs against main's *tip* and renders
   main's exclusive commits as reverse-diffs, so what users actually want is the merge-base
   (`main...HEAD`), not worktree-vs-tip. (Precise: `dd main..HEAD` is **not** equivalent to
   `git diff main` — it ignores uncommitted work. We drop a muddy, rare operation, not a clean,
   common one.) So the positional-committish slot is low-value as worktree-vs-ref.
2. **No users yet** → no backward-compatibility constraint (explicit).

## Decision (user-directed)

1. **`dd` becomes the visual-diff gateway.** Users reach for `dd` when they want to *see any diff
   visually*. The argument selects *which* diff:
   - `s` / `u` / `w` (and bare = `w`) → working-tree diffs (unchanged).
   - a **committish / range / N / -N** → a commit-history diff.
2. **A single committish ⇒ its *introduced* diff** (commit vs its first parent), matching
   `shp` / `git show`. This **reconciles the reported inconsistency**: `dd HEAD` ≡ `shp HEAD`.
   The low-value worktree-vs-arbitrary-ref behavior is dropped.
3. **Add `shv`** — the **visual counterpart to `shp` AND `shcp`**, built over the **same engine** as
   `dd`'s ref path. A single commit behaves like `shp` (its own patch); a range / `-N` behaves like
   `shcp` (cumulative endpoint diff) — exactly what a single `--dir-diff` window can render. Naming
   it after both is honest about the range case: a `--dir-diff` window cannot iterate commits the
   way text `shp -3` does, so `shv -3` is a cumulative (`shcp`-style) view, not a per-commit one.
   Rationale: mnemonic transfer (`shp`/`shcp` → `shv`, "patch → visual") and `sh*`-family
   discoverability — a user who knows `shp` and guesses `shv` is right, with no help-text detour.
   ("The command you'd guess just works.")
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

- `dd HEAD` ≡ `shv HEAD` ≡ bare `shv` ≡ (content of) `shp HEAD` — **for non-merge commits only**.
  Merges differ (`dd`/`shv` use first-parent `^1`; `shp` uses `git show`'s combined diff), so
  equivalence tests MUST use non-merge commits, with a *separate* merge test asserting `<m>^1 <m>`.
- `dd N` ≡ `shv N`; `dd -N` ≡ `shv -N`; `dd A..B` ≡ `shv A..B` (identical difftool argv).
- bare `dd` ≡ `dd w` (working, all uncommitted) — **distinct from** bare `shv` (HEAD's own patch).
  This mirrors the existing split: bare `sw` (working) vs bare `shp` (HEAD's patch).

## Semantic honesty (document these, don't hide them)

- **Single committish = commit vs *first parent*.** Merges diff against the first parent (`<C>^1`);
  `git show` may instead render a combined diff for merges, so `shv <merge>` and `shp <merge>` can
  differ for merges — documented. Use the explicit `^1` form (identical to `^`, but self-documents
  first-parent intent). A **root commit** (no parent) diffs against the empty tree
  (`4b825dc642cb6eb9a060e54bf8d69288fbee4904` — the SHA-1 of the empty tree, a git-stable constant;
  comment it inline so it doesn't read as magic), showing every file as added.
- **Range / `-N` = cumulative endpoint diff** (like `shcp`), **not** per-commit patches. A single
  `--dir-diff` window shows two snapshots; per-commit visual review would require N blocking tool
  launches — rejected, consistent with the one-window `--dir-diff` contract from the 2026-06-04 design.
  **Classification caveat:** `is_range` keys on the literal `..` substring, so a branch/tag named
  `feat..fix` is treated as a range (inherited from `shp`/`shcp`); such names need an explicit
  `refs/heads/feat..fix`.
- **bare `dd` ≠ `dd HEAD`** now: bare `dd` = uncommitted (working-vs-HEAD); `dd HEAD` = HEAD's own
  patch. Framed as "current changes" vs "that commit's changes" it mirrors `sw` vs `shp` — but this
  is the **sharpest residual edge**: a user who learned "bare `dd` = my changes" can misread
  `dd HEAD` as "my changes vs HEAD" and silently get the wrong view. Note this is an
  *internal-coherence* risk, **not** git-transfer — `dd` is a hug-native verb (git has no `dd`), so
  there is no `git diff` command to carry the expectation over from. **Mitigation (required):**
  lead `hug help dd`'s `DESCRIPTION` with this distinction, and differentiate the empty-case
  message — `No changes introduced by <ref>.` for the commit path vs bare `dd`'s `No changes.`

## Must-carry requirements

- **No-changes guard now covers the committish/range path** — this fixes a latent bug: the current
  `dd_ref` (`hug-git-difftool:252`) is the *only* dispatcher lacking the guard that `dd_staged`,
  `dd_unstaged`, and `dd_working` all have, so today `dd HEAD` launches an **empty difftool** on a
  clean tree while bare `dd` prints `No changes.` — despite emitting the identical git command.
  The new engine guards with `git diff --quiet <endpoints> -- <path>…` before launching.
  **Exit-code discipline (do NOT copy `diff_has_working_changes` at `hug-git-diff:102`, which
  collapses every non-`1` exit into "no changes"):** `0` = no diff → friendly message, exit 0;
  `1` = diff → launch; **anything else → surface the git/ref error and exit non-zero** (else an
  invalid ref or bad range silently reads as "No changes introduced…"). **Pathspecs MUST be
  forwarded** to the guard (else `dd <c> -- unmatched-path` false-positives while the commit has
  other changes). Three endpoint forms: range → `--quiet <range>`; single non-root →
  `--quiet "<C>^1" "<C>"`; root → `--quiet <empty-tree> "<C>"`.
- **Guard *ordering* on the ref/range path:** parse → `reject_flag_ref` → resolve → endpoint
  compute → **no-changes guard FIRST**, then `dd_check_tty` / `dd_preflight` **only if a launch will
  actually happen**. (Today `dd_dispatch` runs TTY+preflight before parsing — so `dd badref` would
  wrongly report "no difftool configured / requires TTY" instead of "invalid ref", and an empty
  diff would still demand difftool config.) Strict-mode wrap, pathspec normalization, one-window
  batching otherwise unchanged — and **`shv` must run the guard chain too** (see T3).
- **`shv` rejects `s`/`u`/`w` tokens** with a friendly redirect ("`shv` shows a commit's diff; for
  staged/unstaged/working use `hug dd s|u|w` or `hug ss|su|sw`"), since "show a commit" has no
  staged/unstaged notion.

## Implementation outline

Scripts stay thin; logic lives in `git-config/lib/` (per `bin/CLAUDE.md`). DRY: one engine, two
entry points.

- **T1 — Shared engine** in `git-config/lib/hug-git-difftool` (e.g. `dd_commit_diff <token> [-- paths]`):
  `reject_flag_ref` (so `--stat` etc. never reach git as a pseudo-ref) → `resolve_commit_ref` →
  classify single-commit vs range (`is_range`: contains `..`/`...`) → compute endpoints **as two
  explicit args** (single non-root → `"<C>^1" "<C>"`; **root → `<empty-tree-SHA> "<C>"`**; range →
  pass the range token through) → exit-code-safe **no-changes guard** → `run_visual_diff`.
  **Use the explicit two-arg form, NOT `<C>^!`** (`^!` is rev-list syntax, not a reliable
  `git diff` range). **Replaces** the current `dd_ref`.
  - *Hoist (DECIDED):* move **`resolve_commit_ref` AND `reject_flag_ref`** from `hug-git-show` to
    **`hug-git-repo`** — it already sits in both libs' load chain (via `hug-git-kit`) and already
    owns ref utilities (`validate_commitish`, `is_at_root_commit`, …). Not `hug-common` (no git
    knowledge — category error), not a new module (proliferation). Cross-sourcing `hug-git-show`
    from `hug-git-difftool` is the wrong dependency direction; duplicating violates DRY.
  - *Root detection (DECIDED):* existing `is_at_root_commit` checks **HEAD~1 only** — wrong for an
    arbitrary resolved ref (`dd <root-sha>` while *not* at root would wrongly compute `<C>^1`). Add
    a companion **`is_root_commit <committish>`** using `git rev-parse --verify --quiet "<C>^"`
    inside an `if` (so `set -e` survives the expected non-zero on a root). Keep `is_at_root_commit`
    for HEAD-meaning callers.
- **T2 — `git-config/bin/git-dd`:** route the positional ref/range to the new engine (introduced
  diff) instead of old `dd_ref`; keep `s`/`u`/`w`, bare-default-`w`, and the interactive picker.
  Update `show_help`: **lead `DESCRIPTION` with the bare-`dd`-vs-`dd HEAD` distinction** (the
  residual edge above), put the `N`/`-N` convention *before* the subcommand list with a worked
  contrast (`dd 3` = one commit, `dd -3` = last 3), then the `<ref>` introduced-diff semantics and
  `SEE ALSO` → `shv` / `shp`.
- **T3 — `git-config/bin/git-shv` (new, thin):** default arg `HEAD`; arg grammar
  `[N|-N|<committish>|<range>] [-- <path>…]`. **Pathspec handling mirrors `shcp` (multiple paths via
  `parse_pathspecs`), NOT `shp`** (which warns on >1 path) — consistent with "`shv` = visual `shp`
  *and* `shcp`". **Before calling the engine, run `dd_check_tty` → `dd_preflight` → `check_git_repo`
  in that order** (identical to `dd_dispatch`'s pre-dispatch block): `git-shv` bypasses
  `dd_dispatch`, so it has *no* guards unless it calls them explicitly. Reject `s`/`u`/`w` (friendly
  redirect); `show_help`; `_hug_category='["show"]'`, `_hug_keywords` (`visual`, `difftool`, `shp`,
  `shcp`, `patch`, `side-by-side`); `SEE ALSO` → `shp` / `shcp` / `dd`. Add shell completion.
- **T4 — Docs & cross-refs (docs follow the design):** `README.md` (add `shv` to the `sh*` family;
  update the `dd` row); `docs/command-map.md` (the `dd` semantics change; revisit its `s*`-vs-`show`
  categorization now that `dd <ref>` is commit-history); `docs/git-to-hug.md` (`git diff HEAD`→`sw`
  is unaffected; add `git show <c>` → `dd <c>` / `shv <c>`); `docs/commands/status-staging.md` (the
  `dd` "Visual diff" section — update the ref behavior) and the show-family doc for `shv`;
  `docs/DOCS_ORGANIZATION.md` if needed; completions. Cross-reference both directions
  (`shp` ↔ `shv` ↔ `dd`). Record the reserved `dd w [ref]` as a backlog note.
- **T5 — Tests (BATS):** the harness needs upgrades, not just new cases:
  - **Exact-argv helper** — `assert_shim_logged` uses substring `grep -qF`, so it CANNOT distinguish
    old single-arg `HEAD~1` from new `HEAD~1^` + `HEAD~1` (one is a substring of the other) — the
    regression test would be *write-only*. Add `assert_shim_logged_exact` (`grep -cxF`, exact line)
    and use it for every endpoint case to catch **reversed endpoints**, misplaced `--`, duplicates.
  - **Endpoint cases (exact argv):** single non-root (`… "<C>^1" "<C>"`), **merge** (`… "<m>^1" "<m>"`,
    asserted separately — NOT `shp`-equivalent), **root** (`… <empty-tree> "<C>"`, from a repo where
    the root is NOT HEAD), range `A..B` and **symmetric `A...B`**, `N` / `-N` / `0`.
  - **Equivalence:** `dd <token>` argv == `shv <token>` argv — **non-merge commits only**.
  - **Pathspec × endpoint matrix:** match → one launch with exact `-- <paths>`; non-match → exit 0,
    no launch (guard forwards pathspecs); multiple paths preserve order; `--help` after `--` = path.
  - **No-changes guard:** empty commit (`git commit --allow-empty`; add a
    `create_test_repo_with_empty_commit` fixture), `A..A`, `dd <c> -- unmatched` → friendly "No
    changes introduced…", no launch; **invalid ref / bad range → non-zero error, NOT "no changes"**.
  - **`shv` guards:** `shv` without a TTY refuses; `shv` with no difftool configured errors —
    mirroring `test_dd.bats` Category 3/4 (proves `shv` runs the guard chain).
  - **Detached HEAD:** `dd HEAD` / `dd 0` / `dd -1` / `shv` after `git checkout --detach` → exact
    endpoints, no branch/upstream dependence.
  - **Post-hoist:** existing `resolve_commit_ref` / `reject_flag_ref` tests stay green at the new
    `hug-git-repo` home; `dd --stat` / `shv --stat` rejected (not passed as a ref).
  - **Update** the `dd HEAD~1` case → `HEAD~1^ HEAD~1` (exact-argv); add new `test_shv.bats`.
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

## /autoplan review trail (2026-06-05)

Adapted run (git-blocked env, gstack bins absent): **CEO + Eng** phases, dual voices each
(Codex 0.125.0 + independent Claude subagent). Design phase skipped (no UI scope); DX skipped by
user ("Eng only, then stop").

**CEO premise gate — Path A re-confirmed (user-directed).** Both voices challenged the gateway
reframe 6/6 toward an orthogonal split; user rebutted (docs follow design; `shv` = visual
`shp`+`shcp`; numeric filenames safe behind `--`; worktree-vs-arbitrary-ref low-value). Surviving
edge accepted with mitigation: bare `dd` ≠ `dd HEAD`. User Challenge (drop `shv`) → **REJECTED**.

**Eng findings — all accepted (Mechanical; Eng tiebreakers P5/P3/P1). Architecture CONFIRMED sound.**

| # | Finding | Sev | Voices | Disposition |
|---|---------|-----|--------|-------------|
| E1 | No-changes guard must not copy `diff_has_working_changes` (swallows non-`1` exits → invalid ref reads as "no changes") | crit | Codex | exit-code-safe guard (0/1/else) → Must-carry |
| E2 | Guard ordering: validate + no-changes BEFORE TTY/preflight | high | Codex | ref path reordered → Must-carry |
| E3 | `assert_shim_logged` substring match → endpoint regression test write-only | high | both | `assert_shim_logged_exact` → T5 |
| E4 | Equivalence breaks on merges | high | Codex | tests non-merge only + merge `^1` test → Equivalences/T5 |
| E5 | Pathspec × endpoint test matrix unspecified | high | both | added → T5 |
| E6 | `resolve_commit_ref` + `reject_flag_ref` home | high | both | hoist to `hug-git-repo` → T1 |
| E7 | `shv` guard chain unspecified (bypasses `dd_dispatch`) | high | both | explicit `dd_check_tty`→`dd_preflight`→`check_git_repo` → T3 |
| E8 | `is_at_root_commit` HEAD-only → wrong for `dd <root-sha>` | med | Claude | add `is_root_commit <committish>` → T1 |
| E9 | `shv` pathspecs should mirror `shcp` (multi), not `shp` (single+warn) | med | Codex | → T3 |
| E10 | `<C>^!` unreliable for `git diff` | med | Claude | explicit two-arg `"<C>^1" "<C>"` → T1 |
| E11 | detached HEAD, `A...B`, `..`-in-name, empty-tree-SHA comment | low | both | tests + Semantic honesty |

No taste decisions; no unresolved user challenges. Ready for implementation (writing-plans → worktree).
