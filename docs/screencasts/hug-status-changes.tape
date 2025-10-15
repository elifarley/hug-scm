Output hug-status-changes.gif

Require echo
Require hug

Set Shell "fish"
Set FontSize 24
Set Width 940
Set Height 500
Set Margin 0
Set Theme "Afterglow"

Hide
Type '#PS1="> "' Enter
Type 'cd /tmp/demo' Enter
Type "clear" Enter
# Assume a clean git repo with no changes
Type 'echo "initial content" > example.txt' Enter
Sleep 100 ms
Show

Set TypingSpeed 40ms
Type "hug s # Initial status: no changes" Sleep 100ms Enter
Sleep 2s

Type "echo 'first change' >> example.txt" Sleep 100ms Enter
Type "hug a example.txt # Stage the file" Sleep 100ms Enter
Sleep 200ms
Type "hug s # Now shows 1 staged change" Sleep 100ms Enter
Sleep 100ms Type "# Green 'S1': 1 (S)taged file" Sleep 100ms Enter
Sleep 2s

Type "echo 'second unstaged change' >> example.txt" Sleep 100ms Enter
Sleep 200ms
Type "hug s # Now shows both staged and unstaged on the same file" Sleep 100ms Enter
Sleep 100ms Type "# 'S1 U1': 1 staged, 1 unstaged change in example.txt" Sleep 100ms Enter
Sleep 2s

Type "hug sl # List uncommitted changes (no untracked files shown)" Sleep 100ms Enter
Sleep 100ms Type "# Shows modified files with status" Sleep 100ms Enter
Sleep 2s

Type "hug ss # Show diff for staged changes" Sleep 100ms Enter
Sleep 100ms Type "# Shows the diff of what was staged (first change)" Sleep 100ms Enter
Sleep 3s

Type "hug su # Show diff for unstaged changes" Sleep 100ms Enter
Sleep 100ms Type "# Shows the diff of unstaged changes (second change)" Sleep 100ms Enter
Sleep 3s

Type "hug sw # Show diff for working directory changes (staged + unstaged)" Sleep 100ms Enter
Sleep 100ms Type "# Shows the full diff from HEAD (both changes combined)" Sleep 100ms Enter
Sleep 3s

Sleep 10s
