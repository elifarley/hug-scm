Set Height 160
Source setup.tape

Hide
Type "echo 'test change' >> test.txt && clear" Enter
Sleep 300ms
Show

Type "hug sl # Show status with changes" Enter
Sleep 100ms
Type "hug w discard test.txt # (W)orking dir (DISCARD) - remove unstaged" Enter
Sleep 100ms

Screenshot ../commands/img/hug-w-discard.png
Sleep 10ms
