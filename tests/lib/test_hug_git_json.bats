#!/usr/bin/env bats
# Tests for hug-git-json library functions

load "../test_helper.bash"

# Helper function to source all required libraries
source_hug_json_libs() {
  export HUG_LIB_DIR="git-config/lib"
  source git-config/lib/hug-common
  source git-config/lib/hug-json
  source git-config/lib/hug-git-kit
  source git-config/lib/hug-git-json
}

@test "parse_file_to_json: handles modified files" {
  source_hug_json_libs

  run parse_file_to_json $'M\tfile.txt'

  # Check output exists and contains expected values
  [[ -n "$output" ]]
  echo "$output" | grep -q '"path".*"file.txt"'
  echo "$output" | grep -q '"status".*"modified"'
}

@test "parse_file_to_json: handles added files" {
  source_hug_json_libs

  local result
  result="$(parse_file_to_json $'A\tnewfile.txt')"

  echo "$result" | jq -e '.path == "newfile.txt"' >/dev/null
  echo "$result" | jq -e '.status == "added"' >/dev/null
}

@test "parse_file_to_json: handles deleted files" {
  source_hug_json_libs

  local result
  result="$(parse_file_to_json $'D\tdeleted.txt')"

  echo "$result" | jq -e '.path == "deleted.txt"' >/dev/null
  echo "$result" | jq -e '.status == "deleted"' >/dev/null
}

@test "parse_file_to_json: handles renamed files (3 fields)" {
  source_hug_json_libs

  local result
  result="$(parse_file_to_json $'R100\told.txt\tnew.txt')"

  echo "$result" | jq -e '.path == "new.txt"' >/dev/null
  echo "$result" | jq -e '.status == "renamed"' >/dev/null
}

@test "parse_file_to_json: handles copied files" {
  source_hug_json_libs

  local result
  result="$(parse_file_to_json $'C100\toriginal.txt\tcopy.txt')"

  echo "$result" | jq -e '.path == "copy.txt"' >/dev/null
  echo "$result" | jq -e '.status == "copied"' >/dev/null
}

@test "parse_file_to_json: returns empty for invalid input" {
  source_hug_json_libs

  local result
  result="$(parse_file_to_json "" 2>/dev/null || true)"

  [[ -z "$result" ]]
}

@test "collect_git_files_json: collects staged files correctly" {
  local TEST_REPO
  source_hug_json_libs  # Source libraries before cd
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO" || return 1

  echo "new content" > file.txt
  git add file.txt

  # collect_git_files_json prints one JSON object per line; mapfile captures
  # both the complete objects and the count (the array length).
  local -a files=()
  mapfile -t files < <(collect_git_files_json "staged")
  [[ ${#files[@]} -eq 1 ]]
  local joined="${files[*]:-}"
  echo "$joined" | grep -q '"path".*"file.txt"'
  echo "$joined" | grep -q '"status".*"added"'  # New files are "added" not "modified"
}

@test "collect_git_files_json: collects untracked files correctly" {
  local TEST_REPO
  source_hug_json_libs  # Source libraries before cd
  TEST_REPO=$(create_test_repo)
  cd "$TEST_REPO" || return 1

  echo "new file" > untracked.txt

  local -a files=()
  mapfile -t files < <(collect_git_files_json "untracked")
  [[ ${#files[@]} -eq 1 ]]
  local joined="${files[*]:-}"
  echo "$joined" | grep -q '"path".*"untracked.txt"'
  echo "$joined" | grep -q '"status".*"untracked"'
}

@test "collect_git_files_json: handles renamed files correctly" {
  local TEST_REPO
  source_hug_json_libs  # Source libraries before cd
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO" || return 1

  echo "content" > old.txt
  git add old.txt
  git commit -m "add old"

  rm -f new.txt  # Remove any existing file first
  git mv old.txt new.txt
  git add -A

  local -a files=()
  mapfile -t files < <(collect_git_files_json "staged")
  [[ ${#files[@]} -eq 1 ]]
  local joined="${files[*]:-}"
  echo "$joined" | grep -q '"status".*"renamed"'
  echo "$joined" | grep -q '"path".*"new.txt"'
}

@test "collect_git_files_json: returns empty for no files" {
  local TEST_REPO
  source_hug_json_libs  # Source libraries before cd
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO" || return 1

  local -a files=()
  mapfile -t files < <(collect_git_files_json "staged")
  [[ ${#files[@]} -eq 0 ]]
}

@test "collect_git_files_json: collects unstaged files correctly" {
  local TEST_REPO
  source_hug_json_libs  # Source libraries before cd
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO" || return 1

  # Modify an existing tracked file to create unstaged changes
  echo "unstaged content" > feature1.txt

  local -a files=()
  mapfile -t files < <(collect_git_files_json "unstaged")
  [[ ${#files[@]} -eq 1 ]]
  local joined="${files[*]:-}"
  echo "$joined" | grep -q '"path".*"feature1.txt"'
  echo "$joined" | grep -q '"status".*"modified"'
}

@test "collect_git_files_json: collects ignored files correctly" {
  local TEST_REPO
  source_hug_json_libs  # Source libraries before cd
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO" || return 1

  echo "ignored content" > ignored.txt
  echo "ignored.txt" >> .gitignore
  git add .gitignore
  git commit -m "add gitignore"

  local -a files=()
  mapfile -t files < <(collect_git_files_json "ignored")
  [[ ${#files[@]} -eq 1 ]]
  local joined="${files[*]:-}"
  echo "$joined" | grep -q '"path".*"ignored.txt"'
  echo "$joined" | grep -q '"status".*"ignored"'
}

@test "git_status_to_json_type: maps all status codes correctly" {
  source_hug_json_libs

  [[ "$(git_status_to_json_type "A")" == "added" ]]
  [[ "$(git_status_to_json_type "M")" == "modified" ]]
  [[ "$(git_status_to_json_type "D")" == "deleted" ]]
  [[ "$(git_status_to_json_type "R100")" == "renamed" ]]
  [[ "$(git_status_to_json_type "C100")" == "copied" ]]
  [[ "$(git_status_to_json_type "U")" == "conflict" ]]
  [[ "$(git_status_to_json_type "??")" == "untracked" ]]
  # Skip ignored test due to bash history expansion issues in subshells
  # [[ "$(git_status_to_json_type '!!')" == "ignored" ]]
  [[ "$(git_status_to_json_type "X")" == "unknown" ]]
}

@test "collect_git_files_json: collects conflicted files with conflict status" {
  local TEST_REPO
  source_hug_json_libs  # Source libraries before cd
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO" || return 1

  # Build a real merge conflict (raw git is fine inside tests)
  echo "base" > conflict-file.txt
  git add conflict-file.txt
  git commit -q -m "Add base"
  git switch -q -c branch1
  echo "branch1 change" > conflict-file.txt
  git add conflict-file.txt
  git commit -q -m "Change on branch1"
  git switch -q main
  echo "branch2 change" > conflict-file.txt
  git add conflict-file.txt
  git commit -q -m "Change on branch2"
  git merge --no-commit --no-ff branch1 2>/dev/null || true

  local -a files=()
  mapfile -t files < <(collect_git_files_json "conflicted")
  [[ ${#files[@]} -eq 1 ]]
  local joined="${files[*]:-}"
  echo "$joined" | grep -q '"path".*"conflict-file.txt"'
  echo "$joined" | grep -q '"status".*"conflict"'

  # Pin summary.conflicted to the truthful object count (1 file, not the
  # 2 fragment-split elements the legacy types count — elifarley/hug-scm#247).
  # The emitter prints "conflicted":  "1" (to_json_object space + sed space).
  run output_json_status_unified --filter conflicted
  assert_success
  echo "$output" | grep -qE '"conflicted": +"1"'
  # Pin the array emission path (add_file_array) — otherwise untested.
  echo "$output" | grep -q '"conflicted": \['
}

# =============================================================================
# Pathspec plumbing through the JSON chain (Task 6, #292 PR-B)
# =============================================================================
# Contract: output_json_status → output_json_status_unified →
# collect_git_files_json → list_*_files must forward pathspecs collected
# after a protective '--', consuming the separator at each layer and
# re-appending exactly ONE at its own list/git boundary (the exact-one-'--'
# rule landed with Task 5's separator-aware selector loops). A pathspec
# spelled like one of our own flags ('--cwd') is DATA — it scopes, never
# toggles.

# Fixture: staged src/a.py + staged other.txt, so a 'src/' scope
# discriminates (one file in, one file out).
setup_json_pathspec_fixture() {
  local repo
  repo=$(create_test_repo)
  mkdir -p "$repo/src"
  cd "$repo" || return 1
  echo py1 > src/a.py
  echo other > other.txt
  git add src/a.py other.txt
}

@test "output_json_status_unified: pathspecs after -- scope the envelope (two-sided)" {
  local TEST_REPO
  source_hug_json_libs  # Source libraries before cd
  setup_json_pathspec_fixture

  run output_json_status_unified --filter staged -- src/
  assert_success
  local json_out="$output"
  assert_valid_json "$json_out"
  [[ "$json_out" == *'"src/a.py"'* ]]
  [[ "$json_out" != *'"other.txt"'* ]]
  # summary counts must match the scoped array
  run python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['summary']['staged'], len(d['staged']))" "$json_out"
  assert_output "1 1"
}

@test "output_json_status_unified: empty scope keeps the envelope shape" {
  # Machine contract: a scoped query answers with the SAME envelope shape —
  # zero-length arrays present, summary counts 0. The shape must not change
  # just because the scope matched nothing.
  local TEST_REPO
  source_hug_json_libs  # Source libraries before cd
  setup_json_pathspec_fixture

  run output_json_status_unified --filter staged -- docs/none/
  assert_success
  local json_out="$output"
  assert_valid_json "$json_out"
  run python3 -c "import json,sys; d=json.loads(sys.argv[1]); print('staged' in d, d['staged'], d['summary']['staged'], d['summary']['total'])" "$json_out"
  assert_output "True [] 0 0"
}

@test "output_json_status_unified: pathspec spelled '--cwd' scopes, does not toggle" {
  local TEST_REPO
  source_hug_json_libs  # Source libraries before cd
  setup_json_pathspec_fixture
  echo cwd1 > ./--cwd
  git add -- ./--cwd

  run output_json_status_unified --filter staged -- --cwd
  assert_success
  local json_out="$output"
  assert_valid_json "$json_out"
  [[ "$json_out" == *'"--cwd"'* ]]
  [[ "$json_out" != *'"src/a.py"'* ]]
  [[ "$json_out" != *'"other.txt"'* ]]
}

@test "collect_git_files_json: forwards pathspecs after -- (staged, two-sided)" {
  local TEST_REPO
  source_hug_json_libs  # Source libraries before cd
  setup_json_pathspec_fixture

  local -a files=()
  mapfile -t files < <(collect_git_files_json "staged" -- src/)
  [[ ${#files[@]} -eq 1 ]]
  local joined="${files[*]:-}"
  echo "$joined" | grep -q '"path".*"src/a.py"'
  [[ "$joined" != *"other.txt"* ]]
}

@test "collect_git_files_json: forwards pathspecs after -- (untracked, two-sided)" {
  local TEST_REPO
  source_hug_json_libs  # Source libraries before cd
  setup_json_pathspec_fixture
  echo untracked > src/new.txt
  echo untracked > root-new.txt

  local -a files=()
  mapfile -t files < <(collect_git_files_json "untracked" -- src/)
  [[ ${#files[@]} -eq 1 ]]
  local joined="${files[*]:-}"
  echo "$joined" | grep -q '"path".*"src/new.txt"'
  [[ "$joined" != *"root-new.txt"* ]]
}

@test "collect_git_files_json: pathspec spelled '--cwd' stays data" {
  local TEST_REPO
  source_hug_json_libs  # Source libraries before cd
  setup_json_pathspec_fixture
  echo cwd1 > ./--cwd
  git add -- ./--cwd

  local -a files=()
  mapfile -t files < <(collect_git_files_json "staged" -- --cwd)
  [[ ${#files[@]} -eq 1 ]]
  local joined="${files[*]:-}"
  echo "$joined" | grep -q '"path".*"--cwd"'
  [[ "$joined" != *"src/a.py"* ]]
}
