#!/usr/bin/env bats
# Tests for hug llu (outgoing log): truthful empty-path sync-state reporting
# (human + JSON), per docs/superpowers/specs/2026-08-28-truthful-sync-state-messages-for-llu-lol-h-files-design.md

load '../test_helper'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_remote_upstream)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

# Makes origin/main 1 ahead of local main: push an empty commit (updates the
# local remote-tracking ref), then move local main back. No fetch needed.
make_behind() {
  git commit -q --allow-empty -m "upstream-only commit"
  git push -q origin main
  git reset -q --hard HEAD~1
}

@test "hug llu: synced upstream -> truthful synced message + trailing summary" {
  run hug llu
  assert_success
  assert_output --partial "📭 No outgoing commits (already synced to origin/main)"
  refute_output --partial "up to date"
  assert_output --partial "HEAD:" # unscoped runs still end with the whole-repo summary
}

@test "hug llu: behind upstream -> truthful behind message" {
  make_behind
  run hug llu
  assert_success
  assert_output --partial "📭 No outgoing commits (branch is behind origin/main by 1 commit — pull or rebase to catch up)"
  refute_output --partial "already synced"
  refute_output --partial "up to date"
  assert_output --partial "HEAD:" # unscoped behind runs also end with the whole-repo summary
}

@test "hug llu --json: synced -> state in_sync" {
  run hug llu --json
  assert_success
  assert_output --partial '"state":"in_sync"'
  assert_output --partial '"behind_count":0'
  echo "$output" | python3 -m json.tool > /dev/null
}

@test "hug llu --json: behind -> state behind with count" {
  make_behind
  run hug llu --json
  assert_success
  assert_output --partial '"state":"behind"'
  assert_output --partial '"behind_count":1'
  echo "$output" | python3 -m json.tool > /dev/null
}

@test "hug llu --json: unborn HEAD with upstream config -> error sync_state_unknown" {
  git checkout -q --orphan fresh
  # `branch --set-upstream-to` refuses unborn branches — write config directly
  # (verified: rev-parse @{u} then succeeds rc=0 while both rev-list counts fail rc=128)
  git config branch.fresh.remote origin
  git config branch.fresh.merge refs/heads/main
  run hug llu --json
  assert_success
  assert_output --partial '"error":"sync_state_unknown"'
  refute_output --partial '"state"'
  echo "$output" | python3 -m json.tool > /dev/null
}

@test "hug llu: unborn HEAD with upstream config -> fallback message, scoped run" {
  git checkout -q --orphan fresh
  git config branch.fresh.remote origin
  git config branch.fresh.merge refs/heads/main
  run hug llu -- . # scoped: the trailing whole-repo summary must NOT fire
  assert_success
  assert_output --partial "📭 No outgoing commits (sync state with origin/main could not be determined)"
  refute_output --partial "up to date"
  refute_output --partial "HEAD:"
}

@test "hug llu -q: synced -> message AND summary suppressed" {
  run hug llu -q
  assert_success
  refute_output --partial "No outgoing commits"
  refute_output --partial "HEAD:"
}

@test "hug llu -q: behind -> message AND summary suppressed" {
  make_behind
  run hug llu -q
  assert_success
  refute_output --partial "No outgoing commits"
  refute_output --partial "HEAD:"
}

@test "hug llu --json -q: JSON unaffected by quiet (machine data stays on stdout)" {
  run hug llu --json -q
  assert_success
  assert_output --partial '"state":"in_sync"'
  echo "$output" | python3 -m json.tool > /dev/null
}
