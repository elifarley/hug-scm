#!/usr/bin/env bash
CMD_BASE="$(readlink -f "$0" 2>/dev/null || greadlink -f "$0")" || CMD_BASE="$0"; CMD_BASE="$(dirname "$CMD_BASE")"

#==============================================================================
# A script to create a hug repository for tutorials with multiple contributors.
# Creates 15+ branches, 4 contributors, and 70+ commits for comprehensive demos.
#==============================================================================

# --- Contributor Definitions ---
readonly AUTHOR_ONE_NAME="Alice Smith"
readonly AUTHOR_ONE_EMAIL="alice.smith@example.com"
readonly AUTHOR_TWO_NAME="Bob Johnson"
readonly AUTHOR_TWO_EMAIL="bob.johnson@example.com"
readonly AUTHOR_THREE_NAME="Carol Martinez"
readonly AUTHOR_THREE_EMAIL="carol.martinez@example.com"
readonly AUTHOR_FOUR_NAME="David Lee"
readonly AUTHOR_FOUR_EMAIL="david.lee@example.com"

# --- Helper Functions ---

# Executes a hug command as a specific author.
# Usage: as_author "Author Name" "author@email.com" "hug c -m 'message'"
as_author() {
    local author_name="$1"; shift
    local author_email="$2"; shift

    GIT_AUTHOR_NAME="$author_name" GIT_AUTHOR_EMAIL="$author_email" \
    GIT_COMMITTER_NAME="$author_name" GIT_COMMITTER_EMAIL="$author_email" \
    hug "$@"
}

# --- Repository Creation Functions ---

# Creates the directory and initializes the git repository.
setup_repo() {
    cd /tmp
    echo "1. Initializing repository..."
    mkdir -p demo-repo
    rm -rf demo-repo/* demo-repo/.git
    cd demo-repo
    git init -b main
}

# Creates the initial commits on the main branch.
create_main_commits() {
    echo "2. Creating initial commits on main branch..."
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c --allow-empty -m "Initial commit"

    echo "# Demo Application" > README.md
    echo "This is a demo repository for Hug SCM tutorials." >> README.md
    hug a README.md
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "docs: Add README file"

    echo "console.log('hello world');" > app.js
    hug a app.js
    as_author "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "feat: Add main application file"

    echo "node_modules/" > .gitignore
    echo ".env" >> .gitignore
    echo "dist/" >> .gitignore
    hug a .gitignore
    as_author "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "chore: Add gitignore file"

    mkdir -p src tests
    echo "// Main entry point" > src/index.js
    hug a src/index.js
    as_author "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "refactor: Move app to src directory"
}

# Creates feature branches with multiple commits.
create_feature_branches() {
    echo "3. Creating feature branches..."
    
    # Feature 1: User Authentication (merged)
    hug bc feature/user-auth
    echo "// User authentication module" > src/auth.js
    hug a src/auth.js
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "feat: Add authentication module"
    
    echo "export function login(user, pass) { /* ... */ }" >> src/auth.js
    hug a src/auth.js
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "feat: Implement login function"
    
    echo "export function logout() { /* ... */ }" >> src/auth.js
    hug a src/auth.js
    as_author "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "feat: Add logout functionality"
    
    hug checkout main
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        mkeep feature/user-auth -m "Merge branch 'feature/user-auth'"
    
    # Feature 2: User Profile (unmerged, active)
    hug bc feature/user-profile
    echo "<h1>User Profile</h1>" > src/profile.html
    hug a src/profile.html
    as_author "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "feat: Add basic HTML for user profile"

    echo "body { font-family: sans-serif; }" > src/styles.css
    hug a src/styles.css
    as_author "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "style: Add basic styling for profile page"

    echo "// Profile data handling" > src/profile.js
    hug a src/profile.js
    as_author "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "feat: Add profile data handler"
    
    # Feature 3: Dashboard (unmerged, active)
    hug bc feature/dashboard
    mkdir -p src/components
    echo "// Dashboard component" > src/components/Dashboard.js
    hug a src/components/Dashboard.js
    as_author "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "feat: Create dashboard component"
    
    echo "// Widget system" > src/components/Widget.js
    hug a src/components/Widget.js
    as_author "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "feat: Add widget system to dashboard"
    
    # Feature 4: API Integration (merged)
    hug bc feature/api-integration
    echo "// API client" > src/api.js
    hug a src/api.js
    as_author "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "feat: Add API client module"
    
    echo "export async function fetchData(endpoint) { /* ... */ }" >> src/api.js
    hug a src/api.js
    as_author "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "feat: Implement data fetching"
    
    echo "export function handleError(err) { /* ... */ }" >> src/api.js
    hug a src/api.js
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "feat: Add error handling to API"
    
    hug checkout main
    as_author "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        mkeep feature/api-integration -m "Merge branch 'feature/api-integration'"
    
    # Feature 5: Search Functionality (unmerged)
    hug bc feature/search
    echo "// Search implementation" > src/search.js
    hug a src/search.js
    as_author "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "feat: Add search functionality"
    
    echo "export function searchUsers(query) { /* ... */ }" >> src/search.js
    hug a src/search.js
    as_author "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "feat: Implement user search"
}

# Creates bugfix branches.
create_bugfix_branches() {
    echo "4. Creating bugfix branches..."
    
    hug b main
    
    # Bugfix 1: Login validation (merged)
    hug bc bugfix/login-validation
    echo "// Fixed: validate email format" >> src/auth.js
    hug a src/auth.js
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "fix: Add email validation to login"
    
    hug checkout main
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        mkeep bugfix/login-validation -m "Merge branch 'bugfix/login-validation'"
    
    # Bugfix 2: Memory leak (merged)
    hug bc bugfix/memory-leak
    echo "// Fixed: clear event listeners" >> src/components/Dashboard.js
    hug a src/components/Dashboard.js
    as_author "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "fix: Fix memory leak in dashboard"
    
    echo "// Add cleanup function" >> src/components/Dashboard.js
    hug a src/components/Dashboard.js
    as_author "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "fix: Add proper cleanup on unmount"
    
    hug checkout main
    as_author "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        mkeep bugfix/memory-leak -m "Merge branch 'bugfix/memory-leak'"
    
    # Bugfix 3: API timeout (unmerged, being worked on)
    hug bc bugfix/api-timeout
    echo "// TODO: implement retry logic" >> src/api.js
    hug a src/api.js
    as_author "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "fix: Add timeout handling to API calls"
    
    # Bugfix 4: CSS styling issue (unmerged)
    hug bc bugfix/css-layout
    echo "/* Fix responsive layout */" >> src/styles.css
    hug a src/styles.css
    as_author "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "fix: Fix layout issues on mobile"
}

# Creates hotfix branches for production issues.
create_hotfix_branches() {
    echo "5. Creating hotfix branches..."
    
    hug b main
    
    # Hotfix 1: Critical security patch (merged)
    hug bc hotfix/security-patch
    echo "// Security: sanitize user input" >> src/auth.js
    hug a src/auth.js
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "hotfix: Add input sanitization"
    
    hug checkout main
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        mkeep hotfix/security-patch -m "Merge branch 'hotfix/security-patch'"
    
    # Hotfix 2: Production crash (merged)
    hug bc hotfix/prod-crash
    echo "// Add null check" >> src/components/Widget.js
    hug a src/components/Widget.js
    as_author "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "hotfix: Fix null pointer crash"
    
    hug checkout main
    as_author "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        mkeep hotfix/prod-crash -m "Merge branch 'hotfix/prod-crash'"
}

# Creates experimental/research branches.
create_experimental_branches() {
    echo "6. Creating experimental branches..."
    
    hug b main
    
    # Experimental 1: New architecture
    hug bc experimental/new-arch
    echo "// Exploring new architecture pattern" > src/experimental.js
    hug a src/experimental.js
    as_author "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "experiment: Try new architecture pattern"
    
    echo "// Continue exploration" >> src/experimental.js
    hug a src/experimental.js
    as_author "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "experiment: Test performance improvements"
    
    # Experimental 2: AI integration
    hug bc experimental/ai-integration
    echo "// AI-powered features" > src/ai.js
    hug a src/ai.js
    as_author "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "experiment: Add AI integration prototype"
}

# Creates release branches.
create_release_branches() {
    echo "7. Creating release branches..."
    
    hug b main
    
    # Release 1: v1.0 (merged)
    hug bc release/v1.0
    echo '{"version": "1.0.0"}' > package.json
    hug a package.json
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "release: Prepare v1.0.0 release"
    
    echo "## Version 1.0.0" > CHANGELOG.md
    echo "- Initial release" >> CHANGELOG.md
    hug a CHANGELOG.md
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "docs: Add changelog for v1.0.0"
    
    hug checkout main
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        mkeep release/v1.0 -m "Merge branch 'release/v1.0'"
    
    # Release 2: v1.1 (in progress)
    hug bc release/v1.1
    echo '{"version": "1.1.0-rc.1"}' > package.json
    hug a package.json
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "release: Bump version to 1.1.0-rc.1"
}

# Add more commits to main branch for realistic history.
add_main_branch_commits() {
    echo "8. Adding more commits to main branch..."
    
    hug b main
    
    # Documentation updates
    echo "## Installation" >> README.md
    echo "\`\`\`bash" >> README.md
    echo "npm install" >> README.md
    echo "\`\`\`" >> README.md
    hug a README.md
    as_author "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "docs: Add installation instructions"
    
    # Testing infrastructure
    echo "// Test helper functions" > tests/helpers.js
    hug a tests/helpers.js
    as_author "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "test: Add test helper utilities"
    
    echo "// Unit tests for auth module" > tests/auth.test.js
    hug a tests/auth.test.js
    as_author "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "test: Add tests for authentication"
    
    echo "// Integration tests" > tests/integration.test.js
    hug a tests/integration.test.js
    as_author "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "test: Add integration tests"
    
    # Configuration files
    echo '{"semi": true, "singleQuote": true}' > .prettierrc
    hug a .prettierrc
    as_author "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "chore: Add prettier configuration"
    
    echo '{"extends": "eslint:recommended"}' > .eslintrc.json
    hug a .eslintrc.json
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "chore: Add ESLint configuration"
    
    # More documentation
    echo "## Contributing" >> README.md
    echo "Pull requests are welcome!" >> README.md
    hug a README.md
    as_author "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "docs: Add contributing section"
    
    echo "# Contributing Guidelines" > CONTRIBUTING.md
    echo "Please follow these guidelines..." >> CONTRIBUTING.md
    hug a CONTRIBUTING.md
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "docs: Add contributing guidelines"
    
    # CI/CD configuration
    mkdir -p .github/workflows
    echo "name: CI" > .github/workflows/test.yml
    hug a .github/workflows/test.yml
    as_author "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "ci: Add GitHub Actions workflow"
    
    # License
    echo "MIT License" > LICENSE
    hug a LICENSE
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "docs: Add MIT license"
}

# Add more realistic development activity with additional commits.
add_development_activity() {
    echo "9. Adding additional development activity..."
    
    # Add more tests
    hug b main
    echo "// Unit tests for API" > tests/api.test.js
    hug a tests/api.test.js
    as_author "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "test: Add API tests"
    
    echo "// End-to-end tests" > tests/e2e.test.js
    hug a tests/e2e.test.js
    as_author "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "test: Add e2e tests"
    
    # More configuration
    echo '{"compilerOptions": {"target": "ES2020"}}' > tsconfig.json
    hug a tsconfig.json
    as_author "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "chore: Add TypeScript configuration"
    
    # Update dependencies
    echo '{"dependencies": {"express": "^4.18.0"}}' >> package.json
    hug a package.json
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "chore: Update dependencies"
    
    # Add API documentation
    mkdir -p docs
    echo "# API Documentation" > docs/API.md
    echo "## Endpoints" >> docs/API.md
    hug a docs/API.md
    as_author "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "docs: Add API documentation"
    
    # Add user guide
    echo "# User Guide" > docs/USER_GUIDE.md
    hug a docs/USER_GUIDE.md
    as_author "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "docs: Add user guide"
    
    # Performance improvements
    echo "// Performance optimization" >> src/api.js
    hug a src/api.js
    as_author "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "perf: Optimize API calls"
    
    # Security updates
    echo "// Security enhancement" >> src/auth.js
    hug a src/auth.js
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "security: Add rate limiting"
    
    # Refactoring
    echo "// Refactored for better maintainability" >> src/index.js
    hug a src/index.js
    as_author "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "refactor: Improve code structure"
    
    # Additional feature commits on branches
    hug b feature/user-profile
    echo "// Profile validation" >> src/profile.js
    hug a src/profile.js
    as_author "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "feat: Add profile validation"
    
    echo "/* Mobile responsive styles */" >> src/styles.css
    hug a src/styles.css
    as_author "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "style: Make profile mobile responsive"
    
    hug b feature/dashboard
    echo "// Dashboard analytics" >> src/components/Dashboard.js
    hug a src/components/Dashboard.js
    as_author "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "feat: Add analytics to dashboard"
    
    echo "// Widget customization" >> src/components/Widget.js
    hug a src/components/Widget.js
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "feat: Add widget customization"
    
    hug b feature/search
    echo "// Advanced search filters" >> src/search.js
    hug a src/search.js
    as_author "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "feat: Add advanced search filters"
    
    echo "// Search result pagination" >> src/search.js
    hug a src/search.js
    as_author "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "feat: Add pagination to search results"
    
    # More bugfix work
    hug b bugfix/api-timeout
    echo "// Implement exponential backoff" >> src/api.js
    hug a src/api.js
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "fix: Implement retry with backoff"
    
    echo "// Add timeout configuration" >> src/api.js
    hug a src/api.js
    as_author "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "fix: Make timeout configurable"
    
    hug b bugfix/css-layout
    echo "/* Fix flexbox issues */" >> src/styles.css
    hug a src/styles.css
    as_author "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "fix: Fix flexbox layout bugs"
    
    echo "/* Add grid layout */" >> src/styles.css
    hug a src/styles.css
    as_author "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "fix: Implement CSS grid for better layout"
    
    # Experimental branches get more work
    hug b experimental/new-arch
    echo "// Modular architecture" >> src/experimental.js
    hug a src/experimental.js
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "experiment: Implement modular architecture"
    
    echo "// Plugin system" >> src/experimental.js
    hug a src/experimental.js
    as_author "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "experiment: Add plugin system"
    
    hug b experimental/ai-integration
    echo "// AI model integration" >> src/ai.js
    hug a src/ai.js
    as_author "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "experiment: Integrate ML model"
    
    echo "// Training pipeline" >> src/ai.js
    hug a src/ai.js
    as_author "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "experiment: Add training pipeline"
    
    # Back to main for final updates
    hug b main
    echo "## Usage" >> README.md
    echo "See docs for details" >> README.md
    hug a README.md
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "docs: Add usage section to README"
    
    echo "## Troubleshooting" >> README.md
    hug a README.md
    as_author "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "docs: Add troubleshooting guide"
    
    # More CI/CD
    echo "name: Deploy" > .github/workflows/deploy.yml
    hug a .github/workflows/deploy.yml
    as_author "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "ci: Add deployment workflow"
    
    # Code quality tools
    echo '{"rules": {"complexity": ["error", 10]}}' > .eslintrc.json
    hug a .eslintrc.json
    as_author "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "chore: Update ESLint rules"
    
    # More tests
    echo "// Performance tests" > tests/performance.test.js
    hug a tests/performance.test.js
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "test: Add performance tests"
}

# Set up a simulated remote and configure upstream tracking.
setup_remote_and_upstream() {
    echo "10. Setting up remote repository and upstream tracking..."
    
    # Create a bare repository to simulate a remote
    cd /tmp
    rm -rf demo-repo.git
    git init --bare demo-repo.git 2>&1 | grep -v "hint:"
    
    cd demo-repo
    git remote add origin /tmp/demo-repo.git 2>&1 | grep -v "hint:"
    
    # Push main branch to establish it on remote
    git push -u origin main 2>&1 | grep -v "hint:"
    
    # Scenario 1: Branch in sync with upstream
    git checkout feature/user-auth 2>&1 | grep -v "hint:"
    git push -u origin feature/user-auth 2>&1 | grep -v "hint:"
    
    # Scenario 2: Branch ahead of upstream
    git checkout feature/user-profile 2>&1 | grep -v "hint:"
    git push -u origin feature/user-profile 2>&1 | grep -v "hint:"
    # Add commit locally to make it ahead
    echo "// Additional profile feature" >> src/profile.js
    git add src/profile.js
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "feat: Add extra profile feature (ahead of origin)"
    
    # Scenario 3: Branch behind upstream (we'll manually update the remote)
    git checkout feature/dashboard 2>&1 | grep -v "hint:"
    local dashboard_commit=$(git rev-parse HEAD)
    git push -u origin feature/dashboard 2>&1 | grep -v "hint:"
    # Add a commit directly to simulate remote ahead
    echo "// Remote addition" >> src/components/Dashboard.js
    git add src/components/Dashboard.js
    GIT_AUTHOR_NAME="$AUTHOR_TWO_NAME" GIT_AUTHOR_EMAIL="$AUTHOR_TWO_EMAIL" \
    GIT_COMMITTER_NAME="$AUTHOR_TWO_NAME" GIT_COMMITTER_EMAIL="$AUTHOR_TWO_EMAIL" \
    git commit -m "feat: Remote team added dashboard feature" 2>&1 | grep -v "hint:"
    git push origin feature/dashboard 2>&1 | grep -v "hint:"
    # Reset local to previous state to be behind
    git reset --hard $dashboard_commit 2>&1 | grep -v "hint:"
    
    # Scenario 4: Branch both ahead and behind (diverged)
    git checkout feature/search 2>&1 | grep -v "hint:"
    local search_base=$(git rev-parse HEAD)
    git push -u origin feature/search 2>&1 | grep -v "hint:"
    
    # Add local commit (makes it ahead)
    echo "// Local search improvement" >> src/search.js
    git add src/search.js
    as_author "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "feat: Local search enhancement (diverged)"
    local search_local=$(git rev-parse HEAD)
    
    # Now create a different remote commit (makes it behind as well)
    git checkout $search_base 2>&1 | grep -v "hint:"
    echo "// Remote search improvement (different line)" >> src/search.js
    git add src/search.js
    GIT_AUTHOR_NAME="$AUTHOR_FOUR_NAME" GIT_AUTHOR_EMAIL="$AUTHOR_FOUR_EMAIL" \
    GIT_COMMITTER_NAME="$AUTHOR_FOUR_NAME" GIT_COMMITTER_EMAIL="$AUTHOR_FOUR_EMAIL" \
    git commit -m "feat: Remote search optimization (diverged)" 2>&1 | grep -v "hint:"
    git push -f origin feature/search 2>&1 | grep -v "hint:"
    
    # Return to the local version (now it's ahead by 1 and behind by 1)
    git checkout -B feature/search $search_local 2>&1 | grep -v "hint:"
    git branch -u origin/feature/search 2>&1 | grep -v "hint:"
    # Fetch to see the divergence
    git fetch origin 2>&1 | grep -v "hint:"
    
    # Scenario 5: Branches with no upstream (bugfix branches)
    # These already have no upstream since we never pushed them
    
    # Push some other branches for completeness
    git checkout release/v1.0 2>&1 | grep -v "hint:"
    git push origin release/v1.0 2>&1 | grep -v "hint:"
    git checkout hotfix/security-patch 2>&1 | grep -v "hint:"
    git push origin hotfix/security-patch 2>&1 | grep -v "hint:"
    
    # Fetch to update remote tracking
    git fetch origin 2>&1 | grep -v "hint:"
    
    # Return to main
    git checkout main 2>&1 | grep -v "hint:"
}

# Add tags at various points in history.
add_tags() {
    echo "11. Adding tags for version markers..."
    
    # Tag the initial release
    git checkout release/v1.0 2>&1 | grep -v "hint:"
    git tag -a v1.0.0 -m "Release version 1.0.0"
    git tag -a v1.0.0-beta.1 HEAD~1 -m "Beta release 1.0.0-beta.1"
    
    # Tag some points on main
    git checkout main 2>&1 | grep -v "hint:"
    git tag -a v0.1.0 $(git rev-list --max-parents=0 HEAD) -m "Initial version"
    
    # Find the commit where we merged feature/user-auth
    local merge_commit=$(git log --grep="Merge branch 'feature/user-auth'" --format="%H" -n 1)
    if [ -n "$merge_commit" ]; then
        git tag -a v0.5.0 $merge_commit -m "Alpha release with authentication"
    fi
    
    # Add a lightweight tag for quick reference (won't be pushed)
    git tag snapshot-$(date +%Y%m%d)
    
    # Tag the current state (won't be pushed)
    git tag -a v1.1.0-alpha.1 -m "Alpha release 1.1.0"
    
    # Add experimental tag (won't be pushed)
    git tag -a experimental-feature -m "Experimental features tag"
    
    # Push only some tags to remote (not all)
    # Push stable release tags
    git push origin v0.1.0 v0.5.0 v1.0.0-beta.1 v1.0.0 2>&1 | grep -v "hint:"
    
    # Note: v1.1.0-alpha.1, snapshot-*, and experimental-feature are NOT pushed
    # This creates variety for demonstrating local vs remote tags
}

# Add some work-in-progress scenarios.
add_wip_scenarios() {
    echo "12. Adding work-in-progress scenarios..."
    
    # Create a branch with uncommitted changes
    git checkout -b feature/notifications 2>&1 | grep -v "hint:"
    echo "// Notification system - WIP" > src/notifications.js
    git add src/notifications.js
    # Leave it staged but not committed
    
    # Create another branch with unstaged changes
    git checkout -b bugfix/performance-issue 2>&1 | grep -v "hint:"
    echo "// Performance optimization - WIP" > src/performance.js
    # Leave it unstaged
    
    # Return to main
    git checkout main 2>&1 | grep -v "hint:"
}

# Displays the final state of the repository.
show_repo_state() {
    echo ""
    echo "✅ Git repository for the tutorial has been set up successfully!"
    echo "========================================================"
    echo "Repository Statistics:"
    echo "  Total commits: $(git rev-list --all --count)"
    echo "  Total branches: $(git branch -a | wc -l)"
    echo "  Total tags: $(git tag | wc -l)"
    echo "  Contributors: 4"
    echo "  Remote: origin -> /tmp/demo-repo.git"
    echo "========================================================"
    echo "Current branches:"
    hug bll
    echo "--------------------------------------------------------"
    echo "Tags:"
    echo "  Local and remote:"
    git tag -l -n1 | grep -E "^(v0\.[15]\.0|v1\.0\.0)" | sed 's/^/    /'
    echo "  Local only (not pushed):"
    git tag -l -n1 | grep -vE "^(v0\.[15]\.0|v1\.0\.0-beta\.1|v1\.0\.0)$" | sed 's/^/    /'
    echo "--------------------------------------------------------"
    echo "Branch upstream status:"
    git for-each-ref --format='%(refname:short) %(upstream:short) %(upstream:track)' refs/heads/ | \
        awk '{printf "  %-30s %-30s %s\n", $1, ($2 ? $2 : "(no upstream)"), ($3 ? $3 : "")}'
    echo "--------------------------------------------------------"
    echo "Recent commit history:"
    hug ll
    hug sl
    echo "========================================================"
    echo ""
    echo "Demo repository created at: /tmp/demo-repo"
    echo "Remote repository at: /tmp/demo-repo.git"
    echo ""
    echo "Upstream scenarios created:"
    echo "  - feature/user-auth: in sync with origin"
    echo "  - feature/user-profile: ahead of origin by 1 commit"
    echo "  - feature/dashboard: behind origin by 1 commit"
    echo "  - feature/search: diverged (ahead 1, behind 1)"
    echo "  - bugfix/*, experimental/*: no upstream"
    echo ""
    echo "Tags:"
    echo "  - Pushed to remote: v0.1.0, v0.5.0, v1.0.0-beta.1, v1.0.0"
    echo "  - Local only: v1.1.0-alpha.1, snapshot-*, experimental-feature"
    echo ""
    echo "WIP scenarios:"
    echo "  - feature/notifications: staged changes (notification system)"
    echo "  - bugfix/performance-issue: unstaged changes (performance optimization)"
}

# --- Main Execution ---

main() (
    setup_repo
    create_main_commits
    create_feature_branches
    create_bugfix_branches
    create_hotfix_branches
    create_experimental_branches
    create_release_branches
    add_main_branch_commits
    add_development_activity
    setup_remote_and_upstream
    add_tags
    add_wip_scenarios
    show_repo_state
)

# Run the script
main
