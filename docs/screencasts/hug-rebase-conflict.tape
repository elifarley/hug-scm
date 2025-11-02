# VHS Tape: Rebase Conflict Resolution with rbc-other
# This tape demonstrates how to resolve a rebase conflict
# by prioritizing the "other" branch's changes.

# Output files (PNG)
Output docs/commands/img/rebase-conflict-1-conflict.png
Output docs/commands/img/rebase-conflict-2-cat.png
Output docs/commands/img/rebase-conflict-3-resolved-cat.png
Output docs/commands/img/rebase-conflict-4-resolved-history.png

Require echo

# Terminal settings
Set Shell "fish"
Set FontSize 13
Set Width 1020
Set Height 800
Set Margin 0
Set Padding 10
Set Theme "Afterglow"

#==============================================================================
# Setup (hidden from output)
#==============================================================================
Hide
Type "cd /tmp/demo-repo"
Enter
Sleep 500ms
Type "./git-config/bin/hug w zap-all -f"
Enter
Sleep 500ms
Type "git checkout main"
Enter
Sleep 500ms
Type "echo 'line 1: Original content' > file.txt"
Enter
Sleep 500ms
Type "./git-config/bin/hug ac 'Add file.txt'"
Enter
Sleep 500ms
Type "./git-config/bin/hug b feature"
Enter
Sleep 500ms
Type "echo 'line 1: Feature branch change' > file.txt"
Enter
Sleep 500ms
Type "./git-config/bin/hug ac 'Modify file.txt on feature'"
Enter
Sleep 500ms
Type "./git-config/bin/hug c main"
Enter
Sleep 500ms
Type "echo 'line 1: Main branch change' > file.txt"
Enter
Sleep 500ms
Type "./git-config/bin/hug ac 'Modify file.txt on main'"
Enter
Sleep 500ms
Type "./git-config/bin/hug c feature"
Enter
Sleep 500ms
Type "clear"
Enter
Sleep 200ms
Show

#==============================================================================
# Command Demonstration (visible in output)
#==============================================================================
Set TypingSpeed 40ms

# Show the divergent history before rebase
Type "./git-config/bin/hug lol -n 4"
Enter
Sleep 3s

# Attempt to rebase the 'feature' branch onto 'main', causing a conflict
Type "./git-config/bin/hug rb main"
Enter
Sleep 3s

# Show the status, which indicates a conflict
Type "./git-config/bin/hug sl"
Enter
Sleep 2s
Screenshot docs/commands/img/rebase-conflict-1-conflict.png

# Show the contents of the file with conflict markers
Type "cat file.txt"
Enter
Sleep 3s
Screenshot docs/commands/img/rebase-conflict-2-cat.png

# Resolve the conflict automatically, accepting the changes from 'main' (other)
Type "./git-config/bin/hug rbc-other"
Enter
Sleep 3s

# Show the file content after resolution
Type "cat file.txt"
Enter
Sleep 2s
Screenshot docs/commands/img/rebase-conflict-3-resolved-cat.png

# Show the new, linear history
Type "./git-config/bin/hug lol -n 4"
Enter
Sleep 3s
Screenshot docs/commands/img/rebase-conflict-4-resolved-history.png

#==============================================================================
# Cleanup (hidden from output)
#==============================================================================
Hide
Type "./git-config/bin/hug w zap-all -f"
Enter
Sleep 300ms
Type "git checkout main &> /dev/null"
Enter
Sleep 300ms
Type "git branch -D feature &> /dev/null"
Enter
Sleep 300ms
