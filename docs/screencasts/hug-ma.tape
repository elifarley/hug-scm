Set Height 200
Source setup.tape

# Create a merge conflict scenario
Hide
Type "echo 'conflict content' > test-file.txt" Enter
Sleep 200ms
Type "hug c 'Create conflict file'" Enter
Sleep 500ms
Type "hug bc temp-conflict" Enter
Sleep 200ms
Type "echo 'other content' > test-file.txt" Enter
Sleep 200ms
Type "hug c 'Modify file differently'" Enter
Sleep 200ms
Type "hug b main" Enter
Sleep 200ms
Type "echo 'main content' > test-file.txt" Enter
Sleep 200ms
Type "hug c 'Modify on main'" Enter
Sleep 200ms
# Try to merge - this will fail with conflict
Type "git merge temp-conflict" Enter
Sleep 500ms
Type "clear" Enter
Sleep 200ms
Show

Type "hug ma" Enter
Sleep 500ms

Screenshot ../commands/img/hug-ma.png
Sleep 10ms
