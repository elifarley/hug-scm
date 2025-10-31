Set Height 250
Source setup.tape

Hide
# Create commits on wrong branch
Type "echo '// Oops commit 1' > oops1.js" Enter
Sleep 200ms
Type "hug aa" Enter
Sleep 200ms
Type "hug c -m 'feat: Feature part 1'" Enter
Sleep 200ms
Type "echo '// Oops commit 2' > oops2.js" Enter
Sleep 200ms
Type "hug aa" Enter
Sleep 200ms
Type "hug c -m 'feat: Feature part 2'" Enter
Sleep 200ms
Type "clear" Enter
Sleep 200ms
Show

Type "hug l -4" Enter
Sleep 500ms
Type "" Enter
Type "hug cmv 2 feature/correct-branch" Enter
Sleep 800ms
Type "" Enter
Type "hug bl" Enter
Sleep 500ms

Screenshot ../../img/practical-workflows/commit-move.png
Sleep 10ms
