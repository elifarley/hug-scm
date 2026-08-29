# Truthful Sync-State Messages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `llu`, `lol`, and `h files` report honest sync state (in_sync / behind-by-N / unknown) on the empty-outgoing path in both the human and JSON channels.

**Architecture:** One detection primitive (`sync_state_of`) and one presentation wrapper (`report_empty_outgoing`) live in `git-config/lib/hug-git-upstream`; the three call sites become thin consumers. `git-llu --json` consumes the primitive directly and emits a three-state empty envelope. Work happens in the existing worktree `~/src/hug-scm.WT.truthful-sync-state-messages-for-llu-lol-h-files` (branch `truthful-sync-state-messages-for-llu-lol-h-files`).

**Tech Stack:** Bash (set -euo pipefail), BATS (bats-core >= 1.14), hug command layer (`hug a`, `hug c -F -`, `make test-*` targets), python3 for JSON validation.

**Spec:** `docs/superpowers/specs/2026-08-28-truthful-sync-state-messages-for-llu-lol-h-files-design.md` (rev. 2 — roast round 1 applied)

**Standing rules for every task:**
- Commit with `hug`, never raw `git commit`/`git add` (`hug a <files>`, `hug c -F - <<'EOF' …`).
- Load the `commit-message` skill before writing each commit message; expand the skeletons below into full WHY/WHAT/HOW/IMPACT.
- Never use `local` outside a function body (repo hard rule).
- Run only the listed test slice per task; the full suite runs in Task 5.

---

### Task 1: Library — `sync_state_of` + `report_empty_outgoing` with lib tests

**Goal:** Add the detection primitive and message wrapper to `hug-git-upstream`, fully covered by BATS lib tests (TDD: tests first, red → green).

**Files:**
- Modify: `tests/lib/test_hug-upstream.bats` (append a new block; the file already defines `setup_synced_upstream` at :218 and `advance_remote` at :234 — reuse them)
- Modify: `git-config/lib/hug-git-upstream` (append two functions at end of file, after `emit_head_recovery_hint`)

**Acceptance Criteria:**
- [ ] `sync_state_of` prints `in_sync` / `behind <N>` / `unknown` and returns 0 in all three cases
- [ ] `report_empty_outgoing` renders synced / behind (singular-correct) / self-contained fallback messages to stderr
- [ ] `make test-lib TEST_FILE=test_hug-upstream.bats` green (new tests + all pre-existing)

**Verify:** `make test-lib TEST_FILE=test_hug-upstream.bats TEST_SHOW_ALL_RESULTS=1` → all pass, including the 7 new tests.

**Steps:**

- [ ] **Step 1: Write the failing tests** — append to `tests/lib/test_hug-upstream.bats`:

```bash
################################################################################
# sync_state_of / report_empty_outgoing: truthful empty-outgoing reporting
################################################################################

@test "sync_state_of: synced repo -> in_sync" {
  create_test_repo_with_history
  setup_synced_upstream
  run sync_state_of "$(git rev-parse '@{u}')"
  assert_success
  assert_output "in_sync"
}

@test "sync_state_of: behind-by-2 -> 'behind 2'" {
  create_test_repo_with_history
  setup_synced_upstream
  advance_remote 2
  run sync_state_of "$(git rev-parse '@{u}')"
  assert_success
  assert_output "behind 2"
}

@test "sync_state_of: failing target ref -> unknown (never in_sync)" {
  create_test_repo_with_history
  run sync_state_of "definitely-not-a-ref"
  assert_success
  assert_output "unknown"
}

@test "report_empty_outgoing: synced -> '(already synced to …)'" {
  create_test_repo_with_history
  setup_synced_upstream
  run report_empty_outgoing "📭 No outgoing commits" "origin/main" "$(git rev-parse '@{u}')"
  assert_success
  assert_output --partial "📭 No outgoing commits (already synced to origin/main)"
}

@test "report_empty_outgoing: behind-by-2 -> truthful count + catch-up hint" {
  create_test_repo_with_history
  setup_synced_upstream
  advance_remote 2
  run report_empty_outgoing "📭 No outgoing commits" "origin/main" "$(git rev-parse '@{u}')"
  assert_success
  assert_output --partial "📭 No outgoing commits (branch is behind origin/main by 2 commits — pull or rebase to catch up)"
  refute_output --partial "already synced"
}

@test "report_empty_outgoing: behind-by-1 -> singular 'commit'" {
  create_test_repo_with_history
  setup_synced_upstream
  advance_remote 1
  run report_empty_outgoing "No outgoing changes" "a1b2c3d" "$(git rev-parse '@{u}')"
  assert_success
  assert_output --partial "behind a1b2c3d by 1 commit —"
  refute_output --partial "1 commits"
}

@test "report_empty_outgoing: failure -> self-contained fallback (no noun repeat)" {
  create_test_repo_with_history
  run report_empty_outgoing "No outgoing changes" "definitely-not-a-ref" "definitely-not-a-ref"
  assert_success
  assert_output --partial "No outgoing changes (sync state with definitely-not-a-ref could not be determined)"
  refute_output --partial "No outgoing changes (No outgoing changes"
}
```

- [ ] **Step 2: Verify red** — `make test-lib TEST_FILE=test_hug-upstream.bats TEST_FILTER="sync_state_of"` → FAIL (function not defined), same for `TEST_FILTER="report_empty_outgoing"`.

- [ ] **Step 3: Implement** — append to `git-config/lib/hug-git-upstream`:

```bash
################################################################################
# Empty-Outgoing Sync-State Reporting (truthful sync-state messages)
################################################################################

# Classifies how far HEAD is from <target_ref>. Does NOT assume @{u}: callers
# pass custom targets (a full hash, origin/main, a local anchor branch).
#
# Usage: state=$(sync_state_of <target_ref>)
# Prints exactly one of:
#   "in_sync"      — target is an ancestor of (or equal to) HEAD
#   "behind <N>"   — HEAD is N commits behind the target (N >= 1)
#   "unknown"      — the count failed (e.g. unborn HEAD); NEVER "in_sync"
# Returns: 0 always — the state is the VALUE, not the exit code, so a bare
#   capture stays errexit-safe (the commit_offset lesson, hug-git-commit:270-277).
#
# The count capture is the failure-testing form ON PURPOSE: the `|| echo "0"`
# swallow idiom modeled at git-llu:181 / git-wtsh:137-138 would map "failed"
# onto 0 => in_sync — the exact false-sync claim this function exists to kill.
sync_state_of() {
    local target_ref="${1:?sync_state_of: target ref required}"
    local behind
    if ! behind=$(git rev-list --count "HEAD..$target_ref" 2> /dev/null); then
        echo "unknown"
        return 0
    fi
    if [ "$behind" -eq 0 ]; then
        echo "in_sync"
    else
        echo "behind $behind"
    fi
}

# Human message for the empty-outgoing path (0 commits ahead): the one wording
# authority shared by git-llu, git-log-outgoing, and git-h-files.
#
# Usage: report_empty_outgoing <noun> <upstream_display> <target_ref>
#   <noun>             Caller's sentence start ("No outgoing commits"); any
#                      emoji is part of the noun (caller-owned).
#   <upstream_display> What humans should see ("origin/main", short hash, or
#                      the resolved upstream branch name).
#   <target_ref>       Ref measured against (forwarded to sync_state_of).
# Prints to stderr (via info) exactly one of:
#   "<noun> (already synced to <upstream_display>)"
#   "<noun> (branch is behind <upstream_display> by N commit[s] — pull or rebase to catch up)"
#   "<noun> (sync state with <upstream_display> could not be determined)"
# Returns: 0 always — message-only; the caller owns the exit code.
# The fallback parenthetical is self-contained so it composes with any noun
# without repeating it, and it is the SAFETY NET for the swallowed ahead-count
# at git-llu:181 — do not delete it if :181 is ever fixed to propagate.
report_empty_outgoing() {
    local noun="${1:?report_empty_outgoing: noun required}"
    local display="${2:?report_empty_outgoing: upstream display required}"
    local target_ref="${3:?report_empty_outgoing: target ref required}"
    local state
    state=$(sync_state_of "$target_ref")
    case "$state" in
    in_sync)
        info "$noun (already synced to $display)"
        ;;
    behind\ *)
        local n="${state#behind }" word="commits"
        if [ "$n" -eq 1 ]; then word="commit"; fi
        info "$noun (branch is behind $display by $n $word — pull or rebase to catch up)"
        ;;
    *)
        info "$noun (sync state with $display could not be determined)"
        ;;
    esac
}
```

Notes for the implementer:
- `info` comes from `hug-common` (already sourced by `hug-git-kit` consumers and by this test file) and routes to stderr, suppressed under `HUG_QUIET=T`.
- The `if [ "$n" -eq 1 ]` form is deliberate: `[[ … ]] && word=commit` at statement level returns 1 when false and would kill the script under `set -e`.

- [ ] **Step 4: Verify green** — `make test-lib TEST_FILE=test_hug-upstream.bats TEST_SHOW_ALL_RESULTS=1` → all pass.

- [ ] **Step 5: Commit**

```bash
hug a git-config/lib/hug-git-upstream tests/lib/test_hug-upstream.bats
hug c -F - <<'EOF'
feat(lib): sync_state_of + report_empty_outgoing — truthful empty-outgoing reporting

WHY: The empty-outgoing gates in llu/lol/h-files treat "0 commits ahead" as
"synced", which is false when the branch is behind. #237/#238 fixed this for
the h* family; this adds the shared detection+wording authority the three
remaining sites will consume (spec rev. 2, Tasks 2-4).

WHAT: sync_state_of <target_ref> prints in_sync | behind <N> | unknown and
returns 0 always (state is the value — errexit-safe captures). It uses the
failure-testing count capture (if ! behind=$(…)), NOT the || echo "0" swallow
modeled at git-llu:181, so a failed count can never masquerade as in_sync.
report_empty_outgoing <noun> <display> <ref> renders the one message wording
for all three callers: synced, behind (singular-correct "1 commit"), and a
self-contained fallback that composes with any noun.

HOW: Behind = rev-list --count HEAD..<target>, computed only on the empty
path. TDD: 7 new lib tests written first (red), including behind-by-2 via the
existing advance_remote helper, behind-by-1 pluralization, and the unknown
fallback. Functions appended to hug-git-upstream, which hug-git-kit:30 already
sources — visible at all three future call sites with no source-list changes.

IMPACT: Detection and wording each live in exactly one place, so the human and
JSON sinks (Tasks 2-4) cannot drift apart — the drift that hid this bug as
three different spellings of the same false claim.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
```

---

### Task 2: Wire `git-log-outgoing` (lol) + behind fixture test

**Goal:** Replace lol's false "already synced" line with the shared wrapper; add a behind-by-1 integration test through the real command.

**Files:**
- Modify: `git-config/bin/git-log-outgoing:96-101` (the empty gate)
- Modify: `tests/unit/test_log_outgoing.bats` (add one test after "handles no outgoing commits to upstream")

**Acceptance Criteria:**
- [ ] Synced run prints `No outgoing changes (already synced to <short-hash>)` — the two pre-existing partial assertions at `:65`/`:118` still pass untouched
- [ ] Behind run prints `No outgoing changes (branch is behind <short-hash> by 1 commit — pull or rebase to catch up)`, never "already synced"
- [ ] Exit code stays 0 in both states

**Verify:** `make test-unit TEST_FILE=test_log_outgoing.bats TEST_SHOW_ALL_RESULTS=1` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing test** — add after the "handles no outgoing commits to upstream" test:

```bash
@test "hug lol: behind upstream -> truthful behind message (never 'already synced')" {
  # Make origin/main 1 ahead: push a commit (updates the local remote-tracking
  # ref), then move local main back. No fetch needed after a push.
  git commit -q --allow-empty -m "upstream-only commit"
  git push -q origin main
  git reset -q --hard HEAD~1

  local upstream_short
  upstream_short=$(git rev-parse --short '@{u}')
  run hug lol
  assert_success
  assert_output --partial "No outgoing changes (branch is behind $upstream_short by 1 commit — pull or rebase to catch up)"
  refute_output --partial "already synced"
}
```

- [ ] **Step 2: Verify red** — `make test-unit TEST_FILE=test_log_outgoing.bats TEST_FILTER="behind upstream"` → FAIL ("already synced" printed).

- [ ] **Step 3: Wire the wrapper** — in `git-config/bin/git-log-outgoing`, replace:

```bash
if [ "$local_commits" -eq 0 ]; then
  info "No outgoing changes (already synced to $target_short)."
  exit 0
fi
```

with:

```bash
if [ "$local_commits" -eq 0 ]; then
  # Truthful sync state: 0 ahead also covers "behind by N" (#237/#238 pattern).
  report_empty_outgoing "No outgoing changes" "$target_short" "$target"
  exit 0
fi
```

(`report_empty_outgoing` is visible here: the script sources `hug-git-kit`, which sources `hug-git-upstream` at `hug-git-kit:30`.)

- [ ] **Step 4: Verify green** — `make test-unit TEST_FILE=test_log_outgoing.bats TEST_SHOW_ALL_RESULTS=1` → all pass, including the two untouched synced assertions.

- [ ] **Step 5: Commit**

```bash
hug a git-config/bin/git-log-outgoing tests/unit/test_log_outgoing.bats
hug c -F - <<'EOF'
fix(lol): truthful behind message on the empty-outgoing path

WHY: On a behind-only branch, `hug lol` printed "No outgoing changes (already
synced to <hash>)" — false, and discouraging the pull/rebase the user needs.
The gate counts only AHEAD commits (count_commits_in_range), and 0 ahead also
covers behind-by-N.

WHAT: The empty gate now calls the shared report_empty_outgoing wrapper with
the target short hash as display and the full hash as measurement ref. Exit
code stays 0. The two pre-existing synced assertions (:65/:118) pass untouched
— they partial-match "(already synced to", which the wrapper preserves.

HOW: New behind-by-1 fixture: push an empty commit to origin (updates the
local remote-tracking ref), then reset local main back — origin/main is 1
ahead with no fetch needed. Asserts the truthful message with the resolved
short hash and refutes "already synced".

IMPACT: `hug lol` stops lying on behind branches; wording stays single-sourced
in the library (Task 1), so lol and the other two sites cannot drift apart.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
```

---

### Task 3: Wire `git-h-files` (resolved branch name) + behind test in test_head.bats

**Goal:** Replace h-files' false "already synced to upstream" line; pass the resolved upstream branch name so a behind answer names the branch.

**Files:**
- Modify: `git-config/bin/git-h-files:125-129` (the empty gate inside `if $upstream; then`)
- Modify: `tests/unit/test_head.bats` (add one test in the `hug h files` block, after "handles when no files in range")

**Acceptance Criteria:**
- [ ] Behind run prints `No local-only commits (branch is behind <branch-name> by 1 commit — pull or rebase to catch up)`, never "already synced"
- [ ] No pre-existing test in test_head.bats pinned the old message (roast R6/S4 confirmed) — the full h-files block stays green
- [ ] Exit code stays 0

**Verify:** `make test-unit TEST_FILE=test_head.bats TEST_FILTER="hug h files" TEST_SHOW_ALL_RESULTS=1` → all pass.

**Steps:**

- [ ] **Step 1: Write the failing test** — add in the `hug h files` block of `tests/unit/test_head.bats`:

```bash
@test "hug h files -u: behind upstream -> truthful message naming the branch" {
  # Local anchor branch 1 ahead of main, set as @{u}: h-files' empty path with
  # no bare remote needed (same technique as the pathspec-conformance fixture).
  git checkout -q -b hfiles-anchor
  git commit -q --allow-empty -m "anchor ahead commit"
  git checkout -q - # back to main (exactly one switch happened)
  git branch --set-upstream-to=hfiles-anchor > /dev/null

  run hug h files -u
  assert_success
  assert_output --partial "No local-only commits (branch is behind hfiles-anchor by 1 commit — pull or rebase to catch up)"
  refute_output --partial "already synced"
}
```

- [ ] **Step 2: Verify red** — `make test-unit TEST_FILE=test_head.bats TEST_FILTER="behind upstream" TEST_SHOW_ALL_RESULTS=1` → FAIL ("already synced to upstream." printed).

- [ ] **Step 3: Wire the wrapper with the resolved name** — in `git-config/bin/git-h-files`, replace:

```bash
  if [ "$local_commits" -eq 0 ]; then
    info "No local-only commits; already synced to upstream."
    exit 0
  fi
```

with:

```bash
  if [ "$local_commits" -eq 0 ]; then
    # Name the actual branch: a behind-by-N answer must say WHICH upstream
    # (same idiom as handle_upstream_operation, hug-git-upstream:66). Do NOT
    # reuse $upstream — that is this script's boolean flag variable.
    upstream_name=$(git for-each-ref --format='%(upstream:short)' \
      "$(git symbolic-ref HEAD)" 2> /dev/null || echo "upstream")
    report_empty_outgoing "No local-only commits" "$upstream_name" "$start_point"
    exit 0
  fi
```

- [ ] **Step 4: Verify green** — `make test-unit TEST_FILE=test_head.bats TEST_SHOW_ALL_RESULTS=1` → all pass (full file, not just the filter — the h-files block shares the file with h* contract tests).

- [ ] **Step 5: Commit**

```bash
hug a git-config/bin/git-h-files tests/unit/test_head.bats
hug c -F - <<'EOF'
fix(h-files): truthful behind message naming the upstream branch

WHY: `hug h files -u` on a behind-only branch printed "No local-only commits;
already synced to upstream." — false (the gate counts only AHEAD commits), and
the literal "upstream" display would have survived even a truthful verdict,
hiding WHICH branch to pull. This gate also carries a stale SAFE verdict in
docs/superpowers/specs/2026-07-29-count-commits-in-range-audit-design.md:186
(superseding note lands in Task 5).

WHAT: The empty gate resolves the upstream's short name via
for-each-ref %(upstream:short) (fallback "upstream" for detached HEAD) and
delegates to the shared report_empty_outgoing wrapper. New variable
$upstream_name deliberately does not shadow the $upstream boolean flag.

HOW: Behind fixture uses a local anchor branch 1 ahead of main, set as @{u}
(same technique as the pathspec-conformance fixture — no bare remote needed).
Asserts the truthful message names hfiles-anchor and refutes "already synced".

IMPACT: Third and final human-path site converted; behind answers are both
true and actionable (named branch, count, catch-up hint).

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
```

---

### Task 4: Wire `git-llu` (human + three-state JSON) + new `tests/unit/test_llu.bats`

**Goal:** Replace llu's false "up to date" line and give `--json`'s empty envelope its three honest states; full unit coverage for the new command behavior.

**Files:**
- Modify: `git-config/bin/git-llu:183-193` (the empty gate, both sinks)
- Create: `tests/unit/test_llu.bats`

**Acceptance Criteria:**
- [ ] Human behind run: `📭 No outgoing commits (branch is behind origin/main by 1 commit — pull or rebase to catch up)`; the unscoped-run `hug s` summary still fires
- [ ] Human unborn-HEAD+upstream run (scoped, so no summary): fallback message, never "up to date"
- [ ] JSON: `in_sync`/`behind_count:0`, `behind`/`behind_count:1`, and `error:"sync_state_unknown"` envelopes — each parses via `python3 -m json.tool`
- [ ] `-q` suppresses both message and summary in synced and behind states
- [ ] No `up to date` string survives anywhere in llu's output

**Verify:** `make test-unit TEST_FILE=test_llu.bats TEST_SHOW_ALL_RESULTS=1` → all 8 tests pass.

**Steps:**

- [ ] **Step 1: Create `tests/unit/test_llu.bats`** with the failing tests:

```bash
#!/usr/bin/env bats
# Tests for hug llu (outgoing log): truthful empty-path sync-state reporting
# (human + JSON), per docs/superpowers/specs/2026-08-28-truthful-sync-…-design.md

load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_remote_upstream)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

# Makes origin/main 1 ahead of local main: push an empty commit (updates the
# local remote-tracking ref), then move local main back. No fetch needed.
make_behind() {
  git commit -q --allow-empty -m "upstream-only commit"
  git push -q origin main
  git reset -q --hard HEAD~1
}

@test "hug llu: synced upstream -> truthful synced message + trailing summary" {
  run hug llu
  assert_success
  assert_output --partial "📭 No outgoing commits (already synced to origin/main)"
  refute_output --partial "up to date"
  assert_output --partial "HEAD:" # unscoped runs still end with the whole-repo summary
}

@test "hug llu: behind upstream -> truthful behind message" {
  make_behind
  run hug llu
  assert_success
  assert_output --partial "📭 No outgoing commits (branch is behind origin/main by 1 commit — pull or rebase to catch up)"
  refute_output --partial "already synced"
  refute_output --partial "up to date"
}

@test "hug llu --json: synced -> state in_sync" {
  run hug llu --json
  assert_success
  assert_output --partial '"state":"in_sync"'
  assert_output --partial '"behind_count":0'
  echo "$output" | python3 -m json.tool > /dev/null
}

@test "hug llu --json: behind -> state behind with count" {
  make_behind
  run hug llu --json
  assert_success
  assert_output --partial '"state":"behind"'
  assert_output --partial '"behind_count":1'
  echo "$output" | python3 -m json.tool > /dev/null
}

@test "hug llu --json: unborn HEAD with upstream config -> error sync_state_unknown" {
  git checkout -q --orphan fresh
  # `branch --set-upstream-to` refuses unborn branches — write config directly
  # (verified: rev-parse @{u} then succeeds rc=0 while both rev-list counts fail rc=128)
  git config branch.fresh.remote origin
  git config branch.fresh.merge refs/heads/main
  run hug llu --json
  assert_success
  assert_output --partial '"error":"sync_state_unknown"'
  refute_output --partial '"state"'
  echo "$output" | python3 -m json.tool > /dev/null
}

@test "hug llu: unborn HEAD with upstream config -> fallback message, scoped run" {
  git checkout -q --orphan fresh
  git config branch.fresh.remote origin
  git config branch.fresh.merge refs/heads/main
  run hug llu -- . # scoped: the trailing whole-repo summary must NOT fire
  assert_success
  assert_output --partial "📭 No outgoing commits (sync state with origin/main could not be determined)"
  refute_output --partial "up to date"
  refute_output --partial "HEAD:"
}

@test "hug llu -q: synced -> message AND summary suppressed" {
  run hug llu -q
  assert_success
  refute_output --partial "No outgoing commits"
  refute_output --partial "HEAD:"
}

@test "hug llu -q: behind -> message AND summary suppressed" {
  make_behind
  run hug llu -q
  assert_success
  refute_output --partial "No outgoing commits"
  refute_output --partial "HEAD:"
}
```

- [ ] **Step 2: Verify red** — `make test-unit TEST_FILE=test_llu.bats TEST_SHOW_ALL_RESULTS=1` → the synced/behind/unknown tests FAIL against today's message and bare JSON envelope.

- [ ] **Step 3: Wire both sinks** — in `git-config/bin/git-llu`, replace:

```bash
if [ "$commit_count" -eq 0 ]; then
  if $json_output; then
    echo '{"commits":[],"summary":{"total_commits":0}}'
  else
    info "📭 No outgoing commits (branch is up to date with ${upstream})"
    # Same summary gate as the no-upstream site above.
    if ! $quiet && [[ ${#pathspecs[@]} -eq 0 ]]; then
      exec hug s
    fi
  fi
  exit 0
fi
```

with:

```bash
if [ "$commit_count" -eq 0 ]; then
  if $json_output; then
    # Machine truth surface: the PRIMITIVE (not the message wrapper) so a
    # failed count renders as an error marker — never as in_sync. The unknown
    # envelope reuses the no_upstream error-marker convention (see :163).
    state=$(sync_state_of "$upstream")
    case "$state" in
    in_sync)
      echo '{"commits":[],"summary":{"total_commits":0,"state":"in_sync","behind_count":0}}'
      ;;
    behind\ *)
      echo "{\"commits\":[],\"summary\":{\"total_commits\":0,\"state\":\"behind\",\"behind_count\":${state#behind }}}"
      ;;
    *)
      echo '{"commits":[],"summary":{"total_commits":0,"error":"sync_state_unknown"}}'
      ;;
    esac
  else
    # 0 ahead != synced — the wrapper distinguishes synced from behind-by-N
    # (spec: docs/superpowers/specs/2026-08-28-truthful-sync-…-design.md).
    report_empty_outgoing "📭 No outgoing commits" "$upstream" "$upstream"
    # Same summary gate as the no-upstream site above.
    if ! $quiet && [[ ${#pathspecs[@]} -eq 0 ]]; then
      exec hug s
    fi
  fi
  exit 0
fi
```

Implementation notes:
- `$upstream` is `git rev-parse --abbrev-ref --symbolic-full-name @{u}` (e.g. `origin/main`) — valid as both display and measurement ref.
- `${state#behind }` is a bare integer (git's own count) — safe to interpolate into the JSON string.
- Every path still reaches `exit 0`; the summary gate is byte-identical to before.

- [ ] **Step 4: Verify green** — `make test-unit TEST_FILE=test_llu.bats TEST_SHOW_ALL_RESULTS=1` → all 8 pass.

- [ ] **Step 5: Commit**

```bash
hug a git-config/bin/git-llu tests/unit/test_llu.bats
hug c -F - <<'EOF'
fix(llu): truthful sync state on empty path — human + three-state JSON

WHY: On a behind-only branch, `hug llu` printed "No outgoing commits (branch
is up to date with origin/main)" while its own trailing `hug s` summary showed
"[behind 189]" — one screen, two opposite facts (the user-reported defect).
Worse, the gate's `|| echo "0"` swallow (git-llu:181) converts a FAILED count
into the same lie: on an unborn HEAD with upstream config, rev-parse @{u}
succeeds (rc=0) while both rev-list counts fail (rc=128), so the old bare
empty JSON envelope was indistinguishable from in_sync.

WHAT: The human path now calls the shared report_empty_outgoing wrapper
(synced / behind-by-N / fallback). The JSON path consumes the sync_state_of
PRIMITIVE and emits a three-state empty envelope: state in_sync
(behind_count 0), state behind (behind_count N), or error
sync_state_unknown — reusing the no_upstream error-marker convention. The
non-empty (ahead) envelope is deliberately unchanged (a non-empty commits
array IS the ahead signal; spec scope cut). Summary gate, exit codes, and the
no_upstream envelope are byte-identical to before.

HOW: New tests/unit/test_llu.bats (8 tests): synced + behind human runs with
trailing-summary pinning, both JSON state envelopes, an unborn-HEAD fixture
(orphan checkout + direct branch.<name>.remote/merge config — the documented
way to reach the unknown branch, since --set-upstream-to refuses unborn
branches), a scoped human unknown run (proves the summary gate stays off), and
-q suppression pins for both states. All JSON validated via python3 -m
json.tool.

IMPACT: `hug llu` stops contradicting itself on behind branches, and scripts
can finally distinguish "in sync" from "behind by N" from "unknowable" —
the machine channel now keeps the same failure-honesty promise as the human
one.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
```

---

### Task 5: Docs + superseding note + full-suite verification

**Goal:** Update the help/docs surfaces the spec's change-set names, mark the stale audit verdicts superseded, and prove the whole suite green.

**Files:**
- Modify: `git-config/bin/git-llu` (show_help text only)
- Modify: `docs/superpowers/specs/2026-07-29-count-commits-in-range-audit-design.md` (superseding note near :182-186)
- Modify: `docs/superpowers/specs/2026-08-16-uniform-pathspec-contract-for-all-path-accepting-hug-commands-design.md` (stale empty-envelope prose at ~:428 — found by Task 4's quality review)
- Modify: `docs/commands/logging.md` (~:237, the "(empty shape on zero matches)" aside)

**Acceptance Criteria:**
- [ ] `hug llu -h` documents behind + unknown and the three empty JSON envelopes
- [ ] The 2026-07-29 audit doc carries a superseded-note scoping its SAFE verdicts to exit-code propagation
- [ ] The 2026-08-16 uniform-pathspec spec's stale empty-envelope sentence (~:428) carries an update pointer to this design's §3 three-state contract
- [ ] Gate 1 (mechanical): the live-code grep over the three fixed scripts returns AT MOST the single mandated show_help quote line (`git-config/bin/git-llu:38`, quoting the NEW truthful runtime message) — any other hit is a FAIL
- [ ] Gate 2 (perimeter audit): the docs/superpowers/-excluded grep returns only CATEGORY-EXPECTED hits — new truthful runtime/docstring strings (`hug-git-upstream` fn block, `git-llu:38`), test assertions/refutes of both old partials and new messages, `git-wtsh`/`git-stats-branch`/`branch-analysis.md:295` correct-code hits — and nothing else
- [ ] `make test` green; `make docs-build` green

**Verify:** `make test TEST_SHOW_ALL_RESULTS=0` → all green; `make docs-build` → exit 0.

**Steps:**

- [ ] **Step 1: Update `git-llu` help text** — in `show_help`, change the DESCRIPTION paragraph:

```
    If there is no upstream branch or no outgoing commits, shows an informative
    message instead.
```

to:

```
    If there is no upstream branch, or there are no outgoing commits, shows an
    informative message instead. With no outgoing commits the message is
    truthful about the direction: "already synced to <upstream>" when in sync,
    or "branch is behind <upstream> by N commits — pull or rebase to catch
    up" when behind. The message always describes the whole branch, even on a
    scoped (pathspec-filtered) run.
```

and extend the JSON OUTPUT section's summary description with:

```
      "summary": {
        "total_commits": 5,
        "date_range": {"earliest": "...", "latest": "..."}
      }

    Empty envelope (no outgoing commits) — one of three shapes:

      {"commits":[],"summary":{"total_commits":0,"state":"in_sync","behind_count":0}}
      {"commits":[],"summary":{"total_commits":0,"state":"behind","behind_count":189}}
      {"commits":[],"summary":{"total_commits":0,"error":"sync_state_unknown"}}

    No upstream configured: {"commits":[],"summary":{"total_commits":0,"error":"no_upstream"}}
```

- [ ] **Step 2: Add the superseding note** — insert directly ABOVE the verdict table in `docs/superpowers/specs/2026-07-29-count-commits-in-range-audit-design.md` (near :182):

```markdown
> **Superseded (2026-08-28), message dimension only:** the SAFE verdicts below
> for `git-log-outgoing:92` and `git-h-files:122` addressed **exit-code
> propagation** and remain valid on that dimension. Their claim that
> `== 0` is the correct "already synced" semantic is **false for message
> truthfulness**: a behind-only branch also yields `== 0` (verified by
> execution). Superseded by
> `2026-08-28-truthful-sync-state-messages-for-llu-lol-h-files-design.md` and
> elifarley/hug-scm#237/#238.
```

- [ ] **Step 3: Touch up `docs/commands/logging.md`** — change `(empty shape on zero matches)` to `(empty envelope with a `state`/`error` marker on zero matches — see `hug help llu`)`.

- [ ] **Step 3b: Update the 2026-08-16 pathspec spec's stale envelope sentence** — in `docs/superpowers/specs/2026-08-16-uniform-pathspec-contract-for-all-path-accepting-hug-commands-design.md` (~:428), immediately after the sentence stating `JSON mode keeps its existing empty envelope ({"commits":[],"summary":{"total_commits":0}}`, append:

  > **Updated 2026-08-28:** the empty envelope is now three-state — `state` `in_sync`|`behind` with `behind_count`, or `error:"sync_state_unknown"` — see `2026-08-28-truthful-sync-state-messages-for-llu-lol-h-files-design.md` §3.

- [ ] **Step 4: Verification greps (two gates)** —

Gate 1 is the mechanical pass/fail: the three fixed sites must contain NEITHER phrase as LIVE code after Tasks 1-4 (before the fix, each contains one). The single sanctioned exception is the show_help quote of the NEW truthful runtime message (a doc line, not a live claim).

```bash
# Gate 1 — live code, mechanical: any hit other than the sanctioned help quote = FAIL.
grep -rn "up to date with\|already synced" \
  git-config/bin/git-llu git-config/bin/git-log-outgoing git-config/bin/git-h-files
```
Expected: exactly one line, `git-config/bin/git-llu:38` (the show_help quote added in Step 1). Nothing else.

Gate 2 is the informational perimeter audit (human-reviewed residual set — historical design docs under `docs/superpowers/` are excluded wholesale: the new spec, this plan, and the audit doc all quote the phrases intentionally, and the audit doc's superseding note scopes its SAFE rows).

```bash
# Gate 2 — everything else that ships the phrases must be on this allowlist
grep -rn "up to date with\|already synced" \
  README.md docs/ git-config/ hg-config/ tests/ | grep -v "docs/superpowers/"
```
Expected residual set (nothing else): the lib docstring (`hug-git-upstream:29`), `git-wtsh` + `git-stats-branch` correct-code hits (they compute both directions; `git-stats-branch:78` is help-text example, not live logic), the natural-language guide heading `docs/skills/hug-repo-analysis/guides/branch-analysis.md:295`, and the two surviving test partials (`test_log_outgoing.bats:65,118`).

- [ ] **Step 5: Full verification** — `make test` (BATS + pytest) → green; `make docs-build` → exit 0.

- [ ] **Step 6: Commit**

```bash
hug a git-config/bin/git-llu docs/superpowers/specs/2026-07-29-count-commits-in-range-audit-design.md docs/superpowers/specs/2026-08-16-uniform-pathspec-contract-for-all-path-accepting-hug-commands-design.md docs/commands/logging.md
hug c -F - <<'EOF'
docs: truthful sync-state help text + superseding note for the 2026-07-29 audit

WHY: The spec's docs change-set (§4) requires the help text to describe the
new behind/unknown behavior and the three empty JSON envelopes, and requires
an explicit direction on the 2026-07-29 count-commits-in-range audit, whose
SAFE verdicts for the lol/h-files gates asserted the opposite
message-truthfulness conclusion. Without the note, a future grep for "already
synced" finds two authoritative-looking, opposite answers about the same gate.

WHAT: git-llu show_help gains the behind/unknown wording, the
whole-branch-scoped-message note, and the three-envelope JSON documentation.
The audit doc gets a scoped superseded-note: SAFE verdicts remain valid for
exit-code propagation, superseded for message truthfulness by this work and
#237/#238. logging.md's "(empty shape on zero matches)" aside now points at
the state/error marker.

HOW: Verification greps confirm no other surface quotes the retired wording
(roast R7 perimeter, re-checked post-change). Full make test + make
docs-build gate the change.

IMPACT: Users discover the new behavior from the command itself; future
readers of the audit doc are told which dimension was superseded and by what,
instead of silently choosing the wrong verdict.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
```

---

## Self-Review Record

- **Spec coverage:** §1 functions → Task 1; §2 call sites → Tasks 2 (lol), 3 (h-files), 4 (llu human); §3 JSON three-state → Task 4; §4 docs + superseding note → Task 5; success criteria 1-4 → Task 5 Step 5 gates them. O-006 quiet semantics → Task 4 `-q` tests; O-003 scoped-run help mention → Task 5 Step 1; O-001 divergence gap stays a recorded non-goal (spec).
- **Placeholder scan:** every code step carries complete code; no TBD/TODO/"handle edge cases".
- **Type consistency:** `sync_state_of` / `report_empty_outgoing` signatures identical across Tasks 1-4; envelope key names match spec §3 exactly; test helper names (`setup_synced_upstream`, `advance_remote`, `create_test_repo_with_remote_upstream`) verified to exist at the cited locations.
