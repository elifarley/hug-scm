#!/usr/bin/env bash
CMD_BASE="$(readlink -f "$0" 2>/dev/null || greadlink -f "$0")" || CMD_BASE="$0"; CMD_BASE="$(dirname "$CMD_BASE")"
HUG_HOME="$CMD_BASE"
set -euo pipefail  # Exit on error, undefined vars, pipe failures

HUG_CONFIG="$HOME"/.hug-scm

test ! -e "$HUG_CONFIG" && echo "Creating '$HUG_CONFIG'..." && echo "HUG_HOME=$HUG_HOME" > "$HUG_CONFIG"

grep -q HUG_HOME "$HOME"/.bashrc || {
  echo "Configuring '"$HOME"/.bashrc' ..."
  cat <<EOF >> "$HOME"/.bashrc

# Activate Hug
. $HUG_HOME/activate
EOF
}

test -e "$HOME"/.gitconfig && grep -q HUG_HOME "$HOME"/.gitconfig || {
  echo "Configuring '$HOME/.gitconfig' ..."
  cat <<EOF >> "$HOME"/.gitconfig

# Activate Hug aliases
[include]
  path = $HUG_HOME/.gitconfig

EOF
}

cat <<EOF
Hug has been installed.
Open a new terminal and type 'hug help' to learn more about Hug.
Bash completions for hug subcommands are now available (requires bash-completion package installed).
To use it in the current terminal, type:

source $HUG_HOME/activate
EOF
