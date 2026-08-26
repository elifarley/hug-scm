# #303 — us Scope Extraction + sl* Family Templating Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract git-us's inline scope-intersection block into a new `hug-pathspec` lib (with the F-003 batching fix), and collapse the five hand-copied sl\* scripts onto one `sl_family_main` entrypoint in a new `hug-status-listing` lib — zero user-visible behavior change except F-003's perf-only delta.

**Architecture:** Two INDEPENDENT extractions (Part 1 = Tasks 2–5, Part 2 = Tasks 6–7), either order, separate commits. New libs follow house conventions: double-load guards, nameref-out parameters, registration via the aggregator's source loop. Spec (source of truth): `docs/superpowers/specs/2026-08-25-us-scope-block-extraction-and-sl-family-templating-design.md` — READ IT FIRST, especially the roast-fixed contracts (set-difference over raw input lines; quiet-extra column; script-local search-meta).

**Tech Stack:** Bash (git-config/bin + git-config/lib), BATS (tests/lib, tests/unit), Makefile targets only.

## Global Constraints

- Work ONLY in this worktree (`~/src/hug-scm.WT.303-us-scope-block-extraction-and-sl-family-templating`).
- Mutations via hug ONLY: `hug a <files>` to stage, `hug c -F - <<'EOF' … EOF` to commit. NEVER raw `git add`/`git commit`.
- `make sanitize` before every commit.
- Tests via Makefile ONLY: `make test-lib TEST_FILE=test_hug-pathspec.bats`, `make test-unit TEST_FILE=…`.
- Probes invoke worktree scripts directly: `export HUG_HOME=<this worktree>; export PATH="$HUG_HOME/git-config/bin:$PATH"` — never the installed dispatcher.
- Red-first: a failing test exists BEFORE the code that passes it.
- Behavior contract: byte-identical messages and exit codes everywhere EXCEPT none — F-003 is perf-only. Any observable diff you didn't intend is a bug you introduced.
- Bash compatibility floor: the repo runs on stock bash ≥4.x; no `mapfile -d` existed anywhere before this PR — your NUL collector is its first instance, so guard empty records explicitly (spec C-007).
- Commit trailer on EVERY commit: `Co-authored-by: CommandCodeBot <noreply@commandcode.ai>` (via `hug c -F -` heredoc).

---

### Task 1: Characterization pins for sl\* family quiet-column + search-meta

**Files:**
- Modify: `tests/unit/test_status_staging.bats`

**Interfaces:**
- Consumes: existing fixture helpers already loaded in this file (`create_test_repo`, `create_slc_conflict_fixture`); hug dispatch through `PATH`/`HUG_HOME`.
- Produces: green pins asserting TODAY's behavior — `slk|sli|slc -q` suppress the status column; `sls|slu -q` preserve status prefixes; `slc --search-meta` prints category AND keywords lines; the other four print category only. These must stay untouched-green through Tasks 6–7.

- [ ] **Step 1: Write the characterization tests**

Append to `tests/unit/test_status_staging.bats`:

```bash
@test "hug slk -q: suppresses the status column (--suppress-status)" {
  local repo; repo=$(create_test_repo); cd "$repo"
  echo x > stray.txt   # untracked: visible to slk
  run hug slk -q
  assert_success
  assert_output --partial "stray.txt"
  refute_output --partial "??"        # status column suppressed
}

@test "hug slu -q: PRESERVES status prefixes" {
  local repo; repo=$(create_test_repo); cd "$repo"
  echo mod > tracked.txt; git add tracked.txt >/dev/null 2>&1 || hug a -- tracked.txt >/dev/null
  hug c -m base >/dev/null 2>&1 || true
  echo changed >> tracked.txt
  run hug slu -q
  assert_success
  assert_output --partial "U:Mod"     # unstaged prefixes stay under -q
}

@test "hug slc --search-meta: prints category AND keywords lines" {
  run hug slc --search-meta
  assert_success
  assert_output --partial 'category = ["status", "staging"]'
  assert_output --partial 'keywords = ["conflict","unmerged","merge","rebase"]'
}

@test "hug sls --search-meta: prints category only (no keywords)" {
  run hug sls --search-meta
  assert_success
  assert_output --partial 'category'
  refute_output --partial 'keywords'
}
```

(If an exact string mismatches — e.g. slc's real category JSON differs — fix the EXPECTED value from the actual script content, never the script. Read `git-config/bin/git-slc:2-6` first. The `slu` test may need `U:` spelled per `list_files_with_status`'s real prefix output; probe once with `HUG_QUIET= hug slu` in a scratch repo and pin what you see.)

- [ ] **Step 2: Run the new tests**

Run: `make test-unit TEST_FILE=test_status_staging.bats`
Expected: ALL PASS (these characterize today). A failure means the pin mis-reads reality — re-probe the script, fix the pin, rerun.

- [ ] **Step 3: Commit**

```bash
make sanitize
hug a tests/unit/test_status_staging.bats && hug c -F - <<'EOF'
test(status): pin sl* quiet-column and search-meta behavior pre-migration

Characterization rows for #303 Part 2: slk/sli/slc -q suppress the status
column (--suppress-status), sls/slu -q keep prefixes; slc alone carries
_hug_keywords in --search-meta. Green pins BEFORE the sl_family_main
migration so any byte-drift during templating fails loudly here.

Co-authored-by: CommandCodeBot <noreply@commandcode.ai>
EOF
```

---

### Task 2: `hug-pathspec` module + `root_to_cwd_relpath` (pure function first)

**Files:**
- Create: `git-config/lib/hug-pathspec`
- Modify: `git-config/lib/hug-git-kit:30` (add `hug-pathspec` to the module loop)
- Create: `tests/lib/test_hug-pathspec.bats`
- Modify: `git-config/lib/README.md` (add a `### hug-pathspec` section near the other module sections)

**Interfaces:**
- Produces: `_HUG_PATHSPEC_LOADED=1`; function `root_to_cwd_relpath <path>` → prints CWD-relative spelling of a root-relative path (prefix-strip when under `$(git rev-parse --show-prefix)`, else `../`-climb per prefix component, identity at root). Later tasks consume this name exactly.

- [ ] **Step 1: Write the failing test file**

Create `tests/lib/test_hug-pathspec.bats`:

```bash
#!/usr/bin/env bats
# Tests for hug-pathspec: pathspec scope-set construction + relpath conversion
load '../test_helper'
load '../../git-config/lib/hug-common'

setup() {
  require_hug
  export HUG_HOME="$BATS_TEST_DIRNAME/../.."
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "hug-pathspec: sources via hug-git-kit after registration" {
  . "$REPO_ROOT/git-config/lib/hug-git-kit"
  declare -F root_to_cwd_relpath >/dev/null
}
```

Run: `make test-lib TEST_FILE=test_hug-pathspec.bats`
Expected: FAIL — `root_to_cwd_relpath` undefined (registration doesn't exist yet).

- [ ] **Step 2: Add failing relpath tests**

Append to `tests/lib/test_hug-pathspec.bats`:

```bash
# Helper: run root_to_cwd_relpath INSIDE a subdir of a scratch repo so
# `git rev-parse --show-prefix` reflects the sub/ context.
relpath_from_sub() {
  local sub="$1"; shift
  local repo; repo=$(mktemp -d)
  git -C "$repo" init -q
  mkdir -p "$repo/$sub"
  (cd "$repo/$sub" && {
    . "$REPO_ROOT/git-config/lib/hug-common" >/dev/null 2>&1 || true
    . "$REPO_ROOT/git-config/lib/hug-pathspec"
    root_to_cwd_relpath "$@"
  })
  rm -rf "$repo"
}

@test "relpath: strips cwd prefix when target lives under cwd" {
  run relpath_from_sub docs docs/a.md
  assert_success
  assert_output "a.md"
}

@test "relpath: climbs when target lives outside cwd (:(top) spelling)" {
  run relpath_from_sub docs ../root.txt
  assert_output "../root.txt"
  # NOTE: input is ROOT-relative per contract; from docs/, root.txt climbs
  run relpath_from_sub docs root.txt
  assert_output "../root.txt"
}

@test "relpath: identity when cwd is repo root (empty show-prefix)" {
  run relpath_from_sub . top.txt
  assert_output "top.txt"
}

@test "relpath: multi-level climb from nested subdir" {
  run relpath_from_sub a/b/c top.txt
  assert_output "../../../top.txt"
}

@test "relpath: strips multi-component shared prefix" {
  run relpath_from_sub a/b a/b/deep/f.txt
  assert_output "deep/f.txt"
}
```

Run: `make test-lib TEST_FILE=test_hug-pathspec.bats`
Expected: FAIL — function still undefined.

- [ ] **Step 3: Implement the module**

Create `git-config/lib/hug-pathspec`:

```bash
# shellcheck shell=bash
# Library: hug-pathspec — pathspec scope-set construction, source-list
# canonicalization, and root↔CWD relpath conversion (#303).
# Depends on: hug-output (error_usage), hug-git-files conventions; callers
# reach those via hug-common's bundle (loaded before hug-git-kit everywhere
# the kit is sourced).
# Functions:
#   - root_to_cwd_relpath <path>: print the CWD-relative spelling of a
#     ROOT-relative path (prefix-strip under cwd, else ../climb; identity
#     at repo root).

# Prevent double-loading
[[ -n "${_HUG_PATHSPEC_LOADED:-}" ]] && return 0
readonly _HUG_PATHSPEC_LOADED=1

# Print the CWD-relative spelling of a root-relative path.
# Usage: root_to_cwd_relpath <root-relative-path>
# Pure over (path, $(git rev-parse --show-prefix)) — unit-testable.
root_to_cwd_relpath() {
  local f="$1"
  local cwd_prefix climb tmp
  cwd_prefix=$(git rev-parse --show-prefix)
  climb=""
  tmp="${cwd_prefix%/}"
  while [[ -n $tmp ]]; do
    climb+="../"
    if [[ "$tmp" == */* ]]; then tmp="${tmp#*/}"; else tmp=""; fi
  done
  if [[ -n $cwd_prefix && $f == "$cwd_prefix"* ]]; then
    printf '%s\n' "${f#"$cwd_prefix"}"
  else
    printf '%s%s\n' "$climb" "$f"
  fi
}
```

Register in `git-config/lib/hug-git-kit` line 30 — add `hug-pathspec` to the `for module in …` list (after `hug-git-files`).

Add to `git-config/lib/README.md` (after the hug-cli-flags section):

```markdown
### hug-pathspec

Pathspec scope-set construction, source-list canonicalization, and root↔CWD relpath conversion (#303).

**Features:**
- `root_to_cwd_relpath <path>` — print the CWD-relative spelling of a root-relative path
- `build_scope_set <out_arr> <pathspec…>` — tracked ∪ staged-deletions, root-relative (Task 3)
- `canonicalize_source_lines <out_resolved> <out_unresolved> [--from-commit] <line…>` — batched F-003 canonicalization (Task 4)
```

- [ ] **Step 4: Run tests until green**

Run: `make test-lib TEST_FILE=test_hug-pathspec.bats`
Expected: ALL PASS. If the climb test fails on trailing slashes, check `${cwd_prefix%/}` handling — `show-prefix` is `docs/` WITH trailing slash.

- [ ] **Step 5: Commit**

```bash
make sanitize
hug a git-config/lib/hug-pathspec git-config/lib/hug-git-kit tests/lib/test_hug-pathspec.bats git-config/lib/README.md && hug c -F - <<'EOF'
feat(lib): add hug-pathspec module with root_to_cwd_relpath (#303)

First slice of the us scope-block extraction: the module registers in
hug-git-kit's source loop (kit consumers get it transitively; error_usage
reaches it because git-us sources hug-common before hug-git-kit, and
hug-common co-loads hug-output). root_to_cwd_relpath is the pure piece —
prefix-strip vs ../climb decided against `git rev-parse --show-prefix`,
identity at root. Logic moved verbatim from git-us:306-312; direct lib
tests become possible for what was end-to-end-only.

Co-authored-by: CommandCodeBot <noreply@commandcode.ai>
EOF
```

---

### Task 3: `build_scope_set` (tracked ∪ staged-deletions)

**Files:**
- Modify: `git-config/lib/hug-pathspec`
- Modify: `tests/lib/test_hug-pathspec.bats`

**Interfaces:**
- Consumes: `error_usage` (via hug-output, transitively loaded).
- Produces: `build_scope_set <out_arr_nameref> <pathspec…>` — fills `<out_arr_nameref>` with the ROOT-relative union of `git ls-files --full-name` paths and staged-deletion paths (`--diff-filter=D --no-renames`). Invalid pathspec → usage error exit 2. Unborn HEAD safe.

- [ ] **Step 1: Write failing tests**

Append to `tests/lib/test_hug-pathspec.bats`:

```bash
# Helper: fresh scratch repo with one committed file
new_scratch_repo() {
  local repo; repo=$(mktemp -d)
  git -C "$repo" init -q
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  mkdir -p "$repo/docs"
  echo a > "$repo/docs/a.md"
  echo r > "$repo/root.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m base
  printf '%s' "$repo"
}

call_build_scope_set() {           # <repo-cd-dir> <out-var> <pathspecs...>
  local dir="$1"; local outvar="$2"; shift 2
  (
    cd "$dir"
    unset _HUG_PATHSPEC_LOADED
    . "$REPO_ROOT/git-config/lib/hug-common" >/dev/null 2>&1 || true
    . "$REPO_ROOT/git-config/lib/hug-git-kit"
    build_scope_set "$outvar" "$@"
    eval "printf '%s\n' \${$outvar[@]+\"\${$outvar[@]}\"}"
  )
}

@test "build_scope_set: tracked files in scope" {
  local repo; repo=$(new_scratch_repo)
  run call_build_scope_set "$repo" out
  assert_success
  assert_line "docs/a.md"
  assert_line "root.txt"
  rm -rf "$repo"
}

@test "build_scope_set: union includes STAGED DELETIONS (index entry gone)" {
  local repo; repo=$(new_scratch_repo)
  git -C "$repo" rm -q --cached docs/a.md   # staged deletion
  run call_build_scope_set "$repo" out
  assert_success
  assert_line "docs/a.md"             # present VIA the D-filter half
  rm -rf "$repo"
}

@test "build_scope_set: --no-renames splits a staged rename's D side" {
  local repo; repo=$(new_scratch_repo)
  git -C "$repo" mv docs/a.md docs/b.md      # staged rename
  run call_build_scope_set "$repo" out
  assert_success
  assert_line "docs/a.md"             # old path joins via --no-renames
  assert_line "docs/b.md"
  rm -rf "$repo"
}

@test "build_scope_set: unborn HEAD does not fatal" {
  local repo; repo=$(mktemp -d)
  git -C "$repo" init -q
  echo x > "$repo/x.txt"; git -C "$repo" add x.txt
  run call_build_scope_set "$repo" out
  assert_success
  assert_line "x.txt"
  rm -rf "$repo"
}

@test "build_scope_set: invalid pathspec dies with usage error (exit 2)" {
  local repo; repo=$(new_scratch_repo)
  run call_build_scope_set "$repo" out ':('
  [[ "$status" -eq 2 ]]
  rm -rf "$repo"
}
```

NOTE on the helper's last line: `call_build_scope_set` prints the out-array by indirection — use exactly

```bash
    eval "printf '%s\n' \${$outvar[@]+\"\${$outvar[@]}\"}"
```

as that final line inside `call_build_scope_set` (the subshell's caller reads `$out`). A nameref (`local -n r=$outvar; printf '%s\n' "${r[@]}"`) is an equivalent alternative — pick ONE style and stay consistent across all helpers.

Run: `make test-lib TEST_FILE=test_hug-pathspec.bats`
Expected: NEW tests FAIL (function undefined).

- [ ] **Step 2: Implement**

Append to `git-config/lib/hug-pathspec`:

```bash
# Build the ROOT-relative scope set: tracked ∪ staged-deletions.
# Usage: build_scope_set <out_arr> <pathspec...>
# WHY the union (PR-B Codex P1): `ls-files` lists INDEX entries; a staged
# deletion removes the entry, so without the D-half union,
# `us --from-commit <c> -- src/` silently leaves 'D src/x' staged.
# WHY --no-renames: rename detection ON collapses `mv old new` to one
# R-status whose D side never emits old; splitting restores old.
build_scope_set() {
  local -n _bss_out=$1
  shift
  local scope_tracked="" scope_deleted="" joined=""
  scope_tracked=$(git ls-files --full-name -- "$@") ||
    error_usage "Invalid pathspec in unstage scope. See 'hug help :pathspec'."
  scope_deleted=$(git diff --cached --name-only --diff-filter=D --no-renames -- "$@") ||
    error_usage "Invalid pathspec in unstage scope. See 'hug help :pathspec'."
  if [[ -n "$scope_tracked" && -n "$scope_deleted" ]]; then
    joined="${scope_tracked}"$'\n'"${scope_deleted}"
  else
    joined="${scope_tracked}${scope_deleted}"   # no phantom blank line
  fi
  _bss_out=()
  [[ -n "$joined" ]] && mapfile -t _bss_out <<< "$joined"
}
```

- [ ] **Step 3: Run tests until green**

Run: `make test-lib TEST_FILE=test_hug-pathspec.bats`
Expected: ALL PASS including the five new ones.

- [ ] **Step 4: Commit**

```bash
make sanitize
hug a git-config/lib/hug-pathspec tests/lib/test_hug-pathspec.bats && hug c -F - <<'EOF'
feat(lib): build_scope_set — tracked ∪ staged-deletions scope builder (#303)

Verbatim semantics from git-us:218-245: ls-files --full-name unioned with
diff --cached --diff-filter=D --no-renames; join avoids the phantom blank
line that becomes a bad assoc subscript under set -u; unborn HEAD safe
(no --with-tree here — that guard belongs to the tracked-check consumer);
invalid pathspecs die loud via error_usage (exit 2). Direct lib tests pin
the rename-split case that was previously reachable only end-to-end.

Co-authored-by: CommandCodeBot <noreply@commandcode.ai>
EOF
```

---

### Task 4: `canonicalize_source_lines` (F-003 batching + representation contract)

**Files:**
- Modify: `git-config/lib/hug-pathspec`
- Modify: `tests/lib/test_hug-pathspec.bats`

**Interfaces:**
- Consumes: nothing from earlier tasks beyond the module itself.
- Produces: `canonicalize_source_lines <out_resolved> <out_unresolved> [--from-commit] <line…>` — resolved lines are ROOT-relative (from-commit input passes through; from-file literals resolve by membership against one batched NUL call; free-form dir/glob lines resolve per-line); unresolved lines appended to `<out_unresolved>` in input order. THE F-003 CONTRACT: a 500-line plain-filename list triggers exactly ONE `git ls-files` invocation.

- [ ] **Step 1: Write the failing tests**

Append to `tests/lib/test_hug-pathspec.bats`:

```bash
# Counting git stub: increments $COUNTER_FILE then delegates to real git.
counting_git_stub() {
  local bin_dir; bin_dir=$(mktemp -d)
  cat > "$bin_dir/git" <<STUB
#!/usr/bin/env bash
printf 'x\n' >> '${COUNT_STUB_COUNTER}'
exec $(command -v git) "\$@"
STUB
  chmod +x "$bin_dir/git"
  printf '%s' "$bin_dir"
}

call_canonicalize() {               # <repo> <extra-env-assignments...> -- <lines...>
  local repo="$1"; shift
  local from_commit=false
  local -a pre=() lines=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do pre+=("$1"); shift; done
  shift                             # drop --
  lines=("$@")
  (
    cd "$repo"
    unset _HUG_PATHSPEC_LOADED
    . "$REPO_ROOT/git-config/lib/hug-common" >/dev/null 2>&1 || true
    . "$REPO_ROOT/git-config/lib/hug-git-kit"
    local -a res=() unres=()
    if [[ "${pre[*]:-}" == *--from-commit* ]]; then
      canonicalize_source_lines res unres --from-commit ${lines[@]+"${lines[@]}"}
    else
      canonicalize_source_lines res unres ${lines[@]+"${lines[@]}"}
    fi
    printf 'R:%s\n' ${res[@]+"${res[@]}"}
    printf 'U:%s\n' ${unres[@]+"${unres[@]}"}
  )
}

@test "canonicalize: literal filenames resolve via ONE batched call (F-003)" {
  local repo; repo=$(new_scratch_repo)
  COUNT_STUB_COUNTER="$(mktemp)"; export COUNT_STUB_COUNTER
  : > "$COUNT_STUB_COUNTER"
  local bindir; bindir=$(counting_git_stub)
  local -i calls_before
  # count baseline: repo setup already ran; measure DELTA across the call
  run env PATH="$bindir:$PATH" bash -c '
    cd "'"$repo"'"
    unset _HUG_PATHSPEC_LOADED
    . "'"$REPO_ROOT"'/git-config/lib/hug-common" >/dev/null 2>&1 || true
    . "'"$REPO_ROOT"'/git-config/lib/hug-git-kit"
    local -a res=() unres=()
    canonicalize_source_lines res unres docs/a.md root.txt nope.txt
  '
  # 500-line variant drives the real assertion; single call suffices here
  assert_success
  rm -rf "$bindir" "$repo"
}

@test "canonicalize: 500 plain filenames => exactly one git invocation" {
  local repo; repo=$(new_scratch_repo)
  COUNT_STUB_COUNTER="$(mktemp)"; export COUNT_STUB_COUNTER
  : > "$COUNT_STUB_COUNTER"
  local bindir; bindir=$(counting_git_stub)
  local -a big=()
  local i; for ((i=1;i<=500;i++)); do big+=("docs/a.md"); done   # dupes fine
  run env PATH="$bindir:$PATH" bash -c "
    cd '$repo'
    unset _HUG_PATHSPEC_LOADED
    . '$REPO_ROOT/git-config/lib/hug-common' >/dev/null 2>&1 || true
    . '$REPO_ROOT/git-config/lib/hug-git-kit'
    local -a res=() unres=()
    canonicalize_source_lines res unres ${big[@]+"${big[@]}"}
    printf '%s\n' \"\${#res[@]}\"
  "
  assert_success
  assert_output "500"                # every dupe resolves
  [[ $(wc -l < "$COUNT_STUB_COUNTER") -eq 1 ]] || {
    echo "expected 1 git call, got $(wc -l < "$COUNT_STUB_COUNTER")"; return 1; }
  rm -rf "$bindir" "$COUNT_STUB_COUNTER" "$repo"
}

@test "canonicalize: dir spec and glob RESOLVE (never marked unresolved)" {
  local repo; repo=$(new_scratch_repo)
  run call_canonicalize "$repo" -- 'docs/' 'docs/*.md'
  assert_success
  assert_line "R:docs/a.md"          # ROOT-relative git spelling, not the input form
  refute_line "U:docs/"
  refute_line "U:docs/*.md"
  rm -rf "$repo"
}

@test "canonicalize: CWD-relative literal from subdir lifts to root spelling (PR #318 review)" {
  # hug us --from-file run from sub/ with line 'a.txt': git emits
  # 'sub/a.txt'; membership must probe the lifted root spelling and push
  # it resolved — 'a.txt' alone never matches the root-relative set.
  local repo; repo=$(new_scratch_repo)
  run bash -c "
    mkdir -p '$repo/sub'
    cd '$repo/sub'
    unset _HUG_PATHSPEC_LOADED
    . '$REPO_ROOT/git-config/lib/hug-common' >/dev/null 2>&1 || true
    . '$REPO_ROOT/git-config/lib/hug-git-kit'
    local -a res=() unres=()
    canonicalize_source_lines res unres ../docs/a.md
    printf 'R:%s\n' \${res[@]+\"\${res[@]}\"}
    printf 'U:%s\n' \${unres[@]+\"\${unres[@]}\"}
  "
  assert_line "R:docs/a.md"
  refute_line "U:../docs/a.md"
  rm -rf "$repo"
}

@test "canonicalize: unknown literal lands in unresolved" {
  local repo; repo=$(new_scratch_repo)
  run call_canonicalize "$repo" ghost.txt
  assert_line "U:ghost.txt"
  rm -rf "$repo"
}

@test "canonicalize: --from-commit passes lines through untouched" {
  local repo; repo=$(new_scratch_repo)
  run call_canonicalize "$repo" --from-commit -- whatever-name.txt
  assert_line "R:whatever-name.txt"   # NOT resolved against the repo
  rm -rf "$repo"
}

@test "canonicalize: empty records dropped (trailing-NUL guard)" {
  local repo; repo=$(new_scratch_repo)
  run call_canonicalize "$repo" docs/a.md
  assert_success
  assert_line "R:docs/a.md"
  refute_line "R:"
  refute_line "U:"
  rm -rf "$repo"
}
```

Run: `make test-lib TEST_FILE=test_hug-pathspec.bats`
Expected: NEW tests FAIL (function undefined).

- [ ] **Step 2: Implement**

Append to `git-config/lib/hug-pathspec`:

```bash
# Canonicalize source-list lines (--from-file/--from-commit payloads) to
# ROOT-relative paths. Usage:
#   canonicalize_source_lines <out_resolved> <out_unresolved> \
#     [--from-commit] <line...>
# Representation contract (roast C-001): a line is RESOLVED iff it
# contributes >=1 output path. Fast path: probe the line's ROOT-relative
# spelling against the batched NUL output set (zero extra processes).
# ANY miss (dir spellings, globs, odd forms, unknown files) falls back to
# today's per-line `git ls-files --full-name` so fan-out and failure
# semantics stay byte-identical with pre-extraction behavior. Plain-
# filename lists: ONE git call total — THE F-003 FIX (was: one process
# PER LINE).
canonicalize_source_lines() {
  local -n _csl_resolved=$1
  local -n _csl_unresolved=$2
  shift 2
  local from_commit=false
  if [[ "${1:-}" == "--from-commit" ]]; then
    from_commit=true
    shift
  fi

  if $from_commit; then
    # Root-relative BY CONSTRUCTION (extract_files_from_commit diffs from
    # the repo root); resolving against CWD wrongly rejected
    # `us --from-commit HEAD -- .` from sub/.
    _csl_resolved=()
    local fc
    for fc in ${1+"$@"}; do [[ -n "$fc" ]] && _csl_resolved+=("$fc"); done
    _csl_unresolved=()
    return 0
  fi

  local tree_opt=()
  if git rev-parse --verify -q HEAD > /dev/null 2>&1; then
    tree_opt=(--with-tree=HEAD)
  fi

  # Every NON-EMPTY line rides the batched call as a pathspec argument.
  # (An empty string is a FATAL git pathspec and resolves nothing anyway;
  # empty list lines resolve to nothing.)
  local -a specs=() line0
  for line0 in ${1+"$@"}; do
    [[ -n "$line0" ]] && specs+=("$line0")
  done

  # THE batched call — NUL output MUST NOT pass through command
  # substitution: bash variables cannot contain NUL bytes, $(...) strips
  # the delimiters and concatenates every pathname into one record, which
  # empties `seen` and marks every valid literal unresolved (PR #318
  # review, codex P1). Transport is a temp FILE: NUL-safe AND the exit
  # status survives the round-trip, keeping failures loud (the house
  # `$(…) || error` idiom is unavailable for binary-clean output).
  local -a batch_paths=() rec
  local batch_ok=0 tmp_nul
  if [[ ${#specs[@]} -gt 0 ]]; then
    tmp_nul="$(mktemp "${TMPDIR:-/tmp}/hug-csl.XXXXXX")" || tmp_nul=""
    if [[ -n "$tmp_nul" ]] &&
      git ls-files -z --full-name ${tree_opt[@]+"${tree_opt[@]}"} \
        -- ${specs[@]+"${specs[@]}"} > "$tmp_nul"; then
      batch_ok=1
      while IFS= read -r -d '' rec; do
        [[ -n "$rec" ]] && batch_paths+=("$rec")   # drop empty records:
        # a trailing NUL yields a final empty element under bash's delimited
        # read — the phantom-subscript class git-us guards at :238-245.
      done < "$tmp_nul"
    fi
    [[ -n "${tmp_nul:-}" ]] && rm -f "$tmp_nul"
  fi

  if [[ $batch_ok -eq 1 ]]; then
    declare -A seen=()
    local p
    for p in ${batch_paths[@]+"${batch_paths[@]}"}; do seen["$p"]=1; done
  else
    # Batch failed (malformed magic spelling poisons the WHOLE invocation)
    # or nothing to batch: fall back to today's per-line loop for ALL
    # lines, byte-for-byte — the bad line must die in hug_us naming ITS
    # OWN line ("File 'X' is not tracked"), never take its valid siblings
    # down with a poisoned batch.
    _csl_resolved=()
    _csl_unresolved=()
    for line0 in ${specs[@]+"${specs[@]}"}; do
      local -a one_hits=()
      while IFS= read -r -d '' rec; do
        [[ -n "$rec" ]] && one_hits+=("$rec")
      done < <(git ls-files -z --full-name ${tree_opt[@]+"${tree_opt[@]}"} -- "$line0")
      if [[ ${#one_hits[@]} -gt 0 ]]; then
        local oh
        for oh in ${one_hits[@]+"${one_hits[@]}"}; do _csl_resolved+=("$oh"); done
      else
        _csl_unresolved+=("$line0")
      fi
    done
    return 0
  fi

  _csl_resolved=()
  _csl_unresolved=()
  local line
  for line in ${1+"$@"}; do
    [[ -n "$line" ]] || continue   # empty input lines resolve to nothing
    # Normalize the CWD-relative spelling: strip leading ./, collapse
    # duplicate slashes.
    local norm="$line"
    norm="${norm#./}"
    while [[ "$norm" == *//* ]]; do norm="${norm//\/\//\/}"; done
    # Probe in GIT's representation: ls-files --full-name emits
    # ROOT-relative paths, so a CWD-relative literal ('a.txt' from sub/)
    # must be lifted to its root spelling ('sub/a.txt') BEFORE the lookup,
    # and the ROOT spelling is what gets pushed (PR #318 review, codex P1:
    # the downstream root_to_cwd_relpath consumes root-relative input).
    local root_spell="$norm"
    if [[ $norm != /* ]]; then
      local prefix base
      prefix=$(git rev-parse --show-prefix)
      base="${prefix%/}"
      root_spell="$norm"
      while [[ "$root_spell" == ../* ]]; do
        root_spell="${root_spell#../}"
        if [[ "$base" == */* ]]; then base="${base%/*}"; else base=""; fi
      done
      root_spell="${base:+$base/}${root_spell#./}"
    fi
    if [[ -n "${seen[$root_spell]:-}" ]]; then
      _csl_resolved+=("$root_spell")
    else
      # Miss: dir spellings, globs, absolute paths, unknown files —
      # today's per-line resolution decides (fan-out preserved; empty
      # result => unresolved, dying loud downstream exactly as before).
      local -a free_hits=()
      while IFS= read -r -d '' rec; do
        [[ -n "$rec" ]] && free_hits+=("$rec")
      done < <(git ls-files -z --full-name ${tree_opt[@]+"${tree_opt[@]}"} -- "$line")
      if [[ ${#free_hits[@]} -gt 0 ]]; then
        local fh
        for fh in ${free_hits[@]+"${free_hits[@]}"}; do _csl_resolved+=("$fh"); done
      else
        _csl_unresolved+=("$line")
      fi
    fi
  done
}
```

(All NUL collection uses the `read -r -d ''` loop pattern above — no `mapfile -d` anywhere, staying inside the repo's proven bash surface.)

- [ ] **Step 3: Run tests until green**

Run: `make test-lib TEST_FILE=test_hug-pathspec.bats`
Expected: ALL PASS. The one-call assertion is the acceptance gate for F-003.

- [ ] **Step 4: Commit**

```bash
make sanitize
hug a git-config/lib/hug-pathspec tests/lib/test_hug-pathspec.bats && hug c -F - <<'EOF'
feat(lib): canonicalize_source_lines — batched F-003 fix with pinned
representation contract (#303)

One `git ls-files -z --full-name` call carries ALL list lines as
pathspecs (was: one process per line — 1000-line list cost 1000
subprocesses). NUL output streams to a temp FILE, never through command
substitution (bash variables cannot hold NUL; $(...) would concatenate
every pathname into one record and mark every valid literal unresolved).
Attribution follows roast C-001: membership probes run against the line's
ROOT-relative spelling (git emits root-relative; a CWD-relative literal
from sub/ lifts before lookup), any miss falls back to today's per-line
call so fan-out and loud-failure semantics stay byte-identical. Empty
records drop at collection (trailing-NUL phantom element).

Co-authored-by: CommandCodeBot <noreply@commandcode.ai>
EOF
```

---

### Task 5: Rewire git-us onto the three functions

**Files:**
- Modify: `git-config/bin/git-us:187-389` (delete the inline intersection internals; keep orchestration)

**Interfaces:**
- Consumes: `build_scope_set`, `canonicalize_source_lines`, `root_to_cwd_relpath` (Tasks 2–4).
- Produces: no interface change — `hug us` CLI contract identical; `tests/unit/test_us_interactive.bats` stays green untouched.

- [ ] **Step 1: Confirm characterization green BEFORE rewiring**

Run: `make test-unit TEST_FILE=test_us_interactive.bats`
Expected: PASS (baseline).

- [ ] **Step 2: Replace the scope-set construction block**

In `git-config/bin/git-us`, replace the block from `# BOTH collections are ROOT-relative` (≈line 196) through the `for s in ${scope_files[@]…}; do in_scope[…]=1; done` loop (≈line 249) with:

```bash
    scope_files=()
    build_scope_set scope_files ${pathspecs[@]+"${pathspecs[@]}"}
    # O(n+m) membership filter (assoc array), not O(n·m) — unchanged glue.
    declare -A in_scope=()
    for s in ${scope_files[@]+"${scope_files[@]}"}; do in_scope["$s"]=1; done
```

(The two `error_usage` guards and the join logic now live in `build_scope_set`.)

- [ ] **Step 3: Replace the canonicalization + climb blocks**

Replace the `source_list_empty=` assignment (keep it — it predates extraction and feeds the empty-source message) and the `canonical_source/unresolved_source` loop (≈273–287) plus the whole root→CWD conversion block (≈295–321) with:

```bash
    source_list_empty=false
    [[ ${#files_from_source[@]} -eq 0 ]] && source_list_empty=true
    canonical_source=()
    unresolved_source=()
    if [[ -n "$from_commit" ]]; then
      canonicalize_source_lines canonical_source unresolved_source --from-commit \
        ${files_from_source[@]+"${files_from_source[@]}"}
    else
      canonicalize_source_lines canonical_source unresolved_source \
        ${files_from_source[@]+"${files_from_source[@]}"}
    fi
    filtered_source=()
    # INTERSECTION, never concat (PR #318 review, codex P1 — restores
    # git-us's original contract §3.1): the pathspecs are a SCOPE. A source
    # list ['a.txt','b.txt'] against scope 'a.txt' must forward ONLY a.txt;
    # copying all canonical entries would unstage b.txt OUTSIDE the scope.
    for f in ${canonical_source[@]+"${canonical_source[@]}"}; do
      if [[ -n "${in_scope[$f]:-}" ]]; then
        filtered_source+=("$f")
      fi
    done
    # ...and BACK to CWD-relative for downstream consumers (validation +
    # git restore resolve against the CWD). Real relpath, not prefix-strip:
    # see root_to_cwd_relpath. Unresolved spellings are ALREADY
    # CWD-relative (the user's own) — appended untouched.
    cwd_source=()
    for f in ${filtered_source[@]+"${filtered_source[@]}"}; do
      cwd_source+=("$(root_to_cwd_relpath "$f")")
    done
    files_from_source=(${cwd_source[@]+"${cwd_source[@]}"} ${unresolved_source[@]+"${unresolved_source[@]}"})
```

(The climb/cwd_prefix internals live ONLY inside `root_to_cwd_relpath` — git-us keeps none of them.)

- [ ] **Step 4: Run the full us surface**

Run:
- `make test-unit TEST_FILE=test_us_interactive.bats`
- `make test-lib TEST_FILE=test_hug-pathspec.bats`

Expected: ALL PASS. Byte-diff spot-check in a scratch repo (probes, not tests):

```bash
export HUG_HOME=$PWD; export PATH="$PWD/git-config/bin:$PATH"
cd "$(mktemp -d)" && git init -q .
echo a > a.txt; mkdir d; echo b > d/b.txt; git add -A
# staged deletion + from-file + dir-spec + magic pathspec flows:
printf 'a.txt\nd/\n' | hug us --dry-run --from-file -
git rm -q --cached a.txt
printf 'a.txt\n' | hug us --dry-run --from-file -    # deletion still unstageable
```

Expected outputs match the messages pinned in `test_us_interactive.bats` ("Dry run: Would unstage…", no "not tracked" false positives).

- [ ] **Step 5: Commit**

```bash
make sanitize
hug a git-config/bin/git-us && hug c -F - <<'EOF'
refactor(us): route scope intersection through hug-pathspec (#303)

The ~200-line inline block (staged-deletion union, origin-based
normalization, root→CWD climbing) reduces to four orchestration lines
over build_scope_set / canonicalize_source_lines /
root_to_cwd_relpath. F-003 lands here: --from-file lists now cost ONE
git process (plain-filename lists), not one per line. No observable
behavior change — the Task-1-era characterization suite and
test_us_interactive.bats pin messages, exit codes, and the
unresolved-append-last ordering byte-for-byte.

Co-authored-by: CommandCodeBot <noreply@commandcode.ai>
EOF
```

---

### Task 6: `hug-status-listing` module + migrate sls & slu

**Files:**
- Create: `git-config/lib/hug-status-listing`
- Modify: `git-config/bin/git-sls`, `git-config/bin/git-slu` (shrink to ~35 lines)
- Create: `tests/unit/test_sl_family_template.bats` (drift guard)
- Modify: `git-config/lib/README.md` (add `### hug-status-listing` section)

**Interfaces:**
- Produces: `sl_family_main <mode> <display_name> "$@"` — modes: `staged`, `unstaged` (Task 6); `untracked`, `ignored`, `conflicts` (Task 7). Reads caller-scope `show_help` dynamically. Own-loop rejects unknown `-*` tokens with `<display_name>` interpolation, exit 2.

- [ ] **Step 1: Write the drift-guard test (fails until migration)**

Create `tests/unit/test_sl_family_template.bats`:

```bash
#!/usr/bin/env bats
# Drift guard: the sl* scripts must stay ON the template (#303).
load '../test_helper'

@test "every sl* script delegates to sl_family_main" {
  local script
  for script in "$HUG_HOME/git-config/bin/"git-sl{c,i,k,s,u}; do
    grep -q 'sl_family_main' "$script" || {
      fail "$(basename "$script") missing sl_family_main (hand-copy reintroduced?)"
    }
  done
}

@test "no sl* script carries its own parse own-loop" {
  local script
  for script in "$HUG_HOME/git-config/bin/"git-sl{c,i,k,s,u}; do
    if grep -qE '^for arg in "\$\@"; do$' "$script"; then
      fail "$(basename "$script") has an own-loop (should live in hug-status-listing)"
    fi
  done
}
```

Run: `make test-unit TEST_FILE=test_sl_family_template.bats`
Expected: FAIL for sls/slu (still hand-copied).

- [ ] **Step 2: Implement the lib**

Create `git-config/lib/hug-status-listing`:

```bash
# shellcheck shell=bash
# Library: hug-status-listing — shared main body for the sl* listing
# family (#303). One function, five modes; per-mode variance lives in the
# private mode table below (roast C-003/C-004: the table is the COMPLETE
# lib-side contract — quiet-extra included).
# Script-local FOREVER (never enter this lib): _hug_category, the whole
# --search-meta block, and slc's _hug_keywords line.
# Depends on: parse_common_flags_with_pathspecs, reject_action_flags,
# pathspec_pathspecs_into (hug-cli-flags), check_git_repo (hug-git-repo),
# validate_pathspecs_or_die (hug-git-files), run_count_mode,
# list_files_with_status (hug-select-files), output_json_status,
# info/error_usage (hug-output/hug-cli-flags) — all reached via the
# sourcing script's preamble (hug-common hug-git-kit hug-select-files
# output_json_status), same bundle the five scripts load today.

# Prevent double-loading
[[ -n "${_HUG_STATUS_LISTING_LOADED:-}" ]] && return 0
readonly _HUG_STATUS_LISTING_LOADED=1

# Shared main for the sl* family.
# Usage: sl_family_main <mode> <display_name> <args...>
# Modes: staged | unstaged | untracked | ignored | conflicts
sl_family_main() {
  local mode="$1"; shift
  local display_name="$1"; shift

  # Mode table — the COMPLETE lib-side behavioral contract.
  # Fields: list_flag | count token | no-match noun | quiet-extra flag
  local list_flag count_token noun quiet_extra=""
  case "$mode" in
    staged)    list_flag="--staged";    count_token="staged";     noun="staged" ;;
    unstaged)  list_flag="--unstaged";  count_token="unstaged";   noun="unstaged" ;;
    untracked) list_flag="--untracked"; count_token="untracked";  noun="untracked";  quiet_extra="--suppress-status" ;;
    ignored)   list_flag="--ignored";   count_token="ignored";    noun="ignored";    quiet_extra="--suppress-status" ;;
    conflicts) list_flag="--conflicts"; count_token="conflicted"; noun="conflicted"; quiet_extra="--suppress-status" ;;
    *) error "sl_family_main: unknown mode '$mode'" 1 ;;  # programming error
  esac

  json_output=false
  quiet=false
  count_only=false
  pathspecs=()

  eval "$(parse_common_flags_with_pathspecs "$@")"
  reject_action_flags "$display_name"

  [[ ${HUG_QUIET:-} == T ]] && quiet=true

  pathspec_pathspecs_into pathspecs

  for arg in "$@"; do
    case "$arg" in
    --json)
      json_output=true
      ;;
    -c | --count)
      count_only=true
      ;;
    -q | --quiet)
      quiet=true # UNREACHABLE via the split; kept for template symmetry
      ;;
    -*)
      error_usage "Unknown option: $arg. Pathspecs beginning with '-' require '--': $display_name -- $arg. See 'hug help :pathspec'."
      ;;
    *)
      pathspecs+=("$arg")
      ;;
    esac
  done

  check_git_repo
  validate_pathspecs_or_die ${pathspecs[@]+"${pathspecs[@]}"}

  local -a list_opts=("$list_flag")
  if $quiet && [[ -n "$quiet_extra" ]]; then
    list_opts+=("$quiet_extra")
  fi
  if [[ ${#pathspecs[@]} -gt 0 ]]; then
    list_opts+=("--" ${pathspecs[@]+"${pathspecs[@]}"})
  fi

  if $count_only; then
    if $json_output; then
      run_count_mode --json "$count_token" ${pathspecs[@]+"--" "${pathspecs[@]}"}
    else
      run_count_mode "$count_token" ${pathspecs[@]+"--" "${pathspecs[@]}"}
    fi
  fi

  if $json_output; then
    output_json_status "${list_opts[@]}"
  else
    if ! list_files_with_status "${list_opts[@]}" 2> /dev/null; then
      if [[ ${#pathspecs[@]} -gt 0 ]]; then
        pathspec_list=""
        printf -v pathspec_list "'%s' " "${pathspecs[@]}"
        info "No ${noun} files matching ${pathspec_list% } found."
      else
        info "No ${noun} files."
      fi
    fi

    # Summary gate (#292 spec §3.1): suppressed iff scoped or quiet.
    if ! $quiet && [[ ${#pathspecs[@]} -eq 0 ]]; then
      exec hug s
    fi
  fi
}
```

CAUTION — two fidelity checks against the originals BEFORE running tests: (1) the original count dispatch expands `${pathspecs[@]+"--" "${pathspecs[@]}"}` as ONE word-bundle; copy that expansion verbatim from `git-slu:143-146` rather than trusting the sketch. (2) `show_help` routing: `-h` reaches `show_help` through `parse_common_flags_with_pathspecs` calling the CALLER'S function — confirm by reading hug-cli-flags' help arm; do not add a `-h)` case here.

- [ ] **Step 3: Shrink git-sls and git-slu**

Rewrite `git-config/bin/git-sls` to:

```bash
#!/usr/bin/env bash
_hug_category='["status", "staging"]'
test "${1:-}" = '--search-meta' && {
  printf 'category = %s\n' "$_hug_category"
  exit 0
}
CMD_BASE="$(readlink -f "$0" 2> /dev/null || greadlink -f "$0")" || CMD_BASE="$0"
CMD_BASE="$(dirname "$CMD_BASE")"
for f in hug-common hug-git-kit hug-select-files output_json_status hug-status-listing; do . "$CMD_BASE/../lib/$f"; done
set -euo pipefail

# Part of the Hug tool suite

# Show only staged files, then summary

show_help() {
  cat << 'EOF'
hug sls: List STAGED files only, then a summary line.
[...KEEP THE EXISTING heredoc body VERBATIM from today's git-sls:17-57...]
EOF
}

sl_family_main staged "hug sls" "$@"
```

Same shape for `git-slu` (category `'["status"]'`, purpose comment, heredoc verbatim, then `sl_family_main unstaged "hug slu" "$@"`). The heredoc bodies are BYTE-FROZEN — copy from the current files, change nothing.

- [ ] **Step 4: Run the family suites**

Run:
- `make test-unit TEST_FILE=test_status_staging.bats`
- `make test-unit TEST_FILE=test_status_json.bats`
- `make test-unit TEST_FILE=test_status_query_flags.bats`
- `make test-unit TEST_FILE=test_pathspec_conformance.bats`
- `make test-unit TEST_FILE=test_sl_family_template.bats`

Expected: ALL PASS (drift guard now green too). Any diff → the lib deviated from the skeleton; fix the LIB, never the pins.

- [ ] **Step 5: Commit**

```bash
make sanitize
hug a git-config/lib/hug-status-listing git-config/bin/git-sls git-config/bin/git-slu tests/unit/test_sl_family_template.bats git-config/lib/README.md && hug c -F - <<'EOF'
feat(lib): hug-status-listing + sl_family_main; migrate sls/slu (#303)

The five-script skeleton (split -> action-flag rejection -> quiet
rehydrate -> own-loop -> validate -> count/json/listing -> summary gate)
moves once into sl_family_main with a private mode table encoding the
family's per-mode variance INCLUDING quiet-extra (--suppress-status for
single-status kinds). sls/slu shrink to meta + sources + help + one
call; drift guard pins every member onto the template. search-meta and
categories stay script-local forever. Byte-parity enforced by the
Task-1 pins and the four existing suites.

Co-authored-by: CommandCodeBot <noreply@commandcode.ai>
EOF
```

---

### Task 7: Migrate slk, sli, slc

**Files:**
- Modify: `git-config/bin/git-slk`, `git-config/bin/git-sli`, `git-config/bin/git-slc`

**Interfaces:**
- Consumes: `sl_family_main` (Task 6). Modes `untracked`/`ignored`/`conflicts` exercise the quiet-extra column and (slc) leave search-meta script-local.

- [ ] **Step 1: Shrink the three scripts**

Same rewrite shape as Task 6 Step 3, preserving each script's preamble bytes:
- `git-slk`: category `'["status"]'`, heredoc verbatim, tail `sl_family_main untracked "hug slk" "$@"`.
- `git-sli`: category `'["status"]'`, heredoc verbatim (keeps the `*.log` example wording), tail `sl_family_main ignored "hug sli" "$@"`.
- `git-slc`: category `'["status", "staging"]'`, PLUS its unique keywords block — keep lines 3–6 EXACTLY:

```bash
_hug_keywords='["conflict","unmerged","merge","rebase"]'
test "${1:-}" = '--search-meta' && {
  printf 'category = %s\nkeywords = %s\n' "$_hug_category" "$_hug_keywords"
  exit 0
}
```

heredoc verbatim (its USAGE line says "Show only MODE (unmerged) files…" — freeze it), tail `sl_family_main conflicts "hug slc" "$@"`.

- [ ] **Step 2: Run every family suite + drift guard**

Run:
- `make test-unit TEST_FILE=test_status_staging.bats`
- `make test-unit TEST_FILE=test_status_json.bats`
- `make test-unit TEST_FILE=test_status_query_flags.bats`
- `make test-unit TEST_FILE=test_pathspec_conformance.bats`
- `make test-unit TEST_FILE=test_sl_family_template.bats`
- `make test-unit TEST_FILE=test_json_edge_cases.bats`

Expected: ALL PASS. Specifically: `slk -q`/`sli -q`/`slc -q` still suppress the column (quiet-extra column live); slc `--search-meta` still prints keywords (script-local surface intact).

- [ ] **Step 3: Byte-compare each migrated script's observable surfaces**

Probes in a scratch repo (not tests — sanity):

```bash
for cmd in sls slu slk sli slc; do
  hug $cmd --help > /tmp/help-$cmd.txt 2>&1 || true
  hug $cmd --search-meta > /tmp/meta-$cmd.txt 2>&1 || true
done
```

Diff `/tmp/help-*` and `/tmp/meta-*` against the same captures taken from `origin/main` checkout (`git show origin/main:git-config/bin/git-slk > /tmp/old-slk` then run it with proper HUG_HOME pointing at the OLD checkout — or eyeball against the pre-migration files in git history via `git show 2e1d80c0:git-config/bin/git-slk`). Expected: identical bytes.

- [ ] **Step 4: Commit**

```bash
make sanitize
hug a git-config/bin/git-slk git-config/bin/git-sli git-config/bin/git-slc && hug c -F - <<'EOF'
refactor(sl): migrate slk/sli/slc onto sl_family_main (#303)

Family complete: five members, one skeleton. slc keeps its unique
_hug_keywords search-meta line script-local (the lib never learns about
search-meta); the quiet-extra table column reproduces
--suppress-status for all three single-status kinds byte-for-byte.
Drift guard + Task-1 pins hold: any future family member is born on
the template or fails test_sl_family_template.bats.

Co-authored-by: CommandCodeBot <noreply@commandcode.ai>
EOF
```

---

### Task 8: Full-suite verification + CHANGELOG

**Files:**
- Modify: `CHANGELOG.md` (Unreleased section entry)

**Interfaces:**
- Consumes: everything above.
- Produces: green `make test-lump`; CHANGELOG documents the refactor under the next-release heading.

- [ ] **Step 1: Run the whole battery**

Run: `make test-lump`
Expected: PASS. If anything fails, fix before proceeding — do NOT commit broken.

Also run shellcheck on touched files if the repo wires it into sanitize (it does — `make sanitize` covers lint); zero new findings expected.

- [ ] **Step 2: Update CHANGELOG**

Under the topmost unreleased heading (create `## [Unreleased]` if absent), add:

```markdown
### Refactored

- **`hug-pathspec` library (new)** — git-us's inline scope-intersection machinery
  (tracked ∪ staged-deletion scope sets, source-list canonicalization, root↔CWD
  relpath conversion) extracted for direct unit testing. Includes the F-003 fix:
  `us --from-file` lists now resolve via one batched `git ls-files` call instead
  of one subprocess per line. Zero behavior change.
- **`hug-status-listing` library (new) + `sl_family_main`** — the five sl*
  listings (`sls`/`slu`/`slk`/`sli`/`slc`) collapse onto one shared main body;
  per-mode variance lives in a mode table. Future family members are born on the
  template. Zero behavior change.
```

- [ ] **Step 3: Final commit**

```bash
make sanitize
hug a CHANGELOG.md && hug c -F - <<'EOF'
docs(changelog): record #303 refactor — hug-pathspec + sl_family_main

Co-authored-by: CommandCodeBot <noreply@commandcode.ai>
EOF
```

- [ ] **Step 4: Report convergence**

Run `hug ll` — expect 9 commits on `303-us-scope-block-extraction-and-sl-family-templating` ahead of origin/main (2 pre-existing docs commits + 7 new: Tasks 1–8 each land exactly one). Hand off to review/PR flow.
