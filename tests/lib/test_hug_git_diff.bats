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
  run pinned_diff --patch HEAD
  assert_failure 2
  assert_output --partial 'unknown format'
}

@test "pinned_diff: too few core args is rejected (exit 2, not a bash unbound trace)" {
  _make_fixture
  run pinned_diff --name-only
  assert_failure 2
  assert_output --partial 'expected'
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

# Fixture: branch `side` adds side.txt at HEAD; merge --no-ff into the main
# line (main did NOT move → parent-2 diff is empty, so -m output lists
# side.txt exactly once). Deterministic typical-merge shape.
_make_merge_fixture() {
  _make_fixture
  git checkout -qb side
  echo s > side.txt && git add side.txt && git commit -qm side
  git checkout -q main
  git merge -q --no-ff side -m "Merge side"
}

@test "pinned_diff: merge commit suppressed by default (v1 byte-identical guard)" {
  _make_merge_fixture
  run pinned_diff --name-only HEAD
  assert_success
  assert_output ""
}

@test "pinned_diff: --merge-aware lists merge changes vs each parent (-n)" {
  _make_merge_fixture
  run pinned_diff --merge-aware --name-only HEAD
  assert_success
  assert_line "side.txt"
}

@test "pinned_diff: --merge-aware --stat lists merge stats" {
  _make_merge_fixture
  run pinned_diff --merge-aware --stat HEAD
  assert_success
  assert_output --partial "side.txt"
}

@test "pinned_diff: --merge-aware is byte-identical no-op on non-merge commits" {
  _make_fixture
  run pinned_diff --name-only HEAD
  [[ "$status" -eq 0 ]]
  local plain="$output"
  run pinned_diff --merge-aware --name-only HEAD
  assert_success
  [[ "$output" == "$plain" ]]
}

@test "pinned_diff: --merge-aware rejected for ranges" {
  _make_fixture
  run pinned_diff --merge-aware --name-only 'HEAD~1..HEAD'
  assert_failure 2
  assert_output --partial "--merge-aware is only valid for single commits"
}

@test "pinned_diff: --merge-aware is a no-op on the root commit (single parent)" {
  _make_fixture
  root=$(git rev-list --max-parents=0 HEAD)
  run pinned_diff --name-only "$root"
  [[ "$status" -eq 0 ]]
  local plain="$output"
  run pinned_diff --merge-aware --name-only "$root"
  assert_success
  [[ "$output" == "$plain" ]]
}

@test "merge_first_parent_patch: merge emits the parent-1 patch (two-tree diff-tree)" {
  _make_merge_fixture
  run merge_first_parent_patch HEAD
  assert_success
  assert_output --partial "diff --git a/side.txt b/side.txt"
  # On THIS fixture every merge form coincides (the parent-2 diff is empty
  # by design), so it pins first-parent CONTENT, not form — the
  # DISCRIMINATING form pin is the both-sides test below.
}

@test "merge_first_parent_patch: byte-identical to git show -m --first-parent" {
  _make_merge_fixture
  local ours ref
  ours=$(merge_first_parent_patch HEAD)
  # Hermetic reference: pins protect against ambient config drift too —
  # color.ui=always would colorize only the porcelain side (diff-tree never
  # colorizes) and diff.renames could flip its rename rendering.
  ref=$(git -c color.ui=never -c diff.renames=false show -m --first-parent HEAD --pretty=format:)
  # TRIAGE if this fails after a git upgrade: diff both sides and decide
  # which moved. The CONTRACT is first-parent content (pinned by the test
  # above); `git show -m --first-parent` is only a cross-form reference,
  # and its byte shape is the version-sensitive side (no enforced repo
  # git floor — only ADR-001 test-strategy 2.23+ is documented). Re-pin deliberately, never silently.
  # This equality also depends on the fixture staying rename-free: on a
  # rename-carrying merge, git show -m --first-parent renders
  # rename from/to (porcelain diff.renames default) while the two-tree
  # form renders delete+add — see the helper's WHY note.
  [[ "$ours" == "$ref" ]]
}

@test "merge_first_parent_patch: octopus merge yields ONE parent-1 patch, not per-parent concatenation" {
  # 3-parent shape (main + o1 + o2 + o3): main is parent 1, so the
  # first-parent diff surfaces exactly the three side files as ONE section
  # each — a regression to the per-parent concatenation form would emit
  # many more sections. Same discriminator class as the both-sides test.
  _make_octopus_fixture
  run is_merge_commit HEAD
  assert_success
  run merge_first_parent_patch HEAD
  assert_success
  [[ $(printf '%s\n' "$output" | grep -c '^diff --git') -eq 3 ]]
  assert_output --partial "diff --git a/o1.txt b/o1.txt"
}

@test "merge_first_parent_patch: textconv driver keeps merge patches readable" {
  # Plumbing diff-tree does not run textconv unless asked (--textconv);
  # without it, a textconv'd file (PDFs/office docs via .gitattributes)
  # renders as "Binary files ... differ" in merge patches while the
  # non-merge branch (git show, porcelain) shows the transformed hunk.
  # Hermetic driver: an upcasing converter on .txt, so the transformed hunk
  # (-HELLO/+HELLO WORLD) is unambiguous against the raw form. tr reads
  # stdin only — the trailing '<' takes git's appended temp-file path as a
  # redirect.
  printf 'hello\n' > conv.txt && git add conv.txt && git commit -qm conv-base
  printf '*.txt diff=up\n' > .gitattributes
  git config diff.up.textconv 'tr a-z A-Z <'
  git add .gitattributes && git commit -qm attrs
  git checkout -qb conv-side
  printf 'hello world\n' > conv.txt && git commit -qam conv-edit
  git checkout -q main
  git merge -q --no-ff conv-side -m conv-merge
  run merge_first_parent_patch HEAD
  assert_success
  assert_output --partial "-HELLO"
  assert_output --partial "+HELLO WORLD"
  refute_output --partial "+hello world"
}

@test "merge_first_parent_patch: pathspecs thread after the two trees" {
  _make_merge_fixture
  run merge_first_parent_patch HEAD -- side.txt
  assert_success
  assert_output --partial "diff --git a/side.txt b/side.txt"
  run merge_first_parent_patch HEAD -- no-such.txt
  assert_success
  assert_output ""
}

@test "merge_first_parent_patch: both-sides fixture — one section, not per-parent concatenation" {
  # The DISCRIMINATING fixture: both parents modify shared.txt, so the
  # per-parent forms (diff-tree -m, with or without --first-parent) emit
  # TWO shared.txt sections while the two-tree form emits exactly ONE.
  # On _make_merge_fixture (empty parent-2 diff) all forms coincide, so
  # this is the pin that catches a regression to the concatenation form.
  _make_both_sides_fixture
  run merge_first_parent_patch HEAD
  assert_success
  [[ $(printf '%s\n' "$output" | grep -c '^diff --git') -eq 1 ]]
  assert_output --partial "diff --git a/shared.txt b/shared.txt"
}

# Fixture: BOTH parents modify shared.txt in different regions (auto-merge
# succeeds without conflict) — the shape behind the documented help contract
# "a file changed on both sides appears once per parent diff". Built on
# _make_fixture (same pattern as _make_merge_fixture) so the repo/branch
# layout matches setup().
_make_both_sides_fixture() {
  _make_fixture
  # shared.txt is committed on main BEFORE branching so the merge BASE
  # contains it — creating it independently on both sides is an add/add
  # conflict, not an auto-merge. After the branch: theirs appends line 3,
  # main changes ONLY line 1 — disjoint regions, auto-resolves.
  printf 'a\nshared\n' > shared.txt && git add shared.txt && git commit -qm shared-base
  git checkout -qb theirs
  printf 'a\nshared\ntheirs\n' > shared.txt && git commit -qam theirs-edit
  git checkout -q main
  printf 'b\nshared\n' > shared.txt && git commit -qam ours-edit
  git merge -q --no-ff theirs -m merged
}

@test "pinned_diff: --merge-aware lists a both-parents-modified file ONCE PER PARENT (help contract)" {
  _make_both_sides_fixture
  # Default stays suppressed (v1 guard, re-pinned for THIS shape — the
  # existing suppression test only covers a side-only merge).
  run pinned_diff --name-only HEAD
  assert_success
  assert_output ""
  # git-shc help + lib/README document the duplication: -m emits one diff per
  # parent, so shared.txt (changed against both) lists exactly twice. A
  # future switch to first-parent-only (-m → first parent) or to dedup'd
  # output breaks this count and MUST update the help text in the same PR.
  run pinned_diff --merge-aware --name-only HEAD
  assert_success
  [[ "$(printf '%s\n' "$output" | grep -cx 'shared.txt')" -eq 2 ]]
}

# Fixture: true octopus — ONE merge commit with 3 parents (o1/o2/o3 each add
# an independent file off the same base; octopus strategy merges cleanly).
_make_octopus_fixture() {
  _make_fixture
  for b in o1 o2 o3; do
    git checkout -qb "$b"
    echo "$b" > "$b.txt" && git add "$b.txt" && git commit -qm "$b"
    git checkout -q main
  done
  git merge -q --no-ff o1 o2 o3 -m octo >/dev/null 2>&1
}

@test "pinned_diff: --merge-aware handles an octopus merge (3 parents, each side listed)" {
  _make_octopus_fixture
  # is_merge_commit's word-count probe must hold beyond 2 parents
  # (rev-list --parents prints 4+ words for a 3-parent commit).
  run is_merge_commit HEAD
  assert_success
  # Default stays suppressed even on an octopus.
  run pinned_diff --name-only HEAD
  assert_success
  assert_output ""
  # -m diffs against EACH parent: all three sides surface.
  run pinned_diff --merge-aware --name-only HEAD
  assert_success
  assert_line "o1.txt"
  assert_line "o2.txt"
  assert_line "o3.txt"
}

@test "pinned_diff: --merge-aware combines with --null in REVERSED flag order" {
  _make_merge_fixture
  # The flag loop was born from an order-permutation bug (the old two-check
  # parser died on the second flag). The branch's own pins always pass
  # --merge-aware FIRST; this pins the loop consuming it SECOND. NUL bytes
  # never survive $output — od pipe discipline (same idiom as the --null
  # tests above). _make_merge_fixture's parent-2 diff is empty, so the
  # stream is exactly one entry.
  [[ "$(pinned_diff --null --merge-aware --name-only HEAD | od -An -c | tr -d ' \n')" == 'side.txt\0' ]]
}

@test "is_merge_commit: merge true; linear, root, and bad refs false (bad-ref stderr silenced)" {
  # ONE _make_merge_fixture serves every case (it builds its own
  # _make_fixture — calling both in one repo would re-run git mv onto an
  # existing destination). History: c1 → c2 → side commit → merge.
  _make_merge_fixture
  run is_merge_commit HEAD
  assert_success
  # Linear commits (side tip, pre-merge main tip) → 2 words → false.
  run is_merge_commit HEAD~1
  assert_failure
  run is_merge_commit HEAD~2
  assert_failure
  # Root commit prints alone (no parent line) → 1 word → false.
  root=$(git rev-list --max-parents=0 HEAD)
  run is_merge_commit "$root"
  assert_failure
  # Bad ref: rev-list fails, stderr is silenced (callers probe speculatively
  # and must not duplicate the diff invocation's authoritative fatal), and
  # the predicate answers false so the flag stays off and git's own fatal
  # fires from pinned_diff.
  run is_merge_commit no-such-ref
  assert_failure
  assert_output ""
}

@test "pinned_diff: --merge-aware keeps the rename DISPLAY stance (merged rename lists new path only)" {
  # Mirrors the single-commit rename tests above, but on a MERGE: the
  # per-parent diff must keep the default collapse-to-new-path display even
  # with --merge-aware threaded in (a flag interaction no other test covers).
  _make_fixture
  git checkout -qb ren
  git mv renamed.txt moved.txt && git commit -qm renamed-on-side
  git checkout -q main
  git merge -q --no-ff ren -m "Merge ren"
  run pinned_diff --merge-aware --name-only HEAD
  assert_success
  assert_line "moved.txt"
  refute_line "renamed.txt"
}
