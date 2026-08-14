# Content-Null Amend Guard for cmod/cmoda — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:subagent-driven-development (recommended) or superpowers-extended-cc:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refuse a content-null amend in `hug cmod`/`hug cmoda` (empty index / clean tree + keep-message intent + no `-f`) with exit 3 via `error_blocked`, so `cmod --no-edit` with nothing staged stops silently re-hashing HEAD (elifarley/hug-scm#263).

**Architecture:** Two new functions in `git-config/lib/hug-git-commit`: `amend_args_message_intent` (computes the **candidate message** — the message the amend would produce — for the statically-decidable flag set, compares byte-for-byte against HEAD's message, returns 0=KEEP/1=CHANGE/2=EDITOR) and `guard_content_null_amend` (picks one content model — staged/tracked/paths — from the arg shape, runs the honest `git diff --quiet` check, exits 3 via `error_blocked` on content-null + KEEP without `HUG_FORCE`, sets caller global `_amend_content_null`). Both bin scripts pre-parse pathspecs with `parse_pathspecs` BEFORE `parse_common_flags` (the library's documented contract — `parse_common_flags` consumes a trailing `--`), re-insert pathspecs into the final `git commit` call, and pick a state-dependent info line from `_amend_content_null` + `amend_args_message_intent`.

**Tech Stack:** Bash (BATS tests, `set -euo pipefail`), GNU make, shellcheck, `git interpret-trailers` (trailer dedupe), `git rev-parse`/`git log -1 --format=%B` (candidate sources). Bash floor 4.0 (no `local -n`).

**Spec:** `docs/superpowers/specs/2026-08-12-cmod-content-null-amend-guard-design.md` (roast-clean after 3 rounds — all probe citations in this plan come from that spec's verified receipts).

**Worktree:** `/home/ecc/src/hug-scm.WT.fix-263-content-null-amend-guard` (branch `fix-263-content-null-amend-guard`). Do ALL work here; the Bash tool resets CWD between calls, so use absolute paths or `cd` at the start of each command.

**Commit discipline:** Use `hug` commands, never raw git. Commit messages document WHY (load the `commit-message` skill). One logical commit per task. Run `make test-unit TEST_FILE=test_commit.bats` and `make test-lib TEST_FILE=test_hug-git-commit.bats` before each commit.

## Global Constraints

- Bash floor 4.0: no `local -n`, no `${var@Q}` — use `printf %q` and `set --` patterns (copied from spec §2).
- Guard runs after `parse_common_flags` — `HUG_FORCE`/`HUG_YES` are exported env vars, never re-read from `"$@"`.
- The guard is **fail-open**: diff rc `>1` → proceed (never refuse on a corrupt index/unborn-HEAD error). Only rc `0` (content-null) + KEEP + no `HUG_FORCE` refuses.
- Exit code for refusal: `HUG_EX_BLOCKED=3` via `error_blocked` (defined in `hug-output`; sourced transitively by `hug-git-kit`).
- `-y`/`HUG_YES` does NOT bypass the guard (spec decision table — semantic guard, not confirmation).
- Never mutate `$@` shape for the final `git commit --amend "$@"` — flags must arrive exactly as the user passed them (minus `-f/-y/-q` stripped by `parse_common_flags`, plus re-inserted pathspecs).
- Every refusal message and info line uses the §3 copy verbatim (spec §3 — the exact strings are load-bearing for the quality-corpus test).
- All test hashes that assert churn MUST set a forced `GIT_COMMITTER_DATE` (spec §1 same-second identity caveat — identical timestamp yields a byte-identical commit object, no hash change).

---

## File Structure

| File | Responsibility | Touched by |
|---|---|---|
| `git-config/lib/hug-git-commit` | + `amend_args_message_intent` (candidate-message three-way classifier), + `guard_content_null_amend` (content-model picker + refuser + `_amend_content_null` global). Header comment gains the two functions. | Task 1 |
| `git-config/bin/git-cmod` | Pre-parse (`parse_pathspecs` → `parse_common_flags`), guard call (`staged`), state-dependent info line, SAFETY GUARD help section. | Task 2 |
| `git-config/bin/git-cmoda` | Pre-parse, guard call (`tracked`), state-dependent info line, SAFETY GUARD help section. | Task 3 |
| `tests/lib/test_hug-git-commit.bats` | Library tests: `amend_args_message_intent` table (spec §6 test 23 verbatim) + `guard_content_null_amend` fail-open + paths branch (spec §6 tests 24/25). | Task 1 |
| `tests/unit/test_commit.bats` | Behavioral tests for both commands (spec §6 tests 1-22). | Task 2, Task 3 |
| `docs/commands/commits.md` | cmod/cmoda sections: guard, exit-3 refusal, `-f` hatch. | Task 4 |
| `git-config/lib/python/articles/agents.md` | Amending section: guard one-liner. | Task 4 |
| `docs/skills/hug-workflow/SKILL.md` | Agent skill: guard one-liner. | Task 4 |
| `README.md` | `cmod` one-liner annotation (line 477). | Task 4 |
| `CHANGELOG.md` | `[Unreleased]` → `### Fixed` entry. | Task 4 |

---

### Task 1: Library — `amend_args_message_intent` + `guard_content_null_amend`

**Files:**
- Modify: `git-config/lib/hug-git-commit` (append the two functions after `commit_args_indicate_amend`, ~line 540; header comment at ~line 7 gains the two names)
- Test: `tests/lib/test_hug-git-commit.bats` (append new tests at end of file)

**Interfaces:**
- Consumes: `hug-output`'s `error_blocked` (via `hug-git-kit` sourcing), `hug-git-state`'s `get_untracked_files` (already in scope — `hug-git-kit` sources both).
- Produces:
  - `amend_args_message_intent "$@"` → returns `0` (KEEP — candidate == HEAD message), `1` (CHANGE — candidate differs), `2` (EDITOR — not statically decidable). No stdout.
  - `guard_content_null_amend <staged|tracked> "$@" [-- <paths...>]` → exits 3 (via `error_blocked`) on refusal; otherwise returns 0. Sets caller global `_amend_content_null=true|false`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/lib/test_hug-git-commit.bats` (after the last existing test; the file already loads `hug-git-commit` at line 5, so both functions are in scope):

```bash
################################################################################
# amend_args_message_intent TESTS (spec §6 test 23)
################################################################################

# Helper: assert the classifier's return code for a given arg vector.
# Uses `run` — bare calls returning 1/2 would trip BATS errexit.
check_intent() {
  local expected="$1"; shift
  run amend_args_message_intent "$@"
  [[ "$status" -eq "$expected" ]] \
    || { echo "expected intent $expected for args [$*], got status $status" >&2; return 1; }
}

@test "amend_args_message_intent: keep/change/editor classification table" {
  # setup() puts HEAD at "third commit"

  # KEEP (0): --no-edit alone, HEAD-resolving refs, identical candidates
  check_intent 0 --no-edit
  check_intent 0 --no-edit -C HEAD
  check_intent 0 --no-edit --reuse-message=HEAD
  check_intent 0 --no-edit -c HEAD
  check_intent 0 --no-edit --reedit-message=HEAD
  check_intent 0 --no-edit -C @
  check_intent 0 --no-edit -C HEAD~0
  check_intent 0 --no-edit -m "third commit"
  check_intent 0 --no-edit -- -m          # after -- is pathspec data

  # CHANGE (1): candidate differs
  check_intent 1 -m x
  check_intent 1 -m x --no-edit
  check_intent 1 -C HEAD~1                # "second commit" differs
  check_intent 1 --reuse-message=HEAD~1
  check_intent 1 -c X --no-edit           # silent replacement (probe-verified)
  check_intent 1 --no-edit --signoff      # signoff absent from "third commit"
  check_intent 1 -s
  check_intent 1 -m"attached"
  check_intent 1 -CHEAD~1                 # attached value
  check_intent 1 --no-edit --fixup=HEAD
  check_intent 1 --no-edit --fixup amend:HEAD   # space form
  check_intent 1 --no-edit --squash=HEAD
  check_intent 1 --no-edit --trailer "Co-Authored-By: x <x@x>"   # absent

  # EDITOR (2): not statically decidable
  check_intent 2                          # bare
  check_intent 2 -c X                     # -c without --no-edit opens editor
  check_intent 2 --reedit-message=X
  check_intent 2 --no-edit -e             # -e overrides --no-edit AND -m
  check_intent 2 -m x -e
}

@test "amend_args_message_intent: -F identical file and trailer dedupe are KEEP" {
  # Candidate == HEAD when -F file content matches HEAD message
  git log -1 --format=%B > ident.txt
  check_intent 0 --no-edit -F ident.txt

  # Candidate == HEAD when the signoff trailer already exists (dedupe).
  # Test repo ident is "Hug Test <test@hug-scm.test>" (create_test_repo).
  git commit -q --amend -m "$(printf 'third commit\n\nSigned-off-by: Hug Test <test@hug-scm.test>')"
  check_intent 0 --no-edit -s
}

@test "amend_args_message_intent: multi -m concatenates paragraphs (candidate join)" {
  # -m a -m b produces "a\n\nb" — a candidate that CAN equal HEAD's message
  git commit -q --amend -m "$(printf 'x\n\ny')"
  check_intent 0 --no-edit -m x -m y
}

################################################################################
# guard_content_null_amend TESTS (spec §6 tests 24/25)
################################################################################

@test "guard_content_null_amend: refuses staged content-null amend (exit 3)" {
  run guard_content_null_amend staged --no-edit
  [ "$status" -eq 3 ]
  assert_output --partial "Nothing to amend"
}

@test "guard_content_null_amend: bypasses on HUG_FORCE" {
  HUG_FORCE=true guard_content_null_amend staged --no-edit
  [ $? -eq 0 ]
  [ "$_amend_content_null" = "true" ]
}

@test "guard_content_null_amend: message-change proceeds and reports content-null" {
  guard_content_null_amend staged --no-edit -m "different"
  [ $? -eq 0 ]
  [ "$_amend_content_null" = "true" ]     # caller needs this for the honest info line
}

@test "guard_content_null_amend: fail-open on corrupt index (rc>1 proceeds)" {
  echo "garbage" > .git/index
  run guard_content_null_amend staged --no-edit
  assert_success
}

@test "guard_content_null_amend: paths branch folds worktree content (proceed when modified)" {
  # setup has clean index (all committed). Add worktree change to file1.txt
  echo "worktree edit" >> file1.txt
  guard_content_null_amend staged --no-edit -- file1.txt
  [ $? -eq 0 ]
  [ "$_amend_content_null" = "false" ]
}

@test "guard_content_null_amend: paths branch refuses when named path matches HEAD" {
  run guard_content_null_amend staged --no-edit -- file1.txt
  [ "$status" -eq 3 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test-lib TEST_FILE=test_hug-git-commit.bats TEST_FILTER="amend_args_message_intent|guard_content_null_amend" TEST_SHOW_ALL_RESULTS=1`
Expected: FAIL — `amend_args_message_intent: command not found` (both functions absent).

- [ ] **Step 3: Implement the two functions**

Append to `git-config/lib/hug-git-commit`:

```bash
# amend_args_message_intent "$@" — three-way scan of forwarded commit args.
# Computes the CANDIDATE message (what the amend would produce) for the
# statically-decidable flags and compares it byte-for-byte against HEAD's
# message. No literal ref comparison anywhere — semantic comparison only.
# Returns:
#   0 = KEEP message    (candidate == HEAD's message)
#   1 = CHANGE message  (candidate differs from HEAD's message)
#   2 = EDITOR decides  (bare, -e/--edit, or -c/--reedit-message without
#                        --no-edit)
# Evaluation order mirrors git's own grammar:
#   -e/--edit beats everything (opens the editor);
#   --fixup/--squash guarantee a prefixed (different) message;
#   message source: -m values concatenate with "\n\n" (git multi -m);
#   -F file content; -C <ref> / -c <ref> WITH --no-edit → the ref's
#   message (silent replacement); -c WITHOUT --no-edit → editor;
#   trailers (-s/--signoff, --trailer <k: v>) append onto the source
#   result via git interpret-trailers, which dedupes the exact line;
#   unresolvable -F/-C/-c source → CHANGE (1): git will produce its own
#   loud error downstream (fail-open).
# Config caveat: trailer.ifexists/ifmissing alter dedupe; computed under
# DEFAULT config — a mispredict is a loud refusal or proceed, never silent.
# Scanning follows commit_args_indicate_amend: skip flag values, stop at --.
# WHY three-way: the guard needs "keep" (fires); the caller's info line
# needs "change"/"editor" to stay honest. Callers MUST capture via
# `rc=0; amend_args_message_intent "$@" || rc=$?` — under `set -e` a bare
# call returning 1/2 kills the script (the commit_offset errexit lesson).
amend_args_message_intent() {
    local head_msg
    head_msg=$(git log -1 --format=%B HEAD)

    local has_no_edit=false has_source=false
    local -a m_values=() trailer_args=()
    local f_file= c_ref= reedit=false

    while (($#)); do
        case "$1" in
            --) break ;;
            --no-edit) has_no_edit=true ;;
            -e|--edit) return 2 ;;
            --fixup|--squash|--fixup=*|--squash=*) return 1 ;;
            -m|--message) has_source=true; m_values+=("$2"); shift ;;
            -m*|--message=*)
                # bash 4.0 floor: no negative array indices — strip via expansion
                has_source=true
                local v="${1#-m}"
                [[ "$1" == --message=* ]] && v="${1#--message=}"
                m_values+=("$v")
                ;;
            -F|--file) has_source=true; f_file="$2"; shift ;;
            -F*|--file=*)
                has_source=true
                f_file="${1#-F}"
                [[ "$1" == --file=* ]] && f_file="${1#--file=}"
                ;;
            -C|--reuse-message|-c|--reedit-message)
                has_source=true
                c_ref="$2"
                [[ "$1" == -c || "$1" == --reedit-message ]] && reedit=true
                shift
                ;;
            -C*|--reuse-message=*)
                has_source=true
                c_ref="${1#-C}"
                [[ "$1" == --reuse-message=* ]] && c_ref="${1#--reuse-message=}"
                ;;
            -c*|--reedit-message=*)
                has_source=true
                reedit=true
                c_ref="${1#-c}"
                [[ "$1" == --reedit-message=* ]] && c_ref="${1#--reedit-message=}"
                ;;
            -s|--signoff)
                has_source=true
                # signoff line from the committer ident (git's own source)
                trailer_args+=(--trailer "Signed-off-by: $(git var GIT_COMMITTER_IDENT 2>/dev/null | sed 's/ [0-9]* [+-][0-9]*$//')")
                ;;
            --trailer) has_source=true; trailer_args+=(--trailer "$2"); shift ;;
            --trailer=*) has_source=true; trailer_args+=(--trailer "${1#--trailer=}") ;;
        esac
        shift
    done

    # -c/--reedit-message WITHOUT --no-edit opens the editor.
    if $reedit && ! $has_no_edit; then
        return 2
    fi

    local candidate=""
    if ((${#m_values[@]})); then
        # git concatenates multiple -m with a blank line between paragraphs
        # (bash 4.0 floor: no array-join tricks — explicit loop)
        local sep="" v
        for v in "${m_values[@]}"; do
            candidate+="$sep$v"
            sep=$'\n\n'
        done
    elif [[ -n "$f_file" ]]; then
        candidate=$(cat "$f_file" 2>/dev/null) || return 1
    elif [[ -n "$c_ref" ]]; then
        candidate=$(git log -1 --format=%B "$c_ref" 2>/dev/null) || return 1
    fi

    if ((${#trailer_args[@]})); then
        # Append (and dedupe) onto the source result, or HEAD's message
        # when there is no source. interpret-trailers dedupes the exact
        # "key: value" line (probe TT1).
        local base_msg="$candidate"
        [[ -n "$base_msg" ]] || base_msg="$head_msg"
        candidate=$(printf '%s\n' "$base_msg" | git interpret-trailers "${trailer_args[@]}" 2>/dev/null) || return 1
    fi

    # Track source PRESENCE separately from candidate CONTENT: -m '' and an
    # empty -F file are legitimate empty candidates (git replaces the
    # message with nothing when --allow-empty-message permits), and must
    # classify CHANGE (1), not fall through to KEEP. `has_source` is set by
    # the scan whenever a source flag appears, even with an empty value.
    if $has_source; then
        if [[ "$candidate" == "$head_msg" ]]; then return 0; fi
        return 1
    fi

    if $has_no_edit; then return 0; fi
    return 2   # bare — the editor decides
}

# guard_content_null_amend <staged|tracked> "$@" [-- <paths...>]
# Refuses a content-null amend (exit 3 via error_blocked) unless HUG_FORCE.
# Sets the caller global _amend_content_null=true|false so the caller picks
# an honest info line (computed once, used twice — the git-c idiom).
# ALWAYS computes content-null (even when the message changes) — the info
# line for a message-only amend needs it. Refusal requires content-null
# AND keep-message AND no HUG_FORCE.
# Content model is the honest one for the amend's actual content source:
#   - trailing paths (bare, or after the -- group) → `git diff HEAD --quiet
#     -- <paths>` (--only mode folds worktree content, not the index)
#   - -a/--all, -p/--patch, -i/--interactive → tracked check (worktree+index
#     vs HEAD); a clean tree still refuses (probe-verified churn)
#   - otherwise → mode argument (staged = git diff --cached; tracked =
#     git diff HEAD)
# Fail-open: rc>1 proceeds (never refuse on a corrupt index or unborn HEAD).
# WHY called BARE (never $(guard_content_null_amend ...)): error_blocked must
# exit the SCRIPT — captured, the refusal dies in the subshell (the exact
# head-mover lesson). Assumes parse_common_flags already ran: -f/-y/-q are
# stripped from "$@" and HUG_FORCE/HUG_YES are set.
guard_content_null_amend() {
    local mode="$1"; shift

    # --- content model (always computed) ---
    local -a paths=()
    local check_mode="$mode"
    local saw_ddash=false
    for arg in "$@"; do
        $saw_ddash && paths+=("$arg") && continue
        case "$arg" in
            --) saw_ddash=true ;;
            -a|--all|-p|--patch|-i|--interactive) check_mode=tracked ;;
            --only) check_mode=paths ;;
        esac
    done
    # bare trailing paths (no --): non-flag tokens not consumed as values.
    # Value-skip walk over EVERY value-taking git commit option (from
    # `git commit -h`): message sources, --author, --date, --cleanup,
    # --pathspec-from-file, and the fixup/squash/trailer values. Any other
    # non-dash token is a bare path.
    local -a flag_args=("$@")
    local i=0 tok
    while ((i < ${#flag_args[@]})); do
        tok="${flag_args[i]}"
        case "$tok" in
            --) break ;;
            -m|-C|-c|-F|-t|--message|--file|--reuse-message|--reedit-message|--fixup|--squash|--trailer|--author|--date|--cleanup|--pathspec-from-file)
                ((i += 2)); continue ;;
            --*=*) ((i += 1)); continue ;;
            -*) ((i += 1)); continue ;;
            *) paths+=("$tok"); check_mode=paths; ((i += 1)) ;;
        esac
    done
    # Paths win over -a/-p/-i whenever present: git treats an explicit path
    # list as --only content even alongside -p/-i (probe-verified); -a with
    # paths is rejected by git itself ("does not make sense") before the
    # amend ever runs, so the paths check is the honest one either way.
    ((${#paths[@]})) && check_mode=paths

    # --- the honest diff check ---
    local rc=0
    case "$check_mode" in
        paths)
            if ((${#paths[@]})); then
                rc=0; git diff --quiet HEAD -- "${paths[@]}" || rc=$?
            else
                rc=0; git diff --quiet HEAD || rc=$?
            fi ;;
        tracked) rc=0; git diff --quiet HEAD || rc=$? ;;
        staged)  rc=0; git diff --quiet --cached || rc=$? ;;
    esac

    # content-null is reported even when the amend will proceed — the
    # caller's info line for a message-only amend depends on it.
    if ((rc == 0)); then _amend_content_null=true; else _amend_content_null=false; fi
    if ((rc != 0)); then return 0; fi          # content exists → never refuse

    # --- message intent ---
    local msg_rc=0
    amend_args_message_intent "$@" || msg_rc=$?
    if ((msg_rc != 0)); then return 0; fi      # CHANGE/EDITOR → proceed

    # --- refusal (unless forced) ---
    if [[ "${HUG_FORCE:-}" == "true" ]]; then
        return 0
    fi

    local msg untracked_count cmd_name scope_label
    cmd_name="cmod"; scope_label="staged changes"
    if [[ "$mode" == "tracked" ]]; then
        cmd_name="cmoda"
        scope_label="tracked changes"
    fi
    untracked_count=$(get_untracked_files | wc -l)
    msg="Nothing to amend — no $scope_label and no message change; the amend would only rewrite HEAD's hash (same tree, same message)."
    msg+=$'\n'"Stage changes first ('hug a <files>') or change the message ('hug $cmd_name -m \"msg\"')."
    msg+=$'\n'"To re-hash/re-date HEAD anyway, re-run with -f/--force."
    if ((untracked_count > 0)); then
        msg+=$'\n'$'\n'"Note: $untracked_count untracked file(s) exist; $cmd_name never includes untracked files — stage them first with 'hug a <file>…' (bare 'hug a' only stages tracked changes) or 'hug aa'."
    fi
    error_blocked "$msg"
}
```

Add to the `hug-git-commit` header comment (the `# HUG-GIT-COMMIT:` block at line ~3): " - Amend safety guards (`amend_args_message_intent`, `guard_content_null_amend`)" plus the bullet list update.

- [ ] **Step 4: Run the lib tests to verify they pass**

Run: `make test-lib TEST_FILE=test_hug-git-commit.bats TEST_SHOW_ALL_RESULTS=1`
Expected: All tests pass, including the new `amend_args_message_intent`/`guard_content_null_amend` blocks and the pre-existing `count_commits_in_range`/`suggest_next_push_command` tests.

- [ ] **Step 5: Sanitize**

Run: `make sanitize-check`
Expected: shellcheck clean. Fix any SC-warnings (especially SC2076 for `[[ ... == *"..."* ]]` and SC2207 for array assignment).

- [ ] **Step 6: Commit**

```bash
hug a git-config/lib/hug-git-commit tests/lib/test_hug-git-commit.bats
hug c -F - <<'EOF'
feat(hug-git-commit): add amend content-null guard + message-intent classifier (#263)

[your WHY narrative — load the commit-message skill]
EOF
```

---

### Task 2: `git-cmod` — pre-parse, guard call, honest info line

**Files:**
- Modify: `git-config/bin/git-cmod` (the call-site block: lines 121-126 — `eval "$(parse_common_flags "$@")"` + `check_git_repo` + `info ...` + `git commit ...`; the `show_help` WARNING block gains the SAFETY GUARD section)
- Test: `tests/unit/test_commit.bats` (append the cmod behavioral tests)

**Interfaces:**
- Consumes: `amend_args_message_intent`, `guard_content_null_amend`, `_amend_content_null` (Task 1); `parse_pathspecs` (from `hug-cli-flags`, sourced via `hug-common`).
- Produces: `git-cmod` behavior: exit 3 on content-null refusal; state-dependent info line; SAFETY GUARD help.

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_commit.bats`:

```bash
@test "hug cmod: refuses content-null amend with --no-edit (exit 3)" {
  # create_test_repo_with_changes has staged.txt staged — unstage everything first
  git restore --staged .
  run hug cmod --no-edit
  [ "$status" -eq 3 ]
  assert_output --partial "Nothing to amend"
}

@test "hug cmod: -f bypasses the guard (hash churn with forced date)" {
  git restore --staged .
  local head_before
  head_before=$(git rev-parse HEAD)
  GIT_COMMITTER_DATE='2030-01-01T00:00:00Z' run hug cmod --no-edit -f
  assert_success
  [ "$(git rev-parse HEAD)" != "$head_before" ]
  [ "$(git show -s --format=%T)" = "$(git rev-parse HEAD^{tree})" ]  # tree unchanged
}

@test "hug cmod: HUG_FORCE=true env bypass parity" {
  git restore --staged .
  local head_before
  head_before=$(git rev-parse HEAD)
  HUG_FORCE=true GIT_COMMITTER_DATE='2030-01-01T00:00:00Z' run hug cmod --no-edit
  assert_success
  [ "$(git rev-parse HEAD)" != "$head_before" ]
}

@test "hug cmod: -m with a new message proceeds" {
  git restore --staged .
  run hug cmod -m "new msg"
  assert_success
  [ "$(git log -1 --format=%s)" = "new msg" ]
}

@test "hug cmod: staged changes + --no-edit proceeds (no regression)" {
  # setup already has staged.txt staged
  run hug cmod --no-edit
  assert_success
  assert_output --partial "Amending last commit with staged changes"
}

@test "hug cmod: untracked-only tree + --no-edit → exit 3 + untracked note" {
  git restore --staged .
  run hug cmod --no-edit
  [ "$status" -eq 3 ]
  assert_output --partial "untracked file"
}

@test "hug cmod: -y does NOT bypass the guard" {
  git restore --staged .
  run hug cmod --no-edit -y
  [ "$status" -eq 3 ]
}

@test "hug cmod: -a re-mode — dirty tree proceeds, clean tree refuses" {
  git restore --staged .
  # dirty tree: README.md has unstaged changes (from setup)
  run hug cmod --no-edit -a
  assert_success

  # clean tree
  git restore .
  run hug cmod --no-edit -a
  [ "$status" -eq 3 ]
}

@test "hug cmod: pathspec --only folds worktree content (proceeds when modified)" {
  git restore --staged .
  echo "modified" >> README.md
  run hug cmod --no-edit -- README.md
  assert_success
  assert_output --partial "named paths"
}

@test "hug cmod: pathspec matching HEAD refuses (exit 3)" {
  git restore --staged .
  run hug cmod --no-edit -- README.md
  [ "$status" -eq 3 ]
}

@test "hug cmod: bare trailing path (no --) is a pathspec" {
  git restore --staged .
  echo "modified" >> README.md
  run hug cmod --no-edit README.md
  assert_success
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="hug cmod: refuses content-null" TEST_SHOW_ALL_RESULTS=1`
Expected: FAIL — current `git-cmod` proceeds (exit 0) and rewrites the hash.

- [ ] **Step 3: Implement the call site + SAFETY GUARD help**

Replace the `git-cmod` call-site block (the four lines after `# Parse common flags`):

```bash
# Pre-parse pathspecs FIRST: parse_common_flags intercepts a trailing --
# (hug-cli-flags:21-23 "Commands that accept -- <path>... must pre-parse
# pathspecs first"). Same idiom as git-shp:76-77.
eval "$(parse_pathspecs "$@")"
eval "$(parse_common_flags "${_pathspec_pre_args[@]}")"
# NOTE: the eval above did `set --` — $@ is now the STRIPPED pre_args
# (-f/-y/-q removed, HUG_FORCE/HUG_YES set). The guard scans $@ (matching
# its precondition), NOT _pathspec_pre_args (which still holds the
# unstripped originals). Pathspecs pass as a separate group after a
# literal --; bare trailing paths (no --) remain inside $@ and the guard
# treats trailing non-flag args as paths.
check_git_repo
guard_content_null_amend staged "$@" \
    -- "${_pathspec_pathspecs[@]}"                   # exits 3 on refusal
# pick honest info line from $_amend_content_null + amend_args_message_intent.
# Capture idiom: rc=0; fn || rc=$? — a bare call returning 1/2 would kill
# the script under set -e (the commit_offset errexit lesson).
_msg_rc=0
amend_args_message_intent "$@" || _msg_rc=$?
if [[ "${_amend_content_null:-false}" == "true" ]]; then
    if [[ "${HUG_FORCE:-}" == "true" ]]; then
        info "Amending last commit (--force: no content change — only the hash will be rewritten)..."
    elif ((_msg_rc == 1)); then
        info "Amending last commit (message change only — no staged changes)..."
    else
        info "Amending last commit (no content change; the editor decides the message)..."
    fi
else
    if [[ ${#_pathspec_pathspecs[@]} -gt 0 ]]; then
        info "Amending last commit with the named paths' changes..."
    else
        info "Amending last commit with staged changes..."
    fi
fi
if [[ ${#_pathspec_pathspecs[@]} -gt 0 ]]; then
    git commit --amend "$@" -- "${_pathspec_pathspecs[@]}" \
        && suggest_next_push_command --amend
else
    git commit --amend "$@" && suggest_next_push_command --amend
fi
```

Then add the SAFETY GUARD section to `show_help` (immediately after the existing WARNING block, before EXAMPLES):

```
  SAFETY GUARD:
  cmod refuses a content-null amend: with nothing staged and --no-edit (no
  message change either), the amend would only rewrite HEAD's hash — same
  tree, same message (unless --date/--reset-author were passed, metadata
  too) — which is almost always a mistake (e.g. running cmod
  before staging). The refusal exits 3 with an actionable message.
    - Stage changes first ('hug a <files>' — bare 'hug a' only stages tracked
      changes) or pass -m to change the message.
    - To re-hash/re-date HEAD anyway, re-run with -f/--force.
    - -y does NOT bypass the guard (it is not a confirmation).
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_SHOW_ALL_RESULTS=1`
Expected: All tests pass, including the new cmod guard tests and all pre-existing `hug c:`/`hug cmod:`/`hug cmv:` tests (the `hug cmod: suggests bpush...` tests must stay green — they stage changes first, so the guard proceeds).

- [ ] **Step 5: Sanitize + quality corpus**

Run: `make sanitize-check`
Run: `make test-lib-py TEST_FILTER=test_quality_corpus`
Expected: shellcheck clean; quality corpus passes (the SAFETY GUARD section must not drop `hug cmod` out of top-5 for query "amend" — the keywords `_hug_keywords` already include "amend", unchanged).

- [ ] **Step 6: Commit**

```bash
hug a git-config/bin/git-cmod tests/unit/test_commit.bats
hug c -F - <<'EOF'
feat(cmod): refuse content-null amends via guard (#263)

[your WHY narrative — load the commit-message skill]
EOF
```

---

### Task 3: `git-cmoda` — guard call (`tracked`), help section

**Files:**
- Modify: `git-config/bin/git-cmoda` (call-site block; `show_help` gains the SAFETY GUARD section with the mode-specific first sentence)
- Test: `tests/unit/test_commit.bats` (append cmoda tests)

**Interfaces:**
- Consumes: `guard_content_null_amend` (Task 1).
- Produces: `git-cmoda` behavior: exit 3 on clean-tree refusal; tracked-mode info line.

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_commit.bats`:

```bash
@test "hug cmoda: refuses content-null amend on clean tree (exit 3)" {
  git restore --staged .
  git restore .
  run hug cmoda --no-edit
  [ "$status" -eq 3 ]
  assert_output --partial "Nothing to amend"
}

@test "hug cmoda: -f bypasses (hash churn, forced date)" {
  git restore --staged .
  git restore .
  local head_before
  head_before=$(git rev-parse HEAD)
  GIT_COMMITTER_DATE='2030-01-01T00:00:00Z' run hug cmoda --no-edit -f
  assert_success
  [ "$(git rev-parse HEAD)" != "$head_before" ]
}

@test "hug cmoda: dirty tree + --no-edit proceeds (no regression)" {
  # setup has unstaged README.md change
  run hug cmoda --no-edit
  assert_success
}

@test "hug cmoda: -a re-mode — clean tree refuses" {
  git restore --staged .
  git restore .
  run hug cmoda --no-edit -a
  [ "$status" -eq 3 ]
}

@test "hug cmoda: -m new message on clean tree proceeds (message-only)" {
  git restore --staged .
  git restore .
  run hug cmoda -m "new msg"
  assert_success
  [ "$(git log -1 --format=%s)" = "new msg" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_FILTER="hug cmoda: refuses content-null" TEST_SHOW_ALL_RESULTS=1`
Expected: FAIL — current `git-cmoda` proceeds and churns.

- [ ] **Step 3: Implement**

Mirror Task 2's call site in `git-cmoda` with these two changes:
1. `guard_content_null_amend tracked "$@" -- "${_pathspec_pathspecs[@]}"` (mode `tracked`).
2. The content-present info line: `info "Amending last commit with all tracked changes..."` (unchanged wording).
3. The final commit MUST re-insert the pathspecs exactly like cmod's — otherwise the pre-parse silently strips `-- <paths>` and `-a` then amends ALL tracked changes instead of the named set (which git would have rejected: "paths with -a does not make sense"):

```bash
if [[ ${#_pathspec_pathspecs[@]} -gt 0 ]]; then
    git commit -a --amend "$@" -- "${_pathspec_pathspecs[@]}" \
        && suggest_next_push_command --amend
else
    git commit -a --amend "$@" && suggest_next_push_command --amend
fi
```

git then applies its own `-a`+paths rejection exactly as before the change.
4. SAFETY GUARD help section with the mode-specific first sentence: `"cmoda refuses a content-null amend: with no tracked changes at all (nothing staged, nothing modified) and --no-edit, …"`.

- [ ] **Step 4: Run tests**

Run: `make test-unit TEST_FILE=test_commit.bats TEST_SHOW_ALL_RESULTS=1`
Expected: All pass, including the new cmoda tests and pre-existing cmoda tests (none exist today — check `grep -n "hug cmoda" tests/unit/test_commit.bats`; the `hug ca`/`hug caa` tests must stay green).

- [ ] **Step 5: Sanitize**

Run: `make sanitize-check`
Expected: shellcheck clean.

- [ ] **Step 6: Commit**

```bash
hug a git-config/bin/git-cmoda tests/unit/test_commit.bats
hug c -F - <<'EOF'
feat(cmoda): refuse content-null amends via tracked guard (#263)

[your WHY narrative — load the commit-message skill]
EOF
```

---

### Task 4: Doc perimeter — commits.md, agents.md, SKILL.md, README, CHANGELOG

**Files:**
- Modify: `docs/commands/commits.md` (cmod § line 124, cmoda section)
- Modify: `git-config/lib/python/articles/agents.md` (Amending section, line 163-169)
- Modify: `docs/skills/hug-workflow/SKILL.md` (line 23-26 CRITICAL block)
- Modify: `README.md` (line 477)
- Modify: `CHANGELOG.md` (`[Unreleased]` → `### Fixed`)

**Interfaces:**
- Consumes: nothing new. Pure documentation — no code.

- [ ] **Step 1: Write the doc edits**

`docs/commands/commits.md` — after the existing cmod description (line ~136), add:

```markdown
**Safety guard:** `cmod` refuses a **content-null amend** — an amend with
nothing staged and no message change (`--no-edit`) — with exit 3, because it
would silently rewrite HEAD's hash (same tree, same message). Stage changes
first (`hug a <files>`) or pass `-m` to change the message. To deliberately
re-hash/re-date HEAD, re-run with `-f`.
```

Same block in the cmoda section, wording "nothing staged or modified".

`git-config/lib/python/articles/agents.md` — after line 169 (`hug cmod --no-edit` bullet), add:

```markdown
- **Safety guard:** `cmod`/`cmoda` refuse content-null amends (exit 3) — nothing staged (cmod) / no tracked changes (cmoda) with `--no-edit`. Stage or pass `-m`; `-f` only for a deliberate re-hash/re-date.
```

`docs/skills/hug-workflow/SKILL.md` — after the CRITICAL block (line 26), add:

```markdown
- **Safety guard:** `cmod`/`cmoda` refuse content-null amends (exit 3) — stage files first or pass `-m`; `-f` only for a deliberate re-hash/re-date.
```

`README.md` line 477 — replace `hug cmod [-m msg]     # Commit: MODify (Amend last commit with staged changes)` with:

```text
hug cmod [-m msg]     # Commit: MODify (Amend last commit with staged changes — refuses no-op amends without -f)
```

`CHANGELOG.md` — under `## [Unreleased]`, add:

```markdown
### Fixed

- **`cmod`/`cmoda` refuse content-null amends** — `cmod --no-edit` with nothing staged (or `cmoda` in a clean tree) now exits 3 instead of silently rewriting HEAD's hash (same tree, same message) and printing the misleading "Amending last commit with staged changes" line. Stage changes or pass `-m`; `-f` only for a deliberate re-hash/re-date. `-y` does NOT bypass (semantic guard, not confirmation) (elifarley/hug-scm#263).
```

- [ ] **Step 2: Verify docs build + quality corpus**

Run: `make docs-build`
Run: `make test-lib-py TEST_FILTER=test_quality_corpus`
Expected: docs build clean; quality corpus passes.

- [ ] **Step 3: Sanitize**

Run: `make sanitize-check`
Expected: clean.

- [ ] **Step 4: Commit**

```bash
hug a docs/commands/commits.md git-config/lib/python/articles/agents.md docs/skills/hug-workflow/SKILL.md README.md CHANGELOG.md
hug c -F - <<'EOF'
docs(amend-guard): document the exit-3 refusal and -f hatch across the perimeter (#263)

[your WHY narrative — load the commit-message skill]
EOF
```

---

### Task 5: Full-suite verification

**Files:**
- None — verification only.

- [ ] **Step 1: Run the full test suite**

Run: `make test`
Expected: All tests pass (2402 unit + 738 lib + 957 python, or higher with the new tests).

- [ ] **Step 2: Run sanitize + docs**

Run: `make sanitize-check`
Run: `make docs-build`
Expected: both clean.

- [ ] **Step 3: Commit any fix-ups** (only if the full suite surfaced a fix — else skip)

```bash
hug a <fixed-files>
hug c -F - <<'EOF'
test(amend-guard): fix <what> after full-suite run (#263)
EOF
```

---

## Self-Review

**1. Spec coverage:**
- §1 trigger semantics (content-null + keep-message + candidate + no-force) → Task 1 `guard_content_null_amend` + `amend_args_message_intent`; decision table rows → Task 2/3 tests (tests 1-22 map 1:1).
- §1 content-expanding re-mode (`-a`/`-p`/`-i` → tracked) → Task 1 content-model picker + Task 2 test "`-a` re-mode".
- §1 pathspec exception (bare + `--`) → Task 1 paths branch + Task 2 tests (pathspec/bare path).
- §1 fail-open (rc>1) → Task 1 test "fail-open on corrupt index".
- §1 same-second caveat → Global Constraints forced `GIT_COMMITTER_DATE` in churn tests.
- §2 contracts (bare-call WHY, `_amend_content_null`, candidate computation) → Task 1 implementation.
- §3 refusal message + honest info line (5 states) → Task 1 refusal message; Task 2/3 info-line selection.
- §4 call sites (pre-parse idiom) → Task 2/3.
- §5 help text SAFETY GUARD → Task 2/3.
- §6 tests 1-22 behavioral + 23-25 library → Task 1 (lib) + Task 2/3 (behavioral), test 23's table verbatim in Task 1 Step 1.
- §7 doc sync (5 files) → Task 4.

**2. Placeholder scan:** None. Every step has concrete code/test content; no "TBD", "similar to", or bare "add tests" steps.

**3. Type consistency:** `_amend_content_null` global name used identically in Task 1 (producer), Task 2/3 (consumer). `guard_content_null_amend <staged|tracked> "$@" [-- <paths...>]` signature matches all call sites. `amend_args_message_intent` return codes (0/1/2) match the capture idiom in Task 2's info-line selection (`_msg_rc=0; fn "$@" || _msg_rc=$?` — bare 1/2 returns would kill the script under set -e).

**4. Smoke-verified (before handoff):** the plan's Step-3 function bodies were extracted verbatim and run under bash against a disposable repo. `amend_args_message_intent`: 14/14 probes correct (`--no-edit`→0, `-C HEAD`/`-c HEAD`/`-C @`/identical `-m`→0, `-m x`/`-C HEAD~1`/`-c X --no-edit`/`--fixup=HEAD`/`--fixup amend:HEAD`→1, bare/`-c X`/`-e`/`-m x -e`→2). `guard_content_null_amend`: content-null+KEEP → exit 3 "REFUSED"; content-null+CHANGE → rc 0 with `_amend_content_null=true`; staged content → rc 0 with `false`; `HUG_FORCE=true` → rc 0 with `true`. The plan's code compiles and behaves as specced.

**Execution note:** Task 5 exists as a checkpoint; Tasks 1-4 each end with their own sanitize + targeted-test runs, so the full suite should be green at each commit boundary.
