# ~/.config/fish/completions/hug.fish
# Comprehensive Fish shell completions for the Hug CLI tool.
# This script provides:
# - Top-level completions for all alias-based and custom commands, plus standard Git subcommands.
# - Subcommand completions for custom scripts (e.g., h, w).
# - Basic positional argument completions (files, branches, tags, refs, remotes, stashes) where applicable.
# - Option completions for commands with explicit options (from reference).
# - For alias-based Git wrappers (e.g., l -> git log), we provide basic common Git options and defer positional to Git-like logic.
#   Full Git option completions are not duplicated here (would require copying entire git.fish); instead, common flags are listed.
# - No file completions at top-level (-f used); enabled dynamically for relevant subcommands.
# - Assumes running inside a Git repo; completions check git rev-parse --git-dir where needed.
# - Dynamic: Uses current token for filtering (e.g., branch names starting with typed prefix).

# Helper functions for common completions (from Hug reference rules).

function __hug_check_git_repo
    git rev-parse --git-dir >/dev/null 2>&1
end

function __hug_complete_files
    if not __hug_check_git_repo
        return
    end
    set -l current (commandline -ct)
    # 1st: Prefix match for unmodified tracked files only
    # Step 1: Get all tracked files (prefix-globbed for efficiency)
    set -l all_tracked (git ls-files --cached -- $current* 2>/dev/null)
    # Step 2: Get modified tracked paths (from status porcelain, parsed)
    set -l modified_paths (git status --porcelain=v1 --untracked-files=all 2>/dev/null | string sub --start=3 | string match -e "*$current*" | string match -v '^$' )  # Filter non-empty, substring for consistency
    # Step 3: Subtract modified from tracked (unmodified only)
    set -l unmodified_tracked
    for file in $all_tracked
        if not contains $file $modified_paths  # Fish 'contains' for exact match exclusion
            set unmodified_tracked $unmodified_tracked $file
        end
    end
    echo $unmodified_tracked  # Output prefix suggestions
    # 2nd: Substring match for modified + untracked (same as before, but full modified/untracked)
    git status --porcelain=v1 --untracked-files=all 2>/dev/null | string sub --start=3 | string match -e "*$current*" | string match -v '^$'
    # Optional: Add descriptions to 2nd (uncomment and adjust parsing for status codes)
    # git status --porcelain=v1 --untracked-files=all 2>/dev/null | while read line
    #     set path (string sub --start=3 $line)
    #     set status (string sub --end=3 $line | string trim)  # Last 3 chars for code (e.g., ' M ', '?? ')
    #     if string match -q '*??*' $status
    #         echo "$path\tUntracked"
    #     else
    #         echo "$path\tModified"
    #     end
    # end | string match -e "*$current*"
end

function __hug_complete_branches
    if not __hug_check_git_repo
        return
    end
    set -l current (commandline -ct)
    git branch --list $current* 2>/dev/null
end

function __hug_complete_all_branches
    if not __hug_check_git_repo
        return
    end
    set -l current (commandline -ct)
    git branch -a $current* 2>/dev/null | string trim -c ' *'
end

function __hug_complete_tags
    if not __hug_check_git_repo
        return
    end
    set -l current (commandline -ct)
    git tag --list $current* 2>/dev/null
end

function __hug_complete_remotes
    if not __hug_check_git_repo
        return
    end
    set -l current (commandline -ct)
    git remote $current* 2>/dev/null
end

function __hug_complete_refs  # Branches, tags, remotes, HEAD, etc.
    if not __hug_check_git_repo
        return
    end
    set -l current (commandline -ct)
    git for-each-ref --format='%(refname:short)' refs/heads/ refs/tags/ refs/remotes/ $current* 2>/dev/null
    if string match -q '*HEAD*' $current
        echo HEAD
    end
    if string match -q '*@{u}*' $current
        git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null
    end
end

function __hug_complete_stashes
    if not __hug_check_git_repo
        return
    end
    set -l current (commandline -ct)
    git stash list --format=%gd $current* 2>/dev/null
end

function __hug_complete_dates  # Basic date completions (not dynamic, common formats)
    set -l current (commandline -ct)
    # Common: yesterday, today, 1.week.ago, etc. (Git accepts natural language)
    echo "yesterday today tomorrow now" | string split ' ' | string match -e "*$current*"
    # Could add more, but keep simple
end

function __hug_complete_search_terms  # For lf, lc, etc.; no dynamic, just files or empty
    __hug_complete_files
end

# List of all top-level Hug commands (unique from reference, alias-based + custom).
# Note: w-backup has hyphen; treated as single token.
set -l hug_tops alias l ll la llf llfp llfs lf lc lcr lau ld lp fblame fb fcon fa fborn a aa ai ap us usa untrack back undo rollback rewind w-backup wip unwip ca cm cma cii cim o cc caa ssave ssavea ssavefull sls speak sshow sapply spopf spop sdrop sbranch sclear sl sla sli s ss su sw sx sh shp shc shf t tc ta ts tr tm tma tpush tpull tpullf tdel tdelr tco twc twp b bs bl bla blr bc br bdel bdelf bdelr bwc bwp bwnc bwm bwnm bpush rb rbi rbc rba rbs m mff mkeep ma bpull pullall type dump remote2ssh h w c statusbase hughelp

# Top-level completions: Custom Hug commands + standard Git subcommands.
# Trigger ONLY if no subcommand seen (after 'hug ' only).
# Fixed: Pass $hug_tops directly (no unnecessary escape/substitution).
complete -c hug -n 'not __fish_seen_subcommand_from $hug_tops' -f -a "$hug_tops" -d "Hug commands"
complete -c hug -n 'not __fish_seen_subcommand_from $hug_tops (git --list-cmds=main 2>/dev/null)' -f -a "(git --list-cmds=main 2>/dev/null)" -d "Git commands"

# Global help flag (supported where noted).
complete -c hug -s h -l help -d "Show help" -n '__fish_seen_subcommand_from (string escape -- $hug_tops)'

# =====================================
# Alias-Based Commands (Section 1)
# For these, provide positional args and common Git options where applicable.
# Common Git log options (for l* commands): --oneline, --graph, --decorate, -p, --all, etc.
set -l common_log_opts --oneline --graph --decorate --color -p --all -i --date=short --pretty=log1
set -l common_status_opts -s -b --porcelain
set -l common_show_opts -p --stat
set -l common_commit_opts -m -a -v --amend
set -l common_cherry_opts --no-commit -e
set -l common_rebase_opts --interactive --root --continue --abort --skip
set -l common_merge_opts --squash --ff --no-ff
set -l common_branch_opts -u -f --track

# Discoverability
complete -c hug -n '__fish_seen_subcommand_from alias' -f -a "(__hug_complete_search_terms)" -d "Pattern"

# Logging (l*)
# After l/ll/la/ld/lp: Git log options + files/dates/authors dynamic where applicable.
for sub in l ll la ld lp
    complete -c hug -n "__fish_seen_subcommand_from $sub" -a "$common_log_opts" -d "Git log options"
    # Enable file completion for file-related (e.g., lp, but general)
    complete -c hug -n "__fish_seen_subcommand_from $sub" -a "(__hug_complete_files)"
end
# llf/llfp/llfs: Require <file>, optional -p
for sub in llf llfp llfs
    complete -c hug -n "__fish_seen_subcommand_from $sub" -s p -d "Show patches"
    complete -c hug -n "__fish_seen_subcommand_from $sub" -a "(__hug_complete_files)" -d "File"
end
# lf/lc/lcr: <search-term> or <regex>, optional -i -p --all [-- <file>]
for sub in lf lc lcr
    complete -c hug -n "__fish_seen_subcommand_from $sub" -s i -d "Ignore case"
    complete -c hug -n "__fish_seen_subcommand_from $sub" -s p -d "Patches"
    complete -c hug -n "__fish_seen_subcommand_from $sub" -l all -d "All"
    # Search term (no dynamic, but files after --)
    complete -c hug -n "__fish_seen_subcommand_from $sub" -a "(__hug_complete_search_terms)"
end
# lau: <author>
complete -c hug -n '__fish_seen_subcommand_from lau' -a "(git log --format='%aN' | sort -u)" -d "Author"
# ld: <since> [<until>]
complete -c hug -n '__fish_seen_subcommand_from ld' -a "(__hug_complete_dates)" -d "Date"

# File Inspection (f*)
for sub in fblame fb fcon fa fborn
    complete -c hug -n "__fish_seen_subcommand_from $sub" -a "(__hug_complete_files)" -d "File"
end

# Staging (a*)
complete -c hug -n '__fish_seen_subcommand_from a' -a "(__hug_complete_files)" -d "Files"
# aa/ai/ap: No args
complete -c hug -n '__fish_seen_subcommand_from aa ai ap' -f

# Unstaging (us*)
complete -c hug -n '__fish_seen_subcommand_from us untrack' -a "(__hug_complete_files)" -d "Files"
# usa: No args
complete -c hug -n '__fish_seen_subcommand_from usa' -f

# HEAD Operations (back etc.; map to custom, but listed as top-level aliases)
# Assume top-level back etc. take [<n|commit>] optional
for sub in back undo rollback rewind
    complete -c hug -n "__fish_seen_subcommand_from $sub" -a "(__hug_complete_refs)" -d "Commit or n"
end

# Working Directory (w* aliases; but w is custom, these are separate)
# w-backup: [-m <message>] optional
complete -c hug -n '__fish_seen_subcommand_from w-backup' -s m -d "Message" -a "(__hug_complete_files)" -d "Files?"
# wip/unwip: No args
complete -c hug -n '__fish_seen_subcommand_from wip unwip' -f

# Commits (c*)
# ca/cm/cma/cii/cim/caa/o: No positional, Git commit options
for sub in ca cm cma cii cim caa o
    complete -c hug -n "__fish_seen_subcommand_from $sub" -a "$common_commit_opts" -d "Git commit options"
end
# cc: <commit-range> [cherry opts]
complete -c hug -n '__fish_seen_subcommand_from cc' -a "(__hug_complete_refs)" -d "Commit range"
complete -c hug -n '__fish_seen_subcommand_from cc' -a "$common_cherry_opts" -d "Cherry-pick options"

# ssave/ssavefull: No args
complete -c hug -n '__fish_seen_subcommand_from ssave ssavefull' -f
# ssavea: <message>
complete -c hug -n '__fish_seen_subcommand_from ssavea' -a " " -d "Message"  # Free text
# sls/sclear: No args
complete -c hug -n '__fish_seen_subcommand_from sls sclear' -f
# speak/sshow/sapply/spopf/spop/sdrop: [<stash@{n}>]
for sub in speak sshow sapply spopf spop sdrop
    complete -c hug -n "__fish_seen_subcommand_from $sub" -a "(__hug_complete_stashes)" -d "Stash"
end
# sbranch: <branch> [<stash>]
complete -c hug -n '__fish_seen_subcommand_from sbranch' -a "(__hug_complete_branches)" -d "Branch"
complete -c hug -n '__fish_seen_subcommand_from sbranch; __fish_seen_subcommand_from ... wait, positional second' -a "(__hug_complete_stashes)"  # Approximate

# Status (s*)
# sl/sla/sli/statusbase: Git status options only (no files)
for sub in sl sla sli statusbase
    complete -c hug -n "__fish_seen_subcommand_from $sub" -a "$common_status_opts" -d "Git status options"
    complete -c hug -n "__fish_seen_subcommand_from $sub" -s h -l help -d "Help"
end

# s: Quick summary (no args, no files)
complete -c hug -n "__fish_seen_subcommand_from s" -f -d "Quick summary (no args)"
complete -c hug -n "__fish_seen_subcommand_from s" -s h -l help -d "Help"

# ss/su/sw: Optional [<file>] + help
for sub in ss su sw
    complete -c hug -n "__fish_seen_subcommand_from $sub" -a "(__hug_complete_files)" -d "File (optional)"
    complete -c hug -n "__fish_seen_subcommand_from $sub" -s h -l help -d "Help"
end

# sx: Working summary (no files, options only)
complete -c hug -n "__fish_seen_subcommand_from sx" -l no-color -d "No color"
complete -c hug -n "__fish_seen_subcommand_from sx" -s h -l help -d "Help"
complete -c hug -n "__fish_seen_subcommand_from sx" -f  # Suppress other suggestions

# Show (sh*)
# sh/shp/twc/bwc etc.: Optional [<commit>]
for sub in sh shp twc bwc bwnc bwm bwnm twp bwp
    complete -c hug -n "__fish_seen_subcommand_from $sub" -a "(__hug_complete_refs)" -d "Commit"
end
# shc: <commit>
complete -c hug -n '__fish_seen_subcommand_from shc' -a "(__hug_complete_refs)" -d "Commit"
# shf: <file> [show opts]
complete -c hug -n '__fish_seen_subcommand_from shf' -a "(__hug_complete_files)" -d "File"
complete -c hug -n '__fish_seen_subcommand_from shf' -a "$common_show_opts" -d "Git show options"

# Tags (t*)
# t: [<pattern>]
complete -c hug -n '__fish_seen_subcommand_from t' -a "(__hug_complete_tags)" -d "Pattern"
# tc/ta/tm/tma/tdel/tdelr/ts/tco: <tag> [opt]
for sub in tc ta tm tma tdel tdelr ts tco
    complete -c hug -n "__fish_seen_subcommand_from $sub" -a "(__hug_complete_tags)" -d "Tag"
end
# ta/tma: [<message>] or <message>
complete -c hug -n '__fish_seen_subcommand_from ta; not __fish_seen_subcommand_from ...' -a " " -d "Message"  # After tag
complete -c hug -n '__fish_seen_subcommand_from tma' -a " " -d "Message"
# tr: <old> <new>
complete -c hug -n '__fish_seen_subcommand_from tr' -a "(__hug_complete_tags)" -d "Old tag"
# tm/tma/tco: [<commit>/object]
complete -c hug -n '__fish_seen_subcommand_from tm tma tco' -a "(__hug_complete_refs)" -d "Commit"
# tpush: [<tags>]
complete -c hug -n '__fish_seen_subcommand_from tpush' -a "(__hug_complete_tags)" -d "Tags"
# tpull/tpullf: No args
complete -c hug -n '__fish_seen_subcommand_from tpull tpullf' -f

# Branches (b*)
# b/bc/m/rb etc.: <branch>
for sub in b bc m mff mkeep rb
    complete -c hug -n "__fish_seen_subcommand_from $sub" -a "(__hug_complete_branches)" -d "Branch"
end
# bs/bl/bla/blr/bdel/bdelf/bdelr/br: No/optional args
complete -c hug -n '__fish_seen_subcommand_from bs' -f
complete -c hug -n '__fish_seen_subcommand_from bl bla blr' -a "(__hug_complete_all_branches)" -d "Branches"
complete -c hug -n '__fish_seen_subcommand_from bdel bdelf bdelr br' -a "(__hug_complete_branches)" -d "Branch"
# bpush: [options] [<remote>] [<url>] (custom, but alias here)
complete -c hug -n '__fish_seen_subcommand_from bpush' -a "$common_branch_opts" -d "Branch options"
complete -c hug -n '__fish_seen_subcommand_from bpush' -a "(__hug_complete_remotes)" -d "Remote"
# bwc etc.: [<commit>]
for sub in bwc bwp bwnc bwm bwnm
    complete -c hug -n "__fish_seen_subcommand_from $sub" -a "(__hug_complete_refs)" -d "Commit/object"
end

# Rebase (rb*)
complete -c hug -n '__fish_seen_subcommand_from rbi' -a "$common_rebase_opts" -d "Rebase options"
complete -c hug -n '__fish_seen_subcommand_from rbi' -a "(__hug_complete_refs)" -d "Commit"
# rbc/rba/rbs: No args
complete -c hug -n '__fish_seen_subcommand_from rbc rba rbs' -f

# Merge (m*)
complete -c hug -n '__fish_seen_subcommand_from m mff mkeep' -a "$common_merge_opts" -d "Merge options"
# ma: No args
complete -c hug -n '__fish_seen_subcommand_from ma' -f

# Pull
complete -c hug -n '__fish_seen_subcommand_from bpull pullall' -f

# Utilities
complete -c hug -n '__fish_seen_subcommand_from type dump' -a "(__hug_complete_refs)" -d "Object"
complete -c hug -n '__fish_seen_subcommand_from remote2ssh' -a "(__hug_complete_remotes)" -d "Remote"

# =====================================
# Custom Script-Based Commands (Section 2)
# These have explicit subcommands/options from reference.

# h (HEAD operations)
set -l h_subs back undo rollback rewind
complete -c hug -n '__fish_seen_subcommand_from h; not __fish_seen_subcommand_from (string escape -- $h_subs)' -f -a "back\t'Soft reset (keep staged)' undo\t'Mixed reset (keep unstaged)' rollback\t'Keep reset (preserve local)' rewind\t'Hard reset (destructive)'"
for sub in $h_subs
    complete -c hug -n "__fish_seen_subcommand_from h $sub" -s h -l help -d "Help"
    complete -c hug -n "__fish_seen_subcommand_from h $sub" -a "(__hug_complete_refs)" -d "n or commit (optional)"
end

# w (Working Directory)
set -l w_subs discard discard-all purge purge-all wipe wipe-all zap zap-all backup restore get changes
complete -c hug -n '__fish_seen_subcommand_from w; not __fish_seen_subcommand_from (string escape -- $w_subs)' -f -a "discard\t'Discard tracked changes' discard-all\t'Repo-wide discard' purge\t'Remove untracked/ignored' purge-all\t'Repo-wide purge' wipe\t'Wipe staged+unstaged' wipe-all\t'Repo-wide wipe' zap\t'Full reset (wipe+purge)' zap-all\t'Repo-wide zap' backup\t'Stash safely' restore\t'Restore from stash' get\t'Get files from commit' changes\t'Working summary'"
# discard/discard-all options + <paths> or none
for sub in discard discard-all
    complete -c hug -n "__fish_seen_subcommand_from w $sub" -s u -l unstaged -d "Unstaged (default)"
    complete -c hug -n "__fish_seen_subcommand_from w $sub" -s s -l staged -d "Staged"
    complete -c hug -n "__fish_seen_subcommand_from w $sub" -l dry-run -d "Dry run"
    complete -c hug -n "__fish_seen_subcommand_from w $sub" -s f -l force -d "Force"
    complete -c hug -n "__fish_seen_subcommand_from w $sub" -s h -l help -d "Help"
    complete -c hug -n "__fish_seen_subcommand_from w $sub" -a "(__hug_complete_files)" -d "Paths (required for discard)"
end
# purge/purge-all
for sub in purge purge-all
    complete -c hug -n "__fish_seen_subcommand_from w $sub" -s u -l untracked -d "Untracked (default)"
    complete -c hug -n "__fish_seen_subcommand_from w $sub" -s i -l ignored -d "Ignored"
    complete -c hug -n "__fish_seen_subcommand_from w $sub" -l dry-run -d "Dry run"
    if string match -q '*all' $sub
        complete -c hug -n "__fish_seen_subcommand_from w $sub" -s f -l force -d "Force"
    end
    complete -c hug -n "__fish_seen_subcommand_from w $sub" -s h -l help -d "Help"
    complete -c hug -n "__fish_seen_subcommand_from w purge" -a "(__hug_complete_files)" -d "Paths (required)"
end
# wipe/wipe-all: -u -s --dry-run -f, paths or none
for sub in wipe wipe-all
    complete -c hug -n "__fish_seen_subcommand_from w $sub" -s u -d "Unstaged"
    complete -c hug -n "__fish_seen_subcommand_from w $sub" -s s -d "Staged"
    complete -c hug -n "__fish_seen_subcommand_from w $sub" -l dry-run -d "Dry run"
    complete -c hug -n "__fish_seen_subcommand_from w $sub" -s f -d "Force"
    if not string match -q '*all' $sub
        complete -c hug -n "__fish_seen_subcommand_from w $sub" -a "(__hug_complete_files)" -d "Paths"
    end
end
# zap/zap-all: --dry-run [-f for all], paths or none
for sub in zap zap-all
    complete -c hug -n "__fish_seen_subcommand_from w $sub" -l dry-run -d "Dry run"
    if string match -q '*all' $sub
        complete -c hug -n "__fish_seen_subcommand_from w $sub" -s f -l force -d "Force"
    end
    complete -c hug -n "__fish_seen_subcommand_from w $sub" -s h -l help -d "Help"
    if not string match -q '*all' $sub
        complete -c hug -n "__fish_seen_subcommand_from w $sub" -a "(__hug_complete_files)" -d "Paths"
    end
end
# backup: [-m <message>]
complete -c hug -n '__fish_seen_subcommand_from w backup' -s m -l message -d "Message" -a " "
complete -c hug -n '__fish_seen_subcommand_from w backup' -s h -l help -d "Help"
# restore: No args (placeholder)
complete -c hug -n '__fish_seen_subcommand_from w restore' -f
# get: <commit> [files...]
complete -c hug -n '__fish_seen_subcommand_from w get' -a "(__hug_complete_refs)" -d "Commit"
complete -c hug -n '__fish_seen_subcommand_from w get; __fish_seen_subcommand_from ...' -a "(__hug_complete_files)" -d "Files (optional)"
# changes: No args
complete -c hug -n '__fish_seen_subcommand_from w changes' -f

# c (Commit): [git-commit-opts]
complete -c hug -n '__fish_seen_subcommand_from c' -a "$common_commit_opts" -d "Git commit options"
complete -c hug -n '__fish_seen_subcommand_from c' -s h -l help -d "Help"

# bpush: [options] [<remote>] [<url>]
complete -c hug -n '__fish_seen_subcommand_from bpush' -s u -l update -d "Update"
complete -c hug -n '__fish_seen_subcommand_from bpush' -s f -l force -d "Safe force"
complete -c hug -n '__fish_seen_subcommand_from bpush' -l unsafe -d "Force"
complete -c hug -n '__fish_seen_subcommand_from bpush' -s t -l track -d "Track"
complete -c hug -n '__fish_seen_subcommand_from bpush' -s h -l help -d "Help"
complete -c hug -n '__fish_seen_subcommand_from bpush' -a "(__hug_complete_remotes)" -d "Remote"
complete -c hug -n '__fish_seen_subcommand_from bpush' -a " " -d "URL"  # Free text for URL

# cc (Cherry-pick): [cherry-opts] <commit-range>...
complete -c hug -n '__fish_seen_subcommand_from cc' -a "$common_cherry_opts" -d "Cherry-pick options"
complete -c hug -n '__fish_seen_subcommand_from cc' -a "(__hug_complete_refs)" -d "Commit range"
complete -c hug -n '__fish_seen_subcommand_from cc' -s h -l help -d "Help"

# caa: [git-commit-opts]
complete -c hug -n '__fish_seen_subcommand_from caa' -a "$common_commit_opts" -d "Git commit options"

# s/ss/su/sw/sx/statusbase: As above in alias section (overlaps)

# remote2ssh: [<remote>]
complete -c hug -n '__fish_seen_subcommand_from remote2ssh' -a "(__hug_complete_remotes)" -d "Remote (optional)"

# hughelp: [<prefix>]
complete -c hug -n '__fish_seen_subcommand_from hughelp' -a " " -d "Prefix (optional)"
