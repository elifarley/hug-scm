Output hug-status-changes.gif

Require echo
Require hug

Set Shell "fish"
Set FontSize 24
Set Width 940
Set Height 1000
Set Margin 0
Set Theme "Afterglow"

Hide
Type 'xxx_PS1="> "' Enter
Type 'cd /tmp/demo && hug zap-all -f' Enter
Type "clear" Enter
Show

Set TypingSpeed 20ms
Type@60ms "hug sl # sl is for (S)tatus + (L)ist uncommitted" Sleep 100ms Enter
Sleep 3s
Type@0s '#' Enter
Type 'echo "Will be STAGED" > example.txt' Enter
Type@60ms "hug a example.txt # (A)dd file to staging area" Sleep 100ms Enter
Sleep 100 ms
Type@60ms "hug sl # Now shows 1 staged change" Sleep 100ms Enter
Sleep 3s

Type@0s '#' Enter
Type "echo 'This will stay UNstaged' >> example.txt" Sleep 100ms Enter
Sleep 200ms
Type@60ms "hug sl # Now shows both staged and unstaged on the same file" Sleep 100ms Enter
Sleep 3s

Type@0s '#' Enter
Type@60ms "hug ss # (S)tatus + (S)taged changes" Sleep 100ms Enter
Sleep 100ms Type "# Shows the diff of what was staged (first change)" Sleep 100ms Enter
Sleep 3s

Type@0s '#' Enter
Type@60ms "hug su # (S)tatus + (U)nstaged changes" Sleep 100ms Enter
Sleep 100ms Type "# Shows the diff of unstaged changes (second change)" Sleep 100ms Enter
Sleep 3s

Type@0s '#' Enter
Type@60ms "hug sw # (S)tatus + (W)orking directory changes (staged + unstaged)" Sleep 100ms Enter
Sleep 100ms Type "# Shows the full diff from HEAD (both changes combined)" Sleep 100ms Enter
Sleep 10s

