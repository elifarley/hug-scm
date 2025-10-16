# Fish completion for the hug command

# Top-level commands (help, scripts, aliases)
complete -c hug -f -a "(begin
    set -l scripts
    set -l dir (dirname (which hug))
    for f in $dir/git-*
        if test -x $f -a (basename $f | sed 's/^git-//' | sed '/hughelp/d') != ''
            set scripts $scripts (basename $f | sed 's/^git-//')
        end
    end
    set -l raw_aliases (git config --name-only --get-regexp '^alias\\.' 2>/dev/null | sed 's/^alias\\.//' | sed '/^$/d' | sort -u)
    echo 'help' $scripts $raw_aliases | sort -u | sed '/^$/d'
end)"

# Gateway subcommands (e.g., hug h <TAB>, hug w <TAB>)
complete -c hug -n '__fish_use_subcommand' -f -a "(begin
    set -l subcmd $argv[2]
    set -l dir (dirname (which hug))
    set -l gateway_cmds
    for f in $dir/git-$subcmd-*
        if test -x $f
            set gateway_cmds $gateway_cmds (basename $f | sed \"s/^git-$subcmd-//\")
        end
    end
    echo $gateway_cmds | tr ' ' '\n' | sort -u | sed '/^$/d'
end)"

# Specific w gateway subcommands (e.g., hug w discard <TAB>)
complete -c hug -n 'test $argv[2] = "w"' -f -a "(begin
    set -l partial_sub $argv[3]
    set -l dir (dirname (which hug))
    set -l matching_subs
    for f in $dir/git-w-$partial_sub*
        if test -x $f
            set matching_subs $matching_subs (basename $f | sed 's/^git-w-//')
        end
    end
    echo $matching_subs | tr ' ' '\n' | sort -u | sed '/^$/d'
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
complete -c hug -n 'test $argv[2] = "w"; and contains -- $argv[3] discard discard-all sw add rm mv ss' -f -a "(git diff --name-only --relative (string join ' ' $argv[4..-1])* 2>/dev/null; or git diff --cached --name-only --relative (string join ' ' $argv[4..-1])* 2>/dev/null) | sort -u"

# Branch completion for branch-related commands
complete -c hug -n 'test -n (git rev-parse --git-dir 2>/dev/null)'; and contains -- $argv[2] b* branch co checkout' -f -a "(git branch --list $argv[-1]* 2>/dev/null | sed 's/^[* ] //' | sed '/^$/d')"

# Ref completion for HEAD-related commands
complete -c hug -n 'test -n (git rev-parse --git-dir 2>/dev/null)'; and contains -- $argv[2] h-back h-undo h-rollback h-rewind h' -f -a "(git for-each-ref --format='%(refname:short)' refs/ 2>/dev/null)"

# Help sub-options
complete -c hug -n 'test $argv[2] = "help"' -f -a "a b c f h l p s sh t w"
