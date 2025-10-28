# VHS tape file for hug HEAD operations
# Shows h back, h undo, and h rewind

Output ../commands/img/hug-head-demo.gif

Require echo
Require hug

Set Shell "bash"
Set FontSize 13
Set Width 1020
Set Height 750
Set Margin 0
Set Padding 10
Set Theme "Afterglow"

# Setup: Start in demo-repo, make some commits
Hide
Type "cd /tmp/demo-repo" Enter
Sleep 500ms
Type "hug w zap-all -f" Enter
Sleep 500ms

# Create a few test commits
Type "echo 'v1' > test.txt && hug aa && hug c -m 'v1'" Enter
Sleep 500ms
Type "echo 'v2' > test.txt && hug aa && hug c -m 'v2'" Enter
Sleep 500ms
Type "echo 'v3' > test.txt && hug aa && hug c -m 'v3'" Enter
Sleep 500ms
Type "clear" Enter
Sleep 200ms
Show

Set TypingSpeed 40ms

# Show current log
Type "hug l -5  # Show last 5 commits" Enter
Sleep 2s

# Demonstrate h back (move HEAD back, keep changes)
Type@0s "" Enter
Type "hug h back  # (H)ead (BACK) - move back 1 commit" Enter
Sleep 1s
Type "hug l -5  # HEAD moved back" Enter
Sleep 2s
Type "hug sl  # Changes preserved as uncommitted" Enter
Sleep 2s

# Go back forward by recommitting
Type@0s "" Enter
Type "hug c -m 'v3 again'" Enter
Sleep 1s

# Demonstrate h undo (undo last commit, keep changes staged)
Type@0s "" Enter
Type "hug h undo  # (H)ead (UNDO) - undo commit, keep staged" Enter
Sleep 1s
Type "hug sl  # Changes now staged" Enter
Sleep 2s

# Recommit
Type@0s "" Enter
Type "hug c -m 'v3 final'" Enter
Sleep 1s

# Demonstrate h rewind (reset to commit, discard changes)
Type@0s "" Enter
Type "hug l -5  # Current state" Enter
Sleep 2s

Type@0s "" Enter
Type "hug h rewind HEAD~1  # (H)ead (REWIND) - reset and discard" Enter
Sleep 1s
Type "hug l -5  # Moved back" Enter
Sleep 1.5s
Type "hug sl  # Changes discarded" Enter
Sleep 2s

# Cleanup
Hide
Type "hug h back 2" Enter
Sleep 300ms
Type "hug w zap-all -f" Enter
Sleep 300ms
