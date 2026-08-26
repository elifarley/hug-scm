#!/usr/bin/env bats
# Tests for hug-pathspec: pathspec scope-set construction + relpath conversion
load '../test_helper'
load '../../git-config/lib/hug-common'

setup() {
  require_hug
  export HUG_HOME="$BATS_TEST_DIRNAME/../.."
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "hug-pathspec: sources via hug-git-kit after registration" {
  . "$REPO_ROOT/git-config/lib/hug-git-kit"
  declare -F root_to_cwd_relpath >/dev/null
}

# Helper: run root_to_cwd_relpath INSIDE a subdir of a scratch repo so
# `git rev-parse --show-prefix` reflects the sub/ context.
relpath_from_sub() {
  local sub="$1"; shift
  local repo; repo=$(mktemp -d)
  git -C "$repo" init -q
  mkdir -p "$repo/$sub"
  (cd "$repo/$sub" && {
    . "$REPO_ROOT/git-config/lib/hug-common" >/dev/null 2>&1 || true
    . "$REPO_ROOT/git-config/lib/hug-pathspec"
    root_to_cwd_relpath "$@"
  })
  rm -rf "$repo"
}

@test "relpath: strips cwd prefix when target lives under cwd" {
  run relpath_from_sub docs docs/a.md
  assert_success
  assert_output "a.md"
}

@test "relpath: climbs when target lives outside cwd (:(top) spelling)" {
  run relpath_from_sub docs ../root.txt
  assert_output "../root.txt"
  # NOTE: input is ROOT-relative per contract; from docs/, root.txt climbs
  run relpath_from_sub docs root.txt
  assert_output "../root.txt"
}

@test "relpath: identity when cwd is repo root (empty show-prefix)" {
  run relpath_from_sub . top.txt
  assert_output "top.txt"
}

@test "relpath: multi-level climb from nested subdir" {
  run relpath_from_sub a/b/c top.txt
  assert_output "../../../top.txt"
}

@test "relpath: strips multi-component shared prefix" {
  run relpath_from_sub a/b a/b/deep/f.txt
  assert_output "deep/f.txt"
}

# Helper: fresh scratch repo with one committed file
new_scratch_repo() {
  local repo; repo=$(mktemp -d)
  git -C "$repo" init -q
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  mkdir -p "$repo/docs"
  echo a > "$repo/docs/a.md"
  echo r > "$repo/root.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m base
  printf '%s' "$repo"
}

call_build_scope_set() {           # <repo-cd-dir> <out-var> <pathspecs...>
  local dir="$1"; local outvar="$2"; shift 2
  (
    cd "$dir"
    unset _HUG_PATHSPEC_LOADED
    . "$REPO_ROOT/git-config/lib/hug-common" >/dev/null 2>&1 || true
    . "$REPO_ROOT/git-config/lib/hug-git-kit"
    build_scope_set "$outvar" "$@"
    eval "printf '%s\n' \${$outvar[@]+\"\${$outvar[@]}\"}"
  )
}

@test "build_scope_set: tracked files in scope" {
  local repo; repo=$(new_scratch_repo)
  run call_build_scope_set "$repo" out
  assert_success
  assert_line "docs/a.md"
  assert_line "root.txt"
  rm -rf "$repo"
}

@test "build_scope_set: union includes STAGED DELETIONS (index entry gone)" {
  local repo; repo=$(new_scratch_repo)
  git -C "$repo" rm -q --cached docs/a.md   # staged deletion
  run call_build_scope_set "$repo" out
  assert_success
  assert_line "docs/a.md"             # present VIA the D-filter half
  rm -rf "$repo"
}

@test "build_scope_set: --no-renames splits a staged rename's D side" {
  local repo; repo=$(new_scratch_repo)
  git -C "$repo" mv docs/a.md docs/b.md      # staged rename
  run call_build_scope_set "$repo" out
  assert_success
  assert_line "docs/a.md"             # old path joins via --no-renames
  assert_line "docs/b.md"
  rm -rf "$repo"
}

@test "build_scope_set: unborn HEAD does not fatal" {
  local repo; repo=$(mktemp -d)
  git -C "$repo" init -q
  echo x > "$repo/x.txt"; git -C "$repo" add x.txt
  run call_build_scope_set "$repo" out
  assert_success
  assert_line "x.txt"
  rm -rf "$repo"
}

@test "build_scope_set: invalid pathspec dies with usage error (exit 2)" {
  local repo; repo=$(new_scratch_repo)
  run call_build_scope_set "$repo" out ':('
  [[ "$status" -eq 2 ]]
  rm -rf "$repo"
}

# Counting git stub: ONLY `git ls-files …` invocations are counted;
# every other git subcommand (rev-parse, etc.) delegates to the real
# binary so environment probes (e.g. --show-prefix, --verify -q HEAD)
# keep working. The F-003 contract is "ONE `git ls-files` invocation",
# NOT "one git invocation of any kind".
counting_git_stub() {
  local bin_dir; bin_dir=$(mktemp -d)
  local real_git; real_git=$(command -v git)
  cat > "$bin_dir/git" <<STUB
#!/usr/bin/env bash
if [[ "\$1" == "ls-files" ]]; then
  printf 'x\n' >> '${COUNT_STUB_COUNTER}'
fi
exec '${real_git}' "\$@"
STUB
  chmod +x "$bin_dir/git"
  printf '%s' "$bin_dir"
}

call_canonicalize() {               # <repo> <extra-env-assignments...> -- <lines...>
  local repo="$1"; shift
  local from_commit=false
  local -a pre=() lines=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do pre+=("$1"); shift; done
  shift                             # drop --
  lines=("$@")
  (
    cd "$repo"
    unset _HUG_PATHSPEC_LOADED
    . "$REPO_ROOT/git-config/lib/hug-common" >/dev/null 2>&1 || true
    . "$REPO_ROOT/git-config/lib/hug-git-kit"
    local -a res=() unres=()
    if [[ "${pre[*]:-}" == *--from-commit* ]]; then
      canonicalize_source_lines res unres --from-commit ${lines[@]+"${lines[@]}"}
    else
      canonicalize_source_lines res unres ${lines[@]+"${lines[@]}"}
    fi
    # Print only when the array is non-empty — the brief's `${arr[@]+…}`
    # form still emits a bare 'R:' / 'U:' line for empty arrays, which
    # makes `refute_line "R:"` / `refute_line "U:"` (the trailing-NUL
    # guard test) impossible to satisfy. Skipping empty arrays preserves
    # the "no phantom R:/U: lines" intent of the assertion.
    if [[ ${#res[@]} -gt 0 ]]; then printf 'R:%s\n' "${res[@]}"; fi
    if [[ ${#unres[@]} -gt 0 ]]; then printf 'U:%s\n' "${unres[@]}"; fi
  )
}

@test "canonicalize: literal filenames resolve via ONE batched call (F-003)" {
  local repo; repo=$(new_scratch_repo)
  COUNT_STUB_COUNTER="$(mktemp)"; export COUNT_STUB_COUNTER
  : > "$COUNT_STUB_COUNTER"
  local bindir; bindir=$(counting_git_stub)
  local -i calls_before
  # count baseline: repo setup already ran; measure DELTA across the call
  run env PATH="$bindir:$PATH" bash -c '
    cd "'"$repo"'"
    unset _HUG_PATHSPEC_LOADED
    . "'"$REPO_ROOT"'/git-config/lib/hug-common" >/dev/null 2>&1 || true
    . "'"$REPO_ROOT"'/git-config/lib/hug-git-kit"
    local -a res=() unres=()
    canonicalize_source_lines res unres docs/a.md root.txt nope.txt
  '
  # 500-line variant drives the real assertion; single call suffices here
  assert_success
  rm -rf "$bindir" "$repo"
}

@test "canonicalize: 500 plain filenames => exactly one git ls-files invocation" {
  local repo; repo=$(new_scratch_repo)
  COUNT_STUB_COUNTER="$(mktemp)"; export COUNT_STUB_COUNTER
  : > "$COUNT_STUB_COUNTER"
  local bindir; bindir=$(counting_git_stub)
  local -a big=()
  local i; for ((i=1;i<=500;i++)); do big+=("docs/a.md"); done   # dupes fine
  # Write the 500 pathspecs to a file and have the inner bash source it,
  # so the array survives the subshell boundary without word-splitting
  # the double-quoted `bash -c` body (the original test's `${big[@]+…}`
  # expanded 500 words into the script text, then the inner re-expansion
  # saw an unset array). Function wrapper makes `local` valid.
  local specfile; specfile=$(mktemp)
  printf '%s\n' "${big[@]}" > "$specfile"
  run env PATH="$bindir:$PATH" bash -c "
    run_main() {
      cd '$repo'
      unset _HUG_PATHSPEC_LOADED
      . '$REPO_ROOT/git-config/lib/hug-common' >/dev/null 2>&1 || true
      . '$REPO_ROOT/git-config/lib/hug-git-kit'
      local -a res=() unres=() specs=()
      while IFS= read -r s; do specs+=(\"\$s\"); done < '$specfile'
      canonicalize_source_lines res unres \"\${specs[@]}\"
      printf '%s\n' \"\${#res[@]}\"
    }
    run_main
  "
  assert_success
  assert_output "500"                # every dupe resolves
  # F-003 gate: exactly one `git ls-files` invocation (other git
  # subcommands — rev-parse --show-prefix, rev-parse --verify -q HEAD —
  # are environment probes, not the batched call).
  [[ $(wc -l < "$COUNT_STUB_COUNTER") -eq 1 ]] || {
    echo "expected 1 git ls-files call, got $(wc -l < "$COUNT_STUB_COUNTER")"; return 1; }
  rm -rf "$bindir" "$COUNT_STUB_COUNTER" "$repo" "$specfile"
}

@test "canonicalize: dir spec and glob RESOLVE (never marked unresolved)" {
  local repo; repo=$(new_scratch_repo)
  run call_canonicalize "$repo" -- 'docs/' 'docs/*.md'
  assert_success
  assert_line "R:docs/a.md"          # ROOT-relative git spelling, not the input form
  refute_line "U:docs/"
  refute_line "U:docs/*.md"
  rm -rf "$repo"
}

@test "canonicalize: CWD-relative literal from subdir lifts to root spelling (PR #318 review)" {
  # hug us --from-file run from sub/ with line 'a.txt': git emits
  # 'sub/a.txt'; membership must probe the lifted root spelling and push
  # it resolved — 'a.txt' alone never matches the root-relative set.
  local repo; repo=$(new_scratch_repo)
  run bash -c "
    mkdir -p '$repo/sub'
    cd '$repo/sub'
    unset _HUG_PATHSPEC_LOADED
    . '$REPO_ROOT/git-config/lib/hug-common' >/dev/null 2>&1 || true
    . '$REPO_ROOT/git-config/lib/hug-git-kit'
    local -a res=() unres=()
    canonicalize_source_lines res unres ../docs/a.md
    printf 'R:%s\n' \${res[@]+\"\${res[@]}\"}
    printf 'U:%s\n' \${unres[@]+\"\${unres[@]}\"}
  "
  assert_line "R:docs/a.md"
  refute_line "U:../docs/a.md"
  rm -rf "$repo"
}

@test "canonicalize: unknown literal lands in unresolved" {
  local repo; repo=$(new_scratch_repo)
  run call_canonicalize "$repo" -- ghost.txt
  assert_line "U:ghost.txt"
  rm -rf "$repo"
}

@test "canonicalize: --from-commit passes lines through untouched" {
  local repo; repo=$(new_scratch_repo)
  run call_canonicalize "$repo" --from-commit -- whatever-name.txt
  assert_line "R:whatever-name.txt"   # NOT resolved against the repo
  rm -rf "$repo"
}

@test "canonicalize: empty records dropped (trailing-NUL guard)" {
  local repo; repo=$(new_scratch_repo)
  run call_canonicalize "$repo" -- docs/a.md
  assert_success
  assert_line "R:docs/a.md"
  refute_line "R:"
  refute_line "U:"
  rm -rf "$repo"
}

@test "canonicalize: plain CWD-relative literal rides the batch (lift preserved)" {
  # From sub/, 'a.txt' is a CWD-relative literal: ls-files --full-name
  # emits 'sub/a.txt', so the lift must compute show-prefix ONCE (hoisted)
  # and prepend 'sub/' before probing the batch. With the prior deviation
  # (base hardcoded to ""), this would fall through to the per-line
  # fallback — verified here: the ls-files counter reads 1, meaning
  # the BATCH resolved it.
  local repo; repo=$(new_scratch_repo)
  mkdir -p "$repo/sub"
  # Add a second tracked file at sub/ so the repo isn't identical to root.
  echo s > "$repo/sub/a.txt"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m subfile
  COUNT_STUB_COUNTER="$(mktemp)"; export COUNT_STUB_COUNTER
  : > "$COUNT_STUB_COUNTER"
  local bindir; bindir=$(counting_git_stub)
  run env PATH="$bindir:$PATH" bash -c '
    cd "'"$repo"'/sub"
    unset _HUG_PATHSPEC_LOADED
    . "'"$REPO_ROOT"'/git-config/lib/hug-common" >/dev/null 2>&1 || true
    . "'"$REPO_ROOT"'/git-config/lib/hug-git-kit"
    local -a res=() unres=()
    canonicalize_source_lines res unres a.txt
    if [[ ${#res[@]} -gt 0 ]]; then printf "R:%s\n" "${res[@]}"; fi
    if [[ ${#unres[@]} -gt 0 ]]; then printf "U:%s\n" "${unres[@]}"; fi
  '
  assert_success
  assert_line "R:sub/a.txt"
  refute_line "U:a.txt"
  refute_line "U:"
  # F-003: the batched ls-files call resolved it — counter == 1 means
  # no per-line fallback happened.
  [[ $(wc -l < "$COUNT_STUB_COUNTER") -eq 1 ]] || {
    echo "expected 1 git ls-files call (batch), got $(wc -l < "$COUNT_STUB_COUNTER")"; return 1; }
  rm -rf "$bindir" "$COUNT_STUB_COUNTER" "$repo"
}
