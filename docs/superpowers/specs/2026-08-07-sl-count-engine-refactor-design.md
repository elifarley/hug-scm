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
  call + `exit 0`, ~14 lines) plus its ~7-line WHY comment are duplicated verbatim across
  the 6 `sl*` dispatchers that implement `-c` locally — `git-sls`, `git-slu`, `git-slk`,
  `git-sli`, `git-slc`, `git-statusbase`. Only the state argument differs. Factor the
  shared logic into a single `run_count_mode` helper.
- **#259:** `count_files_with_status` (the `sl* -c` engine) does not call `check_git_repo`,
  unlike every `list_*_files` function in `hug-git-files`. All current `sl*` callers
  validate at the top of their script, so the gap is defended in practice — but a direct
  library caller gets a raw git error instead of the clean HUG "Not in a git repository"
  message. Add `check_git_repo` for parity.

## Decisions (settled during brainstorming)

| Decision | Choice | Rationale |
|---|---|---|
| **#259 approach** | Unconditional `check_git_repo` as the first line of `count_files_with_status` | Matches the `list_*_files` contract verbatim; simplest. `count_files_with_status` already spawns ≥1 git subprocess per call, so one extra `git rev-parse --git-dir` is negligible. A cached-sentinel guard adds state to a pure helper for a micro-optimization — YAGNI. Guarding in `run_count_mode` only does **not** meet #259's acceptance (a direct library caller still gets a raw git error). |
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

# sl / sla delegate to git-statusbase via .gitconfig aliases → covered transitively, no own copy.
```

`hug-select-files` is loaded by all 6 dispatchers (they source
`hug-common hug-git-kit hug-select-files output_json_status`). `hug-git-kit` aggregates
`hug-git-repo` (provides `check_git_repo`) and `hug-output` (provides `error`), so both
are already in scope wherever `count_files_with_status` runs — the existing `error` call
for unknown state (line ~106) already relies on this chain.

## Section 1 — `count_files_with_status` parity (#259)

Insert `check_git_repo` as the first executable line of `count_files_with_status()`,
before arg parsing. Update the header comment to note the repo precondition is enforced
internally (matching `list_*_files`).

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

## Section 2 — `run_count_mode` wrapper (#258)

Add directly above `count_files_with_status` in `hug-select-files`:

```bash
# run_count_mode — terminating wrapper for the sl* -c/--count dispatch.
# Usage: run_count_mode [--json] <state> [pathspec...]
#   <state>: the count_files_with_status enum (staged|unstaged|untracked|ignored|
#           conflicted|all|all+untracked).
# Encapsulates the -c dispatch previously duplicated verbatim across the 6 sl*
# scripts (git-sls/slu/slk/sli/slc/statusbase):
#   (1) --json is mutually exclusive with -c → error + exit (like hug wtl's
#       --json --path-only error),
#   (2) delegate to count_files_with_status (which itself enforces the repo
#       precondition — #259),
#   (3) exit 0.
# TERMINATING: calls `exit 0`, so a caller running this inside
#   `if $count_only; then ...; fi` never reaches code below the block. Pass
#   `--json` with `${json_output:+--json}` so the caller stays a single line.
# Why NUL-delimited + Bash-4.0-safe: see count_files_with_status.
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

- **`--json` as a flag, passed via `${json_output:+--json}`** — keeps each call site a
  single line and the helper self-contained (no reliance on a caller global variable
  name). The mutual-exclusion check lives inside the helper, so it cannot drift across
  the 6 sites.
- **Terminating (`exit 0`)** — matches #258's "(3) the exit 0" and the original blocks.
  Callers are top-level scripts that intend to terminate; none capture `run_count_mode`
  in `$(...)`, so the known "exit only exits the subshell" footgun (helpers captured via
  command substitution) does not apply.
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
docblock (Section 2). Each call site keeps a one-line pointer.

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
  run_count_mode ${json_output:+--json} staged "${pathspecs[@]}"
fi
```

### `git-statusbase` (branches `all` vs `all+untracked`)

Keeps its existing `if $include_untracked` if/else, swapping the inner guard+exit for
`run_count_mode`. No `local` (top-level, `set -e` footgun), so the two branches inline
the state:

```bash
# Count mode: -c/--count dispatch (see run_count_mode in hug-select-files).
if $count_only; then
  if $include_untracked; then
    run_count_mode ${json_output:+--json} all+untracked "${pathspecs[@]}"
  else
    run_count_mode ${json_output:+--json} all "${pathspecs[@]}"
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

In `test_hug-select-files.bats`, next to the `count_files_with_status` block:

```bash
@test "count_files_with_status: clean error outside a git repo (parity with list_*_files)" {
  cd /tmp  # setup() cds into a repo; leave it for this assertion
  run count_files_with_status staged
  assert_failure
  assert_output --partial "Not in a git repository"
}
```

Convention matches `test_worktree_list.bats:142` (`cd /tmp; run git-wt; assert_failure;
assert_output --partial "Not in a git repository"`). `check_git_repo` and `error` are in
scope via `hug-git-kit` (already loaded at line 6 of the test file); `run` runs in a
subshell that inherits the sourced function, and `error`→`exit 1` is contained there.

### Optional end-to-end test (only if it does not duplicate the lib test)

A `hug sls -c` from `/tmp` asserting the same "Not in a git repository" message —
confirms the wrapper + primitive compose end-to-end. Add **only** if it proves cheaper
than it is duplicative; the lib test above is the load-bearing one for #259's acceptance.

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
  - [ ] `count_files_with_status` from a non-repo directory emits the HUG "Not in a git
        repository" message, not raw git stderr (new lib test).
  - [ ] No regression to in-repo `count_files_with_status` callers (existing lib tests
        green unchanged).

## Out of scope (YAGNI)

- A cached "already-validated" sentinel to avoid the extra `git rev-parse` on repeat
  calls — rejected during brainstorming; the cost is negligible and the sentinel adds
  state to a pure helper.
- Moving `check_git_repo` into `run_count_mode` only — rejected; does not satisfy #259's
  acceptance for direct library callers.
- Refactoring the `sl*` JSON/listing paths (out of scope; only the `-c` dispatch is
  factored).
- Touching `sl`/`sla` directly (they delegate via aliases).

## Risks

- **Top-level `local` footgun:** the `git-statusbase` branch must not introduce a
  `local state=...` at script top level (fatal under `set -euo pipefail`). The design
  inlines the state in two `run_count_mode` calls instead. The `git-sls` family is
  unaffected (single state, no temp var).
- **Terminating helper captured via `$(...)`:** if a future caller captures
  `run_count_mode` in command substitution, `exit 0` only exits the subshell and the
  caller continues — a silent no-op. Mitigated by the docblock's TERMINATING note and by
  the contract (callers invoke it as a statement inside `if $count_only; then ...; fi`).
- **`--json` flag parsing vs. pathspecs starting with `--`:** a pathspec literally named
  `--json` would be mis-read as the flag. This is already broken upstream (the
  dispatchers' `case` collects anything not matching `--json`/`-c`/`-q` as a pathspec, so
  a real `--json` pathspec can't reach `run_count_mode` anyway). No new exposure.