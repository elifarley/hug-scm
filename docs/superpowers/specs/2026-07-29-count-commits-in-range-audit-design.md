# Design: Audit `count_commits_in_range` + callers — kill the `== 0 ⟹ aligned` idiom

- **Issue:** [elifarley/hug-scm#229](https://github.com/elifarley/hug-scm/issues/229)
- **Related:** [elifarley/hug-scm#222](https://github.com/elifarley/hug-scm/issues/222) — HEAD-mover tier + recovery design; this is the primitive underneath its Critical #1 (recovery hints that silently no-op).
- **Date:** 2026-07-29
- **Status:** Design draft, revised after code-roast review (see §10)

> Line numbers cited below are anchors against local `main` @ `36d2eea` (based on `origin/main` @ `1296dbf` at last fetch). Re-resolve at implementation time.

---

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

A one-directional count cannot distinguish these. `handle_standard_operation` conflates them (`hug-git-upstream:107-113`):

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

A failed `rev-list` (unborn HEAD at the root commit, invalid SHA) returns `0` — indistinguishable from "genuinely zero commits ahead." Callers then proceed as if aligned/empty. The root-commit recovery no-op noted in the #222 spec (§10) is this class. **Reproduced:** invalid `start` on an unborn HEAD → helper echoes `0`. An error masquerading as data is a latent correctness hazard across every caller.

## 2. Decision — full scope (D + B + C + A)

| Option | What | In this design? |
|---|---|---|
| **D** | Document the one-directional contract; forbid the alignment idiom | ✅ docstring + `lib/README.md` |
| **B** | Add a two-directional primitive `commits_ahead_behind` + thin `is_aligned` | ✅ §3 |
| **C** | Stop swallowing `rev-list` failures — **strict propagation** | ✅ §4 |
| **A** | Migrate every unsafe alignment caller to `is_aligned` | ✅ §5 |

Chosen approach: **Approach 1 — two-directional primitive as the single source of truth.** Alignment and ahead-count are expressed by one well-named family, honoring the "one algorithm, N consumers" discipline #229 asks for. (Rejected: per-caller SHA-equality or local fixes — they fix the bug but leave two unrelated alignment idioms in the codebase.)

**Error-path posture (C): strict propagation, not a `_strict` variant.** `count_commits_in_range` itself stops swallowing errors. This is the most correct option but means *every* caller — not just the 2 unsafe ones — must handle the new non-zero-on-failure exit. The audit in §4 covers all 9 call sites.

## 3. New library primitives — `git-config/lib/hug-git-commit`

### `commits_ahead_behind <start> <end>` — the two-directional core

```bash
# Returns the ahead/behind relationship between two commits as "<behind>\t<ahead>"
# via the three-dot symmetric difference:
#   git rev-list --left-right --count <start>...<end>
#   <behind> = commits reachable from <start> but NOT <end>  (end is BEHIND start by this many)
#   <ahead>  = commits reachable from <end>  but NOT <start> (end is AHEAD of start by this many)
#   NOTE: output order is git's native --left-right order (first arg's exclusive count
#   FIRST). Do NOT `read` this into named vars without respecting that order, or you
#   will silently swap ahead/behind. When BOTH counts are > 0 the refs have DIVERGED
#   (neither is an ancestor) — a sideways relationship; callers that label a single
#   direction must handle this third case (Site 1 labels it "diverged"). (Shallow clones:
#   the EQUALITY test via is_aligned is shallow-safe; raw ahead/behind COUNTS are not —
#   caveat if a counting consumer ever appears.)
# Alignment (<start> == <end>) ⟺ "0\t0".
#
# STRICT: a failed rev-list (invalid ref, unborn HEAD) propagates non-zero exit and
# prints nothing — it is NEVER swallowed into a zero. Callers MUST handle failure.
commits_ahead_behind() {
  local start="${1:?commits_ahead_behind: start ref required}"
  local end="${2:?commits_ahead_behind: end ref required}"
  git rev-list --left-right --count "$start...$end"
}
```

**Why three-dot `...` not two-dot `..`:** the symmetric difference captures the *relationship* (ahead / behind / equal) in one git call — exactly what the alignment idiom needs and what a one-directional count cannot express. It is also independently useful ("how far behind is my branch?"), which a bare SHA-equality predicate is not.

### `is_aligned <a> <b>` — the single sanctioned alignment predicate

```bash
# True (exit 0) iff <a> and <b> resolve to the SAME existing commit.
#
# This is the ONLY sanctioned alignment test. NEVER infer alignment from a
# one-directional count_commits_in_range == 0 — that means "not ahead," which is
# ALSO true when one ref is BEHIND the other (Defect 1). For the full relationship
# (ahead/behind counts) use commits_ahead_behind(). See lib/README.md "Range counting".
#
# PRECONDITION: both <a> and <b> MUST resolve to existing commits. On an unborn
# repo (no commits) rev-list exits 128 even for HEAD...HEAD, so is_aligned returns
# NON-ZERO for the trivially-aligned case — a false NEGATIVE, never a false positive.
# Callers must not invoke this before a commit exists; the codebase's standard
# repo/commit-existence guards (check_git_repo / ensure_commit_exists) run first in
# every mover, so this precondition holds at every call site. Documented + tested (§7).
#
# $'0\t0' uses ANSI-C quoting so \t is a real TAB (git's output field separator),
# NOT the two characters backslash-t. Do NOT "simplify" to '0\t0' or "0\t0" — both
# are literal backslash-t and never match.
is_aligned() {
  local a="${1:?is_aligned: first ref required}"
  local b="${2:?is_aligned: second ref required}"
  [ "$(commits_ahead_behind "$a" "$b" 2>/dev/null)" = $'0\t0' ]
}
```

**Strictness note:** the `2>/dev/null` in `is_aligned` only suppresses git's stderr chatter; a `rev-list` failure yields an empty/non-matching string → non-zero exit, never a false "aligned." Defect 2's swallow appears nowhere in either new function. The unborn-HEAD case (above) is the one boundary where the answer is a false *negative*; it is documented as a precondition, not hidden.

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

### `count_commits_in_range_or_zero` — the STRICT-display twin (MAJOR #4)

The two display-only call sites (`hug-git-rebase:238`, `git-h-files:202`) legitimately want a cosmetic `0` on `rev-list` failure. Giving each a local `|| echo 0` would re-introduce exactly the Defect-2 pattern (grep-findable, copy-pasteable onto a non-display site) with only a comment as guardrail. Instead, one **named** wrapper makes the function name itself the structural guardrail:

```bash
# STRICT-display twin of count_commits_in_range.
# ONLY for display/tip text where a 0 on rev-list failure is cosmetically acceptable
# (e.g. "in N commits since…"). NEVER use this for a branching or alignment decision —
# there, count_commits_in_range's strict propagation MUST surface the failure.
# Grep invariant: `|| echo 0` appears NOWHERE outside this single definition.
count_commits_in_range_or_zero() {
  count_commits_in_range "$@" || echo 0
}
```

### Caller audit — all 9 call sites of `count_commits_in_range`

> Note: `git-h-restore` is **not** in this table — it does not call `count_commits_in_range`; it has its own local SHA-equality check (Defect 1, same idiom, different mechanism). It is migrated to `is_aligned` in §5 Sites 3a/3b for DRY consistency.

| Site | Current `== 0` semantics | Class — the REAL invariant | Required change |
|---|---|---|---|
| `hug-git-upstream:107` `handle_standard_operation` | alignment/no-op | **UNSAFE (Defect 1)** — `== 0` is not alignment | **→ `is_aligned`** (§5) |
| `git-cmv:160` | "no commits to move" | **SAFE-but-mis-messaged** — `== 0` IS the correct vacuous-op semantic: cmv's target must be an ancestor ("specific commit to move **above**", "reset the current branch **back**"); a descendant has nothing above it, so no-op is right. The defects are the misleading "already at target" message + Defect 2 — NOT alignment. Migrating to `is_aligned` would SHIP a forward hard-reset + branch switch on a "NOT RESTORABLE" command (`git-cmv:41`). | **Keep the `== 0` guard**; strictness only (`|| exit 1`); fix the message (§5 Site 2). **Do NOT migrate to `is_aligned`.** |
| `hug-git-upstream:49` `handle_upstream_operation` | "no local commits ahead of upstream" | SAFE: `== 0` IS the correct no-op semantic for an upstream-aware op ("nothing to discard/push"), regardless of whether upstream itself is valid or ahead. Strictness change only. | `|| return 1` — on the (unexpected) rev-list failure, propagate loudly |
| `git-log-outgoing:92` | "no outgoing commits" | SAFE: `== 0` IS the correct "nothing outgoing" semantic for an upstream-aware op | `|| exit 1` — loud exit on unexpected failure |
| `git-h-files:122` | "no local-only commits" | SAFE: `== 0` IS the correct "already synced" semantic for an upstream-aware op | `|| exit 1` |
| `git-h-squash:167` | (upstream branch) "no commits to squash" | SAFE: `== 0` IS the correct "nothing to squash" semantic | `|| exit 1` |
| `git-h-squash:176` (call; `== 0` test at `:177`) | "no commits to squash" | SAFE, and the `== 0` branch (`:177`) is **LIVE, not defensive**: `ensure_ancestor_of_head` delegates to `merge-base --is-ancestor`, which treats **equality as ancestry** (verified: exit 0 for HEAD vs HEAD), so `hug h squash <SHA-of-HEAD>` lands here. Deleting this branch would resurrect the exact "[squash] 0 commits…" orphan bug the file's own comment (`git-h-squash:161-163`) records having already suffered. | `|| exit 1` (strictness only); **do NOT remove the `== 0` branch** |
| `hug-git-rebase:238` | display only (`num_commits` in plan) | SAFE: not a decision, just a number in the rendered plan | **→ `count_commits_in_range_or_zero`** (named wrapper, §4) |
| `git-h-files:202` | display only (tip text "in N commits since…") | SAFE: not a decision, cosmetic count in a tip line | **→ `count_commits_in_range_or_zero`** (named wrapper, §4) |

**Why the "safe" defense matters (and why it is NOT "target validated upstream"):** a reviewer/implementer trusting a "validated upstream" defense would think the only risk is an invalid ref — obscuring the real invariant (semantic correctness of `== 0` for upstream-aware commands). A future refactor that changed what `get_upstream_commit` returns could turn a "safe" site unsafe without tripping that wrong reasoning. The real invariant — `== 0` means "no local commits ahead of upstream," which is the correct no-op — is what an implementer must preserve.

**Discipline:** strictness is enforced structurally, not by prose. The library function never swallows; the ONLY sanctioned cosmetic-0 escape hatch is the **named** `count_commits_in_range_or_zero` wrapper (§4), and grep for `|| echo 0` must return exactly that one definition — nothing else. The two display sites call the wrapper rather than inlining the swallow, so a future maintainer cannot copy-paste Defect 2 back into a decision path.

**Bash pitfall — declare, then assign.** Every `|| exit 1` / `|| return 1` above MUST attach to a bare assignment, not a `local` declaration: `local x=$(cmd) || exit 1` is **dead code**, because `local` (like `declare`/`export`) always exits 0 regardless of the command substitution's failure, masking the very error strictness is meant to surface (reproduced: the combined form survives with `x=''`; the split form propagates). The correct split — `local x; x=$(cmd) || exit 1` — is what Site 1's snippet demonstrates (`local rel field1 field2` then `rel=$(commits_ahead_behind …) || return 1`).

**The 9 call sites split into two scopes — and the round-4 "add `local`" advice was wrong for one of them (round-5 MAJOR #3).** Bash has no block scope, so the distinction that matters is **function scope vs. script top-level**, not indentation:

- **In a function** (3 sites): use the split form `local x; x=$(…) || exit 1`. Never the combined `local x=$(…) || exit 1` (dead code — see pitfall above).
- **At script top-level** (6 sites — the indentation you see is from `if` blocks, NOT a function): a bare assignment `x=$(…)` propagates correctly under `set -e` (the script exits on a failing substitution). **Do NOT add `local` here — `local` outside a function is fatal** (proven: `bash -c 'set -euo pipefail; local x=1'` → "local: can only be used in a function", exit 1). The round-4 table told the implementer to "add `local`" at four top-level sites; following that would crash `h files` and `h squash`.

The danger an implementer must avoid: "tidying" a top-level bare assignment into `local foo=$(strict_count)` — which is both fatal (top-level) AND, if moved into a function, the dead-code masking form. Per-site scope + action (re-resolve at implementation time):

| Site | Scope today | Form today | Action for strictification |
|---|---|---|---|
| `hug-git-upstream:49` | function (`handle_upstream_operation`) | split `local` | OK as-is |
| `hug-git-upstream:107` | function (`handle_standard_operation`) | split `local` | OK as-is (Site 1 rewrites this) |
| `hug-git-rebase:237-238` | function (`rb_build_plan`) | split `local` | OK as-is |
| `git-h-files:122` | **script top-level** (in `if $upstream` block) | bare assignment | **leave bare** (propagates via `set -e`); do NOT add `local` (fatal). Optionally add explicit `|| exit 1` for clarity |
| `git-h-files:202` | **script top-level** | bare assignment | same — leave bare, do NOT add `local` |
| `git-log-outgoing:92` | **script top-level** | bare assignment | leave bare |
| `git-h-squash:167` | **script top-level** | bare assignment | leave bare, do NOT add `local` |
| `git-h-squash:176` | **script top-level** | bare assignment | leave bare |
| `git-cmv:160` | **script top-level** | bare assignment | leave bare |

**Real Defect-2 enforcement (round-4 MAJOR #5, corrected round-5 MAJOR #4).** A line-based grep **cannot** be a complete invariant here: a correct two-line split (`local x;` then `x=$(count_commits_in_range …)`) puts the call on a line with no `local` and no `|| exit 1`, so any exclusion grep either misses it or flags it (the round-4 grep returned 12 lines on fully-compliant code — verified). The honest enforcement is therefore **runtime, not static**: the **per-site strict-propagation test** (§7) — for each of the 9 sites, feed an invalid start ref and assert the script/function exits non-zero rather than printing "0 commits"/"Already at target". That is what §8 credits. Keep a narrow `|| echo 0` **canary** as a secondary tripwire (it still catches the literal Defect-2 swallow reappearing), but do not present it as proof, and do not present any grep as a complete caller-invariant.

## 5. Fixing the affected call sites (Defect 1)

> Sites 1 and 3b migrate the genuine alignment tests to `is_aligned`. Site 2 (`git-cmv`) is the deliberate exception — its `== 0` is correct, so it keeps the guard and only gets the strictness + message fix. Site 3a is a docs-drift cleanup forced by Site 1.

### Site 1 — `handle_standard_operation` (`hug-git-upstream:101-141`)

Replace the count-based guard with `is_aligned`, and compute the **full ahead/behind relationship** (not just the ahead-count) so the **preview** reports the correct range/count. The helper emits **nothing on stdout** and keeps its `exit 0` aligned-target early-exit — it is still called as a **bare statement** (not captured), so `exit 0` terminates the whole mover as today. The move **direction** is computed downstream in each mover's shared tail (see the design note), NOT by this helper:

```bash
handle_standard_operation() {
    local action_name="$1"
    local target="$2"
    local skip_when_aligned="${3:-true}"

    # Defect-1 fix: alignment is an EXACT SHA relationship, never a one-directional
    # count == 0. A forward (descendant) target was silently no-op'ing here before.
    # Called BARE by the movers, so `exit 0` terminates the whole mover (round-5 MAJOR #1:
    # capturing this helper via $(…) would make `exit 0` quit only the subshell, and the
    # mover would proceed to move HEAD right under the "Already at target" message).
    if is_aligned "$target" HEAD; then
        if [[ "$skip_when_aligned" == true ]] || ! has_uncommitted_tracked_changes; then
            info "Already at target $(git rev-parse --short "$target"). No action taken."
            exit 0
        fi
        [[ ${HUG_QUIET:-} != T ]] && info "No commits to $action_name; local tracked changes will be reset."
        return 0
    fi

    # NOT aligned. Compute the relationship ONCE (strict), for the PREVIEW only. Field names
    # are POSITIONAL (field1/field2) — NOT semantic — correct only for the arg order
    # ("$target" HEAD); positional names make that dependency explicit (round-4 MAJOR #1):
    #   field1 = commits reachable from $target but not HEAD = HEAD-behind-target -> FORWARD magnitude
    #   field2 = commits reachable from HEAD but not $target = HEAD-ahead-of-target -> BACKWARD magnitude
    local rel field1 field2
    rel=$(commits_ahead_behind "$target" HEAD) || return 1
    field1=${rel%%$'\t'*}; field2=${rel##*$'\t'}

    # Direction-cased preview (round-3 MAJOR #3): ALL THREE range-dependent artifacts must
    # flip TOGETHER, or a forward move shows an empty commit list above a non-empty diff
    # stat — the exact "changes in 0 commit:" symptom this audit exists to fix:
    #   field1>0, field2==0 -> FORWARD  -> HEAD..target, count = field1
    #   else (backward/diverged)        -> target..HEAD, count = field2
    local list_start list_end diff_range count
    if [ "$field1" -gt 0 ] && [ "$field2" -eq 0 ]; then
        list_start="HEAD"; list_end="$target"; diff_range="HEAD..$target"; count="$field1"
    else
        list_start="$target"; list_end="HEAD"; diff_range="$target..HEAD"; count="$field2"
    fi
    local commit_word="commit"; [ "$count" -gt 1 ] && commit_word="commits"

    printf 'Commits to be affected:\n' >&2
    print_commit_list_in_range "$list_start" "$list_end" >&2   # was hardcoded: "$target" HEAD
    if git diff --quiet "$diff_range"; then                    # was hardcoded: "$target..HEAD"
        printf '\nPreview: no file changes in %d %s.\n' >&2 "$count" "$commit_word"
    else
        printf '\nPreview: changes in %d %s:\n' >&2 "$count" "$commit_word"
        git diff --stat "$diff_range" >&2
    fi
    # Emits NOTHING on stdout. The mover computes the direction in its own tail.
}
```

**Design note — compute the direction in the mover tail (round-5 unifying fix, adopted; user-confirmed).** Rounds 3–4 threaded the direction *out of* the helper — round 3 via a process-global, round 4 via stdout. Round 5 showed **both are wrong**: emitting on stdout (a) **voids the aligned-target guard** — `exit 0` inside `direction=$(handle_standard_operation …)` quits only the subshell, so the mover proceeds and moves HEAD under the "Already at target" message (reproduced); and (b) **collides with `handle_upstream_operation`'s documented stdout contract** ("upstream commit hash to stdout", `hug-git-upstream:24-25`), captured by 7 callers across 6 commands (`h-back/undo/rollback/rewind`, `git-cmv:141`, `git-h-squash:165`) — a second stdout payload would break every `-u` path.

**Fix:** helpers emit nothing new and keep their existing stdout contracts; the direction is computed in each mover's **shared tail**, where `$target` and `$pre_op_head` (HEAD captured before the reset) are already live, via a thin `direction_between` wrapper — the single place direction is labeled for messaging ("one algorithm, N consumers"):

```bash
# direction_between <a> <b>: label how a move from <b> to <a> goes.
#   a ancestor of b -> "backward"    a descendant of b -> "forward"
#   a == b          -> "aligned"     neither           -> "diverged"
direction_between() {
  local a="${1:?}" b="${2:?}" rel f1 f2
  rel=$(commits_ahead_behind "$a" "$b") || return 1
  f1=${rel%%$'\t'*}; f2=${rel##*$'\t'}
  if   [ "$f1" -gt 0 ] && [ "$f2" -eq 0 ]; then echo forward
  elif [ "$f1" -eq 0 ] && [ "$f2" -gt 0 ]; then echo backward
  elif [ "$f1" -eq 0 ] && [ "$f2" -eq 0 ]; then echo aligned
  else echo diverged; fi
}
```

The mover tail (shown for `git-h-back`; the other three are analogous) changes by **two lines** and preserves everything else — including the #222 recovery hint (round-5 MAJOR #5):

```bash
# git-h-back: helper called BARE (exit 0 still terminates the mover on aligned).
handle_standard_operation "move back" "$target"
if has_staged_changes; then
    prompt_confirm_warn "Move HEAD, keeping changes staged? [y/N]: "   # tier+changes, direction-independent
else
    info "No staged changes detected; skipping confirmation."
fi
pre_op_head=$(git rev-parse HEAD)                          # preserved (round-5 MAJOR #5)
git reset --soft "$target"
direction=$(direction_between "$target" "$pre_op_head")    # ← NEW: computed in-tail
report_head_move "$direction" "$target" "(uncommitted changes preserved)."  # ← NEW (was `info "Moved HEAD back…"`)
emit_head_recovery_hint "$pre_op_head" "back"              # preserved (round-5 MAJOR #5)
```

`handle_upstream_operation` is **unchanged** (still `echo "$target"`; the 7 captures keep working). Its `-u` path converges on the same mover tail (`git-h-back:86-130`), so the tail's `direction_between "$target" "$pre_op_head"` yields `backward` there too (HEAD is ahead of the upstream tip) — fixing round-3 MAJOR #2 (the `-u` double-space) without touching the helper's stdout contract. The `-u` retained no-op (`local_commits == 0` → "Already synced", exit 0) is unchanged and intentionally SAFE (§4).

**Behavioral changes — enumerated, not derived (round-1 MAJOR #4).** Post-fix, every `handle_standard_operation` caller gains a forward-target path. The spec's own standard (a behavior change "must be enumerated, not derived") applies to **all four** movers. The direction (computed in each mover's tail via `direction_between`) makes each caller's preview and messaging direction-truthful. The only observable change is the **message/preview wording** — confirmation behavior is **unchanged** (see the rule below):

| Caller | Pre-fix (forward target) | Post-fix (forward target, clean index) | Changed observable |
|---|---|---|---|
| `git-h-back` | "Already at target", exit 0 | clean → skips confirmation (as today), soft-reset **forward**; result line via `report_head_move` → "Moved HEAD **forward**…" | message only (was "back") |
| `git-h-undo` | "Already at target", exit 0 | clean → skips confirmation (as today), mixed-reset **forward**; `report_head_move` → "Moved HEAD **forward**…" | message only (was "back") |
| `git-h-rollback` | "Already at target", exit 0 | warn prompt (as today), keep-reset forward; `report_head_move` → "… forward …" ¹ | message only (was "back") |
| `git-h-rewind` | "Already at target", exit 0 | **warn** prompt on a clean tree (state-dependent tier — see rule below), hard-reset forward; `report_head_move` switches the verb (see below) | **verb** — there is no "back" string to flip; h-rewind's text is "Rewind HEAD to…?" / "Rewind complete" (`:122/:128/:130`), which would *lie* for a forward move, so the helper words it direction-truthfully |

¹ `git reset --keep` **aborts** ("Entry … not uptodate") if a file in the reset range has uncommitted edits — a pre-existing `--keep` condition, not design-caused, but the forward path can hit it; the table's "keep-reset forward" assumes a clean-in-range tree.

**Confirmation is direction-independent — do NOT add a forward-move prompt.** This codebase's prompts are *safety* gates (danger ⟺ can destroy unrecoverable uncommitted work; warn ⟺ destructive-but-recoverable), not "did you mean that?" UX nudges. A forward move's safety profile is identical to a backward move's, because:

- The destructiveness of `reset --hard` (`h-rewind`) comes from discarding **uncommitted** work — that is orthogonal to direction. On a **clean** tree there is nothing to discard, so a forward `--hard` just moves HEAD to an already-committed descendant (`HEAD@{1}`-recoverable); it is no more destructive than a backward `--hard` on a clean tree.
- A clean-tree move (any mode) loses no uncommitted work and is reflog-recoverable → at most warn-tier, and the existing changes-based prompts already fire precisely when there *is* work at risk.

This is not a new principle — it is the **merged #231 (`head-movers-tier-unify`) model** already in the tree: the tier is computed from tracked-dirty *state*, not from the command. `git-h-rewind:89-94` sets `tier=warn` by default and escalates to `danger` only `if has_uncommitted_tracked_changes`; `h-back`/`h-undo`/`h-rollback` are fixed warn (`h-back`/`h-undo` additionally skip the prompt entirely when clean, since a soft/mixed reset loses nothing); `cmv` is fixed danger. Danger is per-state — the codification of "prompt ⟺ uncommitted work at risk." Therefore confirmation stays **tier + presence-of-changes**, exactly as today; direction affects only the wording. Prompting on a merely-surprising-but-safe, fully-recoverable move would re-introduce the confirmation-gradient noise that #218/#222 existed to remove. Callers use the direction (computed in the mover tail via `direction_between`) only to word the result truthfully — see the mover blueprint in the design note above.

### Site 1b — centralized mover result message: `report_head_move <direction> <target> [extra]` (kills MAJOR #1 + #2)

The four movers hand-roll near-identical result messages (`git-h-back:130`, `git-h-undo:155`, `git-h-rollback:134`, `git-h-rewind:128/:130`) that now all need direction-casing. Fixing that four times in prose is exactly the "N copies of one algorithm" the spec exists to remove — and it is how MAJOR #1 (h-rewind's "Rewind" verb lying on a forward move) and MAJOR #2 (the `-u` double-space) arise. **Centralize the result line in one PURE helper** that takes the direction as an explicit argument (no global — see Site 1):

```bash
# Words the post-move result line truthfully from a DIRECTION ARGUMENT (not a global),
# so all four movers share ONE direction-casing site. `case` (not &&-chains) avoids any
# `set -e` short-circuit hazard. The direction is passed by the caller (Site 1 / Site 1
# -u), so there is no setter-before-reader ordering contract and no `set -u` footgun.
#   backward -> "Moved HEAD back to <sha> <extra>"
#   forward  -> "Moved HEAD forward to <sha> <extra>"   (NOT "back", NOT "Rewind complete")
#   diverged -> "Moved HEAD to <sha> <extra>"           (neutral; neither ahead nor behind)
#   ""(or *) -> "Moved HEAD to <sha> <extra>"           (defensive; should not happen)
report_head_move() {
  local direction="${1:-}" target="${2:?}" extra="${3:-}"
  local word
  case "$direction" in
    forward)  word="forward" ;;
    backward) word="back" ;;
    diverged|'') word="" ;;        # neutral — neither ahead nor behind (or unset)
    *)        word="" ;;
  esac
  info "Moved HEAD ${word:+$word }to $(git rev-parse --short "$target")${extra:+ $extra}"
}
```

All four movers replace their hand-rolled result line with a `report_head_move` call, passing the direction they received from `handle_standard_operation`/`handle_upstream_operation`. h-rewind's "Rewind complete. Repository is now at …" (`:130`) becomes `report_head_move "$dir" "$target"`, which says "forward" on a forward move instead of lying. The per-mover `extra` (e.g. h-undo's "to undo commits") is the third arg; the contract is one direction-casing site, consumed by all four. (No `mode_noun` parameter: it was dead in an earlier draft — the verb is direction-derived, not mode-derived. If a mover needs its mode verb in the line, it's part of `extra`.)

**`skip_when_aligned=false` + dirty-tree + forward-target (the `h-rewind` danger path):** pre-fix this hit the `count == 0` branch and, if the tree was dirty, printed "local tracked changes will be reset." Post-fix a forward target is not aligned, so it flows through the direction-aware preview. The **end-state is unchanged** (HEAD moves forward via the caller's reset; the danger prompt still fires because the tree is dirty — that is what makes `--hard` dangerous, not the direction); only the message wording differs. Pinned by the §7 smoke test.

### Site 2 — `git-cmv` (`:156-164`) — keep the guard, fix strictness + message (NOT `is_aligned`)

Per §4's reclassification, cmv's `== 0` is the **correct** vacuous-op semantic — a descendant target has nothing to move and the request is incoherent. The fix is strictness + a truthful message, **not** an `is_aligned` migration (which would ship a forward hard-reset + branch switch on a "NOT RESTORABLE" command):

```bash
target=$(git rev-parse "$target")

# cmv target must be an ANCESTOR ("commit to move above", "reset branch back").
# == 0 ⟹ vacuous operation (correct no-op). Strict: a bad ref now fails loudly
# instead of masquerading as "0 commits". The OLD message lied ("already at
# target") for a forward target — a forward target is NOT aligned, it is simply
# an incoherent cmv request; say so.
commits_to_relocate=$(count_commits_in_range "$target" HEAD) || exit 1
if [ "$commits_to_relocate" -eq 0 ]; then
  info "No commits to move (target $(git rev-parse --short "$target") is not behind HEAD)."
  exit 0
fi
```

If forward-reset semantics for cmv are ever wanted, that is a separate feature needing its own help-text change + confirmation story — not a drive-by in a correctness audit.

### Site 3a — `git-h-restore` stale comment blocks MUST be rewritten (CRITICAL #1)

`git-h-restore`'s **entire stated reason for existing** is built on the bug Site 1 fixes. Two comment blocks name the `count==0` forward no-op as the defining problem:

- **Header, `git-h-restore:16-20`** — "WHY this exists: re-invoking a mover … to recover forward no-ops **via handle_standard_operation's count==0 gate** (the aligned-target short-circuit in hug-git-upstream:109-112)."
- **Header, `git-h-restore:27-28`** — "safety additions (bare-numeric guard, --rewind+dirty danger escalation, per-tier prompt) **arrive in Task 8**." These are ALREADY in the file (`:85-86`, `:117-120`) — stale regardless of this audit, but the stated goal is "git-h-restore carries no stale rationale," so the whole header block gets one coherent rewrite.
- **Inline, `git-h-restore:104-106`** — "The defining feature: no-op ONLY on exact SHA equality … This lets recovery move FORWARD to a descendant (re-invoking the mover **no-ops there via handle_standard_operation's count==0 bailout**)."

After Site 1, the movers **no longer** have that no-op — `hug h back <descendant>` moves HEAD forward itself. The comments become factually wrong, and a future maintainer reading them concludes the bug still exists. This is exactly the docs/claims hazard the spec exists to eliminate; leaving it would move the defect rather than fix it. **The whole header block (:14-28) plus the inline comment (:104-106) must be rewritten** in the same PR to state `git-h-restore`'s now-actual purpose: an op-named-flag selector for the reset MODE, gated on exact SHA equality — independent of (and now redundant with) the movers' alignment gate. Suggested rewrite of the header WHY block:

```text
# WHY this exists: an explicit recovery primitive that resets HEAD to a prior
# commit as the inverse of a HEAD-mover. Its no-op test is EXACT SHA equality
# (via is_aligned), the only test that distinguishes "already there" from
# "move to a different commit." The movers now share that same is_aligned gate
# (hug-git-upstream); this command remains the dedicated, op-named inverse.
```

(Grep confirms `git-h-restore` is the ONLY file referencing the `count==0` / aligned-target gate, so the docs-drift is bounded to this one file — no other comments need updating.)

### Site 3b — `git-h-restore:107` adopts `is_aligned`

The local SHA-equality check switches to the canonical primitive:

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
- **`git-config/lib/README.md` — fix pre-existing drift + cross-reference `is_aligned`** (minor): `:98` and `:133` both describe `handle_standard_operation`'s aligned-target gating, but they CONTRADICT each other — `:98` attributes the predicate to `has_untracked_or_pending_changes`, while the code (`hug-git-upstream:110`) and `:133` both use `has_uncommitted_tracked_changes`. `:98` is stale; correct it to match `:133`/the code. While there, cross-reference `is_aligned` as the sanctioned alignment test at both `:98` and `:133`, so the README's "aligned-target gating" prose points at the primitive this audit introduces (the same docs-drift discipline as Site 3a).
- **`git-config/lib/README.md:425-435` — refresh the helper-usage examples** (round-5 MAJOR #6): the `handle_upstream_operation` / `handle_standard_operation` examples go stale once this audit lands. Update them to (a) show `handle_standard_operation` called **bare** (its `exit 0` aligned-guard depends on NOT being captured), (b) document the new `direction_between` + `report_head_move` helpers with a worked mover-tail example, and (c) keep `handle_upstream_operation`'s example showing it **returns the upstream SHA** (the stdout contract this audit deliberately preserves). Also enumerate in the §5 table the full set of message changes the movers undergo (full→short SHA in the result line, the `h-rollback` sentence rewrite, h-rewind's verb), so the docs pass and the behavior table agree.

## 7. Testing strategy

Per `git-config/lib/CLAUDE.md` ("elegant tests" for lib changes) and the project's BATS conventions.

**`tests/lib/test_hug-git-commit.bats`** (EXTEND — **hyphens**; the existing `count_commits_in_range` tests at `:33-50` stay and survive strictification. Do NOT create an underscore-named twin):
- `commits_ahead_behind`: ancestor pair → `"0\t<N>"`; descendant pair → `"<N>\t0"`; aligned → `"0\t0"`; invalid ref → non-zero exit, empty stdout.
- `is_aligned`: same SHA → exit 0; ancestor → non-zero; descendant → non-zero; invalid ref → non-zero (never false-aligned); **unborn repo, `is_aligned HEAD HEAD` → non-zero (false NEGATIVE, documented precondition — CRITICAL #2)**.
- `count_commits_in_range` strict: invalid start → non-zero exit, empty stdout (Defect-2 regression); missing `$1` → fails fast via `${1:?}` (MINOR #9).
- `count_commits_in_range_or_zero`: invalid start → echoes `0`, exit 0 (the named cosmetic twin).

**`tests/lib/test_hug-upstream.bats`** (extend existing aligned-target tests):
- **Defect-1 regression (the headline test):** descendant/forward target on a clean tree → `handle_standard_operation` does NOT print "Already at target", does NOT `exit 0` from the guard, and returns 0 *past* the alignment check (so the caller proceeds to its reset). The helper is read-only (it previews/confirms, then returns; the caller performs the reset), so the test asserts the guard is *not* taken — not that HEAD moves inside the helper. The companion smoke test (§7) asserts the end-to-end HEAD move through `hug h back`.
- Keep existing aligned + untracked-only / tracked-dirty tests (they now exercise `is_aligned`).

**`tests/unit/test_commit.bats`** (EXTEND the "# hug cmv expectations" section, `:336+` — there is **no** `test_h_cmv.bats`): forward (descendant) target → still a clean no-op, but the message is now "No commits to move (target … is not behind HEAD)", NOT the false "already at target"; **assert the branch did NOT move forward** (pins that we did not ship the regression). Ancestor target → unchanged behavior.

**`tests/unit/test_h_squash.bats`** (extend, or whichever file covers h-squash): `hug h squash <SHA-of-HEAD>` → "No commits to squash", exit 0, **no commit created** — pins the LIVE `== 0` branch (MAJOR #2) so nobody deletes it as "dead defense" and resurrects the 0-commit orphan bug.

**`tests/unit/test_h_restore.bats`** (extend): aligned → no-op (unchanged via `is_aligned`); invalid SHA → error, not silent.

**Forward-direction tests (behavioral MAJOR #4)** — in the per-command unit files (`tests/unit/test_head.bats` / the relevant mover file):
- `h-back`/`h-undo` + forward target + **clean** index → confirmation still **skipped** (direction-independent; a clean tree loses nothing); HEAD moves forward; result message says "forward", not "back".
- `h-back` + forward target + **staged** changes → warn prompt fires (same as the backward dirty case); message says "forward".
- `h-rewind` + forward target + **clean** tree → **warn** prompt (state-dependent tier: clean→warn); HEAD moves forward.
- `h-rewind` + forward target + **dirty** tree → **danger** prompt (the dirty tree, not the direction, is what makes `--hard` dangerous); HEAD moves forward.
- backward target (the common case) → confirmation behavior **unchanged** (regression guard).
- `handle_standard_operation` is called **bare** and emits nothing on stdout; the mover computes the direction via `direction_between "$target" "$pre_op_head"` and passes it to `report_head_move` (round-5 compute-in-tail; assert the helper leaves no process-global side effect).

**Messaging / preview tests (round-3 MAJORs #1/#2/#3 + round-5 #1/#2/#5):**
- `report_head_move` (unit): `backward` → "Moved HEAD back to …"; `forward` → "Moved HEAD **forward** to …"; `diverged` → neutral "Moved HEAD to …"; empty/`*` → neutral (no crash under `set -euo pipefail` — uses `case`, not `&&`-chains; pins round-4 CRITICAL #2).
- `direction_between` (unit): ancestor→`backward`; descendant→`forward`; equal→`aligned`; sibling→`diverged`; invalid ref→non-zero. (The single direction-labeling site.)
- **Aligned-guard-not-voided (round-5 CRUX, MAJOR #1):** `hug h back` (or any mover) with target == HEAD → prints "Already at target. No action taken.", exits 0, and does **NOT** then print "Moved HEAD …" nor move HEAD nor emit a recovery hint. Pins that `handle_standard_operation` is called **bare** (its `exit 0` terminates the mover); a regression to `direction=$(handle_standard_operation …)` would fail this test (the mover would proceed under the no-op message — reproduced at design time).
- **`handle_upstream_operation` SHA contract preserved (round-5 MAJOR #2):** `target=$(handle_upstream_operation …)` still yields the upstream SHA (not a direction token) on all 7 capturing callers; no `-u` path renders a double-space or directionless result line.
- **Recovery hint preserved (round-5 MAJOR #5):** after a successful warn-tier move, `emit_head_recovery_hint` still prints the `hug h restore <SHA> --<op> -y` line — i.e. the mover blueprint kept `pre_op_head` + the hint (not dropped).
- `h-rewind` + forward target → result line does NOT say "Rewind complete"/"back"; it says "forward" (pins MAJOR #1 — the verb no longer lies).
- `h back -u` with local commits ahead of upstream → result line has NO double space and reads "Moved HEAD back to …" (pins round-3 MAJOR #2 — the mover tail's `direction_between` yields `backward`; `handle_upstream_operation`'s SHA stdout is unchanged).
- forward target preview → the commit list AND the `diff --stat` use `HEAD..target` and the count is the behind-count, so NO "changes in 0 commit:" above a non-empty stat (pins MAJOR #3 — all three artifacts flip together).
- divergent target (`h back <sibling-branch-tip>`) → neutral "Moved HEAD to …", not "backward" (minor #2).
- invalid SHA surviving `resolve_target_with_temporal` through a mover → loud non-zero failure (no silent "Already at target"); §7 currently pins invalid-SHA only for h-restore, so extend to at least one mover (edge case #4).

**Smoke verification (acceptance criterion):** on a scratch repo, `hug h back <descendant-SHA> -y` moves HEAD rather than printing "Already at target." The current bug was reproduced this way at design time; the regression test encodes the inverse.

**Smoke test — `skip_when_aligned=false` + dirty-tree + forward-target (the `h-rewind` danger path):** `hug h rewind <descendant-SHA>` on a repo with dirty tracked changes still fires the danger-tier confirmation and moves HEAD forward.

**Smoke test — forward-direction messaging:** `hug h back <descendant-SHA>` on a clean tree skips confirmation (as today) and prints "Moved HEAD **forward**", not "back".

**Grep canary (secondary):** after implementation, `grep -rn '|| echo 0' git-config/` returns exactly one line — the body of `count_commits_in_range_or_zero`. This is a **tripwire, not a proof**: it misses formatting variants (`||echo 0`, `|| printf '0\n'`, multi-line) and the structural `local`-masking form (round-4 CRITICAL #1). Treat it as a canary, not the acceptance criterion.

**Per-site strict-propagation test (PRIMARY Defect-2 enforcement — round-4 CRITICAL #1):** for each of the 9 call sites, exercise a `rev-list` failure (invalid start ref) and assert the script/function exits non-zero — NOT "Already at target"/"0 commits". Without this, the audit's central guarantee (Defect 2 fixed everywhere) is untested, and a careless `local foo=$(strict_count)` refactor at any site silently reverts it with green happy-path tests. **This runtime test is what §8 credits** — round 5 proved no line-based grep can serve as a complete caller-invariant (a correct two-line `local x; x=$(…)` split puts the call on a line the grep can't classify; the round-4 grep returned 12 false positives on compliant code). The `|| echo 0` canary above stays as a secondary tripwire only.

**Sanitize gate:** `make sanitize` after implementation (per `makefile-rules.md`); shellcheck must pass on all touched bash.

## 8. Acceptance criteria → where addressed

- [x] All **9** call sites audited; each `== 0` use classified safe / unsafe with the REAL invariant stated — §4 table. (2 unsafe → `is_aligned`; 6 safe-ahead-count → strictness; 1 safe-but-mis-messaged `git-cmv` → keep guard + message fix; 2 display → named wrapper. `git-h-restore` is a non-caller handled separately in §5 Sites 3a/3b.)
- [x] Every unsafe **alignment** test replaced with the two-directional primitive (`is_aligned`) — §5 (Site 1 `handle_standard_operation`, Site 3b `git-h-restore`). `git-cmv` deliberately **NOT** migrated (its `== 0` is the correct vacuous-op semantic; migration would ship a forward hard-reset on a "NOT RESTORABLE" command) — §1 counter-example + §4 + §5 Site 2.
- [x] `handle_standard_operation` no longer no-ops on a forward (descendant) target — regression test in §7; the forward-target path is enumerated for **all four** movers (§5 table) with direction-truthful messaging/preview (direction computed in the mover tail via `direction_between`; helper called **bare** so its `exit 0` aligned-guard is intact — round-5 MAJOR #1) and **direction-independent confirmation** (unchanged — safety gates key on uncommitted work, not direction; a clean move loses nothing and is reflog-recoverable).
- [x] `git-h-squash:177`'s `== 0` branch preserved (it is LIVE via `merge-base` equality-as-ancestry, not defensive) + regression test — §4 + §7.
- [x] The `|| echo 0` swallow is removed (strict propagation); the only sanctioned cosmetic-0 escape is the NAMED `count_commits_in_range_or_zero` wrapper. Enforcement is the **per-site strict-propagation test** (§7, round-4 CRITICAL #1) — NOT a grep (round 5 proved no line-grep is complete: the round-4 caller-invariant returned 12 false positives on compliant code). The `|| echo 0` grep is a secondary canary only.
- [x] Docstring + `lib/README.md` state the one-directional contract and forbid the alignment idiom — §6.
- [x] `git-h-restore`'s stale rationale comments (whole header block :14-28 incl. the "arrive in Task 8" line + inline :104-106) rewritten so the spec doesn't move the docs-drift — §5 Site 3a (CRITICAL #1).
- [x] `is_aligned`'s unborn-HEAD precondition documented + tested — §3 + §7 (CRITICAL #2).
- [x] Mover result messaging centralized in `report_head_move` (single direction-casing site) — no direction-lying verb (h-rewind), no `-u` double-space, divergent targets worded neutrally — §5 Site 1b + §7 (round-3 MAJORs #1/#2).
- [x] Site 1 preview block fully enumerated and direction-cased (commit list + diff stat + count flip together) — the "changes in 0 commit:" symptom fixed at its source — §5 Site 1 + §7 (round-3 MAJOR #3).
- [x] `handle_upstream_operation`'s stdout contract (emit upstream SHA) is **UNCHANGED** — its 7 capturing callers keep working; the mover tail computes direction via `direction_between`, so the `-u` path has no double-space/directionless result (round-3 MAJOR #2 fixed without changing the helper — round-5 MAJOR #2). Mover tails preserve `pre_op_head` + `emit_head_recovery_hint` (round-5 MAJOR #5).

## 9. Out of scope

- Root-commit recovery paths noted in #222 §10 (separate defect class; tracked there).
- Any change to the *ahead-count callers'* semantics — they keep meaning "is `end` ahead of `start`?"; only their failure handling changes (§4).
- Mercurial (`hg-config/`) — the issue scopes to Git. `hg` has no upstream-count analog here; no port required.

## 10. Review history

**Round 1 — 2026-07-29 (code-roast).** All five substantive findings were independently re-verified against the codebase before amending; all held:

- **CRITICAL #1** — `git-h-restore` header (`:16-20`) AND inline (`:104-106`) comments name the `count==0` forward no-op as the file's reason for existing; Site 1 fixes that no-op, so both comments go stale. **Added §5 Site 3a** to rewrite both. (Verified: grep confirms `git-h-restore` is the only file with these references — drift is bounded.)
- **CRITICAL #2** — `is_aligned HEAD HEAD` on an unborn repo returns non-zero (false negative). The "never false-aligned" claim survives, but the precondition was undocumented. **Tightened the §3 docstring** + added the §7 unborn-HEAD test row. (Verified empirically: `rev-list HEAD...HEAD` exits 128 on a fresh repo.)
- **MAJOR #3** — audit-table "safe because target validated upstream" was the wrong invariant. **Rewrote the §4 table** to state the real one: `== 0` is the correct no-op semantic for upstream-aware commands.
- **MAJOR #4** — two display sites' local `|| echo 0` re-introduced Defect 2 with only a comment as guardrail. **Added the named `count_commits_in_range_or_zero` wrapper** (§4) + a grep-invariant test (§7). (Verified: the only existing `|| echo 0` is `hug-git-commit:219`.)
- **MAJOR #5** — `skip_when_aligned=false` + dirty-tree + forward-target (`h-rewind` danger path) message-flow change was undocumented. **Added to §5 Site 1** + a §7 smoke test. (Verified: `git-h-rewind:114` passes `false`.)

Also applied MINOR #8 (one anchor SHA in header) and MINOR #9 (`${1:?}` on the rewritten `count_commits_in_range`). MINOR #6/#7 (ANSI-C quoting note, docstring output naming) folded into the §3 `is_aligned` docstring.

**Round 2 — 2026-07-29 (code-roast re-review).** Five MAJORs, no CRITICALs. All five independently re-verified; all held. **Two reverse round-1 classifications — both reversals are correct:**

- **MAJOR #1 (reversal)** — `git-cmv` is **SAFE-but-mis-messaged**, not UNSAFE. For cmv, `== 0` IS the correct vacuous-op semantic (target = "commit to move above"; op "resets the branch back"; tail runs `git reset --hard "$target"`); a descendant target has nothing above it. Round-1's `is_aligned` migration would ship a forward hard-reset + branch switch on a self-declared "NOT RESTORABLE" command (`git-cmv:41`). **Reclassified in §4; §5 Site 2 now keeps the guard** (strictness + truthful message only) and drops the `is_aligned` migration. (Verified: help text `:21/:30/:41`, tail `:222-253`.)
- **MAJOR #2** — `git-h-squash:177`'s `== 0` branch is **LIVE, not "purely defensive"**: `ensure_ancestor_of_head` uses `merge-base --is-ancestor`, which treats equality as ancestry, so `hug h squash <SHA-of-HEAD>` lands there. Deleting it resurrects the 0-commit orphan bug the file's own comment (`:161-163`) records. **Rewrote the §4 rationale** ("do NOT remove the branch") + added a §7 regression test. (Verified: `merge-base --is-ancestor HEAD HEAD` → exit 0; `rev-list --count HEAD..HEAD` → 0.)
- **MAJOR #3** — §1 overcounted the affected population: `git-h-restore` never *calls* `handle_standard_operation` (only references it in comments); the 4 real callers are `h-back/h-undo/h-rollback/h-rewind`. **Fixed §1**; h-restore is the workaround, not an instance. (Round-1's `grep -l` matched comment lines.)
- **MAJOR #4 (behavioral)** — the round-1 forward-target enumeration covered only `h-rewind`; `h-back`/`h-undo` gain a forward move on a clean index, and all movers print direction-inverted "Moved HEAD back" for a forward move. **Decision: expose direction for truthful messaging/preview only; confirmation stays direction-independent.** §5 Site 1 computes the full relationship via `commits_ahead_behind`, exposes `HUG_HEAD_MOVE_DIRECTION`, and makes previews/messaging direction-truthful. An earlier draft added a "forward move confirms even when clean" rule; **the user correctly rejected it**: `reset --hard`'s destructiveness comes from discarding *uncommitted* work (orthogonal to direction), so a clean-tree forward move loses nothing and is reflog-recoverable — prompting on a merely-surprising-but-safe move would re-introduce the confirmation-gradient noise #218/#222 removed. Confirmation is tier + presence-of-changes, exactly as today; direction changes only the wording. Added a §5 enumeration table for all four movers + §7 forward-direction tests.
- **MAJOR #5** — test-file references were wrong: `test_hug_git_commit.bats` (underscores) doesn't exist — the hyphenated `test_hug-git-commit.bats` does (count tests at `:33-50`); `test_h_cmv.bats` doesn't exist — cmv coverage is in `test_commit.bats` (`:336+`). **Fixed §7** to EXTEND the real files.

Round-2 minors also applied: 9 (not 8) call sites (§2/§4/§8); `git-h-restore:27-28` "arrive in Task 8" folded into the Site 3a whole-header rewrite; `commits_ahead_behind` output-order + shallow-clone caveat in §3; header anchor reworded; grep-invariant relabeled a tripwire-not-proof; forward-target preview contradiction fixed by the direction-aware preview.

**Post-roast user corrections (spec review):**
1. **Dropped the "forward move confirms even when clean" rule** (an earlier MAJOR-#4 draft). `reset --hard`'s destructiveness comes from discarding *uncommitted* work — orthogonal to direction — so a clean-tree forward move loses nothing and is reflog-recoverable; prompting on mere surprise would dilute the gradient. Kept direction-exposure for truthful messaging/preview only; confirmation is direction-independent.
2. **`h-rewind` is NOT always danger.** The merged #231 (`head-movers-tier-unify`) model computes the tier from tracked-dirty *state*: `git-h-rewind:89-94` is warn when clean, danger only when dirty; `h-back`/`h-undo`/`h-rollback` are fixed warn (h-back/h-undo skip the prompt when clean); `cmv` is fixed danger. Fixed the §5 table's h-rewind row (clean → warn, not danger), grounded the confirmation rule in this per-state model, and added an h-rewind clean→warn §7 test. This per-state tier model is the codification of the principle in correction #1.

**Round 3 — 2026-07-30 (code-roast re-review).** No CRITICALs; three MAJORs, all in the mover messaging/preview path (the area rounds 1–2 expanded but under-enumerated). All three verified against the tree:

- **MAJOR #1** — the §5 table's h-rewind row claimed a message flip "(was 'back')", but `git-h-rewind` has NO "back" message (`:122` "Rewind HEAD to…?", `:128` "Rewinding to…", `:130` "Rewind complete"); post-fix the "Rewind" verb would lie for a forward move. **Fixed:** corrected the row and centralized the result line in a `report_head_move` helper (§5 Site 1b) that words direction truthfully — killing the verb-lie at the source.
- **MAJOR #2** — the movers' `-u` branch (`handle_upstream_operation`) converges on the SAME shared tail as the explicit-target branch (verified `git-h-back:86-130`), but the helper never emitted a direction, so the tail would print "Moved HEAD  to …" (double space). **Fixed (round 3):** `handle_upstream_operation` emits the direction on its proceed path; the `-u` path is enumerated in §5 + a §7 test. **(Round 4 superseded the mechanism:** the global was dropped in favor of threading the direction explicitly; the `-u` double-space hazard is gone structurally.)
- **MAJOR #3** — Site 1's preview block was elided ("…"), yet it holds the three range-dependent artifacts (commit list, diff stat, count/word — `hug-git-upstream:121-140`) that must flip together; that block is exactly where the motivating "changes in 0 commit:" symptom lives. **Fixed:** replaced the ellipsis with the direction-cased block (range + count chosen by direction; all three artifacts use them).

Round-3 minors also applied: squash call-site anchor `:176` (the `== 0` *test* is `:177` — §8/§10 correctly cite the branch); divergent targets labeled "diverged" with neutral wording (§3 docstring + Site 1 + §7); `lib/README.md:98` stale-predicate fix + `is_aligned` cross-refs at `:98`/`:133` (§6); the `local x=$(cmd)` exit-code-masking pitfall documented in §4. Structural choice adopted per the roast's simplification note: `report_head_move` makes the messaging path the spec's "one algorithm, N consumers" thesis instead of four prose fixes.

**Round 4 — 2026-07-30 (code-roast re-review).** Two CRITICALs + five MAJORs. The roast rated the core design sound (B+/A-) and the two CRITICALs as implementation bugs the spec's own snippets would ship. All verified before amending:

- **CRITICAL #2** — the round-3 `report_head_move` body used `&&`-chains at statement position (`[[ … ]] && word=""`), which is fragile under `set -e`, AND took a dead `mode_noun` parameter. **Adopted the structural fix:** the helper now takes the **direction as an explicit argument** (not a global) and uses `case`; the dead parameter is dropped. (Note: the roast's "crashes on diverged" claim was itself partially wrong — reproduced: the diverged path exits 0, not a crash — but the `&&`-pattern is genuinely fragile and `case` is cleaner, so the rewrite stands.)
- **CRITICAL #1** — the §4 "all 9 call sites verified safe today" claim was **false**. Verified: `git-h-files:122/:202`, `git-h-squash:167/:176`, `git-log-outgoing:92`, `git-cmv:160` are *bare* assignments (implicit globals / script-scope), not split. An implementer "tidying" any into `local x=$(strict_count)` silently re-introduces Defect 2 via `local`'s exit-code masking — a *structural* swallow no `|| echo 0` grep catches. **Fixed:** replaced the blanket claim with a per-site declaration table + a per-site strict-propagation test.
- **MAJOR #2** — the cmv non-migration (the spec's most controversial decision) cited a tail (`:222-253`) the spec never quoted. Verified the tail (`git reset --hard "$target"` + branch switch). **Fixed:** quoted the tail in §1 to close the question.
- **MAJOR #1** — the `behind`/`ahead` field names were positional-but-semantic-looking (fragile to arg-order "tidying"). **Fixed:** renamed to `field1`/`field2` at the consumer with the dependency commented.
- **MAJOR #3** — `HUG_HEAD_MOVE_DIRECTION` global: undocumented setter-before-reader contract, `set -u` footgun. **Fixed by adoption of the round-4 simplification:** **the global was dropped entirely.** `handle_standard_operation`/`handle_upstream_operation` emit the direction on stdout; movers capture and thread it explicitly to `report_head_move`. This removes the global, MAJOR #3, and the `set -u`/`set -e` bug class at the source. Cost: one redundant `git rev-list --count` (trivial).
- **MAJOR #5** — the `|| echo 0` grep tripwire was listed as an acceptance criterion despite §7 admitting it's incomplete. **Fixed:** added the **complete caller-invariant** grep as the primary criterion; demoted `|| echo 0` to a secondary canary.

The headline design change this round is **dropping the `HUG_HEAD_MOVE_DIRECTION` process-global** (3 of 4 rounds flagged global state as a liability) in favor of threading the direction explicitly — a smaller, more testable design.

**Round 5 — 2026-07-30 (code-roast re-review).** 0 CRITICALs, 6 MAJORs, 4 MINORs — all in the shell-runtime-contracts layer rounds 1–4 never stress-tested. **Four of the six were regressions my own round-4 "emit direction on stdout" change introduced**; all six verified against the tree (and one roast sub-claim re-checked, as in round 4). User confirmed the unifying fix before this revision.

- **MAJOR #1 (crux)** — round-4's `direction=$(handle_standard_operation …)` **voided the aligned guard**: `exit 0` inside `$(…)` quits only the subshell (reproduced), so the mover would proceed and move HEAD under "Already at target" — re-shipping the exact lie this audit kills. The house pattern (`… || exit $?; [[ -z "${target:-}" ]] && exit 0`) was omitted. **Fixed (unifying fix):** helpers are called **bare** again (emit nothing); the aligned `exit 0` terminates the whole mover.
- **MAJOR #2** — round-4 also collided with `handle_upstream_operation`'s documented stdout contract ("upstream commit hash", captured by 7 callers across 6 commands incl. `git-cmv:141`/`git-h-squash:165`). **Fixed:** the helper's stdout is UNCHANGED; direction is computed downstream in the mover tail.
- **MAJOR #3** — the round-4 per-site table told the implementer to "add `local`" at `git-h-files:122/:202` and `git-h-squash:167/:176`, but those are **script top-level** (only `show_help()` is a function; bash has no block scope), where `local` is **fatal** (proven: exit 1). **Fixed:** the table now distinguishes function-scope (split `local`, OK) from script-top-level (bare assignment, propagates via `set -e`; do NOT add `local`).
- **MAJOR #4** — the round-4 "complete caller-invariant" grep **cannot pass on compliant code** (verified: 12 lines — a line-grep can't classify a two-line `local x; x=$(…)` split). **Fixed:** demoted to a canary; the **per-site strict-propagation test** is the real (runtime) enforcement, and §8 credits that.
- **MAJOR #5** — the round-4 mover blueprint silently dropped `pre_op_head` + `emit_head_recovery_hint`, deleting the #222 recovery hint from all four movers. **Fixed:** the mover blueprint now shows the full tail with both preserved; §7 pins the hint.
- **MAJOR #6** — `lib/README.md:425-435` helper examples go stale unmentioned, and the §5 table under-enumerated message changes. **Fixed:** added both to the §6 docs pass.

**The unifying fix (user-confirmed): compute the direction in the mover tail.** Instead of threading direction *out of* the helpers (round-3 global, round-4 stdout — both wrong), a new `direction_between <a> <b>` wrapper (thin layer over `commits_ahead_behind`) labels the move in each mover's shared tail from `$target` + `$pre_op_head` (both already live there). Helpers keep their existing stdout contracts and `exit 0` semantics; each mover's diff shrinks to ~2 lines; MAJORs #1 and #2 die at the source. This supersedes the round-4 headline (the global is still gone, but the stdout-emission that replaced it is gone too).
