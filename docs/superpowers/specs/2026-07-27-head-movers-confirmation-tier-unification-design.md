# Design: Unify confirmation tiers across the 6 HEAD-mover commands

- **Issue:** [elifarley/hug-scm#222](https://github.com/elifarley/hug-scm/issues/222) (broad audit; this spec addresses its concern #1)
- **Supersedes part of:** [elifarley/hug-scm#218](https://github.com/elifarley/hug-scm/issues/218) — the `h-rewind` both-paths→danger fix (File 3 of that spec); see §5.
- **Date:** 2026-07-27
- **Status:** Design draft, under user review
- **Branch/worktree:** `head-movers-tier-unify` (`~/src/hug-scm.WT.head-movers-tier-unify`), off `origin/main`

> Line numbers cited below are anchors against the files as they stood at design time (2026-07-27, `origin/main`). Re-resolve at implementation time. Note #218 lands first and rewrites parts of `git-h-rewind`; re-resolve `h-rewind` anchors against the post-#218 tree.

---

## 1. Problem — the inverted confirmation gradient is systemic

Six commands move HEAD and share the `handle_upstream_operation` helper (`git-config/lib/hug-git-upstream:30`). Each has **two code paths** to the same destructive git operation:

- **Non-upstream** — target named explicitly (`HEAD~N`, SHA, branch): `resolve_target_with_temporal` → `handle_standard_operation` (preview) → the command's **own** confirmation gate → the git op.
- **Upstream** — target computed from the tracked upstream branch via `-u`/`--upstream`: `handle_upstream_operation` (validation + preview + confirmation) → the git op.

The helper **hardcodes a single confirmation tier — warn** (`prompt_confirm_warn` at hug-git-upstream:71) — for all six callers, regardless of destructiveness. Meanwhile every command's non-upstream path gates at **danger** (typed-word, `-y` refused). So for every one of the six, the upstream path is gated *weaker* than the non-upstream path for the *identical* destructive operation:

```
hug h rewind HEAD~3   →  type "rewind" (danger; -y refused)
hug h rewind -u       →  y            (warn;   -y auto-confirms)   ← same git reset --hard
```

elifarley/hug-scm#218 found this for `h-rewind` in isolation. The audit shows it is the **shape of all six** — the root cause is the hardcoded warn tier in the shared helper plus ad-hoc (all-danger) non-upstream gates that nothing keeps in agreement.

## 2. Risk tiering — the decision

**Principle:** `danger` ⟺ the operation can destroy **unrecoverable uncommitted work**; `warn` ⟺ everything is reflog-recoverable or preserved. This matches the family's own definitions (`prompt_confirm_danger` comment: "Irreversible or high-impact"; `prompt_confirm_warn`: "destructive but recoverable").

| Command | Op | Can destroy uncommitted work? | **Both paths →** |
|---|---|---|---|
| `h-rewind` | `reset --hard`, **no clean gate** | **YES — unrecoverable** | **danger** |
| `h-cmv` | `reset --hard` on a **clean-gated** tree (comment: "safe since tree/index clean", git-cmv:~220) | No (refuses if dirty; history reflog-recoverable) | **warn** |
| `h-squash` | combine commits | No (history only, reflog) | **warn** |
| `h-rollback` | `reset --keep` (preserves other uncommitted changes) | No (reflog for commits) | **warn** |
| `h-back` | `reset --soft` (changes kept staged) | No (nothing lost) | **warn** |
| `h-undo` | `reset --mixed` (changes kept unstaged) | No (nothing lost) | **warn** |

**`h-rewind` is the only command that can destroy unrecoverable uncommitted work** — it runs `reset --hard` with no cleanliness gate. Every other command either preserves work or explicitly refuses to run on a dirty tree. The rest are reflog-recoverable history rewrites → warn.

## 3. Mechanism — one tier per command, both paths consume it

The root cause is that the tier is *implicit*: hardcoded as warn inside the helper, and chosen ad-hoc (all danger) in each non-upstream block. Nothing forces agreement. **Fix: each command owns exactly one tier; both paths read it.**

### Step 1 — `handle_upstream_operation` gains a required `tier` parameter

```bash
# Usage: target=$(handle_upstream_operation "rewinding" danger "rewind" "git reset --hard is irreversible")
#   $1 - action verb, for warn/safe messages (e.g. "rewinding")
#   $2 - tier ∈ {safe,warn,danger}   REQUIRED (${2:?} — no default, so a future dangerous
#                                     caller cannot silently inherit warn)
#   $3 - action WORD for the danger typed-confirm (e.g. "rewind"). The verb→word mapping is
#        irregular ("moving"→"move", not "mov"), so it is passed explicitly, NOT derived.
#        (Unused for warn/safe, but always pass it — keeps the call shape uniform.)
#   $4 - danger reason (used only when tier=danger)
handle_upstream_operation() {
  local action_name="$1" tier="${2:?handle_upstream_operation requires a confirmation tier}"
  local action_word="$3" danger_reason="${4:-}"
  ... # validation + preview (lines 33–68) unchanged
  case "$tier" in
    danger) prompt_confirm_danger "$action_word" "$danger_reason" ;;
    warn)   prompt_confirm_warn   "Proceed with $action_name to upstream? [y/N]: " ;;
    safe)   prompt_confirm_safe   "Proceed with $action_name to upstream?" ;;
  esac
  echo "$target"
}
```

**Note — the helper currently emits the preview + warn prompt inside a single `if [[ HUG_QUIET != T ]]` block (lines 49–72).** The tier-dispatch `case` replaces the `prompt_confirm_warn` call at line 71, staying inside that same block, so `HUG_QUIET=T` still skips preview+confirmation together (behavior preserved).

This **retires the `HUG_FORCE=true handle_upstream_operation` wrapper hack** that #218's File 3 resorted to (which suppressed the warn gate via `HUG_FORCE` while keeping the preview). Passing `tier=danger` directly gives preview + a single danger gate — no env trick, no double-prompt.

### Step 2 — each command declares its tier once; both paths consume it

Each command sets `tier` (+ `action_word` + `danger_reason` where danger) near the top, then:
- upstream: `handle_upstream_operation "$verb" "$tier" "$danger_reason"`
- non-upstream: `prompt_confirm_${tier} ...`

One declaration, two consumers — they match **by construction**. A consistency-guard test (§6) asserts the two never diverge.

## 4. Per-command changes

| Command | Non-upstream today → | Upstream today → | Net change |
|---|---|---|---|
| `h-rewind` | bespoke `read -p 'Type "rewind"...'` (git-h-rewind:93–100) → **`prompt_confirm_danger`** | warn → **danger** | both paths → danger; bespoke `read` deleted; #218's `HUG_FORCE` hack superseded by `tier=danger` |
| `h-undo` | `prompt_confirm_danger` (git-h-undo:115,135) → **`prompt_confirm_warn`** | warn ✓ | non-upstream lowered to warn |
| `h-back` | `prompt_confirm_danger` (git-h-back:97,109) → **`prompt_confirm_warn`** | warn ✓ | non-upstream lowered to warn |
| `h-rollback` | `prompt_confirm_danger` (git-h-rollback:119) → **`prompt_confirm_warn`** | warn ✓ | non-upstream lowered to warn |
| `h-squash` | `prompt_confirm_danger` (git-h-squash:206,208) → **`prompt_confirm_warn`** | warn ✓ | non-upstream lowered to warn |
| `h-cmv` | `prompt_confirm_danger` (git-cmv:184,217) → **`prompt_confirm_warn`** | warn ✓ | non-upstream lowered to warn |

**Two headline effects:**
1. **`h-rewind -u` is fixed properly** — no longer the weakest-gated destructive command; no longer needs the `HUG_FORCE` double-prompt workaround.
2. **Five commands' non-upstream path gets easier** — `h-undo`, `h-back`, etc. no longer require typing a word to do a fully-recoverable reset; `-y` now works on them. A deliberate UX relaxation justified by the risk model (nothing unrecoverable is lost). `-f` still works everywhere.

**Judgment call (accepted):** lowering the 5 non-upstream tiers danger→warn is a real behavior change for existing users/tests (piped `echo "undo" | hug h undo` tests break → become `-y`/`echo "y"`). The alternative (keep the 5 at danger, only raise `h-rewind` upstream) would leave upstream/non-upstream tiers diverging for those 5 — violating the "both paths same risk level" goal. Full consistency chosen; breakage handled by test migration (§6).

## 5. Relationship to #218 (sequencing)

#218's spec File 3 plans an `h-rewind` both-paths→danger fix via the `HUG_FORCE=true handle_upstream_operation` wrapper + a separate `prompt_confirm_danger`. **This design supersedes that part of #218** — same `h-rewind` outcome, cleaner (a `tier=danger` param instead of the wrapper hack), and fixes the other 5 commands too.

**Sequence (accepted): land #218 first, rework `h-rewind` here.** #218's core is `w get` (nearly done); it lands first. This spec then reworks #218's `h-rewind` File 3 into the tier-param form and adds the 5 other commands. Implementers: when this spec is implemented, #218's `h-rewind` changes already exist — replace the wrapper hack with `handle_upstream_operation "rewinding" danger "..."` and the non-upstream `prompt_confirm_danger` (already present from #218).

## 6. Testing & migration

**Existing piped-confirm tests (verified inventory in `tests/unit/test_head.bats`):**

| Test | Command | New tier | Migration |
|---|---|---|---|
| `:510` | rollback `echo "n"` (decline) | warn | warn honors piped `n` under no-TTY → likely no change; verify |
| `:527` | rollback `echo "rollback"` | warn | → `echo "y"` (or `-y`) |
| `:639` | back `echo "n"` (decline) | warn | no change; verify |
| `:644` | back `echo "back"` | warn | → `echo "y"` (or `-y`) |
| `:592` | rewind `echo "rewind"` | danger | → gum-mock (`HUG_TEST_GUM_INPUT="rewind"`) |
| `:1034`, `:1039` | rewind decline/confirm | danger | → gum-mock |
| `tests/CLAUDE.md:247,251` | doc examples | — | update to match new tiers |

(`h-undo`/`h-squash`/`h-cmv` had no piped-confirm tests in the audit; verify via `make test` during implementation.)

**Mechanical note:** `prompt_confirm_warn` under no-TTY falls through to `read`, so piped `y`/`n` works — the 5 lowered commands need only `echo "<word>"` → `echo "y"`. Only the danger-tier `h-rewind` needs gum-mock (its typed-word gate doesn't read plain pipes; see `hug-confirm:109-118`).

**New tests:**
1. **Consistency guard (locks the design invariant):** for each of the 6 commands, assert upstream and non-upstream resolve to the **same tier** — `h-rewind -u` and `h-rewind HEAD~1` both refuse under `-y` (both danger → exit 3); `h-undo -u` and `h-undo HEAD~1` both proceed under `-y` (both warn → exit 0). This is the regression test for "both paths same risk level"; if anyone re-hardcodes a tier, it fails.
2. **`h-rewind -u` is danger:** refuses under `-y` (exit 3), proceeds under `-f`, and **no double-prompt** (one gate only — the `HUG_FORCE` hack is gone).
3. **Each lowered command:** `-y` auto-confirms the non-upstream path (was danger-refused before).

**Exit-code contract (unchanged family rules, applied consistently):**
- danger + `-y` → exit 3 (`HUG_EX_BLOCKED`); danger + `-f` → proceed.
- warn + `-y`/`-f` → proceed (exit 0); warn + decline → exit 1.

**Help text:** update each command's `show_help` OPTIONS to document the new `-y`/`-f` semantics (danger-tier `h-rewind`: `-y` refused; the 5 warn-tier commands: `-y` auto-confirms).

## 7. Scope & out-of-scope

**In scope:** the `tier` param on `handle_upstream_operation`; per-command tier declarations consumed by both paths; `h-rewind` → danger (both paths, bespoke `read` deleted, #218 hack superseded); the 5 non-upstream tiers lowered to warn; help-text `-y`/`-f` docs for the 6; the consistency-guard test + §6 migrations.

**Out of scope → [elifarley/hug-scm#222](https://github.com/elifarley/hug-scm/issues/222):** `--dry-run` coverage; family-wide exit-code reconciliation (`check_*_clean` exits 1 vs documented exit 3); the `handle_standard_operation` "already at target" edge-case audit; whether the recoverable commands' tiers should be lowered further; the `handle_upstream_operation` `HUG_QUIET=T` path (which skips confirmation entirely — unchanged here).
