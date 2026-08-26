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

@test "relpath: SUPPLIED empty prefix (repo root) makes ZERO git calls" {
  # `${2:-…}` treats the legitimate empty root prefix as omitted and
  # re-probes `git rev-parse` per file — reintroducing the per-file
  # subprocess cost the hoist removes (PR #318 review). Presence must be
  # judged by $#: an explicitly supplied "" prefix is honored as-is.
  local repo; repo=$(mktemp -d)
  git -C "$repo" init -q
  # Identity is REQUIRED: CI runners have no global git identity and the
  # commit below dies with exit 128 ("empty ident name") without it —
  # local machines mask this via their global config (PR #318 CI red).
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  echo x > "$repo/top.txt"
  git -C "$repo" add -A; git -C "$repo" commit -qm base
  COUNT_STUB_COUNTER="$(mktemp)"; export COUNT_STUB_COUNTER
  COUNT_STUB_ALL="$(mktemp)"; export COUNT_STUB_ALL
  : > "$COUNT_STUB_COUNTER"; : > "$COUNT_STUB_ALL"
  local bindir; bindir=$(counting_git_stub)
  run env PATH="$bindir:$PATH" bash -c '
    run_main() {
      cd "$1" || exit 1
      unset _HUG_PATHSPEC_LOADED
      . "$2/git-config/lib/hug-common" >/dev/null 2>&1 || true
      . "$2/git-config/lib/hug-git-kit"
      root_to_cwd_relpath top.txt ""   # explicit EMPTY prefix: honored
      root_to_cwd_relpath top.txt      # omitted: probed (1 git call)
    }
    run_main "$1" "$2"
  ' _ "$repo" "$REPO_ROOT"
  assert_success
  assert_line --index 0 "top.txt"   # supplied-empty call: identity spelling
  assert_line --index 1 "top.txt"   # omitted-arg call: same result, via probe
  [[ $(wc -l < "$COUNT_STUB_ALL") -eq 1 ]] || {
    echo "expected 1 total git call (probe for the omitted case only), got $(wc -l < "$COUNT_STUB_ALL")"; return 1; }
  rm -rf "$bindir" "$COUNT_STUB_COUNTER" "$COUNT_STUB_ALL" "$repo"
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
    # Nameref indirection (no eval): static parsers follow the reference,
    # so ${arr[@]+"${arr[@]}"} stays shellcheck-clean.
    local -n _barr="$outvar"
    [[ ${#_barr[@]} -gt 0 ]] && printf '%s\n' "${_barr[@]}"
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

@test "build_scope_set: empty scope returns 0 (set -e safe)" {
  # Track a file OUTSIDE the queried pathspec so ls-files returns empty.
  local repo; repo=$(mktemp -d)
  git -C "$repo" init -q
  echo x > "$repo/outside.txt"; git -C "$repo" add outside.txt
  # `run` is LOAD-BEARING: $status exists only after bats run — a plain
  # subshell statement discards its exit code and the assert becomes a
  # tautology that every code path satisfies (PR #318 review, testing
  # specialist). Args cross the bash -c boundary via argv, not splicing.
  run bash -c '
    run_main() {
      cd "$1" || exit 1
      unset _HUG_PATHSPEC_LOADED
      . "$2/git-config/lib/hug-common" >/dev/null 2>&1 || true
      . "$2/git-config/lib/hug-git-kit"
      out=()
      set -e
      build_scope_set out nosuchdir/
      [[ ${#out[@]} -eq 0 ]]
    }
    run_main "$1" "$2"
  ' _ "$repo" "$REPO_ROOT"
  assert_success
  rm -rf "$repo"
}

# Counting git stub: `git ls-files …` invocations are counted to
# COUNT_STUB_COUNTER; EVERY git invocation is counted to COUNT_STUB_ALL.
# Two gates: the F-003 contract is "ONE `git ls-files` invocation" for an
# all-literal list, and the total-exec gate (bound, not exact) catches a
# per-line/per-file subprocess explosion from ANY git subcommand — the
# ls-files-only gate was myopic (PR #318 review, red team: a per-file
# rev-parse regression was invisible to it).
counting_git_stub() {
  local bin_dir; bin_dir=$(mktemp -d)
  local real_git; real_git=$(command -v git)
  cat > "$bin_dir/git" <<STUB
#!/usr/bin/env bash
printf 'a\n' >> '${COUNT_STUB_ALL:-/dev/null}'
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
  run env PATH="$bindir:$PATH" bash -c '
    run_main() {
      cd "$1"
      unset _HUG_PATHSPEC_LOADED
      . "$2/git-config/lib/hug-common" >/dev/null 2>&1 || true
      . "$2/git-config/lib/hug-git-kit"
      local -a res=() unres=()
      canonicalize_source_lines res unres docs/a.md root.txt
    }
    run_main "$1" "$2"
  ' _ "$repo" "$REPO_ROOT"
  assert_success
  # F-003 gate at small scale: an all-resolvable literal list costs exactly
  # ONE git ls-files invocation. (An UNKNOWN literal would add a second,
  # per-line probe by design — that case is pinned by the dedicated
  # "unknown literal lands in unresolved" test, which does not count calls.)
  [[ $(wc -l < "$COUNT_STUB_COUNTER") -eq 1 ]] || {
    echo "expected 1 git ls-files call, got $(wc -l < "$COUNT_STUB_COUNTER")"; return 1; }
  rm -rf "$bindir" "$COUNT_STUB_COUNTER" "$repo"
}

@test "canonicalize: 500 plain filenames => exactly one git ls-files invocation" {
  local repo; repo=$(new_scratch_repo)
  COUNT_STUB_COUNTER="$(mktemp)"; export COUNT_STUB_COUNTER
  COUNT_STUB_ALL="$(mktemp)"; export COUNT_STUB_ALL
  : > "$COUNT_STUB_COUNTER"; : > "$COUNT_STUB_ALL"
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
  # Total-exec gate (bound, not exact): the whole call must stay at a
  # HANDFUL of git invocations — a per-line or per-file subprocess loop
  # (any subcommand) explodes past this bound even when the ls-files
  # count above stays at 1.
  [[ $(wc -l < "$COUNT_STUB_ALL") -le 5 ]] || {
    echo "expected <=5 total git calls, got $(wc -l < "$COUNT_STUB_ALL")"; return 1; }
  rm -rf "$bindir" "$COUNT_STUB_COUNTER" "$COUNT_STUB_ALL" "$repo" "$specfile"
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
  # run_main wrapper: `local` is only legal inside a function — at bash -c
  # top level the declaration errors ("can only be used in a function"),
  # the namerefs silently become globals, and the noise line rides $output
  # unrefuted (red-team finding). Args pass $repo/$REPO_ROOT cleanly.
  run bash -c '
    run_main() {
      mkdir -p "$1/sub"
      cd "$1/sub" || exit 1
      unset _HUG_PATHSPEC_LOADED
      . "$2/git-config/lib/hug-common" >/dev/null 2>&1 || true
      . "$2/git-config/lib/hug-git-kit"
      local -a res=() unres=()
      canonicalize_source_lines res unres ../docs/a.md
      printf "R:%s\n" ${res[@]+"${res[@]}"}
      printf "U:%s\n" ${unres[@]+"${unres[@]}"}
    }
    run_main "$1" "$2"
  ' _ "$repo" "$REPO_ROOT"
  refute_line --partial "local: can only be used in a function"
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
    run_main() {
      cd "$1/sub" || exit 1
      unset _HUG_PATHSPEC_LOADED
      . "$2/git-config/lib/hug-common" >/dev/null 2>&1 || true
      . "$2/git-config/lib/hug-git-kit"
      local -a res=() unres=()
      canonicalize_source_lines res unres a.txt
      if [[ ${#res[@]} -gt 0 ]]; then printf "R:%s\n" "${res[@]}"; fi
      if [[ ${#unres[@]} -gt 0 ]]; then printf "U:%s\n" "${unres[@]}"; fi
    }
    run_main "$1" "$2"
  ' _ "$repo" "$REPO_ROOT"
  assert_success
  refute_line --partial "local: can only be used in a function"
  assert_line "R:sub/a.txt"
  refute_line "U:a.txt"
  refute_line "U:"
  # F-003: the batched ls-files call resolved it — counter == 1 means
  # no per-line fallback happened.
  [[ $(wc -l < "$COUNT_STUB_COUNTER") -eq 1 ]] || {
    echo "expected 1 git ls-files call (batch), got $(wc -l < "$COUNT_STUB_COUNTER")"; return 1; }
  rm -rf "$bindir" "$COUNT_STUB_COUNTER" "$repo"
}

@test "canonicalize: ../-prefixed line does NOT corrupt later lines' lift (PR #318 review)" {
  # The ../-climb once consumed the SHARED hoisted base, so a leading
  # '../a.txt' permanently shrank it and a later plain 'a.txt' (meaning
  # sub/a.txt from sub/) lifted to the ROOT spelling — silent no-match or
  # wrong-file unstage downstream (end-to-end repro'd vs merge-base).
  local repo; repo=$(mktemp -d)
  git -C "$repo" init -q
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  mkdir -p "$repo/sub"
  printf 'root\n' > "$repo/a.txt"; printf 'sub\n' > "$repo/sub/a.txt"
  git -C "$repo" add -A; git -C "$repo" commit -qm base
  run bash -c '
    run_main() {
      cd "$1/sub" || exit 1
      unset _HUG_PATHSPEC_LOADED
      . "$2/git-config/lib/hug-common" >/dev/null 2>&1 || true
      . "$2/git-config/lib/hug-git-kit"
      local -a res=() unres=()
      canonicalize_source_lines res unres ../a.txt a.txt
      [[ ${#res[@]} -gt 0 ]] && printf "R:%s\n" "${res[@]}"
      [[ ${#unres[@]} -gt 0 ]] && printf "U:%s\n" "${unres[@]}"
      return 0   # a false guard as the LAST command would exit 1
    }
    run_main "$1" "$2"
  ' _ "$repo" "$REPO_ROOT"
  assert_success
  assert_line "R:a.txt"          # ../a.txt lifted to the ROOT spelling
  assert_line "R:sub/a.txt"      # plain a.txt STILL lifts under sub/ —
                                 # the leak used to produce 'a.txt' here
  refute_line --partial "U:"
  rm -rf "$repo"
}

@test "build_scope_set: NUL transport keeps unicode spellings RAW (PR #318 review)" {
  # Non-NUL captures store git's C-QUOTED spellings ('héllo.txt' arrives
  # as "h\303\251llo.txt") while canonicalize_source_lines emits RAW -z
  # bytes — the membership filter downstream never matched and scoped
  # from-file unstages answered a silent "No files matching …" exit 0
  # (security review; repro'd — pre-extraction failed LOUDLY instead).
  local repo; repo=$(mktemp -d)
  git -C "$repo" init -q
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  printf 'base\n' > "$repo/héllo.txt"
  git -C "$repo" add -A; git -C "$repo" commit -qm base
  run bash -c '
    run_main() {
      cd "$1" || exit 1
      unset _HUG_PATHSPEC_LOADED
      . "$2/git-config/lib/hug-common" >/dev/null 2>&1 || true
      . "$2/git-config/lib/hug-git-kit"
      local -a out=()
      build_scope_set out .
      printf "S:%s\n" ${out[@]+"${out[@]}"}
    }
    run_main "$1" "$2"
  ' _ "$repo" "$REPO_ROOT"
  assert_success
  assert_line "S:héllo.txt"                 # RAW bytes, not C-quoted
  refute_line --partial 'h\303\251'         # the quoted spelling must NOT ride the set
  rm -rf "$repo"
}

@test "canonicalize: poisoned batch falls back per-line — bad line unresolved, siblings resolve" {
  # One malformed magic line kills the WHOLE batched ls-files (exit 128,
  # probed) — the batch_ok=0 fallback then resolves EVERY line per-line:
  # valid siblings still resolve, the bad line lands unresolved so it
  # dies downstream naming ITS OWN line, never poisons its siblings.
  # This branch had zero coverage before (PR #318 review, testing
  # specialist).
  local repo; repo=$(new_scratch_repo)
  run call_canonicalize "$repo" -- 'docs/a.md' ':(' 'root.txt'
  assert_success
  assert_line "R:docs/a.md"
  assert_line "R:root.txt"
  assert_line "U::("
  refute_line "U:docs/a.md"
  refute_line "U:root.txt"
  rm -rf "$repo"
}

@test "canonicalize: glob line that ALSO literal-names a tracked file keeps its fan-out" {
  # A tracked file literally named 'a*.txt' makes the literal probe HIT,
  # which used to push ONLY the literal and silently drop the glob's
  # fan-out ('abbb.txt'). The LITERAL/FREE classification now routes any
  # glob/magic/dir spelling to the per-line path, restoring pre-extraction
  # fan-out semantics (spec contract; PR #318 review, adversarial pass).
  local repo; repo=$(mktemp -d)
  git -C "$repo" init -q
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  printf 'base\n' > "$repo/a*.txt"; printf 'base\n' > "$repo/abbb.txt"
  git -C "$repo" add -A; git -C "$repo" commit -qm base
  run bash -c '
    run_main() {
      cd "$1" || exit 1
      unset _HUG_PATHSPEC_LOADED
      . "$2/git-config/lib/hug-common" >/dev/null 2>&1 || true
      . "$2/git-config/lib/hug-git-kit"
      local -a res=() unres=()
      canonicalize_source_lines res unres "a*.txt"
      [[ ${#res[@]} -gt 0 ]] && printf "R:%s\n" "${res[@]}"
      [[ ${#unres[@]} -gt 0 ]] && printf "U:%s\n" "${unres[@]}"
      return 0   # a false guard as the LAST command would exit 1
    }
    run_main "$1" "$2"
  ' _ "$repo" "$REPO_ROOT"
  assert_success
  assert_line "R:a*.txt"      # the literal file itself
  assert_line "R:abbb.txt"    # AND the glob's fan-out — never dropped
  refute_line --partial "U:"
  rm -rf "$repo"
}
