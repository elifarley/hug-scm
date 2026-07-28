# Design v2: State-determined confirmation tiers + recovery hints for the HEAD-mover family

- **Issue:** [elifarley/hug-scm#222](https://github.com/elifarley/hug-scm/issues/222) (concerns #1, #2, #5, and the #6 guard-completeness prerequisite)
- **Supersedes:** `docs/superpowers/specs/2026-07-27-head-movers-confirmation-tier-unification-design.md` (v1) — see §11 for what changed and why.
- **Partially reverts:** the unconditional-danger `h-rewind` from [elifarley/hug-scm#225](https://github.com/elifarley/hug-scm/pull/225) (its *dirty-tree* danger stays; its *clean-tree* path lowers to warn). See §9 for the sign-off flag.
- **Date:** 2026-07-28 (revised 2026-07-28 after implementation-grounded review — see revision note)
- **Status:** Design draft v2 (post-review revision), under user review
- **Branch/worktree:** `head-movers-tier-unify` (`~/src/hug-scm.WT.head-movers-tier-unify`), **rebased onto `origin/main` @ `1296dbf`** (post-#225)

> Anchors (`file:line`) are against `origin/main` @ `1296dbf` (post-#225); the branch is rebased onto exactly this commit, so anchors and working tree agree. Re-resolve at implementation time if `origin/main` moves.

> **Revision note (2026-07-28, post-review).** An implementation-grounded review replayed every "Verified" claim against the live code and found the original recovery design dead on arrival: re-invoking a mover command to recover forward **no-ops** (the aligned-target short-circuit, §4.1/Appendix A) and `cmv`'s hint ran on the wrong branch (§6/Appendix B). The fix adopted here: recovery is a **purpose-built primitive `hug h restore`** (§4, §7 Step 4) that never short-circuits forward targets, and `cmv` is **danger** (no complete recovery exists). Two design refinements followed: (a) the primitive's flags are the **names of the op being inverted** — `hug h restore <SHA> --back|--undo|--rollback|--rewind` — so the reset mode is implicit and mode-matched by construction (§4.2); (b) each restorable command's `--help` carries a **`RESTORE` section** naming its inverse, so recovery is discoverable from the command you ran (§7 Step 5). §5 is restated as two layers, §10 names the existing `get_dirty_files` primitive and adds the forward-target audit class, and the unverifiable "**Verified:**" prose is replaced by tests that execute the actual hug command (§8).

---

## 1. Problem

Six commands move HEAD via the shared `handle_upstream_operation` / `handle_standard_operation` helpers (`git-config/lib/hug-git-upstream`). Each has two paths — **non-upstream** (explicit target) and **upstream** (`-u`) — to the same git op. Today the tier is *implicit and inconsistent*: the helper hardcodes **warn** (`hug-git-upstream:71`) while each command's non-upstream block hardcodes **danger** (`git-h-back:109`, `git-h-undo:135`, `git-h-rewind:103`). So for every command, the upstream path is gated *weaker* than the non-upstream path for the *identical* operation — the inverted confirmation gradient ([elifarley/hug-scm#218](https://github.com/elifarley/hug-scm/issues/218) found it for `h-rewind`; it is the shape of all six).

v1 fixed the *consistency* (both paths same tier) using an **op-determined** model (tier ⟺ operation category). **v2 replaces the model itself**, because op-determination produces false alarms (clean-tree `h-rewind` demands `-f` for no protective purpose) and gives the user no way back when something does go wrong.

## 2. The standard — tier ⟺ completeness of the recovery command

> **A command's tier is `warn` iff a complete recovery command can be emitted for everything the operation changes. It is `danger` iff the operation changes something no command can recover.** The recovery command, run immediately after, must (a) restore exactly what changed, and (b) not disturb the working-tree/index state the operation left intact.

This subsumes three properties the user established during design:

1. **State-determined.** "What changed" depends on tree state. A clean-tree `h-rewind` changes only HEAD position (commits become reflog-only) → a complete recovery exists → **warn**. A dirty-tree `h-rewind` also destroys uncommitted working-tree edits, which have no git object → no recovery → **danger**. The tier falls out of state, not from a fixed per-op label.
2. **Recovery-hinted.** Every warn-tier op prints the *exact* recovery command (a literal hug invocation) to stderr on success. "Reflog-recoverable" is only a useful tier because hug hands the user the command to do the recovering.
3. **Safe-to-run-immediately.** The hint must not itself be a footgun: executing it right after the op restores the prior state and endangers nothing the user wanted to keep. This rules out the naive "always recover with `h-rewind <SHA>`" — and, as the review proved, also rules out "recover by re-invoking the same mover" (§4).

**Why this standard is stronger than v1's "reflog-recoverable":** v1's phrasing buried the load-bearing conditions (structural guards, reflog horizon). "Complete recovery command exists" is mechanically checkable: hug either can write the command or it can't. Incomplete enumeration (the [elifarley/hug-scm#220](https://github.com/elifarley/hug-scm/issues/220)/[#227](https://github.com/elifarley/hug-scm/pull/227) "guard misses part of the affected set" class) becomes *self-detecting* — if hug can't write a complete recovery command, it can't honestly print warn.

**The standard is also a probe, not just a label.** The review applied it mechanically to the six commands and it *falsified the original tier table*: five of six printed "recovery" commands did not recover (Appendix A/B). That is the standard working as intended — a tier whose recovery command no-ops is not warn-tier, by definition. The rest of this spec is the table rebuilt to satisfy the probe.

## 3. Assumptions (what makes state-determination safe enough here)

These are project conventions; the model relies on them. Documented, not enforced by this spec:

- **At most one writer per worktree.** Branch-worthy work happens in dedicated worktrees (`hug help :worktree`), so the cross-agent/cross-process filesystem race between a gate-time clean-check and the later git op is not a realistic threat. Residual TOCTOU is narrowed to (a) background tooling that writes inside the worktree (watchers, LSPs, build daemons) and (b) the agent's own intervening writes within one turn. Both are low-severity edge cases; documented, not blocking.
- **The main worktree stays on `main`.** So a misfired destructive op in a feature worktree has bounded blast radius (the feature's reflog), never corrupting the integration branch. This lowers the cost of a wrong tier decision and justifies accepting the residual TOCTOU above.
- **Recovery targets committed work, not working-tree edits.** Unstaged edits have no git object; nothing recovers them. So the recovery-hint requirement covers HEAD-position and commit loss; its *absence* (no possible hint) is itself the signal for danger.

## 4. Recovery command — one purpose-built primitive, named for the op it inverts

### 4.1 Why recovery cannot re-invoke the mover (the review's Critical finding)

The original v2 table recovered each op by re-invoking the *same family command* with the pre-op SHA (`hug h back <pre-SHA> -y`, etc.). **That is a silent exit-0 no-op for every forward (descendant) target** — which is exactly what a pre-op HEAD is after a rewind-family op. The shared helper short-circuits:

```bash
# git-config/lib/hug-git-upstream:90-101 (handle_standard_operation)
commits_to_affected=$(count_commits_in_range "$target" HEAD)   # = rev-list --count "$target..HEAD"
if [ "$commits_to_affected" -eq 0 ]; then
    if [[ "$skip_when_aligned" == true ]] || ! has_pending_changes; then
        info "Already at target $(git rev-parse --short "$target"). No action taken."
        exit 0      # <-- reset line never reached
```

After a rewind-family op the current HEAD is an *ancestor* of the pre-op HEAD, so `rev-list --count pre..HEAD` = **0** → "Already at target" → `exit 0`, HEAD unrestored. The short-circuit is **correct** for mover idempotency (re-running `h-back` when you're already there should do nothing); it is **lethal** for recovery, which must move *forward* to a descendant. The original spec's "**Verified:** all five commands accept an arbitrary target" verified target *parsing* (`rev-parse --verify` passes a full SHA through unchanged — that half is true), then asserted end-to-end recovery it never executed. `h-squash`'s hint happened to work, but by topological luck (the squash commit is a *sibling* of the pre-op tip, so `pre..HEAD ≠ 0`), not by any uniform property.

**Conclusion:** recovery must not round-trip through `handle_standard_operation`'s aligned-target short-circuit. It gets its own primitive — but one named so the original instinct ("recover with the family you trust") survives: the flag is the *op being inverted*, not a raw git mode.

### 4.2 The primitive: `hug h restore <target> --<op>`

`hug h restore` is a purpose-built HEAD-mover whose *only* job is to reset HEAD to an arbitrary commit as the inverse of a prior op. Its contract:

- **Never short-circuits on a forward target.** It tests `target == HEAD` (exact SHA equality) for a true no-op; any other target — ancestor *or* descendant — is a real reset. It does not call `count_commits_in_range`-gated `handle_standard_operation`. This is the whole reason it exists (Appendix A).
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

> **Naming caveat — the op names are reset-mode selectors, NOT directions.** The mover family already moves HEAD in *either* direction: `hug h back -u` moves **forward** when the local branch is behind upstream, and `h-back`'s help frames the op as "Moves HEAD to target." The name `back` has a documented history of misleading agents into assuming backward-only. `restore`'s flags reuse these names **strictly as mode selectors** — `--back` means "the soft-reset mode `h-back` uses" — and the *direction* of a restore is determined entirely by where `<target>` sits relative to HEAD, never by the flag. The `RESTORE` help sections and the `restore --help` table (§7 Step 5) state the mode equivalence explicitly so the name cannot mislead a second time. (If the deceiving names ever outweigh the "recover the op you ran" locality, the fallback is preservation-semantic flags — `--keep-staged`/`--keep-unstaged`/`--keep`/`--discard` — which name what happens to your work and need no direction disclaimer.)

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

**Target is the full pre-op SHA** (never a short hash or `HEAD~N` — those resolve differently after the op moves HEAD). Target parsing reuses the family's `resolve_target_with_temporal` → `git rev-parse --verify` path, which passes a full SHA through unchanged; `resolve_head_target`'s numeric regex `^[1-9][0-9]{0,2}$` cannot swallow a 40-hex SHA.

**Flag on the recovery command:** uniformly **`-y`** — `restore` is warn-tier in the recovery context (clean tree at recovery time, except the `--rewind`+dirty escalation which is danger by design). This dissolves the earlier draft's `-y`-vs-`-f` contradiction: recovery no longer re-invokes danger-tier `h-rewind`, so there is no per-op flag to disagree about.

## 5. `--keep` recovery is unconditional — stated as two layers

An earlier draft worried that recovering `h-rollback` with a forward `reset --keep` could trip `--keep`'s "Entry not uptodate" abort. The underlying git invariant is real and verified; the draft's error was asserting it about the *hug command* (`hug h rollback <pre-SHA>`) that never reaches git (Appendix A). Restated honestly, the argument has two layers:

**Layer 1 — the raw-git `--keep` invariant (verified, probe evidence retained).** `--keep` aborts when a file is **both** dirty **and** would be overwritten by the reset. Hence:

- If such a file exists, `--keep` refuses the **original** rollback (`git reset --keep HEAD~N` aborts before HEAD moves). The op never runs; there is nothing to recover.
- If the original rollback **does** run, every dirty file is *outside* the reset range (identical content at both ends). Going forward, those same dirty files are still outside the range → no conflict → forward `--keep` **succeeds cleanly**.

Probed across three scenarios: (a) dirty file unrelated to the range — original OK, forward `--keep` OK; (b) dirty file *in* the range — **original aborts** (`Entry 'f.txt' not uptodate`, HEAD unchanged; no recovery needed); (c) multi-commit range with a file changed mid-range but clean at both ends — original OK, recovery OK.

**Layer 2 — the hug-level precondition (why the primitive is required).** Layer 1 governs `git reset --keep`. For the *hug* recovery to inherit it, the recovery invocation must actually **reach** a `reset --keep`. Re-invoking `hug h rollback <pre-SHA>` does not — it exits at `handle_standard_operation`'s aligned-target short-circuit (Appendix A) before any reset. `hug h restore <pre-SHA> --rollback` (a `reset --keep` underneath, per the §4.2 table) **does** reach the reset, because it never short-circuits forward targets. **Therefore the §2 bar is met for `h-rollback` *conditional on the restore primitive*:** recovery is a single command, and Layer 1 guarantees it preserves the uncommitted edits and endangers nothing. Without the primitive, this section's original unconditional claim was false.

## 6. Per-command tier (both paths), post-v2

Tier is a property of the command's op+state, **identical on both paths** (the bug was that it wasn't). One declaration per command, consumed by both the upstream helper and the non-upstream gate.

| Command | Tier (both paths) | Why (recovery-completeness) |
|---|---|---|
| `h-back` | **warn** + hint | `--soft` preserves all work; `restore --back` restores HEAD completely |
| `h-undo` | **warn** + hint | `--mixed` preserves working tree; `restore --undo` restores HEAD completely |
| `h-rollback` (normal) | **warn** + hint | `--keep` preserves uncommitted work and refuses to run if a dirty file is in range; forward `restore --rollback` always succeeds (§5) |
| `h-rollback` (root path) | **danger** ⚠️ (unchanged) | runs `xargs rm -f` on tracked files, no clean gate — out of scope here; see §10 |
| `h-back` (root path) | **danger** ⚠️ (unchanged) | `git-h-back:87-101`: undoes the root commit (`reset_root_commit "soft"`); recovery at root is a guaranteed no-op (unborn HEAD ⇒ `rev-list` fails ⇒ count 0), so it must **not** be swept to warn |
| `h-undo` (root path) | **danger** ⚠️ (unchanged) | `git-h-undo:96-119`: same root-commit reasoning as `h-back` |
| `h-squash` | **warn** + hint | history rewrite; original commits reflog-recoverable via `restore --back` (soft) forward |
| `cmv` | **danger** (clean-gated) ⚠️ **CHANGED from the original v2 warn** | clean-gate (`git-cmv:130`) keeps the `--hard` from destroying uncommitted work, but the op **switches the current branch** (`git-cmv:242-243`) and **rewrites SHAs** (cherry-pick). No single same-branch `hug h restore` recovers "exactly what changed" → not honestly warn (§2). Danger, no recovery hint. |
| `h-rewind` (clean tree) | **warn** + hint | **CHANGED from #225's danger** — only HEAD moves; `restore --rewind` on the (clean) tree is a complete recovery |
| `h-rewind` (dirty tree) | **danger** + partial hint | uncommitted edits destroyed (unrecoverable); the commit part is recoverable via `hug h restore <pre-op-HEAD> --rewind -f` — but the destroyed working-tree edits cannot be, and the hint says so explicitly |

**Headline behavior changes vs. today:**
1. `h-rewind` becomes **state-dependent**: clean ⇒ warn+hint (was unconditional danger from #225); dirty ⇒ danger (unchanged). This is the partial revert of #225 — see §9.
2. `h-back`/`h-undo`/`h-rollback`/`h-squash` lower to **warn + hint** on both paths (their normal, non-root paths).
3. `cmv` is **danger** (was warn in the original v2 draft) — the honest reading of §2.
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

Each command sets `tier` (+ `action_word` + `danger_reason` where danger) near the top. Both the upstream call (`handle_upstream_operation "$verb" "$tier" …`) and the non-upstream gate (`prompt_confirm_${tier} …`) read it. One declaration, two consumers — they match **by construction**. A consistency-guard test (§8) asserts the two never diverge. **Root-commit paths keep their own `danger` gate** (`git-h-back:87-101`, `git-h-undo:96-119`): the one-tier-per-command sweep applies to the *normal* path only and must not lower the root path (§6).

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

**The predicate wraps the existing primitive, not a third copy (review Major).** #225 already introduced `get_dirty_files` (`hug-git-state:98`) — staged + unstaged tracked, deduped — documented as "MUST mirror `check_files_clean`'s … one algorithm, two consumers" (`hug-git-state:91-92`). `has_uncommitted_tracked_changes` is a thin boolean over it:

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

case "${op:?usage: hug h restore <target> --back|--undo|--rollback|--rewind}" in
  back)     mode=soft  ;;   # ≡ reset --soft  — preserves staged
  undo)     mode=mixed ;;   # ≡ reset --mixed — preserves unstaged
  rollback) mode=keep  ;;   # ≡ reset --keep  — preserves uncommitted; aborts if dirty-in-range
  rewind)   mode=hard  ;;   # ≡ reset --hard  — preserves nothing
  *)        usage_error ;;  # unknown op — never a silent default mode
esac

target=$(resolve_target_with_temporal "" "" "${1:?target required}" '') || exit 1

# Never short-circuit on a forward target: only an EXACT match is a true no-op.
if [ "$target" = "$(git rev-parse HEAD)" ]; then
  info "Already at $(git rev-parse --short "$target"). Nothing to restore."
  exit 0
fi

tier=warn
if [ "$mode" = hard ] && has_uncommitted_tracked_changes; then
  tier=danger   # --rewind would destroy uncommitted tracked edits (unrecoverable)
fi
prompt_confirm_${tier} ...    # warn auto-confirms with -y; danger needs -f / typed word

git reset "$mode" "$target"   # reaches the reset for EVERY non-identical target — the point
```

It deliberately does **not** call `handle_standard_operation`; its no-op test is exact-SHA equality, not the range-count gate (Appendix A is the regression this prevents). The `case` is the single source of truth binding op→mode→preservation; `restore --help` prints that table (§7 Step 5).

**(b) The hint helper** — templates the command from the caller's own op name (no dead parameter, no hand-built strings):

```bash
# Usage: emit_head_recovery_hint <pre-op-HEAD> <op>
#   <op> ∈ back|undo|rollback|rewind — the op being inverted; the caller knows its own name.
# Prints to stderr. Called AFTER the op succeeds, so the SHA is final.
emit_head_recovery_hint() {
  local pre_op_head="${1:?}" op="${2:?}"
  printf '\nℹ️  HEAD moved. Recover with:\n    hug h restore %s --%s -y\n' \
    "$pre_op_head" "$op" >&2
}
```

Each warn-tier command captures `pre_op_head=$(git rev-parse HEAD)` **before** the git op, runs the op, and on success calls `emit_head_recovery_hint "$pre_op_head" "<own op>"` — e.g. `git-h-back` calls `emit_head_recovery_hint "$pre_op_head" "back"`, `git-h-squash` calls it with `"back"` too (squash inverts as a soft reset). The helper takes only `<pre-SHA>` and `<op>` — it has no way to express "you are on a different branch now," which is precisely why **`cmv` never calls it** (its branch switch is what makes recovery incomplete; §6). If a future branch-switching op needs a recovery, the helper grows a branch precondition then — not speculatively.

**Placement invariant:** the hint prints only on the **success** path of the actual git op, never before it. A failed/aborted op prints no hint (nothing to recover). It is suppressed under `HUG_QUIET=T` (human-facing chatter → stderr, same discipline as the preview); `show_help` says so (§7 Step 5), since agents reading `-h` would otherwise expect a hint from a scripted op.

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

- Each restorable command (`h-back`, `h-undo`, `h-rollback`, `h-squash`, clean `h-rewind`) carries the section for **its own** op flag; the text is generated from the same §4.2 table, so help, hint, and primitive cannot drift.
- `h-rewind --help` documents the clean/dirty split (clean ⇒ `restore --rewind -y`; dirty ⇒ danger, `restore --rewind -f` recovers only the commits).
- **`cmv --help` states it is NOT restorable** — danger tier; recovery is manual, branch-aware, multi-step (switch back to the source branch + reset there + repoint the target). Saying so explicitly is the honest counterpart to the warn-tier `RESTORE` sections.
- `hug h restore --help` prints the full op→mode→preservation table and documents the required op-flag and the `--rewind`+dirty escalation.

This makes recovery discoverable from either direction — from the command you ran (`h-back --help` → `RESTORE`), and from the recovery command itself (`restore --help` → the whole table) — without overloading any directional command with its inverse.

## 8. Testing

**Consistency guard (locks the invariant):** for each command, assert upstream and non-upstream resolve to the **same tier** — e.g. `h-undo -u` and `h-undo HEAD~1` both proceed under `-y` (warn); `h-rewind -u` (dirty) and `h-rewind HEAD~1` (dirty) both refuse under `-y` (danger, exit 3). If anyone re-hardcodes a tier, this fails.

**Recovery-hint correctness (the §2 bar — the core of v2):** for each warn-tier command, after a successful op, assert:
1. The printed recovery command, **executed as a real `hug` invocation** (never just `git rev-parse`-parsed), restores HEAD to the pre-op commit (`$(git rev-parse HEAD)` equals the captured pre-op SHA). *This test, run honestly, is what falsified the original design (Appendix A) — it must execute the hug command, not verify target parsing.*
2. **Forward-target regression (the exact failure mode):** set up a state where the recovery target is a *descendant* of current HEAD, run the printed `hug h restore <pre-SHA> --<op> -y`, and assert HEAD **moved** (exit 0 *and* HEAD ≠ pre-recovery HEAD). Guards against anyone re-routing `restore` through the aligned-target short-circuit.
3. The recovery command does **not** alter the working-tree/index state the op left (after `h-back`, recovery leaves changes staged; after `h-undo`, unstaged). Assert via `hug ss`/`hug su` before and after recovery being byte-identical.
4. For `h-rollback`, assert the §5 invariant empirically through the *hug layer*: when the original rollback *runs* (dirty file outside the range), `hug h restore <pre-op-HEAD> --rollback -y` recovers exactly and preserves the uncommitted edits; when a dirty file is *in* the range, the original op aborts (exit non-zero, HEAD unchanged) so no recovery is needed.

**`hug h restore` unit coverage:** exact-SHA target ⇒ "Already at …", exit 0, HEAD unchanged; forward (descendant) target ⇒ moves; `--rewind` on dirty tracked tree + `-y` ⇒ refused, exit 3; `--rewind` on clean tree + `-y` ⇒ proceeds; `--back`/`--undo`/`--rollback` on dirty tree + `-y` ⇒ proceeds (work preserved); missing op-flag ⇒ usage error (never a silent default mode); unknown op-flag ⇒ usage error. **Op→mode table is asserted once**, so the §4.2 mapping (back≡soft, undo≡mixed, rollback≡keep, rewind≡hard) has a single test guarding it.

**`cmv` is danger:** no recovery hint is printed on success; decline ⇒ exit 1; `-y` ⇒ refused, exit 3 (danger); `-f` proceeds and the clean-gate (`git-cmv:130`) still refuses a dirty tree. Assert the current branch *changed* after success (the very fact that makes recovery incomplete).

**State-dependent `h-rewind`:**
- Clean tree + no flag → proceeds at warn, prints `hug h restore <pre-op-HEAD> --rewind -y` hint; `-y` proceeds (was: refused).
- Dirty tree + `-y` → refused, exit 3 (danger); `-f` proceeds, hint prints the commit-recovery command with an explicit "uncommitted edits were destroyed and cannot be recovered" caveat.
- Clean vs dirty tier selected by the **shared** `has_uncommitted_tracked_changes` predicate (§7 Step 3).

**Conditional-skip preservation (do not flatten):** several commands skip the gate when the tree is clean (`h-back` prompts only `if has_staged_changes` at `git-h-back:108`; `h-undo`/`h-squash` use a `should_prompt` flag false when clean). The tier change replaces the **prompt call inside the confirmed branch**, leaving the surrounding `if dirty … else skip` byte-for-byte intact. Include a clean-tree case: `hug h undo` / `hug h squash -u` with no `-y` and a clean tree → exit 0, no prompt. (Failure mode if ignored: clean-tree CI automation breaks.) **When editing `git-h-squash`'s gate, fold in the pre-existing dead conditional at `git-h-squash:206/208`** (the if/else arms are byte-identical `prompt_confirm_danger "squash" …` calls).

**Exit-code contract (unchanged family rules):** danger + `-y` → exit 3 (`HUG_EX_BLOCKED`); danger + `-f` → proceed; warn + `-y`/`-f` → proceed (exit 0); warn + decline → exit 1.

**Discoverability (RESTORE help sections):** each restorable command's `--help` contains a `RESTORE` section naming its own `hug h restore … --<op>` inverse; `cmv --help` states it is not restorable; `hug h restore --help` prints the op→mode→preservation table. Assert the op-flag named in a command's `RESTORE` section matches the op-flag its success hint prints (they come from one table, so a drift here fails the test).

**Test migration:** v1's §6 inventory (the gum-mock vs real-gum mechanics, the `HUG_TEST_GUM_CONFIRM=no` / `HUG_DISABLE_GUM=true` + piped-`read` recipes) carries over **as-is** for the four commands lowering danger→warn — re-resolve line anchors at impl time. The `h-rewind` clean/dirty split and the `hug h restore` suite add new cases on top.

**Help text (concern #5):** warn-tier commands document `-y` auto-confirms + that a recovery hint is printed **and that the hint is suppressed under `HUG_QUIET=T`** (and carry the `RESTORE` section, §7 Step 5).

## 9. Sign-off flag — partial revert of #225

#225 made `h-rewind` **unconditionally danger** on both paths (the right call under v1's op-determined model). v2 lowers the **clean-tree** path to warn+hint. This is a deliberate behavior change requiring explicit owner sign-off:

- **Baseline is `origin/main` @ `1296dbf` (post-#225), and the branch is rebased onto it** — so the code this signs off on (`git-h-rewind:94/103` `prompt_confirm_danger` on both paths) is actually in the working tree. (The original draft was written against a pre-#225 checkout; the rebase made the sign-off honest.)
- **Dirty-tree `h-rewind` stays danger** — unchanged from #225. No regression to the data-loss guard #225 added.
- **Clean-tree `h-rewind` becomes warn + recovery hint** — `-y` now proceeds; the hint `hug h restore <pre-op-HEAD> --rewind -y` is printed. Justified by §2: a clean tree yields a complete recovery command, so warn is honest.
- **Risk accepted:** the clean/dirty split hinges on `has_uncommitted_tracked_changes` being complete (§7 Step 3, §10). If that predicate ever under-counts (the #220/#227 class), a dirty tree could be mis-classified clean and `h-rewind -y` would destroy edits. **This is why §10 (guard-completeness audit) is a prerequisite, not a follow-up.**

## 10. Prerequisite — concern #6 guard-completeness audit (no longer deferred)

Under v1, concern #6 ("silent no-op masks dirty state" / guard-scope-miss) was deferred cleanup. Under v2 it is a **prerequisite**, because hint-completeness is what licenses the warn tier: if `has_uncommitted_tracked_changes` (or `cmv`'s clean-gate, or any hug-coded guard) misses part of the at-risk set, the printed recovery command is incomplete *and* the tier is wrong — silently lowering a danger op to warn.

**Scope of the audit (must land before or with v2):**
- **One dirty-detection algorithm.** Define `has_uncommitted_tracked_changes` as a thin boolean over the **existing** `get_dirty_files` (`hug-git-state:98`; staged + unstaged **tracked**, untracked excluded per §7 Step 3). Consumers to unify onto it: `h-rewind`'s tier decision, `cmv`'s clean-gate (`git-cmv:130`), and `hug h restore`'s `--rewind`+dirty escalation. **No third copy** — no ad-hoc `git diff --quiet` per command. `get_dirty_files` is already documented as "MUST mirror `check_files_clean`'s … one algorithm, two consumers" (`hug-git-state:91-92`); this makes it three consumers, one algorithm.
- **One op→mode table.** The `restore` primitive's `case` (§7 Step 4a) is the single binding of op→reset-mode→preservation; the hint helper and every `RESTORE` help section read from it. Audit that no command hand-builds a recovery string or hardcodes a mode outside this table (same drift hazard, same discipline).
- **`handle_standard_operation` short-circuit (`hug-git-upstream:96-101`) — two no-op classes.** (a) The known "silent no-op masks a dirty tree" class (#220 was this for `w get`). (b) **The forward-target class (new, the one that bit this spec):** for a *descendant* target the range count is 0, so a recovery that round-trips through this helper exits 0 without resetting. The mitigation is structural — recovery uses `hug h restore`, which does not share this gate (§4.2) — and the forward-target regression test (§8.2) locks it.
- **`cmv` — structural incompleteness, not a guard bug.** Its clean-gate is fine; the *operation* (branch switch at `git-cmv:242-243` + SHA rewrite via cherry-pick) has no single-command recovery, so `cmv` is **danger** (§6). No hint until a genuinely complete, branch-aware, multi-command recovery is designed (separate work).
- **`h-rollback` root path:** confirmed danger (§6) and out of scope for lowering; its `xargs rm -f` no-clean-gate is logged for a future root-path spec.
- **`h-back` / `h-undo` root paths** (`git-h-back:87-101`, `git-h-undo:96-119`): stay danger. A mechanical danger→warn sweep must skip them — at root, recovery is a guaranteed no-op (unborn HEAD ⇒ `rev-list` fails ⇒ `|| echo 0` ⇒ count 0), so there is no complete recovery to license warn.

If the audit finds a guard incomplete for a given command, **that command stays danger** (no hint, or partial hint) until the guard is fixed — the standard (§2) is not relaxed to hit a tier.

## 11. What changed from v1, and why

| Aspect | v1 (2026-07-27) | v2 (2026-07-28, post-review) | Why |
|---|---|---|---|
| Tier model | op-determined (by category) | **state-determined** (recovery-completeness) | op-model false-alarms (clean `h-rewind` needs `-f` for nothing); state-model matches agent risk reasoning and unifies with #218's `w get` decision |
| §2 rationale | "warn ⟺ reflog-recoverable" | "warn ⟺ complete recovery command exists" — used as a **probe** | "reflog-recoverable" buried the load-bearing structural-guard conditions; recovery-completeness is mechanically checkable, self-detecting for guard misses, and (applied mechanically) is what caught the original table |
| Recovery command | absent | **one primitive `hug h restore <SHA> --<op>`** — op-named flags, mode implicit, never short-circuits forward targets | re-invoking the mover no-ops on forward targets (Appendix A); naming the flag for the inverted op makes the mode-match construction-enforced with no git vocabulary at the call site; the op names are reused strictly as **mode selectors** (direction comes from the target, not the flag — §4.2 caveat), so no command is overloaded with its inverse |
| Recovery discoverability | (n/a) | **`RESTORE` section in every restorable command's `--help`** (§7 Step 5) | earns back, for a separate command, the "find it from the command you ran" discoverability a per-command `--restore` flag would have given — without overloading the command with its inverse |
| `cmv` tier | (v2 draft: warn + hint) | **danger** | branch switch + SHA rewrite ⇒ no complete single-command recovery ⇒ not honestly warn |
| `h-rewind` tier | unconditional danger (both paths) | **state-dependent**: clean ⇒ warn+hint, dirty ⇒ danger | under recovery-completeness, a clean tree has a full recovery ⇒ warn is honest; dirty stays danger (unrecoverable edits) |
| `--keep` recovery (§5) | "unconditional" | **two layers** (raw-git invariant + hug-level precondition) | the invariant is real but the original draft asserted it about a hug command that never reaches git |
| Dirty predicate | (unspecified) | **`get_dirty_files`** (existing, post-#225), one algorithm / three consumers | avoids a third drifting copy of the dirty-detection algorithm — the exact #220/#227 class |
| #225 relationship | extended #225's danger to a tier param | **partially reverts** #225's clean-path danger (§9), branch rebased onto post-#225 | the model change propagates to `h-rewind`'s clean path; the rebase makes the sign-off honest |
| Concern #6 | deferred cleanup | **prerequisite** (§10), incl. the forward-target no-op class | hint-completeness now licenses the warn tier; an incomplete guard silently lies |

The v1 spec's *mechanism* (the `tier` param on `handle_upstream_operation`, one-tier-per-command consumed by both paths, the consistency guard, the test-migration inventory) is **retained** — v2 changes the *model that feeds the tier* and adds the recovery primitive, not the plumbing.

## 12. Scope

**In scope:** the `tier` param on `handle_upstream_operation`; per-command tier declarations (state-determined for `h-rewind`, warn for the four movers, **danger for `cmv`**) consumed by both paths; the **`hug h restore` primitive** (op-named flags, one op→mode table) + `emit_head_recovery_hint` helper + hints; **`RESTORE` help sections** on every restorable command + `restore --help` table; `h-rewind` clean/dirty split (partial #225 revert, §9); `has_uncommitted_tracked_changes` over `get_dirty_files` + `cmv`-gate unification; the §10 guard-completeness audit (incl. the forward-target class and the single op→mode table) as prerequisite; help-text `-y`/`-f`/recovery/`HUG_QUIET` docs; the consistency guard + recovery-correctness + forward-target regression + `restore` unit + discoverability + migration tests (§8); the `git-h-squash:206/208` dead-conditional cleanup folded into its gate edit.

**Out of scope → separate specs under #222:** `--dry-run` coverage (concern #3); family-wide exit-code reconciliation / `check_*_clean` exit 1 vs documented exit 3 (concern #4); the `h-rollback`/`h-back`/`h-undo` root-path danger-tier fixes (§10 notes); a genuinely complete branch-aware recovery for `cmv` (would re-open its tier); the `handle_upstream_operation` `HUG_QUIET=T` confirmation-skip path (unchanged here — documented as the `--quiet` escape hatch).

---

## Appendix A — Evidence: forward-target recovery is a silent no-op (Critical)

Replayed on `origin/main` @ `1296dbf` (the anchor baseline) in scratch repos:

```text
# h-rewind (clean) + its original hint
$ hug h rewind 2 --force            # HEAD 3e383c4 → 968b3a0, clean tree
$ hug h rewind 3e383c4…64 -f        # the original printed hint (re-invoke mover)
ℹ️ Info: Already at target 3e383c4. No action taken.
exit=0  HEAD still 968b3a0          # NOT recovered

# h-back, h-undo, h-rollback — identical shape:
$ hug h back     903528e… -y   → "Already at target 903528e. No action taken." exit=0, HEAD unmoved
$ hug h undo     903528e… -y   → same
$ hug h rollback 903528e… -y   → same (dirty file outside range — §5 case a — reset never reached)
```

Mechanism: `handle_standard_operation` (`hug-git-upstream:96-101`) computes `count_commits_in_range "$target" HEAD` = `rev-list --count "$target..HEAD"`. For a *forward* (descendant) target everything reachable from HEAD is reachable from its descendant, so the count is **0** → "Already at target" → `exit 0` before any reset. `h-squash` survives by topology (squash commit is a *sibling* of the pre-op tip ⇒ count ≠ 0), which is why it appeared to work. Fix: `hug h restore` (§4.2) tests exact-SHA equality for its no-op, not the range-count gate.

## Appendix B — Evidence: `cmv`'s recovery ran on the wrong branch (Critical)

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
