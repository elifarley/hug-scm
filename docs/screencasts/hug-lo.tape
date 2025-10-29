Source setup.tape

# VHS tape file for hug-lo command
# Shows a preview of local commits not yet on upstream branch

Hide
Type "hug b feature/search && clear" Enter
Sleep 300ms
Show

Type "hug lo  # (L)og (O)utgoing - preview commits before push" Enter
Sleep 500ms

Screenshot ../commands/img/hug-lo.png
Sleep 10ms
