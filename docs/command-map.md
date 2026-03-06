# Command Family Map

This map provides a high-level overview of Hug's command families, grouped by prefix. Each family focuses on a specific aspect of version control, making it easy to remember and discover commands. Use this as a mental model: prefixes indicate the operation type, and suffixes add specificity.

::: tip How to Use This Map
- **Prefixes** (e.g., `h*`) group related commands.
- **Top Commands** show the most common ones; see individual pages for full details.
- **Memory Hook**: Bold letters highlight the key initials (e.g., `hug h back` → **H**EAD **Back**).
- For interactive exploration, run `hug help` in your terminal.

:::

## Command Families Overview

This table is the **authoritative source** for Hug's command organization. All commands are verified against actual implementation in `git-config/bin/` and `git-config/.gitconfig`.

| Prefix | Category | Description | Top Commands | Memory Hook |
|--------|----------|-------------|--------------|-------------|
| `h*` | HEAD Operations | Undo, rewind, and inspect commits without losing work | `hug h back`, `hug h undo`, `hug h files`, `hug h steps` | **H**EAD |
| `w*` | Working Directory | Manage local changes: discard, clean, restore, park/unpark work | `hug w get`, `hug w wip`, `hug w zap`, `hug w purge` | **W**orking dir |
| `wt*` | Worktree Management | Create, switch, list, remove worktrees for parallel development | `hug wt`, `hug wtc`, `hug wtl`, `hug wtll`, `hug wtdel` | **WT**orktree |
| `s*` | Status & Staging | View repo state: summaries, diffs, staged/unstaged changes | `hug ss`, `hug su`, `hug sw`, `hug sx` | **S**tatus |
| `a*` | Staging | Stage changes for commit: tracked, all, or interactive | `hug a`, `hug aa`, `hug ai`, `hug ap` | **A**dd/stage |
| `b*` | Branching | Create, switch, list, delete, sync branches | `hug b`, `hug bc`, `hug bl`, `hug br` | **B**ranch |
| `c*` | Commits | Create and amend commits | `hug c`, `hug ca`, `hug cm`, `hug caa` | **C**ommit |
| `l*` | Logging & History | Search and view history: messages, code, authors, files | `hug l`, `hug lc`, `hug lf`, `hug lu` | **L**og |
| `f*` | File Inspection | Analyze file history: blame, contributors, origin | `hug fa`, `hug fb`, `hug fcon`, `hug fborn` | **F**ile |
| `t*` | Tagging | Manage tags for releases and milestones | `hug t`, `hug tc`, `hug ta`, `hug ts` | **T**ag |
| `r*` | Rebase | Interactive history editing and rebasing | `hug rb`, `hug rbi`, `hug rbc`, `hug rba` | **R**ebase |
| `m*` | Merge | Integrate branches with various strategies | `hug m`, `hug ma`, `hug mff`, `hug mkeep` | **M**erge |
| `analyze*` | Advanced Analysis | Advanced repository analysis and insights | `hug analyze deps`, `hug analyze expert`, `hug analyze activity`, `hug analyze co-changes <file>` | **ANALYZE** |
| `stats*` | Repository Statistics | Quick repository statistics and metrics | `hug stats file`, `hug stats author`, `hug stats branch` | **STATS** |
| `(no prefix)` | Utilities | Helper commands: init, clone, remote management, object inspection | `hug init`, `hug clone`, `hug remote2ssh`, `hug type`, `hug dump` | **UTILITY** |

## Visual Command Tree

<details>
<summary>Expand for a tree view of all families</summary>

```
Hug Commands
├── h* (HEAD: Undo & Rewind)
│   ├── h back         # HEAD goes back, keeping changes staged
│   ├── h undo         # HEAD goes back, keeping changes unstaged
│   ├── h rollback     # HEAD goes back, discarding changes but preserving uncommitted work
│   ├── h rewind       # HEAD goes back, discarding ALL changes
│   ├── h squash       # Squash commits
│   ├── h files        # Preview affected files if HEAD moved back
│   └── h steps <file> # Count steps back to reach most recent file change
├── w* (Working Dir: Clean & Restore)
│   ├── w discard      # Discard unstaged/staged changes
│   ├── w discard-all  # Discard across entire repo
│   ├── w wipe <path>  # Discard uncommitted (unstaged + staged)
│   ├── w wipe-all     # Wipe all tracked files
│   ├── w purge <path> # Remove untracked/ignored
│   ├── w purge-all    # Remove all untracked/ignored
│   ├── w zap <path>   # Full cleanup (wipe + purge)
│   ├── w zap-all      # Complete repo cleanup
│   ├── w get          # Restore from commit
│   ├── w wip          # Park work on separate WIP branch
│   ├── w wips         # Park work & stay on new WIP branch
│   ├── w unwip        # Integrate WIP branch into current
│   └── w wipdel       # Delete WIP branch
├── wt* (Worktrees: Parallel Development)
│   ├── wt             # Interactive worktree management
│   ├── wtc <branch>   # Create worktree for branch
│   ├── wtl            # List worktrees (short format)
│   ├── wtll           # List worktrees (long format with details)
│   └── wtdel [path]   # Remove worktree safely
├── s* (Status: View State)
│   ├── s            # Quick status
│   ├── sl           # Status + List tracked
│   ├── sla          # Status + List all (untracked)
│   ├── sli          # Status + List inc. ignored
│   ├── ss           # Status + Staged diff
│   ├── su           # Status + Unstaged diff
│   ├── sw           # Status + Working dir diff (both unstaged and staged)
│   └── sx           # eXtended summary
├── a* (Staging: Prepare Commit)
│   ├── a            # Add tracked
│   ├── aa           # Add all
│   ├── ai           # Add interactive
│   ├── ap           # Add patch (hunks)
│   ├── us           # UnStage
│   ├── usa          # UnStage All
│   └── untrack      # Stop tracking
├── b* (Branches: Manage Flow)
│   ├── b            # Switch (interactive menu)
│   ├── br           # Branch switch remote (alias for b -r)
│   ├── brr          # Branch switch remote refreshed (alias for b -R)
│   ├── bcp          # Branch Copy (alias: bc --no-switch --point-to)
│   ├── bc           # Create & switch
│   ├── bl           # Branch List local
│   ├── bla          # Branch List All
│   ├── blr          # Branch List Remote
│   ├── bll          # Branch List Long (detailed)
│   ├── bmv          # Branch Rename (alias for branch -m)
│   ├── bdel         # Branch Delete safe
│   ├── bdelf        # Branch Delete force
│   ├── bdelr        # Branch Delete remote
│   ├── bpull        # Branch Pull (ff-only)
│   ├── bpullr       # Branch Pull with rebase
│   ├── bpush        # Branch Push & upstream
│   ├── bpushf       # Branch Safe force push
│   ├── bwc          # Branch Which Contain
│   ├── bwp          # Branch Which Point
│   ├── bwnc         # Branch Which not contain
│   ├── bwm          # Branch Which merged
│   └── bwnm         # Branch Which not merged
├── c* (Commits: Record Changes)
│   ├── c            # Commit staged
│   ├── ca           # Commit All tracked
│   ├── caa          # Commit Add All (tracked+untracked)
│   ├── cm           # Commit Modify last (staged)
│   ├── cma          # Commit Modify last (all tracked)
│   ├── ccp          # Commit Copy (cherry-pick)
│   ├── cii          # Commit Interactive (patch)
│   ├── cim          # Commit Interactive Menu
│   └── cmv          # Commit Move to branch
├── l* (Logging: History Search)
│   ├── l            # Oneline log
│   ├── la           # Oneline log (all branches)
│   ├── ll           # Log Long (detailed)
│   ├── lla          # Log Long (all branches)
│   ├── lp           # Log with Patches
│   ├── lo           # Log Outgoing (quiet)
│   ├── lol          # Log Outgoing (Long)
│   ├── lf           # Log: Filter messages
│   ├── lc           # Log: Code search
│   ├── lcr          # Log: Code search (Regex)
│   ├── lau          # Log find by author
│   ├── ld           # Log find by date
│   ├── llf          # Log File history
│   ├── llfs         # Log File history (+Stats)
│   └── llfp         # Log File history (+Patch)
├── f* (Files: Inspect Authorship)
│   ├── fblame       # Line-by-line blame
│   ├── fb           # Blame (porcelain)
│   ├── fcon         # Contributors
│   ├── fa           # Author counts
│   └── fborn        # File origin
├── t* (Tags: Milestones)
│   ├── t            # List tags
│   ├── tc           # Create lightweight
│   ├── ta           # Create annotated
│   ├── ts           # Show tag details
│   ├── tr           # Rename tag
│   ├── tm           # Move tag
│   ├── tma          # Move & re-annotate
│   ├── tpush        # Push tag(s)
│   ├── tpull        # Pull tags
│   ├── tpullf       # Pull tags (force)
│   ├── tdel         # Delete local tag
│   ├── tdelr        # Delete remote tag
│   ├── tco          # Checkout tag
│   ├── twc          # Tags which contain
│   └── twp          # Tags which point
├── r* (Rebase: Edit History)
│   ├── rb           # Rebase onto
│   ├── rbi          # Interactive rebase
│   ├── rbc          # Rebase continue
│   ├── rba          # Rebase abort
│   └── rbs          # Rebase skip
├── m* (Merge: Integrate)
│   ├── m            # Squash merge
│   ├── mkeep        # Merge (keep commit)
│   ├── mff          # Fast-forward only
│   └── ma           # Merge abort
├── (no prefix) (Utilities: Helper Commands)
│   ├── init           # Initialize new repository
│   ├── clone          # Clone repository (auto-detect VCS)
│   ├── remote2ssh     # Convert remote HTTPS to SSH
│   ├── type           # Show Git object type
│   ├── dump           # Show Git object contents
│   └── untrack        # Stop tracking files
├── analyze* (Advanced Analysis)
│   ├── analyze co-changes  # Find files related to one file (`--all` for repo-wide coupling)
│   ├── analyze activity    # Temporal commit patterns
│   ├── analyze deps        # Commit dependency graph
│   └── analyze expert      # Code ownership and expertise
└── stats* (Repository Statistics)
    ├── stats file      # File-level statistics
    ├── stats author    # Author contributions
    └── stats branch    # Branch statistics
```

</details>

## Next Steps

- **New to Hug?** Check the [Getting Started](getting-started.md) guide
- **Git users transitioning to Hug** → See the [Git to Hug Translation Guide](git-to-hug.md)
- **Daily workflows** → See the [Cheat Sheet](cheat-sheet.md) for scenario-based commands
- **Deep learning** → Pick a family above and explore command details
- **Interactive help** → Run `hug help` in your terminal to discover commands

---

**Maintenance Note**: This map is the authoritative source for command organization. When adding new commands:
1. Update the authoritative table above
2. Add to the visual command tree
3. Update README.md brief summary (if new prefix family)
4. Add to cheat-sheet.md if commonly used
