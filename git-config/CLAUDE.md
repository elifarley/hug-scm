- Hug commands are defined as `bin/git-<COMMAND>` scripts or as aliases inside `.gitconfig`;

- Any script named `bin/git-<COMMAND>` can be run by executing `hug <COMMAND>` (as hug calls `git`, and git calls the script via its auto-discovery mechanism).

- When trying to see the help for a `git-COMMAND` script (that is, the output of `show_help` function), use `hug help <COMMAND>` instead of `--help`;
