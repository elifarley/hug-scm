Set Height 200
Source setup.tape

Hide
# Create a commit to cherry-pick
Type "hug bc feature/fix-bug" Enter
Sleep 200ms
Type "echo '// Bug fix' >> src/utils.js" Enter
Sleep 200ms
Type "hug aa" Enter
Sleep 200ms
Type "hug c -m 'fix: Critical bug fix'" Enter
Sleep 200ms
Type "hug b main" Enter
Sleep 200ms
Type "clear" Enter
Sleep 200ms
Show

Type "hug l feature/fix-bug -1" Enter
Sleep 500ms
Type "" Enter
Type "hug ccp feature/fix-bug" Enter
Sleep 500ms
Type "" Enter
Type "hug l -2" Enter
Sleep 500ms

Screenshot ../../img/practical-workflows/cherry-pick.png
Sleep 10ms
