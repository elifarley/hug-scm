# VHS tape file for hug working directory cleanup commands
# Shows w discard, w wipe, w purge, and w zap

Output ../commands/img/hug-working-dir-demo.gif

Require echo
Require hug

Set Shell "fish"
Set FontSize 13
Set Width 1020
Set Height 800
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

Set TypingSpeed 40ms

# Demonstrate w discard (unstaged changes only)
Type "echo 'Unstaged change' >> README.md" Enter
Sleep 300ms
Type "hug sl  # Shows unstaged change" Enter
Sleep 1.5s

Type@0s "" Enter
Type "hug w discard README.md  # (W)orking dir (DISCARD) - remove unstaged" Enter
Sleep 1s
Type "hug sl  # Clean again" Enter
Sleep 1.5s

# Demonstrate w wipe (staged + unstaged)
Type@0s "" Enter
Type "echo 'Change 1' >> README.md" Enter
Sleep 300ms
Type "hug a README.md  # Stage it" Enter
Sleep 300ms
Type "echo 'Change 2' >> README.md" Enter
Sleep 300ms
Type "hug sl  # Both staged and unstaged" Enter
Sleep 2s

Type@0s "" Enter
Type "hug w wipe README.md  # (W)orking dir (WIPE) - remove both" Enter
Sleep 1s
Type "hug sl  # All clean" Enter
Sleep 1.5s

# Demonstrate w purge (untracked files)
Type@0s "" Enter
Type "echo 'temp file' > temp.txt" Enter
Sleep 300ms
Type "hug sla  # Shows untracked file" Enter
Sleep 1.5s

Type@0s "" Enter
Type "hug w purge  # (W)orking dir (PURGE) - remove untracked" Enter
Sleep 1s
Type "hug sl  # Untracked file removed" Enter
Sleep 1.5s

# Demonstrate w zap (everything: discard + purge)
Type@0s "" Enter
Type "echo 'Change' >> README.md && echo 'temp' > temp2.txt" Enter
Sleep 300ms
Type "hug sla  # Both tracked change and untracked file" Enter
Sleep 2s

Type@0s "" Enter
Type "hug w zap  # (W)orking dir (ZAP) - clean everything" Enter
Sleep 1s
Type "hug sl  # Completely clean" Enter
Sleep 2s

# Cleanup
Hide
Type "hug w zap-all -f" Enter
Sleep 300ms
