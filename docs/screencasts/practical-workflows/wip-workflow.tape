Set Height 250
Source setup.tape

Hide
# Create some uncommitted changes
Type "echo '// Work in progress' > src/feature.js" Enter
Sleep 200ms
Type "echo 'Test data' > test.txt" Enter
Sleep 200ms
Type "clear" Enter
Sleep 200ms
Show

Type "hug sl" Enter
Sleep 500ms
Type "" Enter
Type "hug wip 'Pausing to fix urgent bug'" Enter
Sleep 800ms
Type "" Enter
Type "hug sl" Enter
Sleep 500ms

Screenshot ../../img/practical-workflows/wip-workflow.png
Sleep 10ms
