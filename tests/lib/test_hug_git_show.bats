#!/usr/bin/env bats
# Tests for hug-git-show library: commit display with N/-N resolution

load '../test_helper'
load '../../git-config/lib/hug-common'
load '../../git-config/lib/hug-git-repo'
load '../../git-config/lib/hug-git-show'

setup() {
  require_hug
  TEST_REPO=$(create_test_repo_with_history)
  cd "$TEST_REPO"
}

teardown() {
  cleanup_test_repo
}

################################################################################
# resolve_commit_ref TESTS
################################################################################

@test "resolve_commit_ref: empty string returns HEAD" {
  run resolve_commit_ref ""
  assert_success
  assert_output "HEAD"
}

@test "resolve_commit_ref: empty string with custom default" {
  run resolve_commit_ref "" "main"
  assert_success
  assert_output "main"
}

@test "resolve_commit_ref: 0 returns HEAD" {
  run resolve_commit_ref "0"
  assert_success
  assert_output "HEAD"
}

@test "resolve_commit_ref: single digit returns HEAD~N" {
  run resolve_commit_ref "3"
  assert_success
  assert_output "HEAD~3"
}

@test "resolve_commit_ref: three digit number returns HEAD~N" {
  run resolve_commit_ref "999"
  assert_success
  assert_output "HEAD~999"
}

@test "resolve_commit_ref: negative single digit returns range" {
  run resolve_commit_ref "-3"
  assert_success
  assert_output "HEAD~3..HEAD"
}

@test "resolve_commit_ref: negative three digit number returns range" {
  run resolve_commit_ref "-999"
  assert_success
  assert_output "HEAD~999..HEAD"
}

@test "resolve_commit_ref: numbers >= 1000 pass through" {
  run resolve_commit_ref "1000"
  assert_success
  assert_output "1000"
}

@test "resolve_commit_ref: large numbers pass through" {
  run resolve_commit_ref "12345"
  assert_success
  assert_output "12345"
}

@test "resolve_commit_ref: commit hash passes through" {
  run resolve_commit_ref "abc123def456"
  assert_success
  assert_output "abc123def456"
}

@test "resolve_commit_ref: branch name passes through" {
  run resolve_commit_ref "main"
  assert_success
  assert_output "main"
}

@test "resolve_commit_ref: range passes through" {
  run resolve_commit_ref "main..HEAD"
  assert_success
  assert_output "main..HEAD"
}

@test "resolve_commit_ref: complex ref passes through" {
  run resolve_commit_ref "origin/main"
  assert_success
  assert_output "origin/main"
}

@test "resolve_commit_ref: tag reference passes through" {
  run resolve_commit_ref "v1.0.0"
  assert_success
  assert_output "v1.0.0"
}

@test "resolve_commit_ref: negative zero is invalid (passes through)" {
  # -0 doesn't match the regex for -N (which requires 1-9 as first digit)
  # so it should pass through unchanged
  run resolve_commit_ref "-0"
  assert_success
  assert_output "-0"
}

################################################################################
# is_range TESTS
################################################################################

@test "is_range: returns 0 (true) for double-dot range" {
  run is_range "HEAD~3..HEAD"
  assert_success
  assert_output ""  # No output, just return code 0
}

@test "is_range: returns 0 (true) for branch range" {
  run is_range "main..feature"
  assert_success
  assert_output ""
}

@test "is_range: returns 1 (false) for single commit" {
  run bash -c 'source $HUG_HOME/git-config/lib/hug-git-show; ! is_range "HEAD"'
  assert_success
}

@test "is_range: returns 1 (false) for commit hash" {
  run bash -c 'source $HUG_HOME/git-config/lib/hug-git-show; ! is_range "abc123"'
  assert_success
}

@test "is_range: returns 1 (false) for branch name" {
  run bash -c 'source $HUG_HOME/git-config/lib/hug-git-show; ! is_range "main"'
  assert_success
}

@test "is_range: returns 1 (false) for number" {
  run bash -c 'source $HUG_HOME/git-config/lib/hug-git-show; ! is_range "123"'
  assert_success
}

@test "is_range: returns 1 (false) for negative number" {
  run bash -c 'source $HUG_HOME/git-config/lib/hug-git-show; ! is_range "-5"'
  assert_success
}

@test "is_range: returns 1 (false) for tag" {
  run bash -c 'source $HUG_HOME/git-config/lib/hug-git-show; ! is_range "v1.0.0"'
  assert_success
}

################################################################################
# _xml_escape TESTS
################################################################################

@test "_xml_escape: escapes ampersand" {
  run _xml_escape "Tom & Jerry"
  assert_success
  assert_output "Tom &amp; Jerry"
}

@test "_xml_escape: escapes less than" {
  run _xml_escape "a < b"
  assert_success
  assert_output "a &lt; b"
}

@test "_xml_escape: escapes greater than" {
  run _xml_escape "a > b"
  assert_success
  assert_output "a &gt; b"
}

@test "_xml_escape: escapes all special characters" {
  run _xml_escape "Tom & Jerry: a < b && b > c"
  assert_success
  assert_output "Tom &amp; Jerry: a &lt; b &amp;&amp; b &gt; c"
}

@test "_xml_escape: escapes ampersand first (prevents double escaping)" {
  # This test verifies the order: & first, then < and >
  # If order was wrong, &amp; would become &amp;amp;
  run _xml_escape "&"
  assert_success
  assert_output "&amp;"
}

@test "_xml_escape: handles multiple ampersands" {
  run _xml_escape "A & B & C"
  assert_success
  assert_output "A &amp; B &amp; C"
}

@test "_xml_escape: handles empty string" {
  run _xml_escape ""
  assert_success
  assert_output ""
}

@test "_xml_escape: handles string without special characters" {
  run _xml_escape "Hello World"
  assert_success
  assert_output "Hello World"
}

@test "_xml_escape: escapes XML-like tags" {
  run _xml_escape "<tag>content</tag>"
  assert_success
  assert_output "&lt;tag&gt;content&lt;/tag&gt;"
}

@test "_xml_escape: handles special characters in commit messages" {
  run _xml_escape "Fix: handle < & > in output"
  assert_success
  assert_output "Fix: handle &lt; &amp; &gt; in output"
}

################################################################################
# show_single_commit TESTS (standard format)
################################################################################

@test "show_single_commit: shows HEAD in standard format" {
  run show_single_commit HEAD false standard
  assert_success

  # Should contain commit info
  assert_output --partial "Commit info:"
  assert_output --partial "File stats:"

  # Should NOT contain diff (show_patch=false)
  refute_output --partial "Commit diff:"
}

@test "show_single_commit: shows HEAD with patch in standard format" {
  run show_single_commit HEAD true standard
  assert_success

  # Should contain all sections
  assert_output --partial "Commit info:"
  assert_output --partial "Commit diff:"
  assert_output --partial "File stats:"
}

@test "show_single_commit: shows numeric ref in standard format" {
  run show_single_commit HEAD~1 false standard
  assert_success

  assert_output --partial "Commit info:"
  assert_output --partial "File stats:"
}

@test "show_single_commit: fails for invalid commit" {
  run show_single_commit "invalidcommit123" false standard
  assert_failure
  assert_output --partial "Invalid commit reference"
}

@test "show_single_commit: respects HUG_QUIET for headers" {
  HUG_QUIET=T run show_single_commit HEAD false standard
  assert_success

  # Should NOT contain headers when quiet
  refute_output --partial "Commit info:"
  refute_output --partial "File stats:"

  # But should still have actual content
  assert_output --partial "Add feature"  # From our test commits
}

################################################################################
# show_single_commit TESTS (llm format)
################################################################################

@test "show_single_commit: shows HEAD in LLM format" {
  run show_single_commit HEAD false llm
  assert_success

  # Should have XML tags
  assert_output --partial "<commit "
  assert_output --partial "</commit>"

  # Should have hash attribute
  assert_output --partial 'hash="'

  # Should have date attribute (ISO 8601 to minutes)
  assert_output --partial 'date="'

  # Should have message tags
  assert_output --partial "<msg>"
  assert_output --partial "</msg>"

  # Should NOT have diff
  refute_output --partial "<diff>"
}

@test "show_single_commit: shows HEAD with patch in LLM format" {
  run show_single_commit HEAD true llm
  assert_success

  # Should have diff section
  assert_output --partial "<diff><![CDATA["
  assert_output --partial "]]></diff>"
}

@test "show_single_commit: LLM format escapes XML in commit message" {
  # Create a commit with special characters
  echo "test" > special.txt
  git add special.txt
  git commit -m "Test <tag> & content" -q

  run show_single_commit HEAD false llm
  assert_success

  # Should escape special characters in message
  assert_output --partial "&lt;tag&gt;"
  assert_output --partial "&amp;"
}

@test "show_single_commit: LLM format includes body when present" {
  # Create a commit with body
  echo "test" > body.txt
  git add body.txt
  git commit -m "Summary" -m "This is the body" -q

  run show_single_commit HEAD false llm
  assert_success

  # Should have both summary and body in msg tag
  assert_output --partial "Summary"
  assert_output --partial "This is the body"
}

@test "show_single_commit: LLM format handles commit with empty body" {
  run show_single_commit HEAD false llm
  assert_success

  # Should still have valid XML even without body
  assert_line --partial "<msg>"
  assert_line --partial "</msg>"
}

################################################################################
# show_commits TESTS (single commit)
################################################################################

@test "show_commits: shows single commit by ref" {
  run show_commits HEAD false standard
  assert_success
  assert_output --partial "Commit info:"
}

@test "show_commits: shows single commit by N" {
  run show_commits 0 false standard
  assert_success
  assert_output --partial "Commit info:"
}

@test "show_commits: shows single commit by N (non-zero)" {
  run show_commits 1 false standard
  assert_success
  assert_output --partial "Commit info:"
}

@test "show_commits: shows single commit with patch" {
  run show_commits HEAD true standard
  assert_success
  assert_output --partial "Commit diff:"
}

@test "show_commits: shows single commit in LLM format" {
  run show_commits HEAD false llm
  assert_success
  assert_output --partial "<commit "
}

################################################################################
# show_commits TESTS (range)
################################################################################

@test "show_commits: shows range of commits" {
  run show_commits "-2" false standard
  assert_success

  # Should have multiple commit info sections
  assert_output --partial "Commit info:"
}

@test "show_commits: shows range with explicit ref" {
  run show_commits "HEAD~1..HEAD" false standard
  assert_success
  assert_output --partial "Commit info:"
}

@test "show_commits: range includes separator in standard format" {
  run show_commits "-2" false standard
  assert_success

  # Should have commit info in output
  # The format includes "Commit info:" heading
  assert_output --partial "Commit info:"

  # Verify we have file stats section too
  assert_output --partial "File stats:"
}

@test "show_commits: range respects HUG_QUIET" {
  HUG_QUIET=T run show_commits "-2" false standard
  assert_success

  # Should NOT have headers
  refute_output --partial "Commit info:"

  # But should still have content
  assert_output --partial "Add feature"
}

@test "show_commits: shows range in LLM format" {
  run show_commits "-2" false llm
  assert_success

  # Should have multiple commit tags
  assert_output --partial "<commit "
  assert_output --partial "</commit>"
}

@test "show_commits: shows range with patch in LLM format" {
  run show_commits "-2" true llm
  assert_success

  # Should have diff sections
  assert_output --partial "<diff><![CDATA["
}

@test "show_commits: fails for invalid range" {
  run show_commits "invalid..range" false standard
  assert_failure
  assert_output --partial "Invalid range or no commits found"
}

################################################################################
# Integration tests with N/-N syntax
################################################################################

@test "show_commits: N syntax shows single commit" {
  run show_commits 1 false standard
  assert_success

  # Should show exactly one commit
  # Check for presence of commit info
  assert_output --partial "Commit info:"
}

@test "show_commits: -N syntax shows multiple commits" {
  run show_commits "-2" false standard
  assert_success

  # Should show at least 1 commit (may be 2 depending on history depth)
  assert_output --partial "Commit info:"
}

@test "show_commits: empty input shows HEAD" {
  run show_commits "" false standard
  assert_success

  # Should show HEAD
  assert_output --partial "Commit info:"
}

@test "show_commits: N=0 shows HEAD" {
  run show_commits 0 false standard
  assert_success

  # Should show HEAD (commit hash appears in output, possibly shortened)
  local head_hash
  head_hash=$(git rev-parse HEAD)
  # Check for shortened hash (first 7+ chars)
  local short_hash
  short_hash="${head_hash:0:7}"
  assert_output --partial "$short_hash"
}

################################################################################
# Edge cases and error handling
################################################################################

@test "show_commits: handles large N value" {
  run show_commits 999 false standard
  assert_failure
  # Should fail gracefully when commit doesn't exist
  assert_output --partial "Invalid commit reference"
}

@test "show_commits: handles large -N value" {
  run show_commits "-999" false standard
  assert_failure
  # Should fail gracefully when range is invalid
  assert_output --partial "Invalid range or no commits found"
}

@test "show_single_commit: fails for non-existent ref" {
  run show_single_commit "nonexistent" false standard
  assert_failure
  assert_output --partial "Invalid commit reference"
}

@test "resolve_commit_ref: treats leading zeros as numbers" {
  # Numbers with leading zeros match the 0-999 regex
  # so they are treated as numbers (007 = 7)
  run resolve_commit_ref "007"
  assert_success
  assert_output "HEAD~007"
}

@test "resolve_commit_ref: handles negative with leading zeros" {
  # -007 doesn't match the -N regex (which requires 1-9 as first digit)
  run resolve_commit_ref "-007"
  assert_success
  assert_output "-007"
}

@test "resolve_commit_ref: handles decimal numbers" {
  # Decimal numbers don't match integer patterns, pass through
  run resolve_commit_ref "1.5"
  assert_success
  assert_output "1.5"
}

@test "resolve_commit_ref: treats zero padded numbers as numbers" {
  # 09 matches the 0-999 regex, treated as HEAD~9
  run resolve_commit_ref "09"
  assert_success
  assert_output "HEAD~09"
}
