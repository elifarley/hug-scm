#!/usr/bin/env bats
# E2E pins for the merge family discovery surfaces (elifarley/hug-scm#343).
#
# The pytest corpus pins the SCORING; these pin the CLI surfaces the branch
# added rows for but left unpinned:
#   - `hug help @merge`: registry rows (m, ma, mkeep) + the git-mff script
#     interleaved in ONE alphabetical run (the merge-category analog of the
#     @push-pull row in test_help_articles.bats);
#   - `hug help m` / `hug help ma`: the family's cards (summary, usage,
#     git_equivalent pointers);
#   - card Related-lines carry NO kind marker — the contract documented on
#     _display_description's docstring ("deliberately NOT shared with the
#     card's related-lines").
#
# Related-hint TEXT is deliberately not asserted: hints come from the
# search-meta cache peek, which is cold on a fresh checkout (a bare
# "  hug c" line is the correct cold-cache render).

load ../test_helper

setup() {
  require_hug
  # Fresh search index: registry rows never enter the cache, but a stale
  # script cache could desync the @merge listing from the current tree.
  rm -f /tmp/cache/hug/search-meta.cache
  TEST_TEMP_DIR=$(create_temp_repo_dir)
  mkdir -p "$TEST_TEMP_DIR"
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

@test "hug help @merge interleaves registry rows and the mff script in one run" {
  cd "$TEST_TEMP_DIR"
  # Data lines go to stdout (stdout/stderr discipline); drop stderr so
  # line-order assertions see only the command list.
  run bash -c "hug help '@merge' 2>/dev/null"
  assert_success
  local m ma mff mkeep
  # ^-anchored (2-space indent + space after name): "hug m" must not
  # capture "hug ma"/"hug mff"/"hug mkeep" lines.
  m="$(grep -n '^  hug m ' <<<"$output" | cut -d: -f1)"
  ma="$(grep -n '^  hug ma ' <<<"$output" | cut -d: -f1)"
  mff="$(grep -n '^  hug mff ' <<<"$output" | cut -d: -f1)"
  mkeep="$(grep -n '^  hug mkeep ' <<<"$output" | cut -d: -f1)"
  # All four family members listed...
  [[ -n "$m" && -n "$ma" && -n "$mff" && -n "$mkeep" ]]
  # ...in ONE alphabetical run: the script row mff sits BETWEEN the registry
  # rows ma and mkeep — no script-block-then-registry-block split.
  (( m < ma && ma < mff && mff < mkeep ))
  # Kind markers explain why -h differs across the run.
  assert_output --partial "(git alias)"
}

@test "hug help m renders the merge-family card" {
  cd "$TEST_TEMP_DIR"
  run hug help m
  assert_success
  assert_output --partial "hug m — (git alias)"
  assert_output --partial "Squash-merge a branch"
  assert_output --partial "Usage: hug m <branch>"
  assert_output --partial "Git equivalent: git merge --squash"
  assert_output --partial "Full flags: git help merge"
  refute_output --partial "usage: git merge" # git's own banner must not leak
}

@test "hug help ma renders the abort card" {
  cd "$TEST_TEMP_DIR"
  run hug help ma
  assert_success
  assert_output --partial "hug ma — (git alias)"
  assert_output --partial "Git equivalent: git merge --abort"
  assert_output --partial "Related:"
}

@test "card Related-lines render without the kind marker" {
  cd "$TEST_TEMP_DIR"
  run hug help m
  assert_success
  # m's related set spans all three resolution kinds: registry (mkeep, ma),
  # bin script (mff), gitconfig alias (c) — every related line must render
  # bare, per _display_description's docstring contract.
  local related="${output#*Related:}"
  [[ "$related" != *"(git alias)"* ]]
  [[ "$related" != *"(git passthrough)"* ]]
  # Registry-owned related always render "name — summary"; script/alias
  # related render "name — cached-hint" on a warm cache but BARE ("name")
  # on a cold one (setup deletes the cache) — so only the names are pinned.
  assert_output --partial "  hug mkeep —"
  assert_output --partial "  hug ma —"
  assert_output --partial "  hug mff"
  assert_output --partial "  hug c"
}

# The discovery layer reaches git-mff's help and --search-meta from
# NON-repo cwds (installed layouts have no .git at all) — both must work
# there, or mff silently drops out of the search index and `hug help mff`
# degrades to an error. The repo guard must therefore sit AFTER the -h
# dispatch (same ordering lesson as git-shc's fail-loud guards).
@test "git-mff help and search-meta work outside any repository" {
  # A directory that is NOT a git repo (deliberately not TEST_TEMP_DIR,
  # which create_temp_repo_dir may initialize).
  local bare="$TEST_TEMP_DIR/../mff-bare-$$"
  mkdir -p "$bare"
  cd "$bare"
  run env HUG_HOME="$HUG_HOME" "$HUG_HOME/git-config/bin/git-mff" --help
  assert_success
  assert_output --partial "Fast-forward merge or move branch pointer"
  refute_output --partial "Not in a git repository"

  run env HUG_HOME="$HUG_HOME" "$HUG_HOME/git-config/bin/git-mff" --search-meta
  assert_success
  assert_output --partial "keywords"
}
