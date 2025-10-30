#!/usr/bin/env bash
#==============================================================================
# copilot-setup.sh - Setup script for GitHub Copilot agent environment
#
# This script is automatically executed by GitHub Copilot to prepare the
# environment when agents work on this repository. It installs only the
# essential dependencies needed for Copilot agents to perform their tasks.
#==============================================================================

set -euo pipefail

echo "🤖 Setting up environment for GitHub Copilot agent..."

# Update package lists
sudo apt-get update -qq

# Install essential system dependencies
# Note: ffmpeg, ttyd, and fish are needed for VHS documentation generation
echo "📦 Installing system dependencies..."
sudo apt-get install -y \
    ffmpeg \
    ttyd \
    fish \
    shellcheck \
    || echo "⚠️  Some dependencies failed to install, continuing..."

# Install Hug SCM
echo "🤗 Installing Hug SCM..."
make install || echo "⚠️  Hug installation had issues, continuing..."

# Install VHS for documentation work
echo "📹 Installing VHS..."
make vhs-deps-install || echo "⚠️  VHS installation failed, continuing..."

# Install test dependencies if tests might be run
echo "🧪 Installing test dependencies..."
make test-deps-install || echo "⚠️  Test dependencies installation had issues, continuing..."

echo ""
echo "✅ GitHub Copilot agent environment setup complete!"
echo ""
echo "Available tools:"
echo "  • hug (source bin/activate to use)"
echo "  • vhs (docs/screencasts/bin/vhs)"
echo "  • make (see 'make help' for targets)"
echo "  • git, bash, fish, shellcheck"
