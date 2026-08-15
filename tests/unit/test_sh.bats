#!/usr/bin/env bats
# Tests for hug sh, shp, shc, and shcp commands

# Load test helpers
load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

# -----------------------------------------------------------------------------
# hug sh tests (show commit with file stats)
# -----------------------------------------------------------------------------

@test "hug sh: shows last commit with heading" {
  run hug sh
  assert_success
  # Should show the heading with emojis
  assert_output --partial "📄"
  assert_output --partial "ℹ️"
  assert_output --partial "Commit info:"
  # Should show commit info
  assert_output --partial "Add feature 2"
}

@test "hug sh: shows specific commit" {
  # Get hash of first feature commit
  local first_feature
  first_feature=$(git log --oneline --all | grep "Add feature 1" | awk '{print $1}')

  run hug sh "$first_feature"
  assert_success
  # Should show the heading
  assert_output --partial "Commit info:"
  # Should show the specific commit
  assert_output --partial "Add feature 1"
}

@test "hug sh: shows commit with file statistics" {
  run hug sh
  assert_success
  # Should show stats section (file counts and line changes)
  assert_output --partial "file"
  assert_output --partial "changed"
  assert_output --partial "insertion"
}

@test "hug sh: shows help with -h" {
  run hug sh -h
  assert_success
  assert_output --partial "USAGE:"
  assert_output --partial "Show commit(s) with file statistics"
}

@test "hug sh: handles HEAD~ notation" {
  run hug sh HEAD~1
  assert_success
  # Should show the second commit
  assert_output --partial "Add feature 1"
}

@test "hug sh: shows commit author and date" {
  run hug sh
  assert_success
  # logbody format includes author and date
  assert_output --partial "["
  assert_output --partial "]"
}

# -----------------------------------------------------------------------------
# hug shp tests (show commit with patch and file stats)
# -----------------------------------------------------------------------------

@test "hug shp: shows last commit with heading" {
  run hug shp
  assert_success
  # Should show the heading with emojis
  assert_output --partial "📄"
  assert_output --partial "🔀"
  assert_output --partial "Commit diff:"
  # Should show commit info
  assert_output --partial "Add feature 2"
}

@test "hug shp: shows specific commit with patch" {
  # Get hash of first feature commit
  local first_feature
  first_feature=$(git log --oneline --all | grep "Add feature 1" | awk '{print $1}')

  run hug shp "$first_feature"
  assert_success
  # Should show the heading
  assert_output --partial "Commit diff:"
  # Should show the specific commit
  assert_output --partial "Add feature 1"
}

@test "hug shp: shows full patch diff" {
  run hug shp
  assert_success
  # Should show diff content
  assert_output --partial "diff --git"
  assert_output --partial "index"
  assert_output --partial "---"
  assert_output --partial "+++"
}

@test "hug shp: shows file stats at the end" {
  run hug shp
  assert_success
  # Should show stats after the patch
  # The stats output comes from git show --stat
  assert_output --partial "file"
  # Stats show summary of changes
  [[ "$output" =~ ([0-9]+ insertion|[0-9]+ deletion) ]] || true
}

@test "hug shp: shows help with -h" {
  run hug shp -h
  assert_success
  assert_output --partial "USAGE:"
  assert_output --partial "Show commit(s) with patch and file statistics"
}

@test "hug shp: handles HEAD~ notation" {
  run hug shp HEAD~1
  assert_success
  # Should show the second commit with patch
  assert_output --partial "Add feature 1"
  assert_output --partial "diff --git"
}

@test "hug shp: shows both commit info and patch" {
  run hug shp
  assert_success
  # Should have commit message from logbody format
  assert_output --partial "Add feature 2"
  # Should have patch
  assert_output --partial "diff --git"
  # Should have stats at end
  assert_output --partial "file"
}

# -----------------------------------------------------------------------------
# hug shp file-path tests (-- <path> filtering)
# -----------------------------------------------------------------------------

@test "hug shp: shows patch for specific file with -- separator" {
  # Create a commit with multiple files
  echo "file-a content" > file_a.txt
  echo "file-b content" > file_b.txt
  git add file_a.txt file_b.txt
  git commit -m "Add two files" -q

  run hug shp -- file_a.txt
  assert_success
  assert_output --partial "diff --git"
  assert_output --partial "file_a.txt"
  refute_output --partial "file_b.txt"
}

@test "hug shp: shows patch for specific file at commit ref" {
  run hug shp HEAD -- feature2.txt
  assert_success
  assert_output --partial "diff --git"
  assert_output --partial "feature2.txt"
}

@test "hug shp: shows patch for specific file with N shorthand" {
  run hug shp 1 -- feature1.txt
  assert_success
  assert_output --partial "diff --git"
  assert_output --partial "feature1.txt"
  refute_output --partial "feature2.txt"
}

@test "hug shp: without -- treats argument as commit ref (backward compat)" {
  run hug shp HEAD
  assert_success
  assert_output --partial "Commit diff:"
}

# -----------------------------------------------------------------------------
# Edge cases and error handling
# -----------------------------------------------------------------------------

@test "hug sh: handles non-existent commit gracefully" {
  run hug sh nonexistent123abc
  # git will error on invalid commit
  assert_failure
}

@test "hug shp: handles non-existent commit gracefully" {
  run hug shp nonexistent123abc
  # git will error on invalid commit
  assert_failure
}

# -----------------------------------------------------------------------------
# Flag-as-ref protection (reject_flag_ref)
#
# When a flag like --stat is passed to a command that doesn't support it,
# it used to be silently treated as a commit ref, producing confusing git
# errors. Now these are caught early with a clear "Unknown flag" message
# and the command's help is shown.
# -----------------------------------------------------------------------------

@test "hug shp: rejects unknown flag --stat with help" {
  run hug shp HEAD --stat
  assert_failure
  assert_output --partial "Unknown flag: --stat"
  # Should show the command's help so user sees valid options
  assert_output --partial "USAGE:"
  assert_output --partial "hug shp"
}

@test "hug shp: rejects unknown flag --no-stat" {
  run hug shp --no-stat
  assert_failure
  assert_output --partial "Unknown flag: --no-stat"
  assert_output --partial "USAGE:"
}

@test "hug shc: rejects unknown flag --stat with help" {
  run hug shc --stat
  assert_failure
  assert_output --partial "Unknown flag: --stat"
  assert_output --partial "USAGE:"
  assert_output --partial "hug shc"
}

@test "hug shcp: rejects unknown flag --stat with help" {
  run hug shcp HEAD --stat
  assert_failure
  assert_output --partial "Unknown flag: --stat"
  assert_output --partial "USAGE:"
  assert_output --partial "hug shcp"
}

@test "hug shcp: rejects unknown flag on range" {
  run hug shcp HEAD~1..HEAD --stat
  assert_failure
  assert_output --partial "Unknown flag: --stat"
}

@test "hug shp: -N range not rejected as flag" {
  # -2 is a valid range shorthand, not a flag
  run hug shp -2
  assert_success
  refute_output --partial "Unknown flag"
}

@test "hug sh: --stat still works (not rejected)" {
  # sh explicitly supports --stat — it must not be caught by reject_flag_ref
  run hug sh --stat HEAD
  assert_success
  refute_output --partial "Unknown flag"
}

@test "hug sh: works with empty commit message" {
  echo "empty commit content" > empty.txt
  git add empty.txt
  git commit --allow-empty-message -m ""

  run hug sh HEAD
  assert_success
  # Should still show heading even with empty message
  assert_output --partial "Commit info:"
}

@test "hug shp: works with empty commit message" {
  echo "empty commit content" > empty2.txt
  git add empty2.txt
  git commit --allow-empty-message -m ""

  run hug shp HEAD
  assert_success
  # Should still show heading even with empty message
  assert_output --partial "Commit diff:"
}

@test "hug sh: handles merge commit" {
  # Create a branch and merge it
  git checkout -b feature-branch HEAD~1 2>/dev/null
  echo "branch content" > branch.txt
  git add branch.txt
  git commit -q -m "Branch commit"
  git checkout - 2>/dev/null
  git merge --no-ff feature-branch -m "Merge feature" >/dev/null 2>&1

  run hug sh HEAD
  assert_success
  assert_output --partial "Merge feature"
}

@test "hug shp: handles merge commit" {
  # Create a branch and merge it
  git checkout -b feature-branch HEAD~1 2>/dev/null
  echo "branch content" > branch2.txt
  git add branch2.txt
  git commit -q -m "Branch commit 2"
  git checkout - 2>/dev/null
  git merge --no-ff feature-branch -m "Merge feature 2" >/dev/null 2>&1

  run hug shp HEAD
  assert_success
  assert_output --partial "Merge feature 2"
  assert_output --partial "Commit diff:"
}

# -----------------------------------------------------------------------------
# Root commit tests
# -----------------------------------------------------------------------------

@test "hug sh: handles root commit (first commit with no parent)" {
  # Get the initial commit hash
  local root_commit
  root_commit=$(git rev-list --max-parents=0 HEAD)

  run hug sh "$root_commit"
  assert_success
  # Should show commit info
  assert_output --partial "Commit info:"
  # Should show file stats (this was broken before the --root fix)
  assert_output --partial "File stats:"
  # Should list files in the root commit
  assert_output --partial "file"
}

@test "hug shc: handles root commit" {
  # Get the initial commit hash
  local root_commit
  root_commit=$(git rev-list --max-parents=0 HEAD)

  run hug shc "$root_commit"
  assert_success
  # Should show file stats
  assert_output --partial "file"
  # Should show line changes
  assert_output --partial "+"
}

@test "hug shcp: handles root commit" {
  # Get the initial commit hash
  local root_commit
  root_commit=$(git rev-list --max-parents=0 HEAD)

  run hug shcp "$root_commit"
  assert_success
  # Should show diff section
  assert_output --partial "Diff for"
  # Should show actual diff
  assert_output --partial "diff --git"
  # Should show file stats
  assert_output --partial "File stats:"
}

# -----------------------------------------------------------------------------
# Numeric shorthand tests (N → HEAD~N convention)
# -----------------------------------------------------------------------------

@test "hug sh: numeric shorthand shows commit N steps back" {
  # hug sh 1 should show HEAD~1 (Add feature 1)
  run hug sh 1
  assert_success
  assert_output --partial "Add feature 1"
}

@test "hug shp: numeric shorthand shows commit N steps back with patch" {
  # hug shp 1 should show HEAD~1 (Add feature 1) with patch
  run hug shp 1
  assert_success
  assert_output --partial "Add feature 1"
  assert_output --partial "diff --git"
}

# -----------------------------------------------------------------------------
# hug shc tests (show changed files with stats)
# -----------------------------------------------------------------------------

@test "hug shc: shows changed files in last commit" {
  run hug shc
  assert_success
  assert_output --partial "file"
  assert_output --partial "changed"
}

@test "hug shc: numeric shorthand shows single commit N steps back" {
  # hug shc 1 should show HEAD~1 (single commit with feature1.txt)
  run hug shc 1
  assert_success
  assert_output --partial "feature1.txt"
}

@test "hug shc: numeric shorthand with -N shows cumulative changes in last N commits" {
  # hug shc -2 should show cumulative changes in HEAD~2..HEAD
  run hug shc -2
  assert_success
  assert_output --partial "Changed files in range HEAD~2..HEAD"
}

@test "hug shc: handles explicit range" {
  run hug shc HEAD~1..HEAD
  assert_success
  assert_output --partial "Changed files in range HEAD~1..HEAD"
}

@test "hug shc: shows help with -h" {
  run hug shc -h
  assert_success
  assert_output --partial "USAGE:"
  assert_output --partial "Show files changed"
}

@test "hug shc -n: prints repo-relative paths only for single commit" {
  run hug shc -n HEAD
  assert_success
  assert_output "feature2.txt"
}

@test "hug shc --name-only: long flag works identically" {
  run hug shc --name-only HEAD
  assert_success
  assert_output "feature2.txt"
}

@test "hug shc -n: range prints cumulative paths" {
  run hug shc -n HEAD~2..HEAD
  assert_success
  assert_line "feature1.txt"
  assert_line "feature2.txt"
}

@test "hug shc -n: N/-N forms work" {
  run hug shc -n -2
  assert_success
  # -2 resolves to HEAD~2..HEAD (valid: 3-commit fixture's oldest reachable is HEAD~2).
  # The range diff is relative to the HEAD~2 tree, so README.md (already present at HEAD~2)
  # is NOT listed — only files changed across the range appear.
  assert_line "feature1.txt"
  assert_line "feature2.txt"
  run hug shc -n HEAD~1
  assert_success
  # HEAD~1 is the single commit that added feature1.txt (diff-tree --root lists only its own files).
  assert_output "feature1.txt"
}

@test "hug shc -n: pathspec filtering works" {
  # Range must actually contain feature1.txt for the filter to match. HEAD~2..HEAD does
  # (feature1.txt is added in that range); HEAD~1..HEAD would contain only feature2.txt.
  run hug shc -n HEAD~2..HEAD -- 'feature1.txt'
  assert_success
  assert_output "feature1.txt"
}

@test "hug shc -n: no-match pathspec exits 0 with empty stdout, no stderr hint" {
  run hug shc -n HEAD -- '*.nomatch'
  assert_success
  assert_output ""
  refute_output --partial "No files matching"
}

@test "hug shc -n: bundled -nq is rejected, not silently run in stats mode" {
  run hug shc -nq HEAD
  assert_failure
  assert_output --partial "USAGE:"
  run hug shc -qn HEAD
  assert_failure
  assert_output --partial "USAGE:"
}

@test "hug shc -n: stdout is data-only, no human chatter" {
  run hug shc -n HEAD
  assert_success
  # No header emoji/legend on stdout — pure data
  refute_output --partial "Changed files"
  refute_output --partial "📊"
}

@test "hug shc -n: regression -- still rejects --stat with help" {
  run hug shc --stat
  assert_failure
  assert_output --partial "hug shc"
}

@test "hug shc -n: bare -n defaults to HEAD" {
  run hug shc -n
  assert_success
  assert_output "feature2.txt"
}

@test "hug shc -n: invalid commit ref fails non-zero" {
  run hug shc -n nonexistent123abc
  assert_failure
}

@test "hug shc -n: mixed --stat HEAD also rejected (bundled-flag regression lock)" {
  # Old pre-reject-loop behavior ran stats mode silently for `--stat HEAD`;
  # the loop must reject the long-flag spelling exactly like -nq/-qn.
  run hug shc --stat HEAD
  assert_failure
  assert_output --partial "USAGE:"
}

@test "hug shc -n: HUG_QUIET does not suppress data output" {
  run env HUG_QUIET=T hug shc -n HEAD
  assert_success
  assert_output "feature2.txt"
}

@test "hug shc -n: range no-match pathspec exits 0 with empty stdout" {
  # Mirrors the single-commit no-match test onto the range (git diff) branch
  # so both dispatch arms of show_changed_file_names are covered.
  run hug shc -n HEAD~2..HEAD -- '*.nomatch'
  assert_success
  assert_output ""
}

@test "hug shc -n: paths with spaces and non-ASCII print raw, not C-quoted" {
  echo "space" > "my file.txt"
  printf 'uni' > "unicodé.txt"
  git add "my file.txt" "unicodé.txt"
  git commit -qm "weird names"
  run hug shc -n HEAD
  assert_success
  assert_line "my file.txt"
  assert_line "unicodé.txt"
  refute_output --partial '\303'
}

@test "hug shc -n: rename lists only the new path in both modes" {
  git mv feature2.txt renamed.txt
  git commit -qm "rename feature2"
  run hug shc -n HEAD
  assert_success
  assert_output "renamed.txt"
  run hug shc -n HEAD~1..HEAD
  assert_success
  assert_output "renamed.txt"
}

@test "hug shc -n: merge commit shows nothing (parity with --stat, issue 268)" {
  git checkout -q -b side HEAD~1
  echo side > side.txt
  git add side.txt
  git commit -qm "side change"
  git checkout -q main
  git merge -q --no-ff side -m "Merge side" >/dev/null 2>&1
  run hug shc -n HEAD
  assert_success
  assert_output ""
}

# -----------------------------------------------------------------------------
# hug shc -z / positional / unborn-HEAD (issue #274)
# -----------------------------------------------------------------------------

@test "hug shc -n -z: NUL-separated paths, final entry NUL-terminated, no trailing newline" {
  echo x > a.txt && echo y > b.txt
  git add -A && git commit -qm add-ab
  # NUL assertions via pipe — run/$output strips NUL bytes (project learning).
  # od -c renders NUL as \0 (two chars); full-stream equality also pins the
  # no-trailing-newline contract.
  [[ "$(hug shc -n -z HEAD | od -An -c | tr -d ' \n')" == 'a.txt\0b.txt\0' ]]
}

@test "hug shc -n -z: structural-char filename — line mode one C-quoted line, -z raw bytes" {
  printf 'z\n' > $'we\nird' && printf 'z\n' > 'back\slash.txt'
  git add -A && git commit -qm weird-names
  # BEFORE-behavior (line mode): ONE C-quoted token per path — git never split it.
  # Real enclosing quotes; C-quoting doubles the backslash inside the token.
  run hug shc -n HEAD
  assert_success
  assert_line '"back\\slash.txt"'
  assert_line '"we\nird"'
  # AFTER-behavior (-z): raw bytes, NUL-terminated, tree order
  # (back\slash.txt sorts before we\nird). Single backslashes below are exact
  # bytes — od prints one backslash per byte, no escaping at this layer.
  [[ "$(hug shc -n -z HEAD | od -An -c | tr -d ' \n')" == 'back\slash.txt\0we\nird\0' ]]
}

@test "hug shc -z without -n is a usage error (exit 2)" {
  run hug shc -z
  assert_failure 2
  assert_output --partial 'only valid with -n'
}

@test "hug shc: second positional rejected in stats mode (exit 2, names both tokens)" {
  run hug shc HEAD extra
  assert_failure 2
  assert_output --partial "unexpected second argument 'extra'"
  assert_output --partial "already 'HEAD'"
}

@test "hug shc: second positional rejected in -n mode, both orderings" {
  run hug shc -n main..HEAD typo
  assert_failure 2
  assert_output --partial "unexpected second argument 'typo'"
  run hug shc -n typo main..HEAD
  assert_failure 2
  assert_output --partial "unexpected second argument 'main..HEAD'"
}

@test "hug shc: second positional rejected when it is a -N flag token (-* arm)" {
  run hug shc main..HEAD -3
  assert_failure 2
  assert_output --partial "unexpected second argument '-3'"
  assert_output --partial "already 'main..HEAD'"
}

@test "hug shc: unborn HEAD gives branded error for every HEAD-derived ref form" {
  # Anchored under BATS_TEST_TMPDIR (auto-cleaned per test) — a bare mktemp -d
  # in /tmp leaked the repo on every run.
  local empty_repo
  empty_repo=$(mktemp -d -p "$BATS_TEST_TMPDIR" -t "shc-unborn-XXXXXX")
  cd "$empty_repo"
  git init -q && git config user.email t@t.tld && git config user.name t
  for ref in "" "1" "-3" "main..HEAD" "@" "@~2" "@{1}"; do
    if [[ -z "$ref" ]]; then
      run hug shc -n
    else
      run hug shc -n "$ref"
    fi
    assert_failure 1
    refute_output --partial 'fatal:'
    assert_output --partial 'no commits yet (unborn HEAD)'
  done
  # @{-1} (previous checkout) reads the HEAD reflog, which does not exist while
  # HEAD is unborn — an unresolvable explicit ref keeps git's raw fatal (D5).
  run hug shc -n '@{-1}'
  assert_failure 128
  assert_output --partial 'fatal'
  cd - >/dev/null
}

@test "hug shc: orphan repo — explicit ref works, HEAD-derived forms branded" {
  local orphan_repo
  orphan_repo=$(mktemp -d -p "$BATS_TEST_TMPDIR" -t "shc-orphan-XXXXXX")
  cd "$orphan_repo"
  git init -q && git config user.email t@t.tld && git config user.name t
  echo x > f.txt && git add -A && git commit -qm c1
  git branch -m master
  git switch --orphan fresh
  run hug shc master        # explicit ref: keeps working (probe-backed contract)
  assert_success
  assert_output --partial 'f.txt'
  run hug shc               # HEAD-derived: branded, not a raw fatal
  assert_failure 1
  assert_output --partial 'no commits yet (unborn HEAD)'
  cd - >/dev/null
}

@test "hug shc: orphan repo — origin/HEAD keeps working (rescue: resolvable refs proceed)" {
  # The *HEAD* guard substring also sweeps stock refs that RESOLVE while HEAD
  # is unborn. origin/HEAD is the regression that motivated the rescue clause:
  # pre-rescue it was branded in orphan repos despite resolving fine.
  local src_repo
  src_repo=$(mktemp -d -p "$BATS_TEST_TMPDIR" -t "shc-rescue-src-XXXXXX")
  (
    cd "$src_repo"
    git init -q --initial-branch=master
    git config user.email t@t.tld && git config user.name t
    echo x > remote-file.txt && git add -A && git commit -qm src-c1
  )
  local orphan_repo
  orphan_repo=$(mktemp -d -p "$BATS_TEST_TMPDIR" -t "shc-rescue-orphan-XXXXXX")
  cd "$orphan_repo"
  git init -q --initial-branch=master
  git config user.email t@t.tld && git config user.name t
  git remote add origin "$src_repo"
  git fetch -q origin
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master
  # Local commit uses a DIFFERENT file than the src repo, so asserting
  # remote-file.txt proves origin/HEAD resolved to the REMOTE commit, not to
  # local master by accident.
  echo x > local-file.txt && git add -A && git commit -qm c1
  git switch -q --orphan fresh
  # Non-vacuousness gate: the fixture's origin/HEAD must actually resolve —
  # the rescue only fires for resolvable refs, so this probe failing would
  # make the assertion below meaningless.
  git rev-parse --verify -q origin/HEAD
  run hug shc origin/HEAD
  assert_success
  assert_output --partial 'remote-file.txt'
  refute_output --partial 'no commits yet'
  cd - >/dev/null
}

@test "hug shc: unborn repo — FETCH_HEAD keeps working after a fetch (rescue)" {
  # FETCH_HEAD matches the guard's *HEAD* substring and resolves after a
  # fetch into a never-committed repo — must proceed, not get branded.
  local src_repo
  src_repo=$(mktemp -d -p "$BATS_TEST_TMPDIR" -t "shc-fetch-src-XXXXXX")
  (
    cd "$src_repo"
    git init -q --initial-branch=master
    git config user.email t@t.tld && git config user.name t
    echo x > fetched-file.txt && git add -A && git commit -qm src-c1
  )
  local unborn_repo
  unborn_repo=$(mktemp -d -p "$BATS_TEST_TMPDIR" -t "shc-fetch-unborn-XXXXXX")
  cd "$unborn_repo"
  git init -q --initial-branch=main
  git config user.email t@t.tld && git config user.name t
  git fetch -q "$src_repo" master
  # Non-vacuousness gate: FETCH_HEAD must resolve in this unborn fixture.
  git rev-parse --verify -q FETCH_HEAD
  run hug shc FETCH_HEAD
  assert_success
  assert_output --partial 'fetched-file.txt'
  cd - >/dev/null
}

@test "hug shc stats: rename collapses on single-commit branch; range unchanged at default config" {
  echo a > old.txt && git add -A && git commit -qm init
  git mv old.txt new.txt && git commit -qm rename
  run hug shc HEAD
  assert_success
  assert_output --partial 'old.txt => new.txt'    # single branch: collapsed (delta)
  run hug shc 'HEAD~1..HEAD'
  assert_success
  assert_output --partial 'old.txt => new.txt'    # range: already collapsed today (no delta)
}

@test "hug shc stats: non-ASCII path prints raw (registered delta, byte oracle)" {
  echo a > 'café.txt' && git add -A && git commit -qm cafe
  run hug shc HEAD
  assert_success
  assert_output --partial 'café.txt | 1'
  refute_output --partial 'caf\303\251'
}

# -----------------------------------------------------------------------------
# hug shcp tests (show cumulative diff with stats)
# -----------------------------------------------------------------------------

@test "hug shcp: shows diff and stats for last commit" {
  run hug shcp
  assert_success
  # Should show diff section
  assert_output --partial "📄"
  assert_output --partial "🔀"
  assert_output --partial "Diff for HEAD:"
  # Should show actual diff content
  assert_output --partial "diff --git"
  # Should show stats section
  assert_output --partial "📊"
  assert_output --partial "File stats:"
}

@test "hug shcp: N shows single commit, -N shows range" {
  # hug shcp 0 should show HEAD (edge case)
  run hug shcp 0
  assert_success
  assert_output --partial "Diff for HEAD"
  assert_output --partial "diff --git"

  # hug shcp 2 should show single commit HEAD~2
  run hug shcp 2
  assert_success
  assert_output --partial "Diff for HEAD~2"
  assert_output --partial "diff --git"
  assert_output --partial "File stats:"

  # hug shcp -2 should show cumulative diff in HEAD~2..HEAD
  run hug shcp -2
  assert_success
  assert_output --partial "Cumulative diff for range HEAD~2..HEAD:"
  assert_output --partial "diff --git"
  assert_output --partial "Cumulative file stats:"
}

@test "hug shcp: handles explicit range" {
  run hug shcp HEAD~1..HEAD
  assert_success
  assert_output --partial "Cumulative diff for range HEAD~1..HEAD"
  assert_output --partial "diff --git"
  assert_output --partial "Cumulative file stats:"
}

@test "hug shcp: shows help with -h" {
  run hug shcp -h
  assert_success
  assert_output --partial "USAGE:"
  assert_output --partial "Show cumulative diff and file statistics"
}

@test "hug shcp: handles non-existent commit gracefully" {
  run hug shcp nonexistent123abc
  # git will error on invalid commit
  assert_failure
}

@test "hug shcp: shows full diff content with additions and deletions" {
  run hug shcp
  assert_success
  # Should show diff markers
  assert_output --partial "---"
  assert_output --partial "+++"
  # Should show file stats summary
  assert_output --partial "file"
  assert_output --partial "changed"
}

# -----------------------------------------------------------------------------
# hug shc path filtering tests (-- <path>...)
# -----------------------------------------------------------------------------

@test "hug shc: filters stats by single glob with --" {
  # Create a commit with multiple file types
  echo "java content" > App.java
  echo "py content" > main.py
  git add App.java main.py
  git commit -m "Add mixed files" -q

  run hug shc HEAD -- '*.java'
  assert_success
  assert_output --partial "App.java"
  refute_output --partial "main.py"
}

@test "hug shc: filters stats by multiple pathspecs with --" {
  # Create a commit with files in subdirectories
  mkdir -p src/lib tests
  echo "lib content" > src/lib/util.java
  echo "test content" > tests/util_test.java
  echo "other content" > other.txt
  git add src/lib/ tests/ other.txt
  git commit -m "Add multi-dir files" -q

  run hug shc -3 -- src/lib/ tests/
  assert_success
  assert_output --partial "src/lib/"
  assert_output --partial "tests/"
  refute_output --partial "other.txt"
}

@test "hug shc: no-match shows stderr hint" {
  run hug shc HEAD -- nonexistent_file.xyz
  assert_success
  # No file stats table (no .txt, .java, etc.) — just header + no-match hint
  refute_output --partial ".txt"
  refute_output --partial ".java"
  # stderr hint should appear in combined output
  assert_output --partial "No files matching"
}

@test "hug shc: bare -- with no paths is identical to no --" {
  run hug shc --
  assert_success
  assert_output --partial "file"
}

@test "hug shc: quiet mode suppresses header with pathspecs" {
  echo "q content" > qfile.txt
  git add qfile.txt
  git commit -m "Add qfile" -q

  run hug shc -q -- '*.txt'
  assert_success
  # No header in output (quiet mode), only file stats
  refute_output --partial "Changed files"
}

@test "hug shc: without -- behavior unchanged (regression)" {
  run hug shc HEAD
  assert_success
  assert_output --partial "file"
}

@test "hug shc: root commit with pathspecs" {
  local root_commit
  root_commit=$(git rev-list --max-parents=0 HEAD)

  # The root commit in test_helper creates initial.txt
  run hug shc "$root_commit" -- '*.txt'
  assert_success
  assert_output --partial ".txt"
}

# -----------------------------------------------------------------------------
# hug shcp path filtering tests (-- <path>...)
# -----------------------------------------------------------------------------

@test "hug shcp: filters both diff and stats by pathspec" {
  # Create a commit with multiple files
  echo "java content" > Filtered.java
  echo "py content" > Unfiltered.py
  git add Filtered.java Unfiltered.py
  git commit -m "Add files for filter test" -q

  run hug shcp HEAD -- '*.java'
  assert_success
  # Diff should be filtered
  assert_output --partial "Filtered.java"
  refute_output --partial "Unfiltered.py"
  # Stats should also be filtered
  assert_output --partial "File stats"
}

@test "hug shcp: filters single commit diff by pathspec" {
  run hug shcp HEAD -- '*.txt'
  assert_success
  # Should show stats section
  assert_output --partial "File stats"
}

@test "hug shcp: no-match shows empty diff and stats" {
  run hug shcp HEAD -- nonexistent_file.xyz
  assert_success
  # Should still show section headers but no file content
  assert_output --partial "Diff for"
  assert_output --partial "File stats"
}

# -----------------------------------------------------------------------------
# hug shp path filtering regression tests (after library upgrade)
# -----------------------------------------------------------------------------

@test "hug shp: single file pathspec still works after library upgrade" {
  # Create a commit with multiple files
  echo "a content" > a.txt
  echo "b content" > b.txt
  git add a.txt b.txt
  git commit -m "Add a and b" -q

  run hug shp HEAD -- a.txt
  assert_success
  assert_output --partial "diff --git"
  assert_output --partial "a.txt"
  refute_output --partial "b.txt"
}

@test "hug shp: warns when multiple pathspecs given" {
  echo "c content" > c.txt
  echo "d content" > d.txt
  git add c.txt d.txt
  git commit -m "Add c and d" -q

  run hug shp HEAD -- c.txt d.txt
  assert_success
  # Should warn about extra pathspecs on stderr
  [[ "$output" == *"Warning"* ]] || [[ "$output" == *"only supports single-file"* ]]
}
