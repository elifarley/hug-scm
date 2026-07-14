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
| D8 | Same-name no-op: detect upstream via `@{u}`, suggest exact ref | Informative without magical silent rewrite. `git rev-parse @{u}` returns `origin/main`; suggestion is `hug rb origin/main` — the exact command the user meant. |
| D9 | Falls back to bare no-op when no upstream configured | Don't suggest a ref that doesn't exist. |
| D10 | Fix remediation text in-place, mirror existing wording | Three wrong strings → three correct `hug w *` equivalents. Same bullet structure. |

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
- `--cap 10` with 14 items: prints 10 items, then a synthetic overflow line:
  `... (+4 more — <hint>)`. The hint is appended verbatim.
- `--cap 10` with 5 items: full list, no overflow line.
- `--more-hint` without `--cap`: hint ignored, no overflow line.
- All output to stderr (unchanged).

### Commit 2 — `hug c` staged-file preview (#207)

**File:** `git-config/bin/git-c` (lines 82-92).

**Change:** Between the `has_staged_changes` check and `git commit`, insert the preview; remove the old `info "Committing staged changes..."` line.

```bash
if ! $allow_empty && ! has_staged_changes; then
  info "No staged changes found. ..."  # unchanged
  exit 1
fi

# Pre-commit visibility (elifarley/hug-scm#207).
# Show staged file names so agents/humans can spot unexpected entries
# (e.g. left over from a soft-reset) BEFORE the commit lands.
if ! $allow_empty || has_staged_changes; then
  mapfile -t _staged_files < <(git diff --cached --name-only 2>/dev/null || true)
  if [[ ${#_staged_files[@]} -gt 0 ]]; then
    print_list --cap 10 --more-hint "run 'hug sls' for the full list" \
      "Committing staged file(s)" "${_staged_files[@]}"
  fi
fi

# existing
git commit "$@" && suggest_next_push_command "${_suggest_args[@]}"
```

Fallback: if `git diff --cached --name-only` fails, the array stays empty and no preview prints. The commit proceeds — never block on a preview failure.

### Commit 3a — dirty-tree remediation text (#208 part 1)

**File:** `git-config/lib/hug-git-state`.

`check_working_tree_clean` (lines 67-74):
```bash
error "Working tree is not clean!
   Unstaged changes: $unstaged_count files
   Staged changes: $staged_count files

   Solutions:
   • Use 'hug w wip \"<msg>\"' to save changes first
   • Use 'hug w discard-all' to discard changes
   • Use 'hug w discard <file>' for specific files"
```

`check_file_unstaged` (line 189): `git w-discard $file` → `hug w discard $file`.

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
- `print_list --cap 10` with 14 items: 10 items + `... (+4 more — <hint>)`.
- `print_list --cap 0`: full list (treated as no-cap).
- `print_list --more-hint "x"` without `--cap`: hint ignored.
- All output on stderr; stdout empty.

### Commit 2 — `tests/unit/test_commit.bats` (extend)

- `hug c -m`: stderr contains "Committing N staged file(s)" + file names.
- `hug c` with 1 staged file: stderr shows filename, no overflow.
- `hug c` with >10 staged files: stderr shows first 10 + `(+M more — run 'hug sls'...)`.
- `hug c --allow-empty` (no staged): stderr does NOT contain the preview.
- `hug c` stdout: empty before git's own output (stderr discipline).
- Regression: `hug c -m "x"` still commits successfully.

### Commit 3a — `tests/lib/test_hug_git_state.bats` (extend) or `tests/unit/test_rebase.bats`

- `check_working_tree_clean` with dirty tree: error contains `hug w wip`,
  `hug w discard-all`, `hug w discard <file>`; does NOT contain `git w-`.
- `check_file_unstaged`: error contains `hug w discard` (not `git w-discard`).

### Commit 3b — `tests/unit/test_rebase.bats` (extend)

- `hug rb main` while on main, with `origin/main` upstream:
  stderr contains `did you mean 'hug rb origin/main'`.
- `hug rb main` while on main, NO upstream:
  stderr contains `nothing to rebase` (regression).
- `hug rb main --dry-run` while on main: same pointer message.
- Exit code 0 in both cases.

### Stdout/stderr discipline (per CLAUDE.md)

For `hug c`: assert `2>/dev/null` removes the preview but git's commit output
on stdout remains intact.

### Test isolation

Same-name no-op test needs `origin/main` set as upstream. Use `create_test_repo`
+ `git branch --set-upstream-to=origin/main main` in setup. If
`create_test_repo` doesn't create a remote, the test naturally covers the
no-upstream fallback case — no special setup needed.

### Dev-time make targets

```bash
make test-lib TEST_FILE=test_hug_arrays.bats
make test-unit TEST_FILE=test_commit.bats
make test-unit TEST_FILE=test_rebase.bats
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
4. **#208 remediation repro:** dirty tree + `hug rb origin/main` — see
   `hug w wip` / `hug w discard-all` / `hug w discard <file>` in error.
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

1. `feat(hug-arrays): print_list gains --cap and --more-hint flags`
2. `fix(hug-c): show staged-file preview before committing (closes #207)`
3. `fix(hug-rb,hug-git-state): correct dirty-tree remediation + same-name no-op pointer (closes #208)`

Each commit independently compiles and passes tests.
