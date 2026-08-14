#!/usr/bin/env bats
# Structural guard: detect risky `git ... | <early-exit-filter>` patterns that
# race with SIGPIPE under `set -o pipefail`.
#
# WHY: Under pipefail, `git ... | grep -q PATTERN` is racy — grep exits at
# first match, closes the pipe, git gets SIGPIPE (exit 141), and the pipeline
# returns non-zero even though the match succeeded.  The canonical fix is
# capture-then-filter (see hug-git-worktree:397-421 for the reference
# implementation with a detailed WHY comment).
#
# HOW THIS TEST WORKS:
#   1. Scans every script under git-config/{lib,bin}/.
#   2. Skips full-line comments (lines whose first non-whitespace is '#').
#   3. Joins backslash-continued lines into logical lines before matching.
#   4. Searches each logical line for `git ... | <early-exit-filter>` where
#      the filter is one of: grep -[qQ], head -[0-9], awk.*exit.
#   5. For each match, checks whether any of the 3 preceding *original* (non-
#      joined) lines carry a `# SIGPIPE-safe:` annotation.
#   6. Fails with a diagnostic listing every unannotated site.
#
# To annotate a site, place `# SIGPIPE-safe: <reason>` on or within 3 lines
# above the pipe.  Example reasons:
#   # SIGPIPE-safe: TODO (Commit N)
#   # SIGPIPE-safe: already fixed (capture-then-filter)
#   # SIGPIPE-safe: output bounded by --max-count=1

load '../test_helper'

# Directory where the library and command scripts live.
HUG_LIB_DIR="$BATS_TEST_DIRNAME/../../git-config/lib"
HUG_BIN_DIR="$BATS_TEST_DIRNAME/../../git-config/bin"

# ---------------------------------------------------------------------------
# scan_sigpipe_races <dir>
#
# Scans all regular files under <dir> (non-recursive — files are flat) for
# risky SIGPIPE pipe patterns.  Prints one line per violation to stdout:
#   <file>:<line>: <matched pipe text>
#
# Returns 0 if no violations found, 1 otherwise.
# ---------------------------------------------------------------------------
scan_sigpipe_races() {
  local dir="$1"
  local violations=0

  # Collect target files (only regular, executable or sourced scripts).
  # We use an array so that globbing is safe even with spaces in paths.
  local -a files=()
  while IFS= read -r -d '' f; do
    files+=( "$f" )
  done < <(find "$dir" -maxdepth 1 -type f -print0 | sort -z)

  local file
  for file in "${files[@]}"; do
    # Read the entire file into an array of original lines.
    local -a lines=()
    while IFS= read -r line || [[ -n "$line" ]]; do
      lines+=( "$line" )
    done < "$file"

    local total_lines=${#lines[@]}
    local i=0

    while (( i < total_lines )); do
      local logical_line="${lines[$i]}"
      local start_idx=$i   # remember first physical line of this logical line

      # --- Join backslash-continuations ---
      # If the current line ends with '\', the next line continues it.
      while [[ "$logical_line" =~ \\$ ]] && (( i + 1 < total_lines )); do
        logical_line="${logical_line%\\} ${lines[$((i+1))]}"
        (( i++ )) || true
      done

      local end_idx=$i  # last physical line of this logical line

      # --- Skip full-line comments ---
      # A logical line that starts with optional whitespace then '#' is a
      # comment — even if it contains example code like `git ... | grep -q`.
      # This is critical: hug-git-worktree:401-406 has a WHY comment with
      # example pipe patterns that must NOT be flagged.
      if [[ "$logical_line" =~ ^[[:space:]]*# ]]; then
        (( i++ )) || true
        continue
      fi

      # --- Match risky pipe patterns ---
      # We look for `git` piped to an early-exit consumer.
      # High-risk patterns:
      #   git ... | grep -[qQ]      — exits at first match
      #   git ... | head -N          — exits after N lines
      #   git ... | head -n N        — same, explicit -n flag
      #   git ... | head -"$var"     — same, variable argument
      #   git ... | awk '... exit'   — can exit early
      #
      # We intentionally do NOT flag: wc, tail, sort, cut, tr, sed (without q/Q)
      # as these generally read to EOF.
      #
      # IMPORTANT: The git command may appear after `$(` (command substitution)
      # so we do NOT anchor to start-of-line — the regex just needs `git`
      # followed by a pipe and an early-exit filter somewhere on the line.
      local matched=false
      local match_text=""

      # Pattern: git ... | grep -[qQ]  (grep quiet mode — exits at first match)
      if [[ "$logical_line" =~ git[[:space:]].*\|[[:space:]]*.*grep[[:space:]]+-[qQ] ]]; then
        matched=true
        match_text="git...| grep -[qQ]"
      fi

      # Pattern: git ... | head -<N>  (head — exits after N lines)
      # Covers: head -1, head -20, head -5
      if ! $matched && [[ "$logical_line" =~ git[[:space:]].*\|[[:space:]]*.*head[[:space:]]+-[0-9] ]]; then
        matched=true
        match_text="git...| head -N"
      fi

      # Pattern: git ... | head -n<N> or head -n <N>  (head with -n flag)
      # Covers: head -n1, head -n 1, head -n1)
      if ! $matched && [[ "$logical_line" =~ git[[:space:]].*\|[[:space:]]*.*head[[:space:]]+-n[[:space:]]*[0-9] ]]; then
        matched=true
        match_text="git...| head -nN"
      fi

      # Pattern: git ... | head -"$var"  (head with variable argument)
      # Covers: head -"$top_n", head -"$count"
      if ! $matched && [[ "$logical_line" =~ git[[:space:]].*\|[[:space:]]*.*head[[:space:]]+-\" ]]; then
        matched=true
        match_text="git...| head -\"\$var\""
      fi

      # Pattern: git ... | awk '... exit ...'  (awk with early exit)
      # This is broader — awk scripts with exit can terminate early.
      if ! $matched && [[ "$logical_line" =~ git[[:space:]].*\|[[:space:]]*.*awk.*exit ]]; then
        matched=true
        match_text="git...| awk...exit"
      fi

      # Pattern: multi-stage pipe with head in it: git ... | ... | head -<any>
      # Catches cases like `git ... | sort | uniq -c | sort -rn | head -5`
      # Matches head with -N, -nN, -n N, or -"$var"
      if ! $matched && [[ "$logical_line" =~ git[[:space:]].*\|.*\|[[:space:]]*.*head[[:space:]]+- ]]; then
        matched=true
        match_text="git...|...| head (multi-stage)"
      fi

      # Pattern: multi-stage pipe with grep -[qQ] after intermediate filter
      # e.g., git ... | cut ... | grep -q
      if ! $matched && [[ "$logical_line" =~ git[[:space:]].*\|.*\|[[:space:]]*.*grep[[:space:]]+-[qQ] ]]; then
        matched=true
        match_text="git...|...| grep -[qQ] (multi-stage)"
      fi

      if $matched; then
        # --- Check for annotation in preceding 3 physical lines ---
        # We look at the original (non-joined) lines before start_idx.
        local annotated=false
        local check_start=$(( start_idx - 1 ))   # line just before
        local check_end=$(( start_idx - 3 ))      # 3 lines before (inclusive)
        (( check_end < 0 )) && check_end=0

        local j
        for (( j = check_start; j >= check_end; j-- )); do
          if [[ "${lines[$j]}" =~ '# SIGPIPE-safe:' ]]; then
            annotated=true
            break
          fi
        done

        if ! $annotated; then
          # Report violation: use 1-based line number for human readability.
          local relpath="${file#$BATS_TEST_DIRNAME/../../}"
          printf '%s:%d: %s  →  %s\n' "$relpath" "$(( start_idx + 1 ))" "$match_text" "${logical_line#"${logical_line%%[![:space:]]*}"}"
          (( violations++ )) || true
        fi
      fi

      (( i++ )) || true
    done
  done

  (( violations == 0 ))
}


################################################################################
# Test: no unannotated SIGPIPE-race pipe patterns in lib/
################################################################################

@test "SIGPIPE guard: lib/ has no unannotated git-piped-to-early-exit patterns" {
  run scan_sigpipe_races "$HUG_LIB_DIR"
  if [[ "$status" -ne 0 ]]; then
    printf 'Unannotated SIGPIPE-race patterns found in lib/:\n%s\n' "$output" >&2
  fi
  assert_success
}


################################################################################
# Test: no unannotated SIGPIPE-race pipe patterns in bin/
################################################################################

@test "SIGPIPE guard: bin/ has no unannotated git-piped-to-early-exit patterns" {
  run scan_sigpipe_races "$HUG_BIN_DIR"
  if [[ "$status" -ne 0 ]]; then
    printf 'Unannotated SIGPIPE-race patterns found in bin/:\n%s\n' "$output" >&2
  fi
  assert_success
}
