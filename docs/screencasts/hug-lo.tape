# VHS tape file for hug-lo command
# Shows a preview of local commits not yet on upstream branch

Output ../commands/img/hug-lo.png

Require echo
Require hug

Set Shell "bash"
Set FontSize 13
Set Width 1020
Set Height 400
Set Margin 0
Set Padding 10
Set Theme "Afterglow"

# Setup: Start in demo-repo with a feature branch
Hide
Type "cd /tmp/demo-repo" Enter
Sleep 500ms

# Switch to or create a feature branch with commits
Type "hug b feature/demo 2>/dev/null || hug bc feature/demo" Enter
Sleep 500ms

# Make some local commits that haven't been pushed
Type "echo 'Local change 1' >> demo-file.txt" Enter
Sleep 200ms
Type "hug aa" Enter
Sleep 200ms
Type "hug c -m 'feat: add demo feature part 1'" Enter
Sleep 500ms

Type "echo 'Local change 2' >> demo-file.txt" Enter
Sleep 200ms
Type "hug aa" Enter
Sleep 200ms
Type "hug c -m 'feat: add demo feature part 2'" Enter
Sleep 500ms

Type "clear" Enter
Sleep 200ms
Show

# Run hug lo to show outgoing commits (quiet mode)
Set TypingSpeed 40ms
Type "hug lo  # (L)og (O)utgoing - preview commits before push" Enter
Sleep 2s

# Capture the screenshot
Screenshot ../commands/img/hug-lo.png

# Cleanup
Hide
Type "hug b main" Enter
Sleep 300ms
Type "hug w zap-all -f" Enter
Sleep 300ms
