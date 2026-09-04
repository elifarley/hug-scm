#!/usr/bin/env bats
# Tests for pinned_diff() in git-config/lib/hug-git-diff — the canonical
# pinned changed-files invocation (spec: 2026-08-14-shc-deferred-follow-ups).

load '../test_helper'
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-git-repo' # is_range — hug-common does NOT load it

setup() {
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

# Fixture: c1 adds plain.txt + café.txt; c2 renames plain.txt → renamed.txt
# and appends to café.txt. Non-ASCII AND structural chars where quoting matters.
_make_fixture() {
  echo a > plain.txt
  echo a > 'café.txt'
  echo a > 'back\slash.txt'
  git add -A && git commit -qm c1
  git mv plain.txt renamed.txt
  echo b >> 'café.txt'
  git add -A && git commit -qm c2
}

@test "pinned_diff: single commit dispatches to diff-tree (no commit id line)" {
  _make_fixture
  run pinned_diff --name-only HEAD
  assert_success
  refute_line --partial "$(git rev-parse HEAD)"   # --no-commit-id honored
  assert_line "renamed.txt"                        # display contract: new path only
}

@test "pinned_diff: range dispatches to git diff" {
  _make_fixture
  run pinned_diff --name-only 'HEAD~1..HEAD'
  assert_success
  assert_line "renamed.txt"
  assert_line "café.txt"
}

@test "pinned_diff: --stat is accepted for both branches" {
  _make_fixture
  run pinned_diff --stat HEAD
  assert_success
  assert_output --partial 'renamed.txt'
  run pinned_diff --stat 'HEAD~1..HEAD'
  assert_success
  assert_output --partial 'changed'
}

@test "pinned_diff: --null emits NUL-terminated raw paths (pipe assertion, never \$output)" {
  _make_fixture
  # od -c renders non-ASCII bytes as octal escapes (é → 303 251) and NUL as \0;
  # emission order is tree order (café.txt before renamed.txt). Full-stream
  # equality pins order, NUL termination, no trailing newline, and rawness —
  # C-quoted output would render as "caf\303\251.txt" (visible backslashes),
  # a different string. Fixtures here avoid od's `*` line-dedup (streams
  # under 16 bytes/line or with distinct lines only).
  [[ "$(pinned_diff --null --name-only HEAD | od -An -c | tr -d ' \n')" == 'caf303251.txt\0renamed.txt\0' ]]
}

@test "pinned_diff: --null on the RANGE branch emits NUL-terminated raw paths" {
  _make_fixture
  # Companion to the single-commit --null test above: the range dispatches to
  # `git diff` (NOT diff-tree), a different git code path for -z — no commit-id
  # entry either way, and renames still collapse to the new path. Oracle
  # probed on git 2.34.1; same od-pipe discipline (never $output — NUL).
  [[ "$(pinned_diff --null --name-only 'HEAD~1..HEAD' | od -An -c | tr -d ' \n')" == 'caf303251.txt\0renamed.txt\0' ]]
}

@test "pinned_diff: --null with --stat is rejected (exit 2)" {
  _make_fixture
  run pinned_diff --null --stat HEAD
  assert_failure 2
  assert_output --partial '--null is only valid with --name-only'
}

@test "pinned_diff: leading flags parse in any order (--no-renames before --null)" {
  _make_fixture
  # Order-independence lock: the original two-sequential-checks parser treated
  # a --null arriving AFTER --no-renames as the FORMAT token → misleading
  # "unknown format '--null'" (exit 2). The combo is valid: renames expand to
  # both sides AND paths are NUL-terminated. Oracle probed on git 2.34.1 —
  # tree order (café.txt, plain.txt deleted, renamed.txt added), so this
  # assertion fails against the old parser (empty stream from exit 2).
  [[ "$(pinned_diff --no-renames --null --name-only HEAD | od -An -c | tr -d ' \n')" == 'caf303251.txt\0plain.txt\0renamed.txt\0' ]]
}

@test "pinned_diff: unknown format is rejected (exit 2)" {
  _make_fixture
  # The bogus format is a NON-dash token on purpose: a `-`-prefixed token in
  # the format slot (--patch) is classified as a MISPLACED LEADING FLAG
  # ("leading flags must precede", elifarley/hug-scm#284) — this test pins the
  # remaining class, a garbage non-dash format, which stays "unknown format".
  run pinned_diff patch HEAD
  assert_failure 2
  assert_output --partial 'unknown format'
}

@test "pinned_diff: too few core args is rejected (exit 2, not a bash unbound trace)" {
  _make_fixture
  run pinned_diff --name-only
  assert_failure 2
  assert_output --partial 'expected'
}

@test "pinned_diff: misplaced flag in pathspec position is rejected (exit 2, not silent-empty)" {
  _make_fixture
  # THE silent-empty trap (elifarley/hug-scm#284): `--null` arriving after the
  # resolved_ref is bound as a PATHSPEC literally named "--null" — git diffs
  # nothing, prints nothing, exits 0. For an action-list builder an empty
  # stdout + exit 0 is the worst failure class: every downstream action is
  # silently skipped. Must be a loud exit-2 usage error naming the expected
  # argument order instead.
  run pinned_diff --name-only HEAD --null
  assert_failure 2
  assert_output --partial 'leading flags must precede'
  assert_output --partial "(got '--null')"
}

@test "pinned_diff: misplaced flag in resolved_ref position is rejected (exit 2, not raw git usage)" {
  _make_fixture
  # The loud sibling (elifarley/hug-scm#284): a flag in the resolved_ref slot
  # used to die as git's own usage dump (exit 129/128-class) — incoherent for
  # hug callers expecting the library's exit-2 usage contract. Now rejected
  # BEFORE any git invocation, with the same order-naming message. (No ref or
  # range can start with '-': git check-ref-format refuses it — so a dash
  # token in this slot is always a misplaced flag, never a real ref.)
  run pinned_diff --name-only --null HEAD
  assert_failure 2
  assert_output --partial 'leading flags must precede'
  assert_output --partial "(got '--null')"
}

@test "pinned_diff: post--- pathspecs named like flags still work (escape hatch)" {
  # Regression guard for the guard itself: a `-`-prefixed token AFTER a `--`
  # separator is pathspec DATA, never a flag. Two escape-hatch stances pinned:
  # (1) git tracks files literally named like flags (-weird.txt);
  # (2) parse_pathspecs passes a SECOND `--` through as a literal candidate
  #     element (hug shc HEAD -- -- foo.txt → candidates=(-- foo.txt)), so a
  #     leading `--` element in the candidate list must STOP the guard scan,
  #     not reject. Own fixture: _make_fixture's rename would muddy the
  #     single-commit pathspec story here.
  echo a > plain.txt
  echo a > ./-weird.txt
  git add -A && git commit -qm c1
  run pinned_diff --name-only HEAD -- '-weird.txt'
  assert_success
  assert_line '-weird.txt'
  run pinned_diff --name-only HEAD -- -- '-weird.txt'
  assert_success
  assert_line '-weird.txt'
}

@test "pinned_diff: quotePath pin defeats hostile core.quotePath=true (non-ASCII raw)" {
  _make_fixture
  git config core.quotePath true
  run pinned_diff --name-only HEAD
  assert_success
  assert_line 'café.txt'                    # raw, NOT "caf\303\251.txt"
  refute_output --partial 'caf\303\251'
}

@test "pinned_diff: structural chars stay C-quoted in line mode regardless of pin" {
  _make_fixture
  run pinned_diff --name-only 'HEAD~1'
  assert_success
  assert_line '"back\\slash.txt"'           # git quotes structural chars unconditionally
}

@test "pinned_diff: --stat non-ASCII flips raw (registered delta, both branches)" {
  _make_fixture
  run pinned_diff --stat HEAD
  assert_success
  assert_output --partial 'café.txt'    # raw, not "caf\303\251.txt" (spec: pinned probe)
  run pinned_diff --stat 'HEAD~1..HEAD'
  assert_output --partial 'café.txt'
}

@test "pinned_diff: rename stance — default collapses, --no-renames expands both sides" {
  _make_fixture
  run pinned_diff --no-renames --name-only HEAD
  assert_success
  assert_line 'plain.txt'                   # deleted side back in the list
  assert_line 'renamed.txt'
}

@test "pinned_diff: --no-renames overrides hostile diff.renames=true on the range branch" {
  _make_fixture
  git config diff.renames true
  run pinned_diff --no-renames --name-only 'HEAD~1..HEAD'
  assert_success
  assert_line 'plain.txt'
  assert_line 'renamed.txt'
}

@test "pinned_diff: rename collapse is forced on the single branch under hostile diff.renames=false" {
  _make_fixture
  git config diff.renames false
  run pinned_diff --stat HEAD
  assert_success
  assert_output --partial 'plain.txt => renamed.txt'
}

@test "pinned_diff: paths stay repo-relative under hostile diff.relative=true" {
  _make_fixture
  mkdir -p sub && echo x > sub/deep.txt && git add -A && git commit -qm c3
  git config diff.relative true
  cd sub
  run pinned_diff --name-only HEAD
  assert_success
  assert_line 'sub/deep.txt'                # repo-relative, not deep.txt
}

@test "pinned_diff: paths stay repo-relative under hostile diff.relative=true on the RANGE branch" {
  _make_fixture
  mkdir -p sub && echo x > sub/deep.txt && git add -A && git commit -qm c3
  git config diff.relative true
  cd sub
  run pinned_diff --name-only 'HEAD~1..HEAD'
  assert_success
  assert_line 'sub/deep.txt'                # repo-relative, not deep.txt
}

@test "pinned_diff: submodule pin defeats hostile diff.ignoreSubmodules=all" {
  local child="$BATS_TEST_TMPDIR/child-$$"
  git init -q "$child"
  ( cd "$child" \
    && git config user.email t@t.tld && git config user.name t \
    && echo x > sub.txt && git add -A && git commit -qm subinit )
  git -c protocol.file.allow=always submodule add -q "$child" sub
  git commit -qm addsub
  git config diff.ignoreSubmodules all
  run pinned_diff --name-only HEAD
  assert_success
  assert_line 'sub'                         # shown despite hostile config
}

@test "pinned_diff: submodule pin defeats hostile diff.ignoreSubmodules=all on the RANGE branch" {
  local child="$BATS_TEST_TMPDIR/child-$$"
  git init -q "$child"
  ( cd "$child" \
    && git config user.email t@t.tld && git config user.name t \
    && echo x > sub.txt && git add -A && git commit -qm subinit )
  git -c protocol.file.allow=always submodule add -q "$child" sub
  git commit -qm addsub
  # The submodule worktree is a SEPARATE repo (.git/modules/sub): it inherits
  # neither the parent's local identity nor any global one (CI runners have
  # none) — configure it before committing there, same as the child repo above.
  ( cd sub \
    && git config user.email t@t.tld && git config user.name t \
    && echo y > sub.txt && git add -A && git commit -qm childchange )
  git add sub && git commit -qm bumpsub
  git config diff.ignoreSubmodules all
  run pinned_diff --name-only 'HEAD~1..HEAD'
  assert_success
  assert_line 'sub'                         # shown despite hostile config
}

@test "pinned_diff: pathspec passthrough filters output" {
  _make_fixture
  run pinned_diff --name-only HEAD -- 'renamed.txt'
  assert_success
  assert_line 'renamed.txt'
  refute_line 'café.txt'
}

@test "pinned_diff: pathspec passthrough filters output on the RANGE branch" {
  _make_fixture
  run pinned_diff --name-only 'HEAD~1..HEAD' -- 'renamed.txt'
  assert_success
  assert_line 'renamed.txt'
  refute_line 'café.txt'
}

@test "pinned_diff: bad ref propagates git exit 128 + fatal (nothing swallowed)" {
  _make_fixture
  run pinned_diff --name-only no-such-ref
  assert_failure 128
  assert_output --partial 'fatal'
}
