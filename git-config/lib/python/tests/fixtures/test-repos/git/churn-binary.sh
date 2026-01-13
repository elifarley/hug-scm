#!/usr/bin/env bash
# Setup script: Test repository with binary file for error handling tests
# Creates both text and binary files to test binary file detection

set -euo pipefail

# Initialize git repo
git init
git config user.name "Test User"
git config user.email "test@example.com"

# Create text file
echo "Normal text file" > text.txt
git add text.txt
GIT_AUTHOR_DATE="2024-01-01 10:00:00 -0500" \
  GIT_COMMITTER_DATE="2024-01-01 10:00:00 -0500" \
  git commit -m "Add text file"

# Create binary file (PNG-like header)
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR' > image.png
git add image.png
GIT_AUTHOR_DATE="2024-01-02 11:00:00 -0500" \
  GIT_COMMITTER_DATE="2024-01-02 11:00:00 -0500" \
  git commit -m "Add binary file"

# Modify binary file
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00' > image.png
git add image.png
GIT_AUTHOR_DATE="2024-01-03 12:00:00 -0500" \
  GIT_COMMITTER_DATE="2024-01-03 12:00:00 -0500" \
  git commit -m "Update binary file"

echo "✓ Created binary file test repo with 3 commits"
