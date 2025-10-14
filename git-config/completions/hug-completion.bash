# bash completion for the hug command

_hug() {
    local cur prev words cword
    _init_completion -n =: || return

    local hug_path dir scripts aliases all_commands subcmd

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
    mapfile -t aliases < <(git config --get-regexp '^alias\.' 2>/dev/null || true | cut -d '.' -f2 | cut -d '=' -f1 | grep -v '^$' | sort -u)

    # Filter empties in scripts
    mapfile -t scripts < <(printf '%s\n' "${scripts[@]}" | grep -v '^$' | sort -u)

    # Combine unique, add 'help' explicitly
    mapfile -t all_commands < <(printf '%s\n' "help" "${scripts[@]}" "${aliases[@]}" | sort -u | grep -v '^$')

    if [[ $cword -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "${all_commands[*]}" -- $cur ) )
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
        mapfile -t gateway_cmds < <(printf '%s\n' "${gateway_cmds[@]}" | grep -v '^$' | sort -u)

        if [[ ${#gateway_cmds[@]} -gt 0 ]]; then
            COMPREPLY=( $(compgen -W "${gateway_cmds[*]}" -- $cur ) )
            return 0
        fi
    fi

    # Special completion for 'hug help [prefix]' (for cword >=2)
    if [[ "$subcmd" == "help" ]]; then
        local help_opts="a b c f h l p s sh t w"
        COMPREPLY=( $(compgen -W "$help_opts" -- $cur ) )
        return 0
    fi

    # Arg completion based on subcmd (flat or gateway); only for known commands, else empty
    case "$subcmd" in
        sw|add|rm|mv|ss)
            # File completion for known file-taking commands
            COMPREPLY=( $(compgen -f -- $cur ) )
            ;;
        b*|branch|co|checkout)
            # Branch completion (local branches, handles spaces, filter empties)
            if git rev-parse --git-dir > /dev/null 2>&1; then
                mapfile -t COMPREPLY < <(git branch --list "${cur}*" 2>/dev/null | sed 's/^\* \?//' | grep -v '^$')
            else
                COMPREPLY=()
            fi
            ;;
        h-back|h-undo|h-rollback|h-rewind)
            # Ref completion for known HEAD subcommands
            COMPREPLY=( $(compgen -W "$(git for-each-ref --format='%(refname:short)' refs/ 2>/dev/null || true)" -- $cur ) )
            ;;
        h)
            # Fallback ref completion for partial HEAD gateway
            COMPREPLY=( $(compgen -W "$(git for-each-ref --format='%(refname:short)' refs/ 2>/dev/null || true)" -- $cur ) )
            ;;
        *)
            COMPREPLY=()
            ;;
    esac

    return 0
}

complete -F _hug hug
