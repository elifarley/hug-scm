#!/usr/bin/env bats
# Tests for create_test_repo_with_submodule test helper

setup() {
  load test_helper
}

# NOTE: We do NOT use `run` for these tests because `run` executes in a subshell,
# which loses the global variables (TEST_SUBMODULE_NAMES, TEST_SUBMODULE_PATHS,
# TEST_SUBMODULE_ORIGINS) that the function sets. Instead, call the function
# directly and rely on its own error handling (returns non-zero on failure).

@test "create_test_repo_with_submodule: single default submodule" {
  create_test_repo_with_submodule

  local parent="$TEST_PARENT_REPO"
  [[ -d "$parent" ]]
  [[ -f "$parent/.gitmodules" ]]
  [[ -d "$parent/sub" ]]
  [[ -f "$parent/sub/content.txt" ]]
  [[ "${#TEST_SUBMODULE_NAMES[@]}" -eq 1 ]]
  [[ "${TEST_SUBMODULE_NAMES[0]}" == "sub" ]]
  [[ "${#TEST_SUBMODULE_PATHS[@]}" -eq 1 ]]
  [[ "${TEST_SUBMODULE_PATHS[0]}" == "$parent/sub" ]]
  [[ "${#TEST_SUBMODULE_ORIGINS[@]}" -eq 1 ]]
}

@test "create_test_repo_with_submodule: multiple named submodules" {
  create_test_repo_with_submodule pay pay-v2

  local parent="$TEST_PARENT_REPO"
  [[ -d "$parent" ]]
  [[ -f "$parent/.gitmodules" ]]

  # Check .gitmodules has both entries
  grep -q 'path = pay' "$parent/.gitmodules"
  grep -q 'path = pay-v2' "$parent/.gitmodules"

  # Both submodule dirs exist with content
  [[ -f "$parent/pay/content.txt" ]]
  [[ -f "$parent/pay-v2/content.txt" ]]

  [[ "${#TEST_SUBMODULE_NAMES[@]}" -eq 2 ]]
  [[ "${TEST_SUBMODULE_NAMES[0]}" == "pay" ]]
  [[ "${TEST_SUBMODULE_NAMES[1]}" == "pay-v2" ]]

  [[ "${#TEST_SUBMODULE_PATHS[@]}" -eq 2 ]]
  [[ "${TEST_SUBMODULE_PATHS[0]}" == "$parent/pay" ]]
  [[ "${TEST_SUBMODULE_PATHS[1]}" == "$parent/pay-v2" ]]

  [[ "${#TEST_SUBMODULE_ORIGINS[@]}" -eq 2 ]]
}

@test "create_test_repo_with_submodule: submodules are initialized" {
  create_test_repo_with_submodule

  local parent="$TEST_PARENT_REPO"
  # A properly initialized submodule has a .git file (not dir) pointing
  # to the parent's .git/modules/<name>
  [[ -f "$parent/sub/.git" ]]
  # The submodule should have its own commit history (HEAD exists)
  [[ -d "$parent/.git/modules/sub" ]]
  # Verify submodule has content committed
  grep -q 'sub' "$parent/sub/content.txt"
}
