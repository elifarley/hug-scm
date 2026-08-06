# Head-mover correctness batch — design

Date: 2026-08-06
Status: Approved (brainstorming, design sections §1–§5 validated; spec-roast findings folded 2026-08-06)
Tracks: elifarley/hug-scm#234, elifarley/hug-scm#237, elifarley/hug-scm#235, elifarley/hug-scm#236, elifarley/hug-scm#239
Parent context: elifarley/hug-scm#222 (HEAD-mover family audit), elifarley/hug-scm#233 (count_commits_in_range audit, merged)

## Context

The #222 family audit and the #233 count-range audit left a residue of follow-up issues.
They decompose into three independent sub-projects; this spec is **batch B, the safety +
correctness batch**. Batches A (family overhaul: elifarley/hug-scm#240 direction-truthful
messaging + elifarley/hug-scm#230 `h back` naming) and C (#222 concerns 3/4/5 audit) are
separate specs.

Of #222's original six concerns, three are already resolved (1+2 by elifarley/hug-scm#231,
6 by #233). This batch closes the remaining correctness residue.

## Goals

1. **#234** — an explicit garbage or forward target in `h-back`/`h-undo`/`h-rollback`
   fails LOUDLY instead of silently triggering root-recovery (a destructive operation).
2. **#237** — the `-u` upstream path stops claiming "Already synced" when HEAD is
   actually behind upstream.
3. **#235/#236/#239** — pin the load-bearing `|| return 1` guard with a test; correct two
   misleading doc wordings.

## Non-goals

See §5 Scope exclusions.

## §1 Backward-target validation (#234)

### Root cause

`git-h-back:96`, `git-h-undo:106`, `git-h-rollback:101` share one shape:

```bash
if ! git rev-parse --verify --quiet "$target" > /dev/null 2>&1 && is_at_root_commit; then
    # root-recovery path → reset_root_commit <mode>
```

Two distinct conditions both satisfy `! rev-parse`:

- the LEGITIMATE one: no explicit target, default `HEAD~1` does not exist because HEAD is
  at the root commit;
- a GARBAGE explicit target (`hug h back notaref`), at ANY position, and at root it is
  indistinguishable from the legitimate case.

`resolve_target_with_temporal` deliberately swallows explicit-target resolution failures
(its fallback returns the raw ref for `handle_standard_operation` to reject later) — but
at root the root-recovery branch intercepts FIRST. Result: `hug h back garbage` at the
root commit performs `reset_root_commit` — the most destructive thing the command can do
— on nonsense input. Temporal and `-u` targets are already validated; the gap is
specifically the explicit positional argument.

### The fix

New shared helper in `git-config/lib/hug-git-upstream` (home of the other operation
handlers):

```
validate_backward_target <target> <op>
```

Contract — kept deliberately ISOMORPHIC to `commit_offset`'s documented outcome table
(hug-git-commit), so the two can never drift. All FOUR outcomes must be mapped; the naive
`offset=$(commit_offset …) || return 1` form conflates exit 2 with exit 3 and is FORBIDDEN
(the library's own comment warns about exactly this conflation):

| Input (`commit_offset "$target" HEAD`) | Result |
|---|---|
| unresolvable target (exit 3, empty stdout) | `error "'<target>' is not a valid commit"` + non-zero |
| DIVERGED target (exit 2, empty stdout) | silent pass — a valid SIDEWAYS move; preserves today's behavior (see decision below) |
| target AHEAD of HEAD (exit 0, offset < 0) | `error "hug h <op> moves HEAD back, but '<target>' is ahead of HEAD by N commit(s) (use 'hug h restore' to move forward)"` + non-zero |
| target is HEAD or an ancestor (exit 0, offset >= 0) | silent pass, exit 0 |

**Diverged policy — silent pass.** `hug h undo main` is a documented everyday invocation
(docs/commands/head.md) and, on a branch whose `main` has advanced, `main` is diverged
from HEAD. Today the movers preview and reset to such a target (a sideways move); this
batch must not change that (§5 "no behavior change"). Whether sideways moves through
backward-named commands deserve their own semantics is exactly #230's question
(sub-project A) — it is NOT decided here.

**Mandated implementation shape** — two non-negotiable idioms:

1. **Dispatch on the exit code, never on the offset alone** (on exit 2 stdout is EMPTY,
   so any `[ "$offset" … ]` test evaluates the empty string).
2. **Capture via `|| rc=$?` — the assignment MUST sit left of `||`.** A bare
   `offset=$(commit_offset …)` followed by `rc=$?` is DEAD CODE under the movers'
   `set -euo pipefail`: the assignment statement's exit status IS the substitution's, so
   errexit aborts the mover at the assignment for exactly exit 2 and exit 3 — the two
   codes the dispatch exists to distinguish (empirically probed: silent exit, dispatch
   never reached; the `|| rc=$?` form reaches it). Same failure class as the
   `local x=$(…)` masking pitfall: a capture that hides the captured command's failure.

```bash
validate_backward_target() {
    local target="$1" op="$2" user_input="${3:-$1}" offset rc=0
    offset=$(commit_offset "$target" HEAD) || rc=$?
    case $rc in
      3) error "'$user_input' is not a valid commit" ;;
      2) return 0 ;;   # diverged: valid sideways move — today's behavior, NOT an error
      0) ;;
      *) return 1 ;;   # unreachable; loud by construction
    esac
    if [ "$offset" -lt 0 ]; then
        error "hug h $op moves HEAD back, but '$user_input' is ahead of HEAD by ${offset#-} commit(s) (use 'hug h restore' to move forward)"
    fi
}
```

(The `error` arms carry no `return 1` — `error` hard-exits the shell (hug-output), so a
return after it is unreachable. `user_input` defaults to `$1`; wiring passes the user's
LITERAL argument so `hug h back 1` at root reports `'1' is not a valid commit`, not the
internally-resolved `HEAD~1`.)

**Docstring sync:** `commit_offset`'s Usage docstring in `hug-git-commit` teaches this
capture idiom and shipped the broken `; rc=$?` form (this spec's first draft transcribed
it). This batch fixes that docstring to the `|| rc=$?` form above — spec and library doc
stay isomorphic, so neither can re-infect the other.

**Test-layer warning:** BATS `run` DISABLES errexit, so helper-layer tests pass green on
a broken capture idiom (probed). The mover-layer e2e — a real `hug h …` script under
`set -euo pipefail` — is the ONLY layer that can catch it; §4 therefore mandates a
mover-layer assertion that the diverged shape PROCEEDS rather than exiting silently.

**Wiring (identical seam in all three movers):** insert the call right after
`resolve_target_with_temporal` in the NON-upstream path, before the root-path branch,
**conditioned on a non-empty positional arg**:

```bash
[[ -n "$target_arg" ]] && validate_backward_target "$target" "back" "$target_arg"
```

EXPLICIT targets only. The DEFAULT `HEAD~1` is skipped by design: at the root commit it
legitimately does not resolve — that unresolved default is precisely the trigger for the
root-recovery branch, so validating it would break the legitimate no-arg case. Temporal
(`-t`) targets are out of scope of the gate too: `resolve_temporal_to_commit` resolves
exclusively within HEAD's own history (`git log … HEAD --reverse`), so a temporal target
is ALWAYS an ancestor of HEAD — a valid backward move by construction — and a mistyped
time spec is not the "typed the wrong ref" mistake this gate exists for.

**Defense in depth:** the root-path guard additionally requires an empty positional arg:

```bash
if [[ -z "$target_arg" ]] && ! git rev-parse --verify --quiet "$target" … && is_at_root_commit; then
```

The validator already rejects unresolvable EXPLICIT targets before this line; the
`-z target_arg` clause makes root-recovery structurally unreachable for any explicit
target, so a future refactor of the validator cannot re-open the hole.

### Behavior matrix

| Input | at root | not at root |
|---|---|---|
| `h back garbage` | error: not a valid commit | error: not a valid commit |
| `h back <descendant>` | error: is ahead of HEAD | error: is ahead of HEAD |
| `h back <diverged-ref>` | silent pass — sideways move (reachable: orphan branches and fetched foreign roots DO diverge from the root; only single-root histories cannot) | silent pass — sideways move, unchanged behavior |
| `h back N` (explicit numeric, e.g. `1`) | error: `'N' is not a valid commit` (`HEAD~N` does not exist at root) — **behavior change**: today this triggers root-recovery, but an explicit target is a user assertion, so loud failure is #234's policy | normal move back N (unchanged) |
| `h back <ancestor>` | normal back move | normal back move (unchanged) |
| `h back` (no arg) | root-recovery, danger tier (unchanged) | default move back 1 (unchanged) |

Note the forward-explicit case becomes a loud error EVEN NOT-AT-ROOT. This is deliberate
and strictly safer than the post-#233 status quo (which silently allowed forward moves
through a backward-named command); restore is the sanctioned forward mover.

### Decisions

- **`-u` path is EXEMPT.** Syncing to upstream legitimately discards local-only commits;
  "forward relative to HEAD" is the point of `-u`, not an error.
- **Error exit code: plain `error` + exit 1.** No new code invented — exit-code taxonomy
  is #222 concern 4's job (batch C).
- **Danger tier of root-recovery is preserved** (per #233's §6 rationale: recovery at
  root is a guaranteed loud failure, so no complete recovery licenses a warn tier).

## §2 Truthful sync-state messaging (#237)

### Defect

`handle_upstream_operation` (hug-git-upstream:51-54):

```bash
if [ "$local_commits" -eq 0 ]; then
    info "Already synced to upstream (…)"; exit 0
```

`count_commits_in_range(target, HEAD) == 0` means "HEAD is not AHEAD of upstream" — also
true when HEAD is BEHIND. This is the exact `count==0 ⟹ aligned` conflation #233 killed
in the guards, surviving in a display message.

Key property: **diverged cannot reach this branch** (diverged ⇒ ahead > 0 ⇒ the preview
path). The `== 0` branch contains exactly two states — aligned or behind — which is
precisely what `commit_offset` distinguishes.

### Fix (inside the existing `== 0` branch)

```bash
if [ "$local_commits" -eq 0 ]; then
    local offset
    offset=$(commit_offset "$target" HEAD) || return 1   # 0 aligned, -N behind; diverged unreachable here (diverged ⇒ ahead > 0)
    local target_short
    target_short=$(git rev-parse --short "$target")
    if [ "$offset" -eq 0 ]; then
        info "Already synced to upstream ($target_short)."
        exit 0
    fi
    local upstream_branch
    upstream_branch=$(git for-each-ref --format='%(upstream:short)' "$(git symbolic-ref HEAD)" 2>/dev/null || echo "upstream")
    info "Nothing to move: HEAD is ${offset#-} commit(s) behind upstream ($upstream_branch). Pull or rebase to catch up."
    exit 0
fi
```

`set -u` safety: every variable used above is computed INSIDE the branch (declaration and
assignment on separate lines, per the `local x=$(…)` masking pitfall). Neither
`target_short` nor `upstream_branch` exists earlier in `handle_upstream_operation`, so
they must not be referenced before this computation. The branch label mirrors the preview
block's computation (`git symbolic-ref HEAD` guarded by `2>/dev/null || echo "upstream"`)
for PARITY — the fallback cannot actually fire inside this helper, because
`get_upstream_commit` already resolved `@{u}`, which requires an attached HEAD.

Decisions:

- **Behind is informational + exit 0**, not a warning/non-zero: "you asked to move local
  commits upstream and there are none" is still a successful no-op — the message just has
  to be honest.
- **Lives in the shared helper**, so all six `-u` callers get it at once.
- **Bonus:** first PRODUCTION caller of `commit_offset`, advancing #238 (its eventual
  full home is Phase-2 direction messaging).

## §3 Hygiene trio

**#235 — pin `handle_upstream_operation`'s `|| return 1` — the count guard at
hug-git-upstream:49 specifically** (the helper carries a SECOND `|| return 1` at :41 on
`get_upstream_commit`; the plan must pin the :49 one, not that one). The :49 guard cannot
fail naturally (if the upstream resolves, the count resolves), which is why it is
untested — and deleting it currently keeps the suite green. Test design: source the lib,
redefine `count_commits_in_range() { return 1; }` (bash redefinition shadows the library
function), call `handle_upstream_operation` in a repo with a valid upstream, assert
non-zero exit AND no preview output. Without the guard the stub's failure falls through
into the preview block, so the test goes red — the regression it exists to prevent.

**Symmetry:** §2 adds a NEW `|| return 1` guard (`offset=$(commit_offset …) || return 1`
inside the `== 0` branch); it must not ship unpinned while its sibling gets pinned. One
more stub test covers it: redefine `commit_offset() { return 1; }` in a repo whose HEAD
is synced with upstream (so the `== 0` branch executes), assert `handle_upstream_operation`
returns non-zero with no message conflated into the synced/behind paths.

**#236 — README set-e attribution** (~git-config/lib/README.md:460): "set -e is suspended
inside `$(…)`" is wrong — capture does not suspend errexit; the `|| exit $?` call context
does (commands on the left of `||`, and functions called there). Reword to attribute the
suspension to `|| exit $?` and state that this is why the `|| return 1` is load-bearing.

**#239 — oxymoron reword** (git-config/lib/hug-git-commit:237): "STRICT-display twin" →
"Display-only, failure-tolerant twin of `count_commits_in_range`". Keep the "NEVER use
for a branching or alignment decision" guidance verbatim.

## §4 Testing strategy

TDD throughout; only `make test-*` targets.

- **#234 helper layer** (`tests/lib/test_hug-upstream.bats`): `validate_backward_target`
  garbage → "not a valid commit"; forward/descendant → "is ahead of HEAD by N";
  DIVERGED → silent pass (exit 0, no message); ancestor and self → silent pass.
- **#234 mover layer** (`tests/unit/test_head.bats`): full matrix for `h back` at root
  (garbage → loud failure + root commit intact; `<descendant>` → loud failure; no-arg →
  root-recovery proceeds at danger tier; valid ancestor → normal move). Spot-checks of
  the same shapes for `h undo` and `h rollback` (identical wiring; per-command matrices
  would be redundant), PLUS a sideways spot-check for the documented everyday shape
  (`hug h undo main` with an advanced/diverged `main`) asserting it PROCEEDS to
  preview/reset — NOT a silent non-zero exit. This assertion is the batch's only defense
  against the errexit capture bug: `bats run` disables errexit, so a broken
  `offset=$(…); rc=$?` idiom passes the helper layer green and dies only in the real
  mover script under `set -euo pipefail`.
- **#237** (`tests/lib/test_hug-upstream.bats`): aligned → "Already synced"; behind →
  "N commit(s) behind … pull or rebase"; exit 0 in both.
- **#235**: the two function-shadowing stub tests above.
- **Regression guard,** stated by concern surface: every suite asserting the changed
  "Already synced" message stays green — `test_workflows.bats` ×4 (h-back/-undo/-rollback/
  -squash `-u` synced, integration) and `test_head.bats` ×1 (h-rewind `-u`) — and all
  existing targeted suites stay green. Counts, with measurement bases labeled: head 157,
  upstream 10, restore 18, lib-commit 43, workflows 22 are whole-file `@test` counts;
  cmv 35 is the `TEST_FILTER=cmv` topic SUBSET of `test_commit.bats` (72 tests total).
  Valid backward targets behave identically.
- **Canary:** `grep -rn '|| echo 0' git-config/` stays at exactly 1 hit — new comments
  must not reintroduce the literal pipe-form (the #233 born-broken-canary lesson).

## §5 Scope exclusions

Explicitly NOT in this batch:

- **#240 / #230 / the "changes in 0 commit:" forward-preview cosmetic** — sub-project A
  (family overhaul; Phase-2 spec exists:
  `docs/superpowers/specs/2026-07-30-head-mover-direction-messaging-design.md`).
- **#222 concerns 3/4/5** — sub-project C (audit).
- **#232** (target-aware untracked-overwrite escalation) — separate issue, not batch B.
- **h-rewind / h-squash** — no root-recovery path, so §1's gate has no seam there. The
  §2 truthful message is a different story: it lands on ALL SIX callers of
  `handle_upstream_operation` (h-back, h-undo, h-rollback, h-rewind, h-squash, h-cmv)
  via the shared helper.
- **No behavior change** for valid backward targets or any `-u` path beyond the truthful
  message.

## §6 CHANGELOG entry

`CHANGELOG.md` documents every user-visible change in detail (see the 1.4.0 entries).
Structural wart to handle while touching it: the file carries TWO `## [Unreleased]`
headers (:5 empty, :71 populated with already-shipped wtdel entries). The batch's entries
go in the TOP one; rename the second block to its actual release (pre-existing wart,
cheap to fix in the same edit). Entries:

- **Fixed** — loud errors for invalid/forward explicit targets in `h back`/`h undo`/
  `h rollback` (a garbage target could previously trigger the root-recovery path; a
  forward target was a silent surprise): elifarley/hug-scm#234.
- **Changed** — `-u` operations now report "N commit(s) behind upstream" instead of the
  false "Already synced" when HEAD is behind: elifarley/hug-scm#237.
- **Fixed** — `commit_offset`'s Usage docstring recommended a capture idiom
  (`offset=$(…); rc=$?`) that aborts `set -e` callers before the dispatch can run;
  corrected to the `|| rc=$?` form (discovered while specifying #234's gate).

## §7 Perimeter documentation — docs/commands/head.md

`head.md` documents the EXACT fate this batch rewrites, and is already stale:

- `head.md:155-165` ("Why a dedicated recovery command?") claims re-invoking a mover
  with a forward target "silently exits 0" via the `count_commits_in_range == 0`
  aligned check. Stale since #229-Phase-1 (the guard is `is_same_commit` and a forward
  target PROCEEDS, pinned by test_hug-upstream.bats), and doubly wrong post-batch:
  forward explicit targets error LOUDLY via `validate_backward_target`.
- `head.md:125` repeats the mechanism parenthetically ("which would short-circuit on
  the aligned-target check").

Both passages rewrite to the post-batch truth: a backward mover REJECTS a forward
explicit target with a loud error pointing at `hug h restore`; restore remains the
sanctioned forward mover, and its actual rationale (exact-SHA no-op test, op-named mode
flags) is unchanged and stays. Land with this batch; sequence per the note in
Risks/notes.

## Risks / notes

- `validate_backward_target` adds one rev-parse + one rev-list traversal per explicit
  target; negligible for an interactive safety gate.
- The `-z target_arg` guard clause relies on `target_arg` being in scope at the root-path
  check — true in all three movers today (parsed in the flag loop before the branch); the
  implementation plan must keep it that way.
- #237's behind-message mentions pull/rebase generically; which one is right depends on
  the user's intent. This is informational guidance, not a command suggestion with
  force-semantics, so the generic wording is acceptable (Phase-2 messaging can refine).
- **Sequencing with sub-project A:** the batch-A Phase-2 spec
  (`2026-07-30-head-mover-direction-messaging-design.md`) records the `-u` retained
  no-op (`local_commits == 0` → "Already synced", exit 0) as UNCHANGED context; this
  batch rewrites exactly that branch's message (semantics preserved: exit 0 in-subshell
  no-op, helper stdout contract `echo "$target"` intact). Either landing order works,
  but A's spec text should be refreshed to match if this batch lands first. The head.md
  perimeter rewrite (§7) lands WITH this batch and supersedes the stale passages for
  either order.
