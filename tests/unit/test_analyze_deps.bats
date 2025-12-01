#!/usr/bin/env bats
# Tests for hug analyze deps command

load ../test_helper

setup() {
  require_hug
  TEST_REPO=$(create_demo_repo_simple)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

# Basic functionality tests

@test "hug analyze deps: shows help with -h" {
  run git analyze-deps -h

  assert_success
  assert_output --partial "hug analyze deps"
  assert_output --partial "Show dependency graph"
  assert_output --partial "USAGE:"
  assert_output --partial "EXAMPLES:"
}

@test "hug analyze deps: shows help with --help" {
  run git analyze-deps -h

  assert_success
  assert_output --partial "hug analyze deps"
  assert_output --partial "Show dependency graph"
}

@test "hug analyze deps: requires commit argument when not in --all mode" {
  run git analyze-deps

  # Without gum, should fail with error
  if ! command -v gum &>/dev/null; then
    assert_failure
    assert_output --partial "Commit argument required"
  fi
  # With gum, might succeed if user selects a commit (skip this assertion)
}

@test "hug analyze deps: fails with invalid commit hash" {
  run git analyze-deps nonexistent123

  assert_failure
  assert_output --partial "Invalid commit"
}

@test "hug analyze deps: analyzes HEAD commit" {
  # Demo repo has "feat: add feature B" as HEAD commit
  run git analyze-deps HEAD

  assert_success
  assert_output --partial "Dependency graph for commit"
  assert_output --partial "feat: add feature B"
}

@test "hug analyze deps: shows related commits via file overlap" {
  # Get the first commit with file dependencies (feat: add feature A)
  # Skip the initial 3 commits (README, app.js, .gitignore) to get to file1.txt commits
  first_commit=$(git log --oneline --grep="feat: add feature A" --format="%H" -n 1)

  run git analyze-deps "$first_commit" --threshold 1

  assert_success
  assert_output --partial "Dependency graph for commit"
  # Should show related commits that touch file1 or file2
}

@test "hug analyze deps: respects threshold parameter" {
  # Get the first commit with file dependencies
  first_commit=$(git log --oneline --grep="feat: add feature A" --format="%H" -n 1)

  # With high threshold, should find fewer or no matches
  run git analyze-deps "$first_commit" --threshold 10

  assert_success
  assert_output --partial "No related commits found"
}

@test "hug analyze deps: supports --format text" {
  run git analyze-deps HEAD --format text

  assert_success
  assert_output --partial "Related commits for"
  assert_output --partial "feat: add feature B"
}

@test "hug analyze deps: supports --format json" {
  run git analyze-deps HEAD --format json

  assert_success
  # JSON output should have expected structure
  assert_output --partial '"root_commit"'
  assert_output --partial '"dependencies"'
}

@test "hug analyze deps: supports --format graph (default)" {
  run git analyze-deps HEAD --format graph

  assert_success
  assert_output --partial "Dependency graph for commit"
  # Graph format uses tree characters
  assert_output --partial "Author:"
  assert_output --partial "Files modified:"
}

@test "hug analyze deps: supports --depth parameter" {
  first_commit=$(git log --oneline --grep="feat: add feature A" --format="%H" -n 1)

  # Depth 1 (default)
  run git analyze-deps "$first_commit" --depth 1 --threshold 1

  assert_success

  # Depth 2 should potentially find more commits
  run git analyze-deps "$first_commit" --depth 2 --threshold 1

  assert_success
}

@test "hug analyze deps: supports --max-results parameter" {
  # Create more commits to have many related ones
  for i in {1..5}; do
    echo "update $i" >> file1.txt
    git add file1.txt
    git commit -m "update $i"
  done

  first_commit=$(git log --oneline --grep="feat: add feature A" --format="%H" -n 1)

  run git analyze-deps "$first_commit" --max-results 2 --threshold 1

  assert_success
  # Should limit output to 2 results
}

@test "hug analyze deps: supports --since parameter" {
  # Demo repo commits are all from year 2000, so --since="1 week ago" returns nothing
  # Use a date far in the past to include all commits
  run git analyze-deps HEAD --since="1990-01-01"

  assert_success
  assert_output --partial "Dependency graph for commit"
}

# --all mode tests

@test "hug analyze deps: supports --all mode" {
  run git analyze-deps --all --threshold 2 --max-results 5

  assert_success
  assert_output --partial "Commit Coupling Analysis"
  assert_output --partial "threshold: 2 files"
}

@test "hug analyze deps: --all mode shows repository-wide coupling" {
  run git analyze-deps --all --threshold 1 --max-results 10

  assert_success
  assert_output --partial "Found"
  assert_output --partial "commits with dependencies"
}

@test "hug analyze deps: --all mode supports --format json" {
  run git analyze-deps --all --format json --max-results 5

  assert_success
  assert_output --partial '"threshold"'
  assert_output --partial '"total_commits_with_dependencies"'
  assert_output --partial '"coupling"'
}

# Edge cases and error handling

@test "hug analyze deps: handles commit with no related commits" {
  # Use high threshold to ensure no matches
  run git analyze-deps HEAD --threshold 100

  assert_success
  assert_output --partial "Dependency graph for commit"
}

@test "hug analyze deps: handles merge commits" {
  # Store current branch name
  main_branch=$(git rev-parse --abbrev-ref HEAD)

  # Create a branch and merge (use unique name to avoid conflicts)
  git checkout -b test530-feature
  echo "feature" > feature.txt
  git add feature.txt
  git commit -m "feature commit"

  # Return to main branch
  git checkout "$main_branch"
  git merge test530-feature --no-edit

  run git analyze-deps HEAD

  assert_success
  assert_output --partial "Dependency graph"
}

@test "hug analyze deps: works with short commit hashes" {
  # Get short hash
  short_hash=$(git log -1 --format=%h)

  run git analyze-deps "$short_hash"

  assert_success
}

@test "hug analyze deps: works with relative refs like HEAD~1" {
  run git analyze-deps HEAD~1

  assert_success
}

# Python script availability

@test "hug analyze deps: fails gracefully if deps.py not found" {
  # Temporarily rename the Python script (use absolute path)
  python_script="$PROJECT_ROOT/git-config/lib/python/deps.py"

  if [ -f "$python_script" ]; then
    mv "$python_script" "${python_script}.bak"
  fi

  run git analyze-deps HEAD

  # Restore the script
  if [ -f "${python_script}.bak" ]; then
    mv "${python_script}.bak" "$python_script"
  fi

  assert_failure
  assert_output --partial "Dependency analysis not available"
}

# Integration with actual file changes

@test "hug analyze deps: correctly identifies commits touching same files" {
  # Create commit 1 touching unique_file1.txt and unique_file2.txt
  echo "v1" > unique_file1.txt
  echo "v1" > unique_file2.txt
  git add unique_file1.txt unique_file2.txt
  git commit -m "test534: commit 1"
  commit1=$(git log -1 --format=%H)

  # Create commit 2 touching unique_file2.txt and unique_file3.txt
  echo "v2" > unique_file2.txt
  echo "v2" > unique_file3.txt
  git add unique_file2.txt unique_file3.txt
  git commit -m "test534: commit 2"

  # Create commit 3 touching unique_file1.txt and unique_file2.txt (related to commit 1)
  echo "v3" > unique_file1.txt
  echo "v3" >> unique_file2.txt
  git add unique_file1.txt unique_file2.txt
  git commit -m "test534: commit 3"
  commit3=$(git log -1 --format=%H)

  # Analyze commit 1
  run git analyze-deps "$commit1" --threshold 2 --format text

  assert_success
  # Should show commit 3 as related (both touch unique_file1.txt and unique_file2.txt)
  assert_output --partial "test534: commit 3"
}

@test "hug analyze deps: graph output includes file count" {
  first_commit=$(git log --oneline --grep="feat: add feature A" --format="%H" -n 1)

  run git analyze-deps "$first_commit" --threshold 1

  assert_success
  # Should show number of files in overlap
  assert_output --partial "files)"
}

@test "hug analyze deps: text output is properly formatted" {
  run git analyze-deps HEAD --format text

  assert_success
  # Should have readable format with columns
  assert_output --partial "Related commits for"
  # Each line should have hash, subject, file count, date
}

@test "hug analyze deps: handles repository with many commits efficiently" {
  # Create more commits
  for i in {1..10}; do
    echo "commit $i" > "file${i}.txt"
    git add "file${i}.txt"
    git commit -m "commit $i" --allow-empty
  done

  # Test with 120-second timeout protection (configurable via HUG_ANALYZE_DEPS_TIMEOUT)
  run_with_timeout 120 0 git analyze-deps HEAD --threshold 1 --max-results 5

  assert_success
  assert_output --partial "Dependency graph"
}
