# bash completion for the hug command

_hug() {
    local cur prev words cword
    _init_completion -n =: || return

    local hug_path dir scripts aliases all_commands subcmd raw_aliases branch_pattern ref_candidates

    hug_path=$(command -v hug 2>/dev/null)
    if [[ -z "$hug_path" ]]; then
        return 0
    fi
    dir=$(dirname "$hug_path")

    # Collect executable scripts starting with git-
    scripts=()
    for f in "$dir"/git-*; do
        if [[ -x "$f" ]]; then
            script_name=$(basename "$f" | sed 's/^git-//')
            if [[ "$script_name" != "hughelp" ]]; then
                scripts+=("$script_name")
            fi
        fi
    done

    # Collect all git aliases (gracefully handle non-repo), filter empties
    raw_aliases=$(git config --name-only --get-regexp '^alias\.' 2>/dev/null || true)
    if [[ -z "$raw_aliases" ]]; then
        raw_aliases=$(
            git config --get-regexp '^alias\.' 2>/dev/null \
                | sed -E 's/^alias\.([^[:space:]]+).*/alias.\1/' \
                || true
        )
    fi

    mapfile -t aliases < <(
        printf '%s\n' "$raw_aliases" \
        | sed 's/^alias\.//' \
        | sed '/^$/d' \
        | sort -u
    )

    # Filter empties in scripts
    mapfile -t scripts < <(printf '%s\n' "${scripts[@]}" | sed '/^$/d' | sort -u)

    # Combine unique, add 'help' explicitly
    mapfile -t all_commands < <(printf '%s\n' "help" "${scripts[@]}" "${aliases[@]}" | sort -u | sed '/^$/d')

    if [[ $cword -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "${all_commands[*]}" -- "$cur" ) )
        return 0
    fi

    subcmd="${words[1]}"

    # Handle second-level completion for gateways (e.g., 'hug h <TAB>')
    if [[ $cword -eq 2 ]]; then
        gateway_cmds=()
        for f in "$dir"/git-${subcmd}-*; do
            if [[ -x "$f" ]]; then
                gname=$(basename "$f" | sed "s/^git-${subcmd}-//")
                gateway_cmds+=("$gname")
            fi
        done

        # Filter empties
        mapfile -t gateway_cmds < <(printf '%s\n' "${gateway_cmds[@]}" | sed '/^$/d' | sort -u)

        if [[ ${#gateway_cmds[@]} -gt 0 ]]; then
            COMPREPLY=( $(compgen -W "${gateway_cmds[*]}" -- "$cur" ) )
            return 0
        fi
    fi

    # Handle completion for 'w' gateway subcommands (cword >= 3)
    if [[ $cword -ge 3 && ${words[1]} == "w" ]]; then
        local w_subcmd="${words[2]}"
        
        # Complete options for w subcommands
        if [[ $cur == -* ]]; then
            local opts=""
            case "$w_subcmd" in
                discard|discard-all)
                    opts="-u --unstaged -s --staged --dry-run -f --force -h --help"
                    ;;
                purge|purge-all)
                    opts="-u --untracked -i --ignored --dry-run -f --force -h --help"
                    ;;
                wipe|wipe-all)
                    opts="-u -s --dry-run -f --force -h --help"
                    ;;
                zap|zap-all)
                    opts="--dry-run -f --force -h --help"
                    ;;
                wip|wips)
                    opts="--stay -h --help"
                    ;;
                unwip)
                    opts="-f --force --no-squash -h --help"
                    ;;
                wipdel)
                    opts="-f --force -h --help"
                    ;;
                get)
                    opts="-h --help"
                    ;;
            esac
            if [[ -n "$opts" ]]; then
                COMPREPLY=( $(compgen -W "$opts" -- "$cur" ) )
                return 0
            fi
        fi
        
        # Complete file arguments for specific w subcommands
        case "$w_subcmd" in
            discard|purge|wipe|zap)
                if git rev-parse --git-dir > /dev/null 2>&1; then
                    # For these commands, complete with modified files
                    COMPREPLY=( $( { git diff --name-only --relative "${cur}*" 2>/dev/null || true; git diff --cached --name-only --relative "${cur}*" 2>/dev/null || true; git ls-files --others --exclude-standard "${cur}*" 2>/dev/null || true; } | sort -u ) )
                fi
                return 0
                ;;
            unwip|wipdel)
                if git rev-parse --git-dir > /dev/null 2>&1; then
                    # Complete with WIP branches
                    COMPREPLY=( $(git for-each-ref --format='%(refname:short)' --sort=refname 'refs/heads/WIP/' 2>/dev/null | grep "^${cur}" ) )
                fi
                return 0
                ;;
            get)
                # First arg is commit, subsequent are files
                if [[ $cword -eq 3 ]]; then
                    if git rev-parse --git-dir > /dev/null 2>&1; then
                        local ref_candidates=$(git for-each-ref --format='%(refname:short)' refs/ 2>/dev/null || true)
                        COMPREPLY=( $(compgen -W "$ref_candidates" -- "$cur" ) )
                    fi
                else
                    if git rev-parse --git-dir > /dev/null 2>&1; then
                        COMPREPLY=( $(git ls-files --cached "${cur}*" 2>/dev/null) )
                    fi
                fi
                return 0
                ;;
        esac
        return 0
    fi

    # Handle completion for 'h' gateway subcommands (cword >= 3)
    if [[ $cword -ge 3 && ${words[1]} == "h" ]]; then
        local h_subcmd="${words[2]}"
        
        # Complete options for h subcommands
        if [[ $cur == -* ]]; then
            local opts=""
            case "$h_subcmd" in
                back|undo|rollback|rewind)
                    opts="-u --upstream --force --quiet -h --help"
                    ;;
                squash)
                    opts="-u --upstream --force --quiet -h --help"
                    ;;
                files)
                    opts="-u --upstream --quiet --stat -h --help"
                    ;;
                steps)
                    opts="--raw --quiet -h --help"
                    ;;
            esac
            if [[ -n "$opts" ]]; then
                COMPREPLY=( $(compgen -W "$opts" -- "$cur" ) )
                return 0
            fi
        fi
        
        # Complete arguments for h subcommands
        case "$h_subcmd" in
            back|undo|rollback|rewind|squash|files)
                if git rev-parse --git-dir > /dev/null 2>&1; then
                    local ref_candidates=$(git for-each-ref --format='%(refname:short)' refs/ 2>/dev/null || true)
                    COMPREPLY=( $(compgen -W "$ref_candidates" -- "$cur" ) )
                fi
                return 0
                ;;
            steps)
                if git rev-parse --git-dir > /dev/null 2>&1; then
                    COMPREPLY=( $(git ls-files --cached "${cur}*" 2>/dev/null) )
                fi
                return 0
                ;;
        esac
        return 0
    fi

    # Special completion for 'hug help [prefix]' (for cword >=2)
    if [[ "$subcmd" == "help" ]]; then
        local help_opts="a b c f h l p s sh t w"
        COMPREPLY=( $(compgen -W "$help_opts" -- "$cur" ) )
        return 0
    fi
    
    # Handle options for top-level HEAD commands (back, undo, rollback, rewind, squash, files)
    if [[ "$subcmd" =~ ^(back|undo|rollback|rewind)$ ]]; then
        if [[ $cur == -* ]]; then
            COMPREPLY=( $(compgen -W "-u --upstream --force --quiet -h --help" -- "$cur" ) )
            return 0
        fi
        if git rev-parse --git-dir > /dev/null 2>&1; then
            local ref_candidates=$(git for-each-ref --format='%(refname:short)' refs/ 2>/dev/null || true)
            COMPREPLY=( $(compgen -W "$ref_candidates" -- "$cur" ) )
        fi
        return 0
    fi
    
    if [[ "$subcmd" == "squash" ]]; then
        if [[ $cur == -* ]]; then
            COMPREPLY=( $(compgen -W "-u --upstream --force --quiet -h --help" -- "$cur" ) )
            return 0
        fi
        if git rev-parse --git-dir > /dev/null 2>&1; then
            local ref_candidates=$(git for-each-ref --format='%(refname:short)' refs/ 2>/dev/null || true)
            COMPREPLY=( $(compgen -W "$ref_candidates" -- "$cur" ) )
        fi
        return 0
    fi
    
    if [[ "$subcmd" == "files" ]]; then
        if [[ $cur == -* ]]; then
            COMPREPLY=( $(compgen -W "-u --upstream --quiet --stat -h --help" -- "$cur" ) )
            return 0
        fi
        if git rev-parse --git-dir > /dev/null 2>&1; then
            local ref_candidates=$(git for-each-ref --format='%(refname:short)' refs/ 2>/dev/null || true)
            COMPREPLY=( $(compgen -W "$ref_candidates" -- "$cur" ) )
        fi
        return 0
    fi
    
    # Handle top-level WIP commands (wip, wips, unwip, get)
    if [[ "$subcmd" =~ ^(wip|wips)$ ]]; then
        if [[ $cur == -* ]]; then
            if [[ "$subcmd" == "wip" ]]; then
                COMPREPLY=( $(compgen -W "--stay -h --help" -- "$cur" ) )
            else
                COMPREPLY=( $(compgen -W "-h --help" -- "$cur" ) )
            fi
            return 0
        fi
        # Message argument - no completion
        COMPREPLY=()
        return 0
    fi
    
    if [[ "$subcmd" == "unwip" ]]; then
        if [[ $cur == -* ]]; then
            COMPREPLY=( $(compgen -W "-f --force --no-squash -h --help" -- "$cur" ) )
            return 0
        fi
        if git rev-parse --git-dir > /dev/null 2>&1; then
            COMPREPLY=( $(git for-each-ref --format='%(refname:short)' --sort=refname 'refs/heads/WIP/' 2>/dev/null | grep "^${cur}" ) )
        fi
        return 0
    fi
    
    if [[ "$subcmd" == "get" ]]; then
        if [[ $cur == -* ]]; then
            COMPREPLY=( $(compgen -W "-h --help" -- "$cur" ) )
            return 0
        fi
        # First arg is commit, subsequent are files
        if [[ $cword -eq 2 ]]; then
            if git rev-parse --git-dir > /dev/null 2>&1; then
                local ref_candidates=$(git for-each-ref --format='%(refname:short)' refs/ 2>/dev/null || true)
                COMPREPLY=( $(compgen -W "$ref_candidates" -- "$cur" ) )
            fi
        else
            if git rev-parse --git-dir > /dev/null 2>&1; then
                COMPREPLY=( $(git ls-files --cached "${cur}*" 2>/dev/null) )
            fi
        fi
        return 0
    fi
    
    # Special completion for log-outgoing
    if [[ "$subcmd" =~ ^(log-outgoing|lo|lol)$ ]]; then
        if [[ $cur == -* ]]; then
            COMPREPLY=( $(compgen -W "--quiet --fetch -h --help" -- "$cur" ) )
            return 0
        fi
        COMPREPLY=()
        return 0
    fi

    # Arg completion based on subcmd (flat or gateway); only for known commands, else empty
    case "$subcmd" in
        sw|ss|su|add|rm|mv)
            # File completion for known file-taking commands
            COMPREPLY=( $(compgen -f -- "$cur" ) )
            ;;
        b|bc|br|bdel|bdelf|bdelr|branch|co|checkout)
            # Branch completion (local branches, handles spaces, filter empties)
            if git rev-parse --git-dir > /dev/null 2>&1; then
                branch_pattern="$cur"
                if [[ -z "$branch_pattern" ]]; then
                    branch_pattern="*"
                else
                    branch_pattern="${branch_pattern}*"
                fi

                mapfile -t COMPREPLY < <(
                    git branch --list "$branch_pattern" 2>/dev/null \
                    | sed 's/^\* \?//' \
                    | sed '/^$/d'
                )
            else
                COMPREPLY=()
            fi
            ;;
        bll|bl|bla|blr)
            # Branch list commands - no completion
            COMPREPLY=()
            ;;
        *)
            COMPREPLY=()
            ;;
    esac

    return 0
}

complete -F _hug hug
