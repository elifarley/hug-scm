# File Inspection (f*)
File inspection commands in Hug help you analyze the history and authorship of specific files. Prefixed with `f` for "file," they provide tools for blame (who
changed what), contributor lists, author commit counts, and finding when a file was first added. These are especially useful for understanding code ownership
and evolution over time.
These are implemented as Git aliases in `.gitconfig`, wrapping Git's `blame`, `log`, and related commands with optimizations like `--follow` for handling
renames.

## Blame Commands
Blame shows which author last modified each line of a file, helping attribute changes.
- `hug fblame <file>`
    - **Description**: Detailed blame showing author, date, and line content for each line in the file. Ignores whitespace changes and detects moved/copied code
      across files (up to 3 levels).
    - **Usage**:
      ```
      hug fblame src/app.js    # Blame for app.js
      ```
    - **Safety**: Read-only; no repo changes.
    - **Git Equivalent**: `git blame -w -C -C -C <file>`
- `hug fb <file>`
    - **Description**: Short blame output with just author and line number (porcelain format for scripting).
    - **Usage**:
      ```
      hug fb README.md         # Short blame for README.md
      ```
    - **Safety**: Read-only.
    - **Git Equivalent**: `git blame -w -C -C -C --line-porcelain <file>`

## Contributor Analysis
- `hug fcon <file>`
    - **Description**: List all unique contributors (authors with email) to a file, following renames.
    - **Usage**:
      ```
      hug fcon docs/index.md   # Contributors to index.md
      ```
    - **Safety**: Read-only.
    - **Git Equivalent**: `git log --follow --pretty=format:'%an <%ae>' -- <file> | sort -u`
- `hug fa <file>`
    - **Description**: Count commits per author for a file (sorted by count descending), following renames.
    - **Usage**:
      ```
      hug fa lib/utils.js      # Author commit counts for utils.js
      ```
    - **Safety**: Read-only.
    - **Git Equivalent**: `git log --follow --format='%an' -- <file> | sort | uniq -c | sort -rn`

## File Origin
- `hug fborn <file>`
    - **Description**: Show the commit where the file was first added (born), including the full commit details and message. Handles renames with a 40%
      similarity threshold.
    - **Usage**:
      ```
      hug fborn package.json   # When package.json was added
      ```
    - **Safety**: Read-only.
    - **Git Equivalent**: `git log --pretty=logbody --follow --diff-filter=A --find-renames=40% -- <file>`

## Tips
- Combine with [Logging](/commands/logging#file-inspection) for broader file history: e.g., use `hug llf <file> -1` for the latest commit, then `hug fblame <file>` to see line authors.
- For detecting code movement across files, `fblame` and `fb` use advanced `-C -C -C` options - great for refactors.
- Pipe outputs to tools: `hug fa <file> | head -5` for top 5 contributors.
- Always use `--follow` implicitly for rename-aware inspection.

Pair with [Status & Staging](/commands/status-staging) to inspect current file changes, or [Logging](/commands/logging) for commit-level details.
