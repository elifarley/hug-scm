# Screenshot Generation Instructions

This document explains how to generate the actual PNG screenshots from the VHS tape files that have been created.

## Current Status

✅ **Completed:**
- Created 21 new VHS tape files for various commands
- Updated documentation files (logging.md, branching.md, file-inspection.md, working-dir.md, head.md) with screenshot references
- Fixed build error in hug-for-beginners.md
- Created placeholder PNG images so documentation builds successfully
- Updated screencasts/README.md with complete list of tape files

⚠️ **Pending:**
- Generate actual PNG screenshots from tape files using VHS

## New Tape Files Created

### Logging Commands (8 files)
- `hug-la.tape` - Log all branches
- `hug-lla.tape` - Detailed log all branches
- `hug-lp.tape` - Log with patches
- `hug-lf.tape` - Log message filter
- `hug-lc.tape` - Log code search
- `hug-lau.tape` - Log by author
- `hug-ld.tape` - Log by date
- `hug-llf.tape` - Log file history

### Branching Commands (4 files)
- `hug-bl.tape` - List local branches
- `hug-bla.tape` - List all branches
- `hug-blr.tape` - List remote branches
- `hug-bll.tape` - Detailed branch list

### File Inspection Commands (4 files)
- `hug-fblame.tape` - File blame
- `hug-fcon.tape` - File contributors
- `hug-fa.tape` - File authors
- `hug-fborn.tape` - File origin

### Working Directory Commands (2 files)
- `hug-w-discard.tape` - Discard changes
- `hug-w-purge.tape` - Purge untracked files

### HEAD Operations Commands (3 files)
- `hug-h-back.tape` - Move HEAD back
- `hug-h-undo.tape` - Undo commit
- `hug-h-files.tape` - Preview files

## How to Generate Screenshots

### Prerequisites

1. **Install VHS** (Video Handshake tool)
   ```bash
   # macOS
   brew install vhs
   
   # Linux
   go install github.com/charmbracelet/vhs@latest
   ```

2. **Verify Hug is installed and activated**
   ```bash
   make install
   source bin/activate
   hug help  # Should show help output
   ```

3. **Create demo repository**
   ```bash
   make demo-repo
   # or if it exists already:
   make demo-repo-rebuild
   ```

### Generate All Screenshots

To generate PNG screenshots for all tape files:

```bash
make vhs
```

This will:
1. Process all `.tape` files in `docs/screencasts/`
2. Generate PNG images in `docs/commands/img/`
3. Replace the placeholder images with actual terminal screenshots

### Generate Specific Screenshots

To generate a single screenshot:

```bash
make vhs-build-one TAPE=hug-la.tape
```

Or to build multiple specific files:

```bash
cd docs/screencasts
vhs hug-la.tape
vhs hug-ll.tape
vhs hug-lp.tape
```

### Verify Generated Images

After generating, check the images:

```bash
ls -lh docs/commands/img/*.png
```

The placeholder images are very small (67 bytes each). Real VHS-generated screenshots will be much larger (typically 20-100 KB depending on terminal content).

### Commit Generated Images

Once screenshots are generated:

```bash
git add docs/commands/img/*.png
git commit -m "Generate actual screenshots from VHS tape files"
git push
```

## Troubleshooting

### VHS Not Found
```bash
make vhs-check  # Verify VHS installation
```

### Demo Repository Issues
```bash
make demo-repo-rebuild  # Recreate demo repository
```

### Tape File Errors
If a specific tape file fails, you can:
1. Run it directly to see the error: `vhs docs/screencasts/hug-la.tape`
2. Check the tape file syntax
3. Verify the command works manually: `hug la -5`

## Documentation References

- VHS Documentation: https://github.com/charmbracelet/vhs
- Hug Screencasts README: `docs/screencasts/README.md`
- Placeholder note: `docs/commands/img/PLACEHOLDER_NOTE.md`

## Testing

After generating screenshots, verify the documentation builds and displays images correctly:

```bash
# Build documentation
npm run docs:build

# Preview documentation locally
npm run docs:dev
# Then open http://localhost:5173 in a browser
```

Navigate to the command reference pages and verify that screenshots display properly:
- http://localhost:5173/commands/logging.html
- http://localhost:5173/commands/branching.html
- http://localhost:5173/commands/file-inspection.html
- http://localhost:5173/commands/working-dir.html
- http://localhost:5173/commands/head.html
