# hug clone — Correct Target-Directory Derivation — Design

**Date:** 2026-07-03
**Status:** Approved
**Issue:** elifarley/hug-scm#193
**File touched:** `bin/hug-clone`, `tests/integration/test_clone.bats`

---

## Problem

`hug clone <url>` computes the wrong target-directory name whenever the URL has
no trailing `.git` (or `.hg`) suffix — the common case for browser copy-paste.
The script then reports the wrong name and `cd`s into a directory that was never
created:

```
✅ Success: ✓ Cloned successfully to 'github'.
bin/hug-clone: line 231: cd: github: No such file or directory
```

The actual clone lands correctly (git infers the directory itself), but hug's
pre-computed name is wrong, so the success message lies and the promised
post-clone `hug s` never runs.

### Root cause

`bin/hug-clone:207`:

```bash
cloned_dir=$(basename "${url%.*}")
```

`${url%.*}` removes the **shortest** trailing `.` + anything. For a suffixless
URL the last dot lives inside the hostname (`github.com`), so the expansion eats
the entire path back to the host:

```
url      = https://github.com/nexu-io/open-design
${url%.*}= https://github          ← ate "/.com/nexu-io/open-design"
basename = github                  ← wrong
```

### Why this is more than cosmetic — it is a safety bug

The wrong `cloned_dir` feeds **two `rm -rf` paths**:

1. `check_directory_exists "$cloned_dir"` → `rm -rf` after an overwrite confirm
   (`bin/hug-clone:94`).
2. The `cleanup_on_error` EXIT trap → `cleanup_failed_clone "$cloned_dir"` →
   `rm -rf` on **any** non-zero exit (`bin/hug-clone:217`).

A stray `github` / `git@github` directory could therefore be matched and wiped.
Correctness of the derivation is a prerequisite for the safety of both paths.

### Why the issue's own proposed fix is insufficient

The issue suggests an inline snippet that opens with `local stripped=…`. That
line runs at **top-level script scope**, where `local` is illegal — under this
script's `set -euo pipefail` it aborts with:

```
local: can only be used in a function
```

So shipping the snippet verbatim trades one bug for another. The remedy — moving
the logic into a function — also unlocks unit testing, which the inline form
cannot have.

## Decision

Introduce a single, documented, unit-tested helper `derive_clone_dir <url> <vcs>`
that mirrors git's own `guess_dir_name` (`builtin/clone.c`), replacing the fragile
one-liner. Harden the two destructive paths and the post-clone `cd` so an
unanticipated URL degrades to a warning instead of data loss or a raw shell error.
Fix the **class** (any URL whose last dot precedes the final path component), not
just the reported instance.

**Placement (convention):** the helper lives beside its sibling
`detect_vcs_from_url`, inline in `bin/hug-clone`, in the same "VCS-agnostic
orchestration" section. It is used in exactly one place and is unit-tested via the
established `sed`-extraction pattern (`tests/integration/test_clone.bats:206`).
No new library file.

## Design

### 1. The helper

```bash
# Derive the directory name that `<vcs> clone <url>` will create.
# MUST match the VCS's own algorithm: the result drives the pre-clone existence
# check, the success message, AND the post-clone `cd`. If our guess and the VCS's
# real target diverge, `cd` fails after a misleading "success". (#193)
#
# WHY NOT ${url%.*}: it strips the shortest trailing ".<anything>", which for a
# suffixless URL is the dot inside the hostname (github.com) — eating the whole
# path back to the host. Strip only a REAL vcs suffix instead.
#
# Usage: derive_clone_dir <url> <vcs>   (vcs is always "git" or "hg" here)
# Echoes: the directory name (non-empty for a well-formed URL)
derive_clone_dir() {
  local url="$1" vcs="$2"
  # scp-like syntax (user@host:path, no scheme): git treats the part after ':'
  # as the path; basename alone would keep 'user@host:repo'. The common
  # user/repo forms already resolve via '/', so this only rescues the rare
  # no-slash 'host:repo'.
  [[ "$url" != *"://"* && "$url" == *:* ]] && url="${url#*:}"
  # Strip ALL trailing slashes (repo/// -> repo), matching guess_dir_name.
  while [[ "$url" == */ ]]; do url="${url%/}"; done
  # Git strips a trailing ".git"; Mercurial's defaultdest does NOT strip ".hg"
  # (verified against hg 6.1 — see below), so only git strips.
  [[ "$vcs" == git ]] && url="${url%.git}"
  # basename strips any trailing slash the ".git" removal exposed (e.g. "x/.git"
  # -> "x/" -> "x"), so no second slash-strip loop is needed.
  basename -- "$url"
}
```

**VCS-appropriate suffix stripping is deliberate — and asymmetric.** Git's
`guess_dir_name` strips a trailing `.git`, but Mercurial's `defaultdest` does
**NOT** strip `.hg` (verified against hg 6.1: `defaultdest('…/repo.hg')` returns
`repo.hg`). So only git strips; `repo.hg` clones to `repo.hg` under hg. `vcs` is
always resolved to `git` or `hg` before this is called (the `unknown` → prompt
path sets it). An earlier draft stripped `.hg` for hg — that was wrong, and an
adversarial review caught it.

**Verified against real `git clone` and `hg clone`** (hermetic, no network) for:
`.git` suffix, suffixless, scp-style, trailing slash, `.git/`, dotted repo name
(`my.repo`), dotted parent path, and hg `.hg` (kept) — our guess equals the VCS's
actual target in every case. Bare/mirror clones (`--bare`/`--mirror`) name the
target `<name>.git` with no working tree; those are handled at the call site
(append `.git`, skip post-clone status).

### 2. Call site

Replaces `bin/hug-clone:205-208`:

```bash
cloned_dir="${dir}"
[[ -z "$cloned_dir" ]] && cloned_dir="$(derive_clone_dir "$url" "$vcs")"
```

### 3. Harden the cleanup trap

Snapshot that the target is absent immediately before cloning, so the trap only
ever removes a partial clone **we** created — never pre-existing user data.
(`check_directory_exists` has already run by this point, so an absent target that
later appears must be ours.)

```bash
clone_created_target=false
[[ ! -e "$cloned_dir" ]] && clone_created_target=true

cleanup_on_error() {
  local exit_code=$?
  if [[ $exit_code -ne 0 && "$clone_created_target" == true ]]; then
    cleanup_failed_clone "$cloned_dir"
  fi
  exit $exit_code
}
```

### 4. Graceful `cd` guard

Convert any residual surprise into a clear `warning` (stderr, via the library)
instead of a raw bash `cd` error and non-zero exit after the success message:

```bash
if [[ "$run_status" == true ]]; then
  if cd "$cloned_dir"; then
    hug s
  else
    warning "Cloned, but could not enter '$cloned_dir' to show status."
  fi
fi
```

With correct derivation this branch never triggers; it is defense-in-depth for
URL forms we did not anticipate.

## Testing

`tests/integration/test_clone.bats`:

### Unit — `derive_clone_dir` (extraction pattern)

Extract the function with `sed -n '/^derive_clone_dir/,/^}/p'` (as the existing
`detect_vcs_from_url` test does) and assert every URL form:

| Input | vcs | Expected |
|-------|-----|----------|
| `https://github.com/user/repo.git` | git | `repo` |
| `https://github.com/nexu-io/open-design` | git | `open-design` (#193) |
| `https://github.com/user/repo/` | git | `repo` |
| `https://github.com/user/repo.git/` | git | `repo` |
| `git@github.com:user/repo.git` | git | `repo` |
| `git@github.com:user/repo` | git | `repo` |
| `https://github.com/user/my.repo` | git | `my.repo` |
| `https://hg.example.com/repo.hg` | hg | `repo.hg` (hg keeps `.hg`) |
| `git@host:repo` | git | `repo` (scp no-slash edge) |

### Integration — hermetic regression (#193)

Reproduce the class without a network: place a bare remote named `open-design`
(**no** `.git` suffix) under a **dot-containing parent** `dotted.dir/`, so the old
`${url%.*}` misfires (it would strip back to `…/dotted`). Then:

```bash
run hug clone --git "file://$parent/open-design"
assert_success
assert_output --partial "open-design"   # names the repo, not the parent/host
refute_output --partial "dotted"        # never the dotted parent
assert_output --partial "HEAD:"         # proves post-clone `hug s` ran
assert_dir_exists "$TEST_CLONE_DIR/open-design"
```

This is the guard the suite never had: existing clone tests used only `.git`
names and clean paths, so the bug passed CI green.

## Out of scope / known limitations

- **Non-standard scp with a colon inside the path** (e.g. `host:weird:name`):
  git's own handling is the source of truth; hug users never hit this. The
  first-colon split matches git for all realistic forms.
- No `docs/commands/utilities.md` change is expected for a bugfix; it will be
  glanced at during implementation and updated only if a documented promise
  changed.

## Files touched

- `bin/hug-clone` — add `derive_clone_dir`; replace the derivation call site;
  add the `clone_created_target` trap guard; guard the post-clone `cd`.
- `tests/integration/test_clone.bats` — add the `derive_clone_dir` unit test and
  the hermetic `#193` regression test.
