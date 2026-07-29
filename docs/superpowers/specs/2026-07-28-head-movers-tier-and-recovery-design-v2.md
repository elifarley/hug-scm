# Design v2: State-determined confirmation tiers + recovery hints for the HEAD-mover family

- **Issue:** [elifarley/hug-scm#222](https://github.com/elifarley/hug-scm/issues/222) (concerns #1, #2, #5, and the #6 guard-completeness prerequisite)
- **Supersedes:** `docs/superpowers/specs/2026-07-27-head-movers-confirmation-tier-unification-design.md` (v1) — see §11 for what changed and why.
- **Partially reverts:** the unconditional-danger `h-rewind` from [elifarley/hug-scm#225](https://github.com/elifarley/hug-scm/pull/225) (its *dirty-tree* danger stays; its *clean-tree* path lowers to warn). See §9 for the sign-off flag.
- **Date:** 2026-07-28 (consolidated 2026-07-29)
- **Status:** Design v2 — **approved** (owner sign-off 2026-07-29; refined through five review rounds, §13). Next: implement #222 (self-contained); #229 follows as the systemic companion.
- **Branch/worktree:** `head-movers-tier-unify` (`~/src/hug-scm.WT.head-movers-tier-unify`), **rebased onto `origin/main` @ `1296dbf`** (post-#225)

> Anchors (`file:line`) are against `origin/main` @ `1296dbf` (post-#225); the branch is rebased onto exactly this commit, so anchors and working tree agree. Re-resolve at implementation time if `origin/main` moves.

> Every behavioral claim below was replayed against `origin/main` @ `1296dbf` in scratch repos (transcripts in Appendix A). §1–§12 are the forward-looking contract; §13 summarizes the review history (lift-able into the PR description); Appendix A is the empirical evidence.

---

## 1. Problem

Six commands move HEAD via the shared `handle_upstream_operation` / `handle_standard_operation` helpers (`git-config/lib/hug-git-upstream`). Each has two paths — **non-upstream** (explicit target) and **upstream** (`-u`) — to the same git op. Today the tier is *implicit and inconsistent*: the helper hardcodes **warn** (`hug-git-upstream:71`) while each command's non-upstream block hardcodes **danger** (`git-h-back:109`, `git-h-undo:135`, `git-h-rewind:103`). So for every command, the upstream path is gated *weaker* than the non-upstream path for the *identical* operation — the inverted confirmation gradient ([elifarley/hug-scm#218](https://github.com/elifarley/hug-scm/issues/218) found it for `h-rewind`; it is the shape of all six).

v1 fixed the *consistency* (both paths same tier) using an **op-determined** model (tier ⟺ operation category). **v2 replaces the model itself**, because op-determination produces false alarms (clean-tree `h-rewind` demands `-f` for no protective purpose) and gives the user no way back when something does go wrong.

## 2. The standard — tier ⟺ completeness of the recovery command

> **A command's tier is `warn` iff a complete recovery command can be emitted for everything the operation changes. It is `danger` iff the operation changes something no command can recover.** The recovery command, run immediately after, must (a) restore exactly what changed, and (b) not disturb the working-tree/index state the operation left intact.

This subsumes three properties:

1. **State-determined.** "What changed" depends on tree state. A clean-tree `h-rewind` changes only HEAD position (commits become reflog-only) → a complete recovery exists → **warn**. A dirty-tree `h-rewind` also destroys uncommitted working-tree edits, which have no git object → no recovery → **danger**. The tier falls out of state, not from a fixed per-op label.
2. **Recovery-hinted.** Every warn-tier op prints the *exact* recovery command (a literal hug invocation) to stderr on success. "Reflog-recoverable" is only a useful tier because hug hands the user the command to do the recovering.
3. **Safe-to-run-immediately.** The hint must not itself be a footgun: executing it right after the op restores the prior state and endangers nothing the user wanted to keep. This rules out the naive "always recover with `h-rewind <SHA>`" — and also rules out "recover by re-invoking the same mover" (§4).

**Why this standard is stronger than v1's "reflog-recoverable":** v1's phrasing buried the load-bearing conditions (structural guards, reflog horizon). "Complete recovery command exists" is mechanically checkable: hug either can write the command or it can't. Incomplete enumeration (the [elifarley/hug-scm#220](https://github.com/elifarley/hug-scm/issues/220)/[#227](https://github.com/elifarley/hug-scm/pull/227) "guard misses part of the affected set" class) becomes *self-detecting* — if hug can't write a complete recovery command, it can't honestly print warn.

**The standard is also a probe, not just a label.** Applied mechanically to the six commands, it falsifies a naive tier table: five of six re-invocation "recovery" commands do not recover (Appendix A). A tier whose recovery command no-ops is not warn-tier, by definition. The rest of this spec is the table rebuilt to satisfy the probe.

## 3. Assumptions (what makes state-determination safe enough here)

These are project conventions; the model relies on them. Documented, not enforced by this spec:

- **At most one writer per worktree.** Branch-worthy work happens in dedicated worktrees (`hug help :worktree`), so the cross-agent/cross-process filesystem race between a gate-time clean-check and the later git op is not a realistic threat. Residual TOCTOU is narrowed to (a) background tooling that writes inside the worktree (watchers, LSPs, build daemons) and (b) the agent's own intervening writes within one turn. Both are low-severity edge cases; documented, not blocking.
- **The main worktree stays on `main`.** So a misfired destructive op in a feature worktree has bounded blast radius (the feature's reflog), never corrupting the integration branch. This lowers the cost of a wrong tier decision and justifies accepting the residual TOCTOU above.
- **Recovery targets committed work, not working-tree edits.** Unstaged edits have no git object; nothing recovers them. So the recovery-hint requirement covers HEAD-position and commit loss; its *absence* (no possible hint) is itself the signal for danger.

## 4. Recovery command — one purpose-built primitive, named for the op it inverts

### 4.1 Why recovery cannot re-invoke the mover

Recovering by re-invoking the same mover with the pre-op SHA (`hug h back <pre-SHA> -y`, etc.) is a **silent exit-0 no-op for every forward (descendant) target** — which is exactly what a pre-op HEAD is after a rewind-family op. The shared helper short-circuits:

```bash
# git-config/lib/hug-git-upstream:90-101 (handle_standard_operation)
commits_to_affected=$(count_commits_in_range "$target" HEAD)   # = rev-list --count "$target..HEAD"
if [ "$commits_to_affected" -eq 0 ]; then
    if [[ "$skip_when_aligned" == true ]] || ! has_pending_changes; then
        info "Already at target $(git rev-parse --short "$target"). No action taken."
        exit 0      # <-- reset line never reached
```

After a rewind-family op the current HEAD is an *ancestor* of the pre-op HEAD, so `rev-list --count pre..HEAD` = **0** → "Already at target" → `exit 0`, HEAD unrestored. (Precisely: for `h-back`/`h-undo`/`h-rollback` the default `skip_when_aligned=true` fires the exit unconditionally, so re-invocation **always** no-ops on a forward target. `h-rewind` passes `false` (`git-h-rewind:100`), so its exit depends on `! has_pending_changes` — and that predicate (`has_pending_changes`, renamed `has_untracked_or_pending_changes` in §10) counts **untracked** files too (`hug-git-state:29`), which `reset --hard` leaves behind; with any untracked file present the re-invocation falls through to the danger gate and, with `-f`, actually restores HEAD — recovery succeeds *by accident*. A fully clean tree hits the exit. The behavior is state-accidental, not a contract — which is exactly why `restore` exists: recovery must never depend on whether an untracked file happens to lie around.) The short-circuit is **correct** for mover idempotency (re-running `h-back` when already there should do nothing); it is **lethal** for recovery, which must move *forward* to a descendant. Note the subtlety: target *parsing* succeeds for all five commands (`rev-parse --verify` passes a full SHA through unchanged) — the failure is end-to-end; the parsed target never reaches a reset (Appendix A.1). `h-squash`'s re-invocation happens to work, but by topological luck (the squash commit is a *sibling* of the pre-op tip, so `pre..HEAD ≠ 0`), not by any uniform property.

**Conclusion:** recovery must not round-trip through `handle_standard_operation`'s aligned-target short-circuit. It gets its own primitive — named so the natural instinct ("recover with the family you trust") survives: the flag is the *op being inverted*, not a raw git mode.

### 4.2 The primitive: `hug h restore <target> --<op>`

`hug h restore` is a purpose-built HEAD-mover whose *only* job is to reset HEAD to an arbitrary commit as the inverse of a prior op. Its contract:

- **Never short-circuits on a forward target.** It tests `target == HEAD` (exact SHA equality) for a true no-op; any other target — ancestor *or* descendant — is a real reset. It does not call `count_commits_in_range`-gated `handle_standard_operation`. This is the whole reason it exists (Appendix A.1).
- **The flag is the op being inverted — the reset mode is implicit.** `--back | --undo | --rollback | --rewind`, **required** (`${op:?}`). Each names a mover and therefore a reset mode, via **one literal table** (single source of truth — the `get_dirty_files` discipline of §10):

  | `restore` flag | op inverted | reset mode underneath | preserves |
  |---|---|---|---|
  | `--back` | `h-back` (and `h-squash`) | `reset --soft` | changes **staged** |
  | `--undo` | `h-undo` | `reset --mixed` | changes **unstaged** |
  | `--rollback` | `h-rollback` | `reset --keep` | **uncommitted** work; aborts if a dirty file is in range |
  | `--rewind` | `h-rewind` | `reset --hard` | **nothing** |

  Two consequences worth stating. **(a) The mode-match is enforced by construction with zero git vocabulary at the call site** — "recover an `h-back` with `--back`" is trivially correct and one typo away from nothing catastrophic, whereas a raw `--soft`/`--hard` choice is one typo from disaster. **(b) The name honestly carries the safety semantics** — `--rewind` *means* "hard reset, with rewind's state-determination," so the danger-on-dirty escalation below reads as expected, not surprising. The git modes remain visible as the table's "underneath" column (surfaced in `restore --help`, §7 Step 5) for power users reasoning about index state, but they are **not** accepted flags — the accepted vocabulary is the op names only.
- **State-determined like the rest of the family:** `--back`/`--undo`/`--rollback` preserve work ⇒ **warn** (auto-confirms with `-y`). `--rewind` on a tree with uncommitted *tracked* changes ⇒ **danger** (refuses `-y`, exit 3) — discarding those edits is unrecoverable, the same reasoning as dirty-tree `h-rewind`. `--rewind` on a clean tree ⇒ warn.
- **Same-branch by precondition.** It resets HEAD on the *current* branch. That is exactly right for the five ops that leave you on the same branch; it is exactly *wrong* for `cmv`, which is why `cmv` never emits it (§6).
- **`h-squash` recovers with `--back`** (squash is `h-back`+recommit, so its inverse is a soft reset; §4.3). There is deliberately no `--squash` flag — the modes are a lower concept than the commands (four modes, five movers), and squash shares back's.

> **Naming caveat — the op names are reset-mode selectors, NOT directions.** The mover family already moves HEAD in *either* direction: `hug h back -u` moves **forward** when the branch has **diverged** with upstream ahead (local commits exist *and* upstream has advanced; a strictly-behind, fast-forwardable branch performs no HEAD move — a clean exit 0 once the §7 Step 2 guard lands, though the unguarded movers crash exit 128 there today), and `h-back`'s help frames the op as "Moves HEAD to target." The name `back` has a documented history of misleading agents into assuming backward-only. `restore`'s flags reuse these names **strictly as mode selectors** — `--back` means "the soft-reset mode `h-back` uses" — and the *direction* of a restore is determined entirely by where `<target>` sits relative to HEAD, never by the flag. The `RESTORE` help sections and the `restore --help` table (§7 Step 5) state the mode equivalence explicitly so the name cannot mislead a second time. (If the deceiving names ever outweigh the "recover the op you ran" locality, the fallback is preservation-semantic flags — `--keep-staged`/`--keep-unstaged`/`--keep`/`--discard` — which name what happens to your work and need no direction disclaimer.)

> **Relationship to [elifarley/hug-scm#229](https://github.com/elifarley/hug-scm/issues/229) (the systemic fix).** `restore`'s exact-SHA-equality no-op test above is the *local* instance of the `is_same_commit` primitive that [elifarley/hug-scm#229](https://github.com/elifarley/hug-scm/issues/229) generalizes for the whole family. That issue refines the shared distance helper into a `commit_offset` with an *enforced* contract — `0` ⟺ identity (short-circuited on SHA equality), `±N` ⟺ clean directional distance, **empty** ⟺ diverged/incomparable — so `offset == 0` becomes a *sound* alignment test rather than the lossy `count == 0` that caused Appendix A.1. Once those primitives land, `restore` can re-share the hardened `handle_standard_operation` (its "already at target" branch keyed off `is_same_commit`) instead of bypassing it; until then, bypassing is correct.

### 4.3 Mode-matched recovery table

The recovery command is uniformly `hug h restore <pre-op-HEAD> --<op> -y`. Each row only names the op being inverted; everything else (mode, preservation, tier) falls out of the §4.2 table:

| Command | Recovery (run immediately after) | Why it's safe |
|---|---|---|
| `h-back` | `hug h restore <pre-op-HEAD> --back -y` | soft reset moves HEAD only; staged changes stay staged |
| `h-undo` | `hug h restore <pre-op-HEAD> --undo -y` | mixed reset resets index, leaves working tree untouched |
| `h-rollback` | `hug h restore <pre-op-HEAD> --rollback -y` | forward `reset --keep` always succeeds when the original ran (§5) |
| `h-rewind` (clean) | `hug h restore <pre-op-HEAD> --rewind -y` | hard reset to prior commit; tree was clean, nothing to lose; warn on a clean tree |
| `h-squash` | `hug h restore <pre-op-HEAD> --back -y` | squash inverts as a soft reset; `--back` forward restores original commits, index keeps the byte-identical squashed tree |
| `cmv` | **— none; danger tier** | switches branch AND rewrites SHAs; no single same-branch reset recovers "exactly what changed" (§6) |

**The hint's target is the full pre-op SHA** (never a short hash or `HEAD~N` — those resolve differently after the op moves HEAD). The command itself parses targets through the family's `resolve_target_with_temporal` → `git rev-parse --verify` path, which accepts a full SHA, a short SHA, an explicit `HEAD~N`, or a branch/tag name. **The one input `restore` refuses is a bare 1–3-digit numeric** (e.g. `42`): `resolve_head_target`'s regex `^[1-9][0-9]{0,2}$` (`hug-git-repo:327`) silently reinterprets it as `HEAD~42`, and a human typing a short SHA-prefix from memory could mean the commit instead. The regex is bounded to 1–3 digits, so any 4+-char input — a short SHA like `a1b2`, or even `1234` — passes through and resolves normally (verified). This narrow guard, not a blanket full-SHA requirement, is what protects a recovery from a silent wrong-commit reset (§7 Step 4a).

**Flag on the recovery command:** uniformly **`-y`** — `restore` never re-invokes a danger-tier mover, so it is warn-tier in the recovery context (the `--rewind`+dirty escalation excepted; the per-mode rationale is in §7 Step 4b).

## 5. `--keep` (rollback) recovery — two layers

Forward `reset --keep` recovery is safe; the argument has two layers.

**Layer 1 — the raw-git `--keep` invariant (verified, Appendix A.3).** `--keep` aborts when a file is **both** dirty **and** would be overwritten by the reset. Hence:

- If such a file exists, `--keep` refuses the **original** rollback (`git reset --keep HEAD~N` aborts before HEAD moves). The op never runs; there is nothing to recover.
- If the original rollback **does** run, every dirty file is *outside* the reset range (identical content at both ends). Going forward, those same dirty files are still outside the range → no conflict → forward `--keep` **succeeds cleanly**.

Probed across three scenarios: (a) dirty file unrelated to the range — original OK, forward `--keep` OK; (b) dirty file *in* the range — **original aborts** (`Entry 'f.txt' not uptodate`, HEAD unchanged; no recovery needed); (c) multi-commit range with a file changed mid-range but clean at both ends — original OK, recovery OK.

**Layer 2 — the hug-level precondition (why the primitive is required).** Layer 1 governs `git reset --keep`. For the *hug* recovery to inherit it, the recovery invocation must actually **reach** a `reset --keep`. Re-invoking `hug h rollback <pre-SHA>` does not — it exits at `handle_standard_operation`'s aligned-target short-circuit (Appendix A.1) before any reset. `hug h restore <pre-SHA> --rollback` (a `reset --keep` underneath, §4.2) **does** reach the reset, because it never short-circuits forward targets. **Therefore the §2 bar is met for `h-rollback` *conditional on the restore primitive*:** recovery is a single command, and Layer 1 guarantees it preserves the uncommitted edits and endangers nothing.

## 6. Per-command tier (both paths)

Tier is a property of the command's op+state, **identical on both paths** (the bug was that it wasn't). One declaration per command, consumed by both the upstream helper and the non-upstream gate.

| Command | Tier (both paths) | Why (recovery-completeness) |
|---|---|---|
| `h-back` | **warn** + hint | `--soft` preserves all work; `restore --back` restores HEAD completely |
| `h-undo` | **warn** + hint | `--mixed` preserves working tree; `restore --undo` restores HEAD completely |
| `h-rollback` (normal) | **warn** + hint | `--keep` preserves uncommitted work and refuses to run if a dirty file is in range; forward `restore --rollback` always succeeds (§5) |
| `h-rollback` (root path) | **danger** ⚠️ | runs `xargs rm -f` on tracked files, no clean gate — out of scope here; see §10 |
| `h-back` (root path) | **danger** ⚠️ | `git-h-back:87-103`: undoes the root commit (`reset_root_commit "soft"`); recovery at root is a guaranteed no-op (unborn HEAD ⇒ `rev-list` fails ⇒ count 0), so it must **not** be swept to warn |
| `h-undo` (root path) | **danger** ⚠️ | `git-h-undo:96-121`: same root-commit reasoning as `h-back` |
| `h-squash` | **warn** + hint | history rewrite; original commits reflog-recoverable via `restore --back` (soft) forward |
| `cmv` | **danger** (clean-gated) ⚠️ | clean-gate (`git-cmv:130`) keeps the `--hard` from destroying uncommitted work, but the op **switches the current branch** (`git-cmv:242-243`) and **rewrites SHAs** (cherry-pick). No single same-branch `hug h restore` recovers "exactly what changed" → not honestly warn (§2). Danger, no recovery hint. |
| `h-rewind` (clean tree) | **warn** + hint | only HEAD moves; `restore --rewind` on the (clean) tree is a complete recovery — a partial revert of #225's unconditional danger (§9) |
| `h-rewind` (dirty tree) | **danger** + partial hint | uncommitted edits destroyed (unrecoverable) — stated on the **op's own success output**, where the loss happens. The commit part is recoverable via `hug h restore <pre-op-HEAD> --rewind -y` (`-y` because the tree is tracked-clean after `reset --hard`; the destroyed working-tree edits cannot be recovered) |

**Headline behavior changes vs. today:**
1. `h-rewind` becomes **state-dependent**: clean ⇒ warn+hint (today: unconditional danger from #225); dirty ⇒ danger (unchanged). This is the partial revert of #225 — see §9.
2. `h-back`/`h-undo`/`h-rollback`/`h-squash` lower to **warn + hint** on both paths (their normal, non-root paths).
3. `cmv` is **danger** — the honest reading of §2.
4. **Every** warn-tier success prints a `hug h restore … --<op>` recovery hint; `h-rewind`-dirty prints the commit-recovery part but stays danger.

## 7. Mechanism

### Step 1 — `handle_upstream_operation` gains a required `tier` parameter

```bash
# Usage: target=$(handle_upstream_operation "rewinding" warn "rewind" "git reset --hard is irreversible")
#   $1 - action verb              (e.g. "rewinding")
#   $2 - tier ∈ {warn,danger}      REQUIRED (${2:?} — no default; a future dangerous
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
    *)      error "Unknown confirmation tier '$tier' for upstream operation '$action_name'." ;;
  esac
  echo "$target"
}
```

The `case` replaces the hardcoded `prompt_confirm_warn` at `hug-git-upstream:71`, **staying inside the existing `if [[ HUG_QUIET != T ]]` block** so `HUG_QUIET=T` still skips preview+confirmation together (behavior preserved). This **retires the `HUG_FORCE=true handle_upstream_operation` wrapper hack** that #225 used for `h-rewind` — passing `tier=danger` directly gives preview + a single danger gate, no env trick, no double-prompt. (The tier enum is `{warn,danger}` only: no HEAD-mover is safe-tier, so there is no `safe)` arm — YAGNI. If a safe-tier op ever appears, add the arm then.)

### Step 2 — each command owns one tier; both paths consume it

Each command sets `tier` (+ `action_word` + `danger_reason` where danger) near the top. Both the upstream call (`handle_upstream_operation "$verb" "$tier" …`) and the non-upstream gate (`prompt_confirm_${tier} …`) read it. One declaration, two consumers — they match **by construction**. A consistency-guard test (§8) asserts the two never diverge. **Root-commit paths keep their own `danger` gate** (`git-h-back:87-103`, `git-h-undo:96-121`): the one-tier-per-command sweep applies to the *normal* path only and must not lower the root path (§6).

**Empty-target guard (load-bearing; a pre-existing bug now inside this edit region).** `handle_upstream_operation`'s "Already synced" `exit 0` (`hug-git-upstream:44-47`) fires *inside the caller's `$(...)` command-substitution subshell* — the parent receives **empty stdout and keeps running**, then crashes on `git reset --soft|--mixed|--keep ""` (exit 128; `git-h-back:115`, `git-h-undo:139`, `git-h-rollback:122`) against a synced or strictly-behind upstream. Today only `git-h-rewind:90-93` and `git-cmv:141-144` guard this (`[[ -z "${target:-}" ]] && exit 0`); `git-h-back:81`, `git-h-undo` (three sites: `:85/:87/:90`), `git-h-rollback:85`, and `git-h-squash` (three sites: `:154/:156/:159`) do **not**. For `h-back`/`h-undo`/`h-rollback` the result is a loud exit-128 crash; **`h-squash` is worse — it fails silently**: its empty `$target` word-splits away in `back_cmd="hug h back $target --quiet --force"` (`git-h-squash:252-253`), so `hug h back` falls back to its `HEAD~1` default, soft-resets the HEAD commit, and re-commits it under a fabricated `[squash] 0 commits…` message — **exit 0, the user's commit orphaned** — and because that fabricated commit diverges the branch from upstream, the commit step even fires the "Local and remote histories differ … rebase or force-push" tip (`hug-git-commit:437`), nudging the user to push the corruption (`git-h-squash` itself prints no push suggestion). The squash guard is therefore the *highest*-priority of the four. **Every rewritten upstream call site must preserve or add the guard.** The recommended systemic fix is to move the synced-detection *out of the subshell* — the helper returns a distinguished non-zero status and the caller exits — so six call sites cannot each forget it (track under [elifarley/hug-scm#229](https://github.com/elifarley/hug-scm/issues/229)'s caller audit). Note also that "one declaration, two consumers" understates the real surface: `h-undo` and `h-squash` each have **three** upstream call sites.

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

**Predicate scope — tracked only:** `reset --hard` overwrites *tracked* working-tree files; it does **not** touch untracked files. So the danger classification keys on staged + unstaged **tracked** changes (`has_uncommitted_tracked_changes`), not untracked files. Untracked files are neither destroyed nor recoverable-via-reflog, so they are irrelevant to the tier. (A future op that *can* delete untracked files — e.g. `w-wipe`-class — would need a different predicate; out of scope here.) Commands that act on *everything* (`caa`, `w-wip`) use the sibling `has_untracked_or_pending_changes`, which includes untracked — §10 has the two-predicate model.

**The predicate wraps the existing primitive, not a third copy.** #225 already introduced `get_dirty_files` (`hug-git-state:98`) — staged + unstaged tracked, deduped — documented as "MUST mirror `check_files_clean`'s … one algorithm, two consumers" (`hug-git-state:91-92`). `has_uncommitted_tracked_changes` is a thin boolean over it:

```bash
has_uncommitted_tracked_changes() { [ -n "$(get_dirty_files)" ]; }
```

`cmv`'s clean-gate (`git-cmv:130`, currently `has_staged_changes || has_unstaged_changes`) is the **second consumer to unify** onto `get_dirty_files`, so the tier decision, the clean-gate, and the guard-completeness audit (§10) all read one algorithm. The spec's entire safety case ("the tier decision and the guard agree **by construction**") lives or dies on there being exactly one dirty-detection algorithm — naming the existing primitive is what keeps it that way.

Both paths then consume `$tier`. The dirty branch keeps #225's danger semantics (refuses `-y`, exit 3 — verified present on `origin/main` @ `1296dbf`, where `git-h-rewind:94/103` use `prompt_confirm_danger`); the clean branch lowers to warn and prints the recovery hint.

### Step 4 — `hug h restore` + one hint helper

**(a) The primitive** (`git-config/bin/git-h-restore`), the inverse-of-a-mover reset:

```bash
# Usage: hug h restore <target> --back|--undo|--rollback|--rewind [-y|-f]
#   op-flag REQUIRED (${op:?}) — names the op being inverted; its reset mode comes from
#   ONE literal table, so the mode-match is by construction (no git mode at the call site).
#   Warn-tier, EXCEPT --rewind (hard) on a dirty tracked tree ⇒ danger (refuses -y, exit 3).

case "${op:?usage: hug h restore <SHA> --back|--undo|--rollback|--rewind}" in
  back)     mode=soft  ;;   # ≡ reset --soft  — preserves staged
  undo)     mode=mixed ;;   # ≡ reset --mixed — preserves unstaged
  rollback) mode=keep  ;;   # ≡ reset --keep  — preserves uncommitted; aborts if dirty-in-range
  rewind)   mode=hard  ;;   # ≡ reset --hard  — preserves nothing
  *)        error_usage "unknown --op flag: use --back|--undo|--rollback|--rewind" ;;  # never a silent default mode
esac

check_git_repo   # standard repo guard: validate the repo before operating (as every mover does)

# The one genuinely ambiguous input: a bare 1–3 digit numeric, which resolve_head_target
# silently reinterprets as HEAD~N (regex ^[1-9][0-9]{0,2}$, hug-git-repo:327). A human typing a
# short SHA-prefix from memory ("42") might mean the commit, not HEAD~42 — so refuse the bare
# form and ask for clarity; an explicit HEAD~N is fine. Short SHAs (4+ chars) are unambiguous —
# the regex is bounded to 1–3 digits — and resolve normally, as do full SHAs / branch / tag names.
[[ "${1:?target required}" =~ ^[1-9][0-9]{0,2}$ ]] && \
  error_usage "ambiguous target '$1': reads as HEAD~$1 — pass a 4+-char SHA prefix or an explicit HEAD~N"
target=$(resolve_target_with_temporal "" "" "$1" '') || exit 1

# Never short-circuit on a forward target: only an EXACT match is a true no-op.
if [ "$target" = "$(git rev-parse HEAD)" ]; then
  info "Already at $(git rev-parse --short "$target"). Nothing to restore."
  exit 0
fi

tier=warn
if [ "$mode" = hard ] && has_uncommitted_tracked_changes; then
  tier=danger   # --rewind would destroy uncommitted tracked edits (unrecoverable)
fi
# The two tiers take DIFFERENT argument forms, so dispatch by tier — a uniform
# prompt_confirm_${tier} call would mis-feed prompt_confirm_warn (ONE arg: the whole prompt,
# hug-confirm:28) and drop the reason; prompt_confirm_danger takes TWO (word + reason, hug-confirm:76).
# danger's typed word is the op name, consistent with the family.
case "$tier" in
  danger) prompt_confirm_danger "$op" "git reset --$mode discards uncommitted tracked edits (unrecoverable)" ;;
  warn)   prompt_confirm_warn "Reset --$mode to $(git rev-parse --short "$target")? Uncommitted work is preserved. [y/N]: " ;;
esac

git reset --"$mode" "$target"   # reaches the reset for EVERY non-identical target — the point
```

It deliberately does **not** call `handle_standard_operation`; its no-op test is exact-SHA equality, not the range-count gate (Appendix A.1 is the regression this prevents). The `case` is the single source of truth binding op→mode→preservation; `restore --help` prints that table (§7 Step 5).

**(b) The hint helper** — templates the command from the caller's own op name (no dead parameter, no hand-built strings):

```bash
# Usage: emit_head_recovery_hint <pre-op-HEAD> <op>
#   <op> ∈ back|undo|rollback|rewind — the op being inverted; the caller knows its own name.
# Prints to stderr. Called AFTER the op succeeds, so the SHA is final.
emit_head_recovery_hint() {
  local pre_op_head="${1:?}" op="${2:?}"
  test "${HUG_QUIET:-}" && return 0   # human-facing chatter — suppressed under --quiet (mirrors gum_log, hug-gum:42)
  printf '\nℹ️  HEAD moved. Recover with:\n    hug h restore %s --%s -y\n' \
    "$pre_op_head" "$op" >&2
}
```

Each warn-tier command captures `pre_op_head=$(git rev-parse HEAD)` **before** the git op, runs the op, and on success calls `emit_head_recovery_hint "$pre_op_head" "<own op>"` — e.g. `git-h-back` calls `emit_head_recovery_hint "$pre_op_head" "back"`, `git-h-squash` calls it with `"back"` too (squash inverts as a soft reset). The helper takes only `<pre-SHA>` and `<op>` — it has no way to express "you are on a different branch now," which is precisely why **`cmv` never calls it** (its branch switch is what makes recovery incomplete; §6). If a future branch-switching op needs a recovery, the helper grows a branch precondition then — not speculatively.

**Placement invariant:** the hint prints only on the **success** path of the actual git op, never before it. A failed/aborted op prints no hint (nothing to recover). It is suppressed under `HUG_QUIET=T` (human-facing chatter → stderr, same discipline as the preview); `show_help` says so (§7 Step 5), since agents reading `-h` would otherwise expect a hint from a scripted op.

**The hint is uniformly `-y` and forward-looking; the data-loss caveat lives on the op, not the hint.** The helper always prints `-y`, and the reason is **per-mode, not "the tree is clean"**: `--rewind`'s only escalation is `--rewind`+dirty-*tracked*, and `reset --hard` leaves the tree tracked-clean by definition — so `-y` always proceeds there (§6's h-rewind row). `--back`/`--undo`/`--rollback` **never** escalate: they preserve whatever residue the op left (staged / unstaged / uncommitted), so `-y` is safe regardless of tree state — that residue IS the op's intended result, not collateral. (Do **not** "harden" `restore`'s warn path with a tracked-clean assertion: `--soft` leaves changes *staged* and `--mixed` leaves them *unstaged*, so such an assertion would refuse `-y` exactly when the residue exists and would *break* `--back`/`--undo` recovery.) The "your uncommitted edits were destroyed and cannot be recovered" signal for dirty `h-rewind` belongs on **the operation's own success output** (where the loss actually happens), NOT on the recovery hint, whose job is to point forward to the commit recovery. This keeps the helper two arguments forever and keeps §6/§8 consistent with §7.

### Step 5 — `RESTORE` sections in `show_help` (discoverability)

The one legitimate argument for putting recovery *on* the original command (a `hug h back --restore` flag) was **discoverability** — finding the inverse from the command you ran. A separate `restore` noun must earn that discoverability back, and it does, cheaply: **every restorable command's `show_help` ends with a `RESTORE` section naming its exact inverse** and noting that the command prints it (SHA filled in) on success.

```text
# hug h back --help  (tail)
RESTORE
    h-back is inverted by:
        hug h restore <pre-op-HEAD> --back -y
    On a successful h-back, hug prints this exact line with the pre-op SHA
    filled in. (--back ≡ git reset --soft — your changes stay staged.)
```

- Each restorable command (`h-back`, `h-undo`, `h-rollback`, `h-squash`, clean `h-rewind`) carries the section for **its own** op flag. `show_help` heredocs are **static text — not code-generated** from the §4.2 `case`; drift is instead prevented by the §8 discoverability test, which asserts each command's `RESTORE` section names the same op-flag its success hint prints (and §10's audit forbids hand-built recovery strings).
- `h-rewind --help` documents the clean/dirty split (clean ⇒ `restore --rewind -y`; dirty ⇒ danger). Add the evaluation-time note so a reader isn't confused by the two flags: immediately after `h-rewind` the tree is tracked-clean, so the printed `-y` hint proceeds; `restore --rewind -f` is needed only if you dirty the tree *before* recovering, and it recovers only the commits (the destroyed edits are gone).
- **`cmv --help` states it is NOT restorable** — danger tier; recovery is manual, branch-aware, multi-step (switch back to the source branch + reset there + repoint the target). Saying so explicitly is the honest counterpart to the warn-tier `RESTORE` sections.
- `hug h restore --help` prints the full op→mode→preservation table and documents the required op-flag and the `--rewind`+dirty escalation.

This makes recovery discoverable from either direction — from the command you ran (`h-back --help` → `RESTORE`), and from the recovery command itself (`restore --help` → the whole table) — without overloading any directional command with its inverse.

## 8. Testing

**Consistency guard (locks the invariant):** for each command, assert upstream and non-upstream resolve to the **same tier** — e.g. `h-undo -u` and `h-undo HEAD~1` both proceed under `-y` (warn); `h-rewind -u` (dirty) and `h-rewind HEAD~1` (dirty) both refuse under `-y` (danger, exit 3). If anyone re-hardcodes a tier, this fails.

**Empty-target / synced-upstream guard:** for `hug h back -u`, `h-undo -u`, `h-rollback -u`, **and `h-squash -u`** — each across all its upstream call sites and each state branch (forced / staged-dirty / clean) — on a synced or strictly-behind upstream, assert **exit 0 AND `$(git rev-parse HEAD)` unchanged AND no new commit created**. Exit-code-and-message alone is insufficient: today's broken `h-squash -u` already returns exit 0 while silently orphaning the HEAD commit under a fabricated `[squash] 0 commits…` commit (§7 Step 2), so "HEAD unchanged + no new commit" is the only assertion that distinguishes the fixed path from the bug. This asserts every rewritten upstream call site preserves the `[[ -z "${target:-}" ]] && exit 0` guard.

**Recovery-hint correctness (the §2 bar — the core of v2):** for each warn-tier command, after a successful op, assert:
1. The printed recovery command, **executed as a real `hug` invocation** (never just `git rev-parse`-parsed), restores HEAD to the pre-op commit (`$(git rev-parse HEAD)` equals the captured pre-op SHA). *The test must execute the real hug command, not merely parse the target — parsing succeeds even when recovery no-ops (Appendix A.1).*
2. **Forward-target regression (the exact failure mode):** set up a state where the recovery target is a *descendant* of current HEAD, run the printed `hug h restore <pre-SHA> --<op> -y`, and assert HEAD **moved** (exit 0 *and* HEAD ≠ pre-recovery HEAD). Guards against anyone re-routing `restore` through the aligned-target short-circuit.
3. Recovery reaches the pre-op commit **and preserves what the op preserved** (the §2 bar). Capture `git write-tree` and the tracked worktree state **before** the op; after running the printed recovery, assert **HEAD == pre-op SHA** plus the **per-mode preservation invariant** (measured across the restore itself): `restore --back` leaves the **index** byte-identical (`git write-tree` equal before/after the restore — soft touches only HEAD); `restore --undo` leaves **tracked worktree files** byte-identical (mixed resets the index, not the worktree); `restore --rollback` leaves locally-edited files **outside the range** byte-identical (§5). Do **not** assert either naive form: (a) "ss/su identical before and after recovery" fails *because the recovery works* (a clean-pre-op `h-back` recovers to a clean tree — the staged residue is re-committed, not lost); and (b) **"ss/su equal the pre-op capture"** fails for a staged file under `--undo` — a *perfect* recovery brings it back **unstaged** (mixed reset resets the index by definition, so `write-tree` differs too), because recovery restores **HEAD, not the pre-op index**. The §2(b) bar is the *working-tree content* the op left intact — which the per-mode invariant captures, not a blanket ss/su snapshot.
4. For `h-rollback`, assert the §5 invariant empirically through the *hug layer*: when the original rollback *runs* (dirty file outside the range), `hug h restore <pre-op-HEAD> --rollback -y` recovers exactly and preserves the uncommitted edits; when a dirty file is *in* the range, the original op aborts (exit non-zero, HEAD unchanged) so no recovery is needed.

**`hug h restore` unit coverage:** exact-SHA target ⇒ "Already at …", exit 0, HEAD unchanged; forward (descendant) target ⇒ moves; `--rewind` on dirty tracked tree + `-y` ⇒ refused, exit 3; `--rewind` on clean tree + `-y` ⇒ proceeds; `--back`/`--undo`/`--rollback` on dirty tree + `-y` ⇒ proceeds (work preserved); missing op-flag ⇒ non-zero (bash `${op:?}` exits 127); unknown op-flag ⇒ `error_usage`, exit 2 (`HUG_EX_USAGE`); a bare 1–3-digit numeric (e.g. `42`, which the family would otherwise read as `HEAD~42`) ⇒ `error_usage`, exit 2 — but a short hex SHA (e.g. `a1b2`) and an explicit `HEAD~N` resolve normally (the guard rejects only the ambiguous bare numeric, never a silent wrong-commit reset). Mid-conflict (unmerged paths) + `restore --rewind` ⇒ danger — `get_dirty_files` reports the unmerged file (both substrates see it); name this state explicitly, since no other §8 case covers it. **Op→mode table is asserted once**, so the §4.2 mapping (back≡soft, undo≡mixed, rollback≡keep, rewind≡hard) has a single test guarding it.

**`cmv` is danger:** no recovery hint is printed on success; decline ⇒ exit 1; `-y` ⇒ refused, exit 3 (danger); `-f` proceeds and the clean-gate (`git-cmv:130`) still refuses a dirty tree. Assert the current branch *changed* after success (the very fact that makes recovery incomplete).

**State-dependent `h-rewind`:**
- Clean tree + no flag → proceeds at warn, prints `hug h restore <pre-op-HEAD> --rewind -y` hint; `-y` proceeds (today: refused).
- Dirty tree + `-y` → refused, exit 3 (danger); `-f` proceeds; the **op's success output** states "uncommitted edits were destroyed and cannot be recovered"; the recovery hint (commit part) is `hug h restore <pre-op-HEAD> --rewind -y` and proceeds (the tree is tracked-clean post-rewind).
- Clean vs dirty tier selected by the **shared** `has_uncommitted_tracked_changes` predicate (§7 Step 3).

**Conditional-skip preservation (do not flatten):** several commands skip the gate when the tree is clean (`h-back` prompts only `if has_staged_changes` at `git-h-back:108`; `h-undo`/`h-squash` use a `should_prompt` flag false when clean). The tier change replaces the **prompt call inside the confirmed branch**, leaving the surrounding `if dirty … else skip` byte-for-byte intact. Include a clean-tree case: `hug h undo` / `hug h squash -u` with no `-y` and a clean tree → exit 0, no prompt. (Failure mode if ignored: clean-tree CI automation breaks.) **When editing `git-h-squash`'s gate, fold in the pre-existing dead conditional at `git-h-squash:206/208`** (the if/else arms are byte-identical `prompt_confirm_danger "squash" …` calls).

**Exit-code contract (unchanged family rules):** danger + `-y` → exit 3 (`HUG_EX_BLOCKED`); danger + `-f` → proceed; warn + `-y`/`-f` → proceed (exit 0); warn + decline → exit 1.

**Discoverability (RESTORE help sections):** each restorable command's `--help` contains a `RESTORE` section naming its own `hug h restore … --<op>` inverse; `cmv --help` states it is not restorable; `hug h restore --help` prints the op→mode→preservation table. Assert the op-flag named in a command's `RESTORE` section matches the op-flag its success hint prints (they come from one table, so a drift here fails the test).

**Test migration:** v1's §6 inventory (the gum-mock vs real-gum mechanics, the `HUG_TEST_GUM_CONFIRM=no` / `HUG_DISABLE_GUM=true` + piped-`read` recipes) carries over **as-is** for the four commands lowering danger→warn — re-resolve line anchors at impl time. The `h-rewind` clean/dirty split and the `hug h restore` suite add new cases on top.

**Help text (concern #5):** warn-tier commands document `-y` auto-confirms + that a recovery hint is printed **and that the hint is suppressed under `HUG_QUIET=T`** (and carry the `RESTORE` section, §7 Step 5). Recovery-hint suppression is tested **directly**, not just via the help's claim: `HUG_QUIET=T hug h back 2 -y` prints **no** hint (the helper's `test "${HUG_QUIET:-}" && return 0` guard, §7 Step 4b).

## 9. Sign-off flag — partial revert of #225

> **✅ Owner sign-off — approved 2026-07-29.** Clean-tree `h-rewind` lowers to warn + recovery hint; dirty-tree stays danger. The §10 guard-completeness audit is the prerequisite that lands with/before this change. Reversible: if `has_uncommitted_tracked_changes` ever proves incomplete, `h-rewind` reverts to unconditional danger.

#225 made `h-rewind` **unconditionally danger** on both paths (the right call under v1's op-determined model). v2 lowers the **clean-tree** path to warn+hint. This is a deliberate behavior change requiring explicit owner sign-off:

- **Baseline is `origin/main` @ `1296dbf` (post-#225), and the branch is rebased onto it** — so the code this signs off on (`git-h-rewind:94/103` `prompt_confirm_danger` on both paths) is actually in the working tree.
- **Dirty-tree `h-rewind` stays danger** — unchanged from #225. No regression to the data-loss guard #225 added.
- **Clean-tree `h-rewind` becomes warn + recovery hint** — `-y` now proceeds; the hint `hug h restore <pre-op-HEAD> --rewind -y` is printed. Justified by §2: a clean tree yields a complete recovery command, so warn is honest.
- **Risk accepted:** the clean/dirty split hinges on `has_uncommitted_tracked_changes` being complete (§7 Step 3, §10). If that predicate ever under-counts (the #220/#227 class), a dirty tree could be mis-classified clean and `h-rewind -y` would destroy edits. **This is why §10 (guard-completeness audit) is a prerequisite, not a follow-up.**

## 10. Prerequisite — concern #6 guard-completeness audit (no longer deferred)

Under v1, concern #6 ("silent no-op masks dirty state" / guard-scope-miss) was deferred cleanup. Under v2 it is a **prerequisite**, because hint-completeness is what licenses the warn tier: if `has_uncommitted_tracked_changes` (or `cmv`'s clean-gate, or any hug-coded guard) misses part of the at-risk set, the printed recovery command is incomplete *and* the tier is wrong — silently lowering a danger op to warn.

**Scope of the audit (must land before or with v2):**

- **One dirty-detection algorithm, two named predicates.** Two legitimately different questions, two single-purpose predicates reading the **same git state** (index + worktree + untracked), and an audit that **no third detection path appears** (the #220/#227 invariant):
  - **`has_uncommitted_tracked_changes`** (NEW) — staged + unstaged **tracked** only; tracked-only by construction, since `git diff` never reports untracked (and `reset` never touches untracked). A thin boolean over the existing `get_dirty_files` (`hug-git-state:98`): `has_uncommitted_tracked_changes() { [ -n "$(get_dirty_files)" ]; }`. This is the predicate for every **safety/tier** decision: `h-rewind`'s tier, `cmv`'s clean-gate (`git-cmv:130`), `hug h restore`'s `--rewind`+dirty escalation, **and `handle_standard_operation`'s aligned-target short-circuit (`hug-git-upstream:99`)**. That last one today uses the broad predicate below, so it prints "local **tracked** changes will be reset" even when only *untracked* files exist — a latent lie (no reset mode touches untracked); switch it to this tracked-only predicate.
  - **`has_untracked_or_pending_changes`** — `has_pending_changes` **renamed, body unchanged**: it already IS the single `git status --porcelain=2` capture (incl. its SIGPIPE-safe capture-then-filter comment, `hug-git-state:23-31`; tracked = non-`?` lines, untracked = `?` lines). For commands that act on *everything*: `git-caa:85` (`git add -A` + commit) and `git-w-wip:111` (save-all-work) must not report "no changes" when untracked files exist. (`git-rb:138` is behavior-neutral — a cheap gate before the tracked-only `check_working_tree_clean`.)

  The rename makes the untracked-inclusion explicit in the name; the bare "pending changes" is exactly what let `hug-git-upstream:99` conflate the two. The two predicates **agree because they read the same git state, not because they share one process launch** — `get_dirty_files` (diff-based) and the status capture agree in every state including conflicts (verified, Appendix A.3). The discipline being extended is `get_dirty_files`'s "MUST mirror `check_files_clean` … one algorithm" doc (`hug-git-state:91-92`).
- **One op→mode table.** The `restore` primitive's `case` (§7 Step 4a) is the single binding of op→reset-mode→preservation; the hint helper and every `RESTORE` help section are **kept consistent with it by the §8 discoverability test and this audit** (the `show_help` heredocs are static text, not generated from the `case` — §7 Step 5). Audit that no command hand-builds a recovery string or hardcodes a mode outside this table (same drift hazard, same discipline).
- **`handle_standard_operation` short-circuit (`hug-git-upstream:96-101`) — two no-op classes.** (a) The known "silent no-op masks a dirty tree" class (#220 was this for `w get`). (b) **The forward-target class (the one that motivates this design):** for a *descendant* target the range count is 0, so a recovery that round-trips through this helper exits 0 without resetting. The mitigation is structural — recovery uses `hug h restore`, which does not share this gate (§4.2) — and the forward-target regression test (§8, Recovery-hint correctness item 2) locks it.
- **`cmv` — structural incompleteness, not a guard bug.** Its clean-gate is fine; the *operation* (branch switch at `git-cmv:242-243` + SHA rewrite via cherry-pick) has no single-command recovery, so `cmv` is **danger** (§6). No hint until a genuinely complete, branch-aware, multi-command recovery is designed (separate work).
- **`h-rollback` root path:** confirmed danger (§6) and out of scope for lowering; its `xargs rm -f` no-clean-gate is logged for a future root-path spec.
- **`h-back` / `h-undo` root paths** (`git-h-back:87-103`, `git-h-undo:96-121`): stay danger. A mechanical danger→warn sweep must skip them — at root, recovery is a guaranteed no-op (unborn HEAD ⇒ `rev-list` fails ⇒ `|| echo 0` ⇒ count 0), so there is no complete recovery to license warn.

If the audit finds a guard incomplete for a given command, **that command stays danger** (no hint, or partial hint) until the guard is fixed — the standard (§2) is not relaxed to hit a tier.

## 11. What changed from v1, and why

| Aspect | v1 (2026-07-27) | v2 | Why |
|---|---|---|---|
| Tier model | op-determined (by category) | **state-determined** (recovery-completeness) | op-model false-alarms (clean `h-rewind` needs `-f` for nothing); state-model matches agent risk reasoning and unifies with #218's `w get` decision |
| §2 rationale | "warn ⟺ reflog-recoverable" | "warn ⟺ complete recovery command exists" — used as a **probe** | "reflog-recoverable" buried the load-bearing structural-guard conditions; recovery-completeness is mechanically checkable and self-detecting for guard misses |
| Recovery command | absent | **one primitive `hug h restore <SHA> --<op>`** — op-named flags, mode implicit, never short-circuits forward targets | re-invoking the mover no-ops on forward targets (Appendix A.1); naming the flag for the inverted op makes the mode-match construction-enforced with no git vocabulary at the call site; the op names are reused strictly as **mode selectors** (direction comes from the target, not the flag — §4.2 caveat), so no command is overloaded with its inverse |
| Recovery discoverability | (n/a) | **`RESTORE` section in every restorable command's `--help`** (§7 Step 5) | earns back, for a separate command, the "find it from the command you ran" discoverability a per-command `--restore` flag would have given — without overloading the command with its inverse |
| `cmv` tier | warn + hint | **danger** | branch switch + SHA rewrite ⇒ no complete single-command recovery ⇒ not honestly warn |
| `h-rewind` tier | unconditional danger (both paths) | **state-dependent**: clean ⇒ warn+hint, dirty ⇒ danger | under recovery-completeness, a clean tree has a full recovery ⇒ warn is honest; dirty stays danger (unrecoverable edits) |
| `--keep` recovery (§5) | "unconditional" | **two layers** (raw-git invariant + hug-level precondition) | the invariant is real but only applies once the recovery actually reaches the reset (the primitive) |
| Dirty predicate | (unspecified) | **Two named predicates**, one shared algorithm (§10): `has_uncommitted_tracked_changes` (NEW, over `get_dirty_files`; four safety/tier consumers incl. `handle_standard_operation:99`) + `has_untracked_or_pending_changes` (`has_pending_changes` renamed; `caa`/`w-wip`) | avoids a third drifting copy of the dirty-detection algorithm — the exact #220/#227 class |
| #225 relationship | extended #225's danger to a tier param | **partially reverts** #225's clean-path danger (§9), branch rebased onto post-#225 | the model change propagates to `h-rewind`'s clean path; the rebase makes the sign-off honest |
| Concern #6 | deferred cleanup | **prerequisite** (§10), incl. the forward-target no-op class | hint-completeness now licenses the warn tier; an incomplete guard silently lies |

The v1 spec's *mechanism* (the `tier` param on `handle_upstream_operation`, one-tier-per-command consumed by both paths, the consistency guard, the test-migration inventory) is **retained** — v2 changes the *model that feeds the tier* and adds the recovery primitive, not the plumbing.

## 12. Scope

**In scope:** the `tier` param on `handle_upstream_operation`; per-command tier declarations (state-determined for `h-rewind`, warn for the four movers, **danger for `cmv`**) consumed by both paths; the **`hug h restore` primitive** (op-named flags, one op→mode table) + `emit_head_recovery_hint` helper + hints; **`RESTORE` help sections** on every restorable command + `restore --help` table; `h-rewind` clean/dirty split (partial #225 revert, §9); `has_uncommitted_tracked_changes` over `get_dirty_files` + `cmv`-gate unification; the §10 guard-completeness audit (incl. the forward-target class and the single op→mode table) as prerequisite; the empty-target guard on every rewritten upstream call site (pre-existing bug: exit-128 crash for h-back/h-undo/h-rollback, **silent history rewrite for h-squash** — §7 Step 2); the mechanical rename of `has_pending_changes` → `has_untracked_or_pending_changes` across `tests/lib/test_hug-git-state.bats` (11 sites, incl. the SIGPIPE regression test), `tests/lib/test_hug-git-kit.bats:33`, and `git-config/lib/README.md:95`; help-text `-y`/`-f`/recovery/`HUG_QUIET` docs; the consistency guard + recovery-correctness + forward-target regression + `restore` unit + discoverability + migration tests (§8); the `git-h-squash:206/208` dead-conditional cleanup folded into its gate edit.

**Out of scope → separate specs under #222:** `--dry-run` coverage (concern #3); family-wide exit-code reconciliation / `check_*_clean` exit 1 vs documented exit 3 (concern #4); the `h-rollback`/`h-back`/`h-undo` root-path danger-tier fixes (§10 notes); a genuinely complete branch-aware recovery for `cmv` (would re-open its tier); the `handle_upstream_operation` `HUG_QUIET=T` confirmation-skip path (unchanged here — documented as the `--quiet` escape hatch).

## 13. Review history

Refined through five adversarial review rounds, each replaying every behavioral claim against `origin/main` @ `1296dbf` in scratch repos (transcripts in Appendix A). Suitable for lifting into the PR description.

- **Round 1** found the original recovery design dead on arrival: re-invoking a mover to recover forward no-ops (the aligned-target short-circuit), and `cmv`'s hint ran on the wrong branch. Fix: the purpose-built `hug h restore` primitive (§4) and `cmv` → danger (§6).
- **Round 2** confirmed both Criticals resolved; resolved the hint helper's `-y`/`-f` contradiction (uniformly `-y`, data-loss caveat on the op's output) and surfaced the empty-target guard the upstream rewrite must preserve (§7 Step 2).
- **Round 3** found round 2 had mischaracterized `h-squash -u` (it fails *silently*, exit 0, orphaning the commit — not exit 128) and overclaimed the §4.1 clause (`has_pending_changes` counts untracked, so re-invocation recovery is state-accidental); established the two-predicate dirty-detection model (§10).
- **Round 4** (evidence base unfalsifiable) fixed four defects in the new prose: the `git reset --"$mode"` crash, the per-mode `-y` rationale (replacing a false "tree is tracked-clean after any reset" claim), the pre-op-vs-post-recovery test invariant, and §10's collapse to one implementation story.
- **Round 5** (confirmation) verified the per-mode rationale airtight for all four modes and fixed the §8 recovery invariant (a staged file under `--undo` comes back unstaged after a perfect recovery) plus minor count/anchor/attribute corrections. **Verdict: sign-off ready.**

**Recurring lessons:** verify a claim at the layer it asserts (target *parsing* ≠ recovery); a "(verified)" stamp that contradicts the document's own table is the most dangerous artifact; size a guard to the actual hazard (a bare numeric, not "non-full-SHA"); and a test must assert the actual harm, not a proxy the bug also satisfies (exit-code-only passed against the silent squash orphan).

---

## Appendix A — Evidence (verified replays)

All replays on `origin/main` @ `1296dbf` (the anchor baseline) in scratch repos.

### A.1 Forward-target recovery is a silent no-op

```text
# h-rewind (clean) + its would-be hint (re-invoke the mover)
$ hug h rewind 2 --force            # HEAD 3e383c4 → 968b3a0, clean tree
$ hug h rewind 3e383c4…64 -f        # re-invoke with the pre-op SHA
ℹ️ Info: Already at target 3e383c4. No action taken.
exit=0  HEAD still 968b3a0          # NOT recovered

# h-back, h-undo, h-rollback — identical shape:
$ hug h back     903528e… -y   → "Already at target 903528e. No action taken." exit=0, HEAD unmoved
$ hug h undo     903528e… -y   → same
$ hug h rollback 903528e… -y   → same (dirty file outside range — §5 case a — reset never reached)
```

Mechanism: `handle_standard_operation` (`hug-git-upstream:96-101`) computes `count_commits_in_range "$target" HEAD` = `rev-list --count "$target..HEAD"`. For a *forward* (descendant) target everything reachable from HEAD is reachable from its descendant, so the count is **0** → "Already at target" → `exit 0` before any reset. `h-squash` survives by topology (squash commit is a *sibling* of the pre-op tip ⇒ count ≠ 0), which is why it appeared to work. Fix: `hug h restore` (§4.2) tests exact-SHA equality for its no-op, not the range-count gate.

### A.2 `cmv`'s recovery ran on the wrong branch

`git-cmv` ends with `git checkout -q "$branch_name"` ("Stay on target branch", `git-cmv:242-243`), so any recovery hint executes on the **destination** branch against the **source** branch's pre-op HEAD:

```text
# main has its OWN commit 720e6a8; cmv 2 feature commits onto existing main:
$ hug cmv 2 main --force   → "Moved 2 commits to 'main'. Now on 'main'."  (success)
$ hug h back 2127c1b… -y   → "Moved HEAD back to 2127c1b"                 exit=0
$ hug ll -4 main
* 2127c1b (HEAD -> main) feature commit 2     # main now points into feature's old history
* 1cc7fc2 feature commit 1
* 685e40d (feature) base
# main's own commit 720e6a8 — GONE from main. feature branch — still reset. Nothing recovered.
```

New-branch case (`hug cmv 3 feature/api-refactor --new`): the new branch is created *at* the pre-op HEAD, so on it the range count is 0 → silent no-op. Existing-branch case (above): the cherry-picked commits are new SHAs (not descendants of the pre-op HEAD), so the short-circuit does **not** fire and `reset --soft` repoints the *destination* branch, orphaning its own commits — with the post-cmv tree clean, so `h-back`'s `if has_staged_changes` gate (`git-h-back:108`) skips confirmation entirely. A hug-printed "recovery" that manufactures a second incident is strictly worse than none ⇒ `cmv` is danger (§6).

### A.3 Supporting replays (referenced inline)

- **`--keep` abort symmetry (§5):** a dirty file *in* the reset range aborts the original (`Entry 'f.txt' not uptodate`, HEAD unchanged); a dirty file *outside* the range survives, and the forward `--keep` recovery succeeds cleanly.
- **Empty-target crash (§7 Step 2):** `h-back/-undo/-rollback -u` on a synced/strictly-behind upstream → `git reset "" ` exit 128; `h-squash -u` → silent orphan (fabricated `[squash] 0 commits…` commit, exit 0, HEAD replaced, divergence tip from `hug-git-commit:437`).
- **Predicate agreement (§10):** `get_dirty_files` (diff-based) and the porcelain status capture agree in every state including conflicts (unmerged paths reported by both).
- **`restore` target guard (§4.3):** bare `42` → `error_usage` (would read as `HEAD~42`); `a1b2`/`1234`/`HEAD~N`/branch/tag names resolve normally.
- **`-y` escalation (§7 Step 4b):** `restore --rewind` + dirty-*tracked* (staged, unstaged, or mid-conflict) ⇒ danger, refuses `-y`; `--back`/`--undo`/`--rollback` proceed under `-y` regardless of residue (work preserved).
