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
. $HUG_HOME/bin/activate
EOF
}

test -e "$HOME"/.gitconfig && grep -q HUG_HOME "$HOME"/.gitconfig || {
  echo "Configuring '$HOME/.gitconfig' ..."
  cat <<EOF >> "$HOME"/.gitconfig

# Activate Hug aliases
[include]
  path = $HUG_HOME/git-config/.gitconfig

EOF
}

# Configure fish shell if fish is installed
if command -v fish &> /dev/null; then
  FISH_CONFIG="$HOME/.config/fish/config.fish"
  mkdir -p "$HOME/.config/fish"
  
  if [ ! -e "$FISH_CONFIG" ] || ! grep -q "Hug SCM activation" "$FISH_CONFIG" 2>/dev/null; then
    echo "Configuring fish shell for Hug..."
    cat <<'EOF' >> "$FISH_CONFIG"

# Hug SCM activation for fish
if test -e "$HOME/.hug-scm"
    # Read HUG_HOME from .hug-scm file (bash format: HUG_HOME=/path)
    set -l hug_config (cat "$HOME/.hug-scm")
    set -l hug_home (string match -r 'HUG_HOME=(.*)' -- $hug_config)[2]
    if test -n "$hug_home"
        set -gx HUG_HOME $hug_home
        set -gx PATH $HUG_HOME/git-config/bin $PATH
    end
end
EOF
  else
    echo "✓ Fish shell already configured for Hug"
  fi
  
  # Set universal PATH for fish (persists across sessions)
  echo "Setting fish universal PATH..."
  fish -c "contains '$HUG_HOME/git-config/bin' \$fish_user_paths; or set -U fish_user_paths '$HUG_HOME/git-config/bin' \$fish_user_paths" 2>/dev/null || true
fi

# Configure .hgrc if it exists
if [ -e "$HOME"/.hgrc ]; then
  if ! grep -q "path = $HUG_HOME/.hgrc" "$HOME"/.hgrc 2>/dev/null; then
    echo "Configuring '$HOME/.hgrc' ..."
    cat <<EOF >> "$HOME"/.hgrc

# Activate Hug aliases for Mercurial
%include $HUG_HOME/hg-config/.hgrc

EOF
  else
    echo "✓ '$HOME/.hgrc' already configured"
  fi
else
  echo "Creating '$HOME/.hgrc' ..."
  cat <<EOF > "$HOME"/.hgrc
[ui]
username = Your Name <your.email@example.com>

# Activate Hug aliases for Mercurial
%include $HUG_HOME/hg-config/.hgrc

EOF
  echo "⚠️  Please edit '$HOME/.hgrc' and set your username/email"
fi

cat <<EOF
Hug has been installed.
Open a new terminal and type 'hug help' to learn more about Hug.
Bash completions for hug subcommands are now available (requires bash-completion package installed).
To use it in the current terminal, type:

source $HUG_HOME/bin/activate
EOF
