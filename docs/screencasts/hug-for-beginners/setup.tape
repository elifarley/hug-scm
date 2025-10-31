Require echo
Require hug

Set Width 1020
Set FontSize 13
Set Shell "fish"
Set Margin 0
Set Padding 3
Set Theme "Afterglow"
Set TypingSpeed 0ms

# Setup: Start in beginner-repo (clean, minimal environment)
Hide
Type "function fish_prompt ; printf '> '; end; cd /tmp/beginner-repo && clear" Enter
Sleep 400ms
Show
