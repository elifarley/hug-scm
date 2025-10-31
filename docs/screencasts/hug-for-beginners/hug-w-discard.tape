Set Height 200
Source setup.tape

Hide
# Modify an existing file
Type "echo 'Wrong changes' >> README.md" Enter
Sleep 200ms
Type "clear" Enter
Sleep 200ms
Show

Type "hug sl" Enter
Sleep 500ms
Type "" Enter
Type "hug w discard README.md" Enter
Sleep 500ms
Type "" Enter
Type "hug sl" Enter
Sleep 500ms

Screenshot ../../img/hug-for-beginners/hug-w-discard.png
Sleep 10ms
