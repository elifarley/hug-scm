# Command Family Map

This map provides a high-level overview of Hug's command families, grouped by prefix. Each family focuses on a specific aspect of version control, making it easy to remember and discover commands. Use this as a mental model: prefixes indicate the operation type, and suffixes add specificity.

::: tip How to Use This Map
- **Prefixes** (e.g., `h*`) group related commands.
- **Top Commands** show the most common ones; see individual pages for full details.
- **Memory Hook**: Bold letters highlight the key initials (e.g., `hug h back` → **H**EAD **Back**).
- For interactive exploration, run `hug help` in your terminal.

:::

## Command Families Overview

| Prefix | Category | Description | Top Commands                                                                                                                                                                                                                                                                                                     |
|--------|----------|-------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `h*` | HEAD Operations | Undo, rewind, and inspect commits without losing work. Safest for experimenting. | `hug h back` (**H**EAD **Back** – HEAD goes back, keeping changes staged), `hug h undo` (**Undo** – HEAD goes back, keeping changes unstaged), `hug h rewind` (**Rewind** – HEAD goes back, discarding all changes), `hug h squash` (**Squash** – combine commits)                                               |
| `w*` | Working Directory | Manage local changes: discard, clean, restore, or park/unpark temp work. Great for cleanup. | `hug w discard <file>` (**W**orking dir **Discard**), `hug w zap-all` (**Zap** **All** – full reset), `hug wip "<msg>"` (**W**ork **I**n **P**rogress – park & switch back), `hug wips "<msg>"` (**W**ork **I**n **P**rogress **S**tay – park & stay), `hug w unwip` (**Un**park **WIP** – integrate WIP branch) |
| `s*` | Status | View repo state: summaries, diffs, and stashes. Essential for daily checks. | `hug s` (**S**tatus), `hug sl` (**S**tatus + **L**ist), `hug sla` (**S**tatus + **L**ist **A**ll), `hug ss` (**S**tatus + **S**taged diff), `hug su` (**S**tatus + **U**nstaged diff)                                                                                                                            |
| `a*` | Staging/Add | Stage changes for commit: tracked, all, or interactive. Pairs with `s*`. | `hug a <file>` (**A**dd tracked), `hug aa` (**A**dd **A**ll), `hug ap` (**A**dd + **P**atch – interactive)                                                                                                                                                                                                       |
| `b*` | Branching | Create, switch, list, delete, and pull branches. Core for feature isolation and sync. | `hug b <name>` (**B**ranch switch), `hug bc <name>` (**B**ranch **C**reate), `hug bl` (**B**ranch **L**ist), `hug bpull` (**B**ranch **Pull** – safe ff-only), `hug bpullr` (**B**ranch **Pull** **R**ebase)                                                                                                     |
| `c*` | Commits | Create and amend commits. Focus on atomic, meaningful snapshots. | `hug c "<msg>"` (**C**ommit), `hug caa "<msg>"` (**C**ommit **A**dd **A**ll), `hug cm "<msg>"` (**C**ommit **M**odify – amend), `hug cc <commit>` (**C**ommit **C**opy)                                                                                                                                          |
| `l*` | Logging | Search and view history: messages, code, authors, files. For debugging timelines. | `hug l` (**L**og), `hug ll` (**L**og **L**ong), `hug lf "<term>"` (**L**og **F**ilter – Find commit messages), `hug lc "<term>"` (**L**og **C**ode search), `hug llf <file>` (**L**og **L**ookup **F**ile), `hug lol` (**L**og **O**utgoing **L**ong)                                                            |
| `f*` | File Inspection | Analyze file history: blame, contributors, origin. Ownership and evolution insights. | `hug fblame <file>` (**F**ile **B**lame), `hug fcon <file>` (**F**ile **CON**tributors), `hug fa <file>` (**F**ile **A**uthor counts), `hug fborn <file>` (**F**ile **B**orn)                                                                                                                                    |
| `t*` | Tagging | Manage tags for releases/milestones. Lightweight or annotated. | `hug t` (**T**ags list), `hug tc <tag>` (**T**ag **C**reate lightweight), `hug ta <tag> "<msg>"` (**T**ag **A**nnotated), `hug tpush <tag>` (**T**ag **Push**)                                                                                                                                                   |
| `r*` | Rebase | Interactive history editing: continue, abort, skip. For clean timelines. | `hug rb <branch>` (**R**ebase onto branch), `hug rbi` (**R**ebase **I**nteractive), `hug rbc` (**R**ebase **C**ontinue), `hug rba` (**R**ebase **A**bort)                                                                                                                                                        |
| `m*` | Merge | Integrate branches: squash, fast-forward, or keep. Conflict resolution. | `hug m <branch>` (**M**erge squash), `hug mkeep <branch>` (**M**erge **Keep** commit), `hug mff <branch>` (**M**erge **F**ast-**F**orward), `hug ma` (**M**erge **A**bort)                                                                                                                                       |

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
│   ├── w discard    # Discard unstaged/staged
│   ├── w discard-all
│   ├── w wipe <path> # Discard uncommitted (unstaged + staged)
│   ├── w wipe-all
│   ├── w purge <path># Purge untracked/ignored
│   ├── w purge-all
│   ├── w zap <path>  # Wipe + purge
│   ├── w zap-all
│   ├── w get        # Restore from commit
│   ├── w wip        # Park work on separate WIP branch 
│   ├── w wips       # Park work & stay on new WIP branch
│   ├── w unwip      # Integrate WIP branch into current
│   └── w wipdel     # Delete WIP branch
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
│   ├── bc           # Create & switch
│   ├── bl           # Branch List local
│   ├── bla          # Branch List All
│   ├── blr          # Branch List Remote
│   ├── bll          # Branch List Long (detailed)
│   ├── br           # Branch Rename
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
│   └── cc           # Commit Copy
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
│   ├── tpush        # Push a tag
│   └── tpusha       # Push all tags
├── r* (Rebase: Edit History)
│   ├── rb           # Rebase onto
│   ├── rbi          # Interactive rebase
│   ├── rbc          # Rebase continue
│   ├── rba          # Rebase abort
│   └── rbs          # Rebase skip
└── m* (Merge: Integrate)
    ├── m            # Squash merge
    ├── mkeep        # Merge (keep commit)
    ├── mff          # Fast-forward only
    └── ma           # Merge abort
```

</details>

## Next Steps
- Pick a family and explore its dedicated page (e.g., [HEAD Operations](commands/head) for `h*`).
- Practice: Run `hug s` to check status, then `hug b` to switch branches.
- For a quick daily reference, see the [Cheat Sheet](/cheat-sheet).
- For full lists, see individual command docs or `hug help` in your repo.

This map evolves with Hug - contribute new families via pull requests!
