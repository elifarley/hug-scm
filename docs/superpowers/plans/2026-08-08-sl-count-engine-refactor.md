# sl* -c Count Engine Refactor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Factor the duplicated `-c/--count` dispatch block across the 6 `sl*` dispatchers into one `run_count_mode` helper (#258), and add `check_git_repo` parity to `count_files_with_status` (#259) — so the count primitive emits the clean HUG "Not in a git repository" message instead of a silent wrong answer.

**Architecture:** Two stacked edits to `git-config/lib/hug-select-files`, in forced order (#259 then #258 — the wrapper delegates to the primitive, so the primitive must carry the invariant first), then wire the 6 `sl*` dispatchers to the new wrapper. The `check_git_repo` dependency is *declared* in `hug-select-files`'s `Depends on:` header (not auto-sourced — `hug-common` is symlinked into `hg-config`, so `hug-select-files` already loads in Mercurial contexts; auto-sourcing the git-specific `hug-git-repo` there would be a VCS-boundary violation). All 6 dispatchers source `hug-git-kit`, which loads `hug-git-repo`, so `check_git_repo` is available to every real caller.

**Tech Stack:** Bash (BATS tests, `set -euo pipefail`), GNU make, shellcheck. Bash floor 4.0 (no `local -n` nameref on the count path).

**Spec:** `docs/superpowers/specs/2026-08-07-sl-count-engine-refactor-design.md` (roast-clean after 3 rounds).
**Issues:** [elifarley/hug-scm#258](https://github.com/elifarley/hug-scm/issues/258), [elifarley/hug-scm#259](https://github.com/elifarley/hug-scm/issues/259). Out-of-scope arg-parsing hardening tracked as [elifarley/hug-scm#260](https://github.com/elifarley/hug-scm/issues/260).

**Worktree:** `/home/ecc/src/hug-scm.WT.refactor-sl-count-engine-258-259` (branch `refactor-sl-count-engine-258-259`). Do ALL work here; the Bash tool resets CWD between calls, so use absolute paths or `cd` at the start of each command.

**Commit discipline:** Use `hug` commands, never raw git. Commit messages document WHY (load the `commit-message` skill). Because the commit body may reference git internals, use the `GIT-BLOCK:BYPASS` escape hatch in a trailing comment (see `.wolf/cerebrum.md` / the `block-commands.py` hook). One logical commit per task.

---

## File Structure

| File | Responsibility | Touched by |
|---|---|---|
| `git-config/lib/hug-select-files` | The `count_files_with_status` primitive + the new `run_count_mode` wrapper. Header `Depends on:` + function list. | Task 1, Task 2 |
| `tests/lib/test_hug-select-files.bats` | Library tests for the primitive (non-repo error) and the wrapper. | Task 1, Task 2 |
| `git-config/lib/README.md` | Library reference doc — the doc-perimeter. Add `run_count_mode` entry; amend `count_files_with_status` contract. | Task 1, Task 2 |
| `git-config/bin/git-sls`, `git-slu`, `git-slk`, `git-sli`, `git-slc` | 5 single-state dispatchers — replace the 13-line count block with one `run_count_mode` call. | Task 3 |
| `git-config/bin/git-statusbase` | The `all`/`all+untracked` dispatcher — replace its count block (keeps the `include_untracked` if/else). | Task 3 |

`sl`/`sla` delegate to `git-statusbase` via `.gitconfig` aliases, so they are covered transitively (no own copy).

---

### Task 1: #259 — `check_git_repo` parity for `count_files_with_status`

**Goal:** Make `count_files_with_status` emit the clean HUG "Not in a git repository" message (and exit 1) when called outside a repo, instead of a silent wrong answer (`0`, exit 0) — matching the `list_*_files` contract — and declare the new `hug-git-repo` dependency.

**Files:**
- Modify: `git-config/lib/hug-select-files` (header line 5 `Depends on:`, header line 9 function list, and the first line of `count_files_with_status()` at line 27)
- Modify: `git-config/lib/README.md` (the `count_files_with_status` entry at line 202)
- Test: `tests/lib/test_hug-select-files.bats` (insert a new test after the existing `count_files_with_status` tests, ~line 876)

**Acceptance Criteria:**
- [ ] `count_files_with_status` calls `check_git_repo` as its first executable line.
- [ ] `hug-select-files`'s `Depends on:` header (line 5) declares `hug-git-repo`.
- [ ] From a non-repo dir (`mktemp -d`), `count_files_with_status staged` exits 1 with stdout empty and stderr containing "Not in a git repository" (new lib test, `run --separate-stderr`).
- [ ] All existing in-repo `count_files_with_status` lib tests stay green (they `cd "$repo"` first, so `check_git_repo` passes).
- [ ] `git-config/lib/README.md` `count_files_with_status` entry notes the repo precondition.

**Verify:** `make test-lib TEST_FILE=test_hug-select-files.bats TEST_SHOW_ALL_RESULTS=1` → all tests pass, including the new non-repo test and the existing count tests.

**Steps:**

- [ ] **Step 1: Write the failing test.**

In `tests/lib/test_hug-select-files.bats`, insert this test immediately after the existing `count_files_with_status: all+untracked expands untracked dir to its files` test (find it with `grep -n "all+untracked expands" tests/lib/test_hug-select-files.bats`; the test ends at its closing `}`):

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

This test uses `run --separate-stderr` (BATS ≥1.6; the repo already uses it at `tests/unit/test_status_staging.bats:1947`). `error`→`gum_log` writes `>&2`, so the message lands on `$stderr` and `$output` (stdout) stays clean. `check_git_repo` and `error` are in scope via the test file's existing `load` lines (`hug-common` at line 5 → `hug-output` for `error`; `hug-git-kit` at line 6 → `hug-git-repo` for `check_git_repo`).

- [ ] **Step 2: Run the test to verify it fails.**

Run: `make test-lib TEST_FILE=test_hug-select-files.bats TEST_FILTER="clean error outside a git repo" TEST_SHOW_ALL_RESULTS=1`
Expected: FAIL. Current behavior (no `check_git_repo`): from a non-repo, every `git` call is suffixed `2>/dev/null`, so `count_files_with_status staged` returns `0` with exit 0 and empty stderr → `assert_failure` fails (and `[[ -z "$output" ]]` fails because `$output` is `0`). This is the silent-wrong-answer bug #259 fixes.

- [ ] **Step 3: Implement — add `check_git_repo` + declare the dependency.**

Edit `git-config/lib/hug-select-files`:

(a) Header `Depends on:` (line 5) — append `hug-git-repo`:

Replace:
```
# Depends on: hug-gum, hug-output, hug-terminal, hug-git-files (for list_* functions), hug-git-priorities.
```
With:
```
# Depends on: hug-gum, hug-output, hug-terminal, hug-git-files (for list_* functions), hug-git-priorities, hug-git-repo (for check_git_repo, used by count_files_with_status).
```

(b) Header function-list (line 9) — note the repo precondition:

Replace:
```
#   - count_files_with_status: count files by state (NUL-safe, scriptable; the sl* `-c` engine).
```
With:
```
#   - count_files_with_status: count files by state (NUL-safe, scriptable; the sl* `-c` engine; enforces the repo precondition via check_git_repo).
```

(c) The function body — add `check_git_repo` as the first executable line. The function currently starts (line 27):
```bash
count_files_with_status() {
  local state="$1"
  shift
```
Change to:
```bash
count_files_with_status() {
  check_git_repo   # Parity with list_*_files: clean HUG error from any context (#259)
  local state="$1"
  shift
```
(Insert the `check_git_repo` line before `local state="$1"`. Do not touch the rest of the function — the counting loop, the `2>/dev/null` suffixes, and the `error "unknown state"` branch stay as-is.)

- [ ] **Step 4: Amend the library README.**

In `git-config/lib/README.md`, the `count_files_with_status` entry (line 202) is:
```
- `count_files_with_status <state> [pathspec...]` - Count files by state (the sl* `-c` engine)
  - `<state>`: `staged`|`unstaged`|`untracked`|`ignored`|`conflicted`|`all`|`all+untracked`
  - Prints an integer (0 when none, exit 0). NUL-safe (newline filenames count once) and Bash 4.0-safe (no nameref).
  - `all`/`all+untracked` dedup via `git status --porcelain -z` (a file staged AND unstaged counts once)
```
Append a new bullet after the last (`all`/`all+untracked`...) line:
```
  - Enforces the repo precondition internally (`check_git_repo`): exits 1 with "Not in a git repository" when called outside a repo (parity with `list_*_files`)
```

- [ ] **Step 5: Run the test to verify it passes — and the existing count tests stay green.**

Run: `make test-lib TEST_FILE=test_hug-select-files.bats TEST_SHOW_ALL_RESULTS=1`
Expected: PASS — the new non-repo test passes (`assert_failure`, empty stdout, message on stderr), and all existing `count_files_with_status` tests (per-state counts, dedup, pathspec scoping, NUL-safety, rename, untracked-dir expansion) stay green because they `cd "$repo"` first so `check_git_repo` passes.

- [ ] **Step 6: Commit.**

```bash
cd /home/ecc/src/hug-scm.WT.refactor-sl-count-engine-258-259
hug a git-config/lib/hug-select-files git-config/lib/README.md tests/lib/test_hug-select-files.bats
hug c -F - <<'EOF' # GIT-BLOCK:BYPASS
fix(sl*): count_files_with_status now checks the repo (parity with list_*_files) (#259)

WHY: count_files_with_status (the sl* -c engine) did not call check_git_repo, unlike
every list_*_files function. From a non-repo dir this produced a SILENT WRONG ANSWER
(0, exit 0) — every git call is suffixed 2>/dev/null, so git's error never surfaced. A
direct library caller had no idea it was not in a repo. #259 fixes this for parity with
list_*_files, which emits the clean HUG "Not in a git repository" message.

WHAT: Added check_git_repo as the first executable line of count_files_with_status. It
fails fast with the clean message before spending a subprocess on a doomed count; in a
repo it is a no-op pass (one git rev-parse --git-dir). Declared the new hug-git-repo
dependency in hug-select-files's Depends on: header (all 6 sl* dispatchers source
hug-git-kit, which loads hug-git-repo, so check_git_repo is available to every real
caller; declared rather than auto-sourced because hug-common is symlinked into
hg-config, so hug-select-files already loads in Mercurial contexts — auto-sourcing the
git-specific hug-git-repo there would be a VCS-boundary violation). Updated the in-file
function-list header and git-config/lib/README.md to note the repo precondition.

HOW: TDD — wrote the non-repo test first (run --separate-stderr; asserts assert_failure +
empty stdout + "Not in a git repository" on stderr), confirmed it failed against the old
silent-0 behavior, then added check_git_repo. The existing count_files_with_status lib
tests (they cd "$repo" first) pin the in-repo contract and stay green unchanged.

IMPACT: count_files_with_status is now safe to call from any context that sources its
declared deps — outside a repo it fails loudly with the HUG message instead of silently
returning 0. The check_git_repo call adds one git rev-parse to the count path, negligible
beside the git subprocesses the function already runs.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
```

---

### Task 2: #258 — Add the `run_count_mode` wrapper

**Goal:** Add the terminating `run_count_mode [--json] <state> [pathspec...]` helper to `hug-select-files` that encapsulates the `-c` dispatch (mutual-exclusion guard + `count_files_with_status` call + `exit 0`), with focused lib tests, so the 6 `sl*` dispatchers can each collapse their 13-line count block to a one-line call in Task 3.

**Files:**
- Modify: `git-config/lib/hug-select-files` (add the `run_count_mode` function directly above `count_files_with_status`; add it to the function-list header)
- Modify: `git-config/lib/README.md` (add a `run_count_mode` entry next to `count_files_with_status`)
- Test: `tests/lib/test_hug-select-files.bats` (add `run_count_mode` tests next to the `count_files_with_status` tests)

**Acceptance Criteria:**
- [ ] `run_count_mode [--json] <state> [pathspec...]` exists in `hug-select-files`, directly above `count_files_with_status`.
- [ ] It is TERMINATING: `error`→exit 1 on the `--json`+`-c` mutex violation, `exit 0` after printing the count; it never returns.
- [ ] `run_count_mode` lists in the `hug-select-files` function-list header comment.
- [ ] `git-config/lib/README.md` has a `run_count_mode` entry.
- [ ] Lib tests: `run_count_mode staged` in a repo with 1 staged file prints `1` and exits 0; `run_count_mode --json staged` exits nonzero with "mutually exclusive" on stderr.
- [ ] `make sanitize` (shellcheck) passes for `hug-select-files`.

**Verify:** `make test-lib TEST_FILE=test_hug-select-files.bats TEST_FILTER="run_count_mode" TEST_SHOW_ALL_RESULTS=1` → new tests pass; then `make sanitize` → shellcheck clean.

**Steps:**

- [ ] **Step 1: Write the failing tests.**

In `tests/lib/test_hug-select-files.bats`, insert these two tests immediately after the non-repo test added in Task 1 (or next to the other `count_files_with_status` tests):

```bash
@test "run_count_mode: prints the count and exits 0 (terminating wrapper)" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"
  echo "staged" > staged.txt
  git add staged.txt

  # TERMINATING: run in a subshell via `run`; prints the count, exit 0.
  run --separate-stderr run_count_mode staged
  assert_success
  assert_output "1"
  [[ -z "$stderr" ]]
}

@test "run_count_mode: --json and -c are mutually exclusive" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"
  echo "staged" > staged.txt
  git add staged.txt

  run --separate-stderr run_count_mode --json staged
  assert_failure
  [[ "$stderr" == *"mutually exclusive"* ]]
  [[ -z "$output" ]]   # no count printed on the mutex-violation path
}
```

- [ ] **Step 2: Run the tests to verify they fail.**

Run: `make test-lib TEST_FILE=test_hug-select-files.bats TEST_FILTER="run_count_mode" TEST_SHOW_ALL_RESULTS=1`
Expected: FAIL — `run_count_mode: command not found` (the function does not exist yet).

- [ ] **Step 3: Implement `run_count_mode`.**

In `git-config/lib/hug-select-files`, insert this function **directly above** the `count_files_with_status()` definition (i.e. immediately before the `count_files_with_status() {` line, after the existing `count_files_with_status` header comment block that ends at `# Prints a single integer (newline-terminated) to stdout; 0 when none; exit 0.` / the blank line before the function):

```bash
# run_count_mode — terminating wrapper for the sl* -c/--count dispatch.
# Usage: run_count_mode [--json] <state> [pathspec...]
#   <state>: the count_files_with_status enum (staged|unstaged|untracked|ignored|
#           conflicted|all|all+untracked).
# Encapsulates the -c dispatch previously duplicated (near-verbatim) across the 6 sl*
# scripts (git-sls/slu/slk/sli/slc/statusbase):
#   (1) --json is mutually exclusive with -c -> error + exit (like hug wtl's
#       --json --path-only error),
#   (2) delegate to count_files_with_status (which itself enforces the repo
#       precondition -- #259),
#   (3) exit 0.
# TERMINATING: calls `exit 0` (and `error`->exit 1 on the --json violation), so it
#   NEVER returns -- a caller running it inside `if $count_only; then ...; fi` never
#   reaches code below the block. Callers pass `--json` only when their json flag is
#   true, e.g. `if $json_output; then run_count_mode --json <state> ...; else
#   run_count_mode <state> ...; fi`. Do NOT use ${json_output:+--json}: hug stores
#   booleans as the strings true/false, so :+ fires on the non-empty "false" too and
#   would ALWAYS pass --json. Do NOT capture this in $(...) : the subshell exit is
#   contained and the count is captured correctly, but the caller does NOT terminate
#   -- in the dispatchers, execution falls through to the listing/summary code and
#   prints BOTH the (captured) count AND the listing (broken output). Call it as a
#   statement, never as a substitution.
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

`local` is legal here (this is a real function body, unlike dispatcher top-level code). `local -a pathspecs=("$@")` declares the array, so `"${pathspecs[@]}"` is safe under `set -u` even when empty — matching the existing `count_files_with_status` pattern.

- [ ] **Step 4: Add `run_count_mode` to the function-list header.**

In `git-config/lib/hug-select-files`, the function-list header (after Task 1) reads:
```
#   - count_files_with_status: count files by state (NUL-safe, scriptable; the sl* `-c` engine; enforces the repo precondition via check_git_repo).
```
Insert a new line directly after it:
```
#   - run_count_mode: terminating wrapper for the sl* -c/--count dispatch (mutual-exclusion guard + count + exit 0).
```

- [ ] **Step 5: Add the `run_count_mode` README entry.**

In `git-config/lib/README.md`, directly after the `count_files_with_status` entry's last bullet (the "Enforces the repo precondition..." bullet added in Task 1), add:
```
- `run_count_mode [--json] <state> [pathspec...]` - Terminating wrapper for the sl* `-c/--count` dispatch
  - Encapsulates the mutual-exclusion guard + `count_files_with_status` call + `exit 0` (formerly duplicated across the 6 `sl*` dispatchers)
  - `--json` is mutually exclusive with `-c` (errors and exits); the function ALWAYS exits (never returns) — call it as a statement, never in `$(...)`
```

- [ ] **Step 6: Run the tests to verify they pass.**

Run: `make test-lib TEST_FILE=test_hug-select-files.bats TEST_FILTER="run_count_mode" TEST_SHOW_ALL_RESULTS=1`
Expected: PASS — both new tests pass. Then run the full lib file to confirm no regression:
Run: `make test-lib TEST_FILE=test_hug-select-files.bats TEST_SHOW_ALL_RESULTS=1`
Expected: all tests pass (the existing count tests + the Task 1 non-repo test + the two new wrapper tests).

- [ ] **Step 7: Run shellcheck.**

Run: `make sanitize`
Expected: clean (no new shellcheck warnings for `hug-select-files` — `local` inside `run_count_mode()` is valid; the `[[ ... ]] && { ...; }` pattern is safe under `set -euo pipefail`).

- [ ] **Step 8: Commit.**

```bash
cd /home/ecc/src/hug-scm.WT.refactor-sl-count-engine-258-259
hug a git-config/lib/hug-select-files git-config/lib/README.md tests/lib/test_hug-select-files.bats
hug c -F - <<'EOF' # GIT-BLOCK:BYPASS
refactor(sl*): add run_count_mode wrapper to hug-select-files (#258)

WHY: The -c/--count dispatch block (mutual-exclusion guard + count_files_with_status
call + exit 0, ~13 lines) plus its ~7-line WHY comment were duplicated near-verbatim
across the 6 sl* dispatchers (git-sls/slu/slk/sli/slc/statusbase); only the state
argument differed (and statusbase's all/all+untracked branch). A DRY smell: any future
change to -c semantics would have to be edited in 6 places.

WHAT: Added run_count_mode [--json] <state> [pathspec...] to hug-select-files, directly
above count_files_with_status. It owns (1) the --json mutual-exclusion error, (2) the
delegation to count_files_with_status (which now enforces the repo precondition --
#259), and (3) exit 0. It is TERMINATING (always exits, never returns): error->exit 1
on the --json violation, exit 0 after printing the count. The dispatchers (Task 3) will
each call it via the two-branch `if $json_output; then run_count_mode --json <state> ...;
else run_count_mode <state> ...; fi` inside `if $count_only; then ...; fi`, collapsing
their 13-line block.

HOW: TDD -- wrote two lib tests first (count output + exit 0; --json mutex -> failure +
"mutually exclusive" on stderr, no count on stdout), confirmed command-not-found, then
implemented. The wrapper takes a --json flag (consistent with the codebase's flag-based
library functions); callers pass it only when $json_output is true via the two-branch
idiom (do NOT use ${json_output:+--json} -- hug stores booleans as true/false strings, so
:+ fires on the non-empty "false" too and would ALWAYS pass --json; caught by TDD in Task
3). local is legal inside the
function body; local -a pathspecs=("$@") keeps "${pathspecs[@]}" safe under set -u even
when empty, matching the existing primitive. The terminating (not non-terminating)
design is intentional: a $(...) capture returns the correct count but the caller does
not terminate (broken output: count + listing fall-through) -- a benign contract
violation, preferred over the non-terminating alternative whose forgotten exit 0 at any
of 6 call sites would produce the same broken output with 6 chances instead of 1.

IMPACT: Single source of truth for the -c dispatch is now in place (1 helper). The 6
dispatchers are wired in the next commit. Documented the new function in the in-file
header and git-config/lib/README.md.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
```

---

### Task 3: Wire the 6 `sl*` dispatchers to `run_count_mode`

**Goal:** Replace the duplicated ~13-line `-c` count block in each of the 6 `sl*` dispatchers with a one-line `run_count_mode` call (and the `git-statusbase` two-branch variant), collapsing the DRY smell. Behavior is unchanged — pinned by the existing `sl* -c` unit tests.

**Files:**
- Modify: `git-config/bin/git-sls` (state: `staged`)
- Modify: `git-config/bin/git-slu` (state: `unstaged`)
- Modify: `git-config/bin/git-slk` (state: `untracked`)
- Modify: `git-config/bin/git-sli` (state: `ignored`)
- Modify: `git-config/bin/git-slc` (state: `conflicted`)
- Modify: `git-config/bin/git-statusbase` (states: `all` / `all+untracked`, branch on `$include_untracked`)

**Acceptance Criteria:**
- [ ] Each of the 5 single-state dispatchers replaces its 13-line count block (the `# Count mode: ...` comment + the `if $count_only; then ... fi` block) with a 3-line `# Count mode: ...` pointer + `if $count_only; then run_count_mode ...; fi`.
- [ ] `git-statusbase` keeps its `if $include_untracked` if/else but swaps the inner guard+exit for `run_count_mode` (inlining `all+untracked` vs `all` — no top-level `local`, which is fatal under `set -euo pipefail`).
- [ ] The `~7`-line WHY comment is gone from all 6 call sites (it lives once in `run_count_mode`'s docblock); each site keeps a one-line pointer.
- [ ] All existing `sl* -c` unit tests stay green unchanged: `hug slc -c: -c + --json errors (mutually exclusive)`, `hug slk -c: counts a newline-containing filename once (NUL-safe)`, the `slu -c` pathspec test, `sls`/`sli`/`sl`/`sla` `-c` tests.
- [ ] `make sanitize` passes for all 6 edited dispatchers.

**Verify:** `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="-c" TEST_SHOW_ALL_RESULTS=1` → all `sl* -c` tests pass; then `make test` → full suite green; then `make sanitize` → clean.

**Steps:**

- [ ] **Step 1: Replace the count block in the 5 single-state dispatchers.**

Each of `git-sls`, `git-slu`, `git-slk`, `git-sli`, `git-slc` contains this exact 13-line block (only the state argument on the `count_files_with_status <state>` line differs — `staged` / `unstaged` / `untracked` / `ignored` / `conflicted` respectively):

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
  count_files_with_status <STATE> "${pathspecs[@]}"
  exit 0
fi
```

Replace the entire block (the 7-line comment + the 6-line `if`) with:

```bash
# Count mode: -c/--count dispatch (see run_count_mode in hug-select-files).
# --json passed only when $json_output is true (the codebase stores booleans as
# true/false strings; ${json_output:+--json} would ALWAYS expand — see run_count_mode).
if $count_only; then
  if $json_output; then
    run_count_mode --json <STATE> "${pathspecs[@]}"
  else
    run_count_mode <STATE> "${pathspecs[@]}"
  fi
fi
```

Substitute `<STATE>` per file:
- `git-sls` → `staged`
- `git-slu` → `unstaged`
- `git-slk` → `untracked`
- `git-sli` → `ignored`
- `git-slc` → `conflicted`

(Confirm each block matches the "before" above by reading the file — they were verified identical except the state line. The `run_count_mode` function is sourced via `hug-select-files`, which each dispatcher already loads in its `for f in hug-common hug-git-kit hug-select-files output_json_status` line — no new source line needed.)

- [ ] **Step 2: Replace the count block in `git-statusbase`.**

`git-config/bin/git-statusbase` contains this 18-line block (it has an extra dedup comment line and an `if $include_untracked` if/else):

```bash
# Count mode: print the number of matching files (the grep -c of listings).
# NUL-safe + Bash-4.0-safe via count_files_with_status (hug-select-files):
# counts git's NUL-delimited records, so newline-containing filenames count
# once, and no `local -n` nameref (Bash 4.3+) is reached. The count is the
# whole answer: it suppresses the trailing summary and is mutually exclusive
# with --json (like `hug wtl`'s --json --path-only error). all/all+untracked
# dedup a file that is both staged and unstaged (one MM record in porcelain).
if $count_only; then
  if $json_output; then
    error "-c/--count and --json are mutually exclusive"
  fi
  if $include_untracked; then
    count_files_with_status all+untracked "${pathspecs[@]}"
  else
    count_files_with_status all "${pathspecs[@]}"
  fi
  exit 0
fi
```

Replace the entire block with (a scratch var `_slc_state` selects `all+untracked` vs `all` — **no `local`**, which is fatal at script top level under `set -euo pipefail`; the dispatcher already uses non-local top-level vars like `pathspecs`/`list_opts`. Then the same two-branch over `$json_output`):

```bash
# Count mode: -c/--count dispatch (see run_count_mode in hug-select-files).
# --json passed only when $json_output is true (the codebase stores booleans as
# true/false strings; ${json_output:+--json} would ALWAYS expand — see run_count_mode).
if $count_only; then
  if $include_untracked; then _slc_state=all+untracked; else _slc_state=all; fi
  if $json_output; then
    run_count_mode --json "$_slc_state" "${pathspecs[@]}"
  else
    run_count_mode "$_slc_state" "${pathspecs[@]}"
  fi
fi
```

(The `all`/`all+untracked` dedup rationale that was in the dropped comment is relocated, not lost — it lives in `count_files_with_status`'s header and is summarized in `run_count_mode`'s docblock.)

- [ ] **Step 3: Run the `sl* -c` unit tests.**

Run: `make test-unit TEST_FILE=test_status_staging.bats TEST_FILTER="-c" TEST_SHOW_ALL_RESULTS=1`
Expected: PASS — every `sl* -c` test passes unchanged. These tests pin the contract end-to-end: `hug slc -c: -c + --json errors (mutually exclusive)` (line ~1953), `hug slk -c: counts a newline-containing filename once (NUL-safe)` (line ~1966), the `slu -c` pathspec test (line ~1981), and the `sls`/`sli`/`sl`/`sla` `-c` tests (lines ~1996-2019). If any fails, the dispatcher wiring diverged from the original semantics — re-check the state argument and that `--json` is passed via the two-branch `if $json_output` idiom (NOT `${json_output:+--json}`, which is broken for true/false-string booleans).

- [ ] **Step 4: Run the full suite.**

Run: `make test`
Expected: PASS (all BATS + pytest). This catches any cross-command regression.

- [ ] **Step 5: Run shellcheck on the edited dispatchers.**

Run: `make sanitize`
Expected: clean (the edits remove code, not add constructs; `run_count_mode` is the only new construct and it lives in the already-checked `hug-select-files`).

- [ ] **Step 6: Commit.**

```bash
cd /home/ecc/src/hug-scm.WT.refactor-sl-count-engine-258-259
hug a git-config/bin/git-sls git-config/bin/git-slu git-config/bin/git-slk git-config/bin/git-sli git-config/bin/git-slc git-config/bin/git-statusbase
hug c -F - <<'EOF' # GIT-BLOCK:BYPASS
refactor(sl*): wire the 6 sl* dispatchers to run_count_mode (#258)

WHY: With run_count_mode now in hug-select-files (previous commit), the 6 sl* dispatchers
can each drop their ~13-line duplicated -c count block (and its ~7-line WHY comment) for a
one-line call. Single source of truth: any future change to -c semantics is now one edit,
not six.

WHAT: Replaced the count block in git-sls (staged), git-slu (unstaged), git-slk (untracked),
git-sli (ignored), git-slc (conflicted), and git-statusbase (all / all+untracked) with
`run_count_mode` calls inside `if $count_only; then ...; fi`, using the two-branch
`if $json_output; then run_count_mode --json <state> ...; else run_count_mode <state> ...; fi`
idiom (do NOT use ${json_output:+--json} -- broken for true/false-string booleans).
git-statusbase keeps its if/else over $include_untracked, inlining the state
(all vs all+untracked) -- no top-level `local`, which is fatal under set -euo pipefail.
The ~7-line WHY comment is gone from all 6 sites; it lives once in run_count_mode's
docblock, and each site carries a one-line pointer. sl/sla delegate to git-statusbase via
.gitconfig aliases, so they are covered transitively.

HOW: Behavior-preserving by construction -- run_count_mode encapsulates exactly the
mutual-exclusion guard + count_files_with_status call + exit 0 that each block had (the
--json check runs before count_files_with_status, matching the original ordering). The
existing sl* -c unit tests (slc -c --json mutex, slk -c NUL-safety, slu -c pathspec,
sls/sli/sl/sla -c) pin the contract end-to-end and stay green unchanged.

IMPACT: 6 near-verbatim copies of a 13-line block collapse to one helper + six one-line
calls. The sl* -c engine is now DRY; the count_files_with_status primitive (which now
checks the repo, #259) is reached only through the wrapper in production.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
```

---

## Self-Review

**1. Spec coverage:**
- #259 (`check_git_repo` first line of `count_files_with_status`, declare `hug-git-repo` dep, non-repo clean error) → Task 1. ✓
- #258 (`run_count_mode` wrapper in `hug-select-files`, terminating, `--json` mutex, 6 dispatchers collapse) → Task 2 (helper + tests) + Task 3 (wire dispatchers). ✓
- Doc-perimeter (`git-config/lib/README.md` — `run_count_mode` entry + amended `count_files_with_status` contract) → Task 1 (amend) + Task 2 (add). ✓
- In-file header comment (function list + repo-precondition note) → Task 1 (count_files_with_status line + Depends-on) + Task 2 (run_count_mode line). ✓
- Implementation order forced #259 then #258 → Task 1 before Task 2 before Task 3. ✓
- Out-of-scope arg-parsing hardening → tracked as #260, referenced in the header; not implemented here. ✓
- Risks (top-level `local` footgun in `git-statusbase`) → Task 3 Step 2 inlines the state, explicitly notes no `local`. ✓
- Risks (terminating helper) → Task 2 docblock + commit message document it. ✓

**2. Placeholder scan:** No TBD/TODO/"implement later"/"add appropriate error handling". Each step contains the actual code. State arguments are concretely substituted per file (no `<STATE>` left in a final artifact — it's a template with an explicit per-file substitution list). ✓

**3. Type consistency:** `run_count_mode` signature `[--json] <state> [pathspec...]` is identical in Task 2 (definition), Task 3 (call sites), the README entry, and the header comment. `count_files_with_status` signature unchanged. The two-branch `if $json_output` call-site idiom is identical at all 6 sites (NOT `${json_output:+--json}`, which is broken for true/false-string booleans — see the Implementation note in the spec). ✓

**4. Ambiguity check:** The `git-statusbase` "no `local`" constraint is called out explicitly (the one place a reader might reach for a temp var). The `--separate-stderr` test convention is pinned to an existing repo test (`test_status_staging.bats:1947`). ✓

---

## Notes for the executor

- **Worktree CWD:** the Bash tool resets CWD between calls. Every `cd`/`make`/`hug` command in this plan either starts with `cd /home/ecc/src/hug-scm.WT.refactor-sl-count-engine-258-259` or is run after one. Do not run `make`/tests from the main checkout — run them inside the worktree.
- **Known local-only test flakes (NOT regressions):** if `make test-lib` fails `test_hug-file-input.bats` (global `core.excludesFile` lists `.env`) or `test_hug-common.bats` (symlinked-checkout `HUG_HOME` mismatch), those are pre-existing environment issues (elifarley/hug-scm#197, #198), green in CI — not caused by this work. Investigate only if a `count_files_with_status` / `run_count_mode` / `sl* -c` test fails.
- **`GIT-BLOCK:BYPASS`:** the commit bodies reference git internals (`git rev-parse`, `git status --porcelain`), which the `block-commands.py` hook string-matches. The trailing `# GIT-BLOCK:BYPASS` comment after the heredoc opener bypasses the hook without polluting the message. (See `.wolf/cerebrum.md`.)