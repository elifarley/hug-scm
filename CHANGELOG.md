# Changelog

All notable changes to the Hug SCM project will be documented in this file.

## [Unreleased]

### Added
- `hug shc -z/--null` (with `-n`): NUL-separated changed-file paths — the only
  mode fully raw for every filename (line mode still C-quotes structural
  characters). Pair with `xargs -0 -r` / `read -d ''`.
- `pinned_diff()` in `hug-git-diff`: the single canonical pinned changed-files
  invocation, with an explicit rename contract — `--find-renames` for display,
  `--no-renames` for action lists (both rename sides).

### Changed
- `hug shc` stats: non-ASCII paths print raw instead of C-quoted (both dispatch
  branches); renames collapse to one `{old => new}` line on the single-commit
  branch; submodules always shown. Output is now deterministic under hostile
  `core.quotePath` / `diff.renames` / `diff.relative` / `diff.ignoreSubmodules`.
- `hug a/us/untrack/ccp --from-commit`: deterministic path lists (non-ASCII raw,
  submodules shown); rename lists keep BOTH sides — behavior preserved.
- `hug shc`: a second positional is now a usage error (exit 2); unborn HEAD
  (HEAD-derived refs, incl. `@`) gives a branded exit-1 message instead of a raw
  git fatal; explicit refs in orphan repos keep working.

## [1.9.0] - 2026-08-14

### Added

- **`hug shc -n` / `--name-only`** — print only the changed-file paths of a commit, count, or range: repo-relative, one per line, no stats and no header on stdout. Built for pipes and scripts — `files=$(hug shc -n main..HEAD)` just works: exit 0 with empty stdout on zero matches, paths print raw (never C-quoted), renames list the new path only, and pathspec filtering composes (`hug shc -n main..HEAD -- '*.py'`). Unknown bundled flags like `-nq` are rejected loudly instead of silently running stats mode (elifarley/hug-scm#266).

### Fixed

- **`shc -n` output is byte-stable across machines and configs** — `core.quotePath`, `diff.relative`, `diff.ignoreSubmodules`, and rename detection are pinned in the underlying calls, so the same repo yields identical output everywhere; before, non-ASCII paths could print C-quoted and single-commit vs range modes disagreed on renames (cross-model adversarial review finding; the `sl*` family tracks the same class in elifarley/hug-scm#249).
- **Invalid refs fail honestly in `-n` mode** — a bad ref propagates a non-zero exit; zero matches still exit 0 with empty stdout (the previously documented "exit 0 always" was false).
- **`make docs-build` works again** — internal planning dirs (`docs/plans/`, `docs/planning/`, `docs/superpowers/`) are excluded from the VitePress build, which had failed the entire site deploy since 2026-08-12 on an angle-bracket token in planning prose parsed as an unclosed HTML element (elifarley/hug-scm#170).
- **Local test runs match CI on machines with a global git ignore file** — test fixtures pin `core.excludesFile=/dev/null`, extending the v1.8.1 hooks hermeticity to the global-excludes class (elifarley/hug-scm#197): `make test-lib` no longer fails where a global ignore lists `.env`.

## [1.8.1] - 2026-08-14

### Fixed

- **`cmod`/`cmoda` refuse content-null amends** — `cmod --no-edit` with nothing staged (or `cmoda` in a clean tree) now exits 3 instead of silently rewriting HEAD's hash (same tree, same message) and printing the misleading "Amending last commit with staged changes" line. Stage changes or pass `-m`; `-f` only for a deliberate re-hash/re-date. `-y` does NOT bypass (semantic guard, not confirmation) (elifarley/hug-scm#263).
- **The guard cannot be silently bypassed** — a `-m`/`-F` message differing only by trailing whitespace (git trims it before committing), a no-op editor (`GIT_EDITOR=true`, the CI/agent norm), a trailing value-flag, or a commit-msg hook that rewrites the message: each is classified honestly — refuse, fail open, or proceed — never a silent hash rewrite (elifarley/hug-scm#263 review hardening).
- **No false refusals** — `--pathspec-from-file` and `-i/--include` amends proceed (their content is not statically decidable / includes the index alongside the named paths), and the refusal names the check actually run (staged / tracked / named paths) instead of the caller's default.
- **Honest amend info lines** — `cmoda` now states "message change only — no tracked changes" / "(--force: no content change)" / "the editor decides the message" like `cmod`, instead of always claiming "all tracked changes".
- **Clean blocked-operation output** — the stray "3: " line is gone from every refusal (error rendering no longer includes the exit code); `w-unwip` failure messages name the branch inline and exit 1 instead of 255.
- **Test suites are hermetic on hook-configured machines** — test repos pin their own `core.hooksPath` (elifarley/hug-scm#184), and repo helpers abort loudly when `cd` fails to arrive at the temp dir instead of committing fixtures into the host repository.

## [1.8.0] - 2026-08-13

### Added

- **`cmv --wt`** — move commits to a branch AND ensure it has a worktree (create if missing, reuse if present), staying on the source branch. Move is danger-tier; worktree creation is safe-tier; recovery is the inverse cmv. The new branch is created at the original HEAD (exact SHA preserved); an existing target branch is cherry-picked into its worktree. Safety guards block (exit 3) when the target is the current branch or its worktree is stale/locked. Extracts a shared `create_worktree_for_branch` helper from `wtc` so both `wtc` and `cmv` share one worktree-creation path.

## [1.7.0] - 2026-08-07

### Added

- **`-c/--count` flag across the `sl*` family** (`sl`, `sla`, `sls`, `slu`, `slk`, `sli`, `slc`) — prints only the number of matching files: a single integer on stdout, `0` when none, exit `0` (the `grep -c` idiom). Removes the `| wc -l` pipe for scripting (`hug slc -c` in a conflict-resolution hook: `0` → clean proceed, `>0` → act). Composes with pathspecs (`hug slu -c src/`), suppresses the trailing `hug s` summary, and is mutually exclusive with `--json`. Counts are NUL-safe (a filename containing a newline counts once) and deduplicated (a file both staged and unstaged counts once in `hug sl -c`); backed by a new `count_files_with_status` engine that avoids `local -n` so it runs on the Bash 4.0–4.2 floor (elifarley/hug-scm#245).

### Fixed

- **Unified JSON pipeline `summary.*` counts now count files, not comma-fragments** — `slu`/`sls`/`slk`/`sli`/`slc`/`sl`/`sla --json` previously counted comma-split JSON fragments (a 2-field object inflated `summary.<type>` to 2), so one modified file reported `summary.unstaged = 2`. The collection contract now emits one JSON object per line and counts objects, so the summary matches the array length. This is a deliberate **behavior change** for consumer-visible counts (elifarley/hug-scm#247).

- **`h back`/`h undo`/`h rollback` reject invalid and forward explicit targets loudly** — a garbage target could previously trigger the root-recovery path (undoing the root commit on nonsense input), and a forward target moved HEAD through a backward-named command; both now error, with forward targets pointing at `hug h restore <target> --<op>` (elifarley/hug-scm#234). Root-recovery is now reachable only with no positional target.

- **`commit_offset`'s Usage docstring corrected to the errexit-safe capture idiom** (`offset=$(…) || rc=$?`) — the previous form (capture, then read the status on the next line) is dead code under `set -e` for exactly the exit codes the dispatch exists to distinguish (related: elifarley/hug-scm#234).

### Changed

- **`-u` operations report "N commit(s) behind upstream" instead of the false "Already synced" when HEAD is behind upstream** — aligned keeps its message; the exit-0 no-op contract is unchanged (elifarley/hug-scm#237).

## [1.6.0] - 2026-08-07

### Added

- **`hug s` conflict visibility** — the summary line now shows a red `C:` count when files are unmerged, and the ball turns red for conflict state; `hug s --conflicted` prints the conflicted-file count to stdout (long-only, canonical order `staged unstaged untracked ignored conflicted ball`); `hug s --json` gains `status.conflicted_count` (elifarley/hug-scm#246).

### Changed

- **The red ball (🔴) now signals conflict state first** — when files are unmerged, the ball is red regardless of staged/unstaged mix (conflict is the highest-stakes working-tree state). Scripts that parsed 🔴 as strictly "unstaged changes only" now also see it during conflicts; the `--ball` query flag and help text reflect the widened precedence (elifarley/hug-scm#246).

## [1.5.0] - 2026-08-06

### Added

- **`hug slc`** — list only conflicted (unmerged) files, the native equivalent of `git diff --name-only --diff-filter=U`. Each conflicted path is shown with the `Cnflt` marker; `-q` prints plain paths for piping straight into `xargs`; `--json` emits the unified status envelope with a truthful `summary.conflicted` count; pathspecs scope the text listing. Slots into the sl* family (`sl`, `sls`, `slu`, `sla`, `slk`, `sli`).

- **`hug slc` discoverability** — keyword searchable via `hug help /conflict` and `hug help !conflict`, with full `--help`, backed by a quality-corpus regression pin.

- **Fish completions** — `slc` registered, plus the previously missing `slu`/`slk` entries.

### Fixed

- **Filenames containing `|` no longer corrupt sl* listing output** — the renderer's internal sort tuples now use a unit separator instead of `|`, so a conflicted file like `a|b.txt` lists correctly in every sl* command (previously the path was garbled and the dedup key corrupted).

### Changed

- **sl* family documentation completed** — `sls`/`slu`/`slk` (previously undocumented) and the new `slc` are now documented across the command reference, agent cheat sheet, git-to-hug translation table, README, and completion reference.

## [1.4.0] - 2026-07-29

### Added

- **`hug h restore` recovery primitive** (`hug h restore <SHA> --back|--undo|--rollback|--rewind`) — a purpose-built HEAD-mover that resets to any commit as the inverse of a prior op. Its op-named flag selects the reset mode by construction (one literal table); its no-op test is exact SHA equality (never the `count == 0` gate that makes re-invoking a mover silently no-op on forward targets). Bare-numeric guard rejects the 1–3-digit `HEAD~N` hijack. `--rewind` on a dirty tracked tree escalates to danger (exit 3). Registered in `.gitconfig`, the `git-h` gateway, and bash + fish completions.

- **State-determined confirmation tiers** across the six HEAD-mover commands sharing `handle_upstream_operation` — `tier ⟺ completeness of the recovery command` (warn iff a complete recovery exists, danger iff something unrecoverable changes). The upstream helper gains a required `tier` param; each command declares its tier and both paths (upstream + non-upstream) consume it by construction.

- **Recovery hints** — every warn-tier mover prints the exact `hug h restore <SHA> --<op> -y` command to stderr on success (quiet-aware via `HUG_QUIET`). Each restorable command's `--help` carries a `RESTORE` section naming its inverse.

- **`has_uncommitted_tracked_changes` predicate** — a tracked-only dirty boolean over the existing `get_dirty_files` (staged + unstaged tracked, untracked excluded). The single safety/tier predicate; `has_pending_changes` renamed to `has_untracked_or_pending_changes` to make the untracked-inclusion explicit in the name.

- **`emit_head_recovery_hint` library helper** — one quiet-aware function templating the recovery command from the caller's own op name (no hand-built hint strings).

- **Integration tests** (11 new): recovery cycles (op → printed restore → HEAD restored + per-mode invariant), synced-upstream guard (exit 0, HEAD unchanged, no new commit across h-back/h-undo/h-rollback/h-squash), h-rewind clean/dirty e2e.

### Changed

- **`h-rewind` becomes state-dependent** (§9 owner-signed-off, partial revert of #225): clean tree ⇒ warn + `restore --rewind -y` hint (was unconditional danger); dirty tree stays danger. The `HUG_FORCE=true` wrapper hack for the upstream danger path is retired — passing `tier=danger` directly achieves the same gate.

- **`h-back`/`h-undo`/`h-rollback`/`h-squash` lower to warn** on both paths (normal, non-root) with empty-target guard + restore hint + RESTORE help.

- **`cmv` is danger** (was implicitly warn in the v2 draft): branch switch + SHA rewrite means no complete single-command recovery exists. Help states it is NOT restorable.

- **`handle_standard_operation`'s aligned-target message** now keys on the tracked-only predicate — an untracked-only tree no longer triggers the misleading "local tracked changes will be reset" message.

### Fixed

- **`h-squash -u` silent-orphan bug** — on a synced upstream, the empty `$target` word-split into `hug h back`'s `HEAD~1` default, fabricating a `[squash] 0 commits…` commit with exit 0 and orphaning the user's commit. Fixed by adding the `[[ -z "$target" ]] && exit 0` guard to all upstream call sites (h-back, h-undo, h-rollback, h-squash).

- **Empty-target exit-128 crash** — `h-back`/`h-undo`/`h-rollback -u` on a synced upstream crashed `git reset --soft|--mixed|--keep ""` (exit 128). Same guard fixes all four.

- **Dead conditional in `git-h-squash:206/208`** — byte-identical `prompt_confirm_danger "squash"` if/else arms collapsed to one call.

## [1.3.1] - 2026-07-15

### Fixed

- **Flaky `hug analyze deps: repository size detection` test** (issues #186, #204) — the BATS test intermittently failed under CI load with `git commit` exit 128 (index-lock contention from repeatedly touching the working tree). It now creates commits via `git_commit_deterministic … --allow-empty`, which counts toward the repository-size boundary without contending on the index, and uses the deterministic helper for reproducible hashes and explicit author identity. The test also gained a tighter `commit_count` guard and an honest scope note clarifying it is a classification + completion smoke test (the size→limit mapping is covered by the new Python unit tests). Test runs are now stable across repeated invocations.

### Added

- **Python unit tests for `detect_repository_size`** (`git-config/lib/python/tests/test_deps.py`) — parametrized boundary coverage (0, 99, 100, 999, 1000, 9999, 10000, 100000) for the small/medium/large/massive size classifier, plus a sequence-type acceptance test. These are fast, deterministic, and require no git repository.

- **Optional extra-flags parameter** on the `commit_with_date` / `git_commit_deterministic` test helpers (`tests/lib/deterministic_git.bash`) — a backward-compatible 5th positional argument (defaults to empty) that lets test callers pass flags such as `--allow-empty` without re-implementing the deterministic-commit logic.

## [1.3.0] - 2026-07-15

### Added

- **`hug c` pre-commit staged-file preview** (closes #207) — between the staged-changes check and `git commit`, `hug c` now renders a capped (10-item) preview of staged filenames to stderr, pointing at `hug sls` for the full list. HONEST framing: this is a RECOVERY/TRANSPARENCY aid, not a gate (the time window is too short for interactive humans; agents see it post-commit). Suppressed by `--quiet`/`HUG_QUIET` via call-site gate. Skipped for `--allow-empty` with no staged files.
- **`hug a` post-stage index summary** (closes #207 root cause) — after every successful `git add`, `hug a` prints `Staged N file(s). Index now has M file(s) staged total.` to stderr. The cumulative count `M` is the prevention signal: an agent running `hug a file.txt` after a soft-reset immediately sees the index was already populated. Suppressed by `--quiet`/`HUG_QUIET`. Also fixes a pre-existing bug where `--quiet` leaked through to `git add` (exit 129).
- **`print_list --cap N` and `--more-hint "<text>"` API** in `hug-arrays` — opt-in list truncation with overflow line. Default behavior unchanged for the 17 existing callers. Cap bounded to 6 digits to prevent bash arithmetic overflow; octal trap (`08`) defused via `$((10#$_cap_raw))`; `--` delimiter for leading-dash titles; explicit error messages for missing value, non-integer, overflow, and missing title. `print_list` deliberately does NOT honor `HUG_QUIET` (it's data for dry-run callers like `hug w discard --dry-run`); callers gate at the call site.

### Fixed

- **#208: `hug rb` same-name no-op now points at the upstream tracking ref** — `hug rb main` while on `main` previously silent-no-oped; now detects `@{u}` via `git rev-parse --abbrev-ref @{u}` and prints `Already on 'main' — did you mean 'hug rb origin/main'? (Rebases onto the last-fetched upstream tracking ref; run 'hug fetch' first if you need fresh commits.)` Falls back to the bare no-op when no upstream is configured or `@{u}` doesn't resolve (configured-but-never-fetched case).
- **#208: dirty-tree remediation text now suggests actually-working commands** — `check_working_tree_clean` previously suggested three non-existent commands (`git w-backup`, `git w-discard-all`, `git w-discard <file>`). Worse, `discard[-all]` defaults to unstaged-only, so following that remedy would leave staged changes and trap the user in a loop. Now suggests `hug w wip "<msg>"` / `hug w wipe-all` / `hug w wipe <file>` (the `wipe` family actually produces a fully clean tree) plus a `Run 'hug sl' to see the full file list` pointer. `check_file_unstaged` keeps `discard` (correct there — function only asserts unstaged state). `.github/copilot-instructions.md` line 467 also fixed.

### Changed

- **`hug c` stderr chatter string changed** from `Committing staged changes...` to `Committing staged file(s) (N):` (followed by file names). Any external script grepping `hug c` stderr for the old string will need to update its pattern. The new string is richer (count + names) and arrives BEFORE the commit lands, enabling recovery.
- **`hug a` adds a new stderr line** (`Staged N file(s). Index now has M file(s) staged total.`) after every successful stage. External scripts parsing `hug a` stderr may see the new line; stdout is unchanged.

### Fixed

- **P0: `wtdel -p <main-repo> --force` no longer deletes the entire main repository** — path-mode had no main-worktree guard, and the rm -rf fallback bulldozed git's refusal. Worktree removal now never falls back to a blind filesystem delete; it surfaces git's reason and stops.
- **Scoped prune: removing worktree A no longer prunes unrelated stale entry B** — replaced global `git worktree prune` with targeted `prune_worktree_entry` that removes only the specific stale metadata row.

### Changed

- **Batch semantics: `wtdel` now validates ALL targets before removing ANY** — was best-effort; mixed-validity batches now remove nothing. Fix the blocked/invalid items and re-run.
- **Single confirmation covers the whole batch** — was one confirmation per worktree.
- **Exit codes now distinguish usage (2) vs safety-blocked (3) vs operational (1)** across the worktree family (wtc, wtdel, wtl).
- **`-y` on danger-tier operations now exits 3** (was 1) — clearer signal that safety blocked the operation, not that it failed at runtime.
- **`-f` and `--dry-run` now compose in `wtc`** — were mutually exclusive. `wtc feature --base HEAD~3 --dry-run -f` previews what force semantics would do.

### Added

- **`wtc`: `-p/--path`, `-B/--with-branch`, `--json`, `-q`, `HUG_FORCE` env support** — path and branch-creation flags bring parity with wtdel's interface; `--json` and `-q` enable scripting.
- **`wtdel`: `--json`, `-q`, pre-flight plan display** — batch removals show a validated plan before execution; `--json` emits a structured result object on stdout.
- **`wtl`: `(gone)` display for stale worktrees** — directories removed externally now show `(gone)` instead of a commit hash; `missing` and `dirty_details` fields in JSON output; usage errors exit 2.
- **`HUG_EX_OK/FAIL/USAGE/BLOCKED` constants + `error_usage`/`error_blocked` helpers in hug-output** — shared exit-code convention for the worktree family.
- **`main_worktree_of_gitdir` and `prune_worktree_entry` in hug-git-worktree lib** — targeted worktree metadata operations replacing global prune.

## [1.2.0] - 2026-06-05

### Added

- **`hug rb --dry-run` is now fully faithful** — previews commits, the backup name that will be created, and whether you'll need `-y` (warn-tier) or `-f` (danger-tier) for non-interactive use. Zero side effects.

- **`hug rb` backup branch names now use seconds-precision naming** — form is `hug-backups/YYYY-MM/DD-HHMM[SS[-N]].<base>`, widened from the previous `DD-HHMM.<base>`. The widening only triggers on same-minute or same-second collisions (a rare event). Old `DD-HHMM` names still parse correctly everywhere in hug. **If you have scripts that match backup names with a strict regex**, widen your pattern from `[0-9]{4}` (HHMM) to `[0-9]{4}([0-9]{2}(-[0-9]+)?)?` to accept the new form. The minute-precision threshold for `hug bdel-backup --delete-older-than` is unchanged.

- **`hug rb` confirmation tiers are now dynamic** — backup-on (default) ⇒ warn-tier (auto-confirms with `-y`); `--no-backup` ⇒ danger-tier (needs `-f` non-interactively). The ad-hoc `--no-backup requires --force` hard-error is removed; `--no-backup` now routes through the standard danger-tier confirm (type "rebase" interactively, or pass `-f`).

- **`hug rb` exit codes are now honest** — `--no-backup -f` success returns 0 (previously returned 1 in some flows). Conflict guidance is now printed when a rebase pauses (previously the script died silently under `set -e`).

- **`hug rb` now refuses to start when a rebase is already in progress** — detects `.git/rebase-merge` or `.git/rebase-apply` and exits with a clear error, preventing orphan backup branches.

- **`hug rb --quiet` no longer silently authorizes the rebase** — pass `-y` (warn-tier) or `-f` (danger-tier) explicitly for non-interactive use. Quiet only suppresses chatter, not safety checks.

- **`hug shv` — visual show.** Renders a commit's patch (like `hug shp`) or a range's cumulative diff (like `hug shcp`) in your configured difftool instead of as text. `hug shv` defaults to HEAD; `hug shv <committish>`, `hug shv N`, `hug shv -N`, and `hug shv A..B` all work. It is a thin entry point over the same engine as `hug dd`'s commit mode, so `hug shv X` is identical to `hug dd X` for any commit/range/N. `shv s|u|w` is rejected with a redirect to `hug dd s|u|w` (it is commit-history only). Pathspec scoping mirrors `shcp` (multiple paths).
- **`hug dd` accepts the `N`/`-N` convention** (the same shorthand as `hug sh`/`shp`): `hug dd 3` is the commit three back, `hug dd -3` is the cumulative diff of the last three commits.
- **`is_root_commit <committish>` in `hug-git-repo`.** A per-ref companion to `is_at_root_commit` (which only answers for HEAD), so root-commit detection is correct for an arbitrary ref (e.g. `hug dd <root-sha>` reviewed from a non-root checkout).

### Changed

- **`hug dd <committish>` now shows that commit's *introduced* diff (commit vs its first parent), not worktree-vs-ref.** So **`hug dd HEAD` now matches `hug shp HEAD`** (visual), instead of silently behaving like bare `hug dd`. This makes `dd` a coherent visual-diff gateway: `s`/`u`/`w` (and bare `dd`) are working-tree views; a committish/range/N is a commit-history view. Bare `hug dd` is unchanged (still all uncommitted, worktree-vs-HEAD). A merge is diffed against its first parent (so `dd <merge>` can differ from `shp <merge>`'s combined diff); a root commit shows every file as added; a range is the cumulative endpoint diff. For working-tree-vs-a-ref, use a range (e.g. `hug dd main..HEAD`). This also fixes a latent bug: the old ref path lacked the no-changes guard, so `dd HEAD` launched an empty difftool on a clean tree; the engine now guards all paths and surfaces an error (rather than a misleading "no changes") on an invalid ref.
- **Ref-arithmetic helpers hoisted to `hug-git-repo`.** `resolve_commit_ref`, `reject_flag_ref`, and `is_range` moved from `hug-git-show` to `hug-git-repo` (pure ref arithmetic, already in every caller's load chain) so the visual-diff engine reuses them without a difftool-to-show dependency. No behavior change for `sh`/`shp`/`shc`/`shcp`/`l`/`ll`.

### Removed

- **Stray test-debugging artifacts from the repo root** (`errors.txt`, `errors-grouped.txt`, `semantic-count-test.txt`, `file1.txt`, `file3.txt`, `TAG_TEST_FIXES_SUMMARY.md`, `skipped-tests-analysis.yaml`) committed by mistake in earlier sessions. Legitimate fixtures (screencast demos, Python test fixtures) are untouched.

## [1.1.0] - 2026-06-04

### Fixed

- **`hug-common` self-resolves `HUG_HOME` from `BASH_SOURCE[1]`.** On CI where `HUG_HOME` is unset, `hug-common` now derives it from the sourcing script's path instead of calling the undefined `error` function and `exit 1` (which killed the parent). Fixes `test_quality_corpus.py` failures on GitHub Actions — 12 of 17 keyword/intent search tests were failing because `--help` subprocess invocations returned empty metadata.
- **CI workflow persists `HUG_HOME` to `GITHUB_ENV`.** After `make install`, `HUG_HOME=$GITHUB_WORKSPACE` is written to `$GITHUB_ENV` so all subsequent steps in each matrix job inherit it. Defense-in-depth layer alongside the self-resolution fix.
- **Python test conftest sets `HUG_HOME` for subprocesses.** An autouse session fixture walks up from `conftest.py` to find the repo root via `.git` marker detection, ensuring `HUG_HOME` is available even when tests run without prior activation.

### Added

- **BATS tests for `hug-common` HUG_HOME self-resolution.** Four new tests verify: derivation from `BASH_SOURCE`, preservation of existing values, graceful failure (`return 1` not `exit 1`), and caller survival on failure.

- **Staged gitlinks (submodule pointers) now visible in `hug sls` and `hug sl`.** When `submodule.*.ignore` or `diff.ignoreSubmodules` is set, `git diff --cached` silently suppresses gitlink entries. `list_staged_files()` now passes `--ignore-submodules=none` so staged submodule pointer changes are never dropped, regardless of ignore settings.

- **`hug dd` — visual side-by-side diff command family.** Opens a configured difftool (e.g. kitty diff) instead of a text patch: `hug dd s` (staged), `hug dd u` (unstaged), `hug dd w` / bare `hug dd` (all uncommitted — *net* worktree-vs-HEAD), and `hug dd <ref|range>`. The visual counterpart to `ss`/`su`/`sw`. `dd w` is a net view, so it intentionally differs from `sw`'s two-section split (a staged-then-reverted hunk cancels out) — see `docs/commands/status-staging.md` → "Visual diff". Productizes the former `dd` gitconfig alias into a real `git-dd` command with difftool preflight (friendly error when unconfigured), no-changes and non-TTY guards, `--no-prompt`, and an interactive `--` file picker. `--help` works without a TTY or a configured difftool.
- **`hug version` / `hug --version` now reports a version number.** Added a `VERSION` file at the repo root and wired the dispatcher to print it. Previously `hug version` printed only a description with no number. Scripts can read it via `hug version` or the `VERSION` file directly.
- **`hug s -r, --remote` query flag:** Outputs the fetch URL of the tracking remote (empty when no upstream is configured). Part of the `hug s` query flag system for scripting. Use `hug s -r` alone or combine: `hug s -b -r -u`.
- **Unified Selection Framework (`selection_core.py`).** Shared toolkit for all Python selection modules: `bash_escape`, `BashDeclareBuilder`, `parse_numbered_input`, `get_selection_input`, `add_common_cli_args`, and ANSI color constants. Adding a new selection domain now requires ~50 lines instead of ~200.
- **Branch single-select Python migration.** `print_interactive_branch_menu()` now delegates formatting and numbered-list interaction to Python via `branch_select.py prepare` and `single-select` commands. Eval output validated before execution.
- **Per-item CLI args for subjects and tracks.** `--subject`/`--track` repeated flags replace space-joined `--subjects`/`--tracks` to prevent multi-word commit subjects from being split incorrectly.
- **`parse_single_input()` for strict single-select.** Rejects anything that isn't exactly one valid integer, unlike the multi-select parser which silently skips invalid tokens.

### Changed

- **4 Python modules refactored onto `selection_core`.** `tag_select.py`, `worktree_select.py`, `branch_select.py`, and `branch_filter.py` now import shared utilities instead of maintaining local copies.
- **`multi_select_branches()` menu display moved to stderr.** Prevents menu text from being captured by Bash `$()` and eval'd as shell commands.
- **`branch_filter.py` `custom_filter` raises `NotImplementedError`.** Previously silently no-oped.
- **Worktree indicators changed format.** Worktree listing commands (`hug wtl`, `hug wt`, `hug wtll`, `hug wtsh`) now display single-character indicators (`* + # @`) instead of bracketed words (`[CURRENT]`, `[DIRTY]`, `[LOCKED]`, `[DETACHED]`). The new format is more compact and easier to scan. See `hug wtl --help` for the indicator legend.
- **Stdout/stderr discipline enforced across 21 commands and 5 libraries.** Listing and query commands now route headers, legends, and tips to stderr, keeping stdout clean for piping. The `CAPTURING OUTPUT` help text section documents this for `wtl`, `wtll`, `wtsh`, `shc`, and `h-files`. Script authors relying on stdout capturing these headers should test with `2>/dev/null` to verify behavior.
- **Migration note for script authors.** If you parse `hug wtl` output in scripts, update your grep patterns from `[CURRENT]`/`[DIRTY]` to `*`/`+`. For stable machine-readable output, prefer `hug wtl --json` which uses boolean fields and is not affected by display format changes.

### Removed

- **`_should_use_gum()` from `branch_select.py`.** Dead code with a latent bug. Gum detection stays in Bash.

### Breaking Changes - Makefile Target Naming Normalization

The Makefile targets have been renamed to align with the makefile-dev PRD canonical target taxonomy.

**Static Quality Targets:**
- **NEW**: `sanitize-check` - Read-only static checks (lint + typecheck)
- **NEW**: `sanitize-check-verbose` - Read-only static checks with detailed output
- **REMOVED**: `static` - replaced by `sanitize-check`
- **UPDATED**: `sanitize` now uses `sanitize-check` internally (DRY)

**Gate Targets (Naming Swapped):**
- **`check`** now means PRD-compliant fast gate (sanitize + unit tests only)
- **`check-full`** is the enhanced gate (includes library tests)
- **`check-verbose`** is now PRD-compliant with detailed output
- **`check-full-verbose`** is enhanced with detailed output
- **`validate-full`** added for full release validation including library tests
- **REMOVED**: `check-prd` - `check` is now PRD-compliant

**Test Targets (Naming Swapped):**
- **`test`** now means PRD-compliant behavioral tests (unit + integration)
- **`test-full`** includes all tests (prerequisites + library + unit + integration)
- **`test-verbose`** is now PRD-compliant with detailed output
- **`test-full-verbose`** includes all tests with detailed output
- **REMOVED**: `test-prd` - `test` is now PRD-compliant

**Development Dependencies (dev- prefix added):**
- **`dev-test-deps-install`** - Install test dependencies (replaces removed `test-deps-install`)
- **`dev-optional-install`** - Install optional dependencies (replaces removed `optional-deps-install`)
- **`dev-optional-check`** - Check optional dependencies (replaces removed `optional-deps-check`)

**Documentation:**
- **`docs-deps-install`** - Install documentation dependencies (replaces removed `deps-docs`)

**Migration Guide:**

**For users who used `make check` (old behavior included library tests):**
```bash
# Old: make check (included library tests)
# New: make check-full
```

**For users who used `make test` (old behavior included all tests):**
```bash
# Old: make test (included all tests)
# New: make test-full
```

**For users who used `make static`:**
```bash
# Old: make static
# New: make sanitize-check
```

**Removed Targets (breaking changes - no aliases available):**
- `test-deps-install` → use `dev-test-deps-install`
- `optional-deps-install` → use `dev-optional-install`
- `optional-deps-check` → use `dev-optional-check`
- `deps-docs` → use `docs-deps-install`
- `static` → use `sanitize-check`
- `check-prd` → use `check`
- `test-prd` → use `test`

### Changed - Makefile Canonical Targets (2025-01-13)

The Makefile has been updated to comply with the canonical target taxonomy.
**Breaking change:** Several make targets have been renamed.

**Renamed Targets:**
| Old Target | New Target | Purpose |
|------------|------------|---------|
| `python-check` | `doctor` | Environment & tool readiness check |
| `python-venv-create` | `dev-env-init` | Create virtual environment (one-time) |
| `test-deps-py-install` | `dev-deps-sync` | Sync dependencies from lockfiles |
| `test-check` | `check` | Fast merge gate (sanitize + unit tests) |

**New Targets Added:**
| Target | Purpose |
|--------|---------|
| `format` | Format code (LLM-friendly: summary only) |
| `format-verbose` | Format code (show changes) |
| `lint` | Run linting checks (LLM-friendly) |
| `lint-verbose` | Run linting (detailed) |
| `typecheck` | Type check Python (LLM-friendly) |
| `typecheck-verbose` | Type check Python (detailed) |
| `sanitize` | Run all static checks (format + lint + typecheck) |
| `test-unit-verbose` | Run unit tests (detailed output) |
| `test-integration-verbose` | Run integration tests (detailed output) |
| `test-verbose` | Run all tests (detailed output) |
| `check-verbose` | Merge gate with detailed output |

**Migration Guide:**
- Replace `make python-check` with `make doctor`
- Replace `make python-venv-create` with `make dev-env-init`
- Replace `make test-deps-py-install` with `make dev-deps-sync`
- Replace `make test-check` with `make doctor` (for prerequisites) or `make check` (for full gate)

**New Recommended Workflow:**
```bash
# Initial setup
make doctor
make dev-env-init
make dev-deps-sync

# Development iteration
make sanitize        # Format + lint + typecheck
make test            # Run all tests
make check           # Full merge gate
```
