# VHS tape file for hug commit workflow
# Shows basic commit and commit with add

Output ../commands/img/hug-commit-demo.gif

Require echo
Require hug

Set Shell "fish"
Set FontSize 13
Set Width 1020
Set Height 650
Set Margin 0
Set Padding 10
Set Theme "Afterglow"

# Setup: Start in demo-repo
Hide
Type "cd /tmp/demo-repo" Enter
Sleep 500ms
Type "hug w zap-all -f" Enter
Sleep 500ms
Type "clear" Enter
Sleep 200ms
Show

# Make a change and show status
Set TypingSpeed 40ms
Type "echo 'New feature' >> README.md" Enter
Sleep 300ms
Type@0s "" Enter
Type "hug sl  # Check status - shows unstaged change" Enter
Sleep 2s

# Stage and commit
Type@0s "" Enter
Type "hug a README.md  # (A)dd - stage the change" Enter
Sleep 500ms
Type@0s "" Enter
Type "hug sl  # Now staged" Enter
Sleep 1.5s

Type@0s "" Enter
Type "hug c -m 'docs: update README'  # (C)ommit" Enter
Sleep 1s

Type@0s "" Enter
Type "hug sl  # Clean - change is committed" Enter
Sleep 2s

# Show the shortcut: commit with add
Type@0s "" Enter
Type "echo 'Another change' >> README.md" Enter
Sleep 300ms
Type@0s "" Enter
Type "hug ca -m 'docs: add more info'  # (C)ommit (A)dd - stage and commit" Enter
Sleep 1s

Type@0s "" Enter
Type "hug l -2  # Show last 2 commits" Enter
Sleep 2.5s

# Cleanup
Hide
Type "hug h back 2" Enter
Sleep 300ms
Type "hug w zap-all -f" Enter
Sleep 300ms
