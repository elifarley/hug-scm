# Design: `hug slc` — list conflicted (unmerged) files only

- **Issue:** [elifarley/hug-scm#244](https://github.com/elifarley/hug-scm/issues/244)
- **Related:** [elifarley/hug-scm#243](https://github.com/elifarley/hug-scm/issues/243) — recovery incident that motivates surfacing conflicts as a first-class listing
- **Date:** 2026-08-06
- **Status:** Design draft, under review (survived 1 code-roast pass — no CRITICALs; 3 MAJORs addressed: doc-perimeter anchors, agent-facing corpus, `--json`+pathspec contract)
- **Branch:** `feat-slc-conflicted-files` (based on `origin/main` @ `e41aa1c`)

> All git behaviors cited below were **empirically verified** in scratch repos (2026-08-06) before writing this spec — see §2. Line anchors in the "Current code" notes are against `origin/main` @ `e41aa1c`.

---

## 1. Problem

During a merge/rebase conflict, no native command lists conflicts **only**. The closest is `hug slu`, which interleaves conflicted files (marked `Cnflt`) with ordinary unstaged modifications; extracting just the conflicts requires shell post-processing:

```bash
hug slu | grep '^Cnflt'
```

Conflict state is the highest-stakes working-tree state — resolution means acting on exactly the right file set. A one-word native command removes the filter step and makes conflict files directly scriptable. One nuance (probed): during a rename/modify conflict (`D ren.txt` + `UU renamed.txt`), `--diff-filter=U` lists only the unmerged path `renamed.txt` — the staged deletion of the old name is outside the unmerged set. That is the actionable file set for resolution; the spec's "exactly the right file set" claim is scoped to it.

**Solution:** add `hug slc` — **S**tatus + **L**ist **C**onflicts — the native equivalent of `git diff --name-only --diff-filter=U`, slotting into the `sl*` family (`sls` staged, `slu` unstaged, `sla` all, `slk` untracked, `sli` ignored) as the next one-letter suffix. **Purely additive**: no existing command changes behavior (`slu`/`sla`/`sl` keep showing `Cnflt` entries mixed with their states).

## 2. Verified git behavior (probes, 2026-08-06)

Scratch repos with real conflicts (diverging branches + `git merge`; genuinely divergent gitlink bumps for the submodule case):

| Claim | Result |
|---|---|
| `git diff --name-only --diff-filter=U` lists **exactly** the conflicted files, exit 0 | ✅ `file.txt`, `other.txt`; rc=0 |
| `git diff --name-status` (no filter) during a conflict returns **both** `U` and `M` for each conflicted file | ✅ — this is why `list_unstaged_files`' U-over-M dedup exists |
| `git diff --name-only` (no filter) lists each conflicted file **twice** | ✅ — the dedup is load-bearing |
| Pathspec scoping: `git diff --name-only --diff-filter=U -- <path>` | ✅ works |
| `git ls-files -u` yields the same file set | ✅ — documented alternative, not used (see §4) |
| Gitlink (submodule) conflicts (`UU inner` in `git status --porcelain`) appear with `--diff-filter=U` | ✅ — **without** `--ignore-submodules=none`; no extra flag needed (unlike `list_staged_files`); holds even under `diff.ignoreSubmodules=all` — unmerged state bypasses submodule-ignore |

## 3. Command surface: `git-config/bin/git-slc`

A thin script mirroring `git-sli` (the single-status-type family precedent — see §5 for why `sli`, not `slu`):

| Invocation | stdout | stderr | trailing `hug s` summary |
|---|---|---|---|
| `hug slc` | `Cnflt <file>` lines, priority-sorted (status priority 90 — already the top) | — | yes (unless `-q`) |
| `hug slc -q` | **plain paths only**, one per line | `info` no-files messages | no |
| `hug slc --json` | unified JSON envelope (§6) | — | no |
| `hug slc <pathspec>…` | scoped to pathspecs | `info "No conflicted files matching '<p>' found."` on no-match | as above |

- **`-q/--quiet` → `--suppress-status` + skip summary** — the `git-sli:44-47` pattern byte-for-byte. `hug slc -q | xargs …` receives exactly the file paths. This is the scripting mode.
- **No conflicts** → `list_files_with_status` returns 1 → `info "No conflicted files."` to **stderr**; stdout empty; exit 0 — scriptable. Same shape as `git-slu`'s no-files path.
- **`HUG_QUIET=T`** sets `quiet=true` at parse time (mirrors `git-sli:22-24`).
- **`--json` + `-q`** → JSON wins; `-q` ignored (mirrors `git-sli`'s JSON path — `output_json_status` harmlessly ignores `--suppress-status`).
- **`_hug_category='["status"]'`** (mirrors `slu`/`sli`); **`_hug_keywords='["conflict","unmerged","merge","rebase"]'`** so `hug help /conflict` finds it (mechanism documented in `git-config/bin/CLAUDE.md`).
- **Colors**: `Cnflt` prefix rendered via `_format_unstaged_status U`; plain text when piped, like the family.
- **Not in a repo** → `check_git_repo` exits, family pattern.
- **`--json` ignores pathspecs — explicit contract**: the unified JSON pipeline's parse loop drops unknown args (`output_json_status:40-42`), family-consistent with `sli`/`slu`/`slk` today. `hug slc --json <path>` returns **all** conflicted files, unfiltered, exit 0. Stated here and pinned by a §8.1 test — deliberately **not** plumbed, because fixing it would change existing family commands' JSON behavior and break the purely-additive constraint. (The roast's alternative — plumb pathspecs through `collect_git_files_json` — is recorded in §10 as rejected.)
  - **SUPERSEDED (PR-B, 2026-08-18)**: flipped by [elifarley/hug-scm#298](https://github.com/elifarley/hug-scm/pull/298) under the uniform pathspec contract ([elifarley/hug-scm#292](https://github.com/elifarley/hug-scm/issues/292) §5.5) — pathspecs now scope `--json`, and the §10 rejection this bullet cites is overturned by the parent PRD's §5.5 decision. Historical text kept verbatim above.
- **`-q` + exotic filenames**: output is line-based, so `hug slc -q | xargs …` splits on filenames containing spaces/newlines. Family-inherited (all sl* are line-based); a NUL-terminated mode is future work, not part of this change.
- `--` literal: not special-cased (family doesn't; git tolerates it in pathspec position — probed: `hug slc --` yields empty result, exit 0).

## 4. Library layer

### 4.1 `list_conflicted_files` — `git-config/lib/hug-git-files`

Mirrors `list_unstaged_files`' shape (`--status` / `--cwd` / pathspecs → `convert_to_relative_paths`), but simpler:

```bash
git diff --name-only|--name-status --diff-filter=U [--] [pathspecs...]
```

- **No dedup map needed** — `--diff-filter=U` returns each file exactly once (§2). `list_unstaged_files` needs its U-over-M map *because* it cannot filter.
- **No `--find-renames`** — the `U` filter can never produce rename entries.
- **No `--ignore-submodules=none`** — verified unnecessary for the `U` filter (§2).
- Exit 0 and empty output when no conflicts.

### 4.2 Renderer: `list_files_with_status --conflicts` — `git-config/lib/hug-select-files`

- New `--conflicts` include → collects via `list_conflicted_files --status`, renders `_format_unstaged_status U` → `Cnflt` / `U:Cnflt`, joins the existing priority-sort + dedup machinery.
- **`_can_suppress_status` gains an `include_conflicts` parameter**, and conflicts-only counts as suppress-safe. The gate is **type-level, not substate-based**: the safe types (untracked/ignored today; conflicts join them) are hardcoded, and the function's `status_codes` parameter is currently unused — do not transcribe substate reasoning into comments. Staged/unstaged stay unsafe because those types span multiple status codes. This is what makes `hug slc -q`'s plain paths legal. Single call site (`hug-select-files:312`) — contained change.
- The suppression-rebuild branch (`hug-select-files:309-347`) is **currently unreachable**: the only `--suppress-status` callers today (`git-sli`/`git-slk`) are suppress-safe, so the rebuild never fires; `slc` keeps it unreachable. Its `U:Cnflt` case (`:336`) is correct-by-construction for a future mixed-status suppression, not exercised precedent — do not cite it as verified behavior in tests.

### 4.3 JSON plumbing: `output_json_status` + `hug-git-json`

- `output_json_status`: new `--conflicts` flag → filter string gains `"conflicted"`.
- `output_json_status_unified`: **default filter untouched** (`staged,unstaged,untracked,ignored` — `hug s --json` / `slu --json` output byte-identical to today). New `conflicted_files` collection + `summary.conflicted` count (joined into `total`) + `conflicted` array via the existing `add_file_array` (omit-when-empty).
- `collect_git_files_json`: new `"conflicted"` case → `list_conflicted_files --status` → `parse_file_to_json`, which already maps `U` → `"conflict"` (`hug-git-json:27`). Per-file objects come free.

## 5. Why mirror `git-sli`, not `git-slu`

`git-slu` does **not** map `-q` to `--suppress-status` — and correctly so: its output spans multiple `U:*` substates (Mod/Del/Cnflt), so suppressing the status column would lose information. `git-sli`/`git-slk` do map `-q` → `--suppress-status` (`git-sli:44-47`) because ignored/untracked are single-status listings — suppression is safe. **Conflicts are also a single status type (`Cnflt`)**, so `slc` follows the `sli`/`slk` convention: `-q` = plain paths, exactly the scripting mode requested.

## 6. JSON schema (`hug slc --json`)

```json
{
  "repository": {"path": "..."},
  "timestamp": "...",
  "command": "hug status --json",
  "version": "...",
  "summary": {"staged": 0, "unstaged": 0, "untracked": 0, "ignored": 0, "conflicted": 2, "total": 2},
  "conflicted": [{"path": "file.txt", "status": "conflict"}, ...]
}
```

- **Summary shape**: the four existing keys (`staged`/`unstaged`/`untracked`/`ignored`) are **always present** — unchanged behavior; `conflicted` is added to `summary` and `total` **only when the filter requests it**. `slu --json`/`sls --json` output stays byte-identical to today (`hug s --json` is a separate emitter, `output_json_status_summary`, and is untouched by this change).
- **Count semantics (2026-08-06 decision, superseded 2026-08-07)**: `summary.conflicted` counts **files** (JSON objects). The original design note said the four legacy keys count comma-split *fragments* (2 per file) due to a pre-existing pipeline quirk (`IFS=',' read -ra` on comma-joined objects), tracked as [elifarley/hug-scm#247](https://github.com/elifarley/hug-scm/issues/247). **#247 was fixed on 2026-08-07**: `collect_git_files_json` now delivers the object count via nameref (no comma-split), so **all** five summary keys — including the four legacy ones — count files. `total` is uniform (files only).
- Empty conflicts → `summary: {"staged": 0, "unstaged": 0, "untracked": 0, "ignored": 0, "conflicted": 0, "total": 0}`, no `conflicted` array, exit 0, zero non-JSON bytes on stdout.
- Known cosmetic carry-over: envelope `command` field says `"hug status --json"` — same as `slu --json` today. Not worth plumbing a parameter (YAGNI; family-consistent).

## 7. Wiring

- **Fish completions** (`completions/hug.fish`): add `slc` to `hug_tops`; add `slc`, `slu`, `slk` to the status-options group alongside `sl`/`sla`/`sli` (fixes the pre-existing gap where `slu`/`slk` are missing — user-approved drive-by).
- **Bash completions** (`completions/hug-completion.bash`): auto-discover scripts — no change.
- **Docs** (follow `docs/DOCS_ORGANIZATION.md` placement rules):
  - `docs/commands/status-staging.md` — **complete the sl* family documentation** in the existing detail-block style: the page currently documents only `hug sl` (~:74), `hug sla` (~:106), `hug sli` (~:111) in the family detail section, and only `sl`/`sla` in the Quick Reference table (~:28-40). Add `slc` **and** the missing existing siblings `sls`, `slu`, `slk` in both places; the `slc` entry carries the `-q` scripting note. (The `Cnflt` marker is already documented in the file-state alphabet — no change there.)
  - `git-config/lib/python/articles/agents.md` (~:124-131) — add `hug slc`: conflict only to the "Listing commands" list (after `hug slu`). This is the agent-facing corpus the spec's motivation depends on — the reader hunting for conflicts must learn `slc` exists, not just `slu`+grep.
  - `docs/git-to-hug.md` (~:48, after the `git diff` rows) — add a translation row: `git diff --name-only --diff-filter=U` → `hug slc` (the spec calls slc the native equivalent of that exact command).
  - `README.md` — the Status & Staging section is a shell code block (~:329-339, listing s/sl/sla/sli): add an `hug slc` line.
  - `docs/meta/hug-completion-reference.md` — add `slc` if it enumerates commands.

## 8. Tests

### 8.1 Unit — `tests/unit/test_status_staging.bats` (sl-family home)

1. **Real conflict fixture** (issue's recipe): diverging branches + `hug mkeep` → conflict. The fixture must also contain, alongside the conflicted files: a file modified on only one side (cleanly merged — not a conflict) and a staged file — so the test can assert `hug slc` lists **exactly** the conflicted paths with `Cnflt` prefix, and excludes unstaged non-conflict files and staged files.
2. **`hug slc -q`**: plain paths only; pipe-safe (assert stdout is exactly the paths — no prefix, no chatter; assert stderr carries no summary).
3. **No conflicts**: empty stdout, exit 0; `info` message on stderr only (`run hug slc 2>&1 1>/dev/null` → partial match; `2>/dev/null` → stdout empty).
4. **`hug slc --json`**: parses via `python3 -m json.tool`, zero non-JSON bytes, `summary.conflicted` == expected, entries carry `"status": "conflict"`.
5. **Pathspec scoping**: `hug slc <path>` limits to that file; no-match → "No conflicted files matching" on stderr.
6. **`-q` suppresses the trailing `hug s`**; non-quiet shows it (stderr).
7. **Gitlink conflict**: `UU inner` via the embedded-repo recipe — add the inner repo path with `git add` and commit divergent pointer bumps on both branches (probe-verified). **No `git submodule add`**: that fixture fails on git ≥2.38 (`transport 'file' not allowed` without `-c protocol.file.allow=always`), and the embedded-repo recipe avoids the file protocol entirely. `hug slc` lists `inner`.
8. **`--json` ignores pathspecs** (pinned contract, §3): `hug slc --json <path>` returns ALL conflicted files, unfiltered — assert the full set, not the scoped one.
   - **SUPERSEDED (PR-B, 2026-08-18)**: flipped by [elifarley/hug-scm#298](https://github.com/elifarley/hug-scm/pull/298) ([elifarley/hug-scm#292](https://github.com/elifarley/hug-scm/issues/292) §5.5) — pathspecs now scope `--json`; the live test asserts the SCOPED set. Historical text kept verbatim above.
9. **`HUG_QUIET=T`**: plain paths, no trailing summary (mirrors `git-sli:22-24`).
10. **`hug slc --json -q`**: JSON wins — output parses via `python3 -m json.tool`, `-q` ignored.

### 8.2 Library — `tests/lib/test_hug-git-files.bats`

`list_conflicted_files`: `--status` output format (`U\tfile`), `--cwd` scoping, pathspecs, empty repo → empty output. (Per `git-config/lib/CLAUDE.md`: library changes get elegant tests.)

## 9. Error handling & regression surface

- `check_git_repo` first; `--json -q` → json wins (mirror `git-sli`).
- `--json` + pathspec → unfiltered results, per the explicit §3 contract (family-consistent; pinned by test 8).
- Pathspec no-match message mirrors `git-sli:60-64`.
- Rename/modify conflict → only the unmerged path listed (`D ren.txt` invisible) — see §1.
- `hug slc --` (trailing `--`) → literal pathspec → empty result, exit 0 (probed).
- Filenames with spaces/newlines → `-q` line output splits under `xargs`; family-inherited, NUL mode is future work (§3).
- **Zero changes to existing commands** — the only shared-lib signature change is `_can_suppress_status` (internal, one call site).
- Stdout/stderr discipline per CLAUDE.md: data (paths / JSON) → stdout only; chatter (`info`, `hug s` summary) → stderr only.

## 10. Alternatives considered (rejected)

- **`hug slu --conflicts` flag** — conflict is a distinct *state*, not an unstaged substate; the one-letter-suffix family convention makes `slc` the predictable name; a flag makes the common case longer to type. (Rejected in the issue; agreed.)
- **Plain-path-only output always (no `Cnflt` prefix)** — maximally scriptable but diverges from the family rendering convention (`sls`/`slu`/`sla` all print status prefixes). Resolved by `-q` → plain paths: family-faithful by default, scriptable on demand.
- **`git ls-files -u` as the mechanism** — equivalent output, but `diff --diff-filter=U` is already verified and consistent with `list_unstaged_files`' conflict-dedup path. `ls-files -u` remains the documented alternative if stage-level detail is ever needed.
- **Plumbing pathspecs into the JSON pipeline** (the roast's alternative for M3) — `collect_git_files_json`'s list functions already accept pathspecs, so the plumb is small; but `output_json_status` is shared by `sli`/`slu`/`slk`, so honoring pathspecs for `slc` only would either diverge from the family or change existing commands' JSON behavior (violating purely-additive). Rejected in favor of the documented-and-tested contract (§3, test 8); a later family-wide fix can plumb it uniformly.
- **hg parity** — sl* family is git-only today; out of scope (noted in the issue).

## 11. Build order

1. `list_conflicted_files` (hug-git-files) + lib tests
2. `--conflicts` include + `_can_suppress_status` param (hug-select-files)
3. JSON plumbing (`output_json_status` → `hug-git-json` → `collect_git_files_json`)
4. `git-slc` script (thin mirror of `git-sli`)
5. Unit tests (test_status_staging.bats — incl. the pinned `--json`+pathspec, `HUG_QUIET`, `--json -q` contracts)
6. Completions (fish: `slc` + `slu`/`slk` gap)
7. Docs (status-staging.md family completion, agents.md, git-to-hug.md, README, meta if needed)
8. `make test` + `make sanitize` in the worktree
