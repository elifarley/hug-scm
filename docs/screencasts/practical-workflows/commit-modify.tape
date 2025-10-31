Set Height 200
Source setup.tape

Hide
# Create a commit that we'll modify
Type "echo '// New function' >> src/app.js" Enter
Sleep 200ms
Type "hug aa" Enter
Sleep 200ms
Type "hug c -m 'feat: Add feature'" Enter
Sleep 200ms
# Now add forgotten file
Type "echo '// Tests' > src/app.test.js" Enter
Sleep 200ms
Type "clear" Enter
Sleep 200ms
Show

Type "hug sl" Enter
Sleep 500ms
Type "" Enter
Type "hug a src/app.test.js" Enter
Sleep 500ms
Type "hug cm -m 'feat: Add feature with tests'" Enter
Sleep 500ms
Type "" Enter
Type "hug l -2" Enter
Sleep 500ms

Screenshot ../../img/practical-workflows/commit-modify.png
Sleep 10ms
