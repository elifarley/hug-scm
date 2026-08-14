#!/usr/bin/env bats
# Tests for hug-git-commit library: commit range analysis functions

load '../test_helper'
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-git-repo'
load '../../git-config/lib/hug-git-commit'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
  
  # Create a few commits for testing
  echo "first" > file1.txt
  git add file1.txt
  git commit -q -m "first commit"
  
  echo "second" > file2.txt
  git add file2.txt
  git commit -q -m "second commit"
  
  echo "third" > file3.txt
  git add file3.txt
  git commit -q -m "third commit"
}

teardown() {
  cleanup_test_repo
}

################################################################################
# count_commits_in_range TESTS
################################################################################

@test "count_commits_in_range: counts commits between two refs" {
  run count_commits_in_range HEAD~2 HEAD
  assert_success
  assert_output "2"
}

@test "count_commits_in_range: returns 0 for same ref" {
  run count_commits_in_range HEAD HEAD
  assert_success
  assert_output "0"
}

@test "count_commits_in_range: uses HEAD as default end" {
  run count_commits_in_range HEAD~1
  assert_success
  assert_output "1"
}

################################################################################
# commit_offset TESTS
################################################################################

@test "commit_offset: ancestor pair -> stdout=N (b ahead of a)" {
  run commit_offset HEAD~2 HEAD
  assert_success
  assert_output "2"
}

@test "commit_offset: descendant pair -> stdout=-N (b behind a)" {
  run commit_offset HEAD HEAD~2
  assert_success
  assert_output "-2"
}

@test "commit_offset: identity -> stdout=0 exit=0" {
  run commit_offset HEAD HEAD
  assert_success
  assert_output "0"
}

@test "commit_offset: diverged -> empty stdout, exit 2" {
  git switch -q -c side HEAD~1
  echo x > side.txt; git add side.txt; git commit -qm "side commit"
  git switch -q -
  # bats' default `run` MERGES stderr into $output. commit_offset emits nothing
  # on stdout for the diverged case (the contract: empty + distinct exit code),
  # but git's rev-list may write to stderr; --separate-stderr keeps $output =
  # stdout ONLY so we assert the real contract.
  bats_require_minimum_version 1.5.0
  run --separate-stderr commit_offset side HEAD
  [ "$status" -eq 2 ]
  assert_output ""
}

@test "commit_offset: invalid ref -> empty stdout, exit 3 (never a fake 0)" {
  # STRICT: an unresolvable ref is exit 3 with EMPTY stdout — the lossy
  # `|| echo 0` swallow of Defect 2 is gone by construction.
  bats_require_minimum_version 1.5.0
  run --separate-stderr commit_offset NO_SUCH_REF HEAD
  [ "$status" -eq 3 ]
  assert_output ""
}

@test "commit_offset: missing args -> fails fast via \${1:?}" {
  run commit_offset
  assert_failure
}

################################################################################
# is_same_commit TESTS
################################################################################

@test "is_same_commit: same SHA -> exit 0" {
  run is_same_commit HEAD HEAD
  assert_success
}

@test "is_same_commit: ancestor (not equal) -> non-zero" {
  run is_same_commit HEAD~1 HEAD
  assert_failure
}

@test "is_same_commit: descendant (not equal) -> non-zero" {
  local descendant; descendant=$(git rev-parse HEAD)
  git reset -q --hard HEAD~1
  run is_same_commit "$descendant" HEAD
  assert_failure
}

@test "is_same_commit: invalid ref -> non-zero (never a false positive)" {
  run is_same_commit NO_SUCH_REF HEAD
  assert_failure
}

@test "is_same_commit: unborn repo (no commits) -> non-zero (false NEGATIVE, documented)" {
  # create_test_repo auto-commits an "Initial commit", so it is NOT unborn.
  # Build a genuinely commit-less repo: mktemp -d yields the path (git init -q
  # prints nothing to stdout, so it must NOT be captured for the path).
  local empty_repo; empty_repo=$(mktemp -d)
  git init -q "$empty_repo"
  cd "$empty_repo"
  run is_same_commit HEAD HEAD
  assert_failure
  cd "$TEST_REPO"
  rm -rf "$empty_repo"
}

@test "is_same_commit: missing second arg -> fails fast via \${2:?}" {
  run is_same_commit HEAD
  assert_failure
}

################################################################################
# count_commits_in_range STRICTNESS TESTS (Defect 2)
################################################################################

@test "count_commits_in_range: invalid start -> non-zero, empty stdout (strict, no swallow)" {
  bats_require_minimum_version 1.5.0
  run --separate-stderr count_commits_in_range NO_SUCH_REF HEAD
  assert_failure
  assert_output ""        # stdout empty (git's fatal: is on stderr, deliberately uncaptured)
}

@test "count_commits_in_range: missing start arg -> fails fast via \${1:?}" {
  run count_commits_in_range
  assert_failure
}

################################################################################
# count_commits_in_range_or_zero TESTS (named display wrapper)
################################################################################

@test "count_commits_in_range_or_zero: valid range -> same as strict count" {
  run count_commits_in_range_or_zero HEAD~2 HEAD
  assert_success
  assert_output "2"
}

@test "count_commits_in_range_or_zero: single arg defaults end to HEAD" {
  # The wrapper forwards "$@" verbatim, so the strict function's ${2:-HEAD} default must
  # still apply through the passthrough: a lone start ref counts commits from <start> to
  # HEAD. setup() makes 3 commits, so HEAD~1 -> 1.
  run count_commits_in_range_or_zero HEAD~1
  assert_success
  assert_output "1"
}

@test "count_commits_in_range_or_zero: invalid start -> echoes 0, exit 0 (cosmetic)" {
  # The wrapper swallows the FAILURE (non-zero exit -> cosmetic 0 on stdout), but git's
  # `fatal: ambiguous argument` diagnostic still goes to STDERR. bats' default `run` MERGES
  # stderr into $output, which would make `assert_output "0"` see that 3-line diagnostic + "0".
  # The contract under test is stdout == "0" + exit 0, so split stderr out (same house pattern
  # as the strict invalid-ref tests above; --separate-stderr needs bats >= 1.5).
  bats_require_minimum_version 1.5.0
  run --separate-stderr count_commits_in_range_or_zero NO_SUCH_REF HEAD
  assert_success
  assert_output "0"
}

################################################################################
# list_changed_files_in_range TESTS
################################################################################

@test "list_changed_files_in_range: lists changed files" {
  run list_changed_files_in_range HEAD~2 HEAD
  assert_success
  assert_line "file2.txt"
  assert_line "file3.txt"
}

@test "list_changed_files_in_range: returns empty for same ref" {
  run list_changed_files_in_range HEAD HEAD
  assert_success
  assert_output ""
}

################################################################################
# count_changed_files_in_range TESTS
################################################################################

@test "count_changed_files_in_range: counts changed files" {
  run count_changed_files_in_range HEAD~2 HEAD
  assert_success
  assert_output "2"
}

@test "count_changed_files_in_range: returns 0 for same ref" {
  run count_changed_files_in_range HEAD HEAD
  assert_success
  assert_output "0"
}

################################################################################
# resolve_temporal_to_commit TESTS
################################################################################

@test "resolve_temporal_to_commit: resolves relative time (days ago)" {
  # Create commits with specific dates
  echo "old" > old.txt
  git add old.txt
  GIT_COMMITTER_DATE="2024-01-01 10:00:00" GIT_AUTHOR_DATE="2024-01-01 10:00:00" \
    git commit -q -m "Old commit"
  
  echo "recent" > recent.txt
  git add recent.txt
  GIT_COMMITTER_DATE="2024-01-15 10:00:00" GIT_AUTHOR_DATE="2024-01-15 10:00:00" \
    git commit -q -m "Recent commit"
  
  # Should find first commit at or after 10 days before HEAD (Jan 15 - 10 days = Jan 5)
  # First commit on/after Jan 5 is the Jan 15 commit
  run resolve_temporal_to_commit "10 days ago" HEAD
  assert_success
  
  # Verify it returns a valid commit hash
  local commit_hash
  commit_hash="$output"
  run git rev-parse --verify "$commit_hash"
  assert_success
}

@test "resolve_temporal_to_commit: resolves relative time (weeks ago)" {
  echo "week1" > week1.txt
  git add week1.txt
  GIT_COMMITTER_DATE="2024-01-01 10:00:00" GIT_AUTHOR_DATE="2024-01-01 10:00:00" \
    git commit -q -m "Week 1"
  
  echo "week2" > week2.txt
  git add week2.txt
  GIT_COMMITTER_DATE="2024-01-15 10:00:00" GIT_AUTHOR_DATE="2024-01-15 10:00:00" \
    git commit -q -m "Week 2"
  
  run resolve_temporal_to_commit "1 week ago" HEAD
  assert_success
  
  # Verify it returns a valid commit hash
  local commit_hash
  commit_hash="$output"
  run git rev-parse --verify "$commit_hash"
  assert_success
}

@test "resolve_temporal_to_commit: resolves absolute date" {
  echo "jan1" > jan1.txt
  git add jan1.txt
  GIT_COMMITTER_DATE="2024-01-01 10:00:00" GIT_AUTHOR_DATE="2024-01-01 10:00:00" \
    git commit -q -m "Jan 1"
  
  echo "jan15" > jan15.txt
  git add jan15.txt
  GIT_COMMITTER_DATE="2024-01-15 10:00:00" GIT_AUTHOR_DATE="2024-01-15 10:00:00" \
    git commit -q -m "Jan 15"
  
  # Should find first commit on or after 2024-01-10
  run resolve_temporal_to_commit "2024-01-10" HEAD
  assert_success
  
  # Verify it returns a valid commit hash
  local commit_hash
  commit_hash="$output"
  run git rev-parse --verify "$commit_hash"
  assert_success
}

@test "resolve_temporal_to_commit: fails when no commits found" {
  # Try to find commits from far in the future
  run resolve_temporal_to_commit "2099-01-01" HEAD
  assert_failure
  assert_output --partial "Unable to parse time specification '2099-01-01' or no commits found after that time"
}

@test "resolve_temporal_to_commit: uses HEAD as default reference" {
  echo "test" > test.txt
  git add test.txt
  GIT_COMMITTER_DATE="2024-01-15 10:00:00" GIT_AUTHOR_DATE="2024-01-15 10:00:00" \
    git commit -q -m "Test commit"
  
  # Should work without explicit reference
  run resolve_temporal_to_commit "5 days ago"
  assert_success
}

@test "resolve_temporal_to_commit: handles various time units" {
  echo "test" > test.txt
  git add test.txt
  GIT_COMMITTER_DATE="2024-01-15 10:00:00" GIT_AUTHOR_DATE="2024-01-15 10:00:00" \
    git commit -q -m "Test commit"
  
  # Test different time units (should not error)
  run resolve_temporal_to_commit "1 hour ago"
  assert_success
  
  run resolve_temporal_to_commit "30 minutes ago"
  assert_success
  
  run resolve_temporal_to_commit "1 month ago"
  assert_success
}

################################################################################
# parse_temporal_flag TESTS
################################################################################

@test "parse_temporal_flag: parses -t flag with time spec" {
  eval "$(parse_temporal_flag -t "3 days ago" some other args)"
  
  assert_equal "$temporal_spec" "3 days ago"
  assert_equal "$1" "some"
  assert_equal "$2" "other"
  assert_equal "$3" "args"
}

@test "parse_temporal_flag: parses --temporal flag" {
  eval "$(parse_temporal_flag --temporal "1 week ago" remaining)"
  
  assert_equal "$temporal_spec" "1 week ago"
  assert_equal "$1" "remaining"
}

@test "parse_temporal_flag: errors when -t missing time spec" {
  run bash -c "cd $TEST_REPO && source $HUG_HOME/git-config/lib/hug-common && source $HUG_HOME/git-config/lib/hug-git-commit && eval \"\$(parse_temporal_flag -t)\""
  assert_failure
  assert_output --partial "requires a time specification"
}

@test "parse_temporal_flag: errors when -t followed by flag" {
  run bash -c "cd $TEST_REPO && source $HUG_HOME/git-config/lib/hug-common && source $HUG_HOME/git-config/lib/hug-git-commit && eval \"\$(parse_temporal_flag -t --force)\""
  assert_failure
  assert_output --partial "requires a time specification"
}

@test "parse_temporal_flag: preserves other arguments" {
  eval "$(parse_temporal_flag arg1 -t "time spec" arg2 --flag arg3)"
  
  assert_equal "$temporal_spec" "time spec"
  assert_equal "$1" "arg1"
  assert_equal "$2" "arg2"
  assert_equal "$3" "--flag"
  assert_equal "$4" "arg3"
}

@test "parse_temporal_flag: handles no temporal flag" {
  eval "$(parse_temporal_flag arg1 arg2)"
  
  assert_equal "$temporal_spec" ""
  assert_equal "$1" "arg1"
  assert_equal "$2" "arg2"
}

################################################################################
# resolve_target_with_temporal TESTS
################################################################################

@test "resolve_target_with_temporal: resolves explicit target" {
  run resolve_target_with_temporal false "" "HEAD~1" "HEAD~2"
  assert_success
  
  # Should resolve to HEAD~1's commit hash
  expected=$(git rev-parse HEAD~1)
  assert_output "$expected"
}

@test "resolve_target_with_temporal: uses default when no args" {
  run resolve_target_with_temporal false "" "" "HEAD~1"
  assert_success
  
  expected=$(git rev-parse HEAD~1)
  assert_output "$expected"
}

@test "resolve_target_with_temporal: resolves temporal spec" {
  # Create a commit with known date
  echo "test" > test.txt
  git add test.txt
  GIT_COMMITTER_DATE="2024-01-15 10:00:00" GIT_AUTHOR_DATE="2024-01-15 10:00:00" \
    git commit -q -m "Test commit"
  
  run resolve_target_with_temporal false "5 days ago" "" "HEAD~1"
  assert_success
  # Should return a commit hash
  [[ "$output" =~ ^[0-9a-f]{40}$ ]] || fail "Expected 40-char commit hash, got: $output"
}

@test "resolve_target_with_temporal: rejects upstream + target" {
  run resolve_target_with_temporal true "" "HEAD~1" "HEAD~2"
  assert_failure
  assert_output --partial "Cannot specify both --upstream and a target"
}

@test "resolve_target_with_temporal: rejects upstream + temporal" {
  run resolve_target_with_temporal true "3 days ago" "" "HEAD~2"
  assert_failure
  assert_output --partial "Cannot specify both --upstream and --temporal"
}

@test "resolve_target_with_temporal: rejects temporal + target" {
  run resolve_target_with_temporal false "3 days ago" "HEAD~1" "HEAD~2"
  assert_failure
  assert_output --partial "Cannot specify both --temporal and a target"
}

################################################################################
# get_first_child_commit TESTS
################################################################################

@test "get_first_child_commit: returns first child commit under pipefail (SIGPIPE regression)" {
  # The default setup creates 3 commits. Re-use them to build a linear history
  # where we know the parent-child relationship.
  # Setup: first (HEAD~2) <- second (HEAD~1) <- third (HEAD)
  local parent
  parent=$(git rev-parse HEAD~1)
  local child
  child=$(git rev-parse HEAD)

  # Must return the immediate child of parent, even under pipefail
  run bash -c "set -o pipefail; source '$HUG_HOME/git-config/lib/hug-common'; source '$HUG_HOME/git-config/lib/hug-git-repo'; source '$HUG_HOME/git-config/lib/hug-git-commit'; get_first_child_commit '$parent'"
  assert_success
  assert_output "$child"
}

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
  check_intent 1 -m ''                    # empty candidate, source present → CHANGE
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

@test "amend_args_message_intent: attached forms classify same as space forms" {
  # --message=X mirrors -m X (CHANGE when candidate differs, KEEP when equal)
  check_intent 1 --message=x
  check_intent 0 --no-edit --message="third commit"

  # --file=X mirrors -F X (candidate is the file's content)
  git log -1 --format=%B > ident.txt
  check_intent 0 --no-edit --file=ident.txt
  printf 'different\n' > diff.txt
  check_intent 1 --no-edit --file=diff.txt

  # --trailer=X mirrors --trailer X (absent trailer → CHANGE)
  check_intent 1 --no-edit --trailer="Co-Authored-By: x <x@x>"
}

@test "amend_args_message_intent: multi -m concatenates paragraphs (candidate join)" {
  # -m a -m b produces "a\n\nb" — a candidate that CAN equal HEAD's message
  git commit -q --amend -m "$(printf 'x\n\ny')"
  check_intent 0 --no-edit -m x -m y
}

@test "amend_args_message_intent: unborn HEAD is silent (no git stderr leak)" {
  # Regression (#263 review): on an unborn branch, resolving HEAD for the
  # candidate message fails. The guard must not leak git's
  # `fatal: ambiguous argument 'HEAD'` to stderr before the caller's exit-3
  # refusal — silence it with 2>/dev/null.
  local empty
  empty=$(mktemp -d -p "$BATS_TEST_TMPDIR" -t "hug-unborn-XXXXXX")
  git init -q --initial-branch=main "$empty"
  cd "$empty"
  git config --local user.email "test@hug-scm.test"
  git config --local user.name "Hug Test"
  run amend_args_message_intent --no-edit
  assert_success
  refute_output --partial "fatal:"
  refute_output --partial "ambiguous argument"
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

@test "guard_content_null_amend: fail-open on corrupt index in tracked mode (rc>1 proceeds)" {
  # Tracked mode runs `git diff HEAD` (worktree+index vs HEAD), which exits
  # 128 on a corrupt index. The guard must fail OPEN (return 0) for rc>1 —
  # never refuse on a broken index.
  echo "garbage" > .git/index
  run guard_content_null_amend tracked --no-edit
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

@test "guard_content_null_amend: --template value is skipped (not a bare path)" {
  # Regression (#263 review): the bare-path value-skip list omitted the long
  # `--template <file>` space form (only `-t` was listed). The file after
  # --template must be consumed as its value, not collected as a bare
  # pathspec — else a worktree-modified template file makes
  # `git diff HEAD -- <file>` exit 1 and lets the guard PROCEED into a no-op
  # amend (silent hash churn).
  echo "worktree edit" >> file1.txt   # tracked file, modified in worktree
  # Clean index + KEEP message + template value consumed ⇒ refuse (exit 3).
  # If file1.txt were misread as a path, the diff check would see the
  # worktree modification and proceed (return 0).
  run guard_content_null_amend staged --no-edit --template file1.txt
  [ "$status" -eq 3 ]
}
