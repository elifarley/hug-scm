#!/usr/bin/env bash
# Setup script: Test repository for churn analysis with --since filter
# Creates a file with commits spanning multiple months for date filtering tests

set -euo pipefail

# Initialize git repo
git init
git config user.name "Alice Smith"
git config user.email "alice@example.com"

# Create initial file
cat > project.py <<EOF
def main():
    pass

if __name__ == "__main__":
    main()
EOF

git add project.py
GIT_AUTHOR_DATE="2024-01-01 09:00:00 -0500" \
GIT_COMMITTER_DATE="2024-01-01 09:00:00 -0500" \
git commit -m "Initial version"

# Old commit (should be filtered out by --since="2 months ago")
sed -i 's/pass/print("v1")/' project.py
git add project.py
GIT_AUTHOR_DATE="2024-06-01 10:00:00 -0500" \
GIT_COMMITTER_DATE="2024-06-01 10:00:00 -0500" \
git commit -m "Add v1 functionality"

# Recent commit 1 (within 2 months)
sed -i 's/print("v1")/print("v2")/' project.py
git add project.py
GIT_AUTHOR_DATE="2024-10-01 11:00:00 -0500" \
GIT_COMMITTER_DATE="2024-10-01 11:00:00 -0500" \
git commit -m "Update to v2"

# Recent commit 2 (within 2 months)
git config user.name "Bob Johnson"
git config user.email "bob@example.com"
sed -i 's/print("v2")/print("v3")/' project.py
git add project.py
GIT_AUTHOR_DATE="2024-11-01 12:00:00 -0500" \
GIT_COMMITTER_DATE="2024-11-01 12:00:00 -0500" \
git commit -m "Update to v3"

# Very recent commit (within 1 week)
sed -i 's/print("v3")/print("v4")/' project.py
git add project.py
GIT_AUTHOR_DATE="2024-11-15 13:00:00 -0500" \
GIT_COMMITTER_DATE="2024-11-15 13:00:00 -0500" \
git commit -m "Update to v4"

echo "✓ Created churn test repo with 5 commits spanning multiple months"
