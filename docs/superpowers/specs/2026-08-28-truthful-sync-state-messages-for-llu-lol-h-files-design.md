# Truthful sync-state messages for `llu`, `lol`, and `h-files`

- **Date:** 2026-08-28 (rev. 2 — roast round 1 applied: C-001..C-003, C-005..C-007)
- **Status:** Approved design (brainstormed; user approved approach A — shared helper)
- **Scope:** `git-config/bin/git-llu`, `git-config/bin/git-log-outgoing`, `git-config/bin/git-h-files`, new functions in `git-config/lib/hug-git-upstream`

## Summary

Three commands claim the branch is "up to date" / "already synced" based on an
**ahead-only** commit count. Zero commits ahead also covers "behind by N", so all
three print a false sync claim exactly when the user most needs the truth. The fix
splits sync-state detection (`sync_state_of`) from its message presentation
(`report_empty_outgoing`) in one shared library, applies it at all three sites,
and gives `llu --json`'s empty envelope three honest states: `in_sync`,
`behind`, and an error marker when the state cannot be determined.

## Problem

User-reported output (worktree behind `origin/main` by 189 commits):

```
$ hug llu
ℹ️ Info: 📭 No outgoing commits (branch is up to date with origin/main)   ← FALSE
🔴 HEAD: 026fe27b 🌿274-shc-deferred-follow-ups-…origin/main [behind 189]  ← the truth, one line later
```

The same screen asserts two opposite facts, and the false one discourages the
correct action (pull/rebase).

### Root cause

All three sites gate the "synced" message on a count of commits **ahead only**:

| Site | Gate | False claim when behind |
|---|---|---|
| `git-llu:181-193` | `git rev-list --count @{u}..HEAD` == 0 (failure swallowed by `|| echo "0"`) | "(branch is up to date with …)" |
| `git-log-outgoing:96-101` | `count_commits_in_range "$target" HEAD` == 0 | "(already synced to <hash>)" |
| `git-h-files:125-129` | `count_commits_in_range "$start_point" HEAD` == 0 | "already synced to upstream" |

`A..B` counts commits reachable from B but not A — i.e. *ahead only*. A
`behind`-only branch yields 0 and falls into the "synced" branch. A diverged
branch never reaches these gates (diverged ⇒ ahead > 0).

The failure path is also reachable, not theoretical: on an **unborn HEAD with
upstream config** (verified by execution), `git rev-parse --abbrev-ref
--symbolic-full-name @{u}` succeeds (rc=0) while both `rev-list` counts fail
(rc=128). Today `git-llu:181`'s `|| echo "0"` swallow converts that failure
into the same "up to date" lie. Any fix must keep failure distinct from zero
in *both* output channels.

### Precedent already in the codebase

#237/#238 fixed this exact ambiguity for the `h*` upstream family:
`commit_offset` (`git-config/lib/hug-git-commit:295`) distinguishes aligned /
ahead / behind, and `handle_upstream_operation`
(`git-config/lib/hug-git-upstream:51-68`) prints the honest two-way message
("Already synced" vs "HEAD is N commit(s) behind upstream — pull or rebase to
catch up"). `llu`, `lol`, and `h-files` predate/missed that treatment.
`git-wtsh` and `git-stats-branch` compute both directions and are correct —
but both model the `|| echo "0"` swallow this design must NOT copy.

## Design

### 1. New library functions in `git-config/lib/hug-git-upstream`

**Primitive — `sync_state_of <target_ref>`** (detection, single-sourced):

```bash
# Usage: sync_state_of <target_ref>
# Prints exactly one of:
#   "in_sync"        — target is an ancestor of (or equal to) HEAD
#   "behind <N>"     — HEAD is N commits behind the target (N >= 1)
#   "unknown"        — the count failed (e.g. unborn HEAD); NEVER "in_sync"
# Returns: 0 always — the state is the VALUE, not the exit code. Callers
#   capture with state=$(sync_state_of "$ref") (errexit-safe; see the
#   commit_offset errexit lesson, hug-git-commit:270-277).
# JSON consumers parse the count as ${state#behind }.
```

**Presentation — `report_empty_outgoing <noun> <upstream_display> <target_ref>`**
(thin wrapper over `sync_state_of`; wording, single-sourced):

```bash
#   <noun>             Caller's sentence start, e.g. "No outgoing commits".
#                      Emoji, if any, is part of the noun (caller-owned).
#   <upstream_display> What humans should see: "origin/main", a short hash,
#                      or the resolved upstream branch name.
#   <target_ref>       The ref to measure against. Never assumed to be @{u} —
#                      git-log-outgoing passes custom targets (hash or ref).
# Prints to stderr (via info) exactly one of:
#   "<noun> (already synced to <upstream_display>)"
#   "<noun> (branch is behind <upstream_display> by N commit|commits — pull or rebase to catch up)"
#   "<noun> (sync state with <upstream_display> could not be determined)"
# Returns: 0 always.
```

- **Measurement:** `git rev-list --count HEAD..<target_ref>` — commits in the
  target not in HEAD = behind. Computed only on the empty path; the normal
  listing path (ahead > 0) never reaches it, so there is zero added cost for
  the common case.
- **The count capture MUST use the failure-testing form:**
  `if ! behind=$(git rev-list --count "HEAD..$target_ref" 2>/dev/null); then …`
  — NOT the `|| echo "0"` swallow modeled at `git-llu:181` and
  `git-wtsh:137-138` in the same file family. Copying the swallow would map
  "failed" onto `0` ⇒ `in_sync` and silently kill the `unknown` branch
  (roast C-001).
- **Failure honesty:** `unknown` renders as a neutral fallback message and as
  a JSON error marker — never as a synced claim, in either channel. This
  fallback is the **safety net for the swallowed ahead-count at
  `git-llu:181`**: at `lol`/`h-files` the strictly-propagating ahead count
  plus ahead==0 provably resolve both endpoints, so the fallback is live only
  via `llu`'s swallow today. It must NOT be "simplified away" if `:181` is
  later fixed to propagate — it is the contract for unknown, not dead code
  (roast S2/O-008).
- **Pluralization:** behind-by-1 renders "by 1 commit" (`[[ $n -eq 1 ]]`);
  proper pluralization, not the precedent's "commit(s)" — this is new central
  wording and the cleaner form costs one line (roast C-003).
- **Composition:** the fallback parenthetical is self-contained ("sync state
  with <display> could not be determined") so it reads correctly with any
  caller noun — no self-repeat like "No outgoing changes (no outgoing
  commits; …)" (roast C-005).

### 2. Call sites (behavior-preserving except the message)

| Site | New call | Preserved behavior |
|---|---|---|
| `git-llu` (human, empty path) | `report_empty_outgoing "📭 No outgoing commits" "$upstream" "$upstream"` | summary gate (`! quiet && unscoped → exec hug s`) unchanged; exit 0 |
| `git-log-outgoing:98-100` | `report_empty_outgoing "No outgoing changes" "$target_short" "$target"` | `exit 0` |
| `git-h-files:126-129` | resolve the short upstream name first (`git for-each-ref --format='%(upstream:short)' "$(git symbolic-ref HEAD)"`, fallback `"upstream"` — same idiom as `hug-git-upstream:66`), then `report_empty_outgoing "No local-only commits" "$upstream_name" "$start_point"` | `exit 0` |

- Exit codes stay 0 everywhere: being behind is a normal state, not an error
  (consistent with `handle_upstream_operation`'s exit 0 for the behind message).
- h-files passes the **resolved branch name**, not the literal `"upstream"` —
  a behind-by-N answer must name the branch (roast C-005).
- The empty-path message always describes the **whole branch** even on scoped
  runs (`hug llu -- src/`): the range is deliberately unscoped
  (`git-llu:178-180`). Preserve, and say so in the help text.

### 3. JSON contract — `llu` empty envelope: three states

```json
{"commits":[],"summary":{"total_commits":0,"state":"in_sync","behind_count":0}}
{"commits":[],"summary":{"total_commits":0,"state":"behind","behind_count":189}}
{"commits":[],"summary":{"total_commits":0,"error":"sync_state_unknown"}}
```

- The JSON branch consumes the **primitive** (`sync_state_of`), not the
  message wrapper — detection lives in exactly one place for both channels
  (roast C-002).
- `unknown` reuses the existing error-marker convention already present for
  `no_upstream` (`git-llu:163`) — there is no conformant `state` value for a
  failed measurement, and emitting `in_sync`/`behind_count:0` there would be
  the exact false sync claim this spec kills, relocated into the machine
  channel (roast C-001).
- `no_upstream` keeps its existing marker:
  `{"commits":[],"summary":{"total_commits":0,"error":"no_upstream"}}`.
- The **non-empty (ahead) envelope is unchanged.** A non-empty `commits` array
  is itself the ahead signal; extending it would drag `log_json.py` into scope
  with no consumer need (deliberate scope cut, approved). Known consequence:
  divergence stays undetectable in the non-empty envelope — candidate
  follow-up issue, not in scope here (roast O-001).
- `--json` stays pure stdout: zero non-JSON bytes on stdout; all three
  envelopes must pass `python3 -m json.tool`.
- Human-readable output remains stderr-routed via `info`; stdout stays clean
  (hug stdout/stderr discipline). Quiet (`-q`/`HUG_QUIET`) suppresses the
  message per `info`'s normal semantics (hug-output:66-79); the summary gate
  is orthogonal and unchanged.

### 4. Docs

- `git-llu` help text: "shows an informative message" section gains the behind
  and unknown mentions; JSON section documents `state`/`behind_count` and the
  `sync_state_unknown` error marker for the empty envelope; scoped-run runs
  state that the empty-path message describes the whole branch.
- **Superseding note for `docs/superpowers/specs/2026-07-29-count-commits-in-range-audit-design.md`:**
  that audit's SAFE verdicts for `git-log-outgoing:92` (:185) and
  `git-h-files:122` (:186) — "`== 0` IS the correct 'already synced'
  semantic" — were about exit-code *propagation* and remain valid on that
  dimension; their message-truthfulness claim is **superseded** by this spec
  and by #237/#238 (a behind-only branch yields `== 0` too; verified by
  execution). The note lives in this spec's change-set and as a short
  superseded-marker in that doc, so a future grep for "already synced" never
  finds two authoritative-looking, opposite answers without direction
  (roast C-007).
- README command reference and `docs/commands/` pages: update any quoted old
  wording (verified during implementation planning, not speculatively).

## Testing

- **`tests/lib/test_hug-upstream.bats`** (new block):
  - `sync_state_of`: in_sync → `in_sync`; behind-by-2 → `behind 2`; failing
    target ref → `unknown`; returns 0 in all three.
  - `report_empty_outgoing`: synced message; behind-by-2 message with count;
    **behind-by-1 renders "by 1 commit"** (pluralization pin, roast C-003);
    failure → self-contained fallback that composes with a caller noun
    without repeating it; all messages on stderr, return 0.
- **New `tests/unit/test_llu.bats`**:
  - synced human run: truthful synced message + trailing `hug s` summary still fires
  - behind human run (commit upstream after clone): behind message, refute "synced"
  - `--json` in_sync and behind: parse via `python3 -m json.tool`, correct
    `state` + `behind_count`
  - `--json` **unknown** (unborn HEAD + direct upstream config — the
    `--set-upstream-to` path refuses unborn branches): parses, carries
    `"error":"sync_state_unknown"`, no `state` key (roast C-001)
  - `-q`: message suppressed (info/HUG_QUIET semantics), summary suppressed;
    without `-q` both present — pins message-vs-quiet semantics in both
    states (roast O-006)
- **`tests/unit/test_log_outgoing.bats`:** add a behind fixture (commit on the
  upstream side after the clone) asserting the truthful message; the two
  existing synced assertions (`:65`, `:118`) are partial-match on
  `(already synced to` and remain valid untouched.
- **`tests/unit/test_head.bats`** — the `hug h files` block (~:1590; there is
  no dedicated h-files unit file, coverage is colocated here): add a
  behind-case assertion (roast C-006).

## Alternatives considered

- **B — inline fix per site:** smallest diff, but detection + wording copied
  three times; per-site drift is precisely what let this bug hide (three
  different spellings of the same false claim). Rejected.
- **C — reuse `commit_offset` verbatim at each site (#238 literal):** no new
  library code, but wording still triplicated, two extra git invocations per
  empty run, and each site must defend the unreachable diverged exit-2 path
  under `set -e` (the errexit trap documented at `hug-git-commit:270-277`).
  Rejected. (`commit_offset` appears in this design only here, as the
  rejected alternative — the built design needs only `sync_state_of`.)

## Success criteria

1. On a behind-only branch, `hug llu`, `hug lol`, and `hug h files -u`
   (empty-outgoing path) state the behind count (singular-correct) and never
   claim synced/up to date.
2. `llu --json` distinguishes `in_sync` from `behind` (with `behind_count`) on
   the empty envelope, and renders a failed measurement as
   `"error":"sync_state_unknown"` — **never** as `in_sync`. All JSON remains
   valid, pure stdout.
3. No behavior change on the synced path beyond the unified wording; exit codes
   unchanged (all 0); summary gate in `llu` unchanged.
4. `make test` green; new lib + unit coverage for every branch of the helper —
   including the `unknown` branch in both the human and JSON channels.
