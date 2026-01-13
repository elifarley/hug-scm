#!/usr/bin/env bash
# Setup script: Basic test repository for churn analysis
# Creates a simple file with multiple commits over time

set -euo pipefail

# Initialize git repo
git init
git config user.name "Test User"
git config user.email "test@example.com"

# Create initial file with 5 lines
cat > file.txt << EOF
line 1
line 2
line 3
line 4
line 5
EOF

git add file.txt
GIT_AUTHOR_DATE="2024-01-01 10:00:00 -0500" \
  GIT_COMMITTER_DATE="2024-01-01 10:00:00 -0500" \
  git commit -m "Initial commit"

# Modify line 2
sed -i 's/line 2/line 2 modified/' file.txt
git add file.txt
GIT_AUTHOR_DATE="2024-02-01 11:00:00 -0500" \
  GIT_COMMITTER_DATE="2024-02-01 11:00:00 -0500" \
  git commit -m "Modify line 2"

# Modify line 2 again (high churn line)
sed -i 's/line 2 modified/line 2 modified again/' file.txt
git add file.txt
GIT_AUTHOR_DATE="2024-03-01 12:00:00 -0500" \
  GIT_COMMITTER_DATE="2024-03-01 12:00:00 -0500" \
  git commit -m "Modify line 2 again"

# Modify line 4
sed -i 's/line 4/line 4 modified/' file.txt
git add file.txt
GIT_AUTHOR_DATE="2024-04-01 13:00:00 -0500" \
  GIT_COMMITTER_DATE="2024-04-01 13:00:00 -0500" \
  git commit -m "Modify line 4"

echo "✓ Created basic churn test repo with 4 commits"
