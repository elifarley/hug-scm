Set Height 200
Source setup.tape

Hide
# Create a commit to undo
Type "echo '// Wrong change' >> src/app.js" Enter
Sleep 200ms
Type "hug aa" Enter
Sleep 200ms
Type "hug c -m 'feat: Wrong implementation'" Enter
Sleep 200ms
Type "clear" Enter
Sleep 200ms
Show

Type "hug l -3" Enter
Sleep 500ms
Type "" Enter
Type "hug h back" Enter
Sleep 500ms
Type "" Enter
Type "hug sl" Enter
Sleep 500ms

Screenshot ../../img/practical-workflows/head-back.png
Sleep 10ms
