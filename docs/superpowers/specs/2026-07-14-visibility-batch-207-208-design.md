# Visibility Batch — Issues #207 + #208

> Spec for `hug c` staged-file preview (#207) and `hug rb` / dirty-tree remediation messaging fixes (#208).
> Single worktree, three atomic commits, one PR.

## Motivation

Two independent UX gaps in commit-family and rebase commands, both rooted in
messaging/visibility correctness:

- **#207:** `hug c` commits whatever is staged with only a post-hoc file-count
  line. An agent that ran `hug a file.txt` after a soft-reset gets surprised
  when the commit lands with 14 files. The "13 files changed" post-commit line
  is the only signal — easy to miss, and too late to abort cheaply.
- **#208:** Two issues in `hug rb`: (a) `hug rb main` while already on `main`
  silently no-ops with no hint that `origin/main` was the intended target;
  (b) the dirty-tree error suggests three non-existent commands (`git w-backup`,
  `git w-discard-all`, `git w-discard <file>`).

## Scope

### In scope

1. `print_list` (`hug-arrays`) — add optional `--cap N` and `--more-hint T` flags.
2. `hug c` (`git-c`) — emit a capped staged-file preview to stderr before `git commit`.
3. `check_working_tree_clean` (`hug-git-state`) — fix three remediation strings.
4. `check_file_unstaged` (`hug-git-state`) — fix one stray `git w-discard` string.
5. `hug rb` (`git-rb`) — same-name no-op detects upstream and points at it.
6. `.github/copilot-instructions.md:467` — fix the stale `git w-discard` reference.

### Out of scope

- **#209** (`hug w unwip` exit code) — separate worktree / PR.
- **#190 / #191** (`cmoda` dirty-tree docs + runtime guard) — different command
  shape (HEAD amend). #190 may close once #207 ships its precedent.
- **`hug ca` / `hug caa` preview** — their purpose is "commit everything
  tracked"; a file-list preview adds noise without closing a known incident.
- **`git-ca`, `git-cmod`, `git-cmoda` remediation sweep** — grep confirmed
  only `hug-git-state` prints the bad `git w-*` strings at runtime.
- **Items-with-newlines handling in `print_list`** — pre-existing; out of scope.

## Design Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | Visibility, not friction: no new prompts on `hug c` | The incident root cause was lack of *visibility* (file list before commit), not lack of a confirmation gate. Prompts would force every CI script and agent to thread `-y` through the most-used commit path. |
| D2 | Show file *names*, not just count | Count alone doesn't surface the "wait, that file shouldn't be here" mismatch. Names let the agent spot the unexpected file and abort. |
| D3 | Cap at 10 with `+M more` overflow marker | Consistent with `hug wtl`, `hug ll -10`, `rb_render_plan`. Predictable for agents and humans. Full list available via `hug sls`. |
| D4 | Extend `print_list` rather than inline or new function | The cap pattern is a generic list-rendering concern. Lives next to its sibling `print_list` in `hug-arrays`. Reusable by future callers (`git-ca` preview, etc.). Default behavior unchanged — opt-in only. |
| D5 | `--more-hint` is caller-supplied | `print_list` stays domain-neutral (doesn't know about `hug sls`). Caller passes the hint text. |
| D6 | Replace `info "Committing staged changes..."` with the preview header | Single scannable info block; count + list together announce the commit. |
| D7 | Skip preview when `--allow-empty` and no staged changes | Don't add noise to an explicit empty-commit invocation. |
| D8 | Same-name no-op: detect upstream via `@{u}`, suggest exact ref | Informative without magical silent rewrite. `git rev-parse @{u}` returns the upstream *tracking* ref (e.g. `origin/main`); suggestion is `hug rb <upstream>`. Wording says "upstream tracking ref", not "fetched remote tip" — `@{u}` reflects whatever was last fetched, which may be stale. **Scope limit:** detection is textual (`current_branch == target_branch`), not semantic — `refs/heads/main` or another ref resolving to HEAD won't trigger the pointer. Out of scope; the bare no-op message stays correct in those cases. |
| D9 | Falls back to bare no-op when no upstream configured | Don't suggest a ref that doesn't exist. |
| D10 | Remediation text reflects the **operation**, not just the prefix | The old strings advertised `discard`, but `hug w discard[-all]` defaults to **unstaged-only** — staged changes survive. `check_working_tree_clean` rejects when EITHER staged or unstaged exist, so a `discard` remedy leaves the user stuck. The correct "fully clean tree" operation is `wipe[-all]` (both staged + unstaged) or `wip` (park everything). `check_file_unstaged`'s `discard` *is* correct (it only asserts unstaged state), so that one keeps `discard`. |

## Components & Files

### Commit 1 — `print_list --cap` (lib infrastructure)

**File:** `git-config/lib/hug-arrays` (function `print_list`, lines 48-56).

**Signature change:**
```
print_list [--cap N] [--more-hint "<text>"] "Title" item1 item2 ...
```

**Behavior:**
- No flags: current behavior (full list, no overflow).
- `--cap 0`: treated as no-cap (full list). Defensive: `[[ "$cap" =~ ^[0-9]+$ ]] || cap=0`.
- `--cap 10` with 14 items: prints 10 items, then a synthetic overflow line.
- `--cap 10` with 5 items: full list, no overflow line.
- `--more-hint` without `--cap`: hint ignored, no overflow line.
- All output to stderr (unchanged).

**Flag-parsing contract (new, satisfies the helper-API spec):**
- Flag parsing stops at the first non-flag argument (the title) or `--`. After
  that point, all remaining args are items.
- `--cap` requires a following argument; if missing (end of args), error to
  stderr and return 1 (do NOT silently default). Same for `--more-hint`.
- `--cap <value>` validation: `value` must match `^[0-9]+$`. Values with leading
  zeroes (`08`, `007`) are accepted by the regex; the implementation must
  compare as a **string count**, not via Bash arithmetic — `$((08))` is an
  invalid octal literal and would error under `set -e`. Use `${#items[@]}`
  vs. the literal string `$cap` via `(( ${#items[@]} > cap ))` after a
  `cap=$((10#$cap))` normalization (the `10#` base prefix forces decimal and
  defuses the octal trap).
- Repeated flags: last one wins. `--cap 5 --cap 10` → effective cap is 10.
  (Matches `getopt` default behavior.)
- Unknown flags (`--foo`): error to stderr, return 1. Don't silently consume
  the title.
- Titles beginning with `--` (e.g. `"--my files--"`): user must use the `--`
  delimiter — `print_list --cap 5 -- "--my files--" file1 file2`. Without
  `--`, the parser treats the leading-dash title as an unknown flag and
  errors. Documented in `print_list`'s header comment.
- Empty/missing `--more-hint` value: when cap is hit and hint is empty OR
  unset, the overflow line is `... (+M more)` with no trailing em-dash.
  When hint is non-empty, the line is `... (+M more — <hint>)`.

### Commit 2 — `hug c` staged-file preview (#207)

**File:** `git-config/bin/git-c` (lines 82-92).

**Change:** Between the `has_staged_changes` check and `git commit`, insert the preview; remove the old `info "Committing staged changes..."` line.

```bash
# Compute staged state ONCE; the prior code re-evaluated has_staged_changes
# in both the rejection guard and the preview condition. One call, one truth.
_has_staged=false
has_staged_changes && _has_staged=true

if ! $allow_empty && ! $_has_staged; then
  info "No staged changes found. ..."  # unchanged
  exit 1
fi

# Pre-commit visibility (elifarley/hug-scm#207).
# Show staged file names so agents/humans can spot unexpected entries
# (e.g. left over from a soft-reset) BEFORE the commit lands.
if $_has_staged; then
  mapfile -t _staged_files < <(git diff --cached --name-only 2>/dev/null || true)
  if [[ ${#_staged_files[@]} -gt 0 ]]; then
    print_list --cap 10 --more-hint "run 'hug sls' for the full list" \
      "Committing staged file(s)" "${_staged_files[@]}"
  fi
fi

# existing
git commit "$@" && suggest_next_push_command "${_suggest_args[@]}"
```

Fallback: if `git diff --cached --name-only` fails, the array stays empty and
no preview prints. The commit proceeds — never block on a preview failure.

**Testability of the fallback:** the `|| true` deliberately hides failures,
so a test asserting "commit proceeds on preview failure" needs an injection
hook (e.g. `HUG_FAKE_DIFF_FAIL=1` env var that the script checks, or mocking
`git diff` in the test PATH). If we don't add that hook, drop the "fallback
is specified behavior" claim and document it as best-effort only. Decision
deferred to plan writing.

### Commit 3a — dirty-tree remediation text (#208 part 1)

**File:** `git-config/lib/hug-git-state`.

`check_working_tree_clean` (lines 67-74). Note: this guard fires when EITHER
staged or unstaged changes exist, so the remediation must offer operations
that produce a *fully* clean tree. `hug w discard[-all]` defaults to
unstaged-only and would leave staged changes (and the guard still firing) —
hence `wipe[-all]` (both) or `wip` (park everything) are the correct pointers.
```bash
error "Working tree is not clean!
   Unstaged changes: $unstaged_count files
   Staged changes: $staged_count files

   Solutions:
   • Use 'hug w wip \"<msg>\"' to park all changes on a WIP branch
   • Use 'hug w wipe-all' to discard both staged and unstaged changes
   • Use 'hug w wipe <file>' for specific files"
```

`check_file_unstaged` (line 189): `git w-discard $file` → `hug w discard $file`.
This one stays on `discard` (not `wipe`) because `check_file_unstaged` only
asserts unstaged state — `discard` (unstaged-only by default) is exactly the
right operation here.

**File:** `.github/copilot-instructions.md:467`: `git w-discard` → `hug w discard`.

### Commit 3b — `hug rb` same-name no-op (#208 part 2)

**File:** `git-config/bin/git-rb` (lines 114-117).

```bash
if [[ "$current_branch" == "$target_branch" ]]; then
  local _upstream
  _upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
  if [[ -n "$_upstream" && "$_upstream" != "$current_branch" ]]; then
    info "Already on '$target_branch' — did you mean 'hug rb $_upstream' to sync with the fetched remote tip?"
  else
    info "Already on '$target_branch'; nothing to rebase."
  fi
  return 0
fi
```

## Data Flow

### Commit 1
```
caller → print_list [--cap N] [--more-hint T] "Title" items...
       ├─ printf header (title + count) → stderr
       ├─ if cap>0 and count>cap: print first N items → stderr
       │                            printf "... (+M more — T)\n" → stderr
       └─ else: print all items → stderr
```

### Commit 2
```
hug c
 ├─ check_git_repo
 ├─ has_staged_changes?  → no: info + exit 1 (unchanged)
 ├─ if !allow_empty || has_staged_changes:
 │     git diff --cached --name-only  →  staged files
 │     print_list --cap 10 --more-hint "..." "Committing staged file(s)" files...  → stderr
 └─ git commit "$@"  →  stdout (unchanged)
```

### Commit 3b
```
hug rb main (already on main)
 ├─ current_branch == target_branch
 ├─ git rev-parse --abbrev-ref --symbolic-full-name '@{u}'  → "origin/main" or ""
 ├─ if upstream non-empty and != current_branch:
 │     info "Already on 'main' — did you mean 'hug rb origin/main'...?"
 └─ else: info "Already on 'main'; nothing to rebase."  (unchanged)
 return 0
```

## Error Handling & Edge Cases

**`print_list --cap`:**
- `--cap 0` or non-integer → treated as no-cap.
- Empty item list → `Title (0):`, no items, no overflow.
- Items with literal newlines → pre-existing limitation (documented in commit message, not fixed here).

**`hug c` preview:**
- `--allow-empty` and no staged changes → preview skipped (D7).
- `git diff --cached --name-only` fails → array stays empty, no preview, commit proceeds.
- Submodules / gitlinks → listed like any file; no special handling.
- **Filename display quoting:** `git diff --cached --name-only` (without `-z`)
  emits one path per line but applies Git's `core.quotepath` quoting to
  non-ASCII bytes (e.g. `"\303\266.txt"` for `ö.txt`). The preview displays
  paths as Git prints them — the quoting is acceptable for a visibility aid
  (the user sees the file, can identify it). Files with literal newlines in
  their path are shown as multiple lines (pre-existing limitation, also
  present in `hug sls`); out of scope to fix here.

**`check_working_tree_clean`:**
- No flow change. The `error` function exits non-zero; corrected strings only.
- `"<msg>"` is literal placeholder text — user substitutes their message.

**`hug rb` same-name no-op:**
- `@{u}` unset (no upstream) → fallback to bare no-op message. Safe.
- `@{u}` somehow equals current branch name → `!= "$current_branch"` guard catches it, falls back.
- Detached HEAD → already rejected at `git-rb:109-111`, never reaches this branch.

## Testing

All tests via `make` targets.

### Commit 1 — `tests/lib/test_hug_arrays.bats` (new or extended)

- `print_list` without `--cap`: full list (regression).
- `print_list --cap 10` with 5 items: no overflow line.
- `print_list --cap 10` with 14 items + non-empty hint:
  10 items + `... (+4 more — <hint>)`.
- `print_list --cap 10` with 14 items + empty/unset hint:
  10 items + `... (+4 more)` (no trailing em-dash).
- `print_list --cap 0`: full list (treated as no-cap).
- `print_list --cap 08` (leading-zero): treated as decimal 8, not octal error.
- `print_list --cap` (missing value, end of args): errors to stderr, returns 1.
- `print_list --more-hint "x"` without `--cap`: hint ignored.
- `print_list --cap 5 -- "—dash title—" a b c d e f`: title parsed after `--`.
- All output on stderr; stdout empty.

### Commit 2 — `tests/unit/test_commit.bats` (extend)

The preview header is whatever `print_list` renders. `print_list "Title" items`
emits `Title (N):` — so with title `"Committing staged file(s)"` and 14 items,
the line is `Committing staged file(s) (14):`. Tests assert that exact shape;
they do NOT say `"Committing N staged file(s)"` (that would require changing
`print_list`'s contract for one caller, out of scope).

- `hug c -m`: stderr contains `Committing staged file(s) (N):` followed by
  file names.
- `hug c` with 1 staged file: stderr shows `Committing staged file(s) (1):`
  + the filename, no overflow line.
- `hug c` with >10 staged files: stderr shows first 10 + overflow
  `... (+M more — run 'hug sls' for the full list)`.
- `hug c --allow-empty` (no staged): stderr does NOT contain the preview.
- `hug c` stdout: empty before git's own commit output (stderr discipline —
  see "Stdout/stderr discipline" below for the redirection mechanics).
- **Existing test update:** any test in `test_commit.bats` that currently
  asserts the old `Committing staged changes...` line must be updated to
  the new header, or removed.
- Regression: `hug c -m "x"` still commits successfully.

### Commit 3a — `tests/lib/test_hug_git_state.bats` (extend) or `tests/unit/test_rebase.bats`

- `check_working_tree_clean` with dirty tree: error contains `hug w wip`,
  `hug w discard-all`, `hug w discard <file>`; does NOT contain `git w-`.
- `check_file_unstaged`: error contains `hug w discard` (not `git w-discard`).

### Commit 3b — `tests/unit/test_rb.bats` (extend)

(The existing rebase test file is `test_rb.bats`, not `test_rebase.bats`.)

- `hug rb main` while on main, with `origin/main` upstream:
  stderr contains `did you mean 'hug rb origin/main'`.
- `hug rb main` while on main, NO upstream:
  stderr contains `nothing to rebase` (regression).
- `hug rb main --dry-run` while on main: same pointer message.
- Exit code 0 in both cases.

### Stdout/stderr discipline (per CLAUDE.md)

BATS's `run hug c` captures stdout+stderr combined into `$output` — it cannot
prove which stream a line landed on. To assert stream discipline:

- **Capture separately** in setup:
  ```bash
  hug c -m "x" >/tmp/out 2>/tmp/err
  ```
  Then assert: `grep "Committing staged file(s)" /tmp/err` (preview is on
  stderr) and `grep -v "Committing" /tmp/out` (stdout has only git's output).
- Or use the pattern `run hug c 2>/dev/null` then assert `$output` lacks the
  preview header (proves it's on stderr), and separately `run hug c 2>&1
  1>/dev/null` to confirm the preview *is* present when stderr is merged but
  stdout is dropped.

The spec does not require both patterns; pick whichever the existing
`test_commit.bats` style uses (look at `hug c: works with --quiet` for the
convention).

### Test isolation

The same-name no-op positive-case test needs `origin/main` to actually exist
as a remote-tracking ref — `git branch --set-upstream-to=origin/main main`
fails otherwise. Two valid setup patterns:

1. **`create_test_repo_with_remote_upstream`** if `test_helper.bash` exposes
   one (check during implementation; if not, add it as a helper).
2. **Bare-remote push:** create a local bare repo, push `main` to it as
   `origin`, then `git branch --set-upstream-to=origin/main main`. This is
   the canonical pattern when no helper exists.

The no-upstream fallback test uses plain `create_test_repo` (no remote) — the
`@{u}` resolution returns empty, the bare no-op message fires.

### Dev-time make targets

```bash
make test-lib TEST_FILE=test_hug_arrays.bats
make test-unit TEST_FILE=test_commit.bats
make test-unit TEST_FILE=test_rb.bats
```

Final validation: `make test` (full suite, confirms no regressions in unrelated
commands that call `print_list` or `check_working_tree_clean`).

## Verification (Success Criteria)

1. `make test` passes (full suite).
2. **#207 repro:** stage 14 files, run `hug c -m "x"` — see first 10 names
   plus `(+4 more — run 'hug sls'...)` on stderr *before* `[main <hash>]`
   on stdout. (With ≤10 staged files, all names appear, no overflow line.)
3. **#208 same-name repro:** on `main` with `origin/main` upstream, run
   `hug rb main` — see pointer message, not bare no-op.
4. **#208 remediation repro:** dirty tree (staged OR unstaged) + `hug rb
   origin/main` — error contains `hug w wip` / `hug w wipe-all` /
   `hug w wipe <file>`. Following either `wipe` remedy leaves the tree
   actually clean (re-running `hug rb origin/main` succeeds).
5. **No stale strings:** `grep -rn 'git w-' git-config/ .github/` returns
   zero runtime matches.
6. **Exit codes unchanged:** `hug c` → 0 on success; `hug rb main` (no-op) → 0;
   `check_working_tree_clean` → non-zero on dirty tree.

## Risk Assessment

- **`print_list --cap` blast radius:** existing callers pass only `Title items...`;
  the new flags are optional and positional-leading, so existing callers work
  unchanged. The full `make test` sweep catches any regression.
- **`git diff --cached --name-only` perf:** one index read, no working-tree
  scan. Sub-millisecond on any repo under ~100k files. Negligible.
- **`hug c` output change:** stderr gains a block. Scripts that capture stderr
  will see new lines; stdout is unchanged. Documented in the commit message as
  a deliberate UX change closing #207.

## Commit Sequencing (single PR)

Three atomic commits. The earlier "Commit 3a" / "Commit 3b" labels were
section-level subdivisions of the design discussion — both land in commit 3
together. (Splitting them into 4 commits would also be defensible, but the
remediation text and same-name no-op are both `hug rb` UX correctness fixes
closing the same issue; one commit tells the cleaner story.)

1. `feat(hug-arrays): print_list gains --cap and --more-hint flags`
2. `fix(hug-c): show staged-file preview before committing (closes #207)`
3. `fix(hug-rb,hug-git-state): correct dirty-tree remediation + same-name no-op pointer (closes #208)`

**Independence criterion:** bash has no compile step; the criterion is that
each commit's targeted test suite passes after that commit lands:

- After commit 1: `make test-lib TEST_FILE=test_hug_arrays.bats` green.
  Existing `print_list` callers unchanged in behavior.
- After commit 2: `make test-unit TEST_FILE=test_commit.bats` green; the
  `hug c` preview works manually.
- After commit 3: `make test-unit TEST_FILE=test_rb.bats` and the
  `hug-git-state` tests green; manual repros for #208 work.

If any intermediate commit breaks an unrelated test, the sequence is wrong —
reorder or split.

## Review History

- **2026-07-14** — codex consult pass (verdict: REVISE). Surfaced 2 blockers
  + 11 non-blockers, all addressed in this revision:
  - **B1 (blocker, verified):** `discard[-all]` defaults to unstaged-only;
    using it as the "clean the tree" remedy in `check_working_tree_clean`
    leaves staged changes (and the guard still firing). Switched the
    remediation to `wipe[-all]`. `check_file_unstaged` stays on `discard`
    (it only asserts unstaged state — `discard` is correct there).
  - **B2 (blocker):** test setup needed a real `origin` remote, not just
    `set-upstream-to`. Wrong filename `test_rebase.bats` → `test_rb.bats`.
  - D3 — `print_list` test contract now matches actual `Title (N):` output.
  - D4 — full flag-parsing contract specified (octal `08`, `--` delimiter,
    leading-dash titles, missing values, repeated flags, empty hint).
  - Dup `has_staged_changes` call — compute once into `_has_staged`.
  - Filename quoting — explicit: Git's `core.quotepath` applies; preview
    shows paths as Git prints them.
  - D8 — "upstream tracking ref" wording replaces "fetched remote tip";
    semantic-scope limit (textual match only) called out.
  - Stderr-discipline test mechanics — BATS `run` merges streams; specify
    redirection-based assertions.
  - 3 vs 3a/3b — resolved: both land in commit 3.
  - `--more-hint` empty case — overflow line is `... (+M more)` without
    trailing em-dash when hint is empty/unset.

