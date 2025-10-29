# VHS tape file for hug-l command
# Shows basic log with graph visualization

Output ../commands/img/hug-l.png

Require echo
Require hug

Set Shell "fish"
Set FontSize 13
Set Width 1020
Set Height 450
Set Margin 0
Set Padding 10
Set Theme "Afterglow"

# Setup: Start in demo-repo
Hide
Type "cd /tmp/demo-repo" Enter
Sleep 500ms
Type "clear" Enter
Sleep 200ms
Show

# Run hug l to show log with graph
Set TypingSpeed 40ms
Type "hug l  # (L)og - one-line history with graph" Enter
Sleep 2s

# Capture screenshot
Screenshot ../commands/img/hug-l.png

# Cleanup
Hide
