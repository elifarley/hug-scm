# Design v2: State-determined confirmation tiers + recovery hints for the HEAD-mover family

- **Issue:** [elifarley/hug-scm#222](https://github.com/elifarley/hug-scm/issues/222) (concerns #1, #2, #5, and the #6 guard-completeness prerequisite)
- **Supersedes:** `docs/superpowers/specs/2026-07-27-head-movers-confirmation-tier-unification-design.md` (v1) — see §11 for what changed and why.
- **Partially reverts:** the unconditional-danger `h-rewind` from [elifarley/hug-scm#225](https://github.com/elifarley/hug-scm/pull/225) (its *dirty-tree* danger stays; its *clean-tree* path lowers to warn). See §9 for the sign-off flag.
- **Date:** 2026-07-28
- **Status:** Design draft v2, under user review
- **Branch/worktree:** `head-movers-tier-unify` (`~/src/hug-scm.WT.head-movers-tier-unify`), off `origin/main`

> Anchors (`file:line`) are against `origin/main` at design time. Re-resolve at implementation time — #225 already moved some `h-rewind` lines.

---

## 1. Problem

Six commands move HEAD via the shared `handle_upstream_operation` / `handle_standard_operation` helpers (`git-config/lib/hug-git-upstream`). Each has two paths — **non-upstream** (explicit target) and **upstream** (`-u`) — to the same git op. Today the tier is *implicit and inconsistent*: the helper hardcodes **warn** (`hug-git-upstream:71`) while each command's non-upstream block hardcodes **danger**. So for every command, the upstream path is gated *weaker* than the non-upstream path for the *identical* operation — the inverted confirmation gradient ([elifarley/hug-scm#218](https://github.com/elifarley/hug-scm/issues/218) found it for `h-rewind`; it is the shape of all six).

v1 fixed the *consistency* (both paths same tier) using an **op-determined** model (tier ⟺ operation category). **v2 replaces the model itself**, because op-determination produces false alarms (clean-tree `h-rewind` demands `-f` for no protective purpose) and gives the user no way back when something does go wrong.

## 2. The standard — tier ⟺ completeness of the recovery command

> **A command's tier is `warn` iff a complete recovery command can be emitted for everything the operation changes. It is `danger` iff the operation changes something no command can recover.** The recovery command, run immediately after, must (a) restore exactly what changed, and (b) not disturb the working-tree/index state the operation left intact.

This subsumes three properties the user established during design:

1. **State-determined.** "What changed" depends on tree state. A clean-tree `h-rewind` changes only HEAD position (commits become reflog-only) → a complete recovery exists → **warn**. A dirty-tree `h-rewind` also destroys uncommitted working-tree edits, which have no git object → no recovery → **danger**. The tier falls out of state, not from a fixed per-op label.
2. **Recovery-hinted.** Every warn-tier op prints the *exact* recovery command (a literal hug invocation) to stderr on success. "Reflog-recoverable" is only a useful tier because hug hands the user the command to do the recovering.
3. **Safe-to-run-immediately.** The hint must not itself be a footgun: executing it right after the op restores the prior state and endangers nothing the user wanted to keep. This rules out the naive "always recover with `h-rewind <SHA>`" (§4).

**Why this standard is stronger than v1's "reflog-recoverable":** v1's phrasing buried the load-bearing conditions (structural guards, reflog horizon). "Complete recovery command exists" is mechanically checkable: hug either can write the command or it can't. Incomplete enumeration (the [elifarley/hug-scm#220](https://github.com/elifarley/hug-scm/issues/220)/[#227](https://github.com/elifarley/hug-scm/pull/227) "guard misses part of the affected set" class) becomes *self-detecting* — if hug can't write a complete recovery command, it can't honestly print warn.

## 3. Assumptions (what makes state-determination safe enough here)

These are project conventions; the model relies on them. Documented, not enforced by this spec:

- **At most one writer per worktree.** Branch-worthy work happens in dedicated worktrees (`hug help :worktree`), so the cross-agent/cross-process filesystem race between a gate-time clean-check and the later git op is not a realistic threat. Residual TOCTOU is narrowed to (a) background tooling that writes inside the worktree (watchers, LSPs, build daemons) and (b) the agent's own intervening writes within one turn. Both are low-severity edge cases; documented, not blocking.
- **The main worktree stays on `main`.** So a misfired destructive op in a feature worktree has bounded blast radius (the feature's reflog), never corrupting the integration branch. This lowers the cost of a wrong tier decision and justifies accepting the residual TOCTOU above.
- **Recovery targets committed work, not working-tree edits.** Unstaged edits have no git object; nothing recovers them. So the recovery-hint requirement covers HEAD-position and commit loss; its *absence* (no possible hint) is itself the signal for danger.

## 4. Recovery command — mode-matched, not universal

**The recovery command is the inverse of the op: same family command, pre-op HEAD as target, mode preserved.** It is NOT "always `h-rewind <SHA>`." `h-rewind` is `reset --hard`; using it to recover a `reset --soft` (`h-back`) would discard the staged work `h-back` deliberately preserved — a recovery worse than the original op. Each command recovers with *itself*, because each command's reset mode is exactly what preserves that command's post-op working state:

| Command | Reset mode | Post-op state to preserve | Recovery (run immediately after) | Why it's safe |
|---|---|---|---|---|
| `h-back` | `--soft` | changes **staged** | `hug h back <pre-op-HEAD> -y` | `--soft` moves HEAD only; staged changes stay staged |
| `h-undo` | `--mixed` | changes **unstaged** | `hug h undo <pre-op-HEAD> -y` | `--mixed` resets index, leaves working tree untouched |
| `h-rollback` | `--keep` | uncommitted work preserved | `hug h rollback <pre-op-HEAD> -y` ⚠️ | see §5 — `--keep` may **abort** going forward |
| `h-rewind` (clean) | `--hard` | nothing (clean) | `hug h rewind <pre-op-HEAD> -y` | `--hard` to prior commit; nothing was uncommitted; recovery re-enters the clean-tree warn branch so `-y` works |
| `h-squash` | `--soft`+recommit | (history rewrite) | `hug h back <pre-op-HEAD> -y` | squash is `h-back`+recommit; `--soft` forward restores original commits |
| `cmv` | `--hard` (clean-gated) | (branch move) | `hug h back <pre-op-HEAD> -y` | original commits reflog-recoverable via soft reset |

**Verified:** all five commands accept an arbitrary target via `target_arg="$1"` → `resolve_target_with_temporal` → `git rev-parse --verify` (passes a full SHA through unchanged). So `hug h <cmd> <full-SHA>` is valid for every command. The hint uses the **full** pre-op SHA (never a short hash or `HEAD~N`, which could resolve differently after the op moves HEAD).

**Flag on the recovery command:** warn-tier ops recover with `-y` (warn auto-confirms); `h-rewind` (the only danger-tier recovery) recovers with `-f`. This matches each command's own tier post-v2, so recovery is frictionless *and* the flag is the one the command actually accepts.

## 5. `--keep` recovery is unconditional — the "abort hole" does not exist

An earlier draft of this spec worried that recovering `h-rollback` with `hug h rollback <pre-op-HEAD>` (`reset --keep` *forward*) could trip `--keep`'s "Entry not uptodate" abort — because `--keep` aborts when a working-tree file with uncommitted changes differs from the target. **Empirical probing disproved this: the hole cannot arise.** The reason is a clean invariant of how `--keep` works:

- `--keep` aborts when a file is **both** dirty **and** would be overwritten by the reset.
- If such a file exists, `--keep` refuses the **original** rollback (`git reset --keep HEAD~N` aborts before HEAD moves — verified). The op never runs, so there is nothing to recover.
- If the original rollback **does** run, it means every dirty file is *outside* the reset range (its content is identical at both ends). Going forward, those same dirty files are still outside the range → no conflict → forward `--keep` **succeeds cleanly**.

Verified across three scenarios (probe scripts in the design session): (a) dirty file unrelated to the range — original OK, recovery OK; (b) dirty file *in* the range — **original aborts** (no recovery needed); (c) multi-commit range with a file changed mid-range but clean at both ends — original OK, recovery OK. In every case where the original op runs, `hug h rollback <pre-op-HEAD> -y` recovers exactly, preserves the uncommitted edits, and endangers nothing. **No caveat, no fallback, no conditional hint.**

**The §2 bar (option 1) is met unconditionally for `h-rollback`:** recovery is a single command. This is stronger than the fail-loud-with-fallback the earlier draft settled for — `h-rollback`'s recovery is as clean as `h-back`'s and `h-undo`'s, justifying warn tier on the same footing.

## 6. Per-command tier (both paths), post-v2

Tier is a property of the command's op+state, **identical on both paths** (the bug was that it wasn't). One declaration per command, consumed by both the upstream helper and the non-upstream gate.

| Command | Tier (both paths) | Why (recovery-completeness) |
|---|---|---|
| `h-back` | **warn** + hint | `--soft` preserves all work; HEAD restore is complete |
| `h-undo` | **warn** + hint | `--mixed` preserves working tree; HEAD restore is complete |
| `h-rollback` (normal) | **warn** + hint | `--keep` preserves uncommitted work and refuses to run if a dirty file is in the reset range; forward recovery always succeeds (§5) |
| `h-rollback` (root path) | **danger** ⚠️ (unchanged) | runs `xargs rm -f` on tracked files, no clean gate — out of scope here; see §10 |
| `h-squash` | **warn** + hint | history rewrite; original commits reflog-recoverable via `--soft` forward |
| `cmv` | **warn** + hint | clean-gated before any `--hard`; old commits reflog-recoverable |
| `h-rewind` (clean tree) | **warn** + hint | **CHANGED from #225's danger** — only HEAD moves; full recovery exists |
| `h-rewind` (dirty tree) | **danger** + partial hint | uncommitted edits destroyed (unrecoverable); commit part recoverable via `hug h back <pre-op-HEAD> -y` (the destroyed working-tree edits cannot be recovered — the hint is explicit about this; `h-back`/`--soft` is used because the post-op tree is clean, so soft-resetting forward is safe and minimal) |

**Headline behavior changes vs. today:**
1. `h-rewind` becomes **state-dependent**: clean ⇒ warn+hint (was unconditional danger from #225); dirty ⇒ danger (unchanged). This is the partial revert of #225 — see §9.
2. The four commands currently danger on non-upstream (`h-back`/`h-undo`/`h-rollback`/`h-squash`) lower to **warn + hint** on both paths.
3. **Every** warn-tier success prints a recovery hint; `h-rewind`-dirty prints the commit-recovery part but stays danger.

## 7. Mechanism

### Step 1 — `handle_upstream_operation` gains a required `tier` parameter

```bash
# Usage: target=$(handle_upstream_operation "rewinding" warn "rewind" "git reset --hard is irreversible")
#   $1 - action verb              (e.g. "rewinding")
#   $2 - tier ∈ {safe,warn,danger}  REQUIRED (${2:?} — no default; a future dangerous
#                                     caller cannot silently inherit warn)
#   $3 - action WORD for danger typed-confirm (e.g. "rewind"); passed always, used only when tier=danger
#   $4 - danger reason (used only when tier=danger)
handle_upstream_operation() {
  local action_name="$1" tier="${2:?handle_upstream_operation requires a confirmation tier}"
  local action_word="$3" danger_reason="${4:-}"
  ... # validation + preview (current lines 33–68) unchanged
  case "$tier" in
    danger) prompt_confirm_danger "$action_word" "$danger_reason" ;;
    warn)   prompt_confirm_warn   "Proceed with $action_name to upstream? [y/N]: " ;;
    safe)   prompt_confirm_safe   "Proceed with $action_name to upstream?" ;;
    *)      error "Unknown confirmation tier '$tier' for upstream operation '$action_name'." ;;
  esac
  echo "$target"
}
```

The `case` replaces the hardcoded `prompt_confirm_warn` at `hug-git-upstream:71`, **staying inside the existing `if [[ HUG_QUIET != T ]]` block** so `HUG_QUIET=T` still skips preview+confirmation together (behavior preserved). This **retires the `HUG_FORCE=true handle_upstream_operation` wrapper hack** that #225 used for `h-rewind` — passing `tier=danger` directly gives preview + a single danger gate, no env trick, no double-prompt.

### Step 2 — each command owns one tier; both paths consume it

Each command sets `tier` (+ `action_word` + `danger_reason` where danger) near the top. Both the upstream call (`handle_upstream_operation "$verb" "$tier" …`) and the non-upstream gate (`prompt_confirm_${tier} …`) read it. One declaration, two consumers — they match **by construction**. A consistency-guard test (§8) asserts the two never diverge.

### Step 3 — `h-rewind` becomes state-dependent

`h-rewind` is the only command whose tier depends on tree state (per §6). Before its gate:

```bash
local tier
if has_uncommitted_tracked_changes; then   # staged OR unstaged TRACKED changes
  tier=danger                              # these would be destroyed by --hard → unrecoverable
else
  tier=warn                                # only HEAD moves → fully recoverable
fi
```

**Predicate scope — tracked only:** `reset --hard` overwrites *tracked* working-tree files; it does **not** touch untracked files. So the danger classification keys on staged + unstaged **tracked** changes (`has_uncommitted_tracked_changes`), not untracked files. Untracked files are neither destroyed nor recoverable-via-reflog, so they are irrelevant to the tier. (A future op that *can* delete untracked files — e.g. `w-wipe`-class — would need a different predicate; out of scope here.)

Both paths then consume `$tier`. The dirty branch keeps #225's danger semantics (refuses `-y`, exit 3); the clean branch lowers to warn and prints the recovery hint. **`has_uncommitted_tracked_changes` must be the same predicate used by the guard-completeness audit (§10) — a shared library function, not an ad-hoc `git diff --quiet`, so the tier decision and the guard agree by construction.**

### Step 4 — recovery hints via one helper

```bash
# Usage: emit_head_recovery_hint <pre-op-HEAD> <recovery-cmd>
# Prints to stderr. Called AFTER the op succeeds, so the SHA is final.
# recovery-cmd is the full literal invocation, e.g. "hug h back <pre-op-HEAD> -y".
emit_head_recovery_hint() {
  local pre_op_head="$1" recover_cmd="$2"
  printf '\nℹ️  HEAD moved. Recover with:\n    %s\n' "$recover_cmd" >&2
}
```

Each mutating command captures `pre_op_head=$(git rev-parse HEAD)` **before** the git op, runs the op, and on success calls `emit_head_recovery_hint "$pre_op_head" "hug h back $pre_op_head -y"` (or the mode-matched equivalent per §4). The hint is suppressed under `HUG_QUIET=T` (it is human-facing chatter → stderr, same discipline as the preview).

**Placement invariant:** the hint prints only on the **success** path of the actual git op, never before it. A failed/aborted op prints no hint (nothing to recover).

## 8. Testing

**Consistency guard (locks the invariant):** for each command, assert upstream and non-upstream resolve to the **same tier** — e.g. `h-undo -u` and `h-undo HEAD~1` both proceed under `-y` (warn); `h-rewind -u` (dirty) and `h-rewind HEAD~1` (dirty) both refuse under `-y` (danger, exit 3). If anyone re-hardcodes a tier, this fails.

**Recovery-hint correctness (the §2 bar — new, the core of v2):** for each warn-tier command, after a successful op, assert:
1. The printed recovery command, **executed immediately**, restores HEAD to the pre-op commit (`$(git rev-parse HEAD)` equals the captured pre-op SHA).
2. The recovery command does **not** alter the working-tree/index state the op left (e.g. after `h-back`, recovery leaves changes staged; after `h-undo`, unstaged). Assert via `hug ss`/`hug su` before and after recovery being byte-identical.
3. For `h-rollback`, assert the §5 invariant empirically: when the original rollback *runs* (dirty file outside the range), `hug h rollback <pre-op-HEAD> -y` recovers exactly and preserves the uncommitted edits; and when a dirty file is *in* the range, the original op aborts (exit non-zero, HEAD unchanged) so no recovery is needed.

**State-dependent `h-rewind`:**
- Clean tree + no flag → proceeds at warn, prints `hug h rewind <pre-op-HEAD> -f` hint; `-y` proceeds (was: refused).
- Dirty tree + `-y` → refused, exit 3 (danger); `-f` proceeds, hint prints the commit-recovery command.
- Clean vs dirty tier selected by the **shared** `has_uncommitted_tracked_changes` predicate (§7 Step 3).

**Conditional-skip preservation (do not flatten):** several commands skip the gate when the tree is clean (`h-back` prompts only `if has_staged_changes`; `h-undo`/`h-squash` use a `should_prompt` flag false when clean). The tier change replaces the **prompt call inside the confirmed branch**, leaving the surrounding `if dirty … else skip` byte-for-byte intact. Include a clean-tree case: `hug h undo` / `hug h squash -u` with no `-y` and a clean tree → exit 0, no prompt. (Failure mode if ignored: clean-tree CI automation breaks.)

**Exit-code contract (unchanged family rules):** danger + `-y` → exit 3 (`HUG_EX_BLOCKED`); danger + `-f` → proceed; warn + `-y`/`-f` → proceed (exit 0); warn + decline → exit 1.

**Test migration:** v1's §6 inventory (the gum-mock vs real-gum mechanics, the `HUG_TEST_GUM_CONFIRM=no` / `HUG_DISABLE_GUM=true` + piped-`read` recipes) carries over **as-is** for the four commands lowering danger→warn — re-resolve line anchors at impl time. The `h-rewind` clean/dirty split adds new cases on top.

**Help text (concern #5):** update each command's `show_help` OPTIONS: warn-tier commands document `-y` auto-confirms + that a recovery hint is printed; `h-rewind` documents the clean/dirty split (clean ⇒ `-y` works; dirty ⇒ `-f` required).

## 9. Sign-off flag — partial revert of #225

#225 made `h-rewind` **unconditionally danger** on both paths (the right call under v1's op-determined model). v2 lowers the **clean-tree** path to warn+hint. This is a deliberate behavior change requiring explicit owner sign-off:

- **Dirty-tree `h-rewind` stays danger** — unchanged from #225. No regression to the data-loss guard #225 added.
- **Clean-tree `h-rewind` becomes warn + recovery hint** — `-y` now proceeds; the hint `hug h rewind <pre-op-HEAD> -f` is printed. Justified by §2: a clean tree yields a complete recovery command, so warn is honest.
- **Risk accepted:** the clean/dirty split hinges on `has_uncommitted_tracked_changes` being complete (§7 Step 3, §10). If that predicate ever under-counts (the #220/#227 class), a dirty tree could be mis-classified clean and `h-rewind -y` would destroy edits. **This is why §10 (guard-completeness audit) is a prerequisite, not a follow-up.**

## 10. Prerequisite — concern #6 guard-completeness audit (no longer deferred)

Under v1, concern #6 ("silent no-op masks dirty state" / guard-scope-miss) was deferred cleanup. Under v2 it is a **prerequisite**, because hint-completeness is what licenses the warn tier: if `has_uncommitted_tracked_changes` (or `cmv`'s clean-gate, or any hug-coded guard) misses part of the at-risk set, the printed recovery command is incomplete *and* the tier is wrong — silently lowering a danger op to warn.

**Scope of the audit (must land before or with v2):**
- Define **one** shared `has_uncommitted_tracked_changes` predicate (staged + unstaged **tracked** changes — see §7 Step 3 for why untracked is excluded) and use it in both `h-rewind`'s tier decision and any clean-gate. No ad-hoc `git diff --quiet` per command.
- `cmv`: verify its clean-gate (the thing that makes `--hard` safe ⇒ warn) is complete — same scrutiny #220/#227 applied to `w get`. Incomplete ⇒ `cmv` must stay danger until fixed.
- `h-rollback` root path: confirmed danger (§6) and out of scope for lowering, but its `xargs rm -f` no-clean-gate is logged for a future root-path spec.
- `handle_standard_operation` "already at target" short-circuit (`hug-git-upstream:98-108`): audit for the "silent no-op masks a dirty tree" class (#220 was this class for `w get`).

If the audit finds a guard incomplete for a given command, **that command stays danger** (no hint, or partial hint) until the guard is fixed — the standard (§2) is not relaxed to hit a tier.

## 11. What changed from v1, and why

| Aspect | v1 (2026-07-27) | v2 (2026-07-28) | Why |
|---|---|---|---|
| Tier model | op-determined (by category) | **state-determined** (recovery-completeness) | op-model false-alarms (clean `h-rewind` needs `-f` for nothing); state-model matches agent risk reasoning and unifies with #218's `w get` decision |
| §2 rationale | "warn ⟺ reflog-recoverable" | "warn ⟺ complete recovery command exists" | "reflog-recoverable" buried the load-bearing structural-guard conditions; recovery-completeness is mechanically checkable and self-detecting for guard misses |
| Recovery hints | absent | **first-class** — `emit_head_recovery_hint`, mode-matched per §4 | user requirement: reflog-recovery is only useful if hug hands the user the command |
| Recovery primitive | (n/a) | **mode-matched** (each command recovers with itself), NOT universal `h-rewind` | universal `--hard` recovery would destroy the staged/unstaged work `--soft`/`--mixed` preserved — a recovery worse than the op |
| `h-rewind` tier | unconditional danger (both paths) | **state-dependent**: clean ⇒ warn+hint, dirty ⇒ danger | under recovery-completeness, a clean tree has a full recovery ⇒ warn is honest; dirty stays danger (unrecoverable edits) |
| #225 relationship | extended #225's danger to a tier param | **partially reverts** #225's clean-path danger (§9) | the model change propagates to `h-rewind`'s clean path |
| Concern #6 | deferred cleanup | **prerequisite** (§10) | hint-completeness now licenses the warn tier; an incomplete guard silently lies |

The v1 spec's *mechanism* (the `tier` param on `handle_upstream_operation`, one-tier-per-command consumed by both paths, the consistency guard, the test-migration inventory) is **retained** — v2 changes the *model that feeds the tier* and adds recovery hints, not the plumbing.

## 12. Scope

**In scope:** the `tier` param on `handle_upstream_operation`; per-command tier declarations (state-determined for `h-rewind`, warn for the rest) consumed by both paths; the `emit_head_recovery_hint` helper + mode-matched hints; `h-rewind` clean/dirty split (partial #225 revert, §9); the §10 guard-completeness audit as prerequisite; help-text `-y`/`-f`/recovery docs; the consistency guard + recovery-correctness + migration tests (§8).

**Out of scope → separate specs under #222:** `--dry-run` coverage (concern #3); family-wide exit-code reconciliation / `check_*_clean` exit 1 vs documented exit 3 (concern #4); the `h-rollback` root-path `xargs rm -f` danger-tier fix (§10 note); the `handle_upstream_operation` `HUG_QUIET=T` confirmation-skip path (unchanged here — documented as the `--quiet` escape hatch).
