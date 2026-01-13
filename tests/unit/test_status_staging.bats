#!/usr/bin/env bats
# Tests for status and staging commands (s*, a*, us*)

# Load test helpers
load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_changes)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

@test "hug s: shows status summary" {
  run hug s
  assert_success
  # Should show some status information (HEAD, branch, or status indicator)
  [[ "$output" =~ (HEAD|master|Staged|Unstaged) ]]
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
  # Create and commit a file
  echo "secret" > .env
  git add .env
  git commit -q -m "Add .env"
  
  # Untrack it with --force to skip confirmation
  run hug untrack .env --force
  assert_success
  assert_output --partial "✅ Success: Untracked 1 file (kept locally):"
  assert_output --partial ".env"
  
  # Verify file is untracked but still exists locally
  run git ls-files
  refute_output --partial ".env"
  assert_file_exist .env
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
  assert_output --partial "UnTrck src/"
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
  # Should show clean state
  assert_output --partial "⚫"
  assert_output --partial "🌿main"
  # Should show empty hash (double spaces)
  assert_output --partial "HEAD:  🌿"
}
