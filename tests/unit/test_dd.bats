#!/usr/bin/env bats
# Tests for `hug dd` — visual diff family (staged / unstaged / working / ref)
#
# WHY a fake-difftool harness:
#   git difftool launches an external blocking GUI — useless in CI and would
#   stall the test suite.  By configuring `diff.tool fake` and a fake cmd that
#   logs the git-resolved LOCAL/REMOTE tmp paths, the real git plumbing runs
#   end-to-end while the "tool" is a no-op write to ARGV_LOG.
#
# WHY we also use a PATH git shim (option B from the test plan):
#   The fake difftool only fires when git actually opens files, so for the
#   "no-changes" path (guard exits before launching) it won't run at all.
#   To assert WHICH flags were passed to `git difftool`, we inject a thin
#   `git` shim at the front of PATH that logs argv for `difftool` calls and
#   execs the real git for everything else.
#
# The two harnesses complement each other:
#   - git shim  → assert exact git command (presence of HEAD / --cached / --no-prompt)
#   - fake tool → assert the tool was NOT launched (no-changes guard)

load '../test_helper'

# --------------------------------------------------------------------------- #
# Helpers                                                                       #
# --------------------------------------------------------------------------- #
#
# The difftool test harness — the PATH `git` shim (setup_git_shim /
# teardown_git_shim), the fake-difftool config (configure_fake_difftool), and the
# argv assertions (assert_shim_logged, assert_shim_logged_exact,
# refute_shim_logged_exact, assert_difftool_not_invoked, assert_fake_tool_not_invoked)
# — lives in tests/test_helper.bash, shared with test_shv.bats (loaded above).
# See that file's "Visual-diff (difftool) test harness" section for the rationale
# (fake tool vs PATH shim, and why exact-line matching is required for endpoints).

# --------------------------------------------------------------------------- #
# Fixture helpers                                                               #
# --------------------------------------------------------------------------- #

# Create a repo with both staged and unstaged changes on SEPARATE files.
# This lets us verify dd s vs dd u vs dd w show distinct content.
create_repo_with_staged_and_unstaged() {
  local repo
  repo=$(create_test_repo)

  (
    cd "$repo"
    # staged: new file
    echo "staged content" > staged.txt
    git add staged.txt

    # unstaged: modify tracked file (README was created by create_test_repo)
    echo "unstaged content" >> README.md
  )

  echo "$repo"
}

# --------------------------------------------------------------------------- #
# Setup / Teardown                                                              #
# --------------------------------------------------------------------------- #

setup() {
  require_hug
}

teardown() {
  teardown_git_shim 2>/dev/null || true
  cleanup_test_repo
}

# --------------------------------------------------------------------------- #
# CATEGORY 1: Command-surface correctness (exact git flags)
# These use the PATH shim to assert exact git invocations.
# --------------------------------------------------------------------------- #

# Test plan #3 — regression guard for the combined-diff bug:
# dd w MUST pass HEAD so staged changes are not silently dropped.
@test "hug dd w: invokes git difftool with HEAD (regression guard for combined-diff bug)" {
  TEST_REPO=$(create_repo_with_staged_and_unstaged)
  cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  setup_git_shim

  run git-dd w
  # Exit is 0 (shim exits 0 simulating tool closed normally)
  assert_success

  assert_shim_logged "HEAD"
  # Must also contain --no-prompt (requirement #3)
  assert_shim_logged "--no-prompt"
  # Must NOT accidentally also pass --cached (that would be staged-only)
  if grep -qF -- "--cached" "$GIT_SHIM_LOG"; then
    fail "dd w must NOT pass --cached; it should use HEAD for net working diff"
  fi
}

# Test plan #1 — staged only uses --cached, not HEAD
@test "hug dd s: invokes git difftool with --cached (staged only)" {
  TEST_REPO=$(create_repo_with_staged_and_unstaged)
  cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  setup_git_shim

  run git-dd s
  assert_success

  assert_shim_logged "--cached"
  assert_shim_logged "--no-prompt"
  # Must NOT pass HEAD
  if grep -qxF "HEAD" "$GIT_SHIM_LOG"; then
    fail "dd s must NOT pass HEAD; it should use --cached for staged-only diff"
  fi
}

# Test plan #2 — unstaged uses neither --cached nor HEAD
@test "hug dd u: invokes git difftool with neither --cached nor HEAD (unstaged only)" {
  TEST_REPO=$(create_repo_with_staged_and_unstaged)
  cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  setup_git_shim

  run git-dd u
  assert_success

  assert_shim_logged "--no-prompt"
  # Must NOT pass HEAD or --cached
  if grep -qxF "HEAD" "$GIT_SHIM_LOG"; then
    fail "dd u must NOT pass HEAD"
  fi
  if grep -qF -- "--cached" "$GIT_SHIM_LOG"; then
    fail "dd u must NOT pass --cached"
  fi
}

# Test plan #14 — --no-prompt is always included
@test "hug dd: always passes --no-prompt to git difftool" {
  TEST_REPO=$(create_repo_with_staged_and_unstaged)
  cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  setup_git_shim

  # dd bare (= dd w) should include --no-prompt
  run git-dd
  assert_success
  assert_shim_logged "--no-prompt"
}

# Engine: a single committish shows its INTRODUCED diff = `<C>^1 <C>` (two
# explicit endpoint args), NOT the worktree-vs-ref forwarding of the old design.
@test "hug dd <committish>: emits two-arg introduced-diff endpoints (C^1 C)" {
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  setup_git_shim

  # HEAD~1 = "Add feature 1"; its introduced diff is HEAD~1^1..HEAD~1.
  run git-dd HEAD~1
  assert_success

  # Exact argv lines — substring matching would falsely pass on the OLD behavior
  # because "HEAD~1" is a substring of "HEAD~1^1" (Eng review E3).
  assert_shim_logged_exact "HEAD~1^1"
  assert_shim_logged_exact "HEAD~1"
  assert_shim_logged "--no-prompt"
  # The old design forwarded a single bare ref with no parent endpoint; ensure
  # we are NOT diffing against the worktree/bare HEAD.
  refute_shim_logged_exact "HEAD"
}

# Rejection guard: combining a ref/range with the interactive picker (bare --)
# is explicitly unsupported — the ref already scopes the diff, so there is no
# "current changes" pool to pick from. The command must fail with a useful message.
@test "hug dd <ref> --: interactive picker with a ref/range is rejected" {
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"

  # WHY no setup_git_shim: we expect early rejection before difftool is called.
  # WHY create_test_repo_with_history: we need HEAD~1 to be a valid ref.
  run git-dd HEAD~1 --
  assert_failure
  assert_output --partial "not supported"
}

# Test plan #8 — path scoping: dd w -- <file> → argv ends HEAD -- <file>
@test "hug dd w -- <file>: passes path scope with single -- boundary" {
  TEST_REPO=$(create_repo_with_staged_and_unstaged)
  cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  setup_git_shim

  run git-dd w -- README.md
  assert_success

  assert_shim_logged "HEAD"
  assert_shim_logged "--"
  assert_shim_logged "README.md"
  # Verify single -- (no double-dash -- -- in the log)
  local double_dash_count
  double_dash_count=$(grep -cxF -- "--" "$GIT_SHIM_LOG" || true)
  if [[ "$double_dash_count" -gt 1 ]]; then
    fail "Expected single -- in difftool argv but found $double_dash_count. Log:\n$(cat "$GIT_SHIM_LOG")"
  fi
}

# Test plan #9 — pathspecs forwarded with a single -- boundary
@test "hug dd s -- <file>: path scope works for staged mode" {
  TEST_REPO=$(create_repo_with_staged_and_unstaged)
  cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  setup_git_shim

  run git-dd s -- staged.txt
  assert_success

  assert_shim_logged "--cached"
  assert_shim_logged "--"
  assert_shim_logged "staged.txt"
}

# --------------------------------------------------------------------------- #
# CATEGORY 2: No-changes guard (test plan #6)
# Each subcommand must exit 0 + print message + NOT launch the tool.
# --------------------------------------------------------------------------- #

@test "hug dd s: no staged changes → prints message and does NOT launch difftool" {
  # create_test_repo gives us a clean committed repo (no staged changes)
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"

  run git-dd s
  assert_success
  assert_output --partial "No staged changes"
  assert_fake_tool_not_invoked
}

@test "hug dd u: no unstaged changes → prints message and does NOT launch difftool" {
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"

  run git-dd u
  assert_success
  assert_output --partial "No unstaged changes"
  assert_fake_tool_not_invoked
}

@test "hug dd w: no changes → prints message and does NOT launch difftool" {
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"

  run git-dd
  assert_success
  assert_output --partial "No changes"
  assert_fake_tool_not_invoked
}

# --------------------------------------------------------------------------- #
# CATEGORY 3: Non-TTY guard (test plan #7)
# When stdout is not a TTY the command must refuse and exit non-zero.
#
# WHY we must unset HUG_TEST_MODE:
#   tests/test_helper.bash exports HUG_TEST_MODE=true globally so the TTY
#   guard is skipped for all other tests (they need to exercise difftool
#   logic without a real terminal). These three tests specifically exercise
#   the TTY guard itself, so they must unset HUG_TEST_MODE to let the guard
#   fire. BATS `run` always captures stdout → not a TTY → guard should fire.
# --------------------------------------------------------------------------- #

@test "hug dd w: refuses with error when stdout is not a TTY (piped/CI)" {
  TEST_REPO=$(create_repo_with_staged_and_unstaged)
  cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"

  # WHY HUG_TEST_MODE="" (unset): test_helper exports HUG_TEST_MODE=true globally,
  # which bypasses the TTY guard. We explicitly clear it here to let the guard fire.
  # WHY HUG_DISABLE_GUM=true: prevents gum from trying to open /dev/tty for output,
  # which would produce an unrelated error message and obscure the actual test.
  HUG_TEST_MODE="" HUG_DISABLE_GUM=true run git-dd w
  assert_failure

  # Error must go to stderr (captured in $output by BATS with combined stderr).
  # We check for a useful error keyword, not the exact phrasing.
  assert_output --partial "TTY"
  assert_fake_tool_not_invoked
}

@test "hug dd s: refuses with error when stdout is not a TTY" {
  TEST_REPO=$(create_repo_with_staged_and_unstaged)
  cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"

  HUG_TEST_MODE="" HUG_DISABLE_GUM=true run git-dd s
  assert_failure
  assert_output --partial "TTY"
}

@test "hug dd u: refuses with error when stdout is not a TTY" {
  TEST_REPO=$(create_repo_with_staged_and_unstaged)
  cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"

  HUG_TEST_MODE="" HUG_DISABLE_GUM=true run git-dd u
  assert_failure
  assert_output --partial "TTY"
}

# --------------------------------------------------------------------------- #
# CATEGORY 4: Unconfigured difftool (test plan #13)
# When neither diff.tool nor any difftool.<t>.cmd is set, print a
# problem→cause→fix error and exit non-zero (never fall through to vimdiff).
# --------------------------------------------------------------------------- #

@test "hug dd: exits with friendly error when no difftool is configured" {
  TEST_REPO=$(create_repo_with_staged_and_unstaged)
  cd "$TEST_REPO"
  # Intentionally do NOT call configure_fake_difftool

  # Explicitly unset diff.tool in the local repo config so the global kitty
  # config (or any user-level config) does not satisfy the preflight check.
  # We use `git config --local diff.tool ""` then remove it to ensure the local
  # scope has no value, forcing the system to fall through to no configuration.
  #
  # WHY we also need GIT_CONFIG_GLOBAL=/dev/null:
  #   Even if diff.tool is absent in the local config, git config reads the
  #   global (~/.gitconfig) and system configs by default. A user with kitty
  #   configured globally would pass the preflight silently. Setting
  #   GIT_CONFIG_GLOBAL to /dev/null (which is empty) prevents that inheritance.
  #
  # WHY HUG_TEST_MODE=true: bypass the non-TTY guard so we reach the preflight.
  # WHY HUG_DISABLE_GUM=true: prevent gum from trying /dev/tty in the test env.
  GIT_CONFIG_GLOBAL=/dev/null HUG_TEST_MODE=true HUG_DISABLE_GUM=true run git-dd w
  assert_failure

  # The error message should explain the problem and how to fix it
  [[ "$output" =~ [Dd]ifftool || "$output" =~ [Dd]iff[[:space:]]tool ]] \
    || fail "Expected error message about difftool configuration. Got: $output"
}

# --------------------------------------------------------------------------- #
# CATEGORY 5: Strict-mode safety (test plan #12)
# A non-zero difftool exit (user cancels, tool missing) must NOT crash the
# script under set -euo pipefail.
# --------------------------------------------------------------------------- #

@test "hug dd: does not crash when difftool exits non-zero (user cancel simulation)" {
  TEST_REPO=$(create_repo_with_staged_and_unstaged)
  cd "$TEST_REPO"

  # Configure a difftool that always exits 1 (simulates user cancel / tool error)
  git config diff.tool cancel-sim
  git config difftool.cancel-sim.cmd 'exit 1'
  git config difftool.prompt false

  # Run via HUG_TEST_MODE to skip non-TTY guard
  HUG_TEST_MODE=true run git-dd w
  # The script must exit cleanly (0) — not crash under set -e
  # Design decision: non-zero difftool exit is treated as "user cancelled",
  # which is a normal operation (not a script failure).
  assert_success
}

# --------------------------------------------------------------------------- #
# CATEGORY 6: Help output (test plan #15)
# --------------------------------------------------------------------------- #

@test "hug dd --help: shows usage with s/u/w subcommands and SEE ALSO" {
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"

  # --help must work in ANY environment: non-TTY (HUG_TEST_MODE="" keeps the TTY
  # guard live) AND with no difftool configured (GIT_CONFIG_GLOBAL=/dev/null).
  # Help is documentation, not a tool launch, so it must precede BOTH guards.
  # Regression guard: the TTY/preflight guards previously ran before --help,
  # so `hug dd --help | less` failed with "requires a TTY".
  HUG_TEST_MODE="" GIT_CONFIG_GLOBAL=/dev/null run git-dd --help
  assert_success

  # Must show usage with subcommands
  assert_output --partial "dd s"
  assert_output --partial "dd u"
  assert_output --partial "dd w"

  # Must explain the net-vs-split semantics (the key conceptual caveat)
  assert_output --partial "NET vs SPLIT"

  # Must have SEE ALSO referencing text-diff siblings
  assert_output --partial "SEE ALSO"
  [[ "$output" =~ ss|su|sw ]] \
    || fail "SEE ALSO should reference ss/su/sw"
}

@test "hug dd -h: shows help (short form, works without TTY or difftool)" {
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"

  HUG_TEST_MODE="" GIT_CONFIG_GLOBAL=/dev/null run git-dd -h
  assert_success
  assert_output --partial "dd s"
}

# --------------------------------------------------------------------------- #
# CATEGORY 7: Bare `dd` defaults to working (= dd w) — test plan taste T2
# --------------------------------------------------------------------------- #

@test "hug dd (bare): defaults to working mode — equivalent to dd w" {
  TEST_REPO=$(create_repo_with_staged_and_unstaged)
  cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  setup_git_shim

  run git-dd
  assert_success

  # Bare dd must pass HEAD (working / net diff), not --cached (staged-only)
  assert_shim_logged "HEAD"
  if grep -qF -- "--cached" "$GIT_SHIM_LOG"; then
    fail "bare 'dd' must not pass --cached — it defaults to working mode (HEAD)"
  fi
}

# --------------------------------------------------------------------------- #
# CATEGORY 8: diff_has_working_changes — new library function (design req)
# Added to hug-git-diff beside the existing staged/unstaged helpers.
# --------------------------------------------------------------------------- #

@test "hug-git-diff: diff_has_working_changes returns true when HEAD differs from worktree" {
  TEST_REPO=$(create_repo_with_staged_and_unstaged)
  cd "$TEST_REPO"

  # WHY source hug-common (not hug-git-diff directly): hug-common is the umbrella
  # loader that chains into hug-git-diff (which defines diff_has_working_changes).
  # This mirrors real command scripts and gives diff_has_working_changes access to
  # all its transitive dependencies (colors, helpers, etc.).
  # NOTE: the source here runs in the BATS test body and has no effect on the
  # `run bash -c ...` subshell below — each subshell sources the library itself.
  # With both staged and unstaged changes, HEAD differs
  run bash -c "source '$PROJECT_ROOT/git-config/lib/hug-common' && cd '$TEST_REPO' && diff_has_working_changes && echo YES"
  assert_success
  assert_output --partial "YES"
}

@test "hug-git-diff: diff_has_working_changes returns false in clean repo" {
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"

  run bash -c "source '$PROJECT_ROOT/git-config/lib/hug-common' && cd '$TEST_REPO' && diff_has_working_changes && echo YES || echo NO"
  assert_success
  assert_output --partial "NO"
}

# --------------------------------------------------------------------------- #
# CATEGORY 9: Interactive file picker (test plan #10 and #11)
# Triggered by a trailing bare '--' (same convention as _diff_cmd_setup).
# Tests verify:
#   #10: multi-file selection → exactly ONE difftool invocation with all files
#   #11: cancel / empty selection → "No files selected" message, no difftool
# --------------------------------------------------------------------------- #

# Test plan #10 — interactive picker: multi-file selection → single difftool call.
#
# WHY gum-mock + HUG_TEST_GUM_SELECTION_INDICES:
#   The real gum opens a TUI that blocks in CI. The gum-mock in tests/bin/
#   intercepts `gum filter` and returns the lines at the given 0-based indices.
#   We set indices "0,1" to select the first two listed files. This exercises
#   the "multi-file selection collapses into one batched invocation" contract
#   without launching a real TUI.
#
# WHY assert difftool called EXACTLY ONCE (via shim log line count):
#   The key invariant is ONE tool window for all selected files, not one window
#   per file. We count lines in the shim log: each difftool invocation writes
#   its argv (one arg per line). The "difftool" token appears exactly once.
@test "hug dd --: interactive picker selects multiple files → difftool invoked exactly once with all files" {
  TEST_REPO=$(create_repo_with_staged_and_unstaged)
  cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  setup_git_shim
  setup_gum_mock
  # Select both available changed files (index 0 and 1 in the picker list)
  export HUG_TEST_GUM_SELECTION_INDICES="0,1"

  # 'hug dd --' defaults to working mode; '--' is the picker trigger
  run git-dd --
  assert_success

  teardown_gum_mock

  # The shim must have been called exactly once with "difftool" as arg[1].
  # WHY grep for the literal word "difftool": the shim logs every argv token
  # one per line; the first token for any difftool call is "difftool".
  local difftool_call_count
  difftool_call_count=$(grep -cxF "difftool" "$GIT_SHIM_LOG" || true)
  if [[ "$difftool_call_count" -ne 1 ]]; then
    fail "Expected exactly 1 difftool invocation, got ${difftool_call_count}. Log:\n$(cat "$GIT_SHIM_LOG")"
  fi

  # Working mode (bare --) must pass HEAD
  assert_shim_logged "HEAD"
  assert_shim_logged "--no-prompt"
  # The -- separator must be present (pathspecs follow it)
  assert_shim_logged "--"

  # Assert the ACTUAL selected file names appear as pathspecs after --.
  # WHY this matters: counting the difftool call only proves ONE invocation
  # occurred; it does NOT prove the files were forwarded as pathspecs.
  # These assertions close the gap by verifying the shim log contains the
  # concrete file names that selection indices 0 and 1 map to:
  #   index 0 → staged.txt  (staged files are listed first by select_files_with_status)
  #   index 1 → README.md   (unstaged files follow staged in the same call)
  # The fixture create_repo_with_staged_and_unstaged creates these exact files.
  assert_shim_logged "staged.txt"
  assert_shim_logged "README.md"
}

# Test plan #10 (variant) — picker for staged mode: 'hug dd s --'
# Verifies that the mode flag (s) is honoured and the invocation uses --cached.
@test "hug dd s --: interactive picker for staged mode invokes difftool with --cached" {
  TEST_REPO=$(create_repo_with_staged_and_unstaged)
  cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  setup_git_shim
  setup_gum_mock
  # Select the first staged file (staged.txt)
  export HUG_TEST_GUM_SELECTION_INDICES="0"

  run git-dd s --
  assert_success

  teardown_gum_mock

  # Exactly one difftool call
  local difftool_call_count
  difftool_call_count=$(grep -cxF "difftool" "$GIT_SHIM_LOG" || true)
  if [[ "$difftool_call_count" -ne 1 ]]; then
    fail "Expected exactly 1 difftool invocation, got ${difftool_call_count}. Log:\n$(cat "$GIT_SHIM_LOG")"
  fi

  assert_shim_logged "--cached"
  assert_shim_logged "--no-prompt"
  assert_shim_logged "--"
}

# Test plan #11 — interactive picker: cancel / empty selection → no difftool.
#
# WHY HUG_TEST_GUM_INPUT_RETURN_CODE=1:
#   gum-mock exits 1 when this variable is set to 1, which simulates the user
#   pressing Escape or Ctrl-C to cancel the picker. select_files_with_status
#   propagates the non-zero exit, mapfile produces an empty array, and the
#   picker must print the cancellation message and exit 0 without calling git.
@test "hug dd --: empty/cancelled picker prints message and does NOT launch difftool" {
  TEST_REPO=$(create_repo_with_staged_and_unstaged)
  cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  setup_git_shim
  setup_gum_mock
  # Simulate user pressing Escape (gum exits 1 = cancel)
  export HUG_TEST_GUM_INPUT_RETURN_CODE=1

  run git-dd --
  assert_success

  teardown_gum_mock

  # Must print the cancellation message
  assert_output --partial "No files selected or cancelled"

  # difftool must NOT have been invoked
  assert_difftool_not_invoked
}

# --------------------------------------------------------------------------- #
# CATEGORY 10: Commit-diff engine — introduced-diff endpoints, N/-N, ranges,
# root + merge commits, exit-code discipline, pathspec x endpoint.
# `dd <committish|range|N>` shows a commit's INTRODUCED diff (commit vs first
# parent), NOT worktree-vs-ref. Endpoints are TWO explicit args; asserted EXACT.
# --------------------------------------------------------------------------- #

@test "hug dd HEAD: introduced diff of HEAD = HEAD^1 HEAD" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"; setup_git_shim
  run git-dd HEAD
  assert_success
  assert_shim_logged_exact "HEAD^1"
  assert_shim_logged_exact "HEAD"
}

@test "hug dd 0: N=0 resolves to HEAD → HEAD^1 HEAD" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"; setup_git_shim
  run git-dd 0
  assert_success
  assert_shim_logged_exact "HEAD^1"
  assert_shim_logged_exact "HEAD"
}

@test "hug dd N: N=1 resolves to HEAD~1 → HEAD~1^1 HEAD~1" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"; setup_git_shim
  run git-dd 1
  assert_success
  assert_shim_logged_exact "HEAD~1^1"
  assert_shim_logged_exact "HEAD~1"
}

@test "hug dd -N: -2 resolves to range HEAD~2..HEAD (single endpoint arg)" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"; setup_git_shim
  run git-dd -2
  assert_success
  assert_shim_logged_exact "HEAD~2..HEAD"
  # A range is ONE diff arg — there must be no synthesized parent endpoint.
  refute_shim_logged_exact "HEAD~2..HEAD^1"
}

@test "hug dd <range>: A..B passed through verbatim as a single endpoint" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"; setup_git_shim
  run git-dd HEAD~2..HEAD
  assert_success
  assert_shim_logged_exact "HEAD~2..HEAD"
}

# Root path: HEAD~2 is the README root (create_test_repo_with_history) and is NOT
# HEAD — proving root detection works for an ARBITRARY ref (is_root_commit
# <committish>), not just HEAD (Eng review E8).
@test "hug dd <root>: root commit diffs against the empty tree" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"; setup_git_shim
  local empty_tree; empty_tree=$(git hash-object -t tree /dev/null)
  run git-dd HEAD~2
  assert_success
  assert_shim_logged_exact "$empty_tree"
  assert_shim_logged_exact "HEAD~2"
}

# Merge commit → first-parent endpoints (m^1 m), built inline.
@test "hug dd <merge>: uses first-parent endpoints (m^1 m)" {
  TEST_REPO=$(create_test_repo); cd "$TEST_REPO"
  local def; def=$(git rev-parse --abbrev-ref HEAD)
  git checkout -q -b side
  echo side > side.txt; git add side.txt; git commit -q -m "side commit"
  git checkout -q "$def"
  echo main >> README.md; git add README.md; git commit -q -m "main commit"
  git merge -q --no-ff -m "merge side" side
  configure_fake_difftool "$TEST_REPO"; setup_git_shim
  run git-dd HEAD            # HEAD is the merge commit
  assert_success
  assert_shim_logged_exact "HEAD^1"
  assert_shim_logged_exact "HEAD"
}

@test "hug dd <empty-commit>: no introduced changes → message, no launch" {
  TEST_REPO=$(create_test_repo_with_empty_commit); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  run git-dd HEAD
  assert_success
  assert_output --partial "No changes introduced"
  assert_fake_tool_not_invoked
}

@test "hug dd A..A: empty range → message, no launch" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  run git-dd HEAD..HEAD
  assert_success
  assert_output --partial "No changes"
  assert_fake_tool_not_invoked
}

# Exit-code discipline (Eng review E1): an invalid ref must ERROR, never read as
# "No changes".
@test "hug dd <invalid-ref>: errors (does NOT report 'no changes')" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  run git-dd no-such-ref-xyz
  assert_failure
  refute_output --partial "No changes"
  assert_fake_tool_not_invoked
}

@test "hug dd --stat: a flag is rejected, not treated as a ref" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  run git-dd --stat
  assert_failure
  assert_output --partial "Unknown flag"
}

# Pathspec + endpoint: matching path → launch with endpoints + -- <file>.
@test "hug dd <committish> -- <file>: scopes the introduced diff to a path" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"; setup_git_shim
  # feature1.txt was added in HEAD~1; scope HEAD~1's diff to it.
  run git-dd HEAD~1 -- feature1.txt
  assert_success
  assert_shim_logged_exact "HEAD~1^1"
  assert_shim_logged_exact "--"
  assert_shim_logged_exact "feature1.txt"
}

# Non-matching pathspec → guard forwards the pathspec, sees no diff, no launch
# (proves pathspecs reach the no-changes guard — Eng review E5).
@test "hug dd <committish> -- <unmatched>: pathspec forwarded to guard → no launch" {
  TEST_REPO=$(create_test_repo_with_history); cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  # HEAD~1 introduced feature1.txt, not feature2.txt → empty scoped diff.
  run git-dd HEAD~1 -- feature2.txt
  assert_success
  assert_output --partial "No changes introduced"
  assert_fake_tool_not_invoked
}
