# VHS Screenshot Generation in CI/CD

This document describes how to integrate VHS screenshot generation into GitHub Actions CI/CD workflows.

## Overview

The documentation build process (`make docs-build`) depends on VHS to generate screenshots and animated GIFs from tape files. This ensures that documentation always includes up-to-date visual examples.

## Current State

As of now, VHS screenshot generation is integrated into the local build process but **not yet** into CI/CD. The documentation deployment workflow needs to be updated.

## Implementation Plan

### Option 1: Generate Screenshots in CI (Recommended)

**Pros:**
- Always up-to-date screenshots
- Ensures tape files are working
- Catches broken tapes early

**Cons:**
- Longer CI build times
- Requires VHS installation in CI
- Requires demo repository setup

**Implementation:**

```yaml
# .github/workflows/deploy-docs.yml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 20

      - name: Install Hug SCM
        run: make install

      - name: Install VHS
        run: |
          # Install VHS from GitHub releases
          VHS_VERSION="v0.7.2"  # Update to latest version
          wget https://github.com/charmbracelet/vhs/releases/download/${VHS_VERSION}/vhs_${VHS_VERSION#v}_Linux_x86_64.tar.gz
          tar -xzf vhs_${VHS_VERSION#v}_Linux_x86_64.tar.gz
          sudo mv vhs /usr/local/bin/
          vhs --version

      - name: Install ttyd (required for VHS)
        run: |
          sudo apt-get update
          sudo apt-get install -y ttyd

      - name: Setup demo repository
        run: |
          source bin/activate
          make demo-repo

      - name: Generate VHS screenshots
        run: |
          source bin/activate
          make vhs

      - name: Install documentation dependencies
        run: make deps-docs

      - name: Build documentation
        run: npm run docs:build  # Skip make docs-build to avoid rebuilding VHS

      # ... rest of deployment steps
```

### Option 2: Pre-generate and Commit Screenshots

**Pros:**
- Faster CI builds (no VHS required)
- Simpler CI configuration
- Guaranteed consistent output

**Cons:**
- Screenshots can become stale
- Manual regeneration required
- Larger git repository (binary files)

**Implementation:**

1. Generate screenshots locally:
   ```bash
   make demo-repo
   make vhs
   ```

2. Commit generated files:
   ```bash
   git add docs/commands/img/*.gif docs/commands/img/*.png
   git commit -m "Update VHS screenshots"
   ```

3. Remove VHS dependency from CI (modify Makefile):
   ```makefile
   # Change docs-build to skip VHS in CI
   docs-build: deps-docs
   ifeq ($(CI),)
       @make vhs  # Only build VHS locally
   endif
       npm run docs:build
   ```

### Option 3: Hybrid Approach (Recommended)

Combine both approaches:

1. **Development:** Generate locally before committing major changes
2. **CI:** Validate that tape files are correct (dry-run) but use committed screenshots
3. **Scheduled:** Run a weekly/monthly job to regenerate and commit updated screenshots

**Implementation:**

```yaml
# .github/workflows/deploy-docs.yml
- name: Validate VHS tapes (dry-run)
  run: |
    if command -v vhs &> /dev/null; then
      make vhs-dry-run
    else
      echo "VHS not installed, skipping validation"
    fi

# .github/workflows/regenerate-screenshots.yml (scheduled)
name: Regenerate VHS Screenshots
on:
  schedule:
    - cron: '0 0 * * 0'  # Weekly on Sunday
  workflow_dispatch:  # Allow manual trigger

jobs:
  regenerate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install dependencies
        run: |
          # Install Hug, VHS, ttyd
          
      - name: Generate screenshots
        run: |
          make demo-repo
          make vhs
          
      - name: Commit and push
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add docs/commands/img/
          git diff --staged --quiet || git commit -m "chore: regenerate VHS screenshots"
          git push
```

## Recommendation

**Use Option 3 (Hybrid Approach)** for the best balance:

1. **Commit screenshots to git** so CI builds are fast and don't require VHS
2. **Validate tape files** in CI with dry-run (if VHS is available)
3. **Automated regeneration** via scheduled workflow to keep screenshots fresh
4. **Manual regeneration** before major releases or when commands change

## Implementation Steps

### Step 1: Update .gitignore

Remove any exclusions for generated screenshots:

```gitignore
# Do NOT ignore generated screenshots (they should be committed)
# docs/commands/img/*.gif
# docs/commands/img/*.png
```

### Step 2: Generate Initial Screenshots

```bash
# Install and setup
make install
source bin/activate
make demo-repo

# Generate all screenshots
make vhs

# Verify generation
ls -la docs/commands/img/
```

### Step 3: Commit Screenshots

```bash
git add docs/commands/img/
git commit -m "chore: add VHS-generated screenshots"
```

### Step 4: Update Makefile (Optional)

Make VHS generation optional in CI:

```makefile
# Check if running in CI
CI ?= $(if $(CI_ENV),true,false)

vhs: demo-repo vhs-check
	@echo "$(BLUE)Building VHS screencasts...$(NC)"
	@bash docs/screencasts/bin/vhs-build.sh --all

docs-build: deps-docs
ifeq ($(CI),true)
	@echo "$(YELLOW)Skipping VHS generation in CI (using committed screenshots)$(NC)"
else
	@make vhs
endif
	@npm run docs:build
```

### Step 5: Create Scheduled Regeneration Workflow

Create `.github/workflows/regenerate-screenshots.yml`:

```yaml
name: Regenerate VHS Screenshots

on:
  schedule:
    - cron: '0 0 1 * *'  # Monthly, first day at midnight
  workflow_dispatch:      # Allow manual trigger

jobs:
  regenerate:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        
      - name: Install Hug SCM
        run: make install
        
      - name: Install VHS
        run: |
          VHS_VERSION="v0.7.2"
          wget -q https://github.com/charmbracelet/vhs/releases/download/${VHS_VERSION}/vhs_${VHS_VERSION#v}_Linux_x86_64.tar.gz
          tar -xzf vhs_${VHS_VERSION#v}_Linux_x86_64.tar.gz
          sudo mv vhs /usr/local/bin/
          
      - name: Install ttyd
        run: sudo apt-get update && sudo apt-get install -y ttyd
        
      - name: Setup demo repository
        run: |
          source bin/activate
          make demo-repo
          
      - name: Generate screenshots
        run: |
          source bin/activate
          make vhs
          
      - name: Check for changes
        id: changes
        run: |
          git diff --quiet docs/commands/img/ || echo "changed=true" >> $GITHUB_OUTPUT
          
      - name: Commit and push
        if: steps.changes.outputs.changed == 'true'
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add docs/commands/img/
          git commit -m "chore: regenerate VHS screenshots [skip ci]"
          git push
```

### Step 6: Document the Process

Add to CONTRIBUTING.md or README:

```markdown
## Updating Screenshots

VHS screenshots are automatically regenerated monthly via GitHub Actions. 

To regenerate manually:

1. Ensure VHS is installed: `make vhs-check`
2. Create demo repository: `make demo-repo`
3. Generate screenshots: `make vhs`
4. Commit changes: `git add docs/commands/img/ && git commit -m "chore: update screenshots"`
```

## Troubleshooting

### VHS Installation Fails in CI

**Problem:** VHS fails to install from GitHub releases

**Solution:** Pin a known working version and verify the download URL

```yaml
- name: Install VHS
  run: |
    VHS_VERSION="v0.7.2"
    ARCH="Linux_x86_64"
    wget https://github.com/charmbracelet/vhs/releases/download/${VHS_VERSION}/vhs_${VHS_VERSION#v}_${ARCH}.tar.gz
    tar -xzf vhs_*.tar.gz
    sudo install -m 755 vhs /usr/local/bin/
```

### Demo Repository Setup Fails

**Problem:** Demo repository creation fails in CI environment

**Solution:** Ensure Git is configured and Hug is activated

```yaml
- name: Setup Git
  run: |
    git config --global user.name "CI Bot"
    git config --global user.email "ci@example.com"
    
- name: Setup demo repository
  run: |
    source bin/activate
    make demo-repo
```

### VHS Hangs or Times Out

**Problem:** VHS tape execution hangs in CI

**Solution:** Add timeout and ensure clean environment

```yaml
- name: Generate screenshots
  timeout-minutes: 10
  run: |
    source bin/activate
    make vhs
```

## Resources

- [VHS GitHub Repository](https://github.com/charmbracelet/vhs)
- [VHS Documentation](https://github.com/charmbracelet/vhs/tree/main/examples)
- [Screencasts README](../docs/screencasts/README.md)
