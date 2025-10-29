Require echo
Require hug

Set Width 1020
#Set Height 170
Set FontSize 13
Set Shell "fish"
Set Margin 0
Set Padding 3
Set Theme "Afterglow"
Set TypingSpeed 0ms

# Setup: Start in demo-repo
Hide
Type "function fish_prompt ; printf '> '; end; cd /tmp/demo-repo && hug b main && clear" Enter
Sleep 400ms
#Wait@800ms />$/
Show
