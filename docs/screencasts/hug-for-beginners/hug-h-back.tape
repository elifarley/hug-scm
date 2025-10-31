Set Height 200
Source setup.tape

Hide
# Create a commit to undo
Type "echo 'Wrong commit' > wrong.txt" Enter
Sleep 200ms
Type "hug aa" Enter
Sleep 200ms
Type "hug c -m 'Wrong commit'" Enter
Sleep 200ms
Type "clear" Enter
Sleep 200ms
Show

Type "hug l -n 3" Enter
Sleep 500ms
Type "" Enter
Type "hug h back" Enter
Sleep 500ms
Type "" Enter
Type "hug sl" Enter
Sleep 500ms

Screenshot ../../img/hug-for-beginners/hug-h-back.png
Sleep 10ms
