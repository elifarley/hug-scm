# Design: Worktree Command Family Hardening & DX Unification

> **Date:** 2026-06-12
> **Status:** Approved (user-reviewed design, 4 contract decisions answered explicitly)
> **Input:** `mgmt/plans/2026-06-03-worktree-commands-exercise-report.md` (20 DX findings)
> **Scope:** `hug wtc`, `hug wtl`, `hug wtdel` (+ `hug-git-worktree`, `hug-confirm` libraries)
> **Delivery:** One combined PR; safety fixes are the first atomic commits.

## 1. Context

The 2026-06-03 exercise report exhaustively drove `wtc`/`wtl`/`wtdel` through their flag
matrices and catalogued 20 DX observations. Before designing fixes, every claim was
re-verified against the current code (no worktree changes landed since the report) and
re-tested empirically in throwaway sandboxes. That verification **disproved one finding,
reframed several, and uncovered a P0 data-loss bug the report missed.**

### What verification changed

| Report claim | Verified reality |
|---|---|
| DX-1: `--base` rejects relative refs (`HEAD~1`) | **False.** `--base HEAD~1` works; the report's repo simply had no `HEAD~3`. Only the *error message* misleads ("not a valid commit, branch, or tag" for valid-but-unresolvable refs). |
| DX-10: `-y` vs `-f` is inconsistent across commands | **By design.** `hug-confirm` implements a deliberate 3-tier model (see §4). The problem is documentation drift, not semantics: `wtdel`'s help lists `-y` as if it could authorize removal, and the `warn`-tier docstring contradicts itself ("keeps safe semantics" on a destructive-op prompt). |
| DX-7: stale-worktree lifecycle is inconsistent; `wtprune` misses orphans | **Reframed.** Fresh stale entries are handled *well* everywhere (`wtl` lists, `wtl -b -p` resolves, `wtprune` detects, `wtdel <branch>` auto-prunes). The observed weirdness has one root cause: **every `wtdel` run executes an unconditional global `git worktree prune`** (git-wtdel:508), silently erasing *all* stale metadata as a side effect. The report's 6a failure was this side effect, not a resolution bug. |
| DX-11: "specify -p" suggestion for main worktree "implies a workaround that doesn't exist" | **Worse: the workaround "works" by destroying the repo.** See N1. |
| DX-9: batch is "worst-of-both-worlds" | Partially reframed: branch-mode is *pre-validate-all-fail-fast* (nothing removed), path-mode is *best-effort*. The inconsistency between the two modes is the actual defect. |

### New findings (not in the report)

| # | Finding | Severity |
|---|---|---|
| **N1** | `hug wtdel -p <main-worktree> -f` run from a linked worktree **permanently deletes the main repository including `.git`**. `git worktree remove` correctly refuses ("is a main working tree"); hug's fallback then `rm -rf`s the path. Reproduced in sandbox: repo destroyed, exit path even reports "Manual intervention required" *after* deleting everything. Root causes: (a) the main-worktree guard exists only in branch-mode resolution; (b) the fallback `rm -rf` fires on *any* git refusal, treating principled refusals as cruft. | **P0 — data loss** |
| **N2** | Unconditional `git worktree prune` on every `wtdel` (see DX-7 reframe above). Surprising global side effect; defeats stale-entry resolution for later commands. | P1 |
| **N3** | `hug-git-worktree` carries **dead code with the same dangerous pattern**: `remove_worktree()` (contains its own `rm -rf` fallback), `create_worktree()`, `create_branch_if_needed()` have zero callers — scripts reimplement them inline. | P2 |
| **N4** | `wtc` ignores the `HUG_FORCE` env var at flag level (`wtdel` honors it). Env force changes prompt behavior but not `wtc`'s force-gated logic (e.g. main-checkout override). | P2 |
| **N5** | `wtc` rejects `-f --dry-run` as "mutually exclusive"; `wtdel` composes them meaningfully (preview of a forced removal). The restriction is arbitrary. | P3 |
| **N6** | Stale worktrees are **indistinguishable from healthy ones** in `wtl` human output and `--json` (no marker, no field). | P2 |

## 2. Approved contract decisions

Answered explicitly by the maintainer on 2026-06-12:

1. **Batch `wtdel` model → validate-all-then-execute.** Pre-flight every target; any
   invalid target aborts the whole batch with a complete per-item report *before anything
   is removed*. Stale entries count as valid (planned action: prune). Unexpected
   mid-execution failures don't roll back but are summarized.
2. **`wtc <missing-branch> -y` auto-creation → keep, document loudly.** It follows the
   tier model (branch creation is additive/reversible ⇒ safe tier ⇒ `-y` answers yes).
   No breaking change to agent workflows (`/hug-worktree` skill relies on `wtc -y --base`).
3. **Exit codes → adopt `0/1/2/3`** family-wide convention (see §6).
4. **Delivery → one combined PR**, safety fixes first in the commit sequence.

## 3. Design A — Safety hardening (P0/P1)

### A1. Main-worktree guard in every `wtdel` mode

New lib helper:

```bash
# main_worktree_of_gitdir <gitdir>  → prints the main working tree owned by <gitdir>
# Tier 1: core.worktree (submodules); Tier 2: first porcelain record.
# (Same two-tier logic as resolve_main_worktree_path, but anchored to an
#  EXPLICIT gitdir instead of CWD — path-mode targets may belong to a
#  different gitdir than the caller's.)
```

`git-wtdel` pre-flight refuses any target whose resolved path equals the main worktree of
its **own** owning gitdir — identical protection for branch-mode, path-mode, batch, and
interactive selection. New message (replaces the actively-harmful DX-11 text):

```
Cannot remove the main worktree (<path>). Only linked worktrees can be removed.
To work elsewhere, create a worktree: hug wtc <branch>
```

### A2. Abolish the blind `rm -rf` fallback

When `git worktree remove` fails:

- If `$force` is true **and** stderr indicates the submodule refusal, retry once with
  `git worktree remove --force --force` (git's own documented escape hatch — still
  git-managed).
- Otherwise: report git's stderr verbatim plus a targeted hint (locked → unlock command;
  unknown → `hug wtprune` / manual steps). **Never `rm -rf` a worktree git refused to
  remove.**
- Post-success leftover-directory branch (currently also `rm -rf`): warn and leave the
  husk, printing the path. Metadata is already gone; deleting user files is not hug's call.

The stale-entry flow (directory already gone, metadata orphaned) is unchanged in spirit —
it never touches user files — but switches to the scoped prune below.

### A3. Scoped pruning

New lib helper:

```bash
# prune_worktree_entry <gitdir> <wt-path>
# Removes ONLY the admin entry $gitdir/worktrees/<id> whose gitdir file
# resolves to <wt-path>/.git. Returns 1 if no matching entry.
```

- `wtdel`'s stale flow uses it (no more global prune that erases unrelated stale entries).
- The unconditional `git worktree prune` after every removal (git-wtdel:508) is deleted —
  `git worktree remove` already cleans its own metadata.
- `hug wtprune` remains the only bulk-prune tool.

### A4. Dead code removal

Delete `remove_worktree()`, `create_worktree()`, `create_branch_if_needed()` from
`hug-git-worktree` (zero callers; duplicate the dangerous fallback). Any lib tests
covering them are removed in the same commit with rationale.

## 4. Design B — Batch model: pre-flight → confirm once → execute

`git-wtdel` is restructured into phases (logic moves into lib functions where testable):

1. **RESOLVE** (never exits mid-loop): every target (branch or path) becomes a record:
   `{spec, path, branch, gitdir, state}` where state ∈
   `ok | stale (will prune) | invalid: no-worktree-for-branch | invalid: not-a-worktree |
   blocked: main-worktree | blocked: current-worktree | blocked: locked | blocked: dirty (needs -f)`.
2. **PRE-FLIGHT REPORT**: per-item summary blocks (existing format, `[i/N]`).
   If any `invalid`/`blocked` → print every problem, remove **nothing**, exit `3` if any
   `blocked` else `1`.
3. **CONFIRM**: exactly **one** danger-tier confirmation for the whole batch
   (`Type "remove" to confirm removal of N worktrees`) replacing today's N sequential
   prompts. `-f` skips as before; `-y` still hard-fails with the teaching error (tier model).
4. **EXECUTE**: per-item; unexpected git failures are recorded, execution continues,
   batch summary reports `removed/pruned/failed`, exit `1` if any failure.
   `-B/--with-branch` deletes each branch after its worktree's successful removal
   (per-item, as today; warn-tier prompts unless `-f`).

## 5. Design C — One safety language

- **`hug-confirm`**: fix the `warn`-tier docstring contradiction; add the canonical tier
  table as the library header comment:

  | Tier | Used for | `-y` | `-f` |
  |---|---|---|---|
  | safe | additive/reversible (create branch/worktree/tag) | auto-yes | auto-yes |
  | warn | destructive but recoverable (delete merged branch) | auto-yes | auto-yes |
  | danger | irreversible / data loss (remove worktree, wipe) | **hard error** (exit 3) | auto-yes |

- **Help texts** (`wtc`, `wtdel`): shared SAFETY section wording: *"`-y` answers yes to
  routine confirmations. It never authorizes dangerous operations — those require `-f`.
  `-f` additionally overrides blocked states (dirty worktree, branch checked out in the
  main checkout)."* `wtdel`'s `-y` line explicitly states it is insufficient for removal.
- **`wtc` parity**: honor `HUG_FORCE` env (N4); allow `-f --dry-run` (N5) — the preview
  reflects force semantics (e.g. "branch would be created without prompting").
- **Docs**: worktree commands page gains the tier table, exit codes, and a scripting
  section; CHANGELOG entry under `[Unreleased]`.

## 6. Design D — Exit codes

Family convention (constants + `die_usage`/`die_blocked` helpers in shared lib):

| Code | Meaning | Examples |
|---|---|---|
| 0 | success (incl. dry-run, "nothing to do") | |
| 1 | operational failure | no worktree for branch; git failure mid-execution; `wtl` zero matches (grep-like, documented) |
| 2 | usage error | unknown flag; getopt failure; mutually-exclusive flags; `-b` without value |
| 3 | blocked by safety | danger-tier `-y` rejection (in `hug-confirm`, so family-wide); main/current worktree; locked; dirty without `-f`; branch checked out elsewhere |

Still non-zero everywhere ⇒ existing `if hug …` scripts unaffected. Each command's help
gains an EXIT CODES section. Mixed batch pre-flight failures report the highest-severity
class (any `blocked` ⇒ 3, else 1).

## 7. Design E — Scriptability

### `wtc --json` (success object, stdout; chatter stays on stderr)

```json
{"branch": "feat-x", "path": "/abs/path", "created_branch": true,
 "base": "origin/main", "start_point": "50df45c"}
```

`base`/`start_point` are `null` when an existing branch was used. Errors keep human
stderr + exit codes. Prompts in `--json` mode require `-y`/`-f` (non-TTY auto-cancel
already applies; documented). JSON emission goes through the existing Python/JSON helper
layer — no hand-rolled escaping in Bash.

### `wtdel --json`

```json
{"removed": [{"path": "...", "branch": "wt1", "action": "removed", "dirty": true,
              "branch_deleted": false}],
 "pruned":  [{"path": "...", "branch": "stale1", "action": "pruned"}],
 "failed":  [{"spec": "bogus", "reason": "no worktree for branch"}],
 "counts": {"removed": 1, "pruned": 1, "failed": 1}}
```

Emitted for `--dry-run` too (with `"dry_run": true`), enabling scripted pre-flight.

### `wtl` enrichment

- `--json` rows gain `"missing": bool` (directory gone) and
  `"dirty_details": ["staged"|"unstaged"|"untracked", ...]` (empty when clean).
  Additive keys only — existing consumers unaffected.
- Human output: stale rows show `(gone)` in place of the commit hash — self-documenting,
  no indicator-column/legend changes, no column shift.

### `-q/--quiet` on `wtc` and `wtdel`

Exports `HUG_QUIET` (matching `wtl`/`parse_common_flags` semantics): suppresses summary
blocks, legends, info/tips; keeps errors, prompts, and data (JSON/paths) intact.

## 8. Design F — Family ergonomics

- **`wtc -p/--path PATH`** flag (mirrors `wtdel -p`); positional `[path]` kept for
  back-compat; both given ⇒ usage error (exit 2). (`wtl -p` remains `--path-only` — a
  different argument *shape*; called out in both helps.)
- **`wtc -B/--with-branch`** as alias of `--new`: one symmetric concept across the family
  — "the branch joins the operation" (create it on the way in; delete it on the way out).
- **Error message upgrades**:
  - branch-in-use (`wtc`): name the holding worktree and the next step:
    `Branch 'X' is checked out in worktree <path>. Remove it (hug wtdel X) or pick another branch.`
  - `--base` resolution failure: `Cannot resolve '--base <ref>' to a commit. Branches,
    tags, hashes, and relative refs (HEAD~N) are accepted — verify the ref exists (hug ll).`
- **Help clarifications**: `wtl -b` may return multiple rows (same branch, multiple
  checkouts); `wtc` `-y`/`--new` interplay (decision §2.2); `wtdel` batch pre-flight
  description; `HUG_FORCE`/`HUG_YES` env vars documented in both helps.

## 9. Out of scope (explicit)

| Item | Disposition |
|---|---|
| DX-5 (`wtl -p` count line on stderr) | Won't fix — already correct (stderr, only when >1); documented in CAPTURING OUTPUT. |
| DX-20 (`wtc --detach`) | Deferred → GitHub issue (additive feature, separate design). |
| Batch `wtc` | YAGNI. |
| `wtll`/`wtsh`/`wt` adoption of new conventions | Follow-up; this PR establishes the convention and the shared helpers. |

## 10. Test plan

BATS (unit + lib), following existing harness patterns:

- **Safety**: main repo *survives* `wtdel -p <main> -f` from a linked worktree (the P0
  regression test); no `rm -rf` on git refusal (locked/unknown failure leaves dir
  intact); submodule double-force retry path; scoped prune leaves unrelated stale
  entries untouched (E3b regression).
- **Batch**: mixed valid+invalid removes nothing and reports every item; exit 3 vs 1
  classes; stale-by-branch resolves to prune; single batch confirmation (HUG_TEST_MODE
  interactive simulation); `-B` after partial failure.
- **Contract**: `--base HEAD~1` succeeds (DX-1 regression); exit codes per class for
  wtc/wtl/wtdel; `HUG_FORCE` env on `wtc`; `-f --dry-run` on `wtc`; `-p`/`-B` flags on
  `wtc`; `-q` suppression (chatter gone, data intact).
- **JSON**: `wtc --json`/`wtdel --json`/`wtl --json` parse via `python3 -m json.tool`;
  `missing` + `dirty_details` fields; zero non-JSON bytes on stdout.

## 11. Commit sequence (one PR)

1. `docs`: this design spec.
2. `fix(wtdel)`: P0 — main-worktree guard (all modes) + abolish rm -rf fallback +
   scoped prune + regression tests. [N1, N2, DX-11]
3. `refactor(lib)`: remove dead worktree functions. [N3]
4. `feat(lib)`: exit-code constants/helpers; danger-tier `-y` rejection → exit 3. [DX-18]
5. `feat(wtdel)`: pre-flight batch model + single batch confirmation + exit codes +
   `--json` + `-q`. [DX-9, DX-12, DX-13, DX-15, DX-17]
6. `feat(wtc)`: env parity, `-f --dry-run`, `-p/--path`, `-B` alias, message upgrades,
   exit codes, `--json`, `-q`. [N4, N5, DX-2-docs, DX-3, DX-4, DX-14, DX-16, DX-19]
7. `feat(wtl)`: `(gone)` display + `missing`/`dirty_details` JSON fields. [N6, DX-8]
8. `docs`: tier model + exit codes in help texts & docs site; `hug-confirm` docstring
   fix; CHANGELOG; DX-6 help note. [DX-6, DX-10]

Each commit passes `make test` independently.
