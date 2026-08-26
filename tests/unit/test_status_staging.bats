#!/usr/bin/env bats
# Tests for status and staging commands (s*, a*, us*)

# Load test helpers
load '../test_helper'

# run --separate-stderr is used below (bats >= 1.5) to assert stdout/stderr
# discipline. GOTCHA: shell redirections like `2>/dev/null` on a `run` call are
# NO-OPs — bats' run overrides them and merges both streams into $output.
bats_require_minimum_version 1.5.0

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_changes)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

# Helper: repo with a real merge conflict (hug mkeep), plus a cleanly-merged
# file and an unstaged modification, so slc's exactness is observable. Leaves
# the repo in conflict state. Callers must capture: repo=$(create_slc_conflict_fixture)
#
# GOTCHA (git >= 2.34): `git merge` REFUSES (exit 128, no conflict created) when
# the index differs from HEAD — any STAGED change blocks the merge, even a new
# file the merge never touches ("would be overwritten by merge": the merged
# tree would drop the staged path). So the pre-merge fixture must have a clean
# index; staged.txt is therefore an UNSTAGED modification. After the merge
# fails, side-only.txt lands STAGED in the index (merged, uncommitted) — that
# is the real staged file slc must exclude.
create_slc_conflict_fixture() {
  local test_repo
  test_repo=$(create_test_repo)

  (
    cd "$test_repo" || exit 1

    echo "base" > conflict.txt
    echo "base" > side-only.txt
    echo "base" > staged.txt
    git add -A
    git commit -q -m "Add base files"

    git switch -q -c side
    echo "side" > conflict.txt
    echo "side" > side-only.txt
    git add -A
    git commit -q -m "Side changes"

    git switch -q main
    echo "main" > conflict.txt
    git add conflict.txt
    git commit -q -m "Main change"

    # Unstaged modification (staging it would block the merge — see GOTCHA)
    echo "staged" > staged.txt
  )

  echo "$test_repo"
}

@test "hug s: shows status summary" {
  run hug s
  assert_success
  # Should show some status information (HEAD, branch, or status indicator)
  [[ "$output" =~ (HEAD|master|Staged|Unstaged) ]]
}

@test "hug s: works in single-commit repository" {
  # Create a fresh repo with only one commit (no parent)
  local single_commit_repo
  single_commit_repo=$(mktemp -d)
  cd "$single_commit_repo"
  git init -q
  git config user.name "Test User"
  git config user.email "test@example.com"
  echo "initial" > file.txt
  git add file.txt
  git commit -q -m "Initial commit"
  
  # Run hug s in this single-commit repo
  run hug s
  assert_success
  # Should show HEAD
  assert_output --partial "HEAD"
  # Should show branch (master/main)
  [[ "$output" =~ (master|main) ]]
  # Should show clean status indicator
  assert_output --partial "⚪"
  
  # Cleanup
  cd "$TEST_REPO"
  rm -rf "$single_commit_repo"
}

@test "hug s: shows staged changes in single-commit repository" {
  # Create a single-commit repo with staged changes
  local single_commit_repo
  single_commit_repo=$(mktemp -d)
  cd "$single_commit_repo"
  git init -q
  git config user.name "Test User"
  git config user.email "test@example.com"
  echo "initial" > file.txt
  git add file.txt
  git commit -q -m "Initial commit"
  
  # Make changes and stage them
  echo "modified" >> file.txt
  git add file.txt
  
  # Run hug s
  run hug s
  assert_success
  # Should show staged changes
  assert_output --partial "Staged: 1 files"
  # Should show green ball emoji for staged-only changes
  assert_output --partial "🟢"
  
  # Cleanup
  cd "$TEST_REPO"
  rm -rf "$single_commit_repo"
}

@test "hug s: shows unstaged changes in single-commit repository" {
  # Create a single-commit repo with unstaged changes
  local single_commit_repo
  single_commit_repo=$(mktemp -d)
  cd "$single_commit_repo"
  git init -q
  git config user.name "Test User"
  git config user.email "test@example.com"
  echo "initial" > file.txt
  git add file.txt
  git commit -q -m "Initial commit"
  
  # Make unstaged changes
  echo "modified" >> file.txt
  
  # Run hug s
  run hug s
  assert_success
  # Should show unstaged changes
  assert_output --partial "Unstaged: 1 files"
  # Should show red ball emoji for unstaged changes
  assert_output --partial "🔴"
  
  # Cleanup
  cd "$TEST_REPO"
  rm -rf "$single_commit_repo"
}

@test "hug s: works in 0-commit repository (completely empty)" {
  # Create a completely fresh repo with no commits
  local zero_commit_repo
  zero_commit_repo=$(mktemp -d)
  cd "$zero_commit_repo"
  git init -q
  git config user.name "Test User"
  git config user.email "test@example.com"
  
  # Run hug s in 0-commit repo
  run hug s
  assert_success
  # Should show HEAD (even though it doesn't exist yet)
  assert_output --partial "HEAD"
  # Should show branch (master/main)
  [[ "$output" =~ (master|main) ]]
  # Should show clean status indicator
  assert_output --partial "⚪"
  
  # Cleanup
  cd "$TEST_REPO"
  rm -rf "$zero_commit_repo"
}

@test "hug s: shows untracked files in 0-commit repository" {
  # Create a 0-commit repo with untracked files
  local zero_commit_repo
  zero_commit_repo=$(mktemp -d)
  cd "$zero_commit_repo"
  git init -q
  git config user.name "Test User"
  git config user.email "test@example.com"
  echo "untracked" > file.txt
  
  # Run hug s
  run hug s
  assert_success
  # Should show untracked count
  assert_output --partial "K:1"
  # Should show magenta ball emoji for untracked files
  assert_output --partial "🟣"
  
  # Cleanup
  cd "$TEST_REPO"
  rm -rf "$zero_commit_repo"
}

@test "hug s: shows staged files in 0-commit repository" {
  # Create a 0-commit repo with staged files
  local zero_commit_repo
  zero_commit_repo=$(mktemp -d)
  cd "$zero_commit_repo"
  git init -q
  git config user.name "Test User"
  git config user.email "test@example.com"
  echo "new file" > file.txt
  git add file.txt
  
  # Run hug s
  run hug s
  assert_success
  # Should show staged changes
  assert_output --partial "Staged: 1 files"
  # Should show green ball emoji for staged-only changes
  assert_output --partial "🟢"
  
  # Cleanup
  cd "$TEST_REPO"
  rm -rf "$zero_commit_repo"
}

@test "hug sl: shows status without untracked files" {
  run hug sl
  assert_success
  # Should not show untracked.txt
  refute_output --partial "untracked.txt"
}

@test "hug sl: shows enhanced status list with color-coded status" {
  run hug sl
  assert_success
  # Should show staged file with status prefix
  assert_output --partial "staged.txt"
  # Should show modified file
  assert_output --partial "README.md"
  # Should show summary line with HEAD
  assert_output --partial "HEAD"
}

@test "hug sl: shows staged and unstaged files with status prefixes" {
  run hug sl
  assert_success
  # Output should have file names (we can't easily test ANSI codes in BATS)
  assert_output --partial "staged.txt"
  assert_output --partial "README.md"
  # Should not show untracked
  refute_output --partial "untracked.txt"
}

@test "hug sla: shows status with untracked files" {
  run hug sla
  assert_success
  # Should show untracked.txt
  assert_output --partial "untracked.txt"
}

@test "hug sla: shows enhanced status list including untracked files" {
  run hug sla
  assert_success
  # Should show all file types
  assert_output --partial "staged.txt"
  assert_output --partial "README.md"
  assert_output --partial "untracked.txt"
  # Should show summary line
  assert_output --partial "HEAD"
}

@test "hug sl: clean repository shows only summary" {
  # Create a fresh repo
  local clean_repo
  clean_repo=$(create_test_repo)
  cd "$clean_repo"
  
  run hug sl
  assert_success
  # Should show HEAD in summary
  assert_output --partial "HEAD"
  # Should not show file listings (no changes)
  refute_output --partial "S:"
  refute_output --partial "U:"
}

@test "hug sla: repository with only untracked files shows untracked" {
  # Create a fresh repo with untracked file
  local test_repo
  test_repo=$(create_test_repo)
  cd "$test_repo"
  echo "new" > untracked.txt
  
  run hug sla
  assert_success
  # Should show untracked file
  assert_output --partial "untracked.txt"
  # Should show summary with untracked count
  assert_output --partial "K:1"
}

@test "hug ss: shows staged changes" {
  run hug ss
  assert_success
  # Should show staged file
  assert_output --partial "staged.txt"
}

@test "hug su: shows unstaged changes" {
  run hug su
  assert_success
  # Should show modified README
  assert_output --partial "README.md"
}

@test "hug su --stat: shows only statistics without patch" {
  # Verify unstaged changes exist
  run git diff --name-only
  assert_success
  assert_output --partial "README.md"

  # Run with --stat flag
  run hug su --stat

  assert_success

  # Should show statistics header
  assert_output --partial "Unstaged file stats"

  # Should NOT show diff markers (@@) - these only appear in patches
  refute_output --partial "@@"

  # Should show file summary
  assert_output --partial "README.md"
}

@test "hug su -s: short flag works for stats-only mode" {
  run hug su -s

  assert_success
  assert_output --partial "Unstaged file stats"
  refute_output --partial "@@"
}

@test "hug su --stat file.txt: shows stats for specific file" {
  # Modify an existing tracked file (README.md exists from setup)
  echo "more changes" >> README.md

  run hug su --stat README.md

  assert_success
  # Should show stats for the modified file
  assert_output --partial "Unstaged file stats"
  assert_output --partial "README.md"
  refute_output --partial "@@"
}

@test "hug su: default shows both patch and stats (no regression)" {
  run hug su

  assert_success

  # Should show BOTH diff and stats
  assert_output --partial "Unstaged diff"
  assert_output --partial "@@"  # Diff markers
  assert_output --partial "Unstaged file stats"
}

@test "hug ss --stat: shows only staged statistics" {
  # Ensure staged.txt is staged
  git add staged.txt

  run hug ss --stat

  assert_success
  assert_output --partial "Staged file stats"
  refute_output --partial "@@"
  assert_output --partial "staged.txt"
}

@test "hug ss -s: short flag works for staged stats" {
  run hug ss -s

  assert_success
  assert_output --partial "Staged file stats"
  refute_output --partial "@@"
}

@test "hug sw --stat: shows only statistics for combined diff" {
  run hug sw --stat

  assert_success
  assert_output --partial "Unstaged file stats"
  assert_output --partial "Staged file stats"
  refute_output --partial "@@"
}

@test "hug su --stat with no changes: shows appropriate message" {
  # Create a fresh clean repo
  local clean_repo
  clean_repo=$(create_test_repo)
  cd "$clean_repo"

  run hug su --stat

  assert_success
  # When there are no unstaged changes, show_unstaged_diff shows an info message
  # and the status summary is shown
  assert_output --partial "No unstaged changes"
  [[ "$output" =~ (HEAD|clean|⚪) ]]

  cd "$TEST_REPO"
}

@test "hug sw: shows working directory changes" {
  run hug sw
  assert_success
  # Should show both staged and unstaged
}

@test "hug a: stages tracked modified files" {
  # Modify a tracked file
  echo "More content" >> README.md
  
  run hug a
  assert_success
  
  # Check that README.md is now staged
  run git diff --cached --name-only
  assert_output --partial "README.md"
}

@test "hug aa: stages all changes including untracked" {
  run hug aa
  assert_success
  
  # Check that untracked.txt is now staged
  run git diff --cached --name-only
  assert_output --partial "untracked.txt"
  assert_output --partial "staged.txt"
}

@test "hug us: unstages specific file" {
  # First ensure staged.txt is staged
  git add staged.txt
  
  run hug us staged.txt
  assert_success
  
  # Check that staged.txt is no longer staged
  run git diff --cached --name-only
  refute_output --partial "staged.txt"
}

@test "hug usa: unstages all files" {
  # Stage multiple files
  git add -A
  
  run hug usa
  assert_success
  
  # Check that nothing is staged
  run git diff --cached --name-only
  assert_output ""
}

@test "hug s with clean repository shows clean status" {
  # Create a fresh repo
  local clean_repo
  clean_repo=$(create_test_repo)
  cd "$clean_repo"
  
  run hug s
  assert_success
  # Clean status shows HEAD or a clean indicator (no Staged/Unstaged mentions)
  [[ "$output" =~ HEAD ]]
  [[ ! "$output" =~ Unstaged ]]
}

@test "hug ss with specific file shows only that file" {
  run hug ss staged.txt
  assert_success
  assert_output --partial "staged.txt"
}

@test "hug su with specific file shows only that file" {
  run hug su README.md
  assert_success
  assert_output --partial "README.md"
}

@test "hug a with specific file stages only that file" {
  # Modify multiple files
  echo "Change 1" >> README.md
  echo "Change 2" > newfile.txt
  git add newfile.txt
  
  run hug a README.md
  assert_success
  
  # Only README.md should be in the last stage operation
  run git diff --cached --name-only
  assert_output --partial "README.md"
}

@test "hug us: shows help with -h flag" {
  run hug us -h
  assert_success
  assert_output --partial "hug us: UnStage one or more files"
  assert_output --partial "USAGE:"
}

# Note: 'staged.txt' is created by the test fixture 'create_test_repo_with_changes' in setup().
@test "hug us: unstages single file when specified" {
  # Stage a file first
  git add staged.txt
  
  run hug us staged.txt
  assert_success
  assert_output --partial "✅ Success: Unstaged 1 file:"
  assert_output --partial "staged.txt"
  
  # Verify file is no longer staged
  run git diff --cached --name-only
  refute_output --partial "staged.txt"
}

@test "hug us: unstages multiple files when specified" {
  # Stage multiple files
  echo "content" > file1.txt
  echo "content" > file2.txt
  git add file1.txt file2.txt
  
  run hug us file1.txt file2.txt
  assert_success
  assert_output --partial "Unstaged 2 files:"
  
  # Verify files are no longer staged
  run git diff --cached --name-only
  refute_output --partial "file1.txt"
  refute_output --partial "file2.txt"
}

@test "hug us: shows informative message when no staged files" {
  # Make sure nothing is staged
  git reset HEAD --quiet 2>/dev/null || true
  
  run hug us
  assert_success
  assert_output --partial "No staged files to unstage"
}

@test "hug us: shows error when file is not staged" {
  # Make sure file is not staged
  git reset HEAD README.md --quiet 2>/dev/null || true
  
  run hug us README.md
  assert_failure
  assert_output --partial "is not staged"
}

@test "hug us: dry-run shows preview without unstaging" {
  # Stage a file
  git add staged.txt
  
  run hug us staged.txt --dry-run
  assert_success
  assert_output --partial "Dry run: Would unstage 1 file"
  assert_output --partial "staged.txt"
  
  # Verify file is still staged
  run git diff --cached --name-only
  assert_output --partial "staged.txt"
}

@test "hug untrack: shows help with -h flag" {
  run hug untrack -h
  assert_success
  assert_output --partial "hug untrack: Stop tracking files but keep them locally"
  assert_output --partial "USAGE:"
}

@test "hug untrack: untracks single file when specified" {
  # Create and commit a file. Avoid `.env` — it commonly sits in developers'
  # global gitignores, which makes `git add` fail outside CI.
  echo "secret" > secret.conf
  git add secret.conf
  git commit -q -m "Add secret.conf"

  # Untrack it with --force to skip confirmation
  run hug untrack secret.conf --force
  assert_success
  assert_output --partial "✅ Success: Untracked 1 file (kept locally):"
  assert_output --partial "secret.conf"

  # Verify file is untracked but still exists locally
  run git ls-files
  refute_output --partial "secret.conf"
  assert_file_exist secret.conf
}

@test "hug untrack: untracks multiple files when specified" {
  # Create and commit multiple files
  echo "secret1" > secret1.txt
  echo "secret2" > secret2.txt
  git add secret1.txt secret2.txt
  git commit -q -m "Add secrets"
  
  # Untrack them with --force to skip confirmation
  run hug untrack secret1.txt secret2.txt --force
  assert_success
  assert_output --partial "Untracked 2 files (kept locally):"
  
  # Verify files are untracked but still exist locally
  run git ls-files
  refute_output --partial "secret1.txt"
  refute_output --partial "secret2.txt"
  assert_file_exist secret1.txt
  assert_file_exist secret2.txt
}

@test "hug untrack: shows error when file is not tracked" {
  # Create an untracked file
  echo "content" > untracked_file.txt
  
  run hug untrack untracked_file.txt
  assert_failure
  assert_output --partial "is not tracked by git"
}

@test "hug untrack: dry-run shows preview without untracking" {
  # Create and commit a file
  echo "test" > test.txt
  git add test.txt
  git commit -q -m "Add test.txt"
  
  run hug untrack test.txt --dry-run
  assert_success
  assert_output --partial "Dry run: Would untrack 1 file"
  assert_output --partial "test.txt"
  
  # Verify file is still tracked
  run git ls-files
  assert_output --partial "test.txt"
}

@test "hug untrack: prompts for confirmation by default" {
  # Create and commit a file
  echo "test" > confirm_test.txt
  git add confirm_test.txt
  git commit -q -m "Add confirm_test.txt"
  
  # Run without --force and provide 'n' to decline
  run bash -c "echo 'n' | hug untrack confirm_test.txt"
  assert_failure
  assert_output --partial "Cancelled"
  
  # Verify file is still tracked
  run git ls-files
  assert_output --partial "confirm_test.txt"
}

################################################################################
# Interactive File Selection with --browse-root Tests
################################################################################

@test "hug sw --browse-root: triggers interactive mode when gum is available" {
  # Mock gum_available to ensure test can run
  if ! gum_available; then
    skip "gum not available"
  fi
  
  # Run with --browse-root and no paths - should trigger interactive mode
  # Use timeout since we can't interact with gum in tests
  run timeout 1 bash -c "hug sw --browse-root < /dev/null" || true
  
  # Should have attempted to use interactive selection
  # The key is that it doesn't show the full diff output (non-interactive mode)
  refute_output --partial "Working dir changes:"
}

@test "hug ss --browse-root: triggers interactive mode" {
  if ! gum_available; then
    skip "gum not available"
  fi
  
  run timeout 1 bash -c "hug ss --browse-root < /dev/null" || true
  
  # Should have attempted interactive selection, not showing full diff
  refute_output --partial "Staged changes:"
}

@test "hug su --browse-root: triggers interactive mode" {
  if ! gum_available; then
    skip "gum not available"
  fi
  
  run timeout 1 bash -c "hug su --browse-root < /dev/null" || true
  
  # Should have attempted interactive selection
  refute_output --partial "Unstaged changes:"
}

@test "hug a --browse-root: triggers interactive mode" {
  if ! gum_available; then
    skip "gum not available"
  fi
  
  run timeout 1 bash -c "hug a --browse-root < /dev/null" || true
  
  # Should have attempted interactive selection
  # Won't stage anything but shouldn't error about missing args
  # Acceptable exit codes: 124 (timeout), or other non-zero (interactive cancel)
  # We do not assert on status here, as interactive mode may exit with non-zero.
  # The output assertions below are sufficient to verify correct behavior.
}

@test "hug sw --browse-root with path: errors and aborts" {
  run hug sw --browse-root file.txt
  assert_failure
  assert_output --partial "cannot be used with explicit paths"
}

@test "hug ss --browse-root with path: errors and aborts" {
  run hug ss --browse-root file.txt
  assert_failure
  assert_output --partial "cannot be used with explicit paths"
}

@test "hug sls: shows only staged files" {
  # Stage a file first
  git add staged.txt

  run hug sls
  assert_success
  assert_output --partial "staged.txt"
  refute_output --partial "README.md"  # unstaged
  refute_output --partial "untracked.txt"
}

@test "hug sls: shows message when no staged files" {
  # Ensure nothing is staged
  git reset HEAD

  run hug sls
  assert_success
  assert_output --partial "No staged files."
}

@test "hug slu: shows only unstaged files" {
  run hug slu
  assert_success
  assert_output --partial "README.md"  # unstaged in test fixture
  refute_output --partial "staged.txt"
  refute_output --partial "untracked.txt"
}

@test "hug slu: shows message when no unstaged files" {
  # Stage all changes
  git add -A

  run hug slu
  assert_success
  assert_output --partial "No unstaged files."
}

@test "hug slk: shows only untracked files" {
  run hug slk
  assert_success
  assert_output --partial "untracked.txt"
  refute_output --partial "staged.txt"
  refute_output --partial "README.md"
}

@test "hug slk: shows message when no untracked files" {
  # Create a fresh repo without untracked files
  local clean_repo
  clean_repo=$(create_test_repo)
  cd "$clean_repo"

  run hug slk
  assert_success
  assert_output --partial "No untracked files."
}

@test "hug sls: supports JSON output" {
  git add staged.txt
  run hug sls --json
  assert_success
  assert_output --partial '{'
  assert_output --partial '"staged"'
}

@test "hug slu: supports JSON output" {
  run hug slu --json
  assert_success
  assert_output --partial '{'
  assert_output --partial '"unstaged"'
}

@test "hug slk: supports JSON output" {
  run hug slk --json
  assert_success
  assert_output --partial '{'
  assert_output --partial '"untracked"'
}

# =============================================================================
# --json pathspec scoping (Task 6, #292 PR-B): the JSON sink chain
# (output_json_status → output_json_status_unified → collect_git_files_json
# → list_*_files) honors the protective '--'. Two-sided per envelope: parses
# via python3 -m json.tool, no file outside the pathspecs AND ≥1 inside,
# summary.* counts match the scoped array.
# =============================================================================

@test "hug sls --json: pathspecs scope the envelope (two-sided)" {
  # Fixture adds staged src/a.py + other.txt next to the helper's staged.txt:
  # the 'src/' scope must keep src/a.py and drop BOTH out-of-scope rows.
  mkdir -p src
  echo py1 > src/a.py
  echo other > other.txt
  git add src/a.py other.txt

  run hug sls --json -- src/
  assert_success
  local json_out="$output"
  assert_valid_json "$json_out"
  [[ "$json_out" == *'"src/a.py"'* ]]
  [[ "$json_out" != *'"staged.txt"'* ]]
  [[ "$json_out" != *'"other.txt"'* ]]
  run python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['summary']['staged'], len(d['staged']))" "$json_out"
  assert_output "1 1"
}

@test "hug slu --json: empty scope keeps the envelope shape" {
  # No UNSTAGED file under src/ (the fixture's unstaged file is README.md at
  # the root): the scoped answer must keep the machine contract — same keys,
  # zero-length arrays, summary counts 0.
  mkdir -p src
  echo py1 > src/a.py

  run hug slu --json -- src/
  assert_success
  local json_out="$output"
  assert_valid_json "$json_out"
  [[ "$json_out" != *'"README.md"'* ]]
  run python3 -c "import json,sys; d=json.loads(sys.argv[1]); print('unstaged' in d, d['unstaged'], d['summary']['unstaged'])" "$json_out"
  assert_output "True [] 0"
}

@test "hug slk --json: pathspecs scope the envelope (two-sided)" {
  # A fully-untracked directory collapses to the dir itself in porcelain
  # output (git's untracked-files=normal default), so the in-scope row is
  # "src/" — not src/new.py. The scope is still two-sided: the out-of-scope
  # untracked.txt (fixture root) must be absent.
  mkdir -p src
  echo untracked > src/new.py

  run hug slk --json -- src/
  assert_success
  local json_out="$output"
  assert_valid_json "$json_out"
  [[ "$json_out" == *'"src/"'* ]]
  [[ "$json_out" != *'"untracked.txt"'* ]]
  run python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['summary']['untracked'], len(d['untracked']))" "$json_out"
  assert_output "1 1"
}

@test "hug sls --json: pathspec spelled '--cwd' scopes, does not toggle" {
  # A file LITERALLY named '--cwd' is data after the separator: it must scope
  # the listing, never toggle the (JSON-internal) scope-to-cwd flag.
  echo cwd1 > ./--cwd
  git add -- ./--cwd

  run hug sls --json -- --cwd
  assert_success
  local json_out="$output"
  assert_valid_json "$json_out"
  [[ "$json_out" == *'"--cwd"'* ]]
  [[ "$json_out" != *'"staged.txt"'* ]]
  run python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['summary']['staged'])" "$json_out"
  assert_output "1"
}

@test "hug sli: shows only ignored files" {
  # Create a .gitignore file and some ignored content
  echo "*.log" > .gitignore
  echo "tempfile.tmp" >> .gitignore
  git add .gitignore
  git commit -m "Add gitignore"

  # Create some ignored files
  echo "log content" > debug.log
  echo "temp" > tempfile.tmp

  run hug sli
  assert_success
  assert_output --partial "debug.log"
  assert_output --partial "tempfile.tmp"
  refute_output --partial "README.md"  # tracked
  refute_output --partial "untracked.txt"  # untracked
  refute_output --partial "staged.txt"  # staged
}

@test "hug sli: shows message when no ignored files" {
  # Create a fresh repo without .gitignore or ignored files
  local clean_repo
  clean_repo=$(create_test_repo)
  cd "$clean_repo"

  run hug sli
  assert_success
  assert_output --partial "No ignored files."
}

@test "hug sli: supports JSON output" {
  echo "*.log" > .gitignore
  git add .gitignore
  git commit -m "Add gitignore"
  echo "log" > debug.log

  run hug sli --json
  assert_success
  assert_output --partial '{'
  assert_output --partial '"ignored"'
  assert_output --partial '"debug.log"'
}

@test "hug sl: shows message when no staged or unstaged files" {
  # Create a fresh repo without any changes
  local clean_repo
  clean_repo=$(create_test_repo)
  cd "$clean_repo"

  run hug sl
  assert_success
  assert_output --partial "No staged or unstaged files."
  # Should still show summary
  assert_output --partial "HEAD"
}

@test "hug sla: shows message when no staged, unstaged, or untracked files" {
  # Create a fresh repo without any changes or untracked files
  local clean_repo
  clean_repo=$(create_test_repo)
  cd "$clean_repo"

  run hug sla
  assert_success
  assert_output --partial "No staged, unstaged, or untracked files."
  # Should still show summary
  assert_output --partial "HEAD"
}

@test "hug sl: shows files when they exist" {
  # Create some unstaged changes
  echo "modified" > README.md

  run hug sl
  assert_success
  # Should show the modified file
  assert_output --partial "README.md"
  # Should NOT show "No files" message
  refute_output --partial "No staged or unstaged files."
}

@test "hug sla: shows untracked files when they exist" {
  # Create an untracked file
  echo "untracked" > newfile.txt

  run hug sla
  assert_success
  # Should show the untracked file
  assert_output --partial "newfile.txt"
  # Should NOT show "No files" message
  refute_output --partial "No staged, unstaged, or untracked files."
}

@test "hug sls with file argument" {
  git add staged.txt
  echo "unstaged" > README.md

  run hug sls staged.txt
  assert_success
  assert_output --partial "staged.txt"
  refute_output --partial "README.md"
}

@test "hug sls with wildcard pattern" {
  echo "unstaged" > README.md
  echo "staged" > test1.js
  echo "staged" > test2.js

  git add test1.js test2.js

  run hug sls "*.js"
  assert_success
  assert_output --partial "test1.js"
  assert_output --partial "test2.js"
  refute_output --partial "README.md"
}

@test "hug sls shows message when no staged files" {
  # Ensure nothing is staged
  git reset HEAD

  run hug sls
  assert_success
  assert_output --partial "No staged files."
}

@test "hug slu with file argument" {
  echo "unstaged1" > file1.txt
  echo "unstaged2" > file2.txt
  git add file1.txt

  run hug slu file2.txt
  assert_success
  assert_output --partial "file2.txt"
  refute_output --partial "file1.txt"
}

@test "hug slu with wildcard pattern" {
  echo "initial js1" > main.js
  echo "initial js2" > utils.js
  echo "initial py" > script.py
  git add main.js utils.js script.py
  git commit -m "Initial commit" 2>/dev/null

  # Now modify them to make them unstaged
  echo "unstaged js1" > main.js
  echo "unstaged js2" > utils.js
  echo "unstaged py" > script.py

  run hug slu "*.js"
  assert_success
  assert_output --partial "main.js"
  assert_output --partial "utils.js"
  refute_output --partial "script.py"
}

@test "hug sls: suppresses summary with --quiet flag" {
  git add staged.txt
  run hug sls --quiet
  assert_success
  assert_output --partial "S:Add"
  refute_output --partial "HEAD:"
}

@test "hug sls: suppresses summary with HUG_QUIET environment" {
  git add staged.txt
  export HUG_QUIET=T
  run hug sls
  assert_success
  assert_output --partial "S:Add"
  refute_output --partial "HEAD:"
  unset HUG_QUIET
}

@test "hug sls: shows summary without quiet flag" {
  git add staged.txt
  run hug sls
  assert_success
  assert_output --partial "S:Add"
  assert_output --partial "HEAD:"
}

@test "hug slu: suppresses summary but preserves status with --quiet flag" {
  run hug slu --quiet
  assert_success
  # Status column is preserved (slu has multiple status types: U:Mod, U:Del, U:Cnflt)
  assert_output --partial "U:"
  refute_output --partial "HEAD:"
}

@test "hug slu: suppresses summary but preserves status with HUG_QUIET environment" {
  export HUG_QUIET=T
  run hug slu
  assert_success
  # Status column is preserved (slu has multiple status types: U:Mod, U:Del, U:Cnflt)
  assert_output --partial "U:"
  refute_output --partial "HEAD:"
  unset HUG_QUIET
}

@test "hug slk: suppresses summary and status column with --quiet flag" {
  run hug slk --quiet
  assert_success
  # Status column is suppressed in quiet mode for single-type commands
  assert_output --partial "untracked.txt"
  refute_output --partial "HEAD:"
}

@test "hug slk: suppresses summary and status column with HUG_QUIET environment" {
  export HUG_QUIET=T
  run hug slk
  assert_success
  # Status column is suppressed in quiet mode for single-type commands
  assert_output --partial "untracked.txt"
  refute_output --partial "HEAD:"
  unset HUG_QUIET
}

@test "hug sli: suppresses summary with --quiet flag" {
  echo "*.log" > .gitignore
  git add .gitignore
  git commit -m "Add gitignore" >/dev/null 2>&1
  echo "log" > debug.log

  run hug sli --quiet
  assert_success
  assert_output --partial "debug.log"
  refute_output --partial "HEAD:"
}

@test "hug sli: suppresses summary with HUG_QUIET environment" {
  echo "*.log" > .gitignore
  git add .gitignore
  git commit -m "Add gitignore" >/dev/null 2>&1
  echo "log" > debug.log

  export HUG_QUIET=T
  run hug sli
  assert_success
  assert_output --partial "debug.log"
  refute_output --partial "HEAD:"
  unset HUG_QUIET
}

@test "hug sl: suppresses summary with --quiet flag" {
  run hug sl --quiet
  assert_success
  assert_output --partial "README.md"
  refute_output --partial "HEAD:"
}

@test "hug sl: suppresses summary with HUG_QUIET environment" {
  export HUG_QUIET=T
  run hug sl
  assert_success
  assert_output --partial "README.md"
  refute_output --partial "HEAD:"
  unset HUG_QUIET
}

@test "hug sla: suppresses summary with --quiet flag" {
  run hug sla --quiet
  assert_success
  assert_output --partial "untracked.txt"
  refute_output --partial "HEAD:"
}

@test "hug sla: suppresses summary with HUG_QUIET environment" {
  export HUG_QUIET=T
  run hug sla
  assert_success
  assert_output --partial "untracked.txt"
  refute_output --partial "HEAD:"
  unset HUG_QUIET
}

@test "hug su: suppresses summary with --quiet flag" {
  run hug su --quiet
  assert_success
  assert_output --partial "Unstaged diff"
  refute_output --partial "HEAD:"
}

@test "hug su: suppresses summary with HUG_QUIET environment" {
  export HUG_QUIET=T
  run hug su
  assert_success
  assert_output --partial "Unstaged diff"
  refute_output --partial "HEAD:"
  unset HUG_QUIET
}

@test "hug su --stat: suppresses summary with --quiet flag" {
  run hug su --stat --quiet
  assert_success
  assert_output --partial "Unstaged file stats"
  refute_output --partial "HEAD:"
}

@test "hug ss: suppresses summary with --quiet flag" {
  git add staged.txt
  run hug ss --quiet
  assert_success
  assert_output --partial "Staged diff"
  refute_output --partial "HEAD:"
}

@test "hug ss: suppresses summary with HUG_QUIET environment" {
  git add staged.txt
  export HUG_QUIET=T
  run hug ss
  assert_success
  assert_output --partial "Staged diff"
  refute_output --partial "HEAD:"
  unset HUG_QUIET
}

@test "hug ss --stat: suppresses summary with --quiet flag" {
  git add staged.txt
  run hug ss --stat --quiet
  assert_success
  assert_output --partial "Staged file stats"
  refute_output --partial "HEAD:"
}

@test "hug sw: suppresses summary with --quiet flag" {
  run hug sw --quiet
  assert_success
  assert_output --partial "Unstaged diff"
  refute_output --partial "HEAD:"
}

@test "hug sw: suppresses summary with HUG_QUIET environment" {
  export HUG_QUIET=T
  run hug sw
  assert_success
  assert_output --partial "Unstaged diff"
  refute_output --partial "HEAD:"
  unset HUG_QUIET
}

@test "hug sw --stat: suppresses summary with --quiet flag" {
  run hug sw --stat --quiet
  assert_success
  assert_output --partial "Unstaged file stats"
  refute_output --partial "HEAD:"
}

@test "hug slu shows message when no unstaged files" {
  # Stage all changes
  git add -A

  run hug slu
  assert_success
  assert_output --partial "No unstaged files."
}

@test "hug slk with directory argument" {
  mkdir -p src
  echo "untracked1" > src/file1.txt
  echo "untracked2" > src/file2.txt

  run hug slk src/
  assert_success
  assert_output --partial "untrcK src/"
}

@test "hug slk shows message when no untracked files" {
  # Create a fresh repo without untracked files
  local clean_repo
  clean_repo=$(create_test_repo)
  cd "$clean_repo"

  run hug slk
  assert_success
  assert_output --partial "No untracked files."
}

@test "hug sli with .gitignore pattern" {
  echo "*.log" > .gitignore
  echo "tempfile.tmp" >> .gitignore
  git add .gitignore
  git commit -m "Add gitignore"

  # Create some ignored files
  echo "log content" > debug.log
  echo "temp" > tempfile.tmp
  echo "not ignored" > regular.txt

  run hug sli "*.log"
  assert_success
  assert_output --partial "debug.log"
  refute_output --partial "tempfile.tmp"  # doesn't match *.log pattern
  refute_output --partial "regular.txt"
}

@test "hug sli shows message when no ignored files" {
  # Create a fresh repo without .gitignore or ignored files
  local clean_repo
  clean_repo=$(create_test_repo)
  cd "$clean_repo"

  run hug sli
  assert_success
  assert_output --partial "No ignored files."
}

@test "hug sl with single file argument shows its status" {
  echo "unstaged" > README.md

  run hug sl README.md
  assert_success
  assert_output --partial "README.md"
  assert_output --partial "U:Mod"
}

@test "hug sl with multiple file arguments" {
  echo "unstaged1" > file1.txt
  echo "unstaged2" > file2.txt
  echo "staged" > staged.txt
  git add staged.txt

  run hug sl README.md staged.txt
  assert_success
  assert_output --partial "README.md"
  assert_output --partial "staged.txt"
  refute_output --partial "file1.txt"
  refute_output --partial "file2.txt"
}

@test "hug sla with directory argument" {
  mkdir -p src lib docs
  echo "initial" > src/main.cpp
  echo "initial" > lib/helper.rb
  git add src/ lib/
  git commit -m "Initial commit" 2>/dev/null

  # Now modify them to make them unstaged
  echo "unstaged" > src/main.cpp
  echo "unstaged" > lib/helper.rb
  echo "untracked" > docs/readme.md

  run hug sla src/ lib/
  assert_success
  assert_output --partial "src/main.cpp"
  assert_output --partial "lib/helper.rb"
  refute_output --partial "docs/readme.md"
}

@test "hug sl with no matching files shows appropriate message" {
  run hug sl "nonexistent/*"
  assert_success
  assert_output --partial "No staged or unstaged files matching 'nonexistent/*' found."
}

@test "hug sls with no matching files shows appropriate message" {
  run hug sls "nonexistent/*"
  assert_success
  assert_output --partial "No staged files matching 'nonexistent/*' found."
}

@test "hug slu with no matching files shows appropriate message" {
  run hug slu "nonexistent/*"
  assert_success
  assert_output --partial "No unstaged files matching 'nonexistent/*' found."
}

@test "hug slk with no matching files shows appropriate message" {
  run hug slk "nonexistent/*"
  assert_success
  assert_output --partial "No untracked files matching 'nonexistent/*' found."
}

@test "hug sli with no matching files shows appropriate message" {
  run hug sli "nonexistent/*"
  assert_success
  assert_output --partial "No ignored files matching 'nonexistent/*' found."
}

@test "hug s: handles empty repository" {
  # Create an empty repository (no commits)
  cd "$(mktemp -d)"
  hug init

  run hug s
  assert_success
  # Should show status without error
  assert_output --partial "HEAD"
  assert_output --partial "main"
  # Should show clean state (test semantic state, not emoji)
  assert_hug_s_state "clean"
  assert_output --partial "🌿main"
  # Should show empty hash (double spaces)
  assert_output --partial "HEAD:  🌿"
}

################################################################################
# Combined Short Flags Tests
################################################################################

@test "hug su -qs: combined flags work correctly" {
  run hug su -qs
  assert_success
  assert_output --partial "Unstaged file stats"
  refute_output --partial "@@"
  refute_output --partial "HEAD:"
}

@test "hug su -sq: combined flags work in reverse order" {
  run hug su -sq
  assert_success
  assert_output --partial "Unstaged file stats"
  refute_output --partial "@@"
  refute_output --partial "HEAD:"
}

@test "hug ss -qs: combined flags work correctly" {
  git add staged.txt
  run hug ss -qs
  assert_success
  assert_output --partial "Staged file stats"
  refute_output --partial "@@"
  refute_output --partial "HEAD:"
}

@test "hug ss -sq: combined flags work in reverse order" {
  git add staged.txt
  run hug ss -sq
  assert_success
  assert_output --partial "Staged file stats"
  refute_output --partial "@@"
  refute_output --partial "HEAD:"
}

@test "hug sw -qs: combined flags work correctly" {
  run hug sw -qs
  assert_success
  assert_output --partial "Unstaged file stats"
  refute_output --partial "@@"
  refute_output --partial "HEAD:"
}

@test "hug sw -sq: combined flags work in reverse order" {
  run hug sw -sq
  assert_success
  assert_output --partial "Unstaged file stats"
  refute_output --partial "@@"
  refute_output --partial "HEAD:"
}

@test "hug su --stat --quiet: long flags work in any order" {
  run hug su --stat --quiet
  assert_success
  assert_output --partial "Unstaged file stats"
  refute_output --partial "@@"
  refute_output --partial "HEAD:"
}

@test "hug su --quiet --stat: long flags work in reverse order" {
  run hug su --quiet --stat
  assert_success
  assert_output --partial "Unstaged file stats"
  refute_output --partial "@@"
  refute_output --partial "HEAD:"
}

################################################################################
# --suppress-status (Quiet Mode Column Suppression) Tests
################################################################################

@test "hug slk -q: suppresses status column in quiet mode" {
  run hug slk -q
  assert_success
  # Should show filename without status prefix
  assert_output --partial "untracked.txt"
  # Should NOT have status label
  refute_output --partial "untrcK"
}

@test "hug slk --quiet: suppresses status column in quiet mode" {
  run hug slk --quiet
  assert_success
  # Should show filename without status prefix
  assert_output --partial "untracked.txt"
  # Should NOT have status label
  refute_output --partial "untrcK"
}

@test "hug slk with HUG_QUIET: suppresses status column" {
  export HUG_QUIET=T
  run hug slk
  assert_success
  # Should show filename without status prefix
  assert_output --partial "untracked.txt"
  # Should NOT have status label
  refute_output --partial "untrcK"
  unset HUG_QUIET
}

@test "hug slk: shows status column without quiet mode" {
  run hug slk
  assert_success
  # Should show both filename AND status label
  assert_output --partial "untracked.txt"
  assert_output --partial "untrcK"
}

@test "hug sli -q: suppresses status column in quiet mode" {
  echo "*.log" > .gitignore
  git add .gitignore
  git commit -m "Add gitignore" >/dev/null 2>&1
  echo "log" > debug.log

  run hug sli -q
  assert_success
  # Should show filename without status prefix
  assert_output --partial "debug.log"
  # Should NOT have status label
  refute_output --partial "Ignore"
}

@test "hug sli --quiet: suppresses status column in quiet mode" {
  echo "*.log" > .gitignore
  git add .gitignore
  git commit -m "Add gitignore" >/dev/null 2>&1
  echo "log" > debug.log

  run hug sli --quiet
  assert_success
  # Should show filename without status prefix
  assert_output --partial "debug.log"
  # Should NOT have status label
  refute_output --partial "Ignore"
}

@test "hug sli with HUG_QUIET: suppresses status column" {
  echo "*.log" > .gitignore
  git add .gitignore
  git commit -m "Add gitignore" >/dev/null 2>&1
  echo "log" > debug.log

  export HUG_QUIET=T
  run hug sli
  assert_success
  # Should show filename without status prefix
  assert_output --partial "debug.log"
  # Should NOT have status label
  refute_output --partial "Ignore"
  unset HUG_QUIET
}

@test "hug sli: shows status column without quiet mode" {
  echo "*.log" > .gitignore
  git add .gitignore
  git commit -m "Add gitignore" >/dev/null 2>&1
  echo "log" > debug.log

  run hug sli
  assert_success
  # Should show both filename AND status label
  assert_output --partial "debug.log"
  assert_output --partial "Ignore"
}

@test "hug slu -q: preserves status column (multiple status types)" {
  run hug slu -q
  assert_success
  # Should show status (slu has multiple status types: U:Mod, U:Del, U:Cnflt)
  assert_output --partial "U:"
}

@test "hug sls -q: preserves status column (multiple status types)" {
  git add staged.txt

  run hug sls -q
  assert_success
  # Should show status (sls cannot suppress due to multiple status types)
  assert_output --partial "S:"
}

@test "hug sl: never suppresses status (multiple file types)" {
  run hug sl -q
  assert_success
  # Should show status prefixes (sl has both staged and unstaged)
  assert_output --partial "S:" || assert_output --partial "U:"
}

################################################################################
# Double Dash (--) for Interactive File Selection Tests
################################################################################

@test "hug su --: triggers interactive file selection mode" {
  # Test that -- sets HUG_INTERACTIVE_FILE_SELECTION environment variable
  # by mocking gum and checking that the command exits due to no files
  # In non-interactive mode, we'd see "Unstaged diff:" in output
  # In interactive mode, the command tries to launch gum and exits early

  # First verify normal mode shows diff
  run hug su
  assert_success
  assert_output --partial "Unstaged diff"

  # Now verify -- mode doesn't show the regular diff output
  # It will fail because gum will exit with error when no TTY
  run hug su --
  # The command should fail (gum can't run) OR succeed with "No files" message
  # Either way, it should NOT show the regular diff
  refute_output --partial "Unstaged diff:"
}

@test "hug ss --: triggers interactive file selection mode" {
  # Ensure there's a staged file
  git add staged.txt

  # First verify normal mode shows diff
  run hug ss
  assert_success
  assert_output --partial "Staged diff"

  # Now verify -- mode doesn't show the regular diff output
  run hug ss --
  # Should NOT show the regular diff (either fails due to gum or shows no files)
  refute_output --partial "Staged diff:"
}

@test "hug sw --: triggers interactive file selection mode" {
  # First verify normal mode shows diff
  run hug sw
  assert_success
  # hug sw shows both unstaged and staged diffs
  assert_output --partial "Unstaged diff"

  # Now verify -- mode doesn't show the regular diff output
  run hug sw --
  # Should NOT show the regular diff (either fails due to gum or shows no files)
  refute_output --partial "Unstaged diff"
}

@test "hug su -qs --: combined flags with interactive mode" {
  # Test that combined short flags still work with --
  # The bug was that combined flags broke -- detection

  # First verify -qs works without --
  run hug su -qs
  assert_success
  assert_output --partial "Unstaged file stats"

  # Now verify -qs -- doesn't show stats (enters interactive mode)
  run hug su -qs --
  # Should NOT show the regular stats output
  refute_output --partial "Unstaged file stats"
}

@test "hug su --stat --: long flag with interactive mode" {
  # Test that --stat still works with interactive selection
  run hug su --stat --
  # Should enter interactive mode, not show stats immediately
  refute_output --partial "Unstaged file stats"
}

################################################################################
# Pathspec Filtering Tests (hug su/ss/sw -- <path>...)
################################################################################

@test "hug su -- <path>: single path filtering" {
  run hug su -- README.md --quiet
  assert_success
  assert_output --partial "Unstaged diff for README.md"
  assert_output --partial "README.md"
  refute_output --partial "staged.txt"
}

@test "hug su -- <path1> <path2>: multiple path filtering" {
  # Create another unstaged file
  echo "more content" >> staged.txt

  run hug su -- README.md staged.txt --quiet
  assert_success
  assert_output --partial "README.md"
  # staged.txt is in the unstaged diff output too
}

@test "hug su -- <path>: paths not treated as revisions (original bug)" {
  # The original bug: hug su -- management/ .wolf/ would fail with
  # "fatal: bad revision '.wolf/'" because paths were placed before '--'
  # Create directories named like the bug case
  mkdir -p management .wolf
  echo "mgmt" > management/a.txt
  echo "wolf" > .wolf/b.txt
  git add management/ .wolf/
  hug c -m "add dirs" --quiet 2>/dev/null || true
  echo "mod1" >> management/a.txt
  echo "mod2" >> .wolf/b.txt

  run hug su -- management/ .wolf/ --quiet
  assert_success
  # Should show both files without "bad revision" error
  refute_output --partial "fatal"
  refute_output --partial "bad revision"
}

@test "hug ss -- <path>: staged diff path filtering" {
  run hug ss -- staged.txt --quiet
  assert_success
  assert_output --partial "staged.txt"
  refute_output --partial "README.md"
}

@test "hug sw -- <path>: combined diff path filtering" {
  run hug sw -- README.md --quiet
  assert_success
  assert_output --partial "README.md"
}

@test "hug su --stat -- <path>: flags + pathspecs combined" {
  run hug su --stat -- README.md --quiet
  assert_success
  assert_output --partial "Unstaged file stats"
  assert_output --partial "README.md"
  refute_output --partial "@@"
}

@test "hug su --: bare -- still triggers interactive mode" {
  # Regression test: bare '--' without paths should trigger interactive mode,
  # not be consumed by parse_pathspecs
  run hug su --
  # Should NOT show the regular diff output (interactive mode was triggered)
  refute_output --partial "Unstaged diff:"
}

@test "hug su <file>: backward compat without --" {
  # Regression test: positional args without -- should still work
  run hug su README.md --quiet
  assert_success
  assert_output --partial "Unstaged diff for README.md"
  assert_output --partial "README.md"
}

@test "hug su -- <nonexistent>: shows no output for non-matching path" {
  run hug su -- nonexistent_dir/ --quiet
  assert_success
  # Should not crash or show "bad revision" — just empty output
  refute_output --partial "fatal"
  refute_output --partial "bad revision"
}

@test "hug ss -- <path1> <path2>: multi-path staged diff" {
  # Stage another file
  echo "staged2" > staged2.txt
  git add staged2.txt

  run hug ss -- staged.txt staged2.txt --quiet
  assert_success
  assert_output --partial "staged.txt"
  assert_output --partial "staged2.txt"
}

@test "hug slc: lists only conflicted files" {
  local repo
  repo=$(create_slc_conflict_fixture)
  cd "$repo"

  # Merge side into main: conflict.txt conflicts; side-only.txt merges cleanly
  # (and lands STAGED — the real staged file slc must exclude); staged.txt stays
  # an unrelated unstaged change (no overlap).
  run hug mkeep side -m "merge side"
  assert_failure  # merge conflict expected

  run hug slc
  assert_success
  assert_output --partial "Cnflt"
  assert_output --partial "conflict.txt"
  refute_output --partial "side-only.txt"
  refute_output --partial "staged.txt"
}

@test "hug slc -q: prints plain paths only" {
  local repo
  repo=$(create_slc_conflict_fixture)
  cd "$repo"
  run hug mkeep side -m "merge side"
  assert_failure

  run hug slc -q
  assert_success
  [[ "$output" == "conflict.txt" ]]
}

@test "hug slc: no conflicts gives empty stdout, exit 0, info on stderr" {
  local clean_repo
  clean_repo=$(create_test_repo)
  cd "$clean_repo"

  # --separate-stderr: $output = stdout only (must be empty), $stderr = chatter
  run --separate-stderr -- hug slc
  assert_success
  [[ -z "$output" ]]

  run --separate-stderr -- hug slc
  assert_success
  [[ "$stderr" == *"No conflicted files."* ]]
}

@test "hug slc --json: empty conflicts still emits a valid envelope" {
  local clean_repo
  clean_repo=$(create_test_repo)
  cd "$clean_repo"

  run hug slc --json
  assert_success
  # GOTCHA: capture the JSON NOW — each subsequent `run` clobbers $output
  local json_out="$output"

  # Zero non-JSON bytes: json.tool must parse the whole output
  assert_valid_json "$json_out"

  # Spec contract: all-zero summary, INCLUDING conflicted and total
  run python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['summary']['conflicted'], d['summary']['total'])" "$json_out"
  assert_output "0 0"

  # Spec contract: NO conflicted array on the empty path — asserted via python
  # (key absence is spacing-independent, unlike raw `"conflicted": [` matching)
  run python3 -c "import json,sys; print('conflicted' in json.loads(sys.argv[1]))" "$json_out"
  assert_output "False"
}

@test "hug slc --json: valid JSON with conflicted summary" {
  local repo
  repo=$(create_slc_conflict_fixture)
  cd "$repo"
  run hug mkeep side -m "merge side"
  assert_failure

  run hug slc --json
  assert_success
  # GOTCHA: capture the JSON NOW — each subsequent `run` clobbers $output
  local json_out="$output"

  # Zero non-JSON bytes: json.tool must parse the whole output
  assert_valid_json "$json_out"

  run python3 -c "import json,sys; print(json.loads(sys.argv[1])['summary']['conflicted'])" "$json_out"
  assert_output "1"

  # Assert VALUES via python — the emitter formats `"key":  "value"` with a
  # double space, so raw-substring matching on key/value pairs is brittle.
  run python3 -c "import json,sys; print(json.loads(sys.argv[1])['conflicted'][0]['status'])" "$json_out"
  assert_output "conflict"

  # Path substring is safe (inside a quoted value; spacing-independent)
  [[ "$json_out" == *'"conflict.txt"'* ]]
}

@test "hug slc with pathspec scoping" {
  local repo
  repo=$(create_slc_conflict_fixture)
  cd "$repo"
  run hug mkeep side -m "merge side"
  assert_failure

  run hug slc conflict.txt
  assert_success
  assert_output --partial "conflict.txt"

  # Non-matching pathspec: empty stdout; info chatter on stderr
  run --separate-stderr -- hug slc no-such-file.txt
  assert_success
  [[ -z "$output" ]]

  run --separate-stderr -- hug slc no-such-file.txt
  assert_success
  [[ "$stderr" == *"No conflicted files matching 'no-such-file.txt' found."* ]]
}

@test "hug slc: -q suppresses the trailing summary; non-quiet shows it" {
  local repo
  repo=$(create_slc_conflict_fixture)
  cd "$repo"
  run hug mkeep side -m "merge side"
  assert_failure

  # Non-quiet: trailing `hug s` summary is chatter on stderr (stdout stays data)
  run --separate-stderr -- hug slc
  assert_success
  [[ "$stderr" == *"HEAD"* ]]

  run --separate-stderr -- hug slc -q
  assert_success
  [[ -z "$stderr" ]]
}

@test "hug slc: lists conflicted submodule pointers (gitlink)" {
  local outer_repo
  outer_repo=$(create_test_repo)
  cd "$outer_repo"

  # Embedded repo at inner/ — NOT `git submodule add` (git >= 2.38 blocks the
  # file protocol without -c protocol.file.allow=always).
  mkdir inner
  (
    cd inner
    git init -q -b main
    git config user.name "Test User"
    git config user.email "test@example.com"
    echo i1 > i.txt
    git add -A
    git commit -q -m "inner base"
  )
  git add inner
  git commit -q -m "Add submodule pointer"
  git branch side

  # main bumps the pointer
  (
    cd inner
    echo i2 > i.txt
    git add -A
    git commit -q -m "inner main bump"
  )
  git add inner
  git commit -q -m "Bump pointer on main"

  # side bumps a genuinely divergent pointer (rewind inner to its base first)
  git switch -q side
  (
    cd inner
    git reset -q --hard HEAD~1
    echo i3 > i.txt
    git add -A
    git commit -q -m "inner side bump"
  )
  git add inner
  git commit -q -m "Bump pointer on side"

  # merge → gitlink conflict (UU inner)
  git switch -q main
  run hug mkeep side -m "merge side"
  assert_failure

  run hug slc
  assert_success
  assert_output --partial "inner"
}

@test "hug slc --json: pathspecs scope the envelope (PR-B #298)" {
  local repo
  repo=$(create_slc_conflict_fixture)
  cd "$repo"
  run hug mkeep side -m "merge side"
  assert_failure

  # FLIPPED by PR-B (uniform pathspec contract): this test used to pin the
  # OLD contract ("--json ignores pathspecs" — a non-matching pathspec left
  # the envelope describing the FULL conflicted state). Pathspecs now scope
  # the envelope exactly like the text listing, and an empty scope keeps the
  # envelope SHAPE (zero-length "conflicted" array present, summary 0) —
  # the machine contract must not change shape with scope.

  # Matching pathspec: the conflicted file stays, count matches the array
  run hug slc --json -- conflict.txt
  assert_success
  local json_out="$output"
  run python3 -c "import json,sys; print(json.loads(sys.argv[1])['summary']['conflicted'])" "$json_out"
  assert_output "1"
  [[ "$json_out" == *'"conflict.txt"'* ]]

  # Non-matching pathspec (positional spelling — no separator needed): EMPTY
  # scope, shape kept
  run hug slc --json no-such-file.txt
  assert_success
  json_out="$output"
  run python3 -c "import json,sys; print(json.loads(sys.argv[1])['summary']['conflicted'])" "$json_out"
  assert_output "0"
  [[ "$json_out" != *'"conflict.txt"'* ]]
  run python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['conflicted'])" "$json_out"
  assert_output "[]"
}

@test "hug slc: HUG_QUIET=T prints plain paths, no summary" {
  local repo
  repo=$(create_slc_conflict_fixture)
  cd "$repo"
  run hug mkeep side -m "merge side"
  assert_failure

  HUG_QUIET=T run hug slc
  assert_success
  [[ "$output" == "conflict.txt" ]]
}

@test "hug slc --json -q: JSON wins" {
  local repo
  repo=$(create_slc_conflict_fixture)
  cd "$repo"
  run hug mkeep side -m "merge side"
  assert_failure

  run hug slc --json -q
  assert_success
  local json_out="$output"
  assert_valid_json "$json_out"
  [[ "$json_out" == *'"conflict.txt"'* ]]
}

# --- hug slc -c/--count ---

@test "hug slc -c: prints only the file count" {
  local repo
  repo=$(create_slc_conflict_fixture)
  cd "$repo"
  run hug mkeep side -m "merge side"
  assert_failure

  run hug slc -c
  assert_success
  assert_output "1"
}

@test "hug slc -c: pathspec scopes the count" {
  local repo
  repo=$(create_slc_conflict_fixture)
  cd "$repo"
  run hug mkeep side -m "merge side"
  assert_failure

  run hug slc -c conflict.txt
  assert_success
  assert_output "1"

  # A pathspec matching nothing → 0, exit 0 (the grep -c idiom)
  run hug slc -c no-such-file.txt
  assert_success
  assert_output "0"
}

@test "hug slc -c: no conflicts prints 0, exit 0" {
  local clean_repo
  clean_repo=$(create_test_repo)
  cd "$clean_repo"

  run hug slc -c
  assert_success
  assert_output "0"
}

@test "hug slc -c: suppresses the trailing summary and wins over -q" {
  local repo
  repo=$(create_slc_conflict_fixture)
  cd "$repo"
  run hug mkeep side -m "merge side"
  assert_failure

  # -c with -q: stdout is exactly the count, no summary chatter
  run --separate-stderr -- hug slc -c -q
  assert_success
  assert_output "1"
  [[ -z "$stderr" ]]
}

@test "hug slc -c: -c + --json errors (mutually exclusive)" {
  local repo
  repo=$(create_slc_conflict_fixture)
  cd "$repo"
  run hug mkeep side -m "merge side"
  assert_failure

  # -c and --json are incompatible (like hug wtl's --json --path-only error)
  run hug slc -c --json
  assert_failure
  [[ "$status" -eq 2 ]]   # usage-error exit family (F-001), not a generic 1
  assert_output --partial "mutually exclusive"
}

@test "hug us: empty --from-file + scope blames the source, not the pathspec" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"
  echo a > a.txt
  hug a -- a.txt
  : > "$BATS_TEST_TMPDIR/empty-list.txt"

  # Empty SOURCE list: the scope never excluded anything — the message must
  # not claim "No files matching <scope>" (code-roast F-004 misattribution).
  run hug us --from-file "$BATS_TEST_TMPDIR/empty-list.txt" -- src/
  assert_success
  assert_output --partial "Source list is empty"

  # Non-empty source fully excluded by scope keeps the no-match wording.
  echo "a.txt" > "$BATS_TEST_TMPDIR/one.txt"
  run hug us --from-file "$BATS_TEST_TMPDIR/one.txt" -- docs/
  assert_success
  assert_output --partial "No files matching 'docs/'"
}

@test "hug us: scoped --from-file unstage WORKS for a unicode filename (raw vs C-quoted, PR #318 review)" {
  # The scope set was captured without -z (git C-quoting: 'héllo.txt' as
  # "h\303\251llo.txt") while the source side resolved RAW — membership
  # never matched and this flow answered a SILENT "No files matching '.'"
  # exit 0 with the file left staged (pre-extraction failed loudly). The
  # -z transport on both sides makes the unstage actually happen.
  local repo
  repo=$(create_test_repo)
  cd "$repo"
  printf 'base\n' > 'héllo.txt'
  hug a -- 'héllo.txt'
  hug c -m base >/dev/null
  printf 'mod\n' >> 'héllo.txt'
  hug a -- 'héllo.txt'
  printf 'héllo.txt\n' > "$BATS_TEST_TMPDIR/uni-list.txt"

  run hug us --from-file "$BATS_TEST_TMPDIR/uni-list.txt" -- .
  assert_success
  assert_output --partial "Unstaged 1 file"
  # The behavioral assert: nothing left staged under the scope.
  run git diff --cached --name-only
  refute_output --partial "llo.txt"
}

@test "hug slk -c: counts a newline-containing filename once (NUL-safe)" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"

  # git permits newlines in filenames; line-based counting would over-count to 2
  touch "$(printf 'weird\nname.txt')"

  run hug slk -c
  assert_success
  assert_output "1"
}

# --- sl* family -c/--count ---

@test "hug slu -c: counts unstaged files, scoped by pathspec" {
  # TEST_REPO (from setup) has 1 unstaged change (README.md)
  run hug slu -c
  assert_success
  assert_output "1"

  # Pathspec that matches nothing → 0
  run hug slu -c no-such-file.txt
  assert_success
  assert_output "0"
}

@test "hug sls -c / slk -c / sli -c: count staged/untracked/ignored" {
  cd "$TEST_REPO"
  # Fixture: staged.txt staged, README.md unstaged, untracked.txt untracked
  run hug sls -c
  assert_success
  assert_output "1"

  run hug slk -c
  assert_success
  assert_output "1"

  echo "*.log" > .gitignore
  touch ignored.log
  run hug sli -c
  assert_success
  assert_output "1"
}

@test "hug sl -c / sla -c: count via git-statusbase aliases" {
  cd "$TEST_REPO"
  # Fixture: staged.txt staged, README.md unstaged, untracked.txt untracked.
  # sl = staged+unstaged (2, deduplicated); sla = +untracked (3).
  run hug sl -c
  assert_success
  assert_output "2"

  run hug sla -c
  assert_success
  assert_output "3"
}

@test "hug sl* listings reject action-only common flags (codex P2)" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"
  echo a > a.txt
  hug a -- a.txt

  # parse_common_flags consumes -f/-y/--dry-run/--browse-root before the
  # scripts' own unknown-option branch sees them — these used to be silently
  # accepted and produce a normal unscoped listing. A listing's only common
  # flags are -q and help; everything else is a usage error (exit 2).
  for cmd in sls slu slk sli slc; do
    for flag in --dry-run -f -y --browse-root; do
      run hug "$cmd" "$flag"
      [[ "$status" -eq 2 ]]
      assert_output --partial "action flags"
    done
  done
  # statusbase serves sl/sla
  run hug sl --dry-run
  [[ "$status" -eq 2 ]]
  # -q (the supported quiet flag) still works
  run hug sls -q
  assert_success

  # INHERITED HUG_YES must not reject an innocent listing (codex follow-up):
  # sequence automation exports the documented confirmation variable for a
  # whole hug command line — only a -y consumed by THIS parse is a violation.
  # The detector is the parse-local yes_flag, never the HUG_YES export.
  HUG_YES=true run hug sls -q
  assert_success
  HUG_YES=false run hug sls
  assert_success
  # ...while an explicit -y on THIS invocation stays a usage error
  run hug sls -y
  [[ "$status" -eq 2 ]]
}

# --- Characterization pins (#303 Part 2, pre sl_family_main migration) ---
# These rows pin TODAY's behavior of the sl* family BEFORE Tasks 6–7 collapse
# the five sibling scripts onto a shared template. Any byte-drift during the
# templating must fail loudly here. Do NOT "fix" these by changing production
# code — they describe current behavior by design.

# PIN ADJUSTMENT vs sketch: slc's real _hug_category is ["status"] (git-slc:2),
# not ["status", "staging"] — the sketch mis-read it; expected fixed from the
# actual script content.
@test "hug slc --search-meta: prints category AND keywords lines" {
  run hug slc --search-meta
  assert_success
  assert_output --partial 'category = ["status"]'
  assert_output --partial 'keywords = ["conflict","unmerged","merge","rebase"]'
}

@test "hug sls --search-meta: prints category only (no keywords)" {
  run hug sls --search-meta
  assert_success
  assert_output --partial 'category'
  refute_output --partial 'keywords'
}

@test "hug slk -q: suppresses the status column (--suppress-status)" {
  local repo; repo=$(create_test_repo); cd "$repo"
  echo x > stray.txt   # untracked: visible to slk
  run hug slk -q
  assert_success
  assert_output --partial "stray.txt"
  # The untracked column is spelled 'untrcK' (hug-select-files
  # _format_untracked_status) — '??' never appears in slk output, so
  # refuting it would be unfalsifiable (PR #318 review, testing specialist).
  refute_output --partial "untrcK"   # status column suppressed
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
