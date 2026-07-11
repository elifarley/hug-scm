# Fix: `hug rb` UX & correctness (issue #205)

> **For Claude:** This is the DESIGN/spec. The implementation plan (task-by-task) is produced
> separately via `superpowers-extended-cc:writing-plans` and saved as the `-impl.md` sibling.

**Goal:** Make `hug rb` (rebase-with-backup) trustworthy and script-safe by fixing the four
sub-bugs reported in [elifarley/hug-scm#205](https://github.com/elifarley/hug-scm/issues/205):
a lying exit code, a backup-branch collision on retry, a non-interactive cancel with no documented
opt-in, and an incoherent `--no-backup` guard.

**Scope:** All four sub-bugs, plus two latent defects found while tracing them (a dead conflict-guidance
branch and a `--quiet`-authorizes-the-rebase conflation). `git-rb` has **no test file today**, so this
adds net-new coverage.

**Architecture:** One unifying refactor — **plan → render → (dry-run stops | confirm → execute)** —
carries all the fixes: a *dynamic confirmation tier* (backup ⇒ warn, `--no-backup` ⇒ danger), backup
creation moved to *after* authorization, collision-proof backup naming reusing the proven `git-bc`
pattern, and a `--dry-run` that faithfully previews the real run with zero side effects.

**Tech stack:** Bash (`git-config/bin`, `git-config/lib`), BATS tests, existing `hug-clock`
(`HUG_FAKE_CLOCK`) and `hug-confirm` tier libraries.

---

## Context — the incident

`hug rb origin/main` was run during post-merge cleanup and exhibited four distinct failures
(verbatim in the issue). Reporter's priority order: **3b > 2 > 1 > 3a**.

| # | Symptom | Impact |
|---|---------|--------|
| 3b | `hug rb <t> -f --no-backup` prints `✅ Success` but **exits 1** | Silent script-breaker (highest) |
| 2  | Retry within the same minute fails: `Failed to create backup branch '…11-1006.main'` | Blocks recovery |
| 1  | `hug rb <t>` in a non-TTY cancels; no documented non-interactive opt-in | Automation friction |
| 3a | `--no-backup requires --force`, an ad-hoc guard outside the tier system | Contract confusion |

## Root causes (traced through the call stack)

- **3b — exit code lies.** `git-rb:180` ends the success branch with
  `[[ -n "$backup_name" ]] && tip …`. Under `--no-backup`, `backup_name` is empty, so the `[[ ]]`
  yields 1 and — as the function's last evaluated command — becomes `hug_rb`'s return value → the
  script exits 1 despite a clean rebase.
- **Bonus (found while tracing 3b) — dead conflict branch.** `git-rb:175` runs a bare
  `git rebase "$target"` under `set -e`. On conflict, `git rebase` returns non-zero and `set -e`
  kills the script *before* the conflict-guidance `else` branch (`:181-187`) can run. That helpful
  guidance is unreachable today.
- **2 — backup collision.** Two compounding faults: (a) the backup is created *before* the
  confirmation gate (`:138` precedes `:152`), so a **cancelled** rebase orphans a backup branch;
  (b) `create_backup_branch` names it with raw `date +'%d-%H%M'` — **minute precision** — so any
  retry in the same minute collides on the leftover branch. Notably `git-bc` already solved this
  exact class with a `hug_clock_now` collision loop; `create_backup_branch` predates it.
- **1 — non-interactive cancel.** `hug rb` calls `prompt_confirm_danger`, which (by the family-wide
  invariant) **rejects `-y`** and, in a non-TTY, prints `Non-interactive environment: cancelled`
  (exit 1). There is no documented flag that clears a danger gate except `-f`, which is heavier than
  needed (it also skips the working-tree-clean check).
- **3a — `--no-backup` guard.** `git-rb:146` hard-errors `--no-backup requires --force` — an
  ad-hoc rule expressed outside the `hug-confirm` tier system, so the help text lists the two flags
  as independent when they are not.
- **Bonus (found while tracing 1/3a) — `--quiet` authorizes.** `git-rb:152` gates the whole
  confirmation on `HUG_QUIET != T`, so `--quiet` silently *authorizes* the rebase. Quiet should
  suppress chatter, never grant authorization.

## Design decisions

### D1 — Dynamic confirmation tier (backup ⇒ warn, `--no-backup` ⇒ danger)

The family invariant (captured, `hug-confirm` header, "design 2026-06-12 §5"): `-y`/`HUG_YES`
auto-confirms **warn** (recoverable) prompts but is **rejected** by **danger**; only `-f`/`HUG_FORCE`
clears danger. A rebase is *recoverable precisely because a backup branch is created* — so the tier
should follow the backup:

- **Default (backup on) ⇒ warn-tier** via `prompt_confirm_warn`. `-y` authorizes without weakening
  the dirty-tree guard (that guard is `-f`'s job, not `-y`'s). Fixes **#1** — `-y` is now the
  documented non-interactive opt-in.
- **`--no-backup` ⇒ danger-tier** via `prompt_confirm_danger "rebase" "no backup will be created…"`.
  Only `-f` clears it; `-y` is refused (exit 3, `HUG_EX_BLOCKED`). This **replaces** the ad-hoc
  `:146` guard with a principled tier routing. Fixes **#3a**: `--no-backup` still needs `-f`
  non-interactively (no safety net + no human ⇒ strongest gate), but interactively it now accepts the
  typed-word confirmation — more flexible than the old hard block, and coherent with every other
  danger-tier command.

Rejected alternatives: *always warn-tier* (would let `--no-backup -y` rewrite history with no
explicit backup on the "safe" flag — contradicts the tier philosophy); *keep danger-tier + document
`-f`* (forces `-f` for every rebase, which also nukes the tree-clean check — the reporter's specific
gripe).

### D2 — Create the backup *after* authorization

Move `create_backup_branch` to run only once the operation is authorized (after the confirm gate).
"Don't create a side effect before the point of no return." A cancelled rebase now creates **no**
backup ⇒ no orphan, nothing to collide with on retry. This is the root-cause half of **#2** and
requires no name-format change.

### D3 — Collision-proof, testable backup naming

Harden `git-config/lib/hug-git-backup`, mirroring the proven `git-bc` pattern:

- Replace raw `date` with **`hug_clock_now`** → UTC and deterministic under `HUG_FAKE_CLOCK`
  (`create_backup_branch` is currently untestable for exactly this reason).
- **Factor `resolve_backup_name <source> <base>`** — pure, read-only (probes `git show-ref`), echoes
  the name it *would* create. `create_backup_branch` becomes `resolve_backup_name` + `git branch`.
  The read-only resolver is what lets `--dry-run` show the concrete name (D4).
- **Collision loop:** the default name stays **minute-precision** (`DD-HHMM.branch`, backward
  compatible). On collision, widen to seconds **inside the time field** (`DD-HHMMSS.branch`) — this
  is the one resolution step the parser accounts for. Encoding the uniquifier in the time field (not
  after the branch name) means only `extract_original_name` needs a one-token regex widen
  (`[0-9]{4}` → `[0-9]{4}([0-9]{2})?`); **`git-bdel-backup`'s date-prefix matching is untouched**
  (`11-1006` still prefix-matches `11-100637`, the correct "delete the 10:06 backups" semantics).
  If even the seconds form is taken (3+ backups of one branch in the same UTC second — only
  reachable via a tight scripted retry loop), the loop is **bounded** and aborts with a clear error
  rather than inventing an unparseable name; the operator retries a second later. This mirrors
  `git-bc`'s bounded-loop philosophy while keeping `extract_original_name`'s contract crisp.

Belt-and-suspenders with D2: D2 removes the incident's cancel→retry collision and orphans; D3 also
covers the residual two-successful-rebases-in-one-minute case and makes the whole thing testable.

### D4 — plan → render → execute; `--dry-run` = render then stop

Eliminate the duplicated preview (the dry-run block `:113-133` and the confirm block `:158-167`
both compute `num_commits`, print the commit list, and run `git diff`). Compute a **plan** once,
**render** it once; dry-run is "render, then `return 0`". Both paths render the same plan, so the
preview is faithful *by construction*.

`--dry-run` shows a faithful, side-effect-free preview:
- **Scope** — "Would rebase N commits onto `<target>`" + diffstat (as today).
- **Backup disposition** *(new)* — "Would create backup at `hug-backups/2026-07/11-1006.main`", or
  "Would **skip** backup (`--no-backup`)".
- **Authorization hint** *(new)* — "warn-tier; a non-interactive run needs `-y`" /
  "danger-tier; needs `-f`" — directly pre-empts #1: preview first, learn the flag, then run.

Guarantees: the early `return 0` precedes both side effects, so dry-run provably creates no branch
and never invokes `git rebase`; it ignores `-y`/`-f` for *authorization* while *reporting* what the
real run requires. Preview chatter stays on stderr (stdout discipline).

### D5 — Honest exit-code contract

- **Status-safe rebase:** `local rebase_status=0; git rebase "$target" || rebase_status=$?` — stops
  `set -e` from short-circuiting, which **resurrects the conflict-guidance branch**.
- **Explicit returns:** success branch ends `return 0` (the `tip` becomes a proper `if`, never a
  bare `&&` tail) → fixes **#3b**; conflict branch prints guidance and `return "$rebase_status"`
  (correctly non-zero, and now reachable).
- Backup-creation failure is handled explicitly (`|| { warn; return 1; }`) instead of the current
  dead `if [[ $? -ne 0 ]]` that `set -e` preempts.

### D6 — `--quiet` never authorizes

Decouple output suppression from authorization. The confirm step runs regardless of `HUG_QUIET`
(and internally honors `-y`/`-f`); `--quiet` only suppresses the rendered preview and success/tip
chatter.

## New `hug_rb` control flow

```
validate            # git repo, target exists, not detached, not already-on-target  (unchanged)
tree_guard          # clean check unless HUG_FORCE (-f warns + skips)                 (unchanged)
plan = build_plan   # pure: current/target, num_commits, diffstat, will_backup→tier,
                    #       resolved backup_name, required non-interactive auth flag
render_plan(plan)   # →stderr: commit list + diffstat + backup disposition  (ONE shared renderer)
if dry_run:
    print_dry_run_preview "…"          # existing helper
    return 0                           # BEFORE any side effect — provably clean
confirm(plan.tier)  # warn ⇒ prompt_confirm_warn ; danger ⇒ prompt_confirm_danger
                    # (-y clears warn only; -f clears both; --quiet does NOT authorize)
if plan.will_backup:
    backup_name = create_backup_branch HEAD "$current_branch"  || { warn; return 1; }
    tip "Backup of '$current_branch' created at: $backup_name"
rebase_status=0; git rebase "$target" || rebase_status=$?
if success: success "…"; [[ -n backup ]] tip via if; return 0
else:       warn guidance (rbc/rba); [[ -n backup ]] tip via if; return "$rebase_status"
```

## Confirmation-tier matrix (the authoritative contract)

Default = **warn** (backup created). `--no-backup` = **danger** (no backup).

| Invocation | Interactive | Non-interactive |
|---|---|---|
| `hug rb <t>`               | y/N prompt (default N)      | **cancel** (exit 1) |
| `hug rb <t> -y`            | proceeds (backup)           | **proceeds** (backup) ← #1 fix |
| `hug rb <t> -f`            | proceeds; skips tree-clean  | proceeds; skips tree-clean |
| `hug rb <t> --no-backup`   | type-"rebase" prompt        | cancel (exit 1) |
| `hug rb <t> --no-backup -y`| **reject** (exit 3)         | **reject** (exit 3) |
| `hug rb <t> --no-backup -f`| proceeds; no backup         | proceeds; no backup ← #3a path |

`--dry-run` on any row: renders the plan + the auth hint for that row, mutates nothing, exits 0.
`--quiet` on any row: suppresses preview/tip chatter only; authorization is unchanged.

## Library changes

- **`hug-git-backup`**: add `resolve_backup_name` (pure); rewrite `create_backup_branch` to
  `resolve` + `git branch` with the `hug_clock_now` collision loop; widen `extract_original_name`
  to accept `DD-HHMM.` and `DD-HHMMSS.`; refresh the header doc-comment (name format, new function).
  Ensure `hug-clock` is in the source chain wherever this runs (`git-bc` already relies on it via
  the kit).
- **`hug-git-rebase`**: house the `build_plan` / `render_plan` helpers so `git-rb` stays a thin
  orchestrator (per `bin/CLAUDE.md`). Reuse existing `print_dry_run_preview` / `print_action_preview`.
- **`git-rb`**: adopt the new flow; swap the confirm call per tier; rewrite `show_help` OPTIONS.

## Testing strategy (net-new)

**`tests/unit/test_rb.bats`:**
- **#3b regression:** `hug rb <t> -f --no-backup` (clean, linear-ahead) → exit 0; conflict → non-zero
  **and** conflict-guidance text present (proves the resurrected branch).
- **Tier (#1/#3a):** `-y` proceeds (warn); bare non-interactive cancels (exit 1);
  `--no-backup -y` → exit 3; `--no-backup -f` → proceeds with no backup; `--quiet` alone does not
  authorize.
- **Backup (#2):** success ⇒ exactly one backup matching the format; cancelled run ⇒ **zero**
  backups; same-minute collision under `HUG_FAKE_CLOCK` ⇒ unique name, no error; dry-run ⇒ HEAD and
  branch list unchanged.
- **Dry-run preview:** asserts backup disposition + tier/auth hint + scope appear (stderr).

**Lib tests** (`tests/lib/`): `resolve_backup_name` read-only + deterministic under `HUG_FAKE_CLOCK`;
collision → seconds → counter; `extract_original_name` returns the original for both `DD-HHMM.branch`
and `DD-HHMMSS.branch`, including branch names containing dots/digits.

## Docs & norms

- Rewrite `git-rb` `show_help` OPTIONS to state the dynamic tier (`-y` authorizes a backed-up rebase;
  `--no-backup` needs `-f`) and the richer `--dry-run`.
- Update the `hug-git-backup` header comment (name format, `resolve_backup_name`).
- Note in the agents cheatsheet that `hug rb` supports `--dry-run`.
- No ADR (bug-fix + local refactor, not architectural).
- **After merge:** capture the rb-tier and backup-naming decisions in omnibrain — the recall flagged
  both as blanks worth capturing.

## Files touched

`git-config/bin/git-rb`, `git-config/lib/hug-git-backup`, `git-config/lib/hug-git-rebase`,
`tests/unit/test_rb.bats` (new), `tests/lib/*` (backup lib), plus help/doc text.

## Edge cases & risks

- Old backups used raw **local**-time labels; new ones use **UTC** — cosmetic only (the label is not
  parsed for correctness; `extract_original_name` handles both formats).
- `resolve_backup_name`→`git branch` TOCTOU is covered by the in-`create` collision loop.
- On the real run, `render_plan` shows the plan's resolved name; if the clock or ref state moves
  between render and creation (rare), the post-creation "Backup created at …" tip is authoritative.
  Dry-run shows the resolved name with no creation to drift from.
- Reordering the backup after confirmation changes the *sequence* of the "Backup created" tip
  (now after the prompt) — intended, and arguably clearer.

## Out of scope

- Broader `prompt_confirm_warn` non-interactive policy (whether warn-tier should ever auto-proceed
  without `-y`) — a family-wide change; this spec keeps the standard warn semantics and uses `-y`.
- Mercurial parity (`hg-config`) — `hug rb` is git-only today; no `hg` rebase-with-backup exists.
