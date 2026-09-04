#!/usr/bin/env bats
# Simple test suite for file input enhancements to hug commands

load '../test_helper'

setup() {
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"
}

@test "hug a: supports --from-file flag" {
  # Create test files
  echo "content1" > file1.txt
  echo "content2" > file2.txt
  echo "content3" > file3.txt

  # Create a file list
  echo -e "file1.txt\nfile3.txt" > files.txt

  # Add files using --from-file
  run hug a --from-file files.txt

  assert_success
  # Check that only files from the list were staged
  run hug sl
  assert_output --partial "file1.txt"
  assert_output --partial "file3.txt"
  refute_output --partial "file2.txt"
}

@test "hug a: supports --from-commit flag" {
  # Create and commit initial files
  echo "content1" > file1.txt
  echo "content2" > file2.txt
  hug add file1.txt file2.txt
  hug c -m "Initial commit"

  # Modify the files
  echo "modified1" > file1.txt
  echo "modified2" > file2.txt

  # Add files from the initial commit
  run hug a --from-commit HEAD

  assert_success
  # Check that both files were staged
  run hug sl
  assert_output --partial "file1.txt"
  assert_output --partial "file2.txt"
}

@test "hug a: --from-commit stages RAW structural-char filenames end-to-end (NUL transport, #285)" {
  # Structural-char fixture: line-mode extraction C-quoted these names
  # ("back\slash.txt", "we\nird"), so hug a staged the QUOTED tokens — the
  # real files never got staged. Acceptance oracle is byte-level: after the
  # run, the index must list the RAW paths exactly as git's own -z
  # name-only stream reports them (tree order: b < p < w).
  echo x > 'back\slash.txt'
  echo y > $'we\nird'
  echo z > plain.txt
  git add -A
  git commit -qm weird

  # Re-staging files identical to HEAD is a no-op (empty index diff), so
  # modify contents first — same observable-staging pattern as the test
  # above.
  echo x2 > 'back\slash.txt'
  echo y2 > $'we\nird'
  echo z2 > plain.txt

  run hug a --from-commit HEAD
  assert_success

  # Byte-level oracle, immune to $output's NUL stripping.
  git diff --cached --name-only -z > "$BATS_TMPDIR/staged_weird.$$"
  printf 'back\\slash.txt\0plain.txt\0we\nird\0' > "$BATS_TMPDIR/staged_weird_expected.$$"
  run cmp -s "$BATS_TMPDIR/staged_weird.$$" "$BATS_TMPDIR/staged_weird_expected.$$"
  assert_success
  rm -f "$BATS_TMPDIR/staged_weird.$$" "$BATS_TMPDIR/staged_weird_expected.$$"
}

@test "hug a: --from-commit <bogus> fails loudly (guard-fatal contract, #285)" {
  # Pre-#285 the process-substitution subshell contained error()'s exit:
  # the commit error PRINTED, then `hug a` answered "No files to stage."
  # with exit 0 — automation read a failed stage as success (the same bug
  # class codex P2 fixed for `hug us`). The guard contract is now fatal in
  # every --from-commit consumer.
  local repo
  repo=$(create_test_repo)
  cd "$repo"
  echo a > a.txt

  run hug a --from-commit DOES_NOT_EXIST
  assert_failure
  [[ "$status" -eq 1 ]]
  assert_output --partial "does not exist"
  refute_output --partial "No files to stage."
}

@test "hug us: supports --from-file flag" {
  # Stage some files
  echo "content1" > file1.txt
  echo "content2" > file2.txt
  hug add file1.txt file2.txt

  # Create a file list to unstage
  echo -e "file1.txt" > files.txt

  # Unstage files using --from-file
  run hug us --from-file files.txt

  assert_success
  # Check that only file1.txt was unstaged
  run hug sl
  refute_output --partial "file1.txt"
  assert_output --partial "file2.txt"
}

@test "hug us: supports --from-commit flag" {
  # Create and commit initial files
  echo "content1" > file1.txt
  echo "content2" > file2.txt
  hug add file1.txt file2.txt
  hug c -m "Initial commit"

  # Modify files and commit again (creates a commit with changes)
  echo "modified1" > file1.txt
  echo "modified2" > file2.txt
  hug add file1.txt file2.txt
  hug c -m "Modify files"

  # Modify the files again so we have something to stage/unstage
  echo "modified3" > file1.txt
  echo "modified4" > file2.txt

  # Stage the modified files
  hug add file1.txt file2.txt

  # Unstage the same files that were changed in the previous commit
  run hug us --from-commit HEAD

  assert_success
  # Check that both files were unstaged (no staged files should be shown)
  run hug sl
  assert_output --partial "📦 Staged: -"  # Should show no staged files
}

@test "hug ccp: supports --husk flag" {
  # Use a timestamp to ensure unique branch name for test isolation
  local branch_name="feature-test-$(date +%s)"

  # Create and commit files in a specific pattern
  echo "content1" > config.json
  echo "content2" > settings.ini
  hug add config.json settings.ini
  hug c -m "Add configuration files"

  # Create new branch
  hug bc "$branch_name"

  # Modify the files with different content
  echo "new config" > config.json
  echo "new settings" > settings.ini

  # Use husk to stage same files with original message
  run hug ccp --husk main

  assert_success
  # Check that the message was reused
  run hug sh
  assert_output --partial "Add configuration files"

  # Check that no files are staged (they were committed by husk)
  run hug sl
  # When no files are staged, hug sl shows only HEAD info
  # Test semantic state (clean) not specific emoji
  assert_hug_s_state "clean"
  assert_output --partial "HEAD:"
}

@test "hug ccp: --husk fails without commit" {
  run hug ccp --husk
  assert_failure
  assert_output --partial "requires a source commit"
}
@test "hug us: --from-commit <bogus> fails loudly with AND without a scope (codex P2)" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"
  echo a > a.txt
  hug a -- a.txt

  # The old 'mapfile < <(extract_files_from_commit …)' swallowed the exit:
  # the commit error PRINTED and both arms then answered a friendly no-match
  # with exit 0 — automation read a failed unstage as success.
  run hug us --from-commit DOES_NOT_EXIST -- .
  assert_failure
  assert_output --partial "Commit 'DOES_NOT_EXIST' does not exist"
  refute_output --partial "Source list is empty"
  refute_output --partial "No files matching"

  run hug us --from-commit DOES_NOT_EXIST
  assert_failure
  assert_output --partial "Commit 'DOES_NOT_EXIST' does not exist"
  refute_output --partial "No staged files to unstage"
}

@test "hug a: scoped picker rejects malformed magic pathspec before the picker (codex P2)" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"
  echo a > a.txt

  # The picker's listing helpers suppress git's failure — without entry
  # validation a malformed spec became an empty candidate list, exit 0.
  run hug a -- ':(bogus)src/' --
  assert_failure
  [[ "$status" -eq 2 ]]
  assert_output --partial "Invalid pathspec"
}

@test "hug us: --from-commit includes a rename's old path in the scope (codex P1)" {
  local repo
  repo=$(create_test_repo)
  cd "$repo"
  echo old > old.txt
  hug a -- old.txt
  hug c -m "add old" >/dev/null 2>&1
  git mv old.txt new.txt

  # Rename detection collapses 'git mv old new' into one R-status change, so
  # the --diff-filter=D membership query missed the old path — "No files
  # matching '.'" exit 0 with the rename still staged. --no-renames splits
  # the D half out so the old path joins the set like any staged deletion.
  run hug us --from-commit HEAD -- .
  assert_success
  assert_output --partial "old.txt"
  # The rename's delete side is unstaged: old.txt back to HEAD in the index.
  run git diff --cached --name-only --diff-filter=D
  refute_output --partial "old.txt"
}
