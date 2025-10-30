# VHS Image Generation Troubleshooting

## Overview

This document provides guidance for troubleshooting issues with VHS (Video Hotkey Script) image generation in the Hug SCM project.

## Common Issues

### 1. Frame Directory Conflicts

**Problem:** VHS creates directories with image file extensions (e.g., `output.png/`) containing frame files, which can conflict with the expected output files.

**Symptoms:**
```bash
cp: 'hug-sl-states.png/frame-text-00621.png' and 'hug-sl-states.png/frame-text-00621.png' are the same file
```

**Solution:** The `vhs-cleanup-frames.sh` script handles this by:
1. Copying the last frame to a temporary file
2. Removing the frame directory
3. Moving the temporary file to the final location

**Manual Fix:**
```bash
cd docs/commands/img
for dir in */; do
    if ls "${dir}"frame-text-*.png > /dev/null 2>&1; then
        last_frame=$(ls "${dir}"frame-text-*.png | sort | tail -1)
        temp_file=".temp-${dir}.$$"
        cp "$last_frame" "$temp_file"
        rm -rf "$dir"
        mv "$temp_file" "${dir%/}"
    fi
done
```

### 2. Missing VHS Binary

**Problem:** VHS is not installed or not in PATH.

**Symptoms:**
```bash
vhs: command not found
```

**Solution:**
```bash
# Install VHS using the automated installer
make vhs-deps-install

# This will:
# - Check if VHS is already installed
# - Download and install VHS v0.10.0 (or latest if GitHub API is available)
# - Install to docs/screencasts/bin/vhs
# - Works even when GitHub API is blocked

# Or manually:
go install github.com/charmbracelet/vhs@latest
# Or download from: https://github.com/charmbracelet/vhs/releases
```

**Note:** The automated installer has a fallback mechanism that uses version v0.10.0 if the GitHub API is unavailable or blocked. This ensures installation works in restricted environments.

### 3. Missing System Dependencies

**Problem:** VHS requires `ffmpeg` and optionally `ttyd` for recording terminal sessions.

**Symptoms:**
- Error messages about missing ffmpeg
- Recording fails or produces empty/corrupt files

**Solution:**
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y ffmpeg ttyd

# macOS
brew install ffmpeg ttyd

# Check installation
ffmpeg -version
ttyd --version
```

### 4. Demo Repository Not Found

**Problem:** VHS tapes reference `/tmp/demo-repo` but it doesn't exist.

**Symptoms:**
- Commands fail with "directory not found"
- Empty or incomplete screenshots

**Solution:**
```bash
# Create demo repository
make demo-repo

# Or for CI/quick testing:
make demo-repo-simple
```

### 5. Stale Frame Directories

**Problem:** Previous VHS runs left frame directories that weren't cleaned up.

**Symptoms:**
- Extra directories with `.png` or `.gif` extensions
- Inconsistent output files

**Solution:**
```bash
# Run cleanup script
bash docs/screencasts/bin/vhs-cleanup-frames.sh docs/commands/img

# Or clean everything and rebuild
make vhs-clean
make vhs
```

## Workflow Issues

### CI/CD Failures

**Problem:** The `regenerate-vhs-images.yml` workflow fails.

**Debugging Steps:**

1. **Check workflow logs:**
   - Go to Actions tab in GitHub
   - Click on the failed workflow run
   - Review logs for each step

2. **Common CI-specific issues:**
   - **VHS installation fails:** Check if download URL is still valid
   - **Permission denied:** Check if binary is marked executable
   - **Timeout:** VHS image generation takes time; consider increasing timeout

3. **Test locally:**
   ```bash
   # Simulate CI environment
   make install
   make demo-repo-simple
   source bin/activate
   make vhs-regenerate
   ```

4. **Manual workflow trigger:**
   - Go to Actions → Regenerate VHS Documentation Images
   - Click "Run workflow"
   - Select branch and run

### Performance Issues

**Problem:** VHS image generation is slow.

**Solutions:**

1. **Optimize tape files:**
   - Reduce unnecessary `Sleep` commands
   - Use shorter recordings when possible
   - Remove `Hide`/`Show` cycles that aren't needed

2. **Generate only essential images:**
   ```bash
   # Instead of:
   make vhs  # Builds all
   
   # Use:
   make vhs-build-one TAPE=specific-file.tape
   ```

3. **Parallel builds (if GNU parallel installed):**
   ```bash
   bash docs/screencasts/bin/vhs-build.sh --parallel --all
   ```

## Output Quality Issues

### Blurry or Low-Quality Images

**Problem:** Generated images don't look crisp.

**Solution:** Check tape file settings:
```tape
Set Width 1020
Set Height 280
Set FontSize 13
Set Theme "Afterglow"
```

Ensure these are consistent across all tape files.

### Incorrect Terminal Size

**Problem:** Output is cut off or has wrong dimensions.

**Solution:** Adjust `Width` and `Height` in tape file to match content:
- Short status output: 280px height
- Multi-line logs: 400-600px height
- Full workflows: 600-800px height

### Color/Theme Issues

**Problem:** Colors don't match documentation style.

**Solution:** Use consistent theme:
```tape
Set Theme "Afterglow"
```

Available themes: Run `vhs themes` to see all options.

## Debugging Tips

### Using GitHub Copilot Devcontainer

**Problem:** Setting up the development environment is complex or time-consuming.

**Solution:** Use the pre-configured GitHub Copilot devcontainer:

1. **In GitHub Codespaces:**
   - Open the repository in GitHub
   - Click "Code" → "Codespaces" → "Create codespace on main"
   - The environment will automatically set up with all dependencies

2. **In VS Code with Dev Containers:**
   - Install the "Dev Containers" extension
   - Open the repository
   - Run "Dev Containers: Reopen in Container"
   - All dependencies will be installed automatically

**What's included:**
- Pre-configured Ubuntu environment
- Git, Node.js, and npm
- System dependencies (ffmpeg, ttyd, fish, shellcheck, bats)
- Hug SCM installed and activated
- VHS installed for documentation generation
- Test dependencies ready to use
- Documentation dependencies installed

**Quick start after opening devcontainer:**
```bash
# Already activated! Just use Hug
hug help

# Run tests
make test

# Build VHS images
make vhs

# Start documentation server
npm run docs:dev
```

### Enable Verbose Output

```bash
# Run vhs-build.sh with trace
bash -x docs/screencasts/bin/vhs-build.sh hug-l.tape

# Run cleanup with trace
bash -x docs/screencasts/bin/vhs-cleanup-frames.sh docs/commands/img
```

### Check VHS Version

```bash
vhs --version

# Update to latest if needed
go install github.com/charmbracelet/vhs@latest
```

### Validate Tape File Syntax

```bash
# VHS will show syntax errors
vhs validate docs/screencasts/hug-l.tape
```

### Manual Testing

Test individual tape files manually:
```bash
cd docs/screencasts
vhs hug-l.tape
ls -la ../commands/img/hug-l.*
```

## Prevention

### Best Practices

1. **Always run cleanup after VHS:**
   ```bash
   make vhs-regenerate  # Already includes cleanup
   ```

2. **Use consistent naming:**
   - Tape files: `hug-<command>.tape`
   - Output files: `hug-<command>.{png|gif}`

3. **Test locally before committing:**
   ```bash
   make demo-repo-simple
   make vhs-build-one TAPE=your-new-tape.tape
   # Verify output looks correct
   ```

4. **Keep tape files simple:**
   - One primary action per tape
   - Clear Hide/Show boundaries
   - Minimal Sleep times

### Pre-commit Checklist

Before committing VHS-related changes:

- [ ] Tested tape file locally
- [ ] Output image looks correct
- [ ] No frame directories left behind
- [ ] Image is committed to git (if using committed screenshots approach)
- [ ] Documentation references correct image path
- [ ] Image dimensions are appropriate

## Getting Help

If you encounter issues not covered here:

1. **Check existing documentation:**
   - `docs/screencasts/README.md` - Creating and managing tapes
   - `IMPLEMENTATION_NOTES_VHS.md` - Implementation details
   - `docs/VHS_CI_INTEGRATION.md` - CI/CD integration

2. **Review VHS documentation:**
   - [VHS GitHub](https://github.com/charmbracelet/vhs)
   - [VHS Documentation](https://github.com/charmbracelet/vhs#vhs)

3. **Check for related issues:**
   - Search GitHub issues for similar problems
   - Look at closed issues for solutions

4. **File a new issue:**
   - Include error messages
   - Describe steps to reproduce
   - Mention your environment (OS, VHS version, etc.)
