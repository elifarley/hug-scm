#!/usr/bin/env bash
# Setup script: Search test repository with commits containing "fix" and "def calculate"
# Creates commits for testing git log --grep and git log -G

set -euo pipefail

# Initialize git repo
git init
git config user.name "Test User"
git config user.email "test@example.com"

# Create initial file
cat > calculator.py << EOF
def add(a, b):
    return a + b

def subtract(a, b):
    return a - b
EOF

git add calculator.py
GIT_AUTHOR_DATE="2025-01-10 08:00:00 -0500" \
  GIT_COMMITTER_DATE="2025-01-10 08:00:00 -0500" \
  git commit -m "Initial commit"

# Commit 1: Add calculate function (for -G search)
git config user.name "Bob Johnson"
git config user.email "bob@example.com"
cat >> calculator.py << EOF

def calculate(values):
    return sum(values) / len(values)
EOF

git add calculator.py
GIT_AUTHOR_DATE="2025-01-14 10:20:00 -0500" \
  GIT_COMMITTER_DATE="2025-01-14 10:20:00 -0500" \
  git commit -m "feat: add calculate function for metrics

Added def calculate() to handle statistical calculations."

# Commit 2: Improve calculate function (for -G search)
git config user.name "Alice Smith"
git config user.email "alice@example.com"
sed -i 's/def calculate(values)/def calculate(values, use_cache=True)/' calculator.py

git add calculator.py
GIT_AUTHOR_DATE="2025-01-12 16:45:00 -0500" \
  GIT_COMMITTER_DATE="2025-01-12 16:45:00 -0500" \
  git commit -m "refactor: improve calculate performance

Optimized def calculate() with memoization."

# Commit 3: Fix memory leak (for --grep search)
git config user.name "Carol Williams"
git config user.email "carol@example.com"
git config user.name "Alice Smith"
cat > cache.py << EOF
# Cache implementation
cache = {}

def cleanup():
    global cache
    cache.clear()
EOF

git add cache.py
GIT_AUTHOR_DATE="2025-01-13 16:45:00 -0500" \
  GIT_COMMITTER_DATE="2025-01-13 16:50:00 -0500" \
  git commit -m "fix: memory leak in cache cleanup

Fixed memory leak by ensuring proper cleanup of cache entries."

# Commit 4: Fix validation (for --grep search)
git config user.name "Bob Johnson"
git config user.email "bob@example.com"
cat > validator.py << EOF
def validate_form(data):
    if not data:
        return False
    return True
EOF

git add validator.py
GIT_AUTHOR_DATE="2025-01-14 11:20:00 -0500" \
  GIT_COMMITTER_DATE="2025-01-14 11:20:00 -0500" \
  git commit -m "fix: correct validation logic in form submission

Fixed form validation to handle edge cases properly."

# Commit 5: Fix NPE (for --grep search)
git config user.name "Alice Smith"
git config user.email "alice@example.com"
git config user.name "Carol Williams"
git config user.email "carol@example.com"
cat > user_service.py << EOF
def get_user(user_id):
    user = fetch_user(user_id)
    if user is None:
        return {"error": "User not found"}
    return user
EOF

git add user_service.py
GIT_AUTHOR_DATE="2025-01-15 14:30:00 -0500" \
  GIT_COMMITTER_DATE="2025-01-15 14:35:00 -0500" \
  git commit -m "fix: resolve null pointer exception in user service

Fixed NPE when user object is null by adding proper validation."

# Commit 6: Feature with files (for --name-status search)
git config user.name "Alice Smith"
git config user.email "alice@example.com"
mkdir -p src/auth
cat > src/auth/login.py << EOF
def login(username, password):
    return authenticate(username, password)
EOF

cat > src/auth/logout.py << EOF
def logout(session_id):
    clear_session(session_id)
EOF

cat > src/auth/jwt_utils.py << EOF
import jwt

def create_token(payload):
    return jwt.encode(payload, SECRET_KEY)
EOF

git add src/auth/
GIT_AUTHOR_DATE="2025-01-16 09:30:00 -0500" \
  GIT_COMMITTER_DATE="2025-01-16 09:30:00 -0500" \
  git commit -m "feat: add user authentication feature

Implemented JWT-based authentication system with login and logout."

# Commit 7: Another feature with files (for --name-status search)
git config user.name "Bob Johnson"
git config user.email "bob@example.com"
mkdir -p src/pages src/components src/api
cat > src/pages/profile.tsx << EOF
export function ProfilePage() {
    return <div>Profile</div>;
}
EOF

cat > src/components/ProfileForm.tsx << EOF
export function ProfileForm() {
    return <form>Profile Form</form>;
}
EOF

cat > src/api/profile.ts << EOF
export async function getProfile(userId: string) {
    return fetch(\`/api/profile/\${userId}\`);
}
EOF

git add src/pages/ src/components/ src/api/
GIT_AUTHOR_DATE="2025-01-14 15:20:00 -0500" \
  GIT_COMMITTER_DATE="2025-01-14 15:20:00 -0500" \
  git commit -m "feat: implement user profile feature

Added user profile page with edit capabilities."

echo "✓ Created search test repo with 7 commits (3 with 'fix', 2 with 'def calculate', 2 with 'feat' and files)"
