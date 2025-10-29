Set Height 80
Source setup.tape

# VHS tape file for hug-sl showing 4 different states
# Outputs a series of PNGs showing: clean, unstaged, staged, and mixed states
#
# This generates 4 separate screenshots:
# - hug-sl-clean.png: Clean working directory
# - hug-sl-unstaged.png: Unstaged changes only  
# - hug-sl-staged.png: Staged changes only
# - hug-sl-mixed.png: Both staged and unstaged changes

# Clean up any existing state
Hide
Type "hug w zap-all --force && hug b main && clear" Enter
Sleep 300ms
Show

# STATE 1: Clean working directory
Type "hug sl  # Clean working directory" Enter
Sleep 200ms
#Wait@800ms />$/
Screenshot ../commands/img/hug-sl-clean.png
Sleep 20ms

# STATE 2: Unstaged changes only
Hide
Type "clear" Enter
#Wait@800ms />$/
Sleep 100ms
Show
Type "echo 'New content' >> README.md && hug sl  # Unstaged changes only" Enter
Sleep 100ms
#Wait@800ms />$/
Screenshot ../commands/img/hug-sl-unstaged.png
Sleep 10ms

# STATE 3: Staged changes only
Hide
Type "clear" Enter
Sleep 100ms
#Wait@800ms />$/
Show
Type "hug a README.md && hug sl  # Staged changes only" Enter
Sleep 300ms
#Wait@800ms />$/
Screenshot ../commands/img/hug-sl-staged.png
Sleep 10ms

# STATE 4: Both staged and unstaged changes
Hide
Type "clear" Enter
Sleep 50ms
Show
Type "echo 'More unstaged content' >> README.md && hug sl  # Staged AND unstaged changes" Enter
Sleep 100ms
Screenshot ../commands/img/hug-sl-mixed.png
Sleep 10ms

# Cleanup
Hide
Type "hug w zap-all --force" Enter
Sleep 200ms
