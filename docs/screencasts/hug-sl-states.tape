# VHS tape file for hug-sl showing 4 different states
# Outputs a series of PNGs showing: clean, unstaged, staged, and mixed states
#
# This generates 4 separate screenshots:
# - hug-sl-clean.png: Clean working directory
# - hug-sl-unstaged.png: Unstaged changes only  
# - hug-sl-staged.png: Staged changes only
# - hug-sl-mixed.png: Both staged and unstaged changes

Require echo
Require hug

Set Shell "bash"
Set FontSize 13
Set Width 1020
Set Height 280
Set Margin 0
Set Padding 10
Set Theme "Afterglow"

# Setup: Start in demo-repo
Hide
Type "cd /tmp/demo-repo" Enter
Sleep 500ms

# Clean up any existing state
Type "hug w zap-all -f" Enter
Sleep 500ms
Type "clear" Enter
Sleep 200ms
Show

# STATE 1: Clean working directory
Output ../commands/img/hug-sl-clean.png
Type "hug sl  # State 1: Clean working directory" Enter
Sleep 1s
Screenshot ../commands/img/hug-sl-clean.png

# STATE 2: Unstaged changes only
Hide
Type "clear" Enter
Sleep 200ms
Type "echo 'New content' >> README.md" Enter
Sleep 200ms
Type "clear" Enter
Sleep 200ms
Show

Output ../commands/img/hug-sl-unstaged.png
Type "hug sl  # State 2: Unstaged changes only" Enter
Sleep 1s
Screenshot ../commands/img/hug-sl-unstaged.png

# STATE 3: Staged changes only
Hide
Type "clear" Enter
Sleep 200ms
Type "hug a README.md" Enter
Sleep 200ms
Type "clear" Enter
Sleep 200ms
Show

Output ../commands/img/hug-sl-staged.png
Type "hug sl  # State 3: Staged changes only" Enter
Sleep 1s
Screenshot ../commands/img/hug-sl-staged.png

# STATE 4: Both staged and unstaged changes
Hide
Type "clear" Enter
Sleep 200ms
Type "echo 'More unstaged content' >> README.md" Enter
Sleep 200ms
Type "clear" Enter
Sleep 200ms
Show

Output ../commands/img/hug-sl-mixed.png
Type "hug sl  # State 4: Staged AND unstaged changes" Enter
Sleep 1s
Screenshot ../commands/img/hug-sl-mixed.png

# Cleanup
Hide
Type "hug w zap-all -f" Enter
Sleep 200ms
