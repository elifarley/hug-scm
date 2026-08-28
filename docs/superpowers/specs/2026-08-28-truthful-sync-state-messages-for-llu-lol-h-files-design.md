# Truthful sync-state messages for `llu`, `lol`, and `h-files`

- **Date:** 2026-08-28
- **Status:** Approved design (brainstormed; user approved approach A — shared helper)
- **Scope:** `git-config/bin/git-llu`, `git-config/bin/git-log-outgoing`, `git-config/bin/git-h-files`, new function in `git-config/lib/hug-git-upstream`

## Summary

Three commands claim the branch is "up to date" / "already synced" based on an
**ahead-only** commit count. Zero commits ahead also covers "behind by N", so all
three print a false sync claim exactly when the user most needs the truth. The fix
moves detection *and* wording into one shared library function that distinguishes
**in sync** from **behind**, and adds a state marker to `llu --json`'s empty envelope.

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
| `git-llu:181-187` | `git rev-list --count @{u}..HEAD` == 0 | "(branch is up to date with …)" |
| `git-log-outgoing:96-101` | `count_commits_in_range "$target" HEAD` == 0 | "(already synced to <hash>)" |
| `git-h-files:125-129` | `count_commits_in_range "$start_point" HEAD` == 0 | "already synced to upstream" |

`A..B` counts commits reachable from B but not A — i.e. *ahead only*. A
`behind`-only branch yields 0 and falls into the "synced" branch. A diverged
branch never reaches these gates (diverged ⇒ ahead > 0).

### Precedent already in the codebase

#237/#238 fixed this exact ambiguity for the `h*` upstream family:
`commit_offset` (`git-config/lib/hug-git-commit:295`) distinguishes aligned /
ahead / behind, and `handle_upstream_operation`
(`git-config/lib/hug-git-upstream:51-68`) prints the honest two-way message
("Already synced" vs "HEAD is N commit(s) behind upstream — pull or rebase to
catch up"). `llu`, `lol`, and `h-files` predate/missed that treatment.
`git-wtsh` and `git-stats-branch` compute both directions and are correct.

## Design

### 1. New library function — `report_empty_outgoing` in `git-config/lib/hug-git-upstream`

```bash
# Usage: report_empty_outgoing <noun> <upstream_display> <target_ref>
#   <noun>             Caller's sentence start, e.g. "No outgoing commits".
#                      Emoji, if any, is part of the noun (caller-owned).
#   <upstream_display> What humans should see: "origin/main", a short hash,
#                      or "upstream".
#   <target_ref>       The ref to measure against. Never assumed to be @{u} —
#                      git-log-outgoing passes custom targets (hash or ref).
# Effect: prints to stderr (via info) exactly one of:
#   "<noun> (already synced to <upstream_display>)"
#   "<noun> (branch is behind <upstream_display> by N commits — pull or rebase to catch up)"
#   "<noun> (no outgoing commits; could not determine sync state with <upstream_display>)"
# Returns: 0 always. Message-only helper; the caller owns the exit code.
#   This keeps it errexit-safe at bare call sites (see the commit_offset
#   errexit lesson, hug-git-commit:270-277).
```

- **Measurement:** `git rev-list --count HEAD..<target_ref>` — commits in the
  target not in HEAD = behind. Computed only on the empty path; the normal
  listing path (ahead > 0) never calls the helper, so there is zero added cost
  for the common case.
- **Failure honesty:** if the count fails, print the neutral fallback — never
  silently claim "synced". That fallback is the whole point of the fix applied
  to its own error path.
- **Wording unification:** all three sites adopt the parenthetical style.
  Drops `lol`'s trailing period and `h-files`'s semicolon phrasing; no pinned
  test depends on either.

### 2. Call sites (behavior-preserving except the message)

| Site | New call | Preserved behavior |
|---|---|---|
| `git-llu` (human, empty path) | `report_empty_outgoing "📭 No outgoing commits" "$upstream" "$upstream"` | summary gate (`! quiet && unscoped → exec hug s`) unchanged; exit 0 |
| `git-log-outgoing:98-100` | `report_empty_outgoing "No outgoing changes" "$target_short" "$target"` | `exit 0` |
| `git-h-files:126-129` | `report_empty_outgoing "No local-only commits" "upstream" "$start_point"` | `exit 0` |

Exit codes stay 0 everywhere: being behind is a normal state, not an error
(consistent with `handle_upstream_operation`'s exit 0 for the behind message).

### 3. JSON contract — `llu` empty envelope only

```json
{"commits":[],"summary":{"total_commits":0,"state":"in_sync","behind_count":0}}
{"commits":[],"summary":{"total_commits":0,"state":"behind","behind_count":189}}
```

- `no_upstream` keeps its existing marker:
  `{"commits":[],"summary":{"total_commits":0,"error":"no_upstream"}}`.
- The **non-empty (ahead) envelope is unchanged.** A non-empty `commits` array
  is itself the ahead signal; extending it would drag `log_json.py` into scope
  with no consumer need (deliberate scope cut, approved).
- `--json` stays pure stdout: zero non-JSON bytes on stdout; both new envelopes
  must pass `python3 -m json.tool`.
- Human-readable output remains stderr-routed via `info`; stdout stays clean
  (hug stdout/stderr discipline).

### 4. Docs

- `git-llu` help text: "shows an informative message" section gains the behind
  mention; JSON section documents `state`/`behind_count` for the empty envelope.
- README command reference and `docs/commands/` pages: update any quoted old
  wording (verified during implementation planning, not speculatively).

## Testing

- **`tests/lib/test_hug-upstream.bats`** (new block):
  - synced repo → "(already synced to …)", message on stderr, returns 0
  - behind-by-2 → "(branch is behind … by 2 commits — pull or rebase to catch up)", returns 0
  - failing target ref → neutral fallback message (never "synced"), returns 0
- **New `tests/unit/test_llu.bats`**:
  - synced human run: truthful synced message + trailing `hug s` summary still fires
  - behind human run (commit upstream after clone): behind message, refute "synced"
  - `--json` both states: parses via `python3 -m json.tool`, correct `state` +
    `behind_count`
  - `-q`: summary suppressed in both states
- **`tests/unit/test_log_outgoing.bats`:** add a behind fixture (commit on the
  upstream side after the clone) asserting the truthful message; the two
  existing synced assertions (`:65`, `:118`) are partial-match on
  `(already synced to` and remain valid untouched.
- **h-files unit file:** add a behind-case assertion.

## Alternatives considered

- **B — inline fix per site:** smallest diff, but detection + wording copied
  three times; per-site drift is precisely what let this bug hide (three
  different spellings of the same false claim). Rejected.
- **C — reuse `commit_offset` verbatim at each site (#238 literal):** no new
  library code, but wording still triplicated, two extra git invocations per
  empty run, and each site must defend the unreachable diverged exit-2 path
  under `set -e` (the errexit trap documented at `hug-git-commit:270-277`).
  Rejected.

## Success criteria

1. On a behind-only branch, `hug llu`, `hug lol`, and `hug h-files --upstream`
   (empty-outgoing path) state the behind count and never claim synced/up to
   date.
2. `llu --json` distinguishes `in_sync` from `behind` (with `behind_count`) on
   the empty envelope; all JSON remains valid, pure stdout.
3. No behavior change on the synced path beyond the unified wording; exit codes
   unchanged (all 0); summary gate in `llu` unchanged.
4. `make test` green; new lib + unit coverage for every branch of the helper.
