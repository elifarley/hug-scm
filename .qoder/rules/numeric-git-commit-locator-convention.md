---
trigger: always_on
---
Wherever a commit hash is accepted in Hug commands, a numeric argument N in range 1..999 should be interpreted as a commit count (the last N commits) or as a pointer to commit `HEAD~N` (for N=0 or absent, it's equivalent to `HEAD`); values 1000 and above are treated as short commit hashes. This shorthand convention applies across commands like git-h-squash and should be consistently adopted where appropriate.

Reference commands using this convention:
- git-sh: the absence of a commit hash means `HEAD`.
- git-h-squash: a numeric value 1..999 means the last N commits.
   - Small exception: when the arg is absent for this command, it means the user wants to squash the last 2 commits (usually the absence means `HEAD`).
- git-shc: the N shorthand means "cumulative stats for last N commits"
- git-shcp: the N shorthand means "cumulative diff + stats for last N commits"