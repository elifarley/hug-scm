# Command Family Map

This map provides a high-level overview of Hug's command families, grouped by prefix. Each family focuses on a specific aspect of version control, making it easy to remember and discover commands. Use this as a mental model: prefixes indicate the operation type, and suffixes add specificity.

::: tip How to Use This Map
- **Prefixes** (e.g., `h*`) group related commands.
- **Top Commands** show the most common ones; see individual pages for full details.
- **Memory Hook**: Bold letters highlight the key initials (e.g., `hug h back` → **H**EAD **Back**).
- For interactive exploration, run `hug help` in your terminal.

:::

## Command Families Overview

| Prefix | Category | Description | Top Commands                                                                                                                                                                                                                                                                                                          |
|--------|----------|-------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `h*` | HEAD Operations | Undo, rewind, and inspect commits without losing work. Safest for experimenting. | `hug h back` (**H**EAD **Back** – soft reset), `hug h undo` (**Undo** – mixed reset), `hug h steps <file>` (**Steps** – distance to last file change)                                                                                                                                                                 |
| `w*` | Working Directory | Manage local changes: discard, clean, restore, or park/unpark temp work. Great for cleanup. | `hug w discard <file>` (**W**orking dir **Discard**), `hug w zap-all` (**Zap** **All** – full reset), `hug wip "<msg>"` (**W**ork **I**n **P**rogress – park & switch back), `hug wips "<msg>"` (**W**ork **I**n **P**rogress **S**tay – park & stay), `hug w unwip` (**Un**park **WIP** – integrate WIP branch) |
| `s*` | Status | View repo state: summaries, diffs, and stashes. Essential for daily checks. | `hug s` (**S**tatus snapshot), `hug sw` (**S**tatus + **W**orking diff), `hug ssave` (**S**tash **Save**)                                                                                                                                                                                                             |
| `a*` | Staging/Add | Stage changes for commit: tracked, all, or interactive. Pairs with `s*`. | `hug a <file>` (**A**dd tracked), `hug aa` (**A**dd **A**ll), `hug ap` (**A**dd + **P**atch – interactive)                                                                                                                                                                                                            |
| `b*` | Branching | Create, switch, list, delete, and pull branches. Core for feature isolation and sync. | `hug bc <name>` (**B**ranch **C**reate), `hug b <name>` (**B**ranch switch), `hug bpull` (**B**ranch **Pull** – safe ff-only), `hug bpullr` (**B**ranch **Pull** **R**ebase)                                                                                                                                          |
| `c*` | Commits | Create and amend commits. Focus on atomic, meaningful snapshots. | `hug c "<msg>"` (**C**ommit), `hug caa "<msg>"` (**C**ommit **A**ll **A**mend), `hug cm "<msg>"` (**C**ommit **M**odify – amend)                                                                                                                                                                                      |
| `l*` | Logging | Search and view history: messages, code, authors, files. For debugging timelines. | `hug l` (**L**og summary), `hug lf "<term>"` (**L**og **F**ilter – message search), `hug llf <file>` (**L**og **L**ookup **F**ile)                                                                                                                                                                                    |
| `f*` | File Inspection | Analyze file history: blame, contributors, origin. Ownership and evolution insights. | `hug fblame <file>` (**F**ile **B**lame), `hug fcon <file>` (**F**ile **CON**tributors), `hug fborn <file>` (**F**ile **B**orn – added date)                                                                                                                                                                          |
| `t*` | Tagging | Manage tags for releases/milestones. Lightweight or annotated. | `hug tc <tag>` (**T**ag **C**reate lightweight), `hug ta <tag> "<msg>"` (**T**ag **A**nnotated), `hug t` (**T**ags list)                                                                                                                                                                                              |
| `r*` | Rebase | Interactive history editing: continue, abort, skip. For clean timelines. | `hug rb <branch>` (**R**ebase onto branch), `hug rbi` (**R**ebase **I**nteractive), `hug rba` (**R**ebase **A**bort)                                                                                                                                                                                                  |
| `m*` | Merge | Integrate branches: squash, fast-forward, or keep. Conflict resolution. | `hug m <branch>` (**M**erge squash), `hug mff <branch>` (**M**erge **F**ast-**F**orward), `hug ma` (**M**erge **A**bort)                                                                                                                                                                                              |

## Visual Command Tree

<details>
<summary>Expand for a tree view of all families</summary>

```
Hug Commands
├── h* (HEAD: Undo & Rewind)
│   ├── h back     # Soft reset (staged)
│   ├── h undo     # Mixed reset (unstaged)
│   ├── h rollback # Hard reset (preserve work)
│   ├── h rewind   # Full hard reset (clean)
│   ├── h files    # Preview affected files
│   └── h steps    # Steps to file change
├── w* (Working Dir: Clean & Restore)
│   ├── w discard  # Discard unstaged/staged
│   ├── w wipe     # Wipe uncommitted
│   ├── w purge    # Purge untracked/ignored
│   ├── w zap      # Wipe + purge (nuclear)
│   ├── w get      # Restore from commit
│   ├── w wip        # Park work & switch back
│   ├── w wips       # Park work & stay on new branch
│   ├── w unwip      # Integrate WIP branch
│   └── w wipdel     # Delete WIP branch
├── s* (Status: View State)
│   ├── s          # Quick summary
│   ├── sl         # List tracked
│   ├── sla        # List all (untracked)
│   ├── ss         # Staged diff
│   ├── su         # Unstaged diff
│   ├── sw         # Working diff (full)
│   └── ssave      # Stash quick
├── a* (Staging: Prepare Commit)
│   ├── a          # Add tracked
│   ├── aa         # Add all
│   ├── ai         # Add interactive
│   └── ap         # Add patch (hunks)
├── b* (Branches: Manage Flow)
│   ├── b          # Switch (interactive)
│   ├── bc         # Create & switch
│   ├── bl         # List local
│   ├── bdel       # Delete safe
│   └── bpush      # Push & upstream
├── c* (Commits: Record Changes)
│   ├── c          # Commit staged
│   ├── caa        # Commit all (tracked + untracked)
│   └── cm         # Amend last
├── l* (Logging: History Search)
│   ├── l          # Oneline log
│   ├── lf         # Filter messages
│   ├── lc         # Code search
│   └── llf        # File history
├── f* (Files: Inspect Authorship)
│   ├── fblame     # Line-by-line blame
│   ├── fcon       # Contributors
│   └── fa         # Author counts
├── t* (Tags: Milestones)
│   ├── t          # List tags
│   ├── tc         # Create lightweight
│   └── ta         # Create annotated
├── r* (Rebase: Edit History)
│   ├── rb         # Rebase onto
│   ├── rbi        # Interactive rebase
│   └── rba        # Abort rebase
└── m* (Merge: Integrate)
    ├── m          # Squash merge
    ├── mff        # Fast-forward only
    └── ma         # Abort merge
```

</details>

## Next Steps
- Pick a family and explore its dedicated page (e.g., [HEAD Operations](commands/head) for `h*`).
- Practice: Run `hug s` to check status, then `hug b` to switch branches.
- For a quick daily reference, see the [Cheat Sheet](/cheat-sheet).
- For full lists, see individual command docs or `hug help` in your repo.

This map evolves with Hug - contribute new families via pull requests!
