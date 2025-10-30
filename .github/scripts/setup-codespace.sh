#!/usr/bin/env bash
#==============================================================================
# setup-codespace.sh - Setup script for GitHub Codespaces
#
# This script installs all required dependencies for developing and testing
# Hug SCM in a GitHub Codespace.
#==============================================================================

set -euo pipefail

echo "🚀 Setting up Hug SCM development environment..."

# Install system dependencies
echo "📦 Installing system dependencies..."
sudo apt-get update -qq
sudo apt-get install -y \
    ffmpeg \
    ttyd \
    fish \
    shellcheck \
    bats

# Install Hug SCM
echo "🤗 Installing Hug SCM..."
make install

# Install test dependencies
echo "🧪 Installing test dependencies..."
make test-deps-install

# Install VHS for documentation
echo "📹 Installing VHS..."
make vhs-deps-install

# Install documentation dependencies
echo "📚 Installing documentation dependencies..."
npm ci

# Activate Hug in the current shell
# Use relative path from repository root
echo "✨ Activating Hug SCM..."
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
echo "source ${REPO_ROOT}/bin/activate" >> ~/.bashrc

echo ""
echo "✅ Development environment setup complete!"
echo ""
echo "Available commands:"
echo "  • make help         - Show all available make targets"
echo "  • make test         - Run all tests"
echo "  • make vhs          - Build VHS screencasts"
echo "  • npm run docs:dev  - Start documentation server"
echo ""
echo "Hug SCM is now activated. Type 'hug help' to get started!"
