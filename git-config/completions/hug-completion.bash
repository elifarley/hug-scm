# bash completion for the hug command

_hug() {
    local cur prev words cword
    _init_completion -n =: || return

    local hug_path dir scripts aliases all_commands subcmd

    hug_path=$(command -v hug 2>/dev/null)
    if [[ -z "$hug_path" ]]; then
        return 1
    fi
    dir=$(dirname "$hug_path")

    # Collect executable scripts starting with git-
    scripts=()
    for f in "$dir"/git-*; do
        if [[ -f "$f" ]]; then
            local script_name
            script_name=$(basename "$f" | sed 's/^git-//')
            scripts+=("$script_name")
        fi
    done

    # Collect all git aliases
    aliases=($(git config --get-regexp '^alias\.' 2>/dev/null | cut -d '.' -f2 | cut -d '=' -f1 | sort -u))

    # Combine unique
    all_commands=($(printf '%s\n' "${scripts[@]}" "${aliases[@]}" | sort -u))

    if [[ $cword -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "${all_commands[*]}" -- $cur ) )
    else
        subcmd="${words[1]}"

        case "$subcmd" in
            help)
                local help_opts="a b c f h l p s sh t w"
                COMPREPLY=( $(compgen -W "$help_opts" -- $cur ) )
                ;;
            sw|add|rm|mv|*)
                # File completion
                COMPREPLY=( $(compgen -f -- $cur ) )
                ;;
            b*|branch|co|checkout)
                # Branch completion (local branches)
                if git rev-parse --git-dir > /dev/null 2>&1; then
                    COMPREPLY=( $(git branch --list "$cur*" 2>/dev/null | sed 's/^\s*\*?\s*//' ) )
                fi
                ;;
            *)
                COMPREPLY=()
                ;;
        esac
    fi
}

complete -F _hug hug
