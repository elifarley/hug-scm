# Fish completion for the hug command.
# Provides completions for top-level commands, subcommands (e.g., for 'h' and 'w'), and arguments like files, branches, tags, and refs.

# Top-level commands (static unique list from reference, including help)
complete -c hug -f -a "a aa ai ap alias b bs bl bla blr bc br bdel bdelf bdelr bpush bwc bwp bwnc bwm bwnm c ca caa cc cm cma cii cim h l ll la llf llfp llfs lf lc lcr lau ld lp m mff mkeep ma o rb rbi rbc rba rbs s sh shp shc shf sl sla sli sls ssave speak sshow sapply spop spopf sbranch sdrop sclear ss su sw sx t tc ta ts tr tm tma tdel tdelr tco tpull tpullf tpush twc twp type dump us usa untrack w fblame fb fcon fa fborn statusbase remote2ssh hughelp help"

# Subcommands for 'h' gateway (hug h <TAB>)
complete -c hug -n 'test (count $argv) -eq 2; and test $argv[2] = h' -f -a "back undo rollback rewind"

# Args for 'h' subcommands (e.g., hug h back <TAB> for refs/numbers)
complete -c hug -n 'test (count $argv) -gt 3; and contains -- $argv[2] back undo rollback rewind; and string match -qrv -- "^-" $argv[-1]' -f -a "(begin
    set -l prefix $argv[-1]
    set -l prefix_regex (string escape --style=regex -- $prefix)
    if string match -qr \"^[0-9]+$\" -- $prefix
        printf '%s\n' 1 2 3 4 5 6 7 8 9 10
    else
        string match -r \"^$prefix_regex\" -- (string replace -r '^[* ] ' '' -- (git branch --list 2>/dev/null))
        string match -r \"^$prefix_regex\" -- (git tag --list 2>/dev/null)
        string match -r \"^$prefix_regex\" -- (git rev-list --all --abbrev-commit 2>/dev/null)
    end | sort -u
end)"

# Subcommands for 'w' gateway (hug w <TAB>)
complete -c hug -n 'test (count $argv) -eq 2; and test $argv[2] = w' -f -a "backup changes discard discard-all get purge purge-all restore wipe wipe-all zap zap-all"

# Options and args for 'w backup' (hug w backup <TAB>)
complete -c hug -n 'test (count $argv) -eq 3; and test $argv[2] = backup; and test $argv[3] != -m; and test $argv[3] != --message' -f -a "-m --message -h --help"
complete -c hug -n 'test (count $argv) -gt 3; and test $argv[2] = backup; and test $argv[3] = -m; or test $argv[3] = --message' -f  # No completion for message arg

# Args for 'w get' (commits/refs)
complete -c hug -n 'test (count $argv) -eq 3; and test $argv[2] = get' -f -a "(git log --oneline --format='%h' 2>/dev/null | string split ' ' | string match -v '' | string match -r '^$argv[3].*'; or git branch --list $argv[3]* 2>/dev/null; or git tag --list $argv[3]* 2>/dev/null | sort -u)"

# Options for 'w discard/discards-all/etc.' (hug w discard <TAB>)
complete -c hug -n 'test (count $argv) -eq 3; and contains -- $argv[2] discard discard-all purge purge-all wipe wipe-all zap zap-all; and string match -q '^-' $argv[3]' -f -a "-h --help --dry-run -f --force"
complete -c hug -n 'test (count $argv) -eq 3; and contains -- $argv[2] purge purge-all; and string match -q '^-' $argv[3]' -f -s u -l untracked -d "Untracked files only"
complete -c hug -n 'test (count $argv) -eq 3; and contains -- $argv[2] purge purge-all; and string match -q '^-' $argv[3]' -f -s i -l ignored -d "Ignored files only"
complete -c hug -n 'test (count $argv) -eq 3; and contains -- $argv[2] discard discard-all; and string match -q '^-' $argv[3]' -f -s u -l unstaged -d "Unstaged changes only"
complete -c hug -n 'test (count $argv) -eq 3; and contains -- $argv[2] discard discard-all; and string match -q '^-' $argv[3]' -f -s s -l staged -d "Staged changes only"

# Files/paths for 'w' subcommands (e.g., hug w discard <files>)
complete -c hug -n 'test (count $argv) -gt 4; and test $argv[2] = w; and contains -- $argv[3] discard discard-all purge purge-all wipe wipe-all zap zap-all; and string match -qrv -- "^-" $argv[-1]' -f -a "(git ls-files --others --exclude-standard -- $argv[-1]* 2>/dev/null; or git status --porcelain=v1 --name-only | string match -r '^$argv[-1].*' 2>/dev/null | sort -u)"

# Branch completion for branch-related commands (e.g., hug b <TAB>)
complete -c hug -n 'test -n (git rev-parse --git-dir 2>/dev/null)'; and contains -- $argv[2] b bc br bdel bdelf bdelr sbranch' -f -a "(git branch --list $argv[-1]* 2>/dev/null | string replace -r '^[* ] ' '' | string match -v '^$' | sort -u)"

# Tag completion for tag-related commands (e.g., hug t <TAB>)
complete -c hug -n 'test -n (git rev-parse --git-dir 2>/dev/null)'; and contains -- $argv[2] t tc ta ts tr tm tma tdel tdelr tco' -f -a "(git tag --list $argv[-1]* 2>/dev/null | sort -u)"

# File completion for file-taking commands (e.g., hug a <TAB>, hug fblame <TAB>)
complete -c hug -n 'test -n (git rev-parse --git-dir 2>/dev/null)'; and contains -- $argv[2] a us llf llfp llfs fblame fb fcon fa fborn shf ss su sw' -f -a "(git ls-files -- $argv[-1]* 2>/dev/null; or git status --porcelain=v1 --name-only | string match -r '^$argv[-1].*' 2>/dev/null | sort -u)"

# Ref/commit completion for log/show/cherry-pick/HEAD commands (e.g., hug l <TAB> for partial hashes, hug cc <TAB>)
complete -c hug -n 'test -n (git rev-parse --git-dir 2>/dev/null)'; and contains -- $argv[2] l ll la lf lc lcr lau ld lp sh shp shc sl sla sli cc h-back h-undo h-rollback h-rewind' -f -a "(begin
    if string match -qr '^[0-9a-f]{3,}$' $argv[-1]
        git rev-list --all --abbrev-commit 2>/dev/null | string match -r '^$argv[-1]'
    else
        git branch --list $argv[-1]* 2>/dev/null; or git tag --list $argv[-1]* 2>/dev/null; or git rev-list --all --abbrev-ref=short 2>/dev/null | sort -u
    end
end)"

# Options for log/show/status aliases (basic Git opts)
complete -c hug -n 'contains -- $argv[2] l ll la lf lc lcr lau ld lp sh shp shc sl sla sli; and string match -q "^-" $argv[-1]' -f -a "--all -p -i --file"

# Remote completion for remote2ssh (hug remote2ssh <TAB>)
complete -c hug -n 'test $argv[2] = remote2ssh; and test (count $argv) -eq 3' -f -a "(git remote 2>/dev/null | string match -r '^$argv[3].*' | sort -u)"

# Help prefix options (hug help <TAB>)
complete -c hug -n 'test $argv[2] = help' -f -a "a b c f h l p s sh t w"

# Default file/dir completion for other args (fallback)
complete -c hug -n 'not set -q argv[2]; or not contains -- $argv[2] help h w b t a l cc sbranch remote2ssh' -f -a "(git status --porcelain=v1 --name-only 2>/dev/null | string trim -c ' ?' | sort -u | string match -r '^$argv[-1].*'; or true)"
