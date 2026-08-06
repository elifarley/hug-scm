# Head-mover correctness batch — design

Date: 2026-08-06
Status: Approved (brainstorming, design sections §1–§5 validated)
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

Contract (built on `commit_offset`, one call resolves all three outcomes):

| Input | Result |
|---|---|
| unresolvable target (`commit_offset` exit 3) | `error "'<target>' is not a valid commit"` + non-zero |
| target AHEAD of HEAD (`offset < 0`) | `error "hug h <op> moves HEAD back, but '<target>' is ahead of HEAD by N commit(s) (use 'hug h restore' to move forward)"` + non-zero |
| target is HEAD or an ancestor (`offset >= 0`) | silent pass, exit 0 |

**Wiring (identical seam in all three movers):** insert the call right after
`resolve_target_with_temporal` in the NON-upstream path, before the root-path branch,
**conditioned on a non-empty positional arg**:

```bash
[[ -n "$target_arg" ]] && validate_backward_target "$target" "back"
```

EXPLICIT targets only. The DEFAULT `HEAD~1` is skipped by design: at the root commit it
legitimately does not resolve — that unresolved default is precisely the trigger for the
root-recovery branch, so validating it would break the legitimate no-arg case. Temporal
(`-t`) targets are out of scope of the gate too (already resolved-and-validated by
`resolve_temporal_to_commit`; their forward-move behavior is the pre-existing post-#233
semantics, and a target-by-time is not a "typed the wrong ref" mistake).

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
    offset=$(commit_offset "$target" HEAD) || return 1   # 0 aligned, -N behind; diverged unreachable
    if [ "$offset" -eq 0 ]; then
        info "Already synced to upstream ($target_short)."
        exit 0
    fi
    info "Nothing to move: HEAD is ${offset#-} commit(s) behind upstream ($upstream_branch). Pull or rebase to catch up."
    exit 0
fi
```

Decisions:

- **Behind is informational + exit 0**, not a warning/non-zero: "you asked to move local
  commits upstream and there are none" is still a successful no-op — the message just has
  to be honest.
- **Lives in the shared helper**, so all six `-u` callers get it at once.
- **Bonus:** first PRODUCTION caller of `commit_offset`, advancing #238 (its eventual
  full home is Phase-2 direction messaging).

## §3 Hygiene trio

**#235 — pin `handle_upstream_operation`'s `|| return 1`.** The guard cannot fail
naturally (if the upstream resolves, the count resolves), which is why it is untested —
and deleting it currently keeps the suite green. Test design: source the lib, redefine
`count_commits_in_range() { return 1; }` (bash redefinition shadows the library
function), call `handle_upstream_operation` in a repo with a valid upstream, assert
non-zero exit AND no preview output. Without the guard the stub's failure falls through
into the preview block, so the test goes red — the regression it exists to prevent.

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
  garbage → "not a valid commit"; forward/descendant → "is ahead of HEAD by N"; ancestor
  and self → silent pass.
- **#234 mover layer** (`tests/unit/test_head.bats`): full matrix for `h back` at root
  (garbage → loud failure + root commit intact; `<descendant>` → loud failure; no-arg →
  root-recovery proceeds at danger tier; valid ancestor → normal move). Spot-checks of
  the same three shapes for `h undo` and `h rollback` (identical wiring; per-command
  matrices would be redundant).
- **#237** (`tests/lib/test_hug-upstream.bats`): aligned → "Already synced"; behind →
  "N commit(s) behind … pull or rebase"; exit 0 in both.
- **#235**: the function-shadowing stub test above.
- **Regression guard:** all existing targeted suites stay green (head 157, upstream 10,
  restore 18, cmv 35, lib-commit 43). Valid backward targets behave identically.
- **Canary:** `grep -rn '|| echo 0' git-config/` stays at exactly 1 hit — new comments
  must not reintroduce the literal pipe-form (the #233 born-broken-canary lesson).

## §5 Scope exclusions

Explicitly NOT in this batch:

- **#240 / #230 / the "changes in 0 commit:" forward-preview cosmetic** — sub-project A
  (family overhaul; Phase-2 spec exists:
  `docs/superpowers/specs/2026-07-30-head-mover-direction-messaging-design.md`).
- **#222 concerns 3/4/5** — sub-project C (audit).
- **#232** (target-aware untracked-overwrite escalation) — separate issue, not batch B.
- **h-rewind / h-squash** — no root-recovery path; they inherit only the shared-helper
  §2 message.
- **No behavior change** for valid backward targets or any `-u` path beyond the truthful
  message.

## Risks / notes

- `validate_backward_target` adds one rev-parse + one rev-list traversal per explicit
  target; negligible for an interactive safety gate.
- The `-z target_arg` guard clause relies on `target_arg` being in scope at the root-path
  check — true in all three movers today (parsed in the flag loop before the branch); the
  implementation plan must keep it that way.
- #237's behind-message mentions pull/rebase generically; which one is right depends on
  the user's intent. This is informational guidance, not a command suggestion with
  force-semantics, so the generic wording is acceptable (Phase-2 messaging can refine).
