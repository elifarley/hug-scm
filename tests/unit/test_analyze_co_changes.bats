#!/usr/bin/env bats
# Tests for hug analyze co-changes command contract

load ../test_helper

setup() {
  require_hug
  TEST_REPO=$(create_demo_repo_simple)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

create_nested_co_change_history() {
  mkdir -p src/components

  cat > src/components/ComponentA.js <<'EOF'
export const componentA = true;
EOF
  cat > src/components/helper.js <<'EOF'
export const helper = true;
EOF
  git add src/components/ComponentA.js src/components/helper.js
  git commit -q -m "feat: add nested co-change pair"

  cat >> src/components/ComponentA.js <<'EOF'
export const componentAUpdated = true;
EOF
  cat >> src/components/helper.js <<'EOF'
export const helperUpdated = true;
EOF
  git add src/components/ComponentA.js src/components/helper.js
  git commit -q -m "fix: update nested co-change pair"
}

@test "hug analyze co-changes: shows updated help" {
  run hug analyze co-changes --help

  assert_success
  assert_output --partial "hug analyze co-changes <file> [options]"
  assert_output --partial "hug analyze co-changes --all [options]"
  assert_output --partial "--commits <n>"
}

@test "hug analyze co-changes: requires file or --all when gum is unavailable" {
  disable_gum_for_test

  run hug analyze co-changes

  assert_failure
  assert_output --partial "File argument required"
  assert_output --partial "hug analyze co-changes --all"
}

@test "hug analyze co-changes: file mode shows related files" {
  run hug analyze co-changes file1.txt --commits 10 --threshold 0.50

  assert_success
  assert_output --partial "Related files for file1.txt"
  assert_output --partial "Target file changed in 2 analyzed commits"
  assert_output --partial "file2.txt"
}

@test "hug analyze co-changes: --all shows repository-wide coupling" {
  run hug analyze co-changes --all --commits 10 --threshold 0.50

  assert_success
  assert_output --partial "Co-change Analysis"
  assert_output --partial "file1.txt ↔ file2.txt"
}

@test "hug analyze co-changes: rejects legacy positional count syntax" {
  run hug analyze co-changes 10

  assert_failure
  assert_output --partial "Positional commit counts were removed"
}

@test "hug analyze co-changes: normalizes nested repo paths from the repository root" {
  create_nested_co_change_history

  run hug analyze co-changes src/components/ComponentA.js --commits 20 --threshold 0.50

  assert_success
  assert_output --partial "Related files for src/components/ComponentA.js"
  assert_output --partial "src/components/helper.js"
}

@test "hug analyze co-changes: normalizes cwd-relative nested paths from a subdirectory" {
  create_nested_co_change_history
  cd src/components

  run hug analyze co-changes ComponentA.js --commits 20 --threshold 0.50

  assert_success
  assert_output --partial "Related files for src/components/ComponentA.js"
  assert_output --partial "src/components/helper.js"
}

@test "hug analyze co-changes: rejects files outside the current repository" {
  local outside_file
  outside_file="$BATS_TEST_TMPDIR/outside-file.js"
  echo "console.log('outside');" > "$outside_file"

  run hug analyze co-changes "$outside_file"

  assert_failure
  assert_output --partial "File must be inside the current repository"
}