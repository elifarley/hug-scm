Output ../commands/img/hug-lol.gif

Require echo
Require hug

Set Shell "fish"
Set FontSize 12
Set Width 1024
Set Height 500
Set Margin 0
Set Theme "Afterglow"

Hide
Type '#PS1="> "' Enter
Type 'cd /tmp/demo-repo && hug b feature/search' Enter
Type "clear" Enter
Sleep 100 ms
Set TypingSpeed 0ms
Type "hug lol # 'lol' is for (L)og (O)utgoing (L)ong" Enter
Sleep 500ms
Show
Sleep 100ms
