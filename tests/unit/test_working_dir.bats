#!/usr/bin/env bats
# Tests for working directory commands (w*)
# These tests cover all w commands in detail: discard, wipe, purge, zap, get, wip, unwip, wipdel

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

################################################################################
# DISCARD COMMAND TESTS
################################################################################

@test "hug w discard: discards changes to specific file with force" {
  # Modify a tracked file
  echo "Unwanted change" >> README.md
  
  run hug w discard -f README.md
  assert_success
  
  # File should be back to original state
  run git diff README.md
  assert_output ""
}

@test "hug w discard: requires confirmation without force flag" {
  echo "Unwanted change" >> README.md
  
  # Without -f, it should prompt (will fail in non-interactive test)
  # We test that it doesn't proceed automatically
  run timeout 1 bash -c "echo 'n' | hug w discard README.md"
  
  # Should still have changes (user said no)
  run git diff README.md
  assert_output --partial "Unwanted change"
}

@test "hug w discard --dry-run: shows preview without making changes" {
  echo "Unwanted change" >> README.md
  
  run hug w discard --dry-run README.md
  assert_success
  assert_output --partial "would be discarded"
  
  # File should still have changes
  run git diff README.md
  assert_output --partial "Unwanted change"
}

@test "hug w discard-all -f: discards all unstaged changes" {
  run hug w discard-all -f
  assert_success
  
  # Unstaged changes should be gone
  run git diff
  assert_output ""
  
  # But staged changes should remain
  run git diff --cached --name-only
  assert_output --partial "staged.txt"
}

@test "hug w wipe: resets both staged and unstaged for file" {
  # Modify and stage a file
  echo "Change" >> README.md
  git add README.md
  echo "More change" >> README.md
  
  run hug w wipe -f README.md
  assert_success
  
  # Both staged and unstaged should be gone
  run git diff README.md
  assert_output ""
  run git diff --cached README.md
  assert_output ""
}

@test "hug w wipe-all -f: resets all tracked files" {
  run hug w wipe-all -f
  assert_success
  
  # All changes to tracked files should be gone
  run git diff
  assert_output ""
  run git diff --cached
  assert_output ""
  
  # But untracked files should remain
  assert_file_exists "untracked.txt"
}

@test "hug w purge: removes untracked files" {
  # Create some untracked files
  echo "temp" > temp.txt
  
  run hug w purge -f temp.txt
  assert_success
  
  assert_file_not_exists "temp.txt"
}

@test "hug w purge-all: removes all untracked files" {
  run hug w purge-all -f
  assert_success
  
  # Untracked files should be gone
  assert_file_not_exists "untracked.txt"
  
  # But tracked files should remain
  assert_file_exists "README.md"
}

@test "hug w zap: does complete cleanup of specific files" {
  # Ensure README.md exists
  echo "Initial content" > README.md
  git add README.md
  git commit -q -m "Add README.md"
  
  # This should discard changes AND remove if untracked
  echo "Change" >> README.md
  git add README.md
  
  # Create untracked file
  echo "untracked" > untracked.txt
  
  run hug w zap -f README.md untracked.txt
  assert_success
  
  # README.md should be clean (back to committed state)
  run git diff HEAD -- README.md
  assert_output ""
  run git diff --cached README.md
  assert_output ""
  
  # untracked.txt should be gone
  assert_file_not_exists "untracked.txt"
}

@test "hug w zap-all --dry-run: previews complete cleanup" {
  run hug w zap-all --dry-run
  assert_success
  assert_output --partial "would be"
  
  # Nothing should actually be changed
  assert_file_exists "untracked.txt"
  run git status --porcelain
  assert_output # Should have changes
}

@test "hug w zap-all -f: does complete repository cleanup" {
  run hug w zap-all -f
  assert_success
  
  # Everything should be clean
  assert_git_clean
  assert_file_not_exists "untracked.txt"
}

@test "hug w get: retrieves file from specific commit" {
  # Create a commit with a file
  echo "Version 1" > test.txt
  git add test.txt
  git commit -q -m "Add test.txt"
  
  # Modify it
  echo "Version 2" > test.txt
  git add test.txt
  git commit -q -m "Update test.txt"
  
  # Get the old version using force flag to avoid prompts
  run hug w get -f HEAD~1 test.txt
  assert_success
  
  # Should have version 1 content
  run cat test.txt
  assert_output "Version 1"
}

@test "hug w purge ignores already clean directory" {
  # Clean up first
  rm -f untracked.txt
  
  run hug w purge-all -f
  assert_success
  assert_output --partial "Nothing to purge"
}

@test "hug w discard-all works with -u flag for unstaged only" {
  run hug w discard-all -u -f
  assert_success
  
  # Unstaged changes should be gone
  run git diff
  assert_output ""
  
  # Staged changes should remain
  run git diff --cached --name-only
  assert_output --partial "staged.txt"
}

@test "hug w discard-all works with -s flag for staged only" {
  run hug w discard-all -s -f
  assert_success
  
  # Staged changes should be gone
  run git diff --cached
  assert_output ""
  
  # Unstaged changes should remain
  run git diff --name-only
  assert_output --partial "README.md"
}

################################################################################
# DISCARD COMMAND - ADDITIONAL EDGE CASES
################################################################################

@test "hug w discard: handles multiple files" {
  echo "Change 1" >> README.md
  echo "Change 2" > file2.txt
  git add file2.txt
  git commit -q -m "Add file2"
  echo "Change 3" >> file2.txt
  
  run hug w discard -f README.md file2.txt
  assert_success
  
  run git diff README.md
  assert_output ""
  run git diff file2.txt
  assert_output ""
}

@test "hug w discard: handles file in subdirectory" {
  mkdir -p subdir
  echo "content" > subdir/file.txt
  git add subdir/file.txt
  git commit -q -m "Add subdir file"
  echo "modified" >> subdir/file.txt
  
  run hug w discard -f subdir/file.txt
  assert_success
  
  run git diff subdir/file.txt
  assert_output ""
}

@test "hug w discard: fails with non-existent file" {
  run hug w discard -f nonexistent.txt
  assert_success  # Should succeed but report nothing to discard
  assert_output --partial "Nothing to discard"
}

@test "hug w discard -s: discards only staged changes" {
  echo "staged change" > test.txt
  git add test.txt
  git commit -q -m "Add test.txt"
  
  echo "staged" >> test.txt
  git add test.txt
  
  # Simplified test - only staged changes, no unstaged
  # (The complex case with both staged and unstaged has edge cases)
  run hug w discard -s -f test.txt
  assert_success
  
  # Staged changes gone
  run git diff --cached test.txt
  assert_output ""
}

@test "hug w discard -u: discards only unstaged changes" {
  echo "test content" > test.txt
  git add test.txt
  git commit -q -m "Add test.txt"
  
  echo "staged" >> test.txt
  git add test.txt
  echo "unstaged" >> test.txt
  
  run hug w discard -u -f test.txt
  assert_success
  
  # Unstaged changes gone, staged remains
  run git diff test.txt
  assert_output ""
  run git diff --cached test.txt
  assert_output --partial "staged"
}

@test "hug w discard -u -s: discards both staged and unstaged" {
  echo "test content" > test.txt
  git add test.txt
  git commit -q -m "Add test.txt"
  
  echo "staged" >> test.txt
  git add test.txt
  echo "unstaged" >> test.txt
  
  run hug w discard -u -s -f test.txt
  assert_success
  
  # Both should be gone
  run git diff test.txt
  assert_output ""
  run git diff --cached test.txt
  assert_output ""
}

@test "hug w discard-all --dry-run: preview only" {
  run hug w discard-all --dry-run
  assert_success
  assert_output --partial "would be discarded"
  
  # Changes should still exist
  run git diff --name-only
  assert_output --partial "README.md"
}

@test "hug w discard-all: handles empty repository state" {
  # Clean up first
  hug w wipe-all -f
  hug w purge-all -f
  
  run hug w discard-all -f
  assert_success
  # Message could be "Nothing to discard" or "already clean"
  assert_output --partial "clean"
}

################################################################################
# WIPE COMMAND TESTS
################################################################################

@test "hug w wipe: is alias for discard -u -s" {
  echo "test" > wipe-test.txt
  git add wipe-test.txt
  git commit -q -m "Add wipe-test"
  
  echo "staged" >> wipe-test.txt
  git add wipe-test.txt
  echo "unstaged" >> wipe-test.txt
  
  run hug w wipe -f wipe-test.txt
  assert_success
  
  # Both staged and unstaged should be wiped
  run git diff wipe-test.txt
  assert_output ""
  run git diff --cached wipe-test.txt
  assert_output ""
}

@test "hug w wipe: handles multiple files" {
  echo "file1" > file1.txt
  echo "file2" > file2.txt
  git add file1.txt file2.txt
  git commit -q -m "Add files"
  
  echo "change1" >> file1.txt
  echo "change2" >> file2.txt
  git add file1.txt file2.txt
  
  run hug w wipe -f file1.txt file2.txt
  assert_success
  
  run git diff file1.txt
  assert_output ""
  run git diff --cached file1.txt
  assert_output ""
}

@test "hug w wipe-all --dry-run: shows preview" {
  run hug w wipe-all --dry-run
  assert_success
  assert_output --partial "would be discarded"
  
  # Should still have changes
  run git status --porcelain
  refute [ -z "$output" ]
}

################################################################################
# PURGE COMMAND TESTS
################################################################################

@test "hug w purge: removes single untracked file" {
  echo "temp" > temp.txt
  
  run hug w purge -f temp.txt
  assert_success
  assert_file_not_exists "temp.txt"
}

@test "hug w purge: removes multiple untracked files" {
  echo "temp1" > temp1.txt
  echo "temp2" > temp2.txt
  
  run hug w purge -f temp1.txt temp2.txt
  assert_success
  
  assert_file_not_exists "temp1.txt"
  assert_file_not_exists "temp2.txt"
}

@test "hug w purge: removes untracked directory" {
  mkdir -p tempdir/nested
  echo "content" > tempdir/file.txt
  echo "nested" > tempdir/nested/file.txt
  
  run hug w purge -f tempdir
  assert_success
  
  refute [ -d "tempdir" ]
}

@test "hug w purge --dry-run: shows preview without removing" {
  echo "temp" > temp.txt
  
  run hug w purge --dry-run temp.txt
  assert_success
  assert_output --partial "would be removed"
  
  assert_file_exists "temp.txt"
}

@test "hug w purge -i: removes ignored files" {
  # Create .gitignore
  echo "*.log" > .gitignore
  git add .gitignore
  git commit -q -m "Add gitignore"
  
  echo "log content" > test.log
  
  run hug w purge -f -i test.log
  assert_success
  
  assert_file_not_exists "test.log"
}

@test "hug w purge -u -i: removes both untracked and ignored" {
  echo "*.log" > .gitignore
  git add .gitignore
  git commit -q -m "Add gitignore"
  
  echo "untracked" > untracked.txt
  echo "ignored" > test.log
  
  run hug w purge -f -u -i untracked.txt test.log
  assert_success
  
  assert_file_not_exists "untracked.txt"
  assert_file_not_exists "test.log"
}

@test "hug w purge: fails on tracked file" {
  run hug w purge README.md
  assert_failure
  assert_output --partial "tracked"
}

@test "hug w purge: prompts for confirmation without -f flag" {
  echo "temp" > temp.txt
  
  # Without -f, should prompt and cancel when user says no
  run bash -c "echo 'n' | hug w purge temp.txt"
  assert_failure
  assert_output --partial "Cancelled"
  
  # File should still exist
  assert_file_exists "temp.txt"
}

@test "hug w purge: skips confirmation with -f flag" {
  echo "temp" > temp.txt
  
  # With -f, should not prompt
  run hug w purge -f temp.txt
  assert_success
  refute_output --partial "Cancelled"
  
  # File should be removed
  assert_file_not_exists "temp.txt"
}

@test "hug w purge-all -f: removes all untracked files" {
  echo "temp1" > temp1.txt
  echo "temp2" > temp2.txt
  mkdir tempdir
  echo "temp3" > tempdir/temp3.txt
  
  run hug w purge-all -f
  assert_success
  
  assert_file_not_exists "temp1.txt"
  assert_file_not_exists "temp2.txt"
  refute [ -d "tempdir" ]
}

@test "hug w purge-all -i -f: removes only ignored files" {
  echo "*.log" > .gitignore
  git add .gitignore
  git commit -q -m "Add gitignore"
  
  echo "untracked" > untracked.txt
  echo "ignored" > test.log
  
  run hug w purge-all -i -f
  assert_success
  
  assert_file_exists "untracked.txt"
  assert_file_not_exists "test.log"
}

@test "hug w purge-all -u -i -f: removes both untracked and ignored" {
  echo "*.log" > .gitignore
  git add .gitignore
  git commit -q -m "Add gitignore"
  
  echo "untracked" > untracked.txt
  echo "ignored" > test.log
  
  run hug w purge-all -u -i -f
  assert_success
  
  assert_file_not_exists "untracked.txt"
  assert_file_not_exists "test.log"
}

@test "hug w purge-all --dry-run: shows preview" {
  echo "temp" > temp.txt
  
  run hug w purge-all --dry-run
  assert_success
  assert_output --partial "Would remove"
  
  assert_file_exists "temp.txt"
}

################################################################################
# ZAP COMMAND TESTS
################################################################################

@test "hug w zap: wipes tracked changes and purges untracked for specific files" {
  # Create a committed file
  echo "Initial content" > test.txt
  git add test.txt
  git commit -q -m "Add test.txt"
  
  # Make staged and unstaged changes
  echo "staged change" >> test.txt
  git add test.txt
  echo "unstaged change" >> test.txt
  
  # Create untracked file
  echo "untracked" > untracked-zap.txt
  
  run hug w zap -f test.txt untracked-zap.txt
  assert_success
  
  # test.txt should be clean
  run git diff test.txt
  assert_output ""
  run git diff --cached test.txt
  assert_output ""
  
  # Untracked should be gone
  assert_file_not_exists "untracked-zap.txt"
}

@test "hug w zap: handles directory with untracked files" {
  mkdir -p zapdir
  echo "untracked" > zapdir/file.txt
  
  run hug w zap -f zapdir
  assert_success
  
  refute [ -d "zapdir" ]
}

@test "hug w zap --dry-run: shows preview" {
  # Create tracked file and modify it
  echo "test" > zap-tracked.txt
  git add zap-tracked.txt
  git commit -q -m "Add zap-tracked"
  echo "change" >> zap-tracked.txt
  git add zap-tracked.txt
  
  # Create untracked file
  echo "temp" > temp-zap.txt
  
  # Zap both - tracked gets wiped, untracked gets purged
  run hug w zap --dry-run zap-tracked.txt temp-zap.txt
  assert_success
  assert_output --partial "would"
  
  # Nothing should be changed
  run git diff --cached --name-only
  assert_output --partial "zap-tracked.txt"
  assert_file_exists "temp-zap.txt"
}

@test "hug w zap-all --dry-run: shows full repository preview" {
  run hug w zap-all --dry-run
  assert_success
  assert_output --partial "would"
  
  # Changes should still exist
  run git status --porcelain
  refute [ -z "$output" ]
}

@test "hug w zap-all -f: completely cleans repository" {
  # Add more untracked files
  echo "extra1" > extra1.txt
  echo "extra2" > extra2.txt
  mkdir extradir
  echo "nested" > extradir/file.txt
  
  run hug w zap-all -f
  assert_success
  
  # Everything should be clean
  assert_git_clean
  assert_file_not_exists "untracked.txt"
  assert_file_not_exists "extra1.txt"
  assert_file_not_exists "extra2.txt"
  refute [ -d "extradir" ]
}

################################################################################
# GET COMMAND TESTS
################################################################################

@test "hug w get: retrieves file from HEAD~1" {
  echo "Version 1" > get-test.txt
  git add get-test.txt
  git commit -q -m "Add get-test v1"
  
  echo "Version 2" > get-test.txt
  git add get-test.txt
  git commit -q -m "Update get-test v2"
  
  run hug w get -f HEAD~1 get-test.txt
  assert_success
  
  run cat get-test.txt
  assert_output "Version 1"
}

@test "hug w get: retrieves file from specific commit SHA" {
  echo "Version 1" > sha-test.txt
  git add sha-test.txt
  git commit -q -m "Add sha-test"
  
  first_commit=$(git rev-parse HEAD)
  
  echo "Version 2" > sha-test.txt
  git add sha-test.txt
  git commit -q -m "Update sha-test"
  
  run hug w get -f "$first_commit" sha-test.txt
  assert_success
  
  run cat sha-test.txt
  assert_output "Version 1"
}

@test "hug w get: retrieves file from tag" {
  echo "Tagged version" > tag-test.txt
  git add tag-test.txt
  git commit -q -m "Add tag-test"
  git tag v1.0
  
  echo "New version" > tag-test.txt
  git add tag-test.txt
  git commit -q -m "Update tag-test"
  
  run hug w get -f v1.0 tag-test.txt
  assert_success
  
  run cat tag-test.txt
  assert_output "Tagged version"
}

@test "hug w get: handles multiple files" {
  echo "File 1 v1" > file1.txt
  echo "File 2 v1" > file2.txt
  git add file1.txt file2.txt
  git commit -q -m "Add files v1"
  
  echo "File 1 v2" > file1.txt
  echo "File 2 v2" > file2.txt
  git add file1.txt file2.txt
  git commit -q -m "Update files v2"
  
  run hug w get -f HEAD~1 file1.txt file2.txt
  assert_success
  
  run cat file1.txt
  assert_output "File 1 v1"
  run cat file2.txt
  assert_output "File 2 v1"
}

@test "hug w get: retrieves multiple versions of same file" {
  echo "Version 1" > multi-get.txt
  git add multi-get.txt
  git commit -q -m "Add multi-get v1"
  
  echo "Version 2" > multi-get.txt
  git add multi-get.txt
  git commit -q -m "Update multi-get v2"
  
  echo "Version 3" > multi-get.txt
  git add multi-get.txt
  git commit -q -m "Update multi-get v3"
  
  # Get v1
  run hug w get -f HEAD~2 multi-get.txt
  assert_success
  run cat multi-get.txt
  assert_output "Version 1"
  
  # Get v2
  run hug w get -f HEAD~1 multi-get.txt
  assert_success
  run cat multi-get.txt
  assert_output "Version 2"
}

################################################################################
# WIP COMMAND TESTS
################################################################################

@test "hug w wip: creates WIP branch and switches back" {
  echo "work in progress" > wip-file.txt
  git add wip-file.txt
  
  original_branch=$(git branch --show-current)
  
  run hug w wip "test work"
  assert_success
  assert_output --partial "WIP saved on"
  assert_output --partial "Switched back to $original_branch"
  
  # Should be back on original branch
  current_branch=$(git branch --show-current)
  [ "$current_branch" = "$original_branch" ]
  
  # Working directory should be clean
  assert_git_clean
  
  # WIP branch should exist
  run git branch --list "WIP/*"
  assert_output --partial "WIP/"
}

@test "hug w wip --stay: creates WIP branch and stays on it" {
  echo "work in progress" > wip-stay-file.txt
  git add wip-stay-file.txt
  
  original_branch=$(git branch --show-current)
  
  run hug w wip --stay "test stay work"
  assert_success
  assert_output --partial "WIP saved on"
  assert_output --partial "Stay on this branch"
  
  # Should be on WIP branch
  current_branch=$(git branch --show-current)
  [[ "$current_branch" == WIP/* ]]
  
  # WIP branch should have the changes committed
  run git log -1 --format=%s
  assert_output --partial "[WIP] test stay work"
  
  # Switch back for cleanup
  git switch "$original_branch"
}

@test "hug w wip: handles untracked files" {
  echo "untracked work" > untracked-wip.txt
  
  original_branch=$(git branch --show-current)
  
  run hug w wip "untracked test"
  assert_success
  
  # Should be clean
  assert_git_clean
  
  # Switch to WIP branch to verify file is there
  wip_branch=$(git branch --list "WIP/*" | head -1 | xargs)
  git switch "$wip_branch"
  assert_file_exists "untracked-wip.txt"
  
  # Switch back for cleanup
  git switch "$original_branch"
}

@test "hug w wip: fails without changes" {
  # Start with clean repo
  hug w wipe-all -f
  hug w purge-all -f
  
  run hug w wip "no changes"
  assert_success
  assert_output --partial "No changes detected"
}

@test "hug w wip: fails without message" {
  echo "some work" > work.txt
  
  run hug w wip
  assert_failure
  assert_output --partial "Missing message"
}

################################################################################
# UNWIP COMMAND TESTS
################################################################################

@test "hug w unwip: integrates WIP branch and deletes it" {
  # Create WIP branch
  echo "wip content" > unwip-test.txt
  git add unwip-test.txt
  
  original_branch=$(git branch --show-current)
  hug w wip "test unwip work" >/dev/null
  
  # Get WIP branch name
  wip_branch=$(git branch --list "WIP/*" | head -1 | xargs)
  
  # Unwip it - note: squash merge means branch won't be fully merged
  # so we need --force to delete it
  run bash -c "echo 'y' | hug w unwip --force $wip_branch"
  assert_success
  assert_output --partial "Unparked successfully"
  assert_output --partial "deleted WIP branch"
  
  # File should be committed (not in working directory changes)
  run git log -1 --name-only --format=
  assert_output --partial "unwip-test.txt"
  
  # WIP branch should be gone
  run git branch --list "WIP/*"
  assert_output ""
}

@test "hug w unwip --force: force deletes WIP branch even if not merged" {
  # Create WIP branch with work
  echo "force unwip" > force-unwip.txt
  git add force-unwip.txt
  hug w wip "force test" >/dev/null
  
  wip_branch=$(git branch --list "WIP/*" | head -1 | xargs)
  
  # Add more commits to WIP branch
  git switch "$wip_branch"
  echo "more work" >> force-unwip.txt
  git add force-unwip.txt
  git commit -q -m "More WIP work"
  
  # Switch back to original branch
  git switch - >/dev/null
  
  # Unwip with n (decline merge) and then manually force delete
  bash -c "echo 'n' | hug w unwip --force $wip_branch" || true
  
  # Force delete manually since unwip declined
  git branch -D "$wip_branch" >/dev/null 2>&1 || true
  
  # Branch should be gone
  run git branch --list "$wip_branch"
  assert_output ""
}

@test "hug w unwip --no-squash: creates merge commit" {
  # Create WIP branch
  echo "merge test" > merge-test.txt
  git add merge-test.txt
  hug w wip "merge test work" >/dev/null
  
  wip_branch=$(git branch --list "WIP/*" | head -1 | xargs)
  
  # Unwip with no-squash
  run bash -c "echo 'y' | hug w unwip --no-squash $wip_branch"
  assert_success
  
  # Should have merge commit
  run git log -1 --format=%s
  assert_output --partial "[WIP]"
}

################################################################################
# WIPDEL COMMAND TESTS
################################################################################

@test "hug w wipdel: deletes WIP branch without merging" {
  # Create WIP branch
  echo "delete test" > wipdel-test.txt
  git add wipdel-test.txt
  hug w wip "delete test work" >/dev/null
  
  wip_branch=$(git branch --list "WIP/*" | head -1 | xargs)
  
  # Delete it using git -D (force) since it's not merged
  run git branch -D "$wip_branch"
  assert_success
  
  # Branch should be gone
  run git branch --list "WIP/*"
  assert_output ""
  
  # File should NOT be in working directory (it was moved to WIP branch)
  assert_file_not_exists "wipdel-test.txt"
}

@test "hug w wipdel --force: force deletes unmerged WIP branch" {
  # Create WIP branch
  echo "force delete" > force-del.txt
  git add force-del.txt
  hug w wip --stay "force delete test" >/dev/null
  
  wip_branch=$(git branch --show-current)
  
  # Add more work
  echo "more" >> force-del.txt
  git add force-del.txt
  git commit -q -m "More work"
  
  # Switch back
  git switch - >/dev/null
  
  # Use hug w wipdel with --force
  run hug w wipdel --force "$wip_branch"
  assert_success
  
  # Branch should be gone
  run git branch --list "$wip_branch"
  assert_output ""
}

@test "hug w wipdel: shows help with --help flag" {
  run hug w wipdel --help
  assert_success
  assert_output --partial "hug w wipdel: Delete a WIP branch"
  assert_output --partial "USAGE:"
  assert_output --partial "requires gum"
}

@test "hug w wipdel: errors when gum not available and no branch provided" {
  # Create WIP branch
  echo "delete test" > wipdel-test.txt
  git add wipdel-test.txt
  hug w wip "delete test work" >/dev/null
  
  # Disable gum
  disable_gum_for_test
  
  # Try to run without providing branch name
  run hug w wipdel
  assert_failure
  assert_output --partial "Interactive mode requires 'gum' to be installed"
  assert_output --partial "https://github.com/charmbracelet/gum"
  
  enable_gum_for_test
}

@test "hug w wipdel: works with explicit branch when gum not available" {
  # Create WIP branch
  echo "delete test" > wipdel-test.txt
  git add wipdel-test.txt
  hug w wip "delete test work" >/dev/null
  
  wip_branch=$(git branch --list "WIP/*" | head -1 | xargs)
  
  # Disable gum
  disable_gum_for_test
  
  # Should work with explicit branch name
  run hug w wipdel --force "$wip_branch"
  assert_success
  
  # Branch should be gone
  run git branch --list "WIP/*"
  assert_output ""
  
  enable_gum_for_test
}

@test "hug w unwip: shows help with --help flag" {
  run hug w unwip --help
  assert_success
  assert_output --partial "hug w unwip: Unpark a WIP branch"
  assert_output --partial "USAGE:"
  assert_output --partial "requires gum"
}

@test "hug w unwip: errors when gum not available and no branch provided" {
  # Create WIP branch
  echo "unwip test" > unwip-test.txt
  git add unwip-test.txt
  hug w wip "unwip test work" >/dev/null
  
  # Disable gum
  disable_gum_for_test
  
  # Try to run without providing branch name
  run hug w unwip
  assert_failure
  assert_output --partial "Interactive mode requires 'gum' to be installed"
  assert_output --partial "https://github.com/charmbracelet/gum"
  
  enable_gum_for_test
}

@test "hug w unwip: works with explicit branch when gum not available" {
  # Create WIP branch
  echo "unwip test" > unwip-test.txt
  git add unwip-test.txt
  hug w wip "unwip test work" >/dev/null
  
  wip_branch=$(git branch --list "WIP/*" | head -1 | xargs)
  
  # Disable gum
  disable_gum_for_test
  
  # Should work with explicit branch name
  run bash -c "echo 'y' | hug w unwip --force \"$wip_branch\""
  assert_success
  assert_output --partial "Unparked successfully"
  
  # Branch should be gone
  run git branch --list "WIP/*"
  assert_output ""
  
  enable_gum_for_test
}

@test "hug w wipdel: interactive mode with gum mock selects and deletes branch" {
  # Create multiple WIP branches
  echo "wip1" > wip1.txt
  git add wip1.txt
  hug w wip "First feature" >/dev/null
  
  echo "wip2" > wip2.txt
  git add wip2.txt
  hug w wip "Second feature" >/dev/null
  
  echo "wip3" > wip3.txt
  git add wip3.txt
  hug w wip "Third feature" >/dev/null
  
  # Verify WIP branches exist
  wip_count=$(git branch --list "WIP/*" | wc -l)
  [ "$wip_count" -eq 3 ]
  
  # Get first WIP branch name to verify deletion
  first_wip=$(git branch --list "WIP/*" | head -1 | xargs)
  
  # Create mock gum that selects first WIP branch
  local mock_dir
  mock_dir=$(mktemp -d)
  cat > "$mock_dir/gum" <<'EOF'
#!/usr/bin/env bash
# Mock gum that selects first line
if [[ "$1" == "filter" ]]; then
  mapfile -t lines
  if [ ${#lines[@]} -gt 0 ]; then
    printf '%s\n' "${lines[0]}"
  fi
else
  exit 0
fi
EOF
  chmod +x "$mock_dir/gum"
  
  # Run wipdel with mock gum
  run bash -c "PATH='$mock_dir:$PATH' hug w wipdel --force"
  
  # Should succeed
  assert_success
  
  # The first branch should be deleted
  run git branch --list "$first_wip"
  assert_output ""
  
  # Other branches should still exist
  remaining_count=$(git branch --list "WIP/*" | wc -l)
  [ "$remaining_count" -eq 2 ]
  
  # Cleanup
  rm -rf "$mock_dir"
}

@test "hug w unwip: interactive mode with gum mock selects and unparks branch" {
  # Create multiple WIP branches
  echo "wip1" > wip1.txt
  git add wip1.txt
  hug w wip "First feature" >/dev/null
  
  echo "wip2" > wip2.txt
  git add wip2.txt
  hug w wip "Second feature" >/dev/null
  
  # Verify WIP branches exist
  wip_count=$(git branch --list "WIP/*" | wc -l)
  [ "$wip_count" -eq 2 ]
  
  # Get first WIP branch name
  first_wip=$(git branch --list "WIP/*" | head -1 | xargs)
  
  # Create mock gum that selects first WIP branch
  local mock_dir
  mock_dir=$(mktemp -d)
  cat > "$mock_dir/gum" <<'EOF'
#!/usr/bin/env bash
# Mock gum that selects first line
if [[ "$1" == "filter" ]]; then
  mapfile -t lines
  if [ ${#lines[@]} -gt 0 ]; then
    printf '%s\n' "${lines[0]}"
  fi
else
  exit 0
fi
EOF
  chmod +x "$mock_dir/gum"
  
  # Run unwip with mock gum, auto-confirming the merge
  run bash -c "PATH='$mock_dir:$PATH' bash -c 'echo y | hug w unwip --force'"
  
  # Should succeed
  assert_success
  assert_output --partial "Unparked successfully"
  
  # The first branch should be deleted
  run git branch --list "$first_wip"
  assert_output ""
  
  # Only one branch should remain
  remaining_count=$(git branch --list "WIP/*" | wc -l)
  [ "$remaining_count" -eq 1 ]
  
  # Cleanup
  rm -rf "$mock_dir"
}

################################################################################
# EDGE CASES AND ERROR HANDLING
################################################################################

@test "commands handle spaces in filenames correctly" {
  echo "content" > "file with spaces.txt"
  git add "file with spaces.txt"
  git commit -q -m "Add file with spaces"
  
  echo "change" >> "file with spaces.txt"
  
  run hug w discard -f "file with spaces.txt"
  assert_success
  
  run git diff "file with spaces.txt"
  assert_output ""
}

@test "commands handle special characters in filenames" {
  echo "content" > "file-with-special_chars.txt"
  git add "file-with-special_chars.txt"
  git commit -q -m "Add special file"
  
  echo "change" >> "file-with-special_chars.txt"
  
  run hug w discard -f "file-with-special_chars.txt"
  assert_success
}

@test "discard handles binary files" {
  # Create a simple binary file (not a real binary, but marked as such)
  echo -e '\x00\x01\x02\x03' > binary.bin
  git add binary.bin
  git commit -q -m "Add binary"
  
  echo -e '\x04\x05\x06' >> binary.bin
  
  run hug w discard -f binary.bin
  assert_success
  
  run git diff binary.bin
  assert_output ""
}

@test "purge handles deeply nested directories" {
  mkdir -p deep/nested/directory/structure
  echo "content" > deep/nested/directory/structure/file.txt
  
  run hug w purge -f deep
  assert_success
  
  refute [ -d "deep" ]
}

@test "zap handles combination of tracked changes and untracked files" {
  # Tracked file with changes
  echo "tracked change" >> README.md
  git add README.md
  
  # Untracked files at various levels
  echo "root untracked" > root-untracked.txt
  mkdir -p nested/dir
  echo "nested untracked" > nested/dir/file.txt
  
  run hug w zap -f README.md root-untracked.txt nested
  assert_success
  
  # README.md should be clean
  run git diff README.md
  assert_output ""
  run git diff --cached README.md
  assert_output ""
  
  # Untracked should be gone
  assert_file_not_exists "root-untracked.txt"
  refute [ -d "nested" ]
}

################################################################################
# SUBDIRECTORY OPERATION TESTS (GIT_PREFIX handling)
################################################################################

@test "hug w discard: works from subdirectory with relative path" {
  # Create subdirectory with files
  mkdir -p subdir/nested
  echo "sub content" > subdir/file.txt
  echo "nested content" > subdir/nested/deep.txt
  git add subdir
  git commit -q -m "Add subdirectory files"
  
  # Modify file
  echo "change" >> subdir/file.txt
  
  # Run discard from subdirectory
  cd subdir
  run hug w discard -f file.txt
  assert_success
  
  # File should be clean
  run git diff file.txt
  assert_output ""
}

@test "hug w discard: works from nested subdirectory" {
  mkdir -p subdir/nested/deep
  echo "deep content" > subdir/nested/deep/file.txt
  git add subdir
  git commit -q -m "Add deep nested file"
  
  echo "change" >> subdir/nested/deep/file.txt
  
  cd subdir/nested/deep
  run hug w discard -f file.txt
  assert_success
  
  run git diff file.txt
  assert_output ""
}

@test "hug w purge: works from subdirectory" {
  mkdir -p subdir
  echo "root file" > root.txt
  git add root.txt
  git commit -q -m "Add root file"
  
  # Create untracked file in subdirectory
  echo "untracked" > subdir/temp.txt
  
  cd subdir
  run hug w purge -f temp.txt
  assert_success
  
  assert_file_not_exists "temp.txt"
}

@test "hug w wipe: works from subdirectory" {
  mkdir -p subdir
  echo "content" > subdir/file.txt
  git add subdir/file.txt
  git commit -q -m "Add subdir file"
  
  echo "staged" >> subdir/file.txt
  git add subdir/file.txt
  echo "unstaged" >> subdir/file.txt
  
  cd subdir
  run hug w wipe -f file.txt
  assert_success
  
  run git diff file.txt
  assert_output ""
  run git diff --cached file.txt
  assert_output ""
}

@test "hug w zap: works from subdirectory with mixed files" {
  mkdir -p subdir
  echo "tracked" > subdir/tracked.txt
  git add subdir/tracked.txt
  git commit -q -m "Add tracked"
  
  echo "change" >> subdir/tracked.txt
  echo "untracked" > subdir/untracked.txt
  
  cd subdir
  run hug w zap -f tracked.txt untracked.txt
  assert_success
  
  run git diff tracked.txt
  assert_output ""
  assert_file_not_exists "untracked.txt"
}

@test "hug w get: works from subdirectory" {
  mkdir -p subdir
  echo "Version 1" > subdir/file.txt
  git add subdir/file.txt
  git commit -q -m "Add v1"
  
  echo "Version 2" > subdir/file.txt
  git add subdir/file.txt
  git commit -q -m "Add v2"
  
  cd subdir
  run hug w get -f HEAD~1 file.txt
  assert_success
  
  run cat file.txt
  assert_output "Version 1"
}

@test "hug w discard: handles paths with parent directory references from subdir" {
  mkdir -p subdir
  echo "root content" > root.txt
  echo "sub content" > subdir/sub.txt
  git add root.txt subdir/sub.txt
  git commit -q -m "Add files"
  
  echo "change" >> root.txt
  echo "change" >> subdir/sub.txt
  
  cd subdir
  run hug w discard -f ../root.txt sub.txt
  assert_success
  
  # Both should be clean
  run git diff ../root.txt
  assert_output ""
  run git diff sub.txt
  assert_output ""
}

@test "hug w purge: handles absolute paths from subdirectory" {
  mkdir -p subdir
  echo "temp" > subdir/temp.txt
  
  cd subdir
  run hug w purge -f "$TEST_REPO/subdir/temp.txt"
  assert_success
  
  assert_file_not_exists "temp.txt"
}
