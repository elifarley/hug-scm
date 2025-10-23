#!/usr/bin/env bash
CMD_BASE="$(readlink -f "$0" 2>/dev/null || greadlink -f "$0")" || CMD_BASE="$0"; CMD_BASE="$(dirname "$CMD_BASE")"
HUG_HOME="$CMD_BASE"
set -euo pipefail  # Exit on error, undefined vars, pipe failures

echo "Installing Hug SCM - Mercurial support..."

# Check if Mercurial is installed
if ! command -v hg >/dev/null 2>&1; then
  echo "⚠️  Warning: Mercurial (hg) is not installed."
  echo "   Hug Mercurial support will not work until you install Mercurial."
  echo "   On Ubuntu/Debian: sudo apt-get install mercurial"
  echo "   On macOS: brew install mercurial"
  echo ""
  read -p "Continue anyway? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

HUG_CONFIG="$HOME"/.hug-scm

# Create or update hug config
if [ ! -e "$HUG_CONFIG" ]; then
  echo "Creating '$HUG_CONFIG'..."
  echo "HUG_HOME=$HUG_HOME" > "$HUG_CONFIG"
else
  # Update existing config
  if ! grep -q "HUG_HOME" "$HUG_CONFIG"; then
    echo "Updating '$HUG_CONFIG'..."
    echo "HUG_HOME=$HUG_HOME" >> "$HUG_CONFIG"
  fi
fi

# Add to .bashrc if not already there
if ! grep -q "hg-config/activate" "$HOME"/.bashrc 2>/dev/null; then
  echo "Configuring '"$HOME"/.bashrc' ..."
  cat <<EOF >> "$HOME"/.bashrc

# Activate Hug for Mercurial
test -f $HUG_HOME/activate && . $HUG_HOME/activate
EOF
fi

# Configure .hgrc if it exists
if [ -e "$HOME"/.hgrc ]; then
  if ! grep -q "path = $HUG_HOME/.hgrc" "$HOME"/.hgrc 2>/dev/null; then
    echo "Configuring '$HOME/.hgrc' ..."
    cat <<EOF >> "$HOME"/.hgrc

# Activate Hug aliases for Mercurial
[include]
  path = $HUG_HOME/.hgrc

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
[include]
  path = $HUG_HOME/.hgrc

EOF
  echo "⚠️  Please edit '$HOME/.hgrc' and set your username/email"
fi

cat <<EOF

✅ Hug Mercurial support has been installed.

To use it:
1. Open a new terminal or run: source $HUG_HOME/activate
2. Navigate to a Mercurial repository
3. Type 'hug help' to see available commands

Note: For full functionality, enable the following Mercurial extensions
      in your ~/.hgrc:
      
      [extensions]
      purge =     # For 'hug w purge' commands
      evolve =    # For 'hug h back/undo' commands (optional)

EOF
