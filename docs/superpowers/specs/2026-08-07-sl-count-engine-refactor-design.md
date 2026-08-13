# Design: `sl* -c` count engine refactor — `run_count_mode` wrapper + `check_git_repo` parity

**Issues:** [elifarley/hug-scm#258](https://github.com/elifarley/hug-scm/issues/258),
[elifarley/hug-scm#259](https://github.com/elifarley/hug-scm/issues/259)
**Tracked from:** PR [elifarley/hug-scm#257](https://github.com/elifarley/hug-scm/pull/257) (v1.7.0, the `-c/--count` feature)
**Branch:** `refactor-sl-count-engine-258-259`
**Date:** 2026-08-07

## Summary

Two tech-debt follow-ups from the `-c/--count` feature, batched into one design +
one PR because both touch the same file (`git-config/lib/hug-select-files`) and the
same test file, and they compose: #259 hardens the count *primitive*, #258 wraps it.

- **#258:** The `-c/--count` dispatch block (mutual-exclusion guard + `count_files_with_status`
  call + `exit 0`, ~14 lines) plus its ~7-line WHY comment are duplicated near-verbatim
  across the 6 `sl*` dispatchers that implement `-c` locally — `git-sls`, `git-slu`,
  `git-slk`, `git-sli`, `git-slc`, `git-statusbase`. Only the state argument differs in the
  5 single-state scripts; `git-statusbase` additionally branches `all` vs `all+untracked`
  on `$include_untracked` (and carries an extra dedup note). Factor the shared logic into
  a single `run_count_mode` helper.
- **#259:** `count_files_with_status` (the `sl* -c` engine) does not call `check_git_repo`,
  unlike every `list_*_files` function in `hug-git-files`. All current `sl*` callers
  validate at the top of their script, so the gap is defended in practice — but a direct
  library caller outside a repo gets a **silent wrong answer** (`0`, exit 0) when not under
  `set -e`, or a **silent crash** (no output, no diagnostic, exit 128) when under
  `set -euo pipefail` — because every `git` call in `count_files_with_status` is suffixed
  `2>/dev/null`, suppressing git's own error. Neither is a "raw git error"; both are *worse*
  (no diagnostic at all). Add `check_git_repo` for parity with `list_*_files`, which emits
  the clean HUG "Not in a git repository" message. (Verified empirically from `/tmp` —
  see Roast hardening §F-003.)

## Decisions (settled during brainstorming)

| Decision | Choice | Rationale |
|---|---|---|
| **#259 approach** | Unconditional `check_git_repo` as the first line of `count_files_with_status` | Matches the `list_*_files` contract; simplest. `count_files_with_status` already spawns ≥1 git subprocess per call, so one extra `git rev-parse --git-dir` is negligible. A cached-sentinel guard adds state to a pure helper for a micro-optimization — YAGNI. Guarding in `run_count_mode` only does **not** meet #259's acceptance (a direct library caller still gets a silent wrong answer / silent crash, not the clean HUG message). |
| **#259 dependency (`check_git_repo` availability)** | Declare `hug-git-repo` in `hug-select-files`'s `Depends on:` header; do **not** auto-source it | `count_files_with_status` lives in `hug-select-files` (the shared `hug-common` bundle), while its `list_*_files` siblings live in `hug-git-files` (the `hug-git-kit` bundle, which co-loads `hug-git-repo`). All 6 `sl*` dispatchers source `hug-git-kit`, so `check_git_repo` is available to every real caller — #259's acceptance is met. Auto-sourcing `hug-git-repo` inside `hug-select-files` was **rejected** on VCS-boundary grounds: `hug-common` is symlinked into `hg-config`, so `hug-select-files` already loads in Mercurial contexts, and injecting the git-specific `check_git_repo` (which calls `git rev-parse`) there is wrong. Adding `hug-git-repo` to `hug-common`'s bundle is rejected for the same reason (shared bundle, git-specific dep). See Roast hardening §F-001. |
| **Scope & PR shape** | One combined design, one PR | Both touch `hug-select-files` + `test_hug-select-files.bats`; #258's wrapper delegates to #259's hardened primitive. Matches the repo's batch precedent (visibility batch #207+#208, head-mover correctness batch). |
| **Implementation order** | #259 first, then #258 | Forced: the wrapper delegates to the primitive, so the primitive must carry the invariant first. |

## Architecture

Single library module, two stacked edits, no new files.

```
git-config/lib/hug-select-files
  ├── run_count_mode [--json] <state> [pathspec...]   # NEW (#258) — terminating wrapper
  └── count_files_with_status <state> [pathspec...]   # MODIFIED (#259) — +check_git_repo first line

git-config/bin/git-sls        # MODIFIED — 14-line block → 1-line call (state: staged)
git-config/bin/git-slu        # MODIFIED — (state: unstaged)
git-config/bin/git-slk        # MODIFIED — (state: untracked)
git-config/bin/git-sli        # MODIFIED — (state: ignored)
git-config/bin/git-slc        # MODIFIED — (state: conflicted)
git-config/bin/git-statusbase # MODIFIED — (state: all / all+untracked, branch on $include_untracked)

git-config/lib/README.md      # MODIFIED — add run_count_mode entry + amend count_files_with_status contract (doc-perimeter)

# sl / sla delegate to git-statusbase via .gitconfig aliases → covered transitively, no own copy.
```

`hug-select-files` is sourced by all 6 dispatchers alongside `hug-common hug-git-kit`
(they source `hug-common hug-git-kit hug-select-files output_json_status`). The two
functions this design touches enter through **different** aggregator modules:

- `error` (used by the existing unknown-state branch, line ~106, and by the new
  `--json` mutex check) is defined in `hug-output`, loaded by **`hug-common`** (line 83 of
  `hug-common`'s `_hug_common_libs`).
- `check_git_repo` (new, #259) is defined in `hug-git-repo`, loaded by **`hug-git-kit`**
  (line 30 of `hug-git-kit`'s module loop). `hug-common` does **not** load `hug-git-repo`.

Both are in scope wherever `count_files_with_status` runs *in production*, because every
`sl*` dispatcher sources both `hug-common` and `hug-git-kit`.

**Structural asymmetry (root of F-001):** `count_files_with_status` lives in
`hug-select-files`, which is bundled in the **shared** `hug-common` (`_hug_common_libs`,
line 90). Its `list_*_files` siblings live in `hug-git-files`, bundled in `hug-git-kit`
(which co-loads `hug-git-repo` in the same loop). So `list_*_files` gets `check_git_repo`
for free from its bundle; `count_files_with_status` does not — its bundle (`hug-common`)
doesn't carry `hug-git-repo`. The fix is to **declare** `hug-git-repo` in `hug-select-files`'s
`Depends on:` header (line 5) so the new dependency is honest and discoverable, matching the
codebase convention (modules declare deps; the caller sources them — `git-g` itself sources
`hug-git-repo` explicitly at line 13 for exactly this reason). We do **not** auto-source
`hug-git-repo` from `hug-select-files`: `hug-common` is symlinked into `hg-config/lib`, so
`hug-select-files` already loads in Mercurial contexts, and defensively sourcing the
git-specific `hug-git-repo` (whose `check_git_repo` calls `git rev-parse`) there would
inject git-only semantics into the hg path. See Roast hardening §F-001 for the rejected
alternatives.

## Section 1 — `count_files_with_status` parity (#259)

Insert `check_git_repo` as the first executable line of `count_files_with_status()`,
before arg parsing. This replaces the current non-repo behavior — a **silent wrong answer**
(`0`, exit 0) without `set -e`, or a **silent crash** (no output, no diagnostic, exit 128)
with `set -euo pipefail`, because every `git` call is suffixed `2>/dev/null` — with the
clean HUG "Not in a git repository" message (verified empirically; see §F-003).

Two header-comment edits in the same file:
- The `Depends on:` line (line 5): append `hug-git-repo (for check_git_repo)` — declares the
  new dependency honestly (see Architecture / §F-001).
- The function-list block (lines 6-9): note the repo precondition is now enforced internally
  (matching `list_*_files`).

```bash
count_files_with_status() {
  check_git_repo   # Parity with list_*_files: clean HUG error from any context (#259)
  local state="$1"
  shift
  local -a pathspecs=("$@")
  local count=0
  ...
}
```

**Why the first line, before arg parsing:** mirrors `list_*_files` (which calls
`check_git_repo` early) and fails fast with the clean message before spending a
subprocess on a doomed count. `check_git_repo`'s `error`→`exit 1` propagates from any
call context (top-level script, or a `run` subshell in tests); when the caller already
validated, the single `git rev-parse --git-dir` is a no-op pass. No behavior change for
any existing in-repo caller — the entire `sl* -c` test suite cds into a repo first.

**Availability of `check_git_repo`:** provided by `hug-git-repo`, which all 6 `sl*`
dispatchers load via `hug-git-kit`. A caller that sources only `hug-common` (which loads
`hug-select-files` but not `hug-git-repo`) must source `hug-git-repo` itself, as the
`Depends on:` header now declares — the same contract every other module in this codebase
uses (callers source declared deps; `git-g` does this explicitly at line 13). #259's
acceptance is met for every real caller.

## Section 2 — `run_count_mode` wrapper (#258)

Add directly above `count_files_with_status` in `hug-select-files`:

```bash
# run_count_mode — terminating wrapper for the sl* -c/--count dispatch.
# Usage: run_count_mode [--json] <state> [pathspec...]
#   <state>: the count_files_with_status enum (staged|unstaged|untracked|ignored|
#           conflicted|all|all+untracked).
# Encapsulates the -c dispatch previously duplicated (near-verbatim) across the 6 sl*
# scripts (git-sls/slu/slk/sli/slc/statusbase):
#   (1) --json is mutually exclusive with -c → error + exit (like hug wtl's
#       --json --path-only error),
#   (2) delegate to count_files_with_status (which itself enforces the repo
#       precondition — #259),
#   (3) exit 0.
# TERMINATING: calls `exit 0` (and `error`→exit 1 on the --json violation), so it
#   NEVER returns — a caller running it inside `if $count_only; then ...; fi` never
#   reaches code below the block. Callers pass `--json` only when their json flag is
#   true, e.g. `if $json_output; then run_count_mode --json <state> ...; else
#   run_count_mode <state> ...; fi`. Do NOT use ${json_output:+--json}: hug stores
#   booleans as the strings true/false, so :+ fires on the non-empty "false" too and
#   would ALWAYS pass --json (making every -c invocation error as mutually exclusive).
#   Do NOT capture this in $(...) : the subshell exit is contained and the count is
#   captured correctly, but the caller does NOT terminate — in the dispatchers,
#   execution falls through to the listing/summary code and prints BOTH the (captured)
#   count AND the listing (broken output). Call it as a statement, never as a substitution.
run_count_mode() {
  local json=false
  [[ "${1:-}" == --json ]] && { json=true; shift; }
  local state="$1"; shift
  local -a pathspecs=("$@")
  if $json; then
    error "-c/--count and --json are mutually exclusive"
  fi
  count_files_with_status "$state" "${pathspecs[@]}"
  exit 0
}
```

### Contract decisions

- **`--json` as a flag, passed via the two-branch `if $json_output` idiom** — the caller
  writes `if $json_output; then run_count_mode --json <state> ...; else run_count_mode
  <state> ...; fi` (the codebase's established conditional-flag pattern, e.g.
  git-statusbase's own `if $include_untracked; then list_opts+=(--untracked); fi`). The
  mutual-exclusion check lives inside the helper, so it cannot drift across the 6 sites.
  **Do NOT use `${json_output:+--json}`** — hug stores booleans as the strings
  `"true"`/`"false"`, so `:+` fires on the non-empty `"false"` too and would ALWAYS pass
  `--json` (every `-c` invocation would error as mutually exclusive). This was a defect in
  earlier drafts of this spec (caught by TDD when all 16 `sl* -c` tests failed; missed by
  3 roast rounds). See §Implementation note (json-flag idiom) below.
- **Terminating (`exit 0`)** — matches #258's "(3) the exit 0" and the original blocks.
  Callers are top-level scripts that intend to terminate; none capture `run_count_mode`
  in `$(...)`. The helper **always exits** (error→exit 1 on the `--json` violation, exit 0
  on success) — a uniform "never returns" contract, which is clearer than a mixed
  "exits on error, returns on success." A non-terminating variant (helper returns, each
  call site adds `; exit 0`) was **considered and rejected**: it trades the benign
  `$(...)`-capture case (which returns the *correct* count, just non-terminating) for a
  *worse* footgun — a forgotten `exit 0` at any of the 6 call sites would print the count
  AND then fall through to the listing/summary code (broken output). The terminating
  design eliminates that failure mode; the project already has terminating helpers
  (`handle_upstream_operation` `exit 0`s internally). See Roast hardening §F-005.
- **`local` is safe here** — this is a real function body (unlike the dispatcher
  top-level code), so `local` is legal under `set -euo pipefail`. The cerebrum's
  "local at top level is a fatal bash error" warning applies only to the dispatcher
  scripts' top-level code, not to this function.
- **Bash-floor safety** — `local -a pathspecs=("$@")` declares the array, so
  `"${pathspecs[@]}"` is safe under `set -u` even when empty, exactly as in the existing
  `count_files_with_status` (declared arrays are "set" even when empty).
- **Module header hygiene** — add `run_count_mode` to the function list in the
  `hug-select-files` header comment (lines 1-9) alongside `count_files_with_status`.

## Section 3 — Call-site transformation (6 dispatchers)

The WHY comment (currently ~7 lines, duplicated 6×) moves into `run_count_mode`'s
docblock (Section 2). Each call site keeps a one-line pointer. Note: `git-statusbase`'s
extra comment about `all`/`all+untracked` dedup (one MM record) is **relocated, not
dropped** — that rationale already lives in `count_files_with_status`'s header (lines
14-15) and is summarized in the helper's docblock; a reviewer comparing diffs should read
it as a move, not a deletion.

### 5 single-state dispatchers

`git-sls` (staged), `git-slu` (unstaged), `git-slk` (untracked), `git-sli` (ignored),
`git-slc` (conflicted) — identical shape. Example, `git-sls`:

Before (~14-line block + ~7-line comment):
```bash
# Count mode: print the number of matching files (the grep -c of listings).
# NUL-safe + Bash-4.0-safe via count_files_with_status (hug-select-files):
# counts git's NUL-delimited records, so newline-containing filenames count
# once, and no `local -n` nameref (Bash 4.3+) is reached. The count is the
# whole answer: it suppresses the trailing summary and is mutually exclusive
# with --json (like `hug wtl`'s --json --path-only error).
if $count_only; then
  if $json_output; then
    error "-c/--count and --json are mutually exclusive"
  fi
  count_files_with_status staged "${pathspecs[@]}"
  exit 0
fi
```

After:
```bash
# Count mode: -c/--count dispatch (see run_count_mode in hug-select-files).
if $count_only; then
  if $json_output; then
    run_count_mode --json staged "${pathspecs[@]}"
  else
    run_count_mode staged "${pathspecs[@]}"
  fi
fi
```

### `git-statusbase` (branches `all` vs `all+untracked`)

Keeps its existing `if $include_untracked` if/else, swapping the inner guard+exit for
`run_count_mode`. No `local` (top-level, `set -e` footgun), so a scratch var `_slc_state`
selects `all+untracked` vs `all`, then the same two-branch over `$json_output`:

```bash
# Count mode: -c/--count dispatch (see run_count_mode in hug-select-files).
if $count_only; then
  if $include_untracked; then _slc_state=all+untracked; else _slc_state=all; fi
  if $json_output; then
    run_count_mode --json "$_slc_state" "${pathspecs[@]}"
  else
    run_count_mode "$_slc_state" "${pathspecs[@]}"
  fi
fi
```

(`sl` / `sla` are `.gitconfig` aliases to `git-statusbase`, so they are covered
transitively — no own copy to touch, exactly as #258 notes.)

## Section 4 — Tests & verification

### No-regression (existing tests, unchanged)

- `tests/lib/test_hug-select-files.bats` lines 757+: per-state counts, dedup, pathspec
  scoping, NUL-safety, rename handling, untracked-dir expansion. All `cd "$repo"` first,
  so the new `check_git_repo` passes and they stay green unchanged.
- `tests/unit/test_status_staging.bats`: the `sl* -c` unit tests — including
  `hug slc -c: -c + --json errors (mutually exclusive)` (line 1953), `hug slk -c: counts
  a newline-containing filename once (NUL-safe)` (line 1966), and the `slu -c` pathspec
  test (line 1981) — pin the contract end-to-end and stay green.

### New test for #259

In `test_hug-select-files.bats`, next to the `count_files_with_status` block. Uses a
fresh `mktemp -d` (not `cd /tmp`) so the "not a repo" precondition is deterministic even on
machines where `/tmp` is versioned:

```bash
@test "count_files_with_status: clean error outside a git repo (parity with list_*_files)" {
  local nonrepo
  nonrepo=$(mktemp -d)   # fresh, guaranteed non-repo (setup() cds into a repo; leave it)
  cd "$nonrepo"
  run --separate-stderr count_files_with_status staged
  assert_failure
  [[ -z "$output" ]]                                  # stdout clean: no leaked count (the old silent-0)
  [[ "$stderr" == *"Not in a git repository"* ]]      # stderr carries the clean HUG message
  rm -rf "$nonrepo"
}
```

Uses `run --separate-stderr` (BATS ≥1.6; the repo already uses it at
`test_status_staging.bats:1947`) so the two halves of the acceptance — "no silent `0` on
stdout" and "the clean message on stderr" — are pinned **independently**. (`gum_log`
writes `>&2`, so the message lands on stderr; `check_git_repo` is the first executable line
and `error`→`exit 1` runs before any `printf '%d\n'`, so stdout is structurally empty on
the error path.) `error` is in scope via `hug-common` (line 5 → `hug-output`);
`check_git_repo` via `hug-git-kit` (line 6 → `hug-git-repo`); `run` runs in a subshell that
inherits the sourced function and contains the `error`→`exit 1`.

### Optional end-to-end test (only if it does not duplicate the lib test)

A `hug sls -c` from a fresh `mktemp -d` dir asserting the same "Not in a git repository"
message — confirms the wrapper + primitive compose end-to-end. Add **only** if it proves
cheaper than it is duplicative; the lib test above is the load-bearing one for #259's
acceptance.

### Doc-perimeter — `git-config/lib/README.md` (#259/#258 contract) — F-004

`git-config/lib/README.md:202` documents `count_files_with_status` as a public library
function (CLAUDE.md points readers here for library docs). It goes stale the moment this
PR lands, so the change-set includes:

- A new entry for `run_count_mode [--json] <state> [pathspec...]` next to the
  `count_files_with_status` entry — describe it as the terminating dispatch wrapper that
  encapsulates the mutual-exclusion guard + count + exit 0 (formerly duplicated across the
  6 `sl*` dispatchers).
- Amend the `count_files_with_status` entry to note it now enforces the repo precondition
  internally (exits 1 with "Not in a git repository" outside a repo), matching the
  `list_*_files` contract documented alongside it.

User-facing command docs (`docs/commands/status-staging.md`) and `CHANGELOG.md` do **not**
need updates — the user-facing `-c` behavior is unchanged; only the internal library
surface changes.

### Verify commands

```bash
make test-lib TEST_FILE=test_hug-select-files.bats TEST_SHOW_ALL_RESULTS=1
make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="-c" TEST_SHOW_ALL_RESULTS=1
make sanitize   # shellcheck: run_count_mode's local usage + the 6 call-site edits
make test       # full suite before commit
```

## Acceptance criteria

Mapped to the two issues:

- **#258:**
  - [ ] Single source of truth for the `-c` dispatch logic (1 `run_count_mode` helper,
        6 one-line call sites).
  - [ ] The ~7-line WHY comment lives once in `run_count_mode`'s docblock; call sites
        carry a one-line pointer.
  - [ ] All `sl* -c` behavior unchanged (pinned by the existing `sl* -c` unit tests,
        which stay green without modification).
- **#259:**
  - [ ] `count_files_with_status` calls `check_git_repo` as its first line.
  - [ ] `hug-select-files`'s `Depends on:` header (line 5) declares `hug-git-repo` (F-001).
  - [ ] `count_files_with_status` from a non-repo directory emits the HUG "Not in a git
        repository" message, not a silent `0`/silent crash (new lib test, `mktemp -d`).
  - [ ] No regression to in-repo `count_files_with_status` callers (existing lib tests
        green unchanged).
- **Both (documentation perimeter):**
  - [ ] `git-config/lib/README.md:202` gains a `run_count_mode` entry and an amended
        `count_files_with_status` contract note (now enforces the repo precondition) (F-004).
  - [ ] `hug-select-files`'s in-file header comment lists `run_count_mode` in its function
        list (lines 6-9) and notes the repo precondition.

## Out of scope (YAGNI)

- A cached "already-validated" sentinel to avoid the extra `git rev-parse` on repeat
  calls — rejected during brainstorming; the cost is negligible and the sentinel adds
  state to a pure helper.
- Moving `check_git_repo` into `run_count_mode` only — rejected; does not satisfy #259's
  acceptance for direct library callers.
- **Auto-sourcing `hug-git-repo` from `hug-select-files`** (F-001) — rejected on
  VCS-boundary grounds: `hug-common` is symlinked into `hg-config/lib`, so
  `hug-select-files` already loads in Mercurial contexts; defensively sourcing the
  git-specific `hug-git-repo` (whose `check_git_repo` calls `git rev-parse`) would inject
  git-only semantics into the hg path. Declaring the dep in the header (the chosen fix) is
  sufficient because every real caller sources `hug-git-kit`.
- **Adding `hug-git-repo` to `hug-common`'s `_hug_common_libs`** — rejected; same
  VCS-boundary reason (shared bundle, git-specific dep).
- **Moving `count_files_with_status`/`run_count_mode` into `hug-git-files`** (the
  `hug-git-kit` bundle, for true co-load parity with `list_*_files`) — considered; would
  remove a git-specific function from the shared `hug-common` bundle. Rejected as
  scope-creep beyond #258/#259 (it would relocate the function and its tests and contradict
  #258's stated location, "next to `count_files_with_status` in `hug-select-files`").
- Refactoring the `sl*` JSON/listing paths (out of scope; only the `-c` dispatch is
  factored).
- Touching `sl`/`sla` directly (they delegate via aliases).
- **`--json`/pathspec arg-parsing hardening** (roast MINOR 4) — `run_count_mode`'s
  `--json` detection is position-only (`$1`), and the 6 dispatcher `case` blocks don't
  honor `--` as a pathspec separator (a pre-existing limitation: a pathspec literally named
  `--json` is consumed as the flag before it can reach the count logic). Both are
  pre-existing and independent of this refactor; tracked as
  [elifarley/hug-scm#260](https://github.com/elifarley/hug-scm/issues/260) (separate PR).

## Risks

- **Top-level `local` footgun:** the `git-statusbase` branch must not introduce a
  `local state=...` at script top level (fatal under `set -euo pipefail`). The design
  inlines the state in two `run_count_mode` calls instead. The `git-sls` family is
  unaffected (single state, no temp var).
- **Terminating helper captured via `$(...)`:** if a future caller captures
  `run_count_mode` in command substitution, `exit 0` only exits the subshell and the
  caller continues — the count is captured correctly (NOT a wrong number), but the caller
  does not terminate, so in the dispatchers execution falls through to the
  listing/summary code and prints BOTH the count AND the listing (broken output — the
  same broken-output shape as a forgotten `exit 0`, but reachable only by violating the
  "never capture" contract, i.e. 1 chance vs the non-terminating alternative's 6
  call-sites). The docblock flags this and the contract is "call as a statement, never
  capture." The terminating design is preferred because it makes the failure-free path the
  default (0 forgotten-`exit 0` sites); the non-terminating alternative has 6. (The two
  roast reports split on this: one rated it an acceptable Minor, the other a Major
  recommending the non-terminating redesign; verified analysis supports keeping
  terminating — see §F-005.)
- **`--json` flag parsing vs. pathspecs starting with `--`:** a pathspec literally named
  `--json` would be mis-read as the flag. This is already broken upstream (the
  dispatchers' `case` collects anything not matching `--json`/`-c`/`-q` as a pathspec, so
  a real `--json` pathspec can't reach `run_count_mode` anyway). No new exposure.

## Roast hardening (dual-voice resolution)

This spec was roasted twice (`--spec` mode). Each finding was verified against ground
truth in the worktree before acting; the two reviewers disagreed on one point (F-005),
resolved by analysis rather than by majority. Findings and dispositions:

### F-001 — Undeclared cross-module dependency (`check_git_repo`) — FIXED (declare-only)

**Claim:** `count_files_with_status` lives in `hug-select-files` (loaded by the shared
`hug-common`), but `check_git_repo` lives in `hug-git-repo` (loaded only by `hug-git-kit`).
A `hug-common`-only caller would get `check_git_repo: command not found`.

**Verified:**
- `hug-common`'s `_hug_common_libs` (lines 80-93) lists `hug-output` (→`error`) and
  `hug-select-files` (→`count_files_with_status`) but NOT `hug-git-repo`.
- `hug-git-kit`'s loop (line 30) loads `hug-git-repo` (and does NOT load `hug-output`).
- Sourcing `hug-common` alone: `error` ✓ defined, `count_files_with_status` ✓ defined,
  `check_git_repo` ✗ NOT defined (empirically confirmed).
- Root cause is a bundle asymmetry: `list_*_files` sits in `hug-git-files` (hug-git-kit
  bundle → `hug-git-repo` co-loaded); `count_files_with_status` sits in `hug-select-files`
  (hug-common bundle → `hug-git-repo` NOT co-loaded).

**Fix:** Declare `hug-git-repo` in `hug-select-files`'s `Depends on:` header (line 5). All
6 `sl*` dispatchers source `hug-git-kit`, so `check_git_repo` is available to every real
caller and #259's acceptance holds.

**Rejected alternatives (VCS-boundary):** defensively auto-sourcing `hug-git-repo` inside
`hug-select-files`, and adding `hug-git-repo` to `hug-common`'s bundle — both rejected
because `hug-config/lib/hug-common` is a **symlink** to `git-config/lib/hug-common`, so
`hug-select-files` already loads in Mercurial contexts; injecting the git-specific
`check_git_repo` (which calls `git rev-parse`) there is a VCS-boundary violation. (A third
alternative — moving `count_files_with_status` into `hug-git-files` for true co-load parity
— was rejected as scope-creep.)

### F-002 — Factual error in the dependency-chain rationale — FIXED

**Claim:** The spec said `hug-git-kit` aggregates `hug-output` (provides `error`). It does
not. `error` reaches the dispatchers via `hug-common` (→ `hug-output`, loaded at
`hug-common:83`); `check_git_repo` via `hug-git-kit` (→ `hug-git-repo`, loaded at
`hug-git-kit:30`). Corrected in the Architecture section and the test section. (The roast's
aside that `git-g` "sources only `hug-common`" was itself inaccurate — `git-g` sources
`hug-git-repo` explicitly at line 13 — but the core finding holds.)

### F-003 — Inaccurate "raw git error" description — FIXED

**Claim:** The current non-repo behavior is not "a raw git error"; every `git` call in
`count_files_with_status` is suffixed `2>/dev/null`, suppressing git's stderr.

**Verified empirically from `/tmp`:**
- Without `set -e`: `count_files_with_status staged` → `stdout=0`, `rc=0`, empty stderr
  (silent wrong answer).
- With `set -euo pipefail`: the `git status` pipeline returns 128, `set -e` kills the
  shell, `2>/dev/null` ate the diagnostic → no output, no message, exit 128 (silent crash).

Corrected throughout the spec. This **strengthens** #259: the bug is silent-wrong/silent-
crash, worse than the cosmetic "raw git error" the issue body implied.

### F-004 — Doc-perimeter omission (`git-config/lib/README.md`) — FIXED

**Claim:** `git-config/lib/README.md:202` documents `count_files_with_status`; the
change-set omitted it. Verified: the README lists the primitive with its state enum and
NUL/Bash-floor guarantees. Added to the change-set (Section 4 "Doc-perimeter" + the
Architecture diagram + acceptance): a new `run_count_mode` entry and an amended
`count_files_with_status` contract note (now enforces the repo precondition).

### F-005 — Terminating helper `exit 0` is context-dependent — ADDRESSED (kept, refuted redesign)

**Claim:** `exit 0` inside a helper is a Bash footgun: terminating when called as a
statement, non-terminating when captured in `$(...)`. The two roast reports disagreed
(one: acceptable Minor; one: Major, recommending a non-terminating core + `; exit 0` at
call sites).

**Verified analysis (kept terminating):**
- A `$(...)` capture of `run_count_mode` returns the **correct** count (the subshell's
  stdout is captured); the caller simply does not terminate. That is a *benign*
  non-termination, not a wrong number.
- The non-terminating alternative trades this benign case for a *worse* footgun: a
  forgotten `exit 0` at any of the 6 call sites would print the count AND fall through to
  the listing/summary code (broken output). The terminating design makes the failure-free
  path the default.
- The project already has terminating helpers (`handle_upstream_operation` `exit 0`s
  internally, per cerebrum).

### Implementation note — the json-flag idiom (TDD-caught defect, post-roast)

Early drafts of this spec (and the plan transcribed from it) prescribed passing `--json`
at the call sites via `${json_output:+--json}`. That idiom is **broken** in this codebase:
hug stores booleans as the literal strings `"true"`/`"false"`, and `${var:+word}` fires on
ANY non-empty value — so `${json_output:+--json}` ALWAYS expands to `--json` (even when
`json_output="false"`), making every `hug sl* -c` error as "mutually exclusive." This was
caught by TDD during Task 3 (all 16 `sl* -c` unit tests failed on the first run with the
`: +` form) — a defect that **3 spec-roast rounds missed** (the roasts verified the
function body but not the call-site expansion semantics against the codebase's boolean
convention). Corrected to the two-branch `if $json_output; then run_count_mode --json
<state> ...; else run_count_mode <state> ...; fi` idiom — the codebase's established
conditional-flag pattern (e.g. `git-statusbase`'s own `if $include_untracked; then
list_opts+=(--untracked); fi`), which is regression-proof (no one will "simplify" an
obvious two-branch back to `:+`). The `run_count_mode` docblock carries the "Do NOT use
${json_output:+--json}" warning with the rationale. `run_count_mode`'s `[--json] <state>
[pathspec...]` interface is UNCHANGED (consistent with the codebase's flag-based library
functions like `list_files_with_status --staged`). Lesson: when a spec proposes a shell
parameter-expansion idiom for conditionally passing a flag, verify it against how the
codebase actually stores the controlling boolean — `${var:+word}` and a true/false-string
boolean are a footgun combination.

**Disposition:** kept the terminating helper; sharpened the docblock (the `$(...)`-capture
behavior is now explicit) and the Risks section. The "always exits, never returns"
contract is uniform (error→exit 1 on the mutex violation, exit 0 on success).

### Minors — addressed
- `cd /tmp` in the new test → `mktemp -d` (deterministic even if `/tmp` is versioned).
- "Duplicated verbatim" → "duplicated near-verbatim" (statusbase has an extra branch +
  dedup note).
- Trimmed the docblock's "Why NUL-delimited + Bash-4.0-safe" pointer (duplicates the
  primitive's own header, one `grep` away).
- Noted the `git-statusbase` dedup comment is relocated (to the primitive's header /
  helper docblock), not dropped — so a reviewer reads the diff as a move.

### Re-roast (round 3) — no CRITICAL/MAJOR; four MINORs addressed

A third `--spec` roast re-verified every load-bearing claim (F-001–F-005 all survived) and
returned **no CRITICAL or MAJOR issues** — the spec was ready to proceed to the plan. Four
MINORs, all addressed in this commit:

- **M1 (test polish):** the #259 test now uses `run --separate-stderr` and asserts stdout
  is empty (`[[ -z "$output" ]]`) AND stderr carries the message — pinning both halves of
  the acceptance ("no silent `0`" + "clean message") independently.
- **M2 (F-005 wording):** the `$(...)`-capture wording now states the downstream consequence
  explicitly — the count is captured correctly but the caller does not terminate, so in the
  dispatchers execution falls through to the listing code (broken output: count + listing).
  The "1 contract-violation vs 6 forgotten-`exit 0` sites" symmetry is now explicit.
- **M3 (factual nit):** `git-g` sources `hug-git-repo` at line **13** (line 11 is
  `hug-git-gc`); the spec's "line 11" aside was corrected.
- **M4 (arg-parsing follow-up):** the position-only `--json` detection in `run_count_mode`
  and the pre-existing `--json`-as-pathspec limitation in the dispatcher `case` blocks are
  out of scope here and tracked as [elifarley/hug-scm#260](https://github.com/elifarley/hug-scm/issues/260).