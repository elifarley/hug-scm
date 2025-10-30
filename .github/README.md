# GitHub Configuration

This directory contains GitHub-specific configuration files for the Hug SCM project.

## Contents

### Workflows

Located in `workflows/` directory:

#### `workflows/test.yml`

Runs the test suite on every push and pull request.

#### `workflows/regenerate-vhs-images.yml`

Automatically regenerates VHS documentation images on a monthly schedule or manual trigger.

**Fixed issues:**
- VHS installation now works with GitHub API blocks using fallback version v0.10.0
- Tar extraction properly handles nested directories
- Local installation detection works correctly

#### `workflows/deploy-docs.yml`

Builds and deploys documentation to GitHub Pages.

### Scripts

Located in `scripts/` directory and root of `.github/`:

#### `copilot-setup.sh`

Setup script for GitHub Copilot agent environment. This script is automatically executed by GitHub Copilot when agents work on this repository.

**What it does:**
- Installs essential system dependencies (ffmpeg, ttyd, fish, shellcheck)
- Runs `make install` to set up Hug SCM
- Installs VHS via `make vhs-deps-install`
- Installs test dependencies via `make test-deps-install`
- Uses error handling to continue even if some steps fail

**Note:** This is a lightweight setup optimized for Copilot agents, not for full development.

#### `scripts/setup-codespace.sh`

Automated setup script for GitHub Codespaces (called by `/.devcontainer/devcontainer.json`).

**What it does:**
- Installs system dependencies via apt-get (ffmpeg, ttyd, fish, shellcheck, bats)
- Runs `make install` to set up Hug SCM
- Installs test dependencies via `make test-deps-install`
- Installs VHS via `make vhs-deps-install`
- Installs npm packages for documentation
- Activates Hug SCM in the bash shell

This script ensures a consistent development environment for all Codespace users.

### Copilot Instructions

#### `copilot-instructions.md`

Guidelines and instructions for GitHub Copilot agents working on this repository. This file is automatically read by GitHub Copilot to understand:
- Project structure and organization
- Coding standards and conventions
- Testing requirements
- Development workflow
- Common tasks and patterns

**Note:** GitHub Copilot agents run in a pre-configured environment managed by GitHub. They do not use devcontainer configurations.

## Development Environments

### For Regular Development (GitHub Codespaces)

Use the devcontainer at `/.devcontainer/devcontainer.json`:

**Usage:**
1. **GitHub Codespaces:**
   ```
   Code → Codespaces → Create codespace
   ```

2. **VS Code Dev Containers:**
   ```
   F1 → Dev Containers: Reopen in Container
   ```

**What's included:**
- Ubuntu-based environment with Git and Node.js
- All system dependencies pre-installed (ffmpeg, ttyd, fish, shellcheck, bats)
- Hug SCM automatically installed and activated
- VHS tool for generating documentation images
- Test and documentation dependencies ready to use
- GitHub Copilot and shell extensions pre-installed

After opening, everything is ready to use:
```bash
hug help              # Hug is already activated
make test             # Run tests
make vhs              # Generate documentation images
npm run docs:dev      # Start documentation server
```

### For GitHub Copilot Agents

GitHub Copilot agents run in a managed environment and use:
- `.github/copilot-setup.sh` - Automated setup script executed when agents start
- `.github/copilot-instructions.md` - Guidelines and instructions for agents

The setup script installs essential dependencies:
- System tools (ffmpeg, ttyd, fish, shellcheck)
- Hug SCM installation
- VHS for documentation generation
- Test dependencies

The agents have access to:
- Standard development tools (bash, git, etc.)
- The repository files and structure
- Custom instructions from `copilot-instructions.md`
- Dependencies installed by `copilot-setup.sh`

## Maintenance

When adding new dependencies:

1. **System packages:** Add to `scripts/setup-codespace.sh`
2. **Node packages:** Use `npm install --save-dev` (updates package.json)
3. **Test dependencies:** Add to appropriate Makefile target

When updating workflows:

1. Test changes locally when possible
2. Use workflow dispatch to manually trigger test runs
3. Check workflow logs for any failures

## Related Documentation

- [Copilot Instructions](copilot-instructions.md) - Guidelines for GitHub Copilot agents
- [Devcontainer](../.devcontainer/devcontainer.json) - Codespaces development environment
- [VHS Troubleshooting](../docs/screencasts/VHS_TROUBLESHOOTING.md) - VHS-specific issues
- [Testing Guide](../TESTING.md) - Running and writing tests
