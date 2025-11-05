#!/usr/bin/env bash
CMD_BASE="$(readlink -f "$0" 2>/dev/null || greadlink -f "$0")" || CMD_BASE="$0"; CMD_BASE="$(dirname "$CMD_BASE")"
set -euo pipefail  # Exit on error, undefined vars, pipe failures

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

hug() { cd "$DEMO_REPO_BASE" && "$CMD_BASE"/../../../git-config/bin/hug "$@" ;}
git() { cd "$DEMO_REPO_BASE" && command git "$@" ;}

# --- Fake Clock System for Deterministic Commit Hashes ---
# Initialize fake clock to a fixed starting date
# This ensures all commits have deterministic dates and thus deterministic hashes
FAKE_CLOCK_EPOCH=946684800  # 2000-01-01 00:00:00 UTC

# Current fake timestamp (will be advanced with each commit)
FAKE_CLOCK_CURRENT=$FAKE_CLOCK_EPOCH

# Advances the fake clock by a specified delta
# Usage: advance_clock <amount> <unit>
#   where unit can be: minutes, hours, days, weeks, months, years
advance_clock() {
    local amount=$1
    local unit=$2
    local seconds=0
    
    case "$unit" in
        minute|minutes)
            seconds=$((amount * 60))
            ;;
        hour|hours)
            seconds=$((amount * 3600))
            ;;
        day|days)
            seconds=$((amount * 86400))
            ;;
        week|weeks)
            seconds=$((amount * 604800))
            ;;
        month|months)
            # Approximate: 30.44 days per month
            seconds=$((amount * 2629800))
            ;;
        year|years)
            # Approximate: 365.25 days per year
            seconds=$((amount * 31557600))
            ;;
        *)
            echo "Error: Unknown time unit: $unit" >&2
            return 1
            ;;
    esac
    
    FAKE_CLOCK_CURRENT=$((FAKE_CLOCK_CURRENT + seconds))
}

# Executes a hug command as a specific author with deterministic dates.
# Usage: commit_with_date <time_delta> <time_unit> "Author Name" "author@email.com" <hug command and args>
# Example: commit_with_date 2 days "Alice Smith" "alice@example.com" c -m "Add feature"
commit_with_date() {
    local time_amount="$1"; shift
    local time_unit="$1"; shift
    local author_name="$1"; shift
    local author_email="$1"; shift
    
    # Advance the fake clock
    advance_clock "$time_amount" "$time_unit"
    
    # Format the timestamp for git (ISO 8601 format with timezone)
    local commit_date="${FAKE_CLOCK_CURRENT} +0000"
    
    # Execute the command with all environment variables set for deterministic commits
    GIT_AUTHOR_NAME="$author_name" \
    GIT_AUTHOR_EMAIL="$author_email" \
    GIT_AUTHOR_DATE="$commit_date" \
    GIT_COMMITTER_NAME="$author_name" \
    GIT_COMMITTER_EMAIL="$author_email" \
    GIT_COMMITTER_DATE="$commit_date" \
    hug "$@"
}

# Executes a hug command as a specific author.
# Usage: commit_with_date 0 days "Author Name" "author@email.com" "hug c -m 'message'"
as_author() (
    local author_name="$1"; shift
    local author_email="$2"; shift

    GIT_AUTHOR_NAME="$author_name" GIT_AUTHOR_EMAIL="$author_email" \
    GIT_COMMITTER_NAME="$author_name" GIT_COMMITTER_EMAIL="$author_email" \
    hug "$@"
)

# --- Repository Creation Functions ---

# Creates the directory and initializes the git repository.
setup_repo() (
    echo "1. Initializing repository..."
    mkdir -p "$DEMO_REPO_BASE"
    cd "$DEMO_REPO_BASE" && git init -b main
)

# Creates the initial commits on the main branch.
create_main_commits() (
    echo "2. Creating initial commits on main branch..."
    commit_with_date 2 hours "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c --allow-empty -m "Initial commit"

    echo "# Demo Application" > README.md
    echo "This is a demo repository for Hug SCM tutorials." >> README.md
    hug a README.md
    commit_with_date 1 day "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "docs: Add README file"

    echo "console.log('hello world');" > app.js
    hug a app.js
    commit_with_date 3 days "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "feat: Add main application file"

    echo "node_modules/" > .gitignore
    echo ".env" >> .gitignore
    echo "dist/" >> .gitignore
    hug a .gitignore
    commit_with_date 1 week "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "chore: Add gitignore file"

    mkdir -p src tests
    echo "// Main entry point" > src/index.js
    hug a src/index.js
    commit_with_date 3 weeks "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "refactor: Move app to src directory"
)

# Creates feature branches with multiple commits.
create_feature_branches() (
    echo "3. Creating feature branches..."
    
    # Feature 1: User Authentication (merged)
    hug bc feature/user-auth
    echo "// User authentication module" > src/auth.js
    hug a src/auth.js
    commit_with_date 3 days "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "feat: Add authentication module"
    
    echo "export function login(user, pass) { /* ... */ }" >> src/auth.js
    hug a src/auth.js
    commit_with_date 2 days "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "feat: Implement login function"
    
    echo "export function logout() { /* ... */ }" >> src/auth.js
    hug a src/auth.js
    commit_with_date 1 day "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "feat: Add logout functionality"
    
    hug checkout main
    commit_with_date 3 weeks "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        mkeep feature/user-auth -m "Merge branch 'feature/user-auth'"
    
    # Feature 2: User Profile (unmerged, active)
    hug bc feature/user-profile
    echo "<h1>User Profile</h1>" > src/profile.html
    hug a src/profile.html
    commit_with_date 4 days "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "feat: Add basic HTML for user profile"

    echo "body { font-family: sans-serif; }" > src/styles.css
    hug a src/styles.css
    commit_with_date 3 days "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "style: Add basic styling for profile page"

    echo "// Profile data handling" > src/profile.js
    hug a src/profile.js
    commit_with_date 3 weeks "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "feat: Add profile data handler"
    
    # Feature 3: Dashboard (unmerged, active)
    hug bc feature/dashboard
    mkdir -p src/components
    echo "// Dashboard component" > src/components/Dashboard.js
    hug a src/components/Dashboard.js
    commit_with_date 4 days "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "feat: Create dashboard component"
    
    echo "// Widget system" > src/components/Widget.js
    hug a src/components/Widget.js
    commit_with_date 3 weeks "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "feat: Add widget system to dashboard"
    
    # Feature 4: API Integration (merged)
    hug bc feature/api-integration
    echo "// API client" > src/api.js
    hug a src/api.js
    commit_with_date 3 days "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "feat: Add API client module"
    
    echo "export async function fetchData(endpoint) { /* ... */ }" >> src/api.js
    hug a src/api.js
    commit_with_date 2 days "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "feat: Implement data fetching"
    
    echo "export function handleError(err) { /* ... */ }" >> src/api.js
    hug a src/api.js
    commit_with_date 1 day "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "feat: Add error handling to API"
    
    hug checkout main
    commit_with_date 3 weeks "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        mkeep feature/api-integration -m "Merge branch 'feature/api-integration'"
    
    # Feature 5: Search Functionality (unmerged)
    hug bc feature/search
    echo "// Search implementation" > src/search.js
    hug a src/search.js
    commit_with_date 3 days "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "feat: Add search functionality"
    
    echo "export function searchUsers(query) { /* ... */ }" >> src/search.js
    hug a src/search.js
    commit_with_date 3 weeks "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "feat: Implement user search"
)

# Creates bugfix branches.
create_bugfix_branches() (
    echo "4. Creating bugfix branches..."
    
    hug b main
    
    # Bugfix 1: Login validation (merged)
    hug bc bugfix/login-validation
    echo "// Fixed: validate email format" >> src/auth.js
    hug a src/auth.js
    commit_with_date 1 day "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "fix: Add email validation to login"
    
    hug checkout main
    commit_with_date 3 weeks "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        mkeep bugfix/login-validation -m "Merge branch 'bugfix/login-validation'"
    
    # Bugfix 2: Memory leak (merged)
    hug bc bugfix/memory-leak
    echo "// Fixed: clear event listeners" >> src/components/Dashboard.js
    hug a src/components/Dashboard.js
    commit_with_date 2 days "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "fix: Fix memory leak in dashboard"
    
    echo "// Add cleanup function" >> src/components/Dashboard.js
    hug a src/components/Dashboard.js
    commit_with_date 1 day "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "fix: Add proper cleanup on unmount"
    
    hug checkout main
    commit_with_date 3 weeks "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        mkeep bugfix/memory-leak -m "Merge branch 'bugfix/memory-leak'"
    
    # Bugfix 3: API timeout (unmerged, being worked on)
    hug bc bugfix/api-timeout
    echo "// TODO: implement retry logic" >> src/api.js
    hug a src/api.js
    commit_with_date 3 weeks "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "fix: Add timeout handling to API calls"
    
    # Bugfix 4: CSS styling issue (unmerged)
    hug bc bugfix/css-layout
    echo "/* Fix responsive layout */" >> src/styles.css
    hug a src/styles.css
    commit_with_date 3 weeks "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "fix: Fix layout issues on mobile"
)

# Creates hotfix branches for production issues.
create_hotfix_branches() (
    echo "5. Creating hotfix branches..."
    
    hug b main
    
    # Hotfix 1: Critical security patch (merged)
    hug bc hotfix/security-patch
    echo "// Security: sanitize user input" >> src/auth.js
    hug a src/auth.js
    commit_with_date 2 hours "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "hotfix: Add input sanitization"
    
    hug checkout main
    commit_with_date 2 weeks "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        mkeep hotfix/security-patch -m "Merge branch 'hotfix/security-patch'"
    
    # Hotfix 2: Production crash (merged)
    hug bc hotfix/prod-crash
    echo "// Add null check" >> src/components/Widget.js
    hug a src/components/Widget.js
    commit_with_date 1 hour "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "hotfix: Fix null pointer crash"
    
    hug checkout main
    commit_with_date 2 weeks "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        mkeep hotfix/prod-crash -m "Merge branch 'hotfix/prod-crash'"
)

# Creates experimental/research branches.
create_experimental_branches() (
    echo "6. Creating experimental branches..."
    
    hug b main
    
    # Experimental 1: New architecture
    hug bc experimental/new-arch
    echo "// Exploring new architecture pattern" > src/experimental.js
    hug a src/experimental.js
    commit_with_date 2 weeks "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "experiment: Try new architecture pattern"
    
    echo "// Continue exploration" >> src/experimental.js
    hug a src/experimental.js
    commit_with_date 2 weeks "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "experiment: Test performance improvements"
    
    # Experimental 2: AI integration
    hug bc experimental/ai-integration
    echo "// AI-powered features" > src/ai.js
    hug a src/ai.js
    commit_with_date 3 weeks "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "experiment: Add AI integration prototype"
)

# Creates release branches.
create_release_branches() (
    echo "7. Creating release branches..."
    
    hug b main
    
    # Release 1: v1.0 (merged)
    hug bc release/v1.0
    echo '{"version": "1.0.0"}' > package.json
    hug a package.json
    commit_with_date 2 weeks "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "release: Prepare v1.0.0 release"
    
    echo "## Version 1.0.0" > CHANGELOG.md
    echo "- Initial release" >> CHANGELOG.md
    hug a CHANGELOG.md
    commit_with_date 3 days "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "docs: Add changelog for v1.0.0"
    
    hug checkout main
    commit_with_date 2 weeks "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        mkeep release/v1.0 -m "Merge branch 'release/v1.0'"
    
    # Release 2: v1.1 (in progress)
    hug bc release/v1.1
    echo '{"version": "1.1.0-rc.1"}' > package.json
    hug a package.json
    commit_with_date 2 weeks "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "release: Bump version to 1.1.0-rc.1"
)

# Creates a branch with a conflict for rebase demonstrations.
create_rebase_conflict_branch() (
    echo "7a. Creating branch with rebase conflict..."

    hug b main

    # 1. Create a common base commit
    echo "This is the original line." > conflict.txt
    hug a conflict.txt
    commit_with_date 1 day "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "feat: Add base file for conflict"

    # 2. Create a branch
    hug bc feature/rebase-conflict-demo

    # 3. Create a commit on the branch
    echo "This is a line from the feature branch." > conflict.txt
    hug a conflict.txt
    commit_with_date 1 day "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "feat: Modify conflict file on feature branch"

    # 4. Go back to the original branch, and create a conflicting commit
    hug b main

    echo "This is a line from the main branch." > conflict.txt
    hug a conflict.txt
    commit_with_date 1 day "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "feat: Modify conflict file on main branch"

    # Leave the repo on the feature branch
    hug b feature/rebase-conflict-demo
)

# Add more commits to main branch for realistic history.
add_main_branch_commits() (
    echo "8. Adding more commits to main branch..."
    
    hug b main
    
    # Documentation updates
    echo "## Installation" >> README.md
    echo "\`\`\`bash" >> README.md
    echo "npm install" >> README.md
    echo "\`\`\`" >> README.md
    hug a README.md
    commit_with_date 2 weeks "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "docs: Add installation instructions"
    
    # Testing infrastructure
    echo "// Test helper functions" > tests/helpers.js
    hug a tests/helpers.js
    commit_with_date 1 week "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "test: Add test helper utilities"
    
    echo "// Unit tests for auth module" > tests/auth.test.js
    hug a tests/auth.test.js
    commit_with_date 1 week "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "test: Add tests for authentication"
    
    echo "// Integration tests" > tests/integration.test.js
    hug a tests/integration.test.js
    commit_with_date 2 weeks "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "test: Add integration tests"
    
    # Configuration files
    echo '{"semi": true, "singleQuote": true}' > .prettierrc
    hug a .prettierrc
    commit_with_date 1 week "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "chore: Add prettier configuration"
    
    echo '{"extends": "eslint:recommended"}' > .eslintrc.json
    hug a .eslintrc.json
    commit_with_date 2 weeks "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "chore: Add ESLint configuration"
    
    # More documentation
    echo "## Contributing" >> README.md
    echo "Pull requests are welcome!" >> README.md
    hug a README.md
    commit_with_date 1 week "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "docs: Add contributing section"
    
    echo "# Contributing Guidelines" > CONTRIBUTING.md
    echo "Please follow these guidelines..." >> CONTRIBUTING.md
    hug a CONTRIBUTING.md
    commit_with_date 2 weeks "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "docs: Add contributing guidelines"
    
    # CI/CD configuration
    mkdir -p .github/workflows
    echo "name: CI" > .github/workflows/test.yml
    hug a .github/workflows/test.yml
    commit_with_date 1 week "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "ci: Add GitHub Actions workflow"
    
    # License
    echo "MIT License" > LICENSE
    hug a LICENSE
    commit_with_date 3 weeks "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "docs: Add MIT license"
)

# Add more realistic development activity with additional commits.
add_development_activity() (
    echo "9. Adding additional development activity..."
    
    # Add more tests
    hug b main
    echo "// Unit tests for API" > tests/api.test.js
    hug a tests/api.test.js
    commit_with_date 2 weeks "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "test: Add API tests"
    
    echo "// End-to-end tests" > tests/e2e.test.js
    hug a tests/e2e.test.js
    commit_with_date 3 weeks "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "test: Add e2e tests"
    
    # More configuration
    echo '{"compilerOptions": {"target": "ES2020"}}' > tsconfig.json
    hug a tsconfig.json
    commit_with_date 3 weeks "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "chore: Add TypeScript configuration"
    
    # Update dependencies
    cat > package.json << 'EOF'
{
  "name": "demo-app",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.0"
  }
}
EOF
    hug a package.json
    commit_with_date 3 weeks "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "chore: Update dependencies"
    
    # Add API documentation
    mkdir -p docs
    echo "# API Documentation" > docs/API.md
    echo "## Endpoints" >> docs/API.md
    hug a docs/API.md
    commit_with_date 2 weeks "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "docs: Add API documentation"
    
    # Add user guide
    echo "# User Guide" > docs/USER_GUIDE.md
    hug a docs/USER_GUIDE.md
    commit_with_date 3 weeks "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "docs: Add user guide"
    
    # Performance improvements
    echo "// Performance optimization" >> src/api.js
    hug a src/api.js
    commit_with_date 3 weeks "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "perf: Optimize API calls"
    
    # Security updates
    echo "// Security enhancement" >> src/auth.js
    hug a src/auth.js
    commit_with_date 2 weeks "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "security: Add rate limiting"
    
    # Refactoring
    echo "// Refactored for better maintainability" >> src/index.js
    hug a src/index.js
    commit_with_date 3 weeks "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "refactor: Improve code structure"
    
    # Additional feature commits on branches
    hug b feature/user-profile
    echo "// Profile validation" >> src/profile.js
    hug a src/profile.js
    commit_with_date 2 weeks "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "feat: Add profile validation"
    
    echo "/* Mobile responsive styles */" >> src/styles.css
    hug a src/styles.css
    commit_with_date 3 weeks "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "style: Make profile mobile responsive"
    
    hug b feature/dashboard
    echo "// Dashboard analytics" >> src/components/Dashboard.js
    hug a src/components/Dashboard.js
    commit_with_date 2 weeks "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "feat: Add analytics to dashboard"
    
    echo "// Widget customization" >> src/components/Widget.js
    hug a src/components/Widget.js
    commit_with_date 3 weeks "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "feat: Add widget customization"
    
    hug b feature/search
    echo "// Advanced search filters" >> src/search.js
    hug a src/search.js
    commit_with_date 2 weeks "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "feat: Add advanced search filters"
    
    echo "// Search result pagination" >> src/search.js
    hug a src/search.js
    commit_with_date 3 weeks "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "feat: Add pagination to search results"
    
    # More bugfix work
    hug b bugfix/api-timeout
    echo "// Implement exponential backoff" >> src/api.js
    hug a src/api.js
    commit_with_date 2 weeks "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "fix: Implement retry with backoff"
    
    echo "// Add timeout configuration" >> src/api.js
    hug a src/api.js
    commit_with_date 3 weeks "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "fix: Make timeout configurable"
    
    hug b bugfix/css-layout
    echo "/* Fix flexbox issues */" >> src/styles.css
    hug a src/styles.css
    commit_with_date 2 weeks "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "fix: Fix flexbox layout bugs"
    
    echo "/* Add grid layout */" >> src/styles.css
    hug a src/styles.css
    commit_with_date 3 weeks "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "fix: Implement CSS grid for better layout"
    
    # Experimental branches get more work
    hug b experimental/new-arch
    echo "// Modular architecture" >> src/experimental.js
    hug a src/experimental.js
    commit_with_date 2 weeks "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "experiment: Implement modular architecture"
    
    echo "// Plugin system" >> src/experimental.js
    hug a src/experimental.js
    commit_with_date 3 weeks "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "experiment: Add plugin system"
    
    hug b experimental/ai-integration
    echo "// AI model integration" >> src/ai.js
    hug a src/ai.js
    commit_with_date 2 weeks "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "experiment: Integrate ML model"
    
    echo "// Training pipeline" >> src/ai.js
    hug a src/ai.js
    commit_with_date 3 weeks "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "experiment: Add training pipeline"
    
    # Back to main for final updates
    hug b main
    echo "## Usage" >> README.md
    echo "See docs for details" >> README.md
    hug a README.md
    commit_with_date 2 weeks "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "docs: Add usage section to README"
    
    echo "## Troubleshooting" >> README.md
    hug a README.md
    commit_with_date 3 weeks "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "docs: Add troubleshooting guide"
    
    # More CI/CD
    echo "name: Deploy" > .github/workflows/deploy.yml
    hug a .github/workflows/deploy.yml
    commit_with_date 2 weeks "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "ci: Add deployment workflow"
    
    # Code quality tools
    echo '{"rules": {"complexity": ["error", 10]}}' > .eslintrc.json
    hug a .eslintrc.json
    commit_with_date 3 weeks "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "chore: Update ESLint rules"
    
    # More tests
    echo "// Performance tests" > tests/performance.test.js
    hug a tests/performance.test.js
    commit_with_date 1 week "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "test: Add performance tests"
)

# Set up a simulated remote and configure upstream tracking.
setup_remote_and_upstream() (
    echo "10. Setting up remote repository and upstream tracking..."
    
    # Create a bare repository to simulate a remote
    # Use command git to avoid the wrapper that cd's to $DEMO_REPO_BASE
    rm -rf "$DEMO_REPO_BASE.git"
    command git init --bare "$DEMO_REPO_BASE.git" 2>&1 | grep -v "hint:" || true
    
    cd "$DEMO_REPO_BASE"
    hug remote add origin "$DEMO_REPO_BASE.git" 2>&1 | grep -v "hint:" || true
    
    # Push main branch to establish it on remote
    hug push -u origin main 2>&1 | grep -v "hint:" || true
    
    # Scenario 1: Branch in sync with upstream
    hug checkout feature/user-auth 2>&1 | grep -v "hint:" || true
    hug push -u origin feature/user-auth 2>&1 | grep -v "hint:" || true
    
    # Scenario 2: Branch ahead of upstream
    hug checkout feature/user-profile 2>&1 | grep -v "hint:" || true
    hug push -u origin feature/user-profile 2>&1 | grep -v "hint:" || true
    # Add commit locally to make it ahead
    echo "// Additional profile feature" >> src/profile.js
    hug add src/profile.js
    commit_with_date 3 days "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "feat: Add extra profile feature (ahead of origin)"
    
    # Scenario 3: Branch behind upstream (we'll manually update the remote)
    hug checkout feature/dashboard 2>&1 | grep -v "hint:" || true
    local dashboard_commit=$(hug rev-parse HEAD)
    hug push -u origin feature/dashboard 2>&1 | grep -v "hint:" || true
    # Add a commit directly to simulate remote ahead
    echo "// Remote addition" >> src/components/Dashboard.js
    hug add src/components/Dashboard.js
    commit_with_date 2 days "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "feat: Remote team added dashboard feature"
    hug push origin feature/dashboard 2>&1 | grep -v "hint:" || true
    # Reset local to previous state to be behind
    hug reset --hard $dashboard_commit 2>&1 | grep -v "hint:" || true
    
    # Scenario 4: Branch both ahead and behind (diverged)
    # This requires careful sequencing to ensure both states exist
    hug checkout feature/search 2>&1 | grep -v "hint:" || true
    local search_base=$(hug rev-parse HEAD)
    hug push -u origin feature/search 2>&1 | grep -v "hint:" || true
    
    # Add local commit (makes it ahead)
    echo "// Local search improvement" >> src/search.js
    hug add src/search.js
    commit_with_date 1 day "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "feat: Local search enhancement (diverged)"
    local search_local=$(hug rev-parse HEAD)
    
    # Create a new commit on the base and push it as the remote version
    # This makes the remote ahead of what we had
    hug checkout -b temp-search-remote $search_base 2>&1 | grep -v "hint:" || true
    echo "// Remote search improvement (different line)" >> src/search.js
    hug add src/search.js
    commit_with_date 1 day "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        c -m "feat: Remote search optimization (diverged)"
    
    # Force push this to origin/feature/search
    hug push -f origin temp-search-remote:feature/search 2>&1 | grep -v "hint:" || true
    
    # Now switch back to our local version which has a different commit
    hug checkout feature/search 2>&1 | grep -v "hint:" || true
    hug reset --hard $search_local 2>&1 | grep -v "hint:" || true
    
    # Update the tracking and fetch to see the divergence
    hug branch -u origin/feature/search 2>&1 | grep -v "hint:" || true
    hug fetch origin 2>&1 | grep -v "hint:" || true
    
    # Clean up temp branch
    hug branch -D temp-search-remote 2>&1 | grep -v "hint:" || true
    
    # Scenario 5: Branches with no upstream (bugfix branches)
    # These already have no upstream since we never pushed them
    
    # Push some other branches for completeness
    hug checkout release/v1.0 2>&1 | grep -v "hint:" || true
    hug push origin release/v1.0 2>&1 | grep -v "hint:" || true
    hug checkout hotfix/security-patch 2>&1 | grep -v "hint:" || true
    hug push origin hotfix/security-patch 2>&1 | grep -v "hint:" || true
    
    # Fetch to update remote tracking
    hug fetch origin 2>&1 | grep -v "hint:" || true
    
    # Return to main
    hug checkout main 2>&1 | grep -v "hint:" || true
)

# Add tags at various points in history.
add_tags() (
    echo "11. Adding tags for version markers..."
    
    # Tag the initial release
    hug checkout release/v1.0 2>&1 | grep -v "hint:" || true
    commit_with_date 1 day "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        tag -a v1.0.0 -m "Release version 1.0.0"
    commit_with_date 1 day "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        tag -a v1.0.0-beta.1 HEAD~1 -m "Beta release 1.0.0-beta.1"
    
    # Tag some points on main
    hug checkout main 2>&1 | grep -v "hint:" || true
    commit_with_date 1 day "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        tag -a v0.1.0 $(hug rev-list --max-parents=0 HEAD) -m "Initial version"
    
    # Find the commit where we merged feature/user-auth
    local merge_commit=$(hug log --grep="Merge branch 'feature/user-auth'" --format="%H" -n 1)
    if [ -n "$merge_commit" ]; then
        commit_with_date 1 day "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
            tag -a v0.5.0 $merge_commit -m "Alpha release with authentication"
    fi
    
    # Add a lightweight tag for quick reference (won't be pushed)
    commit_with_date 1 day "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        tag snapshot-$(date +%Y%m%d)
    
    # Tag the current state (won't be pushed)
    commit_with_date 1 day "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        tag -a v1.1.0-alpha.1 -m "Alpha release 1.1.0"
    
    # Add experimental tag (won't be pushed)
    commit_with_date 1 day "$AUTHOR_FOUR_NAME" "$AUTHOR_FOUR_EMAIL" \
        tag -a experimental-feature -m "Experimental features tag"
    
    # Push only some tags to remote (not all)
    # Push stable release tags
    hug push origin v0.1.0 v0.5.0 v1.0.0-beta.1 v1.0.0 2>&1 | grep -v "hint:" || true
    
    # Note: v1.1.0-alpha.1, snapshot-*, and experimental-feature are NOT pushed
    # This creates variety for demonstrating local vs remote tags
)

# Create comprehensive WIP scenarios demonstrating all major Git file states.
create_comprehensive_wip_scenarios() (
    echo "12. Creating comprehensive WIP scenarios with all Git file states..."
    
    # Switch to main and create new demo branch
    hug checkout main 2>&1 | grep -v "hint:" || true
    hug checkout -b demo/wip-states 2>&1 | grep -v "hint:" || true
    
    # ============================================================================
    # PHASE 1: Setup - commit base files that will be modified/deleted
    # ============================================================================
    
    # Create files that will be deleted (unstaged)
    echo "// App file" > app.js
    hug a app.js
    
    # Create files that will be staged for deletion
    echo "// File to be deleted from staging" > staged-deleted-1.js
    echo "// Another file to be deleted from staging" > staged-deleted-2.js
    hug a staged-deleted-1.js staged-deleted-2.js
    
    # Create files that will be renamed
    mkdir -p src
    echo "// Profile file for rename demo" > src/profile.js
    echo "// Search file for rename demo" > src/search.js
    hug a src/profile.js src/search.js
    
    # Create files for conflicts on this branch
    echo "// Conflict 1 from demo/wip-states" > conflict-1.txt
    echo "// Conflict 2 from demo/wip-states" > conflict-2.txt
    hug a conflict-1.txt conflict-2.txt
    
    commit_with_date 1 day "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "feat: Add base files for WIP demo"
    
    # ============================================================================
    # PHASE 2: Create conflicts via temp branch
    # ============================================================================
    
    # Create temp branch with conflicting versions (branch off before modifying)
    hug checkout -b temp/conflict-branch 2>&1 | grep -v "hint:" || true
    echo "// Conflict 1 from temp branch - VERSION A" > conflict-1.txt
    echo "// Conflict 2 from temp branch - VERSION A" > conflict-2.txt
    hug a conflict-1.txt conflict-2.txt
    commit_with_date 1 day "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "feat: Modify conflicts on temp branch"
    
    # Go back and create different versions to conflict
    hug checkout demo/wip-states 2>&1 | grep -v "hint:" || true
    echo "// Conflict 1 from demo/wip-states - VERSION B (DIFFERENT)" > conflict-1.txt
    echo "// Conflict 2 from demo/wip-states - VERSION B (DIFFERENT)" > conflict-2.txt
    hug a conflict-1.txt conflict-2.txt
    commit_with_date 1 day "$AUTHOR_THREE_NAME" "$AUTHOR_THREE_EMAIL" \
        c -m "feat: Modify conflicts on demo branch"
    
    # Merge to create real conflicts - don't use || true so we can see if it fails
    # The --no-commit keeps it from auto-committing on success
    # Set identity for merge operation
    GIT_AUTHOR_NAME="$AUTHOR_THREE_NAME" \
    GIT_AUTHOR_EMAIL="$AUTHOR_THREE_EMAIL" \
    GIT_COMMITTER_NAME="$AUTHOR_THREE_NAME" \
    GIT_COMMITTER_EMAIL="$AUTHOR_THREE_EMAIL" \
    git merge temp/conflict-branch --no-commit 2>&1 | head -20 || true
    
    # At this point, files should be in conflict state (UU)
    # Don't resolve or abort - leave them conflicted
    
    # Clean up temp branch
    hug branch -D temp/conflict-branch 2>&1 | grep -v "hint:" || true
    
    # ============================================================================
    # PHASE 3: Unclean operations (build dirty working directory)
    # ============================================================================
    
    # State 2: Untracked - Create new files without staging
    echo "// WIP: Untracked file 1" > untracked-1.js
    echo "// WIP: Untracked file 2" > untracked-2.js
    
    # State 3: Ignored - Update .gitignore and create ignored files  
    echo "*.tmp" >> .gitignore
    echo "*.bak" >> .gitignore
    hug a .gitignore
    echo "// WIP: Ignored temporary file 1" > ignored-1.tmp
    echo "// WIP: Ignored backup file 2" > ignored-2.bak
    # Unstage .gitignore to show unstaged modification
    git reset .gitignore 2>&1 | grep -v "hint:" || true
    
    # State 4: Unstaged Modified - Modify tracked files without staging
    ( test -f README.md && echo "" >> README.md && echo "// WIP: Unstaged modification" >> README.md ) || true
    ( test -f CHANGELOG.md || touch CHANGELOG.md ) && echo "// WIP: Unstaged changes" >> CHANGELOG.md || true
    
    # State 5: Staged New - Create and stage new files
    echo "// WIP: Staged new file 1" > staged-new-1.js
    echo "// WIP: Staged new file 2" > staged-new-2.js
    hug a staged-new-1.js staged-new-2.js
    
    # State 6: Staged Modified - Modify tracked files and stage them
    ( test -f src/index.js && echo "// WIP: Staged modification 1" >> src/index.js && hug a src/index.js ) || true
    ( test -f src/auth.js && echo "// WIP: Staged modification 2" >> src/auth.js && hug a src/auth.js ) || true
    
    # State 8: Unstaged Deleted - Remove tracked files without staging
    ( test -f app.js && rm app.js ) || true
    ( test -f src/api.js && rm src/api.js ) || true
    
    # State 9: Staged Deleted - Stage deletion of files
    hug rm staged-deleted-1.js staged-deleted-2.js 2>&1 | grep -v "hint:" || true
    
    # State 10: Staged Renamed - Move and stage files (creates rename detection)
    git mv src/profile.js renamed-profile.js 2>&1 | grep -v "hint:" || true
    git mv src/search.js renamed-search.js 2>&1 | grep -v "hint:" || true
    
    echo "✅ WIP demo complete: 'demo/wip-states' branch has all Git file states!"
)

# Displays the final state of the repository.
show_repo_state() (
    echo ""
    echo "✅ Git repository for the tutorial has been set up successfully!"
    echo "========================================================"
    echo "Repository Statistics:"
    echo "  Total commits: $(hug rev-list --all --count)"
    echo "  Total branches: $(hug branch -a | wc -l)"
    echo "  Total tags: $(hug tag | wc -l)"
    echo "  Contributors: 4"
    echo "  Remote: origin -> $DEMO_REPO_BASE.git"
    echo "========================================================"
    echo "Current branches:"
    hug bll
    echo "--------------------------------------------------------"
    echo "Tags:"
    echo "  Local and remote:"
    hug tag -l -n1 | grep -E "^(v0\.[15]\.0|v1\.0\.0)" | sed 's/^/    /' || true
    echo "  Local only (not pushed):"
    hug tag -l -n1 | grep -vE "^(v0\.[15]\.0|v1\.0\.0-beta\.1|v1\.0\.0)$" | sed 's/^/    /' || true
    echo "--------------------------------------------------------"
    echo "Branch upstream status:"
    hug for-each-ref --format='%(refname:short) %(upstream:short) %(upstream:track)' refs/heads/ | \
        awk '{printf "  %-30s %-30s %s\n", $1, ($2 ? $2 : "(no upstream)"), ($3 ? $3 : "")}'
    echo "--------------------------------------------------------"
    echo "Recent commit history:"
    hug ll -4
    echo "--------------------------------------------------------"
    echo "Working directory status on 'demo/wip-states' branch:"
    hug sl
    echo ""
    echo "State Breakdown (2 files per state):"
    echo "  1. Clean/Committed: .gitignore, package.json (no changes)"
    echo "  2. Untracked: untracked-1.js, untracked-2.js"
    echo "  3. Ignored: ignored-1.tmp, ignored-2.bak (*.tmp, *.bak patterns)"
    echo "  4. Unstaged Modified: README.md, CHANGELOG.md"
    echo "  5. Staged New: staged-new-1.js, staged-new-2.js"
    echo "  6. Staged Modified: src/index.js, src/auth.js"
    echo "  7. Unmerged/Conflicted: conflict-1.txt, conflict-2.txt (UU state)"
    echo "  8. Unstaged Deleted: app.js, src/api.js"
    echo "  9. Staged Deleted: staged-deleted-1.js, staged-deleted-2.js"
    echo "  10. Staged Renamed: src/profile.js → renamed-profile.js, src/search.js → renamed-search.js"
    echo "========================================================"
    echo ""
    echo "Demo repository created at: $DEMO_REPO_BASE"
    echo "Remote repository at: $DEMO_REPO_BASE.git"
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
    echo "Demo ready: Run 'hug sl' to see all Git file states on 'demo/wip-states'!"
)

# --- Main Execution ---

main() (
    readonly DEMO_REPO_BASE="${1:-/tmp/demo-repo}"
    test -d "$DEMO_REPO_BASE" && echo "$DEMO_REPO_BASE already exists" && return 0
    setup_repo && cd "$DEMO_REPO_BASE" || return
    create_main_commits
    create_feature_branches
    create_bugfix_branches
    create_hotfix_branches
    create_experimental_branches
    create_release_branches
    create_rebase_conflict_branch
    add_main_branch_commits
    add_development_activity
    setup_remote_and_upstream
    add_tags
    create_comprehensive_wip_scenarios
    show_repo_state
)

# Run the script
main "$@"
