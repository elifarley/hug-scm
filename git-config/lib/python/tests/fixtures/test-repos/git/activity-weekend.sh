#!/usr/bin/env bash
# Setup script: Activity analysis test repository with weekend work
# Creates 8 commits total, 3 on weekend (Sat/Sun)

set -euo pipefail

# Initialize git repo
git init
git config user.name "Test User"
git config user.email "test@example.com"

# Create 8 commits: 5 weekday, 3 weekend (Sat x2, Sun x1)
# Monday 2025-01-13
git config user.name "Bob Johnson"
echo "Monday" > file.py
git add file.py
GIT_AUTHOR_DATE="2025-01-13 17:30:00 -0500" \
  GIT_COMMITTER_DATE="2025-01-13 17:30:00 -0500" \
  git commit -m "Monday commit"

# Tuesday 2025-01-14
git config user.name "Carol Williams"
echo "Tuesday" >> file.py
git add file.py
GIT_AUTHOR_DATE="2025-01-14 09:00:00 -0500" \
  GIT_COMMITTER_DATE="2025-01-14 09:00:00 -0500" \
  git commit -m "Tuesday commit"

# Wednesday 2025-01-15 (3 commits)
git config user.name "Alice Smith"
echo "Wednesday 1" >> file.py
git add file.py
GIT_AUTHOR_DATE="2025-01-15 12:30:05 -0500" \
  GIT_COMMITTER_DATE="2025-01-15 12:30:05 -0500" \
  git commit -m "Wednesday commit 1"

git config user.name "Bob Johnson"
echo "Wednesday 2" >> file.py
git add file.py
GIT_AUTHOR_DATE="2025-01-15 13:45:22 -0500" \
  GIT_COMMITTER_DATE="2025-01-15 13:45:22 -0500" \
  git commit -m "Wednesday commit 2"

git config user.name "Alice Smith"
echo "Wednesday 3" >> file.py
git add file.py
GIT_AUTHOR_DATE="2025-01-15 14:23:10 -0500" \
  GIT_COMMITTER_DATE="2025-01-15 14:23:10 -0500" \
  git commit -m "Wednesday commit 3"

# Friday 2025-01-17
git config user.name "Alice Smith"
echo "Friday" >> file.py
git add file.py
GIT_AUTHOR_DATE="2025-01-17 16:45:00 -0500" \
  GIT_COMMITTER_DATE="2025-01-17 16:45:00 -0500" \
  git commit -m "Friday commit"

# Saturday 2025-01-18 (weekend)
git config user.name "Bob Johnson"
echo "Saturday 1" >> file.py
git add file.py
GIT_AUTHOR_DATE="2025-01-18 14:20:00 -0500" \
  GIT_COMMITTER_DATE="2025-01-18 14:20:00 -0500" \
  git commit -m "Saturday commit"

# Saturday 2025-01-18 (weekend)
git config user.name "Alice Smith"
echo "Saturday 2" >> file.py
git add file.py
GIT_AUTHOR_DATE="2025-01-18 15:30:00 -0500" \
  GIT_COMMITTER_DATE="2025-01-18 15:30:00 -0500" \
  git commit -m "Saturday commit 2"

# Sunday 2025-01-19 (weekend)
git config user.name "Bob Johnson"
echo "Sunday" >> file.py
git add file.py
GIT_AUTHOR_DATE="2025-01-19 10:00:00 -0500" \
  GIT_COMMITTER_DATE="2025-01-19 10:00:00 -0500" \
  git commit -m "Sunday commit"

echo "✓ Created activity weekend test repo with 8 commits (3 on weekend: 2 Sat, 1 Sun)"
