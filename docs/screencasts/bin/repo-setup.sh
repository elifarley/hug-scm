#!/usr/bin/env bash
CMD_BASE="$(readlink -f "$0" 2>/dev/null || greadlink -f "$0")" || CMD_BASE="$0"; CMD_BASE="$(dirname "$CMD_BASE")"

#==============================================================================
# A script to create a hug repository for tutorials with multiple contributors.
#==============================================================================

# --- Contributor Definitions ---
readonly AUTHOR_ONE_NAME="Alice Smith"
readonly AUTHOR_ONE_EMAIL="alice.smith@example.com"
readonly AUTHOR_TWO_NAME="Bob Johnson"
readonly AUTHOR_TWO_EMAIL="bob.johnson@example.com"

# --- Helper Functions ---

# Executes a hug command as a specific author.
# Usage: as_author "Author Name" "author@email.com" "hug c -m 'message'"
as_author() {
    local author_name="$1"; shift
    local author_email="$2"; shift

    GIT_AUTHOR_NAME="$author_name" GIT_AUTHOR_EMAIL="$author_email" hug "$@"
}

# --- Repository Creation Functions ---

# Creates the directory and initializes the hug repository.
setup_repo() {
    cd /tmp
    echo "1. Initializing repository..."
    mkdir -p demo-repo
    rm -rf demo-repo/* demo-repo/.git
    cd demo-repo
    hug init -b main
}

# Creates the initial commits on the main branch.
create_main_commits() {
    echo "2. Creating initial commits on main branch..."
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c --allow-empty -m "Initial commit"

    echo "console.log('hello world');" > app.js
    hug a app.js
    as_author "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "feat: Add main application file"
}

# Creates a feature branch and merges it into main.
create_merged_feature_branch() {
    echo "3. Creating and merging the 'user-login' feature branch..."
    hug bc feature/user-login

    echo "// User login functionality" > login.js
    hug a login.js
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "feat: Implement user login feature"

    hug checkout main
    as_author "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        mkeep feature/user-login -m "Merge branch 'feature/user-login'"
}

# Creates a second feature branch with multiple commits that remains unmerged.
create_unmerged_feature_branch() {
    echo "4. Creating the unmerged 'user-profile' feature branch..."
    hug bc feature/user-profile

    echo "<h1>User Profile</h1>" > profile.html
    hug a profile.html
    as_author "$AUTHOR_TWO_NAME" "$AUTHOR_TWO_EMAIL" \
        c -m "feat: Add basic HTML for user profile"

    echo "body { font-family: sans-serif; }" > styles.css
    hug a styles.css
    as_author "$AUTHOR_ONE_NAME" "$AUTHOR_ONE_EMAIL" \
        c -m "style: Add basic styling for profile page"

    hug b main
}

# Displays the final state of the repository.
show_repo_state() {
    echo ""
    echo "✅ Git repository for the tutorial has been set up successfully!"
    echo "========================================================"
    echo "Current branches:"
    hug bll
    echo "--------------------------------------------------------"
    echo "Commit history with authors:"
    hug ll
    hug sl
    echo "========================================================"
}


# --- Main Execution ---

main() (
    setup_repo
    create_main_commits
    create_merged_feature_branch
    create_unmerged_feature_branch
    show_repo_state
)

# Run the script
main
