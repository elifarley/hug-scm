#!/usr/bin/env bats
# Tests for hug-cli-flags library: CLI flag parsing utilities

load '../test_helper'
load '../../git-config/lib/hug-output'
load '../../git-config/lib/hug-cli-flags'

setup() {
  export HUG_DISABLE_GUM=true
}

teardown() {
  unset HUG_DISABLE_GUM
  unset HUG_FORCE
  unset HUG_QUIET
  unset HUG_YES
  unset HUG_INTERACTIVE_FILE_SELECTION
}

@test "hug-cli-flags: parse_common_flags sets dry_run=true for --dry-run" {
  # Act
  eval "$(parse_common_flags --dry-run arg1 arg2)"
  
  # Assert
  assert_equal "$dry_run" "true"
  assert_equal "$1" "arg1"
  assert_equal "$2" "arg2"
}

@test "hug-cli-flags: parse_common_flags sets force=true for -f" {
  # Act
  eval "$(parse_common_flags -f arg1)"
  
  # Assert
  assert_equal "$force" "true"
  assert_equal "${HUG_FORCE:-}" "true"
  assert_equal "$1" "arg1"
}

@test "hug-cli-flags: parse_common_flags sets force=true for --force" {
  # Act
  eval "$(parse_common_flags --force arg1)"
  
  # Assert
  assert_equal "$force" "true"
  assert_equal "${HUG_FORCE:-}" "true"
  assert_equal "$1" "arg1"
}

@test "hug-cli-flags: parse_common_flags exports HUG_QUIET for --quiet" {
  # Act
  eval "$(parse_common_flags --quiet arg1)"
  
  # Assert
  assert_equal "${HUG_QUIET:-}" "T"
  assert_equal "$1" "arg1"
}

@test "hug-cli-flags: parse_common_flags handles multiple flags" {
  # Act
  eval "$(parse_common_flags --dry-run -f --quiet arg1 arg2)"
  
  # Assert
  assert_equal "$dry_run" "true"
  assert_equal "$force" "true"
  assert_equal "${HUG_FORCE:-}" "true"
  assert_equal "${HUG_QUIET:-}" "T"
  assert_equal "$1" "arg1"
  assert_equal "$2" "arg2"
}

@test "hug-cli-flags: parse_common_flags handles -- as separator" {
  # Act
  eval "$(parse_common_flags arg1 -- arg2 arg3)"
  
  # Assert
  assert_equal "$1" "arg1"
  assert_equal "$2" "arg2"
  assert_equal "$3" "arg3"
}

@test "hug-cli-flags: parse_common_flags sets HUG_INTERACTIVE_FILE_SELECTION when -- is last arg" {
  # Act
  eval "$(parse_common_flags arg1 arg2 --)"
  
  # Assert
  assert_equal "${HUG_INTERACTIVE_FILE_SELECTION:-}" "true"
  assert_equal "$1" "arg1"
  assert_equal "$2" "arg2"
  assert_equal "$#" "2"
}

@test "hug-cli-flags: parse_common_flags handles no arguments" {
  # Act
  eval "$(parse_common_flags)"
  
  # Assert
  assert_equal "$#" "0"
}

@test "hug-cli-flags: parse_common_flags preserves non-flag arguments" {
  # Act
  eval "$(parse_common_flags --dry-run file1.txt file2.txt)"
  
  # Assert
  assert_equal "$dry_run" "true"
  assert_equal "$1" "file1.txt"
  assert_equal "$2" "file2.txt"
}

@test "hug-cli-flags: parse_common_flags handles flags interspersed with args" {
  # Act
  eval "$(parse_common_flags arg1 --dry-run arg2 -f arg3)"
  
  # Assert
  assert_equal "$dry_run" "true"
  assert_equal "$force" "true"
  assert_equal "$1" "arg1"
  assert_equal "$2" "arg2"
  assert_equal "$3" "arg3"
}

@test "hug-cli-flags: parse_common_flags handles only -- as last argument" {
  # Act
  eval "$(parse_common_flags --)"
  
  # Assert
  assert_equal "${HUG_INTERACTIVE_FILE_SELECTION:-}" "true"
  assert_equal "$#" "0"
}

@test "hug-cli-flags: require_args passes with enough arguments" {
  # Arrange
  export HUG_DISABLE_GUM=true
  
  # Act
  run require_args 2 3 "custom message"
  
  # Assert
  assert_success
}

@test "hug-cli-flags: require_args fails with too few arguments" {
  # Arrange
  export HUG_DISABLE_GUM=true
  
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-cli-flags'
    require_args 3 1
  "
  
  # Assert
  assert_failure
  assert_output --partial "requires at least 3 argument(s)"
}

@test "hug-cli-flags: require_args uses custom error message" {
  # Arrange
  export HUG_DISABLE_GUM=true
  
  # Act
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-cli-flags'
    require_args 2 1 'custom error message'
  "
  
  # Assert
  assert_failure
  assert_output --partial "custom error message"
}

@test "hug-cli-flags: require_args passes when actual equals required" {
  # Arrange
  export HUG_DISABLE_GUM=true
  
  # Act
  run require_args 2 2
  
  # Assert
  assert_success
}

@test "hug-cli-flags: parse_common_flags sets browse_root=true for --browse-root" {
  # Act
  eval "$(parse_common_flags --browse-root)"
  
  # Assert
  assert_equal "$browse_root" "true"
  assert_equal "${HUG_INTERACTIVE_FILE_SELECTION:-}" "true"
  assert_equal "$#" "0"
}

@test "hug-cli-flags: parse_common_flags handles --browse-root with other flags" {
  # Act
  eval "$(parse_common_flags --dry-run --browse-root -f)"
  
  # Assert
  assert_equal "$dry_run" "true"
  assert_equal "$browse_root" "true"
  assert_equal "$force" "true"
  assert_equal "${HUG_INTERACTIVE_FILE_SELECTION:-}" "true"
  assert_equal "$#" "0"
}

@test "hug-cli-flags: parse_common_flags errors when --browse-root used with args even with --" {
  # Act - Using a subshell to capture the error
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-cli-flags'
    eval \"\$(parse_common_flags --browse-root arg1 --)\"
  "
  
  # Assert
  assert_failure
  assert_output --partial "cannot be used with explicit paths"
}

@test "hug-cli-flags: parse_common_flags handles --browse-root alone" {
  # Act
  eval "$(parse_common_flags --browse-root)"
  
  # Assert
  assert_equal "$browse_root" "true"
  assert_equal "$#" "0"
  assert_equal "${HUG_INTERACTIVE_FILE_SELECTION:-}" "true"
}

@test "hug-cli-flags: parse_common_flags errors when --browse-root used with paths" {
  # Act - Using a subshell to capture the error
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-cli-flags'
    eval \"\$(parse_common_flags --browse-root file.txt)\"
  "
  
  # Assert
  assert_failure
  assert_output --partial "cannot be used with explicit paths"
}

@test "hug-cli-flags: check_browse_root_no_paths passes when browse_root is false" {
  # Act
  run check_browse_root_no_paths false true
  
  # Assert
  assert_success
}

@test "hug-cli-flags: check_browse_root_no_paths passes when no paths provided" {
  # Act
  run check_browse_root_no_paths true false
  
  # Assert
  assert_success
}

@test "hug-cli-flags: check_browse_root_no_paths fails when browse_root=true and has_paths=true" {
  # Act - Using a subshell to capture the error
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-cli-flags'
    check_browse_root_no_paths true true
  "
  
  # Assert
  assert_failure
  assert_output --partial "cannot be used with explicit paths"
}

@test "hug-cli-flags: check_browse_root_no_paths passes when both flags are false" {
  # Act
  run check_browse_root_no_paths false false
  
  # Assert
  assert_success
}

# Tests for GNU getopt enhancements

@test "hug-cli-flags: parse_common_flags handles combined short options -fq" {
  # Act
  eval "$(parse_common_flags -fq arg1)"
  
  # Assert
  assert_equal "$force" "true"
  assert_equal "${HUG_FORCE:-}" "true"
  assert_equal "${HUG_QUIET:-}" "T"
  assert_equal "$1" "arg1"
}

@test "hug-cli-flags: parse_common_flags handles combined short options -qf" {
  # Act
  eval "$(parse_common_flags -qf arg1 arg2)"
  
  # Assert
  assert_equal "$force" "true"
  assert_equal "${HUG_FORCE:-}" "true"
  assert_equal "${HUG_QUIET:-}" "T"
  assert_equal "$1" "arg1"
  assert_equal "$2" "arg2"
}

@test "hug-cli-flags: parse_common_flags handles -q short option for quiet" {
  # Act
  eval "$(parse_common_flags -q arg1)"
  
  # Assert
  assert_equal "${HUG_QUIET:-}" "T"
  assert_equal "$1" "arg1"
}

@test "hug-cli-flags: parse_common_flags handles combined -fqh (exits via help)" {
  # Act - Using a subshell to capture the help exit
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-cli-flags'
    show_help() { echo 'Help text'; }
    eval \"\$(parse_common_flags -fqh arg1)\"
  "
  
  # Assert
  assert_success
  assert_output "Help text"
}

@test "hug-cli-flags: parse_common_flags properly reorders options before args" {
  # With GNU getopt, options can come after args and will be reordered
  # Act
  eval "$(parse_common_flags arg1 --dry-run arg2 -f arg3 --quiet)"

  # Assert
  assert_equal "$dry_run" "true"
  assert_equal "$force" "true"
  assert_equal "${HUG_QUIET:-}" "T"
  assert_equal "$1" "arg1"
  assert_equal "$2" "arg2"
  assert_equal "$3" "arg3"
}

# -----------------------------------------------------------------------------
# parse_pathspecs tests (pathspec splitting at first --)
# -----------------------------------------------------------------------------

@test "hug-cli-flags: parse_pathspecs with no args returns empty arrays" {
  eval "$(parse_pathspecs)"

  assert_equal "${#_pathspec_pre_args[@]}" "0"
  assert_equal "${#_pathspec_pathspecs[@]}" "0"
}

@test "hug-cli-flags: parse_pathspecs with only commit ref has no pathspecs" {
  eval "$(parse_pathspecs HEAD)"

  assert_equal "${#_pathspec_pre_args[@]}" "1"
  assert_equal "${_pathspec_pre_args[0]}" "HEAD"
  assert_equal "${#_pathspec_pathspecs[@]}" "0"
}

@test "hug-cli-flags: parse_pathspecs with bare -- at end has empty pathspecs" {
  eval "$(parse_pathspecs HEAD --)"

  assert_equal "${#_pathspec_pre_args[@]}" "1"
  assert_equal "${_pathspec_pre_args[0]}" "HEAD"
  assert_equal "${#_pathspec_pathspecs[@]}" "0"
}

@test "hug-cli-flags: parse_pathspecs splits HEAD -- '*.txt'" {
  eval "$(parse_pathspecs HEAD -- '*.txt')"

  assert_equal "${#_pathspec_pre_args[@]}" "1"
  assert_equal "${_pathspec_pre_args[0]}" "HEAD"
  assert_equal "${#_pathspec_pathspecs[@]}" "1"
  assert_equal "${_pathspec_pathspecs[0]}" "*.txt"
}

@test "hug-cli-flags: parse_pathspecs splits -3 -- src/lib/ tests/" {
  eval "$(parse_pathspecs -3 -- src/lib/ tests/)"

  assert_equal "${#_pathspec_pre_args[@]}" "1"
  assert_equal "${_pathspec_pre_args[0]}" "-3"
  assert_equal "${#_pathspec_pathspecs[@]}" "2"
  assert_equal "${_pathspec_pathspecs[0]}" "src/lib/"
  assert_equal "${_pathspec_pathspecs[1]}" "tests/"
}

@test "hug-cli-flags: parse_pathspecs handles path with spaces" {
  eval "$(parse_pathspecs HEAD -- 'path with spaces.txt')"

  assert_equal "${#_pathspec_pre_args[@]}" "1"
  assert_equal "${_pathspec_pre_args[0]}" "HEAD"
  assert_equal "${#_pathspec_pathspecs[@]}" "1"
  assert_equal "${_pathspec_pathspecs[0]}" "path with spaces.txt"
}

@test "hug-cli-flags: parse_pathspecs only first -- splits, second is literal" {
  eval "$(parse_pathspecs HEAD -- 'path1' -- 'path2')"

  assert_equal "${#_pathspec_pre_args[@]}" "1"
  assert_equal "${_pathspec_pre_args[0]}" "HEAD"
  # Second -- and path2 are both pathspec data
  assert_equal "${#_pathspec_pathspecs[@]}" "3"
  assert_equal "${_pathspec_pathspecs[0]}" "path1"
  assert_equal "${_pathspec_pathspecs[1]}" "--"
  assert_equal "${_pathspec_pathspecs[2]}" "path2"
}

@test "hug-cli-flags: parse_pathspecs treats --help after -- as pathspec" {
  eval "$(parse_pathspecs HEAD -- --help)"

  assert_equal "${#_pathspec_pre_args[@]}" "1"
  assert_equal "${_pathspec_pre_args[0]}" "HEAD"
  assert_equal "${#_pathspec_pathspecs[@]}" "1"
  assert_equal "${_pathspec_pathspecs[0]}" "--help"
}

# ============================================================================
# HUG_YES tests: -y/--yes flag parsing
# ============================================================================

@test "hug-cli-flags: parse_common_flags exports HUG_YES for -y" {
  eval "$(parse_common_flags -y arg1)"

  assert_equal "${HUG_YES:-}" "true"
  assert_equal "$1" "arg1"
}

@test "hug-cli-flags: parse_common_flags exports HUG_YES for --yes" {
  eval "$(parse_common_flags --yes arg1)"

  assert_equal "${HUG_YES:-}" "true"
  assert_equal "$1" "arg1"
}

@test "hug-cli-flags: parse_common_flags handles -y with other flags" {
  eval "$(parse_common_flags -y --dry-run arg1)"

  assert_equal "${HUG_YES:-}" "true"
  assert_equal "$dry_run" "true"
  assert_equal "$1" "arg1"
}

@test "hug-cli-flags: parse_common_flags handles -fy combined" {
  eval "$(parse_common_flags -fy arg1)"

  assert_equal "${HUG_FORCE:-}" "true"
  assert_equal "${HUG_YES:-}" "true"
  assert_equal "$1" "arg1"
}

@test "hug-cli-flags: parse_common_flags fallback handles -y" {
  # Pass an unknown option to trigger the fallback path
  eval "$(parse_common_flags -y --unknown-opt arg1 2>/dev/null)" || true

  assert_equal "${HUG_YES:-}" "true"
}

# -----------------------------------------------------------------------------
# parse_common_flags_with_pathspecs tests (fixed-order parsing + picker export)
# -----------------------------------------------------------------------------

@test "hug-cli-flags: parse_common_flags_with_pathspecs: splits pathspecs and parses pre-args" {
  eval "$(parse_common_flags_with_pathspecs --dry-run HEAD --stat -- '*.java' 'src/')"
  [[ "${_pathspec_pathspecs[0]}" == '*.java' ]]
  [[ "${_pathspec_pathspecs[1]}" == 'src/' ]]
  [[ "${dry_run:-}" == true ]]
  # The caller's "$@" holds the remaining pre-args (flags consumed, pathspecs split off)
  [[ "$#" -eq 2 ]]
  [[ "$1" == "HEAD" ]]
  [[ "$2" == "--stat" ]]
}

@test "hug-cli-flags: parse_common_flags_with_pathspecs: without --picker, trailing bare -- is inert" {
  unset HUG_INTERACTIVE_FILE_SELECTION || true
  eval "$(parse_common_flags_with_pathspecs --)"
  [[ -z "${HUG_INTERACTIVE_FILE_SELECTION:-}" ]]
  [[ ${#_pathspec_pathspecs[@]} -eq 0 ]]
}

@test "hug-cli-flags: parse_common_flags_with_pathspecs: with --picker, trailing bare -- exports the flag" {
  unset HUG_INTERACTIVE_FILE_SELECTION || true
  eval "$(parse_common_flags_with_pathspecs --picker --)"
  [[ "${HUG_INTERACTIVE_FILE_SELECTION:-}" == true ]]
}

@test "hug-cli-flags: parse_common_flags_with_pathspecs: empty args are set -u safe" {
  # Actually exercise set -u: unset-parameter expansion inside would abort the subshell.
  # The assertion must live INSIDE the subshell — assignments there don't escape it,
  # so asserting outside would inspect an untouched array and pass vacuously.
  ( set -u; eval "$(parse_common_flags_with_pathspecs)"; [[ ${#_pathspec_pathspecs[@]} -eq 0 ]] )
}

@test "hug-cli-flags: parse_common_flags_with_pathspecs: --picker is a reserved first token" {
  eval "$(parse_common_flags_with_pathspecs -- --picker)"
  [[ "${_pathspec_pathspecs[0]}" == '--picker' ]]
}

@test "hug-cli-flags: parse_common_flags_with_pathspecs: exotic filenames and leading-dash round-trip" {
  # '-f' after -- is a FILENAME, not a flag: it must land in the pathspec array
  # verbatim (this is what %q quoting + the -- separator guarantee together).
  eval "$(parse_common_flags_with_pathspecs -- 'file with spaces.txt' -f)"
  [[ "${_pathspec_pathspecs[0]}" == 'file with spaces.txt' ]]
  [[ "${_pathspec_pathspecs[1]}" == '-f' ]]
}

# -----------------------------------------------------------------------------
# pathspec_pathspecs_into / forward_pathspecs_to_picker tests (#298)
# -----------------------------------------------------------------------------

@test "hug-cli-flags: pathspec_pathspecs_into populates caller nameref, empty when none" {
  eval "$(parse_common_flags_with_pathspecs -- src/a.py 'b c')"
  local -a out=(sentinel)
  pathspec_pathspecs_into out
  assert_equal "${#out[@]}" "2"
  assert_equal "${out[0]}" "src/a.py"
  assert_equal "${out[1]}" "b c"

  # A later parse with no pathspecs resets the global — the accessor must
  # reflect that (sentinel gone, zero elements), not keep stale data.
  eval "$(parse_common_flags_with_pathspecs x)"
  local -a out2=(sentinel)
  pathspec_pathspecs_into out2
  assert_equal "${#out2[@]}" "0"
}

@test "hug-cli-flags: pathspec_pathspecs_into is empty and set -u safe before any parse" {
  # Simulate the cross-module case: lib freshly sourced, no parse ran yet —
  # including the harsher variant where the global is entirely UNSET (not
  # just empty). Assertions live INSIDE the subshell: assignments there
  # don't escape it, so asserting outside would pass vacuously.
  (
    set -u
    unset _pathspec_pathspecs
    local -a out=(sentinel)
    pathspec_pathspecs_into out
    [[ ${#out[@]} -eq 0 ]]
  )
}

@test "hug-cli-flags: pathspec_pathspecs_into round-trips exotic pathspecs exactly" {
  # Element-by-element equality against the ORIGINAL array — not output
  # substrings — is the contract: whatever the user typed after -- must
  # survive parse + eval + accessor byte-for-byte.
  local -a want=(
    $'line1\nline2'
    'has "double" quotes'
    'back\slash'
    '$(echo not-executed)'
    'tick`id`tock'
    '*.[ch]?'
    '-f'
    '--staged'
  )
  eval "$(parse_common_flags_with_pathspecs -- "${want[@]}")"
  local -a out=()
  pathspec_pathspecs_into out
  assert_equal "${#out[@]}" "${#want[@]}"
  local i
  for i in "${!want[@]}"; do
    assert_equal "${out[$i]}" "${want[$i]}"
  done
}

@test "hug-cli-flags: forward_pathspecs_to_picker appends nothing when empty" {
  eval "$(parse_common_flags_with_pathspecs --)"
  local -a opts=("--staged")
  forward_pathspecs_to_picker opts
  assert_equal "${#opts[@]}" "1"
  assert_equal "${opts[*]}" "--staged"
}

@test "hug-cli-flags: forward_pathspecs_to_picker appends -- and pathspecs when set" {
  local -a opts=("--staged")
  eval "$(parse_common_flags_with_pathspecs -- src/)"
  forward_pathspecs_to_picker opts
  assert_equal "${#opts[@]}" "3"
  assert_equal "${opts[0]}" "--staged"
  assert_equal "${opts[1]}" "--"
  assert_equal "${opts[2]}" "src/"
}

@test "hug-cli-flags: forward_pathspecs_to_picker keeps option-like pathspecs as data" {
  # '--staged' after the separator is a PATHSPEC; the protective emitted
  # '--' is what keeps it data when the picker array is consumed later.
  local -a opts=()
  eval "$(parse_common_flags_with_pathspecs -- --staged 'a b')"
  forward_pathspecs_to_picker opts
  assert_equal "${#opts[@]}" "3"
  assert_equal "${opts[0]}" "--"
  assert_equal "${opts[1]}" "--staged"
  assert_equal "${opts[2]}" "a b"
}

@test "hug-cli-flags: forward_pathspecs_to_picker is set -u safe with unset global" {
  # Helper used before any parse AND before the load-time declare could
  # matter (e.g. re-sourced in a subshell that unset the global) — must not
  # kill the shell under set -u, and must append nothing.
  (
    set -u
    unset _pathspec_pathspecs
    local -a opts=("--staged")
    forward_pathspecs_to_picker opts
    [[ ${#opts[@]} -eq 1 && "${opts[0]}" == "--staged" ]]
  )
}

@test "hug-cli-flags: pathspec_pathspecs_into fails loudly on colliding __psx_ caller name" {
  # A caller variable named __psx_out circulars the nameref; Bash must say so
  # (circular name reference) instead of silently misbehaving. The reserved
  # __psx_ prefix is what makes this collision impossible for real callers.
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-cli-flags'
    eval \"\$(parse_common_flags_with_pathspecs -- src/)\"
    __psx_out=()
    pathspec_pathspecs_into __psx_out
  "
  assert_output --partial "circular name reference"
}

# -----------------------------------------------------------------------------
# reject_multiple_files tests (single-file cardinality guard)
# -----------------------------------------------------------------------------

@test "reject_multiple_files: rejects two files naming the command" {
  # Act - full-sourcing subshell: error() depends on gum_log from hug-gum,
  # which this test file does not load at top level
  run bash -c "
    cd '$BATS_TEST_DIRNAME/../..'
    source 'git-config/lib/hug-terminal'
    source 'git-config/lib/hug-gum'
    source 'git-config/lib/hug-output'
    source 'git-config/lib/hug-cli-flags'
    reject_multiple_files 'hug fa' a.txt b.txt
  "

  # Assert
  assert_failure
  assert_output --partial "hug fa accepts only one file."
}

@test "reject_multiple_files: one file, zero files, and empty strings pass" {
  run reject_multiple_files "hug fa" a.txt
  assert_success
  run reject_multiple_files "hug fa"
  assert_success
  run reject_multiple_files "hug fa" a.txt ""
  assert_success
}
