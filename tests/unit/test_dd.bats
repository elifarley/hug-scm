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

# Set up a git-command shim that logs difftool invocations to GIT_SHIM_LOG.
# The shim is a `git` executable placed at the front of PATH.
# Every `git difftool …` call writes its argv to GIT_SHIM_LOG (one arg per line)
# then exits 0 (success, simulating the tool closed normally).
# Every other `git …` call execs the real git transparently.
#
# WHY exec-the-real-git: the script under test also calls `git diff --quiet`,
# `git config`, etc. — those must still work or the guards won't function.
# WHY write-then-exit: avoids launching a real blocking GUI while still letting
# all git plumbing succeed.
#
# WHY resolve real git BEFORE creating the shim:
#   The shim must know the absolute path to the real git BEFORE it shadows it
#   on PATH. Computing it after would find the shim itself (infinite loop).
setup_git_shim() {
  local shim_dir
  shim_dir=$(mktemp -d)
  GIT_SHIM_DIR="$shim_dir"
  GIT_SHIM_LOG="$shim_dir/git-difftool.log"

  # Resolve the real git BEFORE prepending the shim to PATH.
  # This is critical: once the shim is on PATH, `command -v git` would resolve
  # to the shim itself, causing infinite recursion.
  local real_git
  real_git=$(command -v git)

  # Write the shim with the resolved absolute path embedded.
  # We use printf to embed the real_git path safely (no quotes in heredoc).
  cat > "$shim_dir/git" << SHIM
#!/usr/bin/env bash
if [[ "\${1:-}" == "difftool" ]]; then
  # Log all arguments (one per line) so tests can grep for them
  printf '%s\n' "\$@" >> "\${GIT_SHIM_LOG}"
  exit 0
fi
# For everything else, exec the real git using its absolute path
# (resolved before the shim was placed on PATH to avoid infinite recursion)
exec "${real_git}" "\$@"
SHIM
  chmod +x "$shim_dir/git"

  # Prepend shim dir so `git` resolves to our shim.
  # HUG_BIN remains first so hug commands still resolve correctly — the shim
  # only intercepts `git`, not `hug` or `git-dd`.
  export PATH="$shim_dir:$PATH"
  export GIT_SHIM_LOG GIT_SHIM_DIR
}

teardown_git_shim() {
  [[ -n "${GIT_SHIM_DIR:-}" ]] && rm -rf "$GIT_SHIM_DIR"
  unset GIT_SHIM_DIR GIT_SHIM_LOG
}

# Configure a fake difftool so git difftool does not launch any GUI.
# When the tool IS invoked by git, it writes the resolved LOCAL/REMOTE tmp
# paths to ARGV_LOG — so we can confirm the tool ran (or did NOT run).
configure_fake_difftool() {
  local repo_dir="${1:-$PWD}"
  local log_file="${BATS_TEST_TMPDIR}/difftool-invocations.log"
  ARGV_LOG="$log_file"
  export ARGV_LOG

  git -C "$repo_dir" config diff.tool fake
  # ARGV_LOG must be exported so the cmd subshell can see it
  git -C "$repo_dir" config difftool.fake.cmd \
    'printf "invoked\n" >> "$ARGV_LOG"'
  git -C "$repo_dir" config difftool.prompt false
}

# Verify that the git shim captured the given string in a difftool invocation.
assert_shim_logged() {
  local expected="$1"
  if [[ ! -f "${GIT_SHIM_LOG:-}" ]]; then
    fail "GIT_SHIM_LOG not found — shim not set up or difftool was never called"
  fi
  grep -qF -- "$expected" "$GIT_SHIM_LOG" \
    || fail "Expected '${expected}' in git difftool argv log. Actual log:\n$(cat "$GIT_SHIM_LOG")"
}

# Verify the shim did NOT log a difftool invocation at all.
assert_difftool_not_invoked() {
  if [[ -f "${GIT_SHIM_LOG:-}" ]] && [[ -s "$GIT_SHIM_LOG" ]]; then
    fail "git difftool was unexpectedly invoked. Log:\n$(cat "$GIT_SHIM_LOG")"
  fi
}

# Verify the fake difftool was NOT invoked (no-changes guard check).
assert_fake_tool_not_invoked() {
  if [[ -f "${ARGV_LOG:-}" ]] && grep -q "invoked" "$ARGV_LOG"; then
    fail "Fake difftool was unexpectedly invoked. Log:\n$(cat "$ARGV_LOG")"
  fi
}

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

# Test plan #4 — ref / range forwarded verbatim
@test "hug dd <ref>: forwards ref verbatim to git difftool" {
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"
  configure_fake_difftool "$TEST_REPO"
  setup_git_shim

  # HEAD~1 is a valid ref in a repo with 2+ commits (created by create_test_repo_with_history)
  run git-dd HEAD~1
  assert_success

  assert_shim_logged "HEAD~1"
  assert_shim_logged "--no-prompt"
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

  run git-dd --help
  assert_success

  # Must show usage with subcommands
  assert_output --partial "dd s"
  assert_output --partial "dd u"
  assert_output --partial "dd w"

  # Must have SEE ALSO referencing text-diff siblings
  assert_output --partial "SEE ALSO"
  [[ "$output" =~ ss|su|sw ]] \
    || fail "SEE ALSO should reference ss/su/sw"
}

@test "hug dd -h: shows help (short form)" {
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"

  run git-dd -h
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

  # Source the library directly
  # shellcheck source=/dev/null
  source "$PROJECT_ROOT/git-config/lib/hug-common"

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
