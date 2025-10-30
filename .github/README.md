# GitHub Configuration

This directory contains GitHub-specific configuration files for the Hug SCM project.

## Contents

### `devcontainer.json`

Pre-configured development environment for GitHub Codespaces and VS Code Dev Containers.

**Features:**
- Ubuntu-based environment with Git and Node.js
- All system dependencies pre-installed (ffmpeg, ttyd, fish, shellcheck, bats)
- Hug SCM automatically installed and activated
- VHS tool for generating documentation images
- Test and documentation dependencies ready to use
- GitHub Copilot and shell extensions pre-installed

**Usage:**

1. **GitHub Codespaces:**
   ```
   Code → Codespaces → Create codespace
   ```

2. **VS Code Dev Containers:**
   ```
   F1 → Dev Containers: Reopen in Container
   ```

After opening, everything is ready to use:
```bash
hug help              # Hug is already activated
make test             # Run tests
make vhs              # Generate documentation images
npm run docs:dev      # Start documentation server
```

### `scripts/setup-devcontainer.sh`

Automated setup script called by the devcontainer configuration.

**What it does:**
- Installs system dependencies via apt-get
- Runs `make install` to set up Hug SCM
- Installs test dependencies via `make test-deps-install`
- Installs VHS via `make vhs-deps-install`
- Installs npm packages for documentation
- Activates Hug SCM in the bash shell

This script ensures a consistent development environment across all contributors.

## Workflows

### `workflows/test.yml`

Runs the test suite on every push and pull request.

### `workflows/regenerate-vhs-images.yml`

Automatically regenerates VHS documentation images on a monthly schedule or manual trigger.

**Fixed issues:**
- VHS installation now works with GitHub API blocks using fallback version
- Tar extraction properly handles nested directories
- Local installation detection works correctly

### `workflows/deploy-docs.yml`

Builds and deploys documentation to GitHub Pages.

## Maintenance

When adding new dependencies:

1. **System packages:** Add to `scripts/setup-devcontainer.sh`
2. **Node packages:** Use `npm install --save-dev` (updates package.json)
3. **Test dependencies:** Add to appropriate Makefile target

When updating workflows:

1. Test changes locally when possible
2. Use workflow dispatch to manually trigger test runs
3. Check workflow logs for any failures

## Related Documentation

- [Copilot Instructions](copilot-instructions.md) - Guidelines for GitHub Copilot agents
- [VHS Troubleshooting](../docs/screencasts/VHS_TROUBLESHOOTING.md) - VHS-specific issues
- [Testing Guide](../TESTING.md) - Running and writing tests
