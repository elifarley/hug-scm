# Fish completion for the hug command

# Top-level commands (help, scripts, aliases)
complete -c hug -f -a "(begin
    set -l scripts
    set -l dir (dirname (which hug))
    for f in $dir/git-*
        if test -x $f
            set name (basename $f | string replace -r '^git-(.+)\\.' '$1')
            if test $name != 'hughelp' -a (string length $name) -gt 0
                set scripts $scripts $name
            end
        end
    end
    set -l raw_aliases (git config --name-only --get-regexp '^alias\\.' 2>/dev/null)
    set -l processed_aliases
    for alias in $raw_aliases
        set alias (string replace -r '^alias\.(.+)' '$1' $alias)
        if test (string length $alias) -gt 0
            set processed_aliases $processed_aliases $alias
        end
    end
    set -l unique_aliases (printf '%s\n' $processed_aliases | sort -u)
    printf '%s\n' help $scripts $unique_aliases | sort -u | string match -v '^$'
end)"

# Gateway subcommands (e.g., hug h <TAB>, hug w <TAB>)
complete -c hug -n '__fish_use_subcommand' -f -a "(begin
    set -l subcmd $argv[2]
    set -l dir (dirname (which hug))
    set -l gateway_cmds
    for f in $dir/git-$subcmd-*
        if test -x $f
            set name (basename $f | string replace -r '^git-$subcmd-(.+)\\.' '$1')
            if test (string length $name) -gt 0
                set gateway_cmds $gateway_cmds $name
            end
        end
    end
    printf '%s\n' $gateway_cmds | sort -u | string match -v '^$'
end)"

# Specific w gateway subcommands (e.g., hug w discard <TAB>)
complete -c hug -n 'test $argv[2] = "w"' -f -a "(begin
    set -l partial_sub $argv[3]
    set -l dir (dirname (which hug))
    set -l matching_subs
    for f in $dir/git-w-$partial_sub*
        if test -x $f
            set name (basename $f | string replace -r '^git-w-(.+)\\.' '$1')
            if test (string length $name) -gt 0
                set matching_subs $matching_subs $name
            end
        end
    end
    printf '%s\n' $matching_subs | sort -u | string match -v '^$'
end)"

# Options for specific subcommands
complete -c hug -n 'test $argv[2] = "w"; and test $argv[3] = "discard"' -s u -l unstaged -f -d "Discard unstaged changes only"
complete -c hug -n 'test $argv[2] = "w"; and test $argv[3] = "discard"' -s s -l staged -f -d "Discard staged changes only"
complete -c hug -n 'test $argv[2] = "w"; and test $argv[3] = "discard"' -l dry-run -f -d "Show what would be discarded without applying"
complete -c hug -n 'test $argv[2] = "w"; and test $argv[3] = "discard"' -s f -l force -f -d "Skip confirmation"
complete -c hug -n 'test $argv[2] = "w"; and test $argv[3] = "discard"' -s h -l help -f -d "Show help"

complete -c hug -n 'test $argv[2] = "w"; and test $argv[3] = "discard-all"' -s u -l unstaged -f -d "Discard unstaged changes only"
complete -c hug -n 'test $argv[2] = "w"; and test $argv[3] = "discard-all"' -s s -l staged -f -d "Discard staged changes only"
complete -c hug -n 'test $argv[2] = "w"; and test $argv[3] = "discard-all"' -l dry-run -f -d "Show what would be discarded without applying"
complete -c hug -n 'test $argv[2] = "w"; and test $argv[3] = "discard-all"' -s f -l force -f -d "Skip confirmation"
complete -c hug -n 'test $argv[2] = "w"; and test $argv[3] = "discard-all"' -s h -l help -f -d "Show help"

# File completion for commands that take paths (e.g., w discard <files>)
complete -c hug -n 'test $argv[2] = "w"; and contains -- $argv[3] discard discard-all sw add rm mv ss' -f -a "(git diff --name-only --relative (string join ' ' $argv[4..-1])* 2>/dev/null; or git diff --cached --name-only --relative (string join ' ' $argv[4..-1])* 2>/dev/null | sort -u)"

# Branch completion for branch-related commands
complete -c hug -n 'test -n (git rev-parse --git-dir 2>/dev/null)'; and contains -- $argv[2] b* branch co checkout' -f -a "(git branch --list $argv[-1]* 2>/dev/null | string replace -r '^[* ] ' '' | string match -v '^$')"

# Ref completion for HEAD-related commands
complete -c hug -n 'test -n (git rev-parse --git-dir 2>/dev/null)'; and contains -- $argv[2] h-back h-undo h-rollback h-rewind h' -f -a "(git for-each-ref --format='%(refname:short)' refs/ 2>/dev/null)"

# Help sub-options
complete -c hug -n 'test $argv[2] = "help"' -f -a "a b c f h l p s sh t w"
