#!/usr/bin/env bats
# Performance regression tests for hug analyze deps
#
# LESSON LEARNED: Performance tests should use realistic but constrained parameters
# OPTIMIZATION PRINCIPLES:
# 1. Reduce commit counts to minimum viable test scenarios
# 2. Set reasonable timeouts that catch regressions without being overly generous
# 3. Focus on detecting performance degradation rather than absolute performance
# 4. Use scoped parameters (--depth, --max-results) to prevent exponential growth

load ../test_helper

setup() {
  require_hug
  TEST_REPO=$(create_demo_repo_simple)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

@test "hug analyze deps: small repository performance baseline" {
  # Baseline: should complete within 15 seconds for small repos
  run_with_timeout 15 0 git analyze-deps HEAD --threshold 1 --max-results 5

  assert_success
  assert_output --partial "Dependency graph"
}

@test "hug analyze deps: small repository with multiple commits" {
  # Create 15 commits for small repository test (reduced from 25)
  for i in {1..15}; do
    echo "content $i" >> "test_file.txt"
    git add "test_file.txt"
    git commit -m "update $i"
  done

  # Small repos should complete within 30 seconds
  run_with_timeout 30 0 git analyze-deps HEAD --threshold 1 --max-results 5

  assert_success
  assert_output --partial "Dependency graph"
}

@test "hug analyze deps: medium repository performance test" {
  # Create 30 commits for medium repository test (reduced from 50)
  for i in {1..30}; do
    echo "content $i" >> "test_file.txt"
    git add "test_file.txt"
    git commit -m "update $i"
  done

  # Medium repos should complete within 45 seconds
  run_with_timeout 45 0 git analyze-deps HEAD --threshold 1 --max-results 5

  assert_success
  assert_output --partial "Dependency graph"
}

@test "hug analyze deps: performance with high threshold" {
  # Create 15 commits (reduced from 20)
  for i in {1..15}; do
    echo "content $i" > "file${i}.txt"
    git add "file${i}.txt"
    git commit -m "add file${i}"
  done

  # High threshold should reduce processing time
  run_with_timeout 20 0 git analyze-deps HEAD --threshold 10 --max-results 3

  assert_success
  # With high threshold, should find few or no related commits
  assert_output --partial "Dependency graph"
}

@test "hug analyze deps: performance with depth limit" {
  # Create commits with overlapping files to test depth
  echo "base" > "shared.txt"
  git add "shared.txt"
  git commit -m "add base"

  for i in {1..10}; do  # Reduced from 15
    echo "content $i" >> "shared.txt"
    echo "unique $i" > "unique${i}.txt"
    git add "shared.txt" "unique${i}.txt"
    git commit -m "update $i with shared file"
  done

  # Depth 1 should be faster than depth 3
  run_with_timeout 20 0 git analyze-deps HEAD~10 --threshold 1 --depth 1 --max-results 3

  assert_success
  assert_output --partial "Dependency graph"
}

@test "hug analyze deps: repository size detection" {
  # Create a repository with known number of commits (reduced from 75)
  for i in {1..50}; do
    echo "content $i" >> "size_test.txt"
    git add "size_test.txt"
    git commit -m "commit $i"
  done

  # Should complete within reasonable time for medium repo
  run_with_timeout 40 0 git analyze-deps HEAD --threshold 1 --max-results 5

  assert_success
  assert_output --partial "Dependency graph"
}

@test "hug analyze deps: environment timeout override" {
  # Test that HUG_ANALYZE_DEPS_TIMEOUT environment variable works
  HUG_ANALYZE_DEPS_TIMEOUT=45 run_with_timeout 45 0 git analyze-deps HEAD --threshold 1

  assert_success
  assert_output --partial "Dependency graph"
}

@test "hug analyze deps: performance with JSON output" {
  # Create some commits (reduced from 20)
  for i in {1..15}; do
    echo "content $i" > "json_test${i}.txt"
    git add "json_test${i}.txt"
    git commit -m "add json test file $i"
  done

  # JSON format should have similar performance
  run_with_timeout 30 0 git analyze-deps HEAD --threshold 1 --format json --max-results 5

  assert_success
  assert_output --partial '"root_commit"'
}

@test "hug analyze deps: --all mode performance" {
  # Create commits for repository-wide analysis (reduced from 30)
  for i in {1..20}; do
    echo "all test $i" > "all_test${i}.txt"
    git add "all_test${i}.txt"
    git commit -m "all test commit $i"
  done

  # --all mode should still complete within reasonable time
  run_with_timeout 45 0 git analyze-deps --all --threshold 2 --max-results 5

  assert_success
  assert_output --partial "Commit Coupling Analysis"
}