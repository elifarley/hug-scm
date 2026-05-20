# ADR-004: Bash SIGPIPE + pipefail Discipline

## Status

Accepted

## Context

Hug SCM uses `set -o pipefail` in command scripts (via `set -euo pipefail`) to
ensure pipeline failures propagate. Two bug classes were traced to the same code
shape: `git ... | <early-exit-filter>` inside scripts running under pipefail.

### Bug Class 1: False-negative correctness checks

Functions like `has_pending_changes`, `tag_exists_remote`, and
`get_first_child_commit` used pipes of the form:

```bash
git ... | grep -q PATTERN
```

When git emits enough data to fill the kernel pipe buffer (64 KB on Linux),
`grep -q` exits at the first match, closing the read end of the pipe. Git
continues writing, hits SIGPIPE (signal 13, exit code 141), and pipefail
propagates the failure. The function returns non-zero for a perfectly valid
result -- a **false negative** on safety checks that callers depend on.

Consequences of these false negatives:
- Callers skip safety gates (e.g., proceed with destructive operations despite
  pending changes).
- Tag existence checks silently fail, potentially allowing duplicate tag pushes.
- Parent-child commit resolution returns empty, breaking operations that depend
  on commit graph traversal.

### Bug Class 2: Silent safety-gate bypass (git-mff)

`git-mff` had a worktree safety check using `git worktree list --porcelain |
grep "branch: refs/heads/$branch"`. Two independent bugs made this check
non-functional:

1. **SIGPIPE race** (same as Class 1): under pipefail, the grep could SIGPIPE
   the git producer.
2. **Porcelain format mismatch**: The pattern used `branch:` (with colon) but
   git porcelain emits `branch ` (space, no colon). The grep **never matched**,
   even without the SIGPIPE race.

Result: the safety check was silently broken since its introduction, producing
cryptic errors instead of the clear actionable message intended to guide users.

### The race mechanism

```
  git producer          pipe          grep -q consumer
  |                     |             |
  |--- writes data ---->|             |
  |--- writes data ---->|             |
  |                     |--- found -->| (exits 0, closes read end)
  |--- writes data ----X  SIGPIPE     |
  |   (exit 141)        |             |
  |                     |             |
  pipefail sees: 141 | 0 = 141 (failure)
```

The race is **data-dependent**: with small git output (less than the pipe
buffer), the producer finishes before the consumer closes, and everything works.
With larger output, the race triggers. This makes the bug intermittent and
environment-dependent -- the worst kind to diagnose.

## Decision

### 1. Adopt capture-then-filter as the canonical idiom

Replace all `git ... | <early-exit-filter>` sites with:

```bash
local output
output=$(git ...) || return 1
grep -q "pattern" <<< "$output"
```

This eliminates the pipe entirely: git runs to completion inside the `$()`
subshell, its output is captured into a variable, and the filter operates on
the captured string. No pipe means no SIGPIPE.

**Tolerant variant** (for best-effort checks where a git error should not
abort the caller):

```bash
local output
output=$(git ...) ||:   # no-op on failure; continue with empty string
grep -q "pattern" <<< "$output"
```

### 2. Add a structural lint guard

`tests/lib/test_no_sigpipe_races.bats` is a static scanner that detects risky
`git ... | <early-exit-filter>` patterns in `git-config/{lib,bin}/`. It
matches:

- `git ... | grep -[qQ]`
- `git ... | head -N`
- `git ... | awk ... exit`
- Multi-stage pipes with these filters anywhere downstream

The scanner joins backslash-continued lines, skips full-line comments (to avoid
flagging example code in WHY comments), and requires a `# SIGPIPE-safe:` annotation
within 3 preceding physical lines for any allowed site.

### 3. Require `# SIGPIPE-safe:` annotations for exceptions

Sites that retain the pipe pattern (e.g., process substitution, bounded output)
must carry an annotation within 3 lines above the pipe:

```bash
# SIGPIPE-safe: output bounded by --max-count=1
git log -1 --format=%s | head -1
```

Valid annotation reasons:
- `capture-then-filter` (already fixed)
- `process substitution, not pipe` (`< <(git ...)`)
- `output bounded by <mechanism>`
- `TODO (<commit>)` (temporary, must be resolved)

### Key insights from the investigation

#### Insight 1: Vulnerability is a property of code shape, not runtime default

As of Bash 5.1.16, `shopt inherit_errexit` defaults to `off`. This means `$()`
command substitution does **not** inherit `set -e` from the parent. Sites inside
`$()` are not vulnerable **today** because the inner pipe's exit 141 is masked.

However, the identical code shape is a maintenance trap:
- Any contributor adding `shopt -s inherit_errexit` in any sourcing script
  would silently promote all masked sites to real bugs.
- Copy-paste of the pattern from a `$()` site to a non-`$()` site introduces a
  live bug.
- The lint guard catches the pattern unconditionally, regardless of context.

Defense-in-depth means eliminating the code shape entirely, not just the
currently-active instances.

#### Insight 2: The `local var=$(cmd)` footgun

```bash
# WRONG: local always returns 0, masking the command's exit status
local var=$(failing_cmd)   # exit code lost

# CORRECT: separate declaration from assignment
local var
var=$(failing_cmd) || return 1   # exit code preserved
```

`local` is a builtin that always exits 0. When combined with command
substitution in a single statement, the command's exit code is silently
discarded. This is a well-known Bash footgun that becomes load-bearing when
error propagation matters (as it does under `set -e`).

#### Insight 3: The `|| return 1` is load-bearing for library functions

Under `set -e`, the exit code of commands inside `$()` is **not** propagated to
the enclosing shell. Without `|| return 1`, a real git error (bad gitdir, EACCES)
would set the variable to empty and execution would continue with silently
incorrect results.

## Consequences

### Positive

- **Correctness**: Eliminates an entire class of intermittent, data-dependent
  failures that are extremely difficult to reproduce and diagnose.
- **Safety**: False negatives on safety checks are no longer possible from this
  mechanism.
- **Future-proof**: The lint guard prevents re-introduction of the pattern in CI.
- **Documentation**: Annotations make the reasoning explicit for future
  maintainers, reducing the chance of accidental regressions.
- **Consistency**: A single canonical pattern (capture-then-filter) replaces
  multiple ad-hoc pipe patterns, making the codebase more uniform.

### Negative

- **Code overhead**: Each conversion adds one `local` declaration and splits the
  capture into two lines. For a codebase with 20+ sites, this is ~40 additional
  lines.
- **Memory bounded by git output**: The captured variable holds the full git
  output in memory. In practice, registry sizes and status outputs are KB-scale,
  so this is not a concern for Hug's use case. Sites that could produce very
  large output should use streaming alternatives (process substitution, temp
  files).
- **Lint annotation maintenance**: New pipe patterns require explicit annotation.
  This is intentional friction -- the goal is to make the developer stop and
  think about whether a pipe is truly safe.

### Neutral

- **Behavior unchanged for correct paths**: The fix only affects the error-case
  handling. When git output fits in the pipe buffer (the common case), both the
  old and new code produce identical results.

## Cross-references

- **Canonical WHY comment**: `worktree_exists` in `git-config/lib/hug-git-worktree`
  (lines 397-421) -- the reference implementation with detailed rationale.
- **Lint guard**: `tests/lib/test_no_sigpipe_races.bats`
- **Related commits**:
  - `11e7350` -- Harden test-helper worktree assertions against SIGPIPE under pipefail
  - `e62809f` -- Decouple grep -q from SIGPIPE under pipefail across worktree functions
  - `ba0c062` -- Correct worktree_is_locked safety comment + tighten failure-path test
  - `e26fd62` -- Add SIGPIPE+pipefail structural lint guard with current-state allowlist
  - `20b5a2d` -- Fix real SIGPIPE+pipefail bugs in state, tag, commit, mff
  - `8264954` -- Apply capture-then-filter to remaining SIGPIPE-race sites (defense-in-depth)

## References

- [ADR-001: Automated Testing Strategy](ADR-001-automated-testing-strategy.md)
- [Bash manual: Pipelines and `set -o pipefail`](https://www.gnu.org/software/bash/manual/bash.html#The-Set-Builtin)
- [Bash manual: Command Substitution](https://www.gnu.org/software/bash/manual/bash.html#Command-Substitution)
- [Signal(7): SIGPIPE](https://man7.org/linux/man-pages/man7/signal.7.html)

## Revision History

- 2026-05-20: Initial decision document created
