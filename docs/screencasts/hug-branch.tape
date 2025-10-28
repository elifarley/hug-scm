# VHS tape file for hug branching commands
# Shows branch creation, switching, and listing

Output ../commands/img/hug-branch-demo.gif

Require echo
Require hug

Set Shell "bash"
Set FontSize 13
Set Width 1020
Set Height 600
Set Margin 0
Set Padding 10
Set Theme "Afterglow"

# Setup: Start in demo-repo
Hide
Type "cd /tmp/demo-repo" Enter
Sleep 500ms
Type "hug b main" Enter
Sleep 300ms
Type "clear" Enter
Sleep 200ms
Show

# Show current branch status
Set TypingSpeed 40ms
Type "hug bl  # (B)ranch (L)ist - show all branches" Enter
Sleep 2s

# Create a new branch
Type@0s "" Enter
Type "hug bc feature/demo  # (B)ranch (C)reate - new branch" Enter
Sleep 1.5s

# Show branches again
Type@0s "" Enter
Type "hug bl  # Shows new branch (current branch marked with *)" Enter
Sleep 2s

# Switch branches
Type@0s "" Enter
Type "hug b main  # (B)ranch - switch to main" Enter
Sleep 1s

Type@0s "" Enter
Type "hug bl  # Back on main branch" Enter
Sleep 2s

# Cleanup - delete the demo branch
Hide
Type "git branch -D feature/demo 2>/dev/null || true" Enter
Sleep 300ms
