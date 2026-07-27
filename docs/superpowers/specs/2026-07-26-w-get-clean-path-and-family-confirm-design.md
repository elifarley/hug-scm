# Design: `hug w get` clean-path confirmation + family-wide confirm alignment

- **Issue:** [elifarley/hug-scm#218](https://github.com/elifarley/hug-scm/issues/218)
- **Related (pre-existing bug surfaced by this design):** [elifarley/hug-scm#220](https://github.com/elifarley/hug-scm/issues/220) — reset-all silent data loss; fixed in passing by File 2 step 3.
- **Date:** 2026-07-26
- **Status:** Design draft, under user review (revised after 7 code-roast rounds)
- **Scope:** Approach A (revised after code-roast) — fix `w get` (Concerns 1 & 2) + align one latent same-class sibling (`h-rewind`). `w-unwip` was **removed** from scope (see §1.3).

> Line numbers cited below (e.g. "current lines 65–83") are anchors against the files as they stood at design time (2026-07-26, `main`). Re-resolve them at implementation time.

---

## 1. Problem

`hug w get` (restore file(s) from a commit into the worktree, no staging) has two no-TTY UX defects that push agents toward destructive shortcuts.

### Concern 1 — clean path demands `-f`

When a target file has **no** uncommitted changes, `hug w get <ref> <file>` still refuses without `-f`, and under no-TTY exits 1. Per `hug help :agents`, `-y` is the flag for routine/recoverable confirmations and `-f` is for **dangerous** operations; demanding `-f` here trains the wrong reflex — the one time the file *does* have unstaged edits, the agent that learned "just add `-f`" silently destroys unrecoverable work.

**Root cause:** `git-w-get` defines its own inline `confirm()` function (current lines 65–83) that calls `read -p`. This bypasses the family `prompt_confirm_*` model entirely:

- Under no-TTY, `read` fails → exit 1 (the reported symptom).
- The function reads only a local `force` boolean, never `HUG_YES` → even `-y` does not work.
- It gates *even when there is nothing to destroy* (file matches its committed state).

### Concern 2 — dirty-path remediation is unsafe + non-runnable

The refusal message (from shared lib `check_file_unstaged`) reads `Use 'hug w discard $file' to discard changes first`, which (a) nudges discarding **unseen** work and (b) itself refuses under no-TTY without `-f` (because `w discard` uses `prompt_confirm_danger`). So an agent copy-pasting the suggestion fails twice and is steered toward destroying edits it never inspected. The same refusal fires under `--dry-run`, so the preview also fails.

**How this spec addresses it (read carefully — a round-5/6 reconciliation):** After the gate redesign, `w get`'s dirty-path refusal routes through `check_files_clean` (specific files) / `check_working_tree_clean` (all files) — whose remediation text (`wipe`/`wipe-all`) is **byte-locked** (#208; must not say `discard`). That locked text already carries the `-f`-equivalent (`wipe`), so it *is* runnable under no-TTY via `hug w wipe -f <file>` — fixing half (b)'s "fails twice" cascade for `w get`. The refusal also **itemizes the dirty files**, giving the agent a concrete target to review with `hug sw <file>` before discarding — addressing half (a). The remaining gap — the locked message not explicitly saying "review first" — is a `check_files_clean`/`check_working_tree_clean` *message-quality* issue that this spec does **not** fix (the text is byte-locked for good reason; see §6 follow-up). The `check_file_unstaged` rewrite in File 1 step 3 is therefore **lib hygiene for future unstaged-only callers** — its sole current caller (`git-w-get:217`) is deleted by File 2 — and its test in §4 is a **direct library unit test**, not a `w get` end-to-end test.

### Latent sibling (audit)

`hug-confirm`'s `prompt_confirm_*` family is available to **every** command (sourced transitively via `hug-common`). Despite this, a `git-config/bin/` audit found one more command with a bespoke confirmation of the same bug class:

| Command | Bespoke pattern | Correct tier | Latent bug |
|---|---|---|---|
| `git-h-rewind` | `read -p 'Type "rewind"...'` | danger (`git reset --hard`) | ignores the family `HUG_YES`/`HUG_FORCE` contract (manual `HUG_FORCE` check only; `-y` would be mis-routed if ever wired) |

`git-h-rewind` already calls `parse_common_flags` (verified) so it honors `-y`/`-f` at the parser level; the bespoke `read` just sidesteps the family helper. Swapping to `prompt_confirm_danger` is a clean fix.

`git-t` (interactive tag menu) uses `read -r choice` but it is an interactive **menu**, not a confirmation gate — out of scope. Nine other `read` usages flagged by the audit are data parsing (heredocs, `<<<`, pipelines), not confirmations — out of scope.

### `w-unwip` removed from scope

A prior draft of this spec included `git-w-unwip` as a second sibling (bespoke `read -r -p "Proceed with merge?"` at line 146). It is **dropped** after a code-roast review (verified against source):

- `git-w-unwip` does **not** call `parse_common_flags` — it has a bespoke arg loop (lines 75–96) that rejects unknown options with `usage_error "Unknown option '$1'."` at line 86. So `-y` is rejected as an unknown option today; the family `HUG_YES` path is not wired at all. Aligning it requires flag-parser surgery, not just a confirm-swap.
- `--force` in `w-unwip` sets a flag consumed only for **branch deletion** (after unpark), not for the merge confirm at line 146. So the existing test at `test_working_dir.bats:858` (`echo 'y' | hug w unwip --force`) passes only because it pipes `y` into the bespoke `read`; switching to `prompt_confirm_warn` would break it and the `--force` flag would not save it.
- Net: `w-unwip` is a larger, separate piece of work. File it as a follow-up issue rather than fold it in.

---

## 2. Behavior contract

The confirmation tier (`prompt_confirm_warn` / `_danger`) only governs **how a prompt behaves when one is shown**. For `w get`, a prompt is reached in **no** state — the clean/dirty + force gate makes the bespoke prompt fully redundant. So `w get` has three disjoint states:

| State | Condition | bare | `-y` / `HUG_YES` | `-f` / `HUG_FORCE` |
|---|---|---|---|---|
| **A — clean** | target files have no staged/unstaged changes | ✅ succeed, **no prompt** | ✅ succeed | ✅ succeed |
| **B — dirty, not forced** | target files have uncommitted changes | ❌ refuse + message, exit ≠0 | ❌ refuse + message (`-y` ≠ force) | — |
| **C — dirty, forced** | uncommitted changes present, `HUG_FORCE=true` | — | — | ✅ force-proceed (discard dirty, overwritten or deleted), **no prompt** |

**Key guarantees:**

- **State A never prompts.** The working-tree content is already a git object; restoring swaps one committed version for another. Nothing unrecoverable can be lost — no "are you sure?" is warranted. Under no-TTY, State A succeeds (no `read` runs).
- **State B always refuses, including under `-y`.** `-y` auto-confirms *prompts*; there is no prompt here, only a hard refusal protecting uncommitted work. This is the agent-safety guarantee: `-y` can never authorize destroying uncommitted edits.
- **State C requires `-f`.** Only `HUG_FORCE` overrides the dirty-path refusal (consistent with the family-wide rule: danger-tier overrides need `-f`, not `-y`).

**`--dry-run`** behaves per state: A → preview + "no changes to lose" success; B → **refuse at the cleanliness gate before any diff preview** (the refuse block itself itemizes the dirty files — that is the only "preview" relevant when refusing; do NOT print the full diff preview then refuse, which wastes compute on a path that will exit anyway) + exit ≠0; C → preview + "would discard (overwrite or delete)" message, no file changes. (Operational order in `reset_all_files`: the cleanliness check at line 124 fires before the preview block at lines 127+, so under `--dry-run`+dirty the refuse wins — preserve that order.)

### Sibling contract

- `git-h-rewind` (BOTH paths — see File 3) → `prompt_confirm_danger "rewind" "git reset --hard … is irreversible"`. Danger tier: `-y` refuses (exit 3 family code via `HUG_EX_BLOCKED`), only `-f` proceeds, interactive TTY requires typing the action word.

### Exit-code convention (do not conflate)

The family distinguishes two refusal conditions — they are **intentionally** different exit codes, not an inconsistency:
- **Exit 1** (`HUG_EX_FAIL`) = "operational failure / declined." Covers interactive confirmation declines (`bdel`, `w-discard` decline → exit 1) and the legacy `check_*_clean` family's dirty-state refusals (`rb` via `check_working_tree_clean` → exit 1; and `w get` after this change). **Note the family is NOT fully uniform here:** `hug-output:20-26` documents "dirty without -f" under **exit 3** ("blocked by safety"), and `wtdel` follows that — its batch-block path (git-wtdel:493) uses `error_blocked` → exit 3. So state-block refusals split: legacy `check_*_clean` → 1, `wtdel`-style batch-block → 3. `w get` inherits exit 1 because it routes through `check_working_tree_clean`/`check_files_clean` (do NOT churn those for this PR). Unifying all state-block refusals onto exit 3 would be a broader family change — file as a follow-up, out of scope here.
- **Exit 3** (`HUG_EX_BLOCKED`, defined in `hug-output:31`) = "refused for safety." The canonical surface is `error_blocked()` (`hug-output:51`), called directly by several ops (worktree/branch safety refusals). Within the confirm family, `prompt_confirm_danger` reaches it when `HUG_YES=true` is insufficient (`hug-confirm:91`, via `error … "$HUG_EX_BLOCKED"`). It is a distinct signal from a plain decline: the agent passed `-y` where `-f` was required. **Latent fragility (separate finding, do not fix here):** `hug-confirm` references `HUG_EX_BLOCKED` without itself sourcing `hug-output` — it relies on the consumer having sourced `hug-output` first. Today every consumer gets it transitively via `hug-common`, so the exit is 3 in practice; a future sourcing-order change would degrade it silently to exit 1. Worth a defensive test (see §4).

So `w get` State B → exit 1 (blocked), and `h-rewind` under `-y` → exit 3 (`-y`-insufficient-for-danger). These are different events; both are correct per the family contract. Do not "normalize" them to one code.

---

## 3. Implementation

Guiding principle: **D.R.Y.** One lib function owns the dirty-file-detection algorithm; the bespoke `confirm()` is deleted, not patched.

### File 1 — `git-config/lib/hug-git-state` (shared library)

1. **Add `get_dirty_files`** — non-exiting helper that prints files with staged OR unstaged changes to stdout, one per line, deduped+sorted. **Mirror `check_files_clean`'s exact idiom** (subshell group piped to `sort -u` via process substitution — the canonical form already in this file at lines 99–102), extended to accept an optional file scope and to be non-exiting. With **no file arguments**, it reports the **entire worktree** (needed by the all-files reset path, which destroys edits in files identical between target and HEAD too).
   ```bash
   # Usage:
   #   mapfile -t dirty < <(get_dirty_files file1 file2 ...)   # scoped subset
   #   mapfile -t dirty < <(get_dirty_files)                    # whole worktree
   # Prints files with staged OR unstaged changes (deduped, sorted). Non-exiting, ALWAYS returns 0.
   # MUST mirror check_files_clean's ( … ) | sort -u idiom verbatim — one algorithm,
   # two consumers (get_dirty_files prints; check_files_clean errors+exits on non-empty).
   # Do NOT diverge to a capture-into-variable form: it split from the canonical
   # idiom in an earlier draft and served no purpose (sort cannot SIGPIPE its
   # producer — it must read all input before emitting).
   get_dirty_files() {
     local -a dirty=()
     if [[ $# -gt 0 ]]; then
       mapfile -t dirty < <( ( git diff --name-only -- "$@"; git diff --cached --name-only -- "$@"; ) | sort -u )
     else
       mapfile -t dirty < <( ( git diff --name-only; git diff --cached --name-only; ) | sort -u )
     fi
     # Return 0 unconditionally: ending with `[[ … ]] && printf` would make the function's
     # status 1 on the CLEAN (empty) case — a `set -euo pipefail` landmine for any future
     # bare caller. Reporting primitives must not leak the emptiness test into $?.
     (( ${#dirty[@]} )) && printf '%s\n' "${dirty[@]}"
     return 0
   }
   ```
   **D.R.Y. closure:** refactor `check_files_clean` to call `get_dirty_files` internally, capturing the list for its error message. Uses the `( … ) | sort -u` form via the helper (subshell group → `sort` reads all input → no SIGPIPE on the producer); `check_files_clean` calls this helper, so do not introduce a capture-into-variable variant. New body:
   ```bash
   check_files_clean() {
     local -a files=("$@")
     [[ ${#files[@]} -eq 0 ]] && return 0
     local -a dirty=()
     mapfile -t dirty < <(get_dirty_files "${files[@]}")
     if [[ ${#dirty[@]} -gt 0 ]]; then
       # DO NOT EDIT THIS MESSAGE TEXT — byte-identical to the current block (indentation,
       # line breaks, the sed 9-space indent, the wipe/wipe-all wording all matter). Only the
       # mapfile line above changed (was an inline ( git diff; git diff --cached ) | sort -u ).
       # #208-load-bearing: wipe, not discard (this fires on staged OR unstaged).
       error "Cannot proceed because some affected files have uncommitted changes.
      Affected files:
        $(printf "%s\n" "${dirty[@]}" | sed 's/^/         /')

      Solutions:
      • Use 'hug w wipe-all' to discard changes
      • Use 'hug w wipe <file>' for specific files"
       exit 1
     fi
   }
   ```
   Implementers: copy the existing `error "..."` block **verbatim**; change only the detection line. Behavior + text are byte-identical; only the detection internals change. Now there is genuinely one detection algorithm (`get_dirty_files`); `check_files_clean` is the erroring wrapper (captures via `mapfile`, embeds in its message), `get_dirty_files` is the reporting primitive (prints). Different output surfaces, same algorithm.
   **SIGPIPE note (corrected):** `sort` cannot SIGPIPE its producer (it must read all input before emitting), so the `( … ) | sort -u` pipe is safe — same as `check_files_clean` already relies on. The SIGPIPE traps elsewhere in this library (`has_pending_changes`, `preview_file_changes`) involve early-exiting consumers (`grep -q`, `head -N`), not `sort`.
2. **`check_files_clean` behavior + text unchanged, internals refactored** to call `get_dirty_files` (per step 1's D.R.Y. closure) — same external behavior (same `error` text, same `exit 1`), now delegating detection. Its error text deliberately says `wipe`/`wipe-all`, **not** `discard`, because this function fires when staged OR unstaged changes exist — `discard` (unstaged-only) would leave staged changes and trap the user in a loop ([elifarley/hug-scm#208](https://github.com/elifarley/hug-scm/issues/208), comment at lines 67–72). Leave that text untouched. `w get`'s all-files path will keep calling `check_files_clean` for its State-B refusal (see File 2 step 3), but `HUG_FORCE` is checked first so State C bypasses it.
3. **Rewrite `check_file_unstaged` message** (single-file, unstaged-only variant — lib hygiene for future unstaged-only callers; its sole current caller `git-w-get:217` is deleted by File 2, so this change is **not** what the `w get` user sees — see Concern 2 reconciliation note in §1). This function fires only on unstaged changes (its own comment at lines 195–197 explains `discard` is correct here, unlike `check_files_clean`), so the `discard` suggestion is appropriate; only the **phrasing** changes to review-first + runnable-under-no-TTY. From:
   ```
   File '$file' has unstaged changes
   Use 'hug w discard $file' to discard changes first
   ```
   to:
   ```
   File '$file' has unstaged changes.
   Review with 'hug sw $file' (or 'hug su $file'); if discarding is intended, run 'hug w discard -f $file'.
   ```
   **Path-form note:** `$file` inside this function is `${GIT_PREFIX}$1` (repo-root-relative when `GIT_PREFIX` is set by git's prefix machinery, else as-typed). `GIT_PREFIX` is typically empty for a direct `hug w get` invocation, so `$file == $1`. The suggested `hug sw <file>` must use the **same `$file` form** the message prints, so the review command resolves to the same path — verify in a subdirectory test.

### File 2 — `git-config/bin/git-w-get` (Concern 1, core)

The two reset paths (`reset_specific_files`, `reset_all_files`) currently have **two different State B behaviors** — this spec applies the state gate to each. Both State-B refusals now route through a shared `error`-formatted helper for output-shape consistency: specific-files calls `check_files_clean "${files_to_reset[@]}"`; all-files calls `check_working_tree_clean` (whole-tree). Both use `wipe`/`wipe-all` remediation — correct for both, since either restore can encounter staged changes (`discard` is unstaged-only and would be wrong, per #208). The paths differ only in **scope** (named files vs whole tree) and in the State-C wording (specific-files overwrites only; all-files overwrites **and** deletes — see below).

1. **Delete the bespoke `confirm()` function** (current lines 65–83). Fully replaced by the state gate.

2. **`reset_specific_files`** (currently checks cleanliness per-file via `check_file_staged` + `check_file_unstaged`, two `git diff` calls per file — O(2n)). Keep the per-file `check_file_in_commit` loop (existence is genuinely per-file) to build `files_to_reset`. Replace the per-file staged/unstaged loop with the state gate:
   - **State A** (clean — determine via one batched `get_dirty_files "${files_to_reset[@]}"` call returning empty): `info "Files are clean (no uncommitted changes); restoring N file(s) from $commit_short."` → proceed, **no prompt**.
   - **State B** (`HUG_FORCE != true` and dirty): call `check_files_clean "${files_to_reset[@]}"` directly — it already routes through `error`/`gum_log` (uniform `❌ Error` format, matching the all-files path), already lists the affected files, already covers staged+unstaged (correct: `git restore --worktree` overwrites worktree content regardless of staging), and already exits 1. This **eliminates the bespoke printf-and-exit block** an earlier draft had (which would have produced a different output shape from the all-files refusal). Vocabulary is `wipe`/`wipe-all` for BOTH paths now — consistent and correct (specific-files restore can encounter staged changes too; `discard` would be wrong there, same #208 reasoning). (Under `--dry-run`, the cleanliness check refuses before the diff preview — see §2 dry-run note.)
   - **State C** (`HUG_FORCE == true`): compute the dirty subset once via `get_dirty_files "${files_to_reset[@]}"`. **Emit the notice ONLY when M > 0** — `if (( ${#dirty_files[@]} )); then warning "Discarding uncommitted changes in M file(s) (will be overwritten):" + the list; fi`. Force on a clean set stays silent (today's force path is silent — git-w-get's chatter is all `! $force`-gated; don't add a misleading "Discarding 0 file(s)"). → proceed (no prompt; force authorized it). (Specific-files restore only overwrites — no `rm -f` of absent-from-target files here, so "overwritten" is accurate; the "or deleted" wording is all-files-only.)

3. **`reset_all_files`** (currently calls `check_files_clean "${affected_files[@]}"` at line 124, which `exit 1`s with the `wipe`/`wipe-all` message). The all-files reset performs `git restore --source=$commit --staged --worktree .` — a **full tracked-worktree + index** reset to the target commit (untracked and ignored files are unaffected, matching `git restore`'s scope). This means a *tracked* file that is identical between target and HEAD (so not in `affected_files`) but has uncommitted local edits **also** has those edits destroyed. Therefore the safety gate must scope to the **entire tracked worktree**, not `affected_files`:
   - **Compute the whole-tree dirty set ONCE, up front** (before the gate): `mapfile -t dirty < <(get_dirty_files)`. This is needed both for the State-C notice (file list) AND the early-exit condition — computing it once is more D.R.Y. than the prior draft's per-state calls. Then:
   - **State B** (`HUG_FORCE != true` and `${#dirty[@]} -gt 0`): refuse via `check_working_tree_clean` (already in the lib — fires on any staged OR unstaged change across the whole tree, with the correct `wipe`/`wipe-all` remediation per #208). Exit non-zero.
   - **"Already at target" early-exit:** fire ONLY when `affected_files` is empty **AND** `${#dirty[@]} -eq 0` (computed above). Place it after the State-B gate. The round-5 draft's condition ("affected_files empty, clean tree") was wrong under `-f`: the State-B gate is bypassed under force, so `hug w get -f <target>` with target-tree == HEAD-tree but a **dirty** worktree would hit the early-exit (`affected_files` empty) → `return 0` — silently converting a `-f` wipe request into a no-op while §2's State-C row promises force-proceed. Requiring `dirty` empty too closes that leak: after the gate, dirty implies force, so this changes only the one leaking case.
   - **State A** (`${#dirty[@]} -eq 0` and not already-exited): proceed, no prompt.
   - **State C** (`HUG_FORCE == true` and `${#dirty[@]} -gt 0`): emit the discard notice (only when M > 0, per the specific-files rule above) naming the files in `dirty` → proceed. Wording: `Discarding uncommitted changes in M file(s) (will be overwritten or deleted):` — "overwritten or deleted" because the reset-all operation both overwrites modified files and `rm -f`'s files absent from the target.
   Add tests: (a) HEAD content == target content + dirty worktree + no `-f` → exit ≠0 (refused), NOT "Already at target"; (b) `-f` + target-tree == HEAD-tree + dirty worktree → proceeds, notice names the dirty files, edits gone, output does NOT say "Already at target".
   (State B uses `check_working_tree_clean` for its ready-made `wipe`/`wipe-all` refuse message; State C reuses the pre-computed `dirty` array for the file list. Both do whole-tree detection — one needs a message, the other needs a list; the `dirty` array is computed once and shared.)
   Both State-B refusals now share the `wipe`/`wipe-all` vocabulary and `error` format (specific-files via `check_files_clean`, all-files via `check_working_tree_clean`); they differ only in scope and the State-C wording (all-files says "overwritten or deleted", specific-files says "overwritten"). Tests must cover both paths separately. **Pre-existing bug (tracked as [elifarley/hug-scm#220](https://github.com/elifarley/hug-scm/issues/220)):** the current code's `check_files_clean "${affected_files[@]}"` (line 124) already undercounts (only protects the diff-affected subset, not the whole tree the operation actually resets) — a silent-data-loss defect independent of #218. Switching to `check_working_tree_clean` fixes it in passing since the gate is being rewritten anyway; #220 should be closed by the same PR.

4. **Remove both `confirm "..."` call sites** (the `"reset"` gate in `reset_all_files`, the `"Reset these files? (y/N)"` gate in `reset_specific_files`) — no longer reachable. `prompt_confirm_warn` is **not** introduced for `w get`; the state gate fully replaces confirmation.

5. **`HUG_FORCE` is the single source of truth** for the override (already exported by `parse_common_flags`); the local `force` boolean is retained only for the existing "skip verbose chatter when forced" display branches.

### File 3 — `git-config/bin/git-h-rewind` (latent sibling) — BOTH paths

`h-rewind` has **two** code paths that both culminate in the same irreversible `git reset --hard "$target"` (line 104), but currently gate at *different* tiers — the audit's original "one sibling" framing missed the second:

- **Non-upstream path** (lines 93–100): bespoke `read -p 'Type "rewind"...'` (danger-tier *intent*).
- **Upstream path** (`rewind -u`, lines 77–85): delegates confirmation to `handle_upstream_operation "rewinding"`, which uses `prompt_confirm_warn` (WARN tier, `hug-git-upstream:71`). So `rewind -u` — the *more* destructive variant (upstream may be far ahead) — gets a weaker gate (y/N, `-y` auto-confirms) than `rewind <commit>` (type "rewind", `-y` refuses). **Inverted safety gradient.**

**Fix both paths to danger tier:**

1. **Non-upstream path** — **lines 90–91 are UNCHANGED** (`handle_standard_operation "rewinding" "$target" false` owns the preview AND the "Already at target" short-circuit; do not touch it). Replace ONLY lines 93–100 (the `⚠️ PERMANENT` banner + manual `HUG_FORCE` check + `read -p 'Type "rewind"...'`) with:
   ```bash
   prompt_confirm_danger "rewind" "git reset --hard is irreversible and cannot be undone"
   ```
2. **Upstream path** — `handle_upstream_operation` is shared by 5 HEAD-movers of varying danger (`h-back`, `h-undo`, `h-rollback`, `cmv`, `h-rewind`), so do NOT add a tier param to it (out of scope, regression risk). The trap to avoid: calling `handle_upstream_operation "rewinding"` *then* a separate `prompt_confirm_danger` would **double-prompt in TTY** — `handle_upstream_operation` runs its own `prompt_confirm_warn` (hug-git-upstream:71), and on `y` returns the target, after which the danger gate fires a second time. The established idiom (already used by `h-undo:90`) is to invoke it with `HUG_FORCE=true`, which makes its internal `prompt_confirm_warn` auto-confirm (the warn gate is skipped) **while keeping the preview** (because `HUG_QUIET` is still not `T`, so lines 49–72's preview block still runs). Then the danger gate is the **single** real authorization:
   ```bash
   # upstream path: preview-only (warn auto-confirmed via HUG_FORCE), then the single danger gate
   # The `|| exit $?` is belt-and-suspenders: a plain `target=$(…)` assignment already trips
   # `set -e` on a non-zero helper exit today (the `set -e` exemption is only for `local`/`declare`/
   # `export` declarations, and `target` is a plain re-assignment here — declared at h-rewind:79).
   # The guard stays robust if this line is ever made `local` or moved into a conditional.
   # The empty-target guard then handles the "Already synced to upstream" exit 0
   # (hug-git-upstream:46, runs inside the subshell → empty stdout).
   target=$(HUG_FORCE=true handle_upstream_operation "rewinding") || exit $?
   [[ -z "${target:-}" ]] && exit 0
   prompt_confirm_danger "rewind" "git reset --hard to upstream is irreversible and cannot be undone"
   ```
   **CRITICAL — preserve the empty-target guard.** An earlier draft of this step dropped the `[[ -z "${target:-}" ]] && exit 0` line. Without it, the "Already synced to upstream" no-op case (helper `exit 0`s inside the subshell → `target` empty) falls through to `prompt_confirm_danger` then `git reset --hard ""` → `fatal: ambiguous argument ''`. This guard exists in the current code (h-rewind:83–85) and MUST be retained. (Note: the `HUG_FORCE=true` prefix is scoped to the helper subshell only; `prompt_confirm_danger` re-reads the caller's real `HUG_FORCE` — which is the intended authorization surface.)

`prompt_confirm_danger` honors `HUG_FORCE` (auto-confirms), refuses `HUG_YES` (exit 3 via `HUG_EX_BLOCKED`), and requires typing the action word on a TTY — so both manual `HUG_FORCE` short-circuits are removed (the helper handles them).

**Help text (both commands):** update the `show_help` OPTIONS blocks to document the new `-y` semantics — they change behavior but are currently undocumented:
- `git-h-rewind` OPTIONS: add `-y, --yes` → "refused — rewind is danger-tier; `--force` is required" (mirrors `h-undo`'s documented `-y` at git-h-undo:30). Currently `h-rewind`'s help doesn't mention `-y` at all.
- `git-w-get` OPTIONS: clarify that `-y` does **not** override the dirty-path refusal (only `-f` does); `-y` has no effect on the clean path (which needs no flag). Currently `w-get`'s help documents only `-f/--force`.

---

## 4. Test impact & plan

Per `tests/CLAUDE.md`: interactive tests must use the **gum-mock** (`setup_gum_mock` + `HUG_TEST_GUM_*`) for danger/complex prompts, or `HUG_FORCE` to bypass; raw `echo "..." | cmd` works only for the bespoke `read` paths that this change removes.

### Existing tests that must change

- **`tests/unit/test_head.bats:1020`** (`hug h rewind: requires confirmation without --force`) currently does `echo "rewind" | hug h rewind HEAD~1` and asserts success. After switching to `prompt_confirm_danger`, piped-`echo` stdin is non-TTY → the helper's "Non-interactive environment: cancelled" branch fires → the test **breaks**. **Fix:** convert to gum-mock (`setup_gum_mock` + `export HUG_TEST_GUM_INPUT="rewind"`), and add a `-y`-refuses variant (`assert_failure`, danger tier). The decline cases (`echo "not_rewind"`, `echo ""`) become gum-mock cancellation (`HUG_TEST_GUM_INPUT_RETURN_CODE=1` or wrong input).
- **`tests/unit/test_head.bats:586`** (`hug h rewind: preserves untracked and ignored files`) — its `:592` line does `echo "rewind" | hug h rewind` and breaks identically to :1020 (same bespoke-`read` → `prompt_confirm_danger` no-TTY issue). **Fix:** convert to gum-mock (`setup_gum_mock` + `export HUG_TEST_GUM_INPUT="rewind"`) so the confirmation path stays under test rather than being bypassed with `--force`. (A repo-wide sweep confirms :592 and the three lines inside :1020 are the ONLY piped-confirmation tests for affected commands — this list is complete.)
- **`tests/unit/test_working_dir.bats`** existing `w get` tests (lines 180, 656, 672, 690, 707, 727, 1385, 1440, 1459, 1479, 1507, 1537, 1558, 1567, 1599 — enumerate by grepping `w get` in that file at implementation time) all pass `-f` on **clean** repos — they still pass (State C with empty dirty set). Add a no-`-f` companion to each that asserts the **clean path now succeeds without `-f`**.
- **`tests/unit/test_working_dir.bats:1582`** (`w get reset-all: safety check blocks with uncommitted changes`) — the all-files State B refusal. Verify it still fails; update the asserted message to the (unchanged) `wipe`/`wipe-all` vocabulary. Add a `--force` companion asserting State C overwrites and **names the dirty file**.
- **`tests/lib/test_hug-git-state.bats`**: add `get_dirty_files` coverage — (a) **clean file → count 0** (the joiner-bug regression: MUST be 0, not 1); (b) mixed set; (c) **no-arg whole-tree form** → matches `git status --porcelain` dirty set; (d) SIGPIPE-safety smoke with many files. Update any assertion on the old `check_file_unstaged` text. **Do NOT add expectations that `check_files_clean` text changed** — it is intentionally untouched (#208). (Grep confirms no test currently asserts the old `'Use .hug w discard'` single-file string in a way that breaks — the matches found are `w discard -f` command invocations, not message assertions. Verify during implementation.)
- **`w-unwip` tests (`test_working_dir.bats:858`, `:900`, `:1052`)** — **no change**: `w-unwip` is out of scope (§1.3).

### New tests

**`tests/unit/test_working_dir.bats`** (Concern 1). **Every case must pin `< /dev/null`** (per `tests/CLAUDE.md` §"Critical Issue: TTY Environment" — an unpinned confirm `read` hangs indefinitely in a TTY runner). Pattern: `run bash -c 'hug w get … < /dev/null'`.
- Clean path, **no flag**, no-TTY (`< /dev/null`) → exit 0, message says "clean". (This is the regression test for the `get_dirty_files` joiner bug — it MUST assert exit 0, proving State A is reachable.)
- Clean path, `-y` (`< /dev/null`) → exit 0.
- Dirty path, no flag (`< /dev/null`) → exit ≠0, message names the dirty file + suggests `hug w wipe <file>` / `wipe-all` (the byte-locked `check_files_clean`/`check_working_tree_clean` text — see §1 Concern 2 reconciliation). That remediation is runnable under no-TTY once `-f` is appended to `wipe` (`git-w-wipe:46` → `git-w-discard:215` is danger-tier). Do NOT assert a "review" hint or a bare `-f` substring — neither appears in the locked text.
- Dirty path, `-y` (`< /dev/null`) → **still refuses** (agent-safety guarantee), exit ≠0.
- Dirty path, `-f` → exit 0, message names the discarded file (assert the **specific-files** `(will be overwritten)` wording — no "or deleted" here; that wording is all-files-only and is covered by the All-files bullets below).
- `--dry-run` on dirty path (`< /dev/null`) → refuse message itemizing the dirty files (**no diff preview** — refuse-before-preview per §2) + exit ≠0.
- Multi-file mixed (some clean, some dirty) → refuses naming only the dirty ones; `-f` overwrites naming only the dirty ones.
- **All-files State C undercount regression:** `hug w get -f <commit>` (no file args) where a file *identical* between target and HEAD has uncommitted edits → the discard notice MUST name that file (proves the whole-tree `get_dirty_files` scope, not `affected_files`).
- **All-files State C delete-case wording:** target commit lacks a file that exists (with uncommitted edits) in HEAD → `-f` proceeds AND the notice says "overwritten or deleted" (not just "overwritten"), and the file is gone after. Proves the wording covers the `xargs rm -f` sub-effect, not only the `git restore` overwrite.
- **All-files "Already at target" early-exit placement (M2):** HEAD content == target content + **dirty worktree** + no `-f` (`< /dev/null`) → exit ≠0 (refused by `check_working_tree_clean`), output does NOT say "Already at target". Proves the early-exit moved after the cleanliness gate (pre-fix it would `return 0` and mask the dirty tree).

**`tests/lib/test_hug-git-state.bats`** (Concern 2 — lib hygiene, since `check_file_unstaged` has no end-to-end caller after File 2):
- Direct library unit test: `source hug-git-state`, dirty a file (unstaged only), run `check_file_unstaged file`, assert the **new** review-first text (`Review with 'hug sw …' … run 'hug w discard -f …'`). Do NOT test this via `w get` end-to-end — `w get` surfaces `check_files_clean`/`check_working_tree_clean`'s byte-locked `wipe` text, not this message (see §1 Concern 2 reconciliation).
- `w get` end-to-end still asserts the refusal **itemizes the dirty files** (so the user can review before discarding) — that is the user-visible half of Concern 2 delivered by the gate redesign, tested under the §4 Concern 1 block.

**`tests/unit/test_head.bats`** (`h-rewind` — BOTH paths):
- Non-upstream: gum-mock confirm (`HUG_TEST_GUM_INPUT="rewind"`) → success.
- Non-upstream: `-y` → refuses (danger tier). Assert `[ "$status" -eq 3 ]` **and** `[ "$status" -ne 0 ]` — the `=3` pins the `HUG_EX_BLOCKED` contract (sourced transitively via `hug-common`); the `!=0` is a backstop so a future sourcing-order regression (see §2 fragility note) fails noisily as a *different* nonzero code rather than silently passing.
- Non-upstream: `-f` → success without prompt.
- **Upstream (`rewind -u`):** gum-mock confirm → success (proves the upstream path now ALSO requires the danger gate, not just warn). Set up an upstream branch ahead of HEAD so the reset is non-trivial.
- **Upstream (`rewind -u`) `-y`:** → refuses (danger tier, exit 3, same `=3 && !=0` assertion). This is the regression test for the inverted-gradient bug — pre-fix, `-y` would have auto-confirmed via the warn gate and destroyed work.
- **Upstream (`rewind -u`) TTY double-prompt regression:** under gum-mock, confirm the danger gate is the **single** prompt (set `HUG_TEST_GUM_INPUT="rewind"`; assert the warn-gate mock is NOT invoked twice / the operation completes on one confirm). Guards against the C2 double-prompt regression.
- **Upstream (`rewind -u`) already-synced short-circuit (C1 guard):** HEAD == upstream tip → exit 0, output contains "Already synced", does NOT reach `prompt_confirm_danger` / `git reset --hard`. Guards against the empty-target-guard deletion that crashed this case.
- **Upstream (`rewind -u`) no-upstream-configured:** → exit ≠0 (propagated via `|| exit $?`), not silent exit 0. Guards the `set -e`-exemption fix for the helper's error path.

**`w-unwip`:** no new tests — out of scope (§1.3).

**Interactive `--` selection (`w get <commit> --`):** inherits the specific-files state gate for free (it calls `reset_specific_files` at git-w-get:365). Add one smoke test: select a clean file via gum-mock → succeeds without `-f`; select a dirty file without `-f` → refused.

---

## 5. Verification

```bash
# Targeted, during implementation:
make test-unit TEST_FILE=test_working_dir.bats TEST_FILTER="w get" TEST_SHOW_ALL_RESULTS=1
make test-unit TEST_FILE=test_head.bats TEST_FILTER="rewind" TEST_SHOW_ALL_RESULTS=1
make test-lib TEST_FILE=test_hug-git-state.bats TEST_SHOW_ALL_RESULTS=1

# Full gate before commit:
make test
make sanitize
```

**Manual no-TTY reproduction** (from the issue), each must now pass:
```bash
REPO=$(mktemp -d) && cd "$REPO"
git init -q && git config user.email t@t.t && git config user.name t
printf 'a\n' > f && git add f && git commit -qm base
printf 'b\n' > f && git add f && git commit -qm second

# C1 clean path: now SUCCEEDS with no flag
printf 'b\n' > f   # clean
hug w get HEAD~1 f < /dev/null; echo "exit=$?"   # -> 0

# C2 dirty path: refuses with improved message; suggested command is runnable with -f
printf 'UNSTAGED\n' > f
hug w get HEAD f < /dev/null; echo "exit=$?"      # -> non-zero; message itemizes 'f' and suggests 'hug w wipe f' (append '-f' for no-TTY)
```

---

## 6. Out of scope

- `git-w-unwip` — bespoke `read -r -p` merge confirm, but aligning it requires flag-parser surgery (it does not use `parse_common_flags`, so `-y` is rejected as unknown today) and would break existing `echo 'y' | …` tests. Separate follow-up issue. See §1.3.
- `git-t` interactive tag menu (a menu, not a confirmation gate).
- The nine data-parsing `read` usages flagged by the audit (`git-sx`, `git-w-zap`, `git-w-purge`, `git-mff`, `git-wtsh`, `git-hughelp`, `git-stats-branch`, `git-bpush`, `git-tc`) — not confirmations.
- Any change to `w discard` / `w discard-all` / `w wipe` behavior (only their *invocation* in the improved message text).
- `check_files_clean`'s `wipe`/`wipe-all` remediation text — intentionally untouched ([elifarley/hug-scm#208](https://github.com/elifarley/hug-scm/issues/208)).
- **Filenames with embedded newlines** — `mapfile -t` splits on newline, so a filename containing `\n` would parse as two entries. This is a **pre-existing** limitation of `check_files_clean` (and `git diff --name-only` output generally); `get_dirty_files` inherits it rather than fixes it. Out of scope.
- **Unifying state-block refusals onto exit 3** — `hug-output:20-26` documents "dirty without -f" under exit 3, and `wtdel` follows it, but the legacy `check_*_clean` family (used by `rb`, and now `w get`) exits 1. Reconciling these is a broader family-wide change; file as a follow-up issue (see §2 exit-code note). `w get` keeps exit 1 via `check_*_clean` — don't churn those in this PR.
- **`check_files_clean`/`check_working_tree_clean` remediation text saying "review first"** — Concern 2's half (a). The text is byte-locked (#208) and shared by many commands, so improving it (to add an explicit `hug sw` review-first step) is a separate, broader message-quality change. File as a follow-up. `w get`'s refusal itemizes the dirty files (delivered here), which is the actionable half.
- Mercurial (`hg-config/`) — `check_file_unstaged` is not duplicated in `hg-config/` (audit: `grep -rn "check_file_unstaged\|has unstaged changes" hg-config/` → no matches), so this change is git-only.
