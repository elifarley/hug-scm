# Documentation Images

This directory contains images generated from VHS tape files for the Hug SCM documentation.

## Contents

- `hug-*.png` - Screenshot images of Hug commands
- `hug-*.gif` - Animated demonstrations of Hug commands

## Generation

These images are generated from VHS tape files located in `docs/screencasts/`.

To regenerate images:
```bash
# Install VHS first
make vhs-deps-install

# Create demo repository
make demo-repo

# Generate all images
make vhs
```

## Maintenance

Images are automatically regenerated monthly via the GitHub Actions workflow `.github/workflows/regenerate-vhs-images.yml`.

You can also manually trigger regeneration:
- Go to Actions tab in GitHub
- Select "Regenerate VHS Documentation Images" workflow
- Click "Run workflow"

## Important Notes

- These images **are committed to git** (not in .gitignore)
- This ensures fast CI builds without requiring VHS
- The `make vhs-clean` target removes these images (use with caution)
- Images are regenerated from scratch when running `make vhs`
