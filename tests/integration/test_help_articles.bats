#!/usr/bin/env bats
# End-to-end tests for `hug help :<article>` sigil.
#
# DESIGN NOTE: The `:` sigil routes through git-hughelp → hughelp_dispatch() →
# list_articles() / render_article() / suggest_articles(). These tests cover all
# user-visible behaviors: listing, rendering, pipe-safety (stdout/stderr split),
# typo-suggestion, exit codes, and the top-level tip line.
#
# STDOUT/STDERR CONTRACT (see CLAUDE.md "Stdout/Stderr Discipline"):
#   - stdout = machine-consumable data (slug lines, markdown body)
#   - stderr = human-facing chatter (headers, tips, error messages)
#
# The pipe-safety tests enforce this contract by redirecting stderr to /dev/null
# and asserting that only data lines survive.
#
# LESSON: When verifying typo suggestions, choose a slug whose edit-distance
# to the target falls below the fuzzy-match threshold (≥60 ratio). `:hug-tst`
# is too distant from `:hug-101` (no suggestion rendered); `:hug-10` is close
# enough to trigger "Did you mean". Always probe actual CLI output before writing
# assertion strings.

load ../test_helper

setup() {
  require_hug
  # Articles live in git-config/lib/python/articles/ — checked into the repo.
  # Tests run against the production :hug-101 article; no isolated repo needed
  # because `hug help :` does not operate on the working tree.
  TEST_TEMP_DIR=$(create_temp_repo_dir)
  mkdir -p "$TEST_TEMP_DIR"
}

teardown() {
  rm -rf "$TEST_TEMP_DIR"
}

# --- Listing (hug help :) ---

@test "hug help : lists hug-101 article" {
  cd "$TEST_TEMP_DIR"
  run hug help :
  assert_success
  # Slug + summary land on combined output (BATS merges stdout + stderr).
  assert_output --partial ":hug-101"
  assert_output --partial "Quickstart"
}

@test "hug help : header lands on stderr (stdout-only is pipe-safe)" {
  cd "$TEST_TEMP_DIR"
  # Redirect stderr away; only stdout data should survive.
  # The "── Articles" decorative header must NOT appear on stdout.
  run bash -c "hug help : 2>/dev/null"
  assert_success
  refute_output --partial "── Articles"
  # But the slug line must still reach stdout.
  assert_output --partial ":hug-101"
}

# --- Rendering (hug help :hug-101) ---

@test "hug help :hug-101 renders the article" {
  cd "$TEST_TEMP_DIR"
  run hug help :hug-101
  assert_success
  # Works for both gum-rendered (TTY) and raw-markdown (piped/non-TTY) paths.
  assert_output --partial "Hug 101"
  assert_output --partial "five-minute path"
}

@test "hug help :hug-101 is pipe-safe (raw markdown when not TTY)" {
  cd "$TEST_TEMP_DIR"
  # Piping stdout forces non-TTY mode → render_article emits raw markdown.
  # The H1 heading must be the very first heading line.
  run bash -c "hug help :hug-101 | grep -E '^# ' | head -1"
  assert_success
  assert_output --partial "# Hug 101"
}

# --- Typo suggestion (hug help :<near-miss>) ---

@test "hug help :<near-miss> exits 1 and suggests the closest article" {
  cd "$TEST_TEMP_DIR"
  # `:hug-10` is a clear typo for `:hug-101`: one digit short, fuzzy ratio ≥ 60.
  # LESSON: `:hug-tst` does NOT trigger suggestions (ratio < 60); always
  # pick a near-miss slug that demonstrably shares a long common prefix.
  run hug help :hug-10
  assert_failure
  assert_output --partial "no article named"
  assert_output --partial ":hug-101"
}

# --- No-suggestion path (hug help :<unrelated>) ---

@test "hug help :<totally-unrelated> exits 1 with no suggestions" {
  cd "$TEST_TEMP_DIR"
  # Slug has nothing in common with any article → fuzzy ratio < 60 → no "Did you mean".
  run hug help :zzzzzzzzzz
  assert_failure
  assert_output --partial "no article named"
  refute_output --partial "Did you mean"
}

# --- Top-level tip (hug help) ---

@test "hug help mentions : sigil in top-level topic-search section" {
  cd "$TEST_TEMP_DIR"
  run hug help
  assert_success
  # The top-level help must advertise the : sigil so users can discover articles.
  assert_output --partial "hug help :"
}
