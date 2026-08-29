# Design (Phase 1): Audit `count_commits_in_range` + callers — kill the `== 0 ⟹ aligned` idiom

- **Issue:** [elifarley/hug-scm#229](https://github.com/elifarley/hug-scm/issues/229)
- **Related:** [elifarley/hug-scm#222](https://github.com/elifarley/hug-scm/issues/222) — HEAD-mover tier + recovery design; this is the primitive underneath its Critical #1 (recovery hints that silently no-op).
- **Phase:** **1 of 2.** This spec is the **core correctness fix**. **Phase 2** — direction-truthful previews + result messaging — is a separate, later spec: `2026-07-30-head-mover-direction-messaging-design.md`.
- **Date:** 2026-07-30
- **Status:** Design draft, under review (survived 5 code-roast rounds; decomposed for a minimal, high-confidence Phase 1)

> Line anchors are against local `main` @ `36d2eea` (based on `origin/main` @ `1296dbf` at last fetch). Re-resolve at implementation time.

---

## 0. Why two phases

#229's five acceptance criteria are all about **correctness**: audit the call sites, replace the unsafe alignment tests, stop the forward-target no-op, remove the `|| echo 0` swallow, document the contract. None of them ask for direction-truthful *messaging*.

The direction-awareness work (making the movers say "Moved HEAD forward" instead of "back", and fixing the "changes in 0 commit:" preview) is real polish that the core fix *exposes* — but it lives in the mover tails and adds helpers, and it is where five roast rounds concentrated their churn (a process-global, then stdout-emission, then compute-in-tail; a voided guard; a stdout-contract collision; a dropped recovery hint). Coupling that polish to the safety fix would (a) widen the blast radius of the safety-critical change to all four mover tails, and (b) re-couple the two concerns that this project's norms ("minimum code that solves the problem; touch only what you must; atomic commits") ask us to separate.

So: **Phase 1 ships the surgical safety fix with every helper contract untouched** (helpers called bare; `exit 0` guards intact; the `handle_upstream_operation` SHA captures — 8 sites across 6 callers — undisturbed). **Phase 2** adds direction-awareness as a single, isolated, independently-reviewable concern. Phase 1 deliberately leaves the forward-target preview/message cosmetically rough ("changes in 0 commit:" / "Moved HEAD back") — Phase 2 fixes both.

## 1. Problem — one shared helper idiom causes two correctness defects

`count_commits_in_range` (`git-config/lib/hug-git-commit:215`) returns a **one-directional ahead-count**:

```bash
count_commits_in_range() {
    local start="$1"
    local end="${2:-HEAD}"
    git rev-list --count "$start..$end" 2>/dev/null || echo 0
}
```

`rev-list --count start..end` counts commits reachable from `end` but not `start` — *how far `end` is ahead of `start`*. That contract is correct. The problems are downstream.

### Defect 1 — `== 0` is used as an alignment test (the real bug)

`count(start..HEAD) == 0` means "HEAD is **not ahead** of `start`," which is true in **two** distinct cases:

1. `HEAD == start` — truly aligned; a no-op is correct.
2. `HEAD` is **behind** `start` (`start` is a descendant / a forward target) — a target with real work to do.

A one-directional count cannot distinguish these. `handle_standard_operation` conflates them (`hug-git-upstream:101-141`; guard at `:107-113`):

```bash
commits_to_affected=$(count_commits_in_range "$target" HEAD)
if [ "$commits_to_affected" -eq 0 ]; then
    if [[ "$skip_when_aligned" == true ]] || ! has_uncommitted_tracked_changes; then
        info "Already at target $(git rev-parse --short "$target"). No action taken."
        exit 0      # fires for a forward target too — reset never reached
```

**Reproduced empirically** at design time: with HEAD at an ancestor commit and a descendant SHA as target, `count target..HEAD == 0` → the guard fires → "Already at target", exit 0, HEAD unmoved. The HEAD-movers `h-back`, `h-undo`, `h-rollback`, and `h-rewind` all flow through `handle_standard_operation` (the only four callers — `git-h-back:119`, `git-h-undo:138`, `git-h-rollback:128`, `git-h-rewind:114`) and all accept an arbitrary `target_arg` via `resolve_target_with_temporal`, so any of them no-ops on a forward target. This is the mechanism behind #222's Critical #1.

`git-h-restore` does **not** flow through `handle_standard_operation` — it carries its own exact-SHA-equality test (`git-h-restore:107`) and handles forward targets correctly *today*; it exists precisely as the recovery path **around** this bug. (Its header comment *references* the gate, but it never calls the helper — §5 Site 3a rewrites that stale rationale; Site 3b migrates its SHA check to `is_aligned` for DRY, not for correctness.)

**Counter-example — `git-cmv` is NOT this bug.** `git-cmv:160` also tests `count == 0 ⟹ "No commits to move"`, but for cmv that is the *correct* vacuous-operation semantic, not an alignment conflation: cmv's target is "a specific commit to move **above**" (`git-cmv:21`) and the operation "resets the current branch **back**" (`git-cmv:30`), so a descendant target has nothing above it and the request is incoherent — no-op'ing is right. Migrating cmv to `is_aligned` would convert that safe rejection into an unrequested forward hard-reset + branch switch on a self-declared "NOT RESTORABLE" command (`git-cmv:41`). The tail (`git-cmv:222-253`, quoted verbatim to close the question) is what makes a forward target dangerous — after the count guard it does:

```bash
git checkout -q "$original_branch"
git reset --hard "$target"            # :222-225 — for a forward target, RESETS THE BRANCH FORWARD
...
git checkout -q "$branch_name"        # :247 — and switches you onto the target branch
```

cmv's only real issue is Defect 2 (the swallow) plus a misleading message — fixed in §5 Site 2 by keeping the guard. See §4's reclassification.

### Defect 2 — `|| echo 0` swallows errors into a valid-looking zero

A failed `rev-list` (unborn HEAD at the root commit, invalid SHA) returns `0` — indistinguishable from "genuinely zero commits ahead." Callers then proceed as if aligned/empty. **Reproduced:** invalid `start` on an unborn HEAD → helper echoes `0`. An error masquerading as data is a latent correctness hazard across every caller.

## 2. Decision — full scope for the CORE fix (D + B + C + A)

| Option | What | In Phase 1? |
|---|---|---|
| **D** | Document the one-directional contract; forbid the alignment idiom | ✅ docstring + `lib/README.md` |
| **B** | Add `commits_ahead_behind` + the `is_aligned` alignment predicate | ✅ §3 |
| **C** | Stop swallowing `rev-list` failures — **strict propagation** | ✅ §4 |
| **A** | Migrate every unsafe alignment caller to `is_aligned` | ✅ §5 |

**Approach: two-directional primitive as the single source of truth** for the alignment test. Alignment and ahead-count are expressed by one well-named family, honoring the "one algorithm, N consumers" discipline #229 asks for.

**Error-path posture (C): strict propagation, not a `_strict` variant.** `count_commits_in_range` itself stops swallowing errors. This is the most correct option but means *every* caller — not just the unsafe ones — must handle the new non-zero-on-failure exit. The §4 audit covers all 9 call sites.

**Deferred to Phase 2:** `direction_between` (forward/backward/diverged labeler), `report_head_move` (direction-truthful result line), the mover-tail threading, and the direction-cased preview. None are required by #229's acceptance criteria.

## 3. New library primitives — `git-config/lib/hug-git-commit`

### `commits_ahead_behind <start> <end>` — the two-directional core

```bash
# Returns the ahead/behind relationship between two commits as "<behind>\t<ahead>"
# via the three-dot symmetric difference:
#   git rev-list --left-right --count <start>...<end>
#   <behind> = commits reachable from <start> but NOT <end>  (end is BEHIND start by this many)
#   <ahead>  = commits reachable from <end>  but NOT <start> (end is AHEAD of start by this many)
# Alignment (<start> == <end>) ⟺ "0\t0".
#
# NOTE: output order is git's native --left-right order (first arg's exclusive count
# FIRST) — i.e. "<behind>\t<ahead>", which does NOT match this function's NAME word order
# ("ahead_behind"). Consumers MUST parse into POSITIONAL field1/field2 (as is_aligned and
# Phase 2's direction_between do); NEVER `read ahead behind <<< "…"` — that silently swaps
# them. When BOTH counts are > 0 the refs have DIVERGED (neither is an ancestor) — a sideways
# relationship. (Shallow clones: the EQUALITY test via is_aligned is shallow-safe; raw
# ahead/behind COUNTS are not — caveat if a counting consumer appears.)
#
# STRICT: a failed rev-list (invalid ref, unborn HEAD) propagates non-zero exit and prints
# nothing — it is NEVER swallowed into a zero. Callers MUST handle failure.
commits_ahead_behind() {
  local start="${1:?commits_ahead_behind: start ref required}"
  local end="${2:?commits_ahead_behind: end ref required}"
  git rev-list --left-right --count "$start...$end"
}
```

### `is_aligned <a> <b>` — the single sanctioned alignment predicate

```bash
# True (exit 0) iff <a> and <b> resolve to the SAME existing commit.
#
# This is the ONLY sanctioned alignment test. NEVER infer alignment from a one-directional
# count_commits_in_range == 0 — that means "not ahead," which is ALSO true when one ref is
# BEHIND the other (Defect 1). For the full ahead/behind relationship use
# commits_ahead_behind(). See lib/README.md "Range counting".
#
# PRECONDITION: both <a> and <b> MUST resolve to existing commits. On an unborn repo (no
# commits) rev-list exits 128 even for HEAD...HEAD, so is_aligned returns NON-ZERO for the
# trivially-aligned case — a false NEGATIVE, never a false positive. Movers run repo/commit-
# existence guards first; and even if not, the loud-failure chain holds (commits_ahead_behind
# ALSO exits non-zero on unborn → callers propagate). Documented + tested (§7).
#
# $'0\t0' uses ANSI-C quoting so \t is a real TAB (git's field separator), NOT backslash-t.
is_aligned() {
  local a="${1:?is_aligned: first ref required}"
  local b="${2:?is_aligned: second ref required}"
  [ "$(commits_ahead_behind "$a" "$b" 2>/dev/null)" = $'0\t0' ]
}
```

**Strictness note:** the `2>/dev/null` only suppresses git's stderr chatter; a `rev-list` failure yields an empty/non-matching string → non-zero exit, never a false "aligned." Defect 2's swallow appears nowhere in either new function. The unborn-HEAD case is the one boundary where the answer is a false *negative*; documented as a precondition, not hidden.

## 4. `count_commits_in_range` becomes strict (Defect 2) + caller audit

The existing helper keeps its ahead-count contract but drops the swallow and gains a loud docstring:

```bash
# Counts how far <end> is AHEAD of <start> (commits reachable from <end> but not <start>).
#
# ONE-DIRECTIONAL ahead-count: a result of 0 means "<end> is NOT ahead of <start>" — which
# is TRUE in two distinct cases: (1) end == start (aligned), OR (2) end is BEHIND start.
# Do NOT treat 0 as "aligned." For an alignment test use is_aligned(); for the full
# ahead/behind relationship use commits_ahead_behind(). See lib/README.md "Range counting".
#
# STRICT: a failed rev-list (invalid ref, unborn HEAD) propagates non-zero exit and prints
# nothing — it is NEVER swallowed into a 0. Callers MUST handle failure.
count_commits_in_range() {
    local start="${1:?count_commits_in_range: start ref required}"
    local end="${2:-HEAD}"
    git rev-list --count "$start..$end"
}
```

### `count_commits_in_range_or_zero` — the STRICT-display twin

The two display-only call sites (`hug-git-rebase:238`, `git-h-files:202`) legitimately want a cosmetic `0` on `rev-list` failure. A named wrapper makes the function name itself the structural guardrail (vs. a copy-pasteable `|| echo 0`):

```bash
# STRICT-display twin. ONLY for display/tip text where a 0 on rev-list failure is
# cosmetically acceptable. NEVER use for a branching/alignment decision — there,
# count_commits_in_range's strict propagation MUST surface the failure.
# Grep invariant: `|| echo 0` appears NOWHERE outside this single definition.
count_commits_in_range_or_zero() {
  count_commits_in_range "$@" || echo 0
}
```

### Caller audit — all 9 call sites of `count_commits_in_range`

> Note: `git-h-restore` is **not** in this table — it does not call `count_commits_in_range`; it has its own local SHA-equality check (Defect 1, same idiom, different mechanism). It is migrated to `is_aligned` in §5 Sites 3a/3b for DRY consistency.

> **Superseded (2026-08-28), message dimension only:** the SAFE verdicts below
> for `git-log-outgoing:92` and `git-h-files:122` addressed **exit-code
> propagation** and remain valid on that dimension. Their claim that
> `== 0` is the correct "already synced" semantic is **false for message
> truthfulness**: a behind-only branch also yields `== 0` (verified by
> execution). Superseded by
> `2026-08-28-truthful-sync-state-messages-for-llu-lol-h-files-design.md` and
> elifarley/hug-scm#237/#238.

| Site | Current `== 0` semantics | Class — the REAL invariant | Required change |
|---|---|---|---|
| `hug-git-upstream:107` `handle_standard_operation` | alignment/no-op | **UNSAFE (Defect 1)** — `== 0` is not alignment | **→ `is_aligned`** (§5 Site 1) |
| `git-cmv:160` | "no commits to move" | **SAFE-but-mis-messaged** — `== 0` IS the correct vacuous-op semantic: cmv's target must be an ancestor ("specific commit to move **above**", "reset the current branch **back**"); a descendant has nothing above it, so no-op is right. The defects are the misleading "already at target" message + Defect 2 — NOT alignment. Migrating to `is_aligned` would SHIP a forward hard-reset + branch switch on a "NOT RESTORABLE" command (`git-cmv:41`). | **Keep the `== 0` guard**; strictness only (`|| exit 1`); fix the message (§5 Site 2). **Do NOT migrate to `is_aligned`.** |
| `hug-git-upstream:49` `handle_upstream_operation` | "no local commits ahead of upstream" | SAFE: `== 0` IS the correct no-op semantic for an upstream-aware op ("nothing to discard/push"), regardless of whether upstream itself is valid or ahead. Strictness change only. | `|| return 1` — on the (unexpected) rev-list failure, propagate loudly |
| `git-log-outgoing:92` | "no outgoing commits" | SAFE: `== 0` IS the correct "nothing outgoing" semantic for an upstream-aware op | `|| exit 1` — loud exit on unexpected failure |
| `git-h-files:122` | "no local-only commits" | SAFE: `== 0` IS the correct "already synced" semantic for an upstream-aware op | `|| exit 1` |
| `git-h-squash:167` | (upstream branch) count feeds the upstream path; the `== 0` *decision* for that path lives in `handle_upstream_operation` (the `hug-git-upstream:49` row), not at `:167` itself | SAFE: the upstream no-op semantic is `handle_upstream_operation`'s ("nothing to squash"), which is correct; `:167` just supplies the count | `|| exit 1` |
| `git-h-squash:176` (call; `== 0` test at `:177`) | "no commits to squash" | SAFE, and the `== 0` branch (`:177`) is **LIVE, not defensive**: `ensure_ancestor_of_head` delegates to `merge-base --is-ancestor`, which treats **equality as ancestry** (verified: exit 0 for HEAD vs HEAD), so `hug h squash <SHA-of-HEAD>` lands here. Deleting this branch would resurrect the exact "[squash] 0 commits…" orphan bug the file's own comment (`git-h-squash:161-163`) records having already suffered. | `|| exit 1` (strictness only); **do NOT remove the `== 0` branch** |
| `hug-git-rebase:238` | display only (`num_commits` in plan) | SAFE: not a decision, just a number in the rendered plan | **→ `count_commits_in_range_or_zero`** (named wrapper) |
| `git-h-files:202` | display only (tip text "in N commits since…") | SAFE: not a decision, cosmetic count in a tip line | **→ `count_commits_in_range_or_zero`** (named wrapper) |

**Why the "safe" defense matters (and why it is NOT "target validated upstream"):** a reviewer/implementer trusting a "validated upstream" defense would think the only risk is an invalid ref — obscuring the real invariant (semantic correctness of `== 0` for upstream-aware commands). The real invariant — `== 0` means "no local commits ahead of upstream," which is the correct no-op — is what an implementer must preserve. Preserve the §4 "REAL invariant" rationale **as comments at each call site** in the implementation — it is the audit's hardest-won insight and belongs at the point of use, not only here.

**Discipline:** strictness is enforced structurally, not by prose. The library function never swallows; the ONLY sanctioned cosmetic-0 escape hatch is the **named** `count_commits_in_range_or_zero` wrapper, and grep for `|| echo 0` must return exactly that one definition — nothing else. The two display sites call the wrapper rather than inlining the swallow.

**Bash pitfall — declare, then assign.** Every `|| exit 1` / `|| return 1` MUST attach to a bare assignment, not a `local` declaration: `local x=$(cmd) || exit 1` is **dead code**, because `local` (like `declare`/`export`) always exits 0 regardless of the command substitution's failure, masking the very error strictness is meant to surface (reproduced: the combined form survives with `x=''`; the split form propagates). The correct split — `local x; x=$(cmd) || exit 1`.

**The 9 call sites split into two scopes (round-5 MAJOR #3).** Bash has no block scope, so the distinction that matters is **function scope vs. script top-level**, not indentation:

- **In a function** (3 sites): use the split form `local x; x=$(…) || exit 1`. Never the combined form (dead code).
- **At script top-level** (6 sites — the indentation is from `if` blocks, NOT a function): a bare assignment `x=$(…)` propagates correctly under `set -e` (the script exits on a failing substitution). **Do NOT add `local` here — `local` outside a function is fatal** (proven: `bash -c 'set -euo pipefail; local x=1'` → "local: can only be used in a function", exit 1).

Per-site scope + action (re-resolve at implementation time):

This table is about **declaration form only** (function-scope split `local` vs script-top-level bare). The *semantic* strictification action (wrapper migration, `|| exit 1`) for each site is in the **audit table above** — "OK as-is" below means only that the *declaration form* needs no change.

| Site | Scope today | Form today | Declaration-form action (semantic action: see audit table) |
|---|---|---|---|
| `hug-git-upstream:49` | function (`handle_upstream_operation`) | split `local` | OK as-is (`|| return 1` per audit table) |
| `hug-git-upstream:107` | function (`handle_standard_operation`) | split `local` | OK as-is (Site 1 rewrites this; `is_aligned` per audit table) |
| `hug-git-rebase:237-238` | function (`rb_build_plan`) | split `local` | OK as-is (wrapper migration per audit table) |
| `git-h-files:122` | **script top-level** (in `if $upstream` block) | bare assignment | **leave bare** (propagates via `set -e`); do NOT add `local` (fatal). Optionally add explicit `|| exit 1` for clarity |
| `git-h-files:202` | **script top-level** | bare assignment | leave bare, do NOT add `local` (wrapper per audit table) |
| `git-log-outgoing:92` | **script top-level** | bare assignment | leave bare (`|| exit 1` per audit table) |
| `git-h-squash:167` | **script top-level** | bare assignment | leave bare, do NOT add `local` (`|| exit 1` per audit table) |
| `git-h-squash:176` | **script top-level** | bare assignment | leave bare (`|| exit 1` per audit table) |
| `git-cmv:160` | **script top-level** | bare assignment | leave bare (keep guard + message fix, Site 2) |

## 5. Fixing the affected call sites (Defect 1)

> Sites 1 and 3b migrate the genuine alignment tests to `is_aligned`. Site 2 (`git-cmv`) is the deliberate exception — its `== 0` is correct, so it keeps the guard and only gets the strictness + message fix. Site 3a is a docs-drift cleanup forced by Site 1.

### Site 1 — `handle_standard_operation` (`hug-git-upstream:101-141`)

The minimal core fix: replace the count-based alignment guard with `is_aligned`, and make the preview's count strict. **The helper emits nothing on stdout and keeps its `exit 0` aligned-target early-exit — it is still called as a bare statement (not captured), so `exit 0` terminates the whole mover as today.** Direction-awareness (the "changes in 0 commit:" preview, the result message) is **Phase 2**; Phase 1 leaves the existing preview block unchanged.

```bash
handle_standard_operation() {
    local action_name="$1"
    local target="$2"
    local skip_when_aligned="${3:-true}"

    # Defect-1 fix: alignment is an EXACT SHA relationship, never a one-directional
    # count == 0. A forward (descendant) target was silently no-op'ing here before.
    # Called BARE by the movers, so `exit 0` terminates the whole mover. (Capturing this
    # helper via $(…) would make `exit 0` quit only the subshell and the mover would
    # proceed to move HEAD right under the "Already at target" message — verified bug.)
    if is_aligned "$target" HEAD; then
        if [[ "$skip_when_aligned" == true ]] || ! has_uncommitted_tracked_changes; then
            info "Already at target $(git rev-parse --short "$target"). No action taken."
            exit 0
        fi
        if [[ ${HUG_QUIET:-} != T ]]; then
            info "No commits to $action_name; local tracked changes will be reset."
        fi
        return 0
    fi

    # NOT aligned. Count ahead-commits STRICTLY for the preview (was: swallow via || echo 0).
    # For a forward target this count is 0 (HEAD is behind, not ahead); the preview then
    # reads "changes in 0 commit:" above the diff stat — cosmetically rough, fixed in Phase 2.
    # The operation PROCEEDS either way, which is the fix: resetting onto a descendant moves
    # HEAD forward instead of no-op'ing.
    local commits_to_affected
    commits_to_affected=$(count_commits_in_range "$target" HEAD) || return 1

    # ...existing preview block unchanged in Phase 1 (commit list, diff --stat, pluralization
    #     on $commits_to_affected / "$target..HEAD"); Phase 2 makes it direction-aware...
}
```

**Forward-target behavior after Phase 1 (the fix, enumerated for all four movers).** On a forward (descendant) target, `is_aligned` is false, so the guard no longer fires; the mover proceeds and its reset moves HEAD **forward** instead of printing "Already at target". Confirmation is **unchanged** — see the rule below.

| Caller | Pre-fix (forward target) | Post-fix Phase 1 (forward target, clean index) |
|---|---|---|
| `git-h-back` | "Already at target", exit 0 | clean → skips confirmation (as today), soft-reset **forward** (result line still says "back" — Phase 2 fixes the wording) |
| `git-h-undo` | "Already at target", exit 0 | clean → skips confirmation (as today), mixed-reset **forward** (wording → Phase 2) |
| `git-h-rollback` | "Already at target", exit 0 | warn prompt (as today), keep-reset forward ¹ (wording → Phase 2) |
| `git-h-rewind` | "Already at target", exit 0 | **warn** prompt on a clean tree (state-dependent tier — see rule), hard-reset forward (wording → Phase 2) |

¹ `git reset --keep` **aborts** ("Entry … not uptodate") if a file in the reset range has uncommitted edits — a pre-existing `--keep` condition, not design-caused; the forward path can hit it. Assumes a clean-in-range tree.

**Confirmation is direction-independent — do NOT add a forward-move prompt.** This codebase's prompts are *safety* gates (danger ⟺ can destroy unrecoverable uncommitted work; warn ⟺ destructive-but-recoverable), not "did you mean that?" UX nudges. A forward move's safety profile is identical to a backward move's: the destructiveness of `reset --hard` (`h-rewind`) comes from discarding **uncommitted** work — orthogonal to direction; on a clean tree a forward `--hard` just moves HEAD to an already-committed descendant (`HEAD@{1}`-recoverable). This is the **merged #231 (`head-movers-tier-unify`) model**: the tier is computed from tracked-dirty *state*, not the command — `git-h-rewind:89-94` sets `tier=warn` and escalates to `danger` only `if has_uncommitted_tracked_changes`; `h-back`/`h-undo`/`h-rollback` are fixed warn (`h-back`/`h-undo` additionally skip the prompt when clean); `cmv` is fixed danger. Therefore Phase 1 changes **no** confirmation behavior; it only stops the no-op. (Phase 2 makes the *wording* direction-truthful; it too adds no prompt.)

### Site 2 — `git-cmv` (`:156-164`) — keep the guard, fix strictness + message (NOT `is_aligned`)

Per §4's reclassification, cmv's `== 0` is the **correct** vacuous-op semantic — a descendant target has nothing to move and the request is incoherent. The fix is strictness + a truthful message, **not** an `is_aligned` migration:

```bash
target=$(git rev-parse "$target")

# cmv target must be an ANCESTOR ("commit to move above", "reset branch back").
# == 0 ⟹ vacuous operation (correct no-op). Strict: a bad ref now fails loudly instead
# of masquerading as "0 commits". The OLD message lied ("already at target") for a forward
# target. NOTE: == 0 fires in TWO sub-cases — target == HEAD (aligned) OR target is a
# descendant — so branch on is_aligned (Phase 1) for a message that is truthful in BOTH
# (a single "is not an ancestor of HEAD" would LIE when aligned, since a commit is its own
# ancestor — equality-as-ancestry, §4):
commits_to_relocate=$(count_commits_in_range "$target" HEAD) || exit 1
if [ "$commits_to_relocate" -eq 0 ]; then
  if is_aligned "$target" HEAD; then
    info "No commits to move (already at $(git rev-parse --short "$target"))."
  else
    info "No commits to move (target $(git rev-parse --short "$target") is a descendant of HEAD; cmv needs an ancestor target)."
  fi
  exit 0
fi
```

(Both sub-cases are now truthful: aligned → "already at"; descendant → "is a descendant of HEAD; cmv needs an ancestor target." If forward-reset semantics for cmv are ever wanted, that is a separate feature needing its own help-text change + confirmation story — not a drive-by in a correctness audit.)

### Site 3a — `git-h-restore` stale comment blocks MUST be rewritten

`git-h-restore`'s **entire stated reason for existing** is built on the bug Site 1 fixes. Three comment blocks are affected:

- **Header, `git-h-restore:16-20`** — "WHY this exists: re-invoking a mover … to recover forward no-ops **via handle_standard_operation's count==0 gate** (the aligned-target short-circuit in hug-git-upstream:109-112)."
- **Header, `git-h-restore:27-28`** — "safety additions (bare-numeric guard, --rewind+dirty danger escalation, per-tier prompt) **arrive in Task 8**." These are ALREADY in the file (`:85-86`, `:117-120`) — stale regardless of this audit.
- **Inline, `git-h-restore:104-106`** — "The defining feature: no-op ONLY on exact SHA equality … This lets recovery move FORWARD to a descendant (re-invoking the mover **no-ops there via handle_standard_operation's count==0 bailout**)."

`git-h-restore` is **not** the only file citing the swallow mechanism (an earlier draft claimed it was — **false**, verified by grep). The root-commit **danger-tier rationale comments** in two movers cite the very `|| echo 0` behavior Defect-2 strictification deletes, and must be updated in the same PR:

- **`git-h-back:105-108`** — "Root-commit path stays DANGER (spec §6): recovery at root is a guaranteed **no-op (unborn HEAD ⇒ rev-list fails ⇒ count 0)**, so there is no complete recovery to license a warn tier."
- **`git-h-undo:123-126`** — "Root-commit path stays DANGER … at root, recovery is a guaranteed **no-op (unborn HEAD)** …"

"rev-list fails ⇒ count 0" *is* the swallow. **Post-Phase-1 the mechanism changes:** re-invoking a mover to recover at root hits `is_aligned` non-zero (unborn, exit 128) → strict count propagates non-zero → the mover **exits ≠ 0 — a loud failure, not a silent no-op**. The danger-tier **decision survives** (a loud failure is still "no complete recovery," so the tier stands), but the comments' stated mechanism is stale and must be reworded to "recovery at root is a guaranteed **loud failure** (unborn HEAD ⇒ strict rev-list propagates non-zero ⇒ mover exits ≠ 0) — still no complete recovery, so the danger tier stands." (This is a behavior change — root recovery goes silent→loud — but an improvement; the root-recovery *fix* itself remains deferred to #222 §10, §9.) (Optional borderline touch-up: `hug-git-commit:196-197` "Let handle_standard_operation check if there are commits in range" — still literally true post-fix, but the tolerance it implies is gone.)

After Site 1, the movers **no longer** have the forward no-op — `hug h back <descendant>` moves HEAD forward itself. The `git-h-restore` comments become factually wrong. **The whole header block (:14-28) plus the inline comment (:104-106) must be rewritten** in the same PR to state `git-h-restore`'s now-actual purpose: an op-named-flag selector for the reset MODE, gated on exact SHA equality — independent of (and now redundant with) the movers' alignment gate. Suggested rewrite of the header WHY block:

```text
# WHY this exists: an explicit recovery primitive that resets HEAD to a prior
# commit as the inverse of a HEAD-mover. Its no-op test is EXACT SHA equality
# (via is_aligned), the only test that distinguishes "already there" from
# "move to a different commit." The movers now share that same is_aligned gate
# (hug-git-upstream); this command remains the dedicated, op-named inverse.
```

### Site 3b — `git-h-restore:107` adopts `is_aligned`

```bash
# Was: if [ "$target" = "$(git rev-parse HEAD)" ]; then
if is_aligned "$target" HEAD; then
  info "Already at $(git rev-parse --short "$target"). Nothing to restore."
  ...
```

After Sites 3a + 3b, `is_aligned` is the **only** alignment idiom in the repo and `git-h-restore` carries no stale rationale.

## 6. Documentation (option D)

- **`git-config/lib/hug-git-commit` docstrings** — `count_commits_in_range`, `commits_ahead_behind`, `is_aligned` each carry the contract + the alignment-idiom prohibition (shown in §3/§4).
- **`git-config/lib/README.md`** — add a "Range counting" subsection (near the existing `count_commits_in_range` example at `:414`) stating:
  - `count_commits_in_range` is a ONE-DIRECTIONAL ahead-count; `== 0` means "not ahead," NOT "aligned."
  - For alignment use `is_aligned`; for the ahead/behind relationship use `commits_ahead_behind`.
  - Both new functions + the now-strict `count_commits_in_range` propagate `rev-list` failures (Defect 2).
- **`git-config/lib/README.md` — fix pre-existing drift + cross-reference `is_aligned`**: `:98` and `:133` both describe `handle_standard_operation`'s aligned-target gating, but they CONTRADICT each other — `:98` attributes the predicate to `has_untracked_or_pending_changes`, while the code (`hug-git-upstream:110`) and `:133` both use `has_uncommitted_tracked_changes`. `:98` is stale; correct it to match `:133`/the code. Cross-reference `is_aligned` as the sanctioned alignment test at both `:98` and `:133`.
- **`git-config/lib/README.md:425-435`** — the `handle_standard_operation` usage example must show it called **bare** (its `exit 0` aligned-guard depends on NOT being captured). The direction-messaging helper examples (`direction_between`/`report_head_move`) are added in **Phase 2's** docs pass.

## 7. Testing strategy

Per `git-config/lib/CLAUDE.md` ("elegant tests" for lib changes) and the project's BATS conventions.

**`tests/lib/test_hug-git-commit.bats`** (EXTEND — **hyphens**; the existing `count_commits_in_range` tests at `:33-50` stay and survive strictification. Do NOT create an underscore-named twin):
- `commits_ahead_behind`: ancestor pair → `"0\t<N>"`; descendant pair → `"<N>\t0"`; aligned → `"0\t0"`; diverged pair → `"<M>\t<N>"` (both >0); invalid ref → non-zero exit, empty stdout.
- `is_aligned`: same SHA → exit 0; ancestor → non-zero; descendant → non-zero; invalid ref → non-zero (never false-aligned); **unborn repo, `is_aligned HEAD HEAD` → non-zero (false NEGATIVE, documented precondition)**.
- `count_commits_in_range` strict: invalid start → non-zero exit, empty stdout (Defect-2 regression); missing `$1` → fails fast via `${1:?}`.
- `count_commits_in_range_or_zero`: invalid start → echoes `0`, exit 0 (the named cosmetic twin).

**`tests/lib/test_hug-upstream.bats`** (extend existing aligned-target tests):
- **Defect-1 regression (the headline test):** descendant/forward target on a clean tree → `handle_standard_operation` does NOT print "Already at target", does NOT `exit 0` from the guard, and returns 0 *past* the alignment check (so the caller proceeds to its reset). The helper is read-only (previews/confirms, then returns; the caller performs the reset), so the test asserts the guard is *not* taken — not that HEAD moves inside the helper.
- **Aligned-guard-not-voided (helper called bare):** target == HEAD → prints "Already at target. No action taken.", exits 0, and does NOT proceed. Pins that `handle_standard_operation` is called as a bare statement; a regression to `direction=$(handle_standard_operation …)` would fail this (the capture form lets the mover proceed under the no-op message — verified bug).
- Keep existing aligned + untracked-only / tracked-dirty tests (they now exercise `is_aligned`).

**`tests/unit/test_commit.bats`** (EXTEND the "# hug cmv expectations" section, `:336+` — there is **no** `test_h_cmv.bats`):
- forward (descendant) target → clean no-op with message "No commits to move (target … is a descendant of HEAD; cmv needs an ancestor target)"; **assert the branch did NOT move forward** (pins that we did not ship the forward-hard-reset regression).
- aligned target (`hug cmv HEAD <branch>` / `<SHA-of-HEAD>`) → clean no-op with message "No commits to move (already at …)" — NOT "is a descendant" (pins the `is_aligned` branch; the old single message lied here).
- ancestor target → unchanged behavior (commits move).

**`tests/unit/test_head.bats`** (extend, or whichever file covers h-squash): `hug h squash <SHA-of-HEAD>` → "No commits to squash", exit 0, **no commit created** — pins the LIVE `== 0` branch so nobody deletes it as "dead defense" and resurrects the 0-commit orphan bug.

**`tests/unit/test_h_restore.bats`** (extend): aligned → no-op (unchanged via `is_aligned`); invalid SHA → error, not silent.

**Forward-mover smoke tests (the fix):**
- `hug h back <descendant-SHA> -y` on a scratch repo moves HEAD rather than printing "Already at target" (the headline acceptance criterion; reproduced as a bug at design time, the test encodes the inverse).
- `hug h rewind <descendant-SHA>` on a dirty tracked tree still fires the danger-tier confirmation and moves HEAD forward (`skip_when_aligned=false` + dirty-tree + forward-target path).
- backward target (the common case) on each mover → confirmation behavior **unchanged** (regression guard).

**Per-site strict-propagation test (PRIMARY Defect-2 enforcement).** Exercise a `rev-list` failure (invalid start ref) at each call site and assert the site-specific contract — **split by class** (a blanket "all 9 exit non-zero" would FAIL against the correct implementation, since the 2 display sites legitimately return 0):
- **7 strict sites** (`hug-git-upstream:49/:107`, `git-log-outgoing:92`, `git-h-files:122`, `git-h-squash:167/:176`, `git-cmv:160`): the script/function exits **non-zero** — NOT "0 commits"/"Already at target".
- **2 display sites** (`hug-git-rebase:238`, `git-h-files:202`, via `count_commits_in_range_or_zero`): exit **0** with a cosmetic `0` in the rendered plan/tip (the wrapper's contract — intentional; do NOT strip the wrapper to make a strict test pass).

This runtime test is what §8 credits — no line-based grep can serve as a complete caller-invariant (a correct two-line `local x; x=$(…)` split puts the call on a line a grep can't classify; a round-4 caller-invariant grep returned 12 false positives on compliant code — verified).

**`|| echo 0` canary (secondary tripwire):** after implementation, `grep -rn '|| echo 0' git-config/` returns exactly one line — the body of `count_commits_in_range_or_zero`. A canary, not a proof (it misses `||echo 0`, `|| printf '0\n'`, multi-line, and the structural `local`-masking form); the per-site test above is the real enforcement.

**Edge-case behavior changes (enumerated, not derived):**
- **Root-commit recovery (unborn HEAD):** pre-fix, re-invoking a mover to recover at root swallowed the rev-list failure to `0` → silent "Already at target" no-op. Post-fix, `is_aligned` returns non-zero (unborn, exit 128) → strict count propagates → the mover **exits non-zero (loud failure)**. The danger tier for the root path stands (a loud failure is still "no complete recovery"); the root-recovery *fix* itself stays deferred to #222 §10 (§9). Pin: a mover invoked to recover at root fails loudly, not silently.
- **Garbage target leaking through `resolve_target_with_temporal`** (`hug-git-commit:198`'s `|| echo "$target_ref"` passes literals through): pre-fix → swallow → silent "Already at target ." exit 0; post-fix → `is_aligned` false + strict count's `fatal: ambiguous argument` → mover exits 1. A bonus loud-failure fix the strictification delivers; pin: an unresolvable target exits non-zero, not silent.

**Sanitize gate:** `make sanitize` after implementation (per `makefile-rules.md`); shellcheck must pass on all touched bash.

## 8. Acceptance criteria → where addressed

- [x] All **9** call sites audited; each `== 0` use classified safe / unsafe with the REAL invariant stated — §4 table. (1 unsafe → `is_aligned`; 5 safe-ahead-count → strictness; 1 safe-but-mis-messaged `git-cmv` → keep guard + message fix; 2 display → named wrapper. `git-h-restore` is a non-caller handled in §5 Sites 3a/3b.)
- [x] Every unsafe **alignment** test replaced with the two-directional primitive (`is_aligned`) — §5 (Site 1 `handle_standard_operation`, Site 3b `git-h-restore`). `git-cmv` deliberately **NOT** migrated (its `== 0` is the correct vacuous-op semantic; migration would ship a forward hard-reset on a "NOT RESTORABLE" command) — §1 counter-example + §4 + §5 Site 2.
- [x] `handle_standard_operation` no longer no-ops on a forward (descendant) target — regression test in §7; forward-target path enumerated for all four movers (§5 table); helper called **bare** so its `exit 0` aligned-guard is intact.
- [x] `git-h-squash:177`'s `== 0` branch preserved (LIVE via `merge-base` equality-as-ancestry, not defensive) + regression test — §4 + §7.
- [x] The `|| echo 0` swallow is removed (strict propagation); the only sanctioned cosmetic-0 escape is the NAMED `count_commits_in_range_or_zero` wrapper. Enforcement is the **per-site strict-propagation test** (§7), NOT a grep (no line-grep is complete); the `|| echo 0` grep is a secondary canary.
- [x] Docstring + `lib/README.md` state the one-directional contract and forbid the alignment idiom — §6.
- [x] Stale rationale comments citing the deleted swallow rewritten so the spec doesn't move the docs-drift — §5 Site 3a: `git-h-restore` whole header (:14-28 incl. "arrive in Task 8") + inline (:104-106), **plus** the root-commit danger-tier comments at `git-h-back:105-108` and `git-h-undo:123-126` (reworded "no-op" → "loud failure"; the danger tier stands). Root-recovery behavior change (silent no-op → loud failure) enumerated in §7.
- [x] `is_aligned`'s unborn-HEAD precondition documented + tested — §3 + §7.

## 9. Out of scope (→ Phase 2 or elsewhere)

- **Direction-truthful previews + result messaging** — the "changes in 0 commit:" preview and the "Moved HEAD back" (for a forward move) result line. → **Phase 2** (`2026-07-30-head-mover-direction-messaging-design.md`): `direction_between` + `report_head_move` + mover-tail threading. Phase 1 leaves these cosmetically rough on forward targets.
- Root-commit recovery paths noted in #222 §10 (separate defect class; tracked there).
- Any change to the *ahead-count callers'* semantics — they keep meaning "is `end` ahead of `start`?"; only their failure handling changes (§4).
- Mercurial (`hg-config/`) — the issue scopes to Git. No port required.

## 10. Review history

This spec survived **five code-roast rounds**. The first three plus two user corrections hardened the core (the two-defect framing, the two-directional primitive, the cmv non-migration, the h-squash liveness, the per-state confirmation model). Rounds 3–5 also explored direction-truthful **messaging**, which churned (a process-global → stdout-emission → compute-in-tail; a voided guard; a stdout-contract collision; a dropped recovery hint) — round 5 showed four of its six MAJORs were regressions the messaging machinery itself introduced. **That is the motivation for the decomposition:** the messaging is now carved out to **Phase 2** so the safety-critical core (this spec) ships minimal and high-confidence, and the shell-runtime-subtle messaging gets its own focused review. Key verified facts preserved from the rounds:

- **Defect 1 + 2** reproduced empirically (forward-target no-op; `|| echo 0` swallow on unborn/invalid).
- **`merge-base --is-ancestor HEAD HEAD` → exit 0** (equality-as-ancestry) ⇒ `git-h-squash:177`'s `== 0` branch is LIVE; `rev-list HEAD..HEAD` → 0.
- **Unborn-HEAD `rev-list HEAD...HEAD` → exit 128** ⇒ `is_aligned` false-negative (never false-positive); documented precondition.
- **`exit 0` inside `$(…)` exits only the subshell** ⇒ `handle_standard_operation` must be called bare for its aligned-guard to terminate the mover (the capture form voids it — verified bug; pinned by a §7 test).
- **`local` at script top-level is fatal** ⇒ the 6 top-level call sites stay bare; only the 3 in-function sites use split `local`.
- **No line-grep is a complete caller-invariant** ⇒ the per-site strict-propagation *test* is the enforcement; `|| echo 0` is a canary.
- **`git-cmv` tail (`:222-253`)** hard-resets onto the target + switches branch ⇒ forward-target migration would ship harm; cmv keeps its guard.
- **#231 per-state tier model** (`h-rewind` warn-clean/danger-dirty; `h-back/h-undo/h-rollback` warn; `cmv` danger) ⇒ confirmation is direction-independent.

**Round 6 — 2026-07-30 (code-roast of the LEAN Phase 1).** 0 CRITICAL; the roast confirmed the core design "survived every empirical attack" (it called the cmv counter-example "the spec's crown jewel" and the `local`-pitfall section "institutional knowledge"). Three MAJORs, all spec-internal contradictions, fixed:
- **§7 ↔ §4 contradiction** — the per-site enforcement test said "all 9 sites exit non-zero," but the 2 display sites (via the wrapper) correctly exit 0. Split the prescription: 7 strict (non-zero) / 2 display (exit 0 + cosmetic 0).
- **Site 2 message half-truth** — `count == 0` fires when target == HEAD *or* a descendant; "is not an ancestor of HEAD" lies when aligned (equality-as-ancestry). Branched the message on `is_aligned` (aligned → "already at"; descendant → "is a descendant of HEAD").
- **Site 3a false "only file" claim** — `git-h-back:105-108` and `git-h-undo:123-126` ALSO cite the deleted swallow (root-commit danger-tier comments). Extended the comment rewrite to them (reword "no-op" → "loud failure"; tier stands) and enumerated the root-recovery silent→loud behavior change (§7).

Minors also fixed: the two §4 tables disambiguated (scope table = declaration form only, cross-referencing the audit table); Site 1's `&&` one-liner reverted to the original `if` (avoids a `set -e` subtlety); the `git-h-squash:167` audit column clarified (its `== 0` decision lives in `handle_upstream_operation`); the `commits_ahead_behind` name-vs-output-order guard strengthened (consumers use positional `field1`/`field2`); and the `handle_upstream_operation` capture count corrected to 6 callers / 8 sites (in the Phase 2 spec). The roast also noted a **bonus** the strictification delivers: a garbage target leaking through `resolve_target_with_temporal` (`hug-git-commit:198`) now fails loudly instead of silently no-op'ing (§7).
