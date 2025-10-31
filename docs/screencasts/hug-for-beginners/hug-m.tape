Set Height 250
Source setup.tape

Hide
# Create a branch with a commit
Type "hug bc feature-branch" Enter
Sleep 200ms
Type "echo 'Feature code' > feature.txt" Enter
Sleep 200ms
Type "hug aa" Enter
Sleep 200ms
Type "hug c -m 'Add feature'" Enter
Sleep 200ms
Type "hug b main" Enter
Sleep 200ms
Type "clear" Enter
Sleep 200ms
Show

Type "hug m feature-branch" Enter
Sleep 500ms
Type "" Enter
Type "hug c -m 'Merge feature branch'" Enter
Sleep 500ms

Screenshot ../../img/hug-for-beginners/hug-m.png
Sleep 10ms
