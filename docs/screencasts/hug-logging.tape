Source setup.tape

# VHS tape file for hug-l command
# Shows basic log with graph visualization

# Run hug l to show log with graph
Type "hug l -5 # (L)og - one-line history with graph (last 5)" Enter
Sleep 100ms

# Capture screenshot
Screenshot ../commands/img/hug-l.png
Sleep 50ms

Type "hug ll -5 # (L)og - one-line history with more info (last 5)" Enter
Sleep 100ms

# Capture screenshot
Screenshot ../commands/img/hug-ll.png
Sleep 50ms
