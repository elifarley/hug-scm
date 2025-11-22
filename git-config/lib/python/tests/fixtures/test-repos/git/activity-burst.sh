#!/usr/bin/env bash
# Setup script: Activity analysis test repository with burst pattern
# Creates commits with burst activity pattern (11 commits in one hour on Friday)

set -euo pipefail

# Initialize git repo
git init
git config user.name "Test User"
git config user.email "test@example.com"

# Create burst of commits on Friday 2025-01-17 at hour 9
# Note: No initial commit on another day - all commits on Friday
# Total: 11 commits, 6 from Alice Smith

git config user.name "Alice Smith"
echo "Alice commit 1" > file.py
git add file.py
GIT_AUTHOR_DATE="2025-01-17 09:00:00 -0500" \
GIT_COMMITTER_DATE="2025-01-17 09:00:00 -0500" \
git commit -m "Alice commit 1"

git config user.name "Alice Smith"
echo "Alice commit 2" >> file.py
git add file.py
GIT_AUTHOR_DATE="2025-01-17 09:01:00 -0500" \
GIT_COMMITTER_DATE="2025-01-17 09:01:00 -0500" \
git commit -m "Alice commit 2"

git config user.name "Carol Williams"
echo "Carol commit 1" >> file.py
git add file.py
GIT_AUTHOR_DATE="2025-01-17 09:02:00 -0500" \
GIT_COMMITTER_DATE="2025-01-17 09:02:00 -0500" \
git commit -m "Carol commit 1"

git config user.name "Bob Johnson"
echo "Bob commit 1" >> file.py
git add file.py
GIT_AUTHOR_DATE="2025-01-17 09:03:00 -0500" \
GIT_COMMITTER_DATE="2025-01-17 09:03:00 -0500" \
git commit -m "Bob commit 1"

git config user.name "Alice Smith"
echo "Alice commit 3" >> file.py
git add file.py
GIT_AUTHOR_DATE="2025-01-17 09:05:00 -0500" \
GIT_COMMITTER_DATE="2025-01-17 09:05:00 -0500" \
git commit -m "Alice commit 3"

git config user.name "Alice Smith"
echo "Alice commit 4" >> file.py
git add file.py
GIT_AUTHOR_DATE="2025-01-17 09:10:00 -0500" \
GIT_COMMITTER_DATE="2025-01-17 09:10:00 -0500" \
git commit -m "Alice commit 4"

git config user.name "Bob Johnson"
echo "Bob commit 2" >> file.py
git add file.py
GIT_AUTHOR_DATE="2025-01-17 09:15:00 -0500" \
GIT_COMMITTER_DATE="2025-01-17 09:15:00 -0500" \
git commit -m "Bob commit 2"

git config user.name "Carol Williams"
echo "Carol commit 2" >> file.py
git add file.py
GIT_AUTHOR_DATE="2025-01-17 09:25:00 -0500" \
GIT_COMMITTER_DATE="2025-01-17 09:25:00 -0500" \
git commit -m "Carol commit 2"

git config user.name "Alice Smith"
echo "Alice commit 5" >> file.py
git add file.py
GIT_AUTHOR_DATE="2025-01-17 09:35:00 -0500" \
GIT_COMMITTER_DATE="2025-01-17 09:35:00 -0500" \
git commit -m "Alice commit 5"

git config user.name "Bob Johnson"
echo "Bob commit 3" >> file.py
git add file.py
GIT_AUTHOR_DATE="2025-01-17 09:45:00 -0500" \
GIT_COMMITTER_DATE="2025-01-17 09:45:00 -0500" \
git commit -m "Bob commit 3"

git config user.name "Alice Smith"
echo "Alice commit 6" >> file.py
git add file.py
GIT_AUTHOR_DATE="2025-01-17 09:55:00 -0500" \
GIT_COMMITTER_DATE="2025-01-17 09:55:00 -0500" \
git commit -m "Alice commit 6"

echo "✓ Created activity burst test repo with 11 commits (6 from Alice, 3 from Bob, 2 from Carol, all on Friday hour 9)"
